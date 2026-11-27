[< All Decisions](../DECISIONS.md)

# Statement Tokens: `Stmt.new()` Is the One Way to Make a `Stmt` — Design Rationale

**Gap:** §4.4.10 gave one way to make a `Stmt`: `Stmt.mock(id)`, a pure function with no row that takes an `Int` key. It said that "A `Stmt` that the mock made with `Stmt.mock` can never succeed at the forward, because no outer handler made it." That held for the std SQLite driver, which made its tokens through a constructor inside std. The driver is now the package `blinklang/sqlite`, and a package cannot use that constructor. A package driver can only write `Stmt.mock(k)`, so a mock that writes the same key makes the same token. `Stmt` also had no `Eq`, no `Hash` and no getter, so a handler that holds more than one token cannot find which statement a clause got:

```blink
// a mock that omits `step` forwards it to the driver of the package
fn no_step_db() -> Handler[DB ! DB] {
    handler DB {
        fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(Stmt.mock(1)) }
        // ...
    }
}

// in the driver: its first statement is Stmt.mock(1) too, so the owner check passes.
// And with no Eq and no getter, how does `step(s)` find the real statement for `s`?
```

**Questions:** Q0, does the spec need to say more? Q1, how does a package driver tell its tokens from a mock's token with the same key? Q2, with no getter and no `Eq`, how does a driver or a mock find which statement a clause got? Q3, is the owner identity in the `Stmt` value, or in the record that the driver keeps?

**Already decided (not on the ballot):** the driver is the package `blinklang/sqlite` (see [Database Driver Package rationale](db-driver-package.md)); each `Stmt` method is a `DB` operation that the handler in scope runs, with the three Errs (owner, closed, finalized), an idempotent `finalize`, the exit sweep and the forward of an omitted operation (see [Stmt Operations rationale](stmt-db-effect-ops.md)); opaque types and type-scoped fns; pre-1.0 changes ship at once.

**Names.** The options used three names for the constructor: `Stmt.fresh()` (option F, beside `Stmt.mock`), `Stmt.new()` (option N) and `StmtIssuer.new()` (option I). The quotes keep the name that each panelist wrote.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran three rounds. Phase C split 3-3 on Q2 and Q3a, so Phase D ran one focused round and a silent re-vote. Q2 stayed 3-3, and the user broke the tie.

#### Phase A — Independent proposals

All six said yes to Q0: the gap is real once the driver is a package. Three families of proposal came out of Phase A:

- **F:** keep `Stmt.mock(k)` and add a fresh constructor; `Stmt` gets the traits of `Child` (web, devops, aiml).
- **N:** one fresh constructor that replaces `Stmt.mock` (minimalism).
- **I:** an issuer value that makes tokens and reads the key back only for its own tokens (systems, PLT).

Every proposer gave the fresh constructor no row.


- **Systems:**

> Systems pick: std.db adds one opaque owner type, `StmtOwner`. It mints tagged tokens and reads the key back only for its own tokens. The owner is part of the Stmt value. Drop `Stmt.mock`.
>
> Q0: Yes, the spec must say more. A std-internal constructor fixes the std driver only. The project goal moves the driver to a package, and a package cannot declare `@runtime`. Today a package can only write `Stmt.mock(k)`, which a mock can forge, and it has no way to find its statement. So the gap is real now.
>
> PROPOSAL: `StmtOwner` in std.db
> - `pub opaque type StmtOwner`. `StmtOwner.new() -> StmtOwner` gives a fresh identity on each call. It has no row; it is an allocation, like making a List. No Eq, Hash or Debug.
> - `owner.stmt(key: Int) -> Stmt` makes a token tagged with `owner`.
> - `owner.key_of(s: Stmt) -> Option[Int]` gives `Some(key)` only when `owner` made `s`. Otherwise `None`.
>
> That answers the questions:
> - Q1: A mock makes its own owner. The driver's `key_of` gives `None` for that token, so the driver returns the owner Err. Same key, different owner.
> - Q2: `key_of` is the getter, and only the owner can use it. The driver uses the key to find the statement in its own table.
> - Q3: Each `connect` makes a new owner. Two connections of one driver reject each other's tokens.
>
> Driver side:
> ```blink
> import std.db.{DB, Stmt, StmtOwner}
>
> fn prepare_on(c: Conn, sql: Template[DB]) -> Result[Stmt, DBError] {
>     let raw = prepare_and_bind(c.handle, sql)?
>     let key = c.next_key()          // never reused
>     c.stmts.insert(key, raw)
>     Ok(c.owner.stmt(key))
> }
>
> fn step_on(c: Conn, s: Stmt) -> Result[Int, DBError] {
>     let key = match c.owner.key_of(s) {
>         Some(k) => k
>         None => return Err(DBError.ExecError("statement belongs to another connection"))
>     }
>     if c.closed { return Err(DBError.ConnectionError("connection is closed")) }
>     match c.stmts.get(key) {
>         Some(raw) => Ok(sqlite_step(raw))
>         None => Err(DBError.ExecError("statement is finalized"))
>     }
> }
> ```
>
> Mock side:
> ```blink
> fn no_step_db() -> Handler[DB ! DB] {
>     let me = StmtOwner.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(me.stmt(1)) }
>         fn column_int(s: Stmt, idx: Int) -> Int {
>             match me.key_of(s) { Some(1) => 7  _ => 0 }
>         }
>         // ... step omitted: forwards
>     }
> }
> // under a driver: s.step() prints "exec_error: statement belongs to another connection"
> ```
>
> What it compiles to: the token is `{ owner ptr, key i64 }`, which is today's struct minus `impl`. `key_of` is one pointer compare and one load. The driver lookup is one map or list index next to a `sqlite3_step` call, so the cost is lost in the noise. No vtable, no generic `Stmt[T]`, and the DB op signatures do not change.
>
> Tradeoffs:
> - We lose the `impl` pointer fast path. That is the right trade: a package cannot store a raw C pointer in a std token without an unchecked cast, and the cast is the real risk.
> - Reused keys are a hazard. If a driver reuses a key after `finalize`, a stale token reaches a new statement. That is the classic handle ABA bug. The spec must say that the finalized Err holds only when one owner never reuses a key. Drivers use a counter that only goes up, or slot plus generation.
> - The "pure" fresh identity is visible only through `key_of`. I accept that. If the PLT seat objects, give `new` a row. Each driver's `connect` has an FFI row already, so a row costs nothing there.
> - Why drop `Stmt.mock`: an owner-less token is a second way to do the same thing, and it cannot answer Q2 for a mock that holds two Stmts. `StmtOwner.new().stmt(k)` covers that case. If the panel keeps `Stmt.mock` as shorthand, `key_of` must give `None` for it from every owner.
>
> Rejected: telling tokens apart by key range or by a magic key. A mock forges it in one line.
>
> Cross-language: Erlang `make_ref()` for identity, and Rust slotmap for generational keys. Go `database/sql` gives each driver its own `driver.Stmt` through an interface. We get the same isolation without dynamic dispatch.

- **Web/Scripting:**

> Pick: add `Stmt.fresh()` (a new unique token, never equal to any `Stmt.mock(n)`), give `Stmt` Eq + Hash + Debug like `Child`, and let each driver keep its own `Map[Stmt, RawStmt]`. The map lookup IS the owner check.
>
> Q0. Yes, the spec must say more. The driver is a package as of today, so "std-internal constructor" no longer covers any real driver. Without an answer, the first package author writes `Stmt.mock(next_id)` and the "can never succeed" line is false on day one.
>
> Proposal (behavior):
> - `Stmt.fresh() -> Stmt` in std.db. No effect row. Each call gives a token that equals only itself. It never equals a `Stmt.mock(n)` or another fresh token. Same idea as allocating a new object: identity, not an effect.
> - `Stmt.mock(n) == Stmt.mock(m)` exactly when `n == m` (the `Child` rule, copied).
> - `Stmt` gets `Eq`, `Hash`, `Debug`. Debug prints `Stmt.mock(3)` or `Stmt.fresh(#17)`. Still no getter for the key.
> - Q2: a handler finds its statement with a map lookup. No special API.
> - Q3: the value carries no owner. Each connection keeps its own map. Two connections of one driver have two maps, so connection A's token is not in B's map, and B gives the owner Err. That is the rule the spec already states.
>
> Driver side:
> ```blink
> pub fn connect(path: Str) -> Result[Connection, DBError] {
>     let raw = sqlite_open(path)?
>     let mut stmts: Map[Stmt, Sqlite3Stmt] = Map.new()
>     let h = handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] {
>             let real = prepare_and_bind(raw, sql)?
>             let s = Stmt.fresh()
>             stmts.insert(s, real)
>             Ok(s)
>         }
>         fn step(s: Stmt) -> Result[Int, DBError] {
>             match stmts.get(s) {
>                 Some(real) => Ok(sqlite_step(real))
>                 None => Err(ExecError("statement belongs to another connection"))
>             }
>         }
>         // ...
>     }
>     Ok(Connection { raw: raw, handler: h })
> }
> ```
>
> Mock side (unchanged from today):
> ```blink
> fn no_step_db() -> Handler[DB ! DB] {
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(Stmt.mock(1)) }
>         // step omitted: forwards
>     }
> }
> ```
> The forward reaches the driver. `stmts.get(Stmt.mock(1))` is None, so the driver answers the owner Err. That holds for every package driver, not by luck.
>
> A mock with several statements now writes `if s == Stmt.mock(2) { ... }` or keeps its own map. Today it cannot tell them apart at all.
>
> Tradeoffs (my seat):
> - A JS dev knows this in one minute: `Symbol()` / Python `object()` as a sentinel, plus a dict. No new concept.
> - Two constructors with clear names: `mock(n)` for scripts and tests you want to predict; `fresh()` for drivers. A driver author cannot get the collision wrong unless they pick `mock` on purpose, and the doc line says not to.
> - Driver keeps a map, so `finalize` = `remove`, and the exit sweep = walk the map. That matches what drivers do in every other language.
> - Cost: `fresh()` with no effect row is the one point PLT may push on (it is not referentially pure). I accept that. Allocation identity is not an effect anywhere else in Blink either, and adding `! Rand` or similar to a driver's prepare would be noise.
> - Rejected: owner identity inside the value (a "connection id" field). It adds a second concept, and drivers still need a map to find the real statement. The map alone does both jobs.
> - Rejected: an opaque generic `Stmt[T]` payload. Too clever; mocks would need to name a type parameter.
>
> Cross-language: Go `database/sql` keeps the driver stmt behind an opaque `*Stmt` tied to its `*DB`; Python DB-API cursors are plain objects compared by identity. Both rely on identity, which is what `fresh()` gives.

- **PLT:**

> PLT pick: replace Stmt.mock(k) with a generative issuer (a sealer/unsealer pair). The owner identity lives in the Stmt value, and only the maker can read the key back.
>
> The core point (Q0, Q1). Stmt.mock(k) is a pure function. Equal inputs give equal values. So when a driver and a mock both call Stmt.mock(1), they get the same token, and no check can tell them apart. "Can never succeed" is then false for every package driver. A std-only constructor hides this hole and does not fix it. The spec must change before the driver leaves std.
>
> Proposal. std.db adds one opaque type:
>
> ```blink
> pub opaque type StmtIssuer
> pub fn StmtIssuer.new() -> StmtIssuer                   // fresh identity, no row (like StringBuilder.new)
> pub fn StmtIssuer.make(self, key: Int) -> Stmt          // the token carries (this issuer, key)
> pub fn StmtIssuer.key_of(self, s: Stmt) -> Option[Int]  // Some(key) only if this issuer made s
> ```
>
> Stmt.mock is removed (pre-1.0, one CHANGELOG line). Code that calls it gets the normal unknown-name error. Stmt gets no Eq, Hash, Debug or getter. key_of is the only way to read a key, and only the maker holds its issuer.
>
> Driver side (package):
>
> ```blink
> fn prepare_clause(c: Connection, sql: Template[DB]) -> Result[Stmt, DBError] {
>     let raw = sqlite3_prepare(c.handle, sql)?
>     let k = c.table.add(raw)          // the driver's own table: key -> real statement
>     Ok(c.issuer.make(k))
> }
>
> fn step_clause(c: Connection, s: Stmt) -> Result[Int, DBError] {
>     match c.issuer.key_of(s) {
>         None => Err(ExecError("statement belongs to another connection"))
>         Some(k) => match c.table.get(k) {
>             None => Err(ExecError("statement is finalized"))
>             Some(raw) => sqlite3_step(raw)
>         }
>     }
> }
> ```
>
> Mock side, with one forward on purpose:
>
> ```blink
> fn two_stmt_db() -> Handler[DB ! DB] {
>     let iss = StmtIssuer.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(iss.make(sql.len())) }
>         fn column_int(s: Stmt, idx: Int) -> Int {
>             match iss.key_of(s) {
>                 Some(k) => k
>                 None => panic("not my statement")
>             }
>         }
>         fn step(s: Stmt) -> Result[Int, DBError] { default.step(s) }
>         // ... the other clauses
>     }
> }
> ```
>
> Under a sqlite connection, `s.step()` forwards. The driver calls `c.issuer.key_of(s)` and gets None, because the mock's issuer made s. Output: `exec_error: statement belongs to another connection`. That holds for every key, so the "can never succeed" line becomes a theorem, not a convention.
>
> Q2: key_of gives the maker its key, so a driver or mock with many statements finds the right one. Q3: the identity is in the value. One issuer per connection, so two connections of one driver tell their tokens apart with no extra record. The driver keeps only its key-to-statement table (state, not identity). The finalized and closed Errs stay as today: they come from that table and from a closed flag.
>
> Runtime: the token stays {owner, key}. Owner becomes the issuer's identity. The std-internal sqlite_stmt_token and sqlite_stmt_of go away. A package needs no @runtime.
>
> Tradeoffs:
> - Sound by construction. The key is not forgeable, and nothing outside the issuer can read it. This is capability discipline, not trust in driver authors.
> - StmtIssuer.new() creates a fresh identity, so it is generative, not referentially transparent. Blink already lets StringBuilder.new and spawn give distinct values. If the panel wants this to be an effect, it can go under a row, but no row is my default.
> - One more type in std.db. That is the minimum. The rejected option is a phantom brand Stmt[s] (Haskell ST): the DB op signatures are fixed, and Blink has no rank-2 types.
> - Child.mock keeps its current model. Child has a built-in handler in std and no package driver. Moving it to the same model is a separate ticket.
>
> Cross-language: this is the Morris 1973 sealer/unsealer pair, as in E and in Racket's struct-type properties. ML gets the same effect from generative abstract types and from ref identity.

- **DevOps/Tooling:**

> DevOps/Tooling Phase A pick: give Stmt the Child surface (Eq, Hash, Debug) plus a second constructor `Stmt.fresh()` that makes a token equal only to its own copies; owner identity stays in each driver's own map.
>
> Q0. Yes, the spec must say more. The std-internal constructor hides the gap, and the package decision already removed it. A package driver today has only `Stmt.mock(k)`, so the "can never succeed" line is false for every package driver.
>
> BEHAVIOR
> - `Stmt.mock(k)`: unchanged. Equal to `Stmt.mock(m)` exactly when k == m.
> - `Stmt.fresh()`: pure fn of std.db, no row, no args. Each call gives a Stmt that equals no other Stmt except its copies. It never equals a `Stmt.mock` value. No getter.
> - `Stmt` implements Eq, Hash, Debug. Debug prints `Stmt.mock(3)` or `Stmt(#17)`. The #n changes from run to run; it is not a format (same rule as a real Child).
> - Owner check = "not in my map". Q3: the owner is NOT in the value. Each connection keeps `Map[Stmt, RealStmt]`. A token from connection A is absent in B's map, so B gives the owner Err. No extra concept.
>
> Driver side (package):
> ```blink
> fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] {
>     let raw = ffi_prepare(conn, sql)?
>     let s = Stmt.fresh()
>     stmts.insert(s, raw)
>     Ok(s)
> }
> fn step(s: Stmt) -> Result[Int, DBError] {
>     match stmts.get(s) {
>         Some(raw) => ffi_step(raw)
>         None => Err(ExecError("statement belongs to another connection"))
>     }
> }
> ```
>
> Forwarding mock:
> ```blink
> handler DB {
>     fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(Stmt.mock(1)) }
>     // step omitted: forwards; driver map lookup of Stmt.mock(1) is None
> }
> ```
> Output: `exec_error: statement belongs to another connection`. Holds for every driver, by construction, not by driver care. Q1 solved: the two key spaces are disjoint. Q2 solved: Eq + Hash make the map work, and a multi-Stmt mock can `match` on `s == a`.
>
> TOOLING TRADEOFFS
> - Debug is the big win for me. Today a mock author who hits the owner Err sees no hint which token failed. I suggest (writer's call) the owner Err text include the Debug text: "statement Stmt.mock(1) belongs to another connection". The author sees "mock" at once and knows to write the missing clause. `assert_eq` on Stmt also gets a readable diff.
> - Parity with Child: one rule to teach, one rule for the LSP hover doc, one golden-test rule ("print only mock tokens").
> - No new diagnostic code. Nothing for the compiler to check. Drivers that forget the map lookup are a driver bug, same as today.
> - Cost: `Stmt.fresh()` is not referentially transparent (two calls give unequal values). The optimizer must treat it as an allocation and never merge two calls. PLT seat should rule whether that needs a row. If the panel wants a row, I accept `! DB.Read`-free alternatives only if a prepare clause can still call it without forwarding. I would reject making it perform DB: a call inside the handler would go to the OUTER handler, which is a trap.
>
> REJECTED
> - Package driver mints `Stmt.mock(counter)`: collides with mocks (Q1), and two connections both start at 1.
> - Owner Int in the value, `Stmt.make(owner, key)` from the C pointer address: address reuse after close makes a stale token match a new connection. Hard to test, worse to debug.
> - Keep it std-internal: blocks the package decision.
>
> Cross-language: JDBC PreparedStatement and Python DB-API cursors use object identity; OCaml `ref ()` is the same "fresh allocation" idea. Go's database/sql keeps the driver statement behind an opaque pointer, also identity. Nobody uses user-chosen integer keys for driver handles.

- **AI/ML:**

> AI/ML pick: copy the Child pattern. Stmt gets Eq, Hash and Debug, plus one new constructor Stmt.fresh() that never equals any other Stmt. Each driver keeps its own Map[Stmt, X].
>
> **Q0. Yes, the spec must say more.** The package move is decided, so today a package cannot write a driver. A std-internal constructor cannot be the answer. Every third-party driver (Postgres, MySQL) hits the same gap.
>
> **Behavior**
> - `Stmt.fresh() -> Stmt` is a pure fn of std.db. It has no row and takes no key. Each call gives a new token. That token never equals another fresh token or any `Stmt.mock(k)`. It has no row for the same reason allocation has none: Eq is the only way to see the difference. PLT should check that reading.
> - `Stmt.mock(n) == Stmt.mock(m)` exactly when `n == m`. These are the same rules as Child.
> - Debug prints `Stmt.mock(3)` for a mock token and `Stmt(fresh)` for a fresh one. Fresh tokens show no number, so golden tests stay stable.
> - Q1: the driver stores only fresh tokens. A forwarded `Stmt.mock(k)` is never in its map, so it gets the owner Err. "Can never succeed" now follows from Eq. It no longer depends on a runtime field.
> - Q2: a lookup is `map.get(s)`. A mock that holds several statements compares with `==`.
> - Q3: the driver keeps the record, one map per connection. The value does not carry the owner. Connection B's map does not hold A's token, so B answers with the owner Err. The same map gives the closed and finalized cases (the entry is removed, or a closed flag is set).
>
> ```blink
> // the package blinklang/sqlite
> fn sqlite_handler(h: Sqlite3) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand)] {
>     let stmts: Map[Stmt, Sqlite3Stmt] = Map.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] {
>             let raw = prepare_and_bind(h, sql)?
>             let s = Stmt.fresh()
>             stmts.insert(s, raw)
>             Ok(s)
>         }
>         fn step(s: Stmt) -> Result[Int, DBError] {
>             match stmts.get(s) {
>                 Some(raw) => sqlite_step(h, raw)
>                 None => Err(DBError.ExecError("statement belongs to another connection"))
>             }
>         }
>         // other clauses look up the token the same way
>     }
> }
>
> // a mock that forwards step on purpose
> fn half_mock() -> Handler[DB ! DB] {
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(Stmt.mock(1)) }
>         fn step(s: Stmt) -> Result[Int, DBError] {
>             if s == Stmt.mock(1) { default.step(s) } else { Ok(101) }
>             // default.step gives: exec_error: statement belongs to another connection
>         }
>         // other clauses omitted
>     }
> }
> ```
>
> **Tradeoffs (AI view)**
> - A single learned pattern. Child already has mock + Eq + Hash + Debug. A model that learns one transfers it to the other. If Stmt is the odd one out (no Eq, mock only), a model will write `s == t` or `Map[Stmt, _]` anyway, from Go, Rust and JDBC priors. Today it then gets E1400 (no Hash) and has no fix to reach for. With this proposal that code is correct.
> - The trap this closes: with no fresh constructor, a model writes a driver that numbers its statements `Stmt.mock(counter)`, or uses the C pointer as the key. That compiles and passes tests. A forwarded `Stmt.mock(1)` then runs the driver's real statement 1. The bug is silent and a wrong answer comes out with no Err, the worst case for repair. A separate fresh constructor makes the right path the short one.
> - The cost is small: one constructor, three derives and two Debug forms. It needs no new language feature, and one map per driver is the normal pattern in every host language.
> - Risk: someone may say "mock" was meant to cover both. Then name the pair by what they do: `Stmt.mock(k)` for keyed tokens, `Stmt.fresh()` for unique ones. Do not rename mock in this ticket.
>
> **Cross-language:** this is Go's `database/sql` driver.Stmt (an identity value the driver owns) and Rust's opaque handles plus a slotmap. In Python DB-API, a cursor is identity-compared, and drivers keep the real handle behind it. None of these ships an owner field in the value. The connection holds that record.
>
> **Rejected:** putting the owner in the value (needs a fresh Owner type, so the same question one level up, and two concepts to learn). Pointer-as-key `Stmt.mock(addr)` (collides, not "never").

- **Minimalism:**

> Minimalism pick: replace Stmt.mock(k) with one constructor Stmt.new() that makes a fresh token; Stmt gets Eq + Hash by identity. No owner field, no getter, no key. Each handler keeps its own table.
>
> PROPOSAL A (my pick): one fresh-token constructor, identity equality.
>
> Behavior:
> - `Stmt.new() -> Stmt` in std.db. No effect row. Each call gives a token that equals only itself. It allocates. It reads no state that code can see.
> - `Stmt` implements Eq and Hash. `a == b` exactly when both came from the same `Stmt.new()` call. No Debug (nothing to print that helps; leave it out until someone needs it).
> - `Stmt.mock` is removed. Pre-1.0: a CHANGELOG line, no shim. Old call sites get the normal unknown-function error.
> - Q0: yes, the spec must change. A std-internal constructor hides the gap. A package cannot write `@runtime`, so the package move breaks the "can never succeed" line on day one.
> - Q1: forgery is gone. Nothing makes a token equal to one the driver made, except a copy of that token. A mock's own tokens never match the driver's table, so the forward gets the owner Err.
> - Q2: Eq + Hash means a `Map[Stmt, T]`. That is the whole lookup story.
> - Q3: the driver keeps the record. Each connection has its own map, so two connections of one driver tell their tokens apart for free. Owner identity is "which map has it", not a field.
>
> Driver side:
> ```blink
> pub type Conn { handle: Sqlite3, stmts: Map[Stmt, Sqlite3Stmt] }
>
> fn prepare_clause(c: Conn, sql: Str) -> Result[Stmt, DBError] {
>     let raw = sqlite_prepare(c.handle, sql)?
>     let s = Stmt.new()
>     c.stmts.insert(s, raw)
>     Ok(s)
> }
>
> fn step_clause(c: Conn, s: Stmt) -> Result[Int, DBError] {
>     match c.stmts.get(s) {
>         Some(raw) => sqlite_step(raw)
>         None => Err(ExecError("statement belongs to another connection"))
>     }
> }
> ```
>
> Mock side, forwarding step on purpose:
> ```blink
> fn half_mock() -> Handler[DB ! DB] {
>     let mine = Stmt.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(mine) }
>         fn column_text(s: Stmt, idx: Int) -> Str { "ada" }
>         fn step(s: Stmt) -> Result[Int, DBError] { default.step(s) }
>         // other clauses as in §4.4.10
>     }
> }
> // under a driver connection: s.step() gives
> // Err(ExecError("statement belongs to another connection"))
> ```
>
> A mock with many statements does `if s == first { ... }`, or keeps its own Map.
>
> Tradeoffs:
> - One constructor instead of two (mock + internal). The std driver and package drivers use the same tool. No special path in std.
> - Cost: a mock can no longer write `Stmt.mock(1)` inline in a clause; it binds the token in a `let` first. One extra line. Worth it: the inline key form is exactly what made forgery possible.
> - Cost: hash by identity needs a stable address. The runtime GC does not move objects, so this holds. If it ever moves, the runtime adds a counter id; the surface does not change.
> - The finalized-vs-foreign split: a driver keeps finalized tokens in a set (or a state in the map value) so a second finalize gives Ok and a foreign token gives the owner Err. That is driver code, not language.
> - Child.mock keeps its key form. Child has one maker (the built-in handler) and no package drivers, so its forgery risk does not exist. Do not touch it here.
>
> PROPOSAL B (fallback): keep Stmt.mock(k) with key Eq/Hash like Child, and add Stmt.new() as above for drivers. Fresh tokens never equal a mock token. Works, but two constructors for one job. I vote A over B.
>
> Rejected: an owner field in the value (Q3 "in the token"). It adds a type parameter or an Any-ish owner slot for a fact each handler already knows.
>
> Cross-language: Scheme gensym + eq?, Lua tables as keys (identity hashing), Go `&token{}` pointer compare. All three use plain identity, not a keyed constructor, for unforgeable handles.

#### Phase B — Round 1

The moderator put four facts from the spec to the panel:

1. §3.6 *Container Equality*: "**Values, never identity.** `==` never compares identity."
2. §9.1 *What `! ()` Claims on an `@ffi` Decl*: "An empty row lets a compiler reuse the result of a call, move the call, or delete the call when it does not use the result." §3.6 *Hash Contract and Seeding*: "A compiler may reuse the result of a pure call only for arguments that are identical in representation."
3. The `Child` rule "Two spawns under the built-in handler never give equal values" is about values from `process.spawn`, which performs an effect operation. `Child.mock(n)` is the only `Child` constructor with no row.
4. A `handler E { ... }` expression captures bindings as a closure does, and a captured `let mut` is a shared cell. So a driver's map written in `prepare` is seen by later operations.

Fact 2 moved every panelist: a fresh constructor with no row and no arguments may be merged into one call, so two prepares could share one token. All six then asked for a row or a rule. PLT moved from I to N; DevOps moved from F to I; Minimalism moved from N to I. Picks after round 1: I (sys, devops, min), F (web, aiml), N (plt).

- **Systems:**

> Systems B1: I still pick I. I change one thing: the issuer constructor needs a row. Facts 1 and 2 decide this. They hurt F and N more than they hurt I.
>
> Fact 2 (codegen). An empty row lets the compiler reuse, move or delete the call. Every "fresh" constructor with no row contradicts that. Two `Stmt.fresh()` calls with the same args (no args) may become one call, so two prepares share one token. Memoizing across calls is allowed too, so two `connect` calls could share one issuer. That is a real miscompile risk, not just a point of style. So I change my position: the fresh constructor must have a row. Under I, that costs almost nothing. Only one fresh call runs per connection, and it runs in `connect`, which already has an FFI row. A mock pays the row once, in the fn that builds it, outside the handler. F and N need a fresh call on each `prepare`, inside a handler clause. Every mock clause that makes a token then picks up the row, and devops showed the row cannot be `DB`. The name of the row is the PLT seat's call. My limits: not `DB`, and the narrowest effect that exists. `make(key)` and `key_of` stay pure: (issuer, key) in, the same token out. Reuse is correct for them.
>
> Fact 1 ("`==` never compares identity"). F and N give `Stmt` an Eq that is true only for copies. That is identity Eq, and it breaks §3.6, or it needs an exception written for `Stmt` alone. I has no Eq on `Stmt`. `key_of` gives back a plain `Int`, and the driver compares Ints. No conflict.
>
> Fact 3 agrees: `Child`'s "never equal" rule depends on an effect op that makes the value. A no-row constructor has no precedent.
>
> Variations:
> - I-v1 (names): the writer decides. Either set is fine.
> - I-v2: `Stmt` gets no Eq, Hash, Debug or getter. YAGNI, and Eq would bring fact 1 back.
> - I-v3: keep it. One issuer's key names one statement for the life of that issuer. A driver that reuses a key breaks the finalized-Err promise. That is the handle ABA bug. The compiler cannot check this, so it is a driver contract in the spec, in the same way the `Connection` convention is.
> - F-v2: against it. It makes Err text depend on Debug output, and the text is a contract.
> - F-v1: moot under I.
>
> Cost check under I: the token is {issuer pointer, i64}, one compare, one table index. No identity hashing.
>
> stable, ready to vote

- **Web/Scripting:**

> Position: still F. One change: I now say `Stmt.fresh()` needs a row. Facts 1 and 2 changed my mind.
>
> The row question. Fact 2 lets a compiler reuse the result of a no-row call when the arguments are identical. Zero arguments are always identical. So two `Stmt.fresh()` calls may become one token, and two statements collide. That breaks F, and it breaks I and N the same way: `StmtIssuer.new()` and `Stmt.new()` are no-arg, no-row calls too. So this point does not pick between options. Every option needs a row on its fresh constructor. I withdraw my "allocation is not an effect" claim.
>
> Which row: PLT should pick. My only rule is the 90% case: a mock never calls the fresh constructor, so a mock keeps an empty row. Under F that is already true, because mocks use `Stmt.mock(k)`. Only driver authors pay, and a driver's clause row already has FFI, so the cost is close to zero. I agree with devops: not `DB`.
>
> Fact 1 (`==` never compares identity): F fits it if a fresh token holds a hidden serial number and `==` compares that value. Then it is value equality, like `Child`. Say it that way, not "identity".
>
> Why F over I and N:
> - N removes inline `Stmt.mock(1)`. Every scripted mock in the docs gets a `let` line and loses its predictable value. That is a cost for the many to save the few.
> - I adds a second type, three functions, and a key table. A driver still needs a table. F does the job with one function and one map. A JS dev reads F in a minute; I needs a paragraph.
>
> F-v1: aiml's `Stmt(fresh)`. No number, so golden output stays stable. `Stmt.mock(3)` prints as written.
>
> F-v2: yes, I want it. "statement Stmt.mock(1) belongs to another connection" tells a mock author which token went where. A forward with a missing clause is the main way people hit this Err, so the extra text pays for itself.
>
> I-v3 has an F version that the spec must cover. If `finalize` removes the map entry, a later op on that token gets the owner Err, not "statement is finalized". So the driver must keep a record of a finalized token (map value is a state, not just the raw statement). Fresh tokens are never reused, so a stale token never reaches a new statement. That is a plus for F.
>
> I-v2: under F, Stmt gets Eq + Hash + Debug. Without them a mock that holds two statements cannot tell them apart.
>
> stable, ready to vote

- **PLT:**

> PLT Phase B1: I change my pick from I to N. Second choice F, third I.
>
> Why I move. N fixes Q1 to Q3 with one function and no new type. Ownership moves out of the value and into the driver's map: "not in my map" means the owner Err. That is as sound as my issuer, and it removes a hazard that I had. In I, the caller picks keys, so a reused key lets a stale token reach a new statement (sys's I-v3). In N, a token is never reused, so I-v3 cannot happen. I was wrong to keep the extra type.
>
> Fact 1 (`==` never compares identity). N and F are fine only if equality is value equality on a hidden serial. The runtime gives each `Stmt.new()` token a serial that no other call gets, and `==` and `Hash` compare that serial. That is a value in the representation, not a pointer compare, so §3.6 holds. The spec must say it that way.
>
> Fact 2 (no-row calls can be reused). This breaks every option as written, mine too. `Stmt.new()` has no args, so under the reuse rule a compiler may merge two calls. Then two connections share a token, or a loop of prepares gives one token. My position: no row. A DB row is wrong (devops is right: it goes to the outer handler), and no other row fits. Instead the spec must name `Stmt.new()` as generative: a compiler never reuses, merges, hoists or deletes a call of it. StringBuilder.new() needs the same rule today, so this is one shared rule, not a Stmt exception. I want that rule in the ballot text. Without it I vote against every option.
>
> N details:
> - Eq and Hash: yes, on the serial (Q2 needs them for Map[Stmt, Raw]).
> - Debug: none, or one with no number (aiml's reason: a golden test must not change from run to run). I do not want a serial in program output.
> - min's cost, "bind the token in a let first", is correct and small. A mock with many statements makes many tokens and keeps them in a Map or a List.
>
> F: sound with the same two rules, but it gives two ways to make a token. Also two nested mocks that both use `Stmt.mock(1)` take each other's tokens. I accept F over I, not over N.
>
> F-v2 (Debug text in the owner Err): against. It puts unstable text in program output and changes an error message that the decided spec fixes.
>
> I-v2: no longer relevant since I drop I. If I wins, keep no Eq, Hash or Debug, and adopt sys's key-reuse rule.
>
> stable, ready to vote

- **DevOps/Tooling:**

> DevOps B1: I move from F to I. Facts 1 and 2 break my Phase A pick.
>
> Why F fails: `Stmt.fresh()` with no row gives unequal values for equal arguments. Fact 2 lets the compiler reuse or delete a no-row call, so two `Stmt.fresh()` calls may merge into one token. That bug would be silent, would depend on the optimization level, and no test would catch it the same way twice. That is the worst kind of bug for tools. N has the same flaw.
>
> Why I is better: the fresh step happens once, in `StmtIssuer.new()`, at `connect` time. That is outside every handler clause, so a row on it costs nothing and has no outer-handler trap. Then `iss.make(key)` is pure in the real sense: same issuer and same key give equal tokens. Fact 3 is the precedent: like `Child` from `spawn`, the identity comes from an effectful call, not a no-row one.
>
> Row question: `StmtIssuer.new()` MUST have a row (PLT picks which one). `make` and `key_of` have no row.
>
> I-v2: I want `Debug` on `Stmt`. With an issuer it stays stable: `Stmt.mock(1)`, or `Stmt(key 5)` for an issued token, with no issuer number in the text, so golden tests stay stable. `assert_eq` and LSP hover need it. `Eq` and `Hash` are nice to have but not needed now that `key_of` exists. I will not block on them.
>
> `Stmt.mock(k)`: I would keep it as an issuer-less token that `key_of` never matches. Then a mock can write `Ok(Stmt.mock(1))` inline, with no row and no `let` above the handler. The forward still "can never succeed". If the panel wants one constructor only, I accept removing it.
>
> I-v3: yes. The spec must say: one issuer never reuses a key, or the finalized Err is not promised. A counter in the driver does it. Add an example that shows the counter.
>
> F-v2: I withdraw it. With issued tokens, the Debug text in the Err makes program output depend on driver keys. Keep the Err text fixed. Tools can show the token on hover.
>
> Names (I-v1): `StmtIssuer` reads better in an error message and on hover than `StmtOwner`, which sounds like a connection. Small preference.
>
> stable, ready to vote

- **AI/ML:**

> AI/ML round 1: still F, but I change my position on the row. Fact 2 breaks "no row".
>
> **Change: the fresh constructor needs a row.** Fact 2 says a compiler may reuse a pure call's result when the arguments are identical. `Stmt.fresh()` has no arguments, so every call has identical arguments. With no row, `let a = Stmt.fresh()` and `let b = Stmt.fresh()` may become one call, and then `a == b`. Two statements of one connection would share a map entry. The bug is silent and gives a wrong answer with no Err, which is the exact trap I wanted to close. Fact 3 points the same way: Child's distinct values come from `spawn`, an effect op, never from a no-row fn. N and I have the same flaw (`Stmt.new()`, `StmtIssuer.new()`). So the row question is not optional for any option.
> - PLT should name the row. It must not be `DB`, since devops is right that it would go to the outer handler. It must be a row that a driver can put in the R of `Handler[DB ! R]`. Mocks do not need it, because they use `Stmt.mock(k)`.
> - Fact 1 (values, never identity) does not hurt F if the spec says that a fresh token holds a hidden key that the runtime fills. Then `==` compares that key as a value. The spec should state it that way and not say "identity".
>
> **F vs N vs I**
> - F: yes. It mirrors Child, so a model learns one pattern for both. A mock still writes `Stmt.mock(1)` inline.
> - N: no. It removes the inline mock token, breaks the Child symmetry, and every mock pays an extra `let` and a captured binding. That is more tokens and one more thing to get wrong.
> - I: no. It has two concepts (issuer + key) where F has one. I-v3 shows a new silent-bug class: if a driver reuses a key after `finalize`, a stale token runs a new statement. With F, a driver cannot reuse a token at all, so the class does not exist.
>
> **Variations**
> - F-v1: `Stmt(fresh)`, with no number. Goldens and spec examples stay stable, and models copy what they see in examples. A run-varying `#17` in an Err text will leak into tests that a model writes and then fails to repair.
> - F-v2: yes, with F-v1's text. "statement Stmt.mock(1) belongs to another connection" names the mock token, so the reader at once sees that a mock made it. That is the repair hint the current text lacks (the spec admits the Err "does not name the omitted operation"). Under F-v1 the text stays stable.
>
> Stable on F + F-v1 (`Stmt(fresh)`) + F-v2 + "fresh constructor carries a row (not DB; PLT names it)". Ready to vote on that bundle. If the panel rules no row, my vote turns against F as written.
>
> stable, ready to vote

- **Minimalism:**

> Minimalism B1: I change my pick from N to I. Facts 1 and 2 break N, and they break F too.
>
> Fact 1 ("== never compares identity"): N and F both give Stmt an Eq that compares identity. That is a second meaning of == for one type. A smaller language does not add an exception to a rule it states in §3.6. I withdraw N and my fallback B.
>
> Fact 2 (a no-row call may be reused or deleted): `Stmt.fresh()` / `Stmt.new()` with no row and no args may legally fold into one call. Two connections in a loop would then share tokens, and the owner check is gone. This is a real bug, not a theory point.
>
> Why I is the smallest option that stays correct:
> - Stmt keeps no Eq, Hash, Debug or getter (I-v2: I take plt's line). The spec rule for Stmt does not change; only the maker does.
> - One new opaque type and three fns replace `Stmt.mock` plus the std-internal pair. One path for std and package drivers.
> - The key is an Int that only the issuer reads back. The driver keeps `Map[Int, Raw]` with plain value equality. No identity anywhere in Stmt.
> - A mock keeps the inline key style: `Ok(iss.make(1))`. My N cost (bind in a `let`) is mostly gone; the mock binds the issuer once.
>
> Row question: the issuer's `new()` gives a distinct value per call, so by fact 2 it MUST have a row. No-row is wrong. Not DB (devops is right: it would go to the outer handler). I ask plt to name an existing row that fits; I vote against a new effect just for this. `make` and `key_of` read only their args and can stay no-row: `make(k)` on the same issuer gives tokens that `key_of` reads back the same, so reuse is harmless.
>
> I-v1 names: writer's call. I lean `StmtIssuer` (it says what it does; "owner" also reads as the connection).
>
> I-v3 key reuse: agree with sys. The spec says the finalized Err holds only when an issuer never sees a key reused. That is driver code, not language. Do not make the issuer count keys; that needs mutation and a row on `make`.
>
> Fact 3: it supports I. Child's no-row `mock(n)` is safe because only an effect op makes real Childs. A package driver has no such op, so it needs a maker with a row. That is the issuer.
>
> F-v1 / F-v2: if F wins, no Debug, and no F-v2 (do not change the owner Err text).
>
> stable, ready to vote

#### Phase B — Round 2

The moderator added three facts: there is no `FFI` effect (fact 4); `StringBuilder.new()`, `Map.new()`, `Set.new()` and `Bytes.new()` have no row (fact 5); and the text of the reuse license (fact 6). The panel had to name an existing effect for the row, or take a rule with no row.

Five replies backed a rule that a compiler never merges a call that makes a fresh value. PLT withdrew its own rule and named `State`. Systems moved from I to N; DevOps moved from I to F; PLT moved from N to I. Picks after round 2: F (web, devops, aiml), N (sys), I (plt, min).

- **Systems:**

> Systems B2: I drop the row and take PLT's generative rule. With the row question gone, I change my pick from I to N. Second choice I, third F.
>
> 1. Row: I name none. Fact 4 removes the FFI row I counted on. State, Rand and Time all have the wrong meaning, and each one would charge a mock for nothing. A new effect only for this is too much. I withdraw "it needs a row".
>
> 2. Generative rule: yes. Signature: `pub fn Stmt.new() -> Stmt`, with no row. Facts 5 and 6 show we need this rule already. `StringBuilder.new()` has no row and gives a mutable value, so merging two calls of it is a miscompile today. Fact 6 already names "a fresh result". It is the C `malloc` attribute and LLVM's `noalias` return: the call is free of side effects, but no compiler merges two calls. What it compiles to: a 64-bit atomic counter. There is no hoisting or CSE of the call, and nothing else changes.
>
> My one demand on the rule: it must be TRANSITIVE. A driver helper `fn mint() -> Stmt { Stmt.new() }` has no row. If the rule marks only `Stmt.new`, a compiler may still merge two `mint()` calls, and the bug comes back through a wrapper. So write it as a narrower reuse license (fact 6): "a compiler may reuse a pure call only when the callee, directly or through its callees, makes no fresh result". Do not write it as a mark on one fn. Our emitter does no call CSE today, and gcc does not merge calls to fns that have no `pure` or `const` attribute. So the cost now is spec text only.
>
> 3. Why I move to N. My case for I depended on the row: one fresh call per connection against one per prepare. With no row, that point is gone. What is left goes against I:
> - I-v3 (key reuse, my own point) is a silent bug that I brings in and N cannot have. A serial is never reused.
> - Fact 1: Eq on a hidden serial is value equality on the representation. I accept PLT's reading.
> - Size: the N token is 8 bytes (the serial). The I token is 16. The driver does one integer hash in `Map[Stmt, Raw]`, which costs nothing next to `sqlite3_step`.
> - F keeps `Stmt.mock(k)`. Two mocks that both make `Stmt.mock(1)` then accept each other's tokens on a forward, so "can never succeed" is false for a forward from mock to mock. N closes that hole, and I closes it too.
>
> N details: Eq and Hash on the serial. No Debug: a run-varying number must never show in output. Against F-v2.
>
> stable, ready to vote

- **Web/Scripting:**

> Web B2.
>
> 1. Row: none. My "a driver row already has FFI" was wrong (fact 4: there is no FFI effect). I withdraw it. I looked for an existing effect that fits and found none. `Rand` is the only candidate, and it is a lie: the driver's clause row would carry `Rand`, so `with sqlite.connect(path)? { }` would show `! Rand` to the user. A JS dev would ask "why does opening a database need randomness?" and they would be right. I vote against a new effect for one constructor.
>
> 2. Generative rule: yes, PLT's rule. Facts 5 and 6 show the language needs it already. `Map.new()` and `StringBuilder.new()` have no row and no args. If a compiler merged two `Map.new()` calls, two maps would share one cell, and that is already a miscompile. Fact 6 allows "a fresh result" from an empty row. So the rule is not a `Stmt` exception. It names a thing the spec already depends on: a constructor marked generative gives a fresh result on each call, and a compiler never reuses, merges, hoists or deletes a call of it. `Stmt.fresh()` joins `Map.new()` in that set.
>
> Signature (F):
> ```blink
> pub fn Stmt.fresh() -> Stmt    // generative: each call gives a new serial
> pub fn Stmt.mock(id: Int) -> Stmt
> ```
> `==` and `Hash` compare the hidden serial, or the mock key. That is a value in the representation, so fact 1 holds. PLT says the same. To sys and min: this is not identity Eq. A serial is an Int the runtime fills, and two tokens are `==` when their Ints are equal.
>
> 3. Pick: still F. Rank: F, then I with devops's variant (keep inline `Stmt.mock(k)`, keep Debug), then N.
> - The generative rule removes the main point for I. Sys and devops liked I because the fresh call happens once, at `connect`, where a row is cheap. With no row, a fresh call in `prepare` costs nothing either.
> - I still asks a driver author for more: an issuer, a key counter, a key table, and a contract that they never reuse a key (I-v3). A wrong key gives a silent ABA bug. F cannot have that bug, because a token is never reused.
> - A mock in F writes `Ok(Stmt.mock(1))` inline, as today.
>
> Changes: I drop F-v2. Devops withdrew it, and three seats are against it. Keep the owner Err text fixed; tools can show the token on hover. F-v1 stays `Stmt(fresh)`, with no number.
>
> Driver note for the writer: `finalize` keeps a "finalized" record in the map. If it deletes the entry, a later op gets the owner Err, not "statement is finalized".
>
> stable, ready to vote

- **PLT:**

> PLT B2: the row is `State`. I drop my generative rule, and I go back to I.
>
> Q1, the row: `State` (§4.16.1). It exists, and it fits exactly. A fresh constructor reads and writes a process-wide counter, and a later call sees the change. That is the §4.16.1 "foreign state" case, and the spec's own `next_id() -> Int ! State` is the same shape. The §07 test settles it: claim 3 ("no hidden channel") fails for any constructor whose result differs from call to call by a counter. So `! ()` was a false claim, and I was wrong to ask for a special rule. `State` also avoids every trap that was named:
> - It has no handler, so it never goes to an outer handler (devops's objection to DB does not apply).
> - `main` and each test block hold it, so E0539 never fires.
> - Capability budgets ignore it, so a driver package with no extra capabilities is fine.
> - It changes no generated code.
>
> ```blink
> pub opaque type StmtIssuer
> pub fn StmtIssuer.new() -> StmtIssuer ! State
> pub fn StmtIssuer.make(self, key: Int) -> Stmt
> pub fn StmtIssuer.key_of(self, s: Stmt) -> Option[Int]
> ```
>
> `make` and `key_of` stay `! ()`. The same issuer and key give tokens that `key_of` reads the same, so reuse of those calls is harmless.
>
> Q2: I withdraw the generative rule. I also withdraw my StringBuilder.new() claim. Its freshness shows only through writes to the result, which §07 claim 2 allows ("a fresh result"). A Stmt serial shows through `==` or `key_of`, so it is a different case.
>
> Q3, my pick: I (back from N). The reason is where the row lands. Under N or F, the fresh call runs in each `prepare` clause, so `State` enters the clause row. A mock becomes `Handler[DB ! State]`, and the spec's "the mock has an empty clause row" fails. Under I, the issuer is made once, outside the handler: in `connect` for a driver, and in the builder fn for a mock. The clause row stays empty. Fact 1 also stops being a question: Stmt gets no `==`.
>
> Mock under I:
> ```blink
> fn scripted_db() -> Handler[DB] ! State {
>     let iss = StmtIssuer.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(iss.make(1)) }
>         // ...
>     }
> }
> ```
>
> Variations:
> - I-v1 names: StmtIssuer, a weak preference. Otherwise it is the writer's call.
> - I-v2: Stmt gets no Eq or Hash. A Debug that prints only the key (devops's `Stmt(key 5)`) is stable, and I will not block it. No issuer number may appear in output.
> - I-v3: yes, sys's driver contract. One issuer never reuses a key, or the finalized Err is not promised. Show a counter in the example.
> - devops's issuer-less `Stmt.mock(k)` (one that `key_of` never matches): it is sound, but it gives a second way to make a token. I prefer to remove it, and I will not vote against I over this.
> - F-v2: against.
>
> stable, ready to vote

- **DevOps/Tooling:**

> DevOps B2: I take PLT's generative rule (no row), and so I move back from I to F. Facts 5 and 6 change my reason for leaving F.
>
> Q1 (a row): I name none. No existing effect fits. `Rand` is wrong: a fresh serial is not random, and every mock or test that makes one would then need a Rand handler. `DB` sends the call to the outer handler. I vote against a new effect for this.
>
> Q2 (generative rule): yes. Fact 5 shows the rule exists in all but name: `Map.new()`, `StringBuilder.new()` and `Bytes.new()` have no row and must give a new value on each call. Fact 6 already lets a no-row call write "a fresh result". If the fact-2 reuse rule could merge two `Map.new()` calls, that is a bug in the spec today, not a Stmt problem. So the ballot should say: a compiler never reuses, merges, hoists or deletes a call of a generative constructor. The rule names `Map.new`, `Set.new`, `Bytes.new`, `StringBuilder.new` and `Stmt.fresh`. Signature:
> ```blink
> pub fn Stmt.fresh() -> Stmt    // generative, no row
> pub fn Stmt.mock(id: Int) -> Stmt
> ```
>
> Q3 (pick): F. My only reason to leave F was the merge bug. The generative rule fixes it for every option. With that gone, I compare the options by silent bug classes, which is my main test:
> - I has the stale-key bug (I-v3). A driver that reuses a key after `finalize` runs a new statement with no Err. The compiler cannot check it. The spec can only write a contract. That is the worst kind of bug for tools.
> - F and N cannot have this bug: a fresh token is never reused.
> - F keeps `Ok(Stmt.mock(1))` inline for mocks, and it matches `Child`. One pattern for docs, hover text and models.
>
> Fact 1: F is fine if the spec says a fresh token holds a hidden serial, and `==` and `Hash` compare that value. That is value equality, like `Child`. Do not write "identity".
>
> Variations:
> - F-v1: `Stmt(fresh)`, no number (aiml). Golden output stays the same between runs. `Stmt.mock(3)` prints as written.
> - F-v2: I keep it withdrawn. With F-v1 the text would be stable, but the Err text is part of a decided ruling. A tool can show the token on hover without that change.
> - Eq + Hash + Debug on `Stmt`: yes. A mock with two statements needs Eq, and a driver needs Hash for `Map[Stmt, Raw]`.
> - The spec must say what `finalize` leaves in the map (web's point). Keep the entry with a "finalized" state, so a later op gives "statement is finalized", not the owner Err.
>
> If the panel rejects the generative rule, I go back to I with a row on `StmtIssuer.new()`.
>
> stable, ready to vote

- **AI/ML:**

> AI/ML round 2: I take PLT's generative rule, not a row. My pick stays F, with I as second choice (only the variant that keeps `Stmt.mock`).
>
> **Q1 (row): withdrawn.** No existing effect fits. `Rand` is the nearest, and it is a lie: a model that sees `! Rand` on a prepare clause will infer that the driver uses random numbers. A new effect for one constructor is worse. So I ask for no row.
>
> **Q2 (generative rule): yes.** Facts 5 and 6 settle it. `Map.new()`, `Set.new()`, `StringBuilder.new()` and `Bytes.new()` have no row and must already give a distinct cell on each call. If a compiler merged two `Map.new()` calls, that would be a miscompile today. Fact 6 already allows a no-row call to return "a fresh result". So the rule exists in practice, and it only needs a name. The spec should state one shared rule: a compiler never merges, reuses, hoists out of a loop, or deletes a call of a generative constructor. It should list them: `Map.new`, `Set.new`, `StringBuilder.new`, `Bytes.new`, and the fresh `Stmt` constructor. This is one rule for a model to learn, not a `Stmt` exception. It also repairs a gap the spec has now.
>
> Signature (F):
> ```blink
> pub fn Stmt.mock(key: Int) -> Stmt    // pure; Stmt.mock(n) == Stmt.mock(m) iff n == m
> pub fn Stmt.fresh() -> Stmt           // generative; no row; never equal to any other Stmt
> ```
> Under I, the same rule goes on `StmtIssuer.new()`, and `make` and `key_of` stay plain pure functions.
>
> **Fact 1 (identity Eq).** Sys and min call F's Eq "identity". I disagree. The runtime gives each fresh token a serial, and `==` and `Hash` compare that serial as a value, the same as `Child`, which already has this Eq in the spec with no exception written. If the panel reads it as an identity Eq, then `Child` already breaks §3.6 too, and that is a separate fix.
>
> **Q3 (pick): F, then I (keeping `Stmt.mock`, as in devops' variant), then N.**
> - F gives the 90% user, a mock author, the same line as `Child`: `Ok(Stmt.mock(1))` inline, with no new type. Models copy the pattern they have seen most.
> - I has the hazard that sys and devops name themselves (a reused key runs a stale statement, the ABA bug), and it can only be fixed by a driver contract in prose. A model writes a driver from examples, not from contracts. F cannot have this bug.
> - If I wins, I want devops' variant: keep `Stmt.mock(k)` as a token that no issuer ever matches, and give Debug `Stmt.mock(1)` / `Stmt(key 5)`. Without Debug, an `assert_eq` failure on a `Stmt` says nothing, and repair gets harder.
> - N: last, for the reasons I gave in round 1.
>
> F-v2: I drop it. Three panelists object that the Err text is a contract, and the repair gain is small next to that. F-v1 stays `Stmt(fresh)`.
>
> stable, ready to vote

- **Minimalism:**

> Minimalism B2: no row. I take PLT's generative rule. My pick stays I. Ranking I > N > F.
>
> Q1 (a row): I withdraw my ask for one. Fact 4 kills the "drivers already have FFI" claim: there is no FFI effect. Of the effects that exist, none fits. Rand lies (the value is not random and a seeded Rand handler could replay it). State and Time do not mean this. A new effect just to mint a token is the opposite of minimal. So no row.
>
> Q2 (generative rule): yes. Facts 5 and 6 decide it. `Map.new()` and `StringBuilder.new()` have no row and give a fresh mutable value. If a compiler merged two `Map.new()` calls, two maps would share cells. That is already a miscompile under today's text. So the spec needs this rule today, for types that already exist. Adding `StmtIssuer.new()` to it costs nothing new. One rule, written once:
>
> "A call to a constructor that gives a fresh value is never merged with, reused for, or moved past another call of it. Each call gives its own value." It covers `Map.new()`, `Set.new()`, `Bytes.new()`, `StringBuilder.new()`, and `StmtIssuer.new()` (or `Stmt.new()` under N/F).
>
> Signature under I:
> ```blink
> pub opaque type StmtIssuer
> pub fn StmtIssuer.new() -> StmtIssuer          // generative, no row
> pub fn StmtIssuer.make(self, key: Int) -> Stmt // no row, plain pure
> pub fn StmtIssuer.key_of(self, s: Stmt) -> Option[Int] // no row, plain pure
> ```
> `make` and `key_of` are pure in the normal sense: the same issuer and key give tokens that `key_of` reads back the same, so reuse is safe.
>
> Q3 (pick): still I. Why not N now that the row problem is gone for all three:
> - N needs Eq and Hash on Stmt over a serial that no code can make or read. PLT calls that value equality. In practice it is identity with a different name: you can only get an equal Stmt by copying it. I would rather not add a second meaning of == to the language. Under I, Stmt has no Eq at all, and the driver compares plain Ints.
> - I keeps the inline mock style: `Ok(iss.make(1))`.
> - The cost of I is the key-reuse contract (sys, I-v3). That is one sentence in the spec, and a driver meets it with a counter. I accept it.
> - N is my second choice. It is one fn, and it has no key-reuse rule. If the panel goes N, I accept Eq + Hash on the serial, and no Debug.
> - F stays last: two constructors for one job, and Debug plus F-v2 change program output.
>
> Variations: I-v2 no Eq, Hash or Debug on Stmt. I-v3 yes, with sys's text. Against F-v2. I-v1 names: writer's call, lean `StmtIssuer`. On devops's keep-`Stmt.mock(k)`-beside-I idea: against. One constructor path. A mock that wants an inline token writes `iss.make(1)`.
>
> stable, ready to vote

#### Phase B — Round 3

The moderator added the text of §4.16.1 *The `State` Effect* (fact 7: no operations and no handler, the roots hold it, budgets ignore it, no run-time cost, "foreign state" that a later call can see) and the two sentences that say a mock has an empty clause row (fact 8).

Five panelists took `State` and dropped the rule. PLT took the rule in its transitive form and moved back to N. Picks after round 3: F (web, devops, aiml), N (sys, plt), I (min). All six said they were stable.

- **Systems:**

> Systems B3: I take the `State` row and drop the never-merge rule. My pick stays N, with I as a close second. In a run-off between I and F, I vote I.
>
> 1. Row: `State`. This answers my own round-2 demand. I asked that the rule pass through wrappers, so that `fn mint() -> Stmt { Stmt.new() }` cannot be merged. An effect row already does that: E0552 makes every `pub fn` above the call declare `State`, and the checker enforces it at each level. A rule would need its own analysis across fns, with a set of constructors to keep up to date. The row reuses machinery we have. Fact 7 also removes my cost objection: no generated code changes, no handler, the roots hold it, and capability budgets ignore it. The meaning is honest too: a process-wide counter that a later call sees is the §4.16.1 "foreign state" case exactly. I was wrong to call State "the wrong meaning". I withdraw the generative rule.
>
> Signature (N):
> ```blink
> pub fn Stmt.new() -> Stmt ! State
> ```
> Under I: `pub fn StmtIssuer.new() -> StmtIssuer ! State`, and `make` and `key_of` have no row.
>
> 2. Pick: N first, I second, F third.
> - Why N still: a serial is never reused, so no ABA. The token is 8 bytes. No key contract for a driver to get wrong. With `State`, a driver pays nothing: `State` in the prepare clause row compiles to nothing, and `main` holds it.
> - PLT's point against N (fact 8): it bites only a mock that mints in a clause. A mock with a fixed set mints up front, `let a = Stmt.new()` in the builder fn, and its clause row stays empty. A mock that mints in a clause gets `Handler[DB ! State]`. That costs no capability and no code, and fact 8's sentence names FS, Time and Rand, not State. So it is a small cost.
> - Min's identity point: I accept Eq + Hash on the serial as a value, the same as `Child`.
> - I is a close second: a clean clause row, no `==` question, and a contract of one sentence that a counter meets.
> - F last: two ways to make a token, and two mocks that both make `Stmt.mock(1)` still accept each other's tokens on a forward.
>
> If the vote is I against F, I vote I. If I wins: no Eq or Hash on Stmt, sys's key-reuse contract with a counter in the example, and against an issuer-less `Stmt.mock`. A Debug that prints the key only is fine. Against F-v2 in every case.
>
> stable, ready to vote

- **Web/Scripting:**

> Web B3.
>
> 1. Row or rule: I take PLT's `State` row and drop the never-merge rule. Fact 7 changed my mind. My objection to a row was that it would lie to the user (`Rand`). `State` does not lie: the spec's own text says "foreign state ... that a later call can see", and a serial counter is exactly that. It has no handler, roots hold it, budgets ignore it, and it costs nothing at run time. A row also fixes sys's wrapper problem for free. A helper `fn mint() -> Stmt ! State { Stmt.fresh() }` carries the row, so the compiler checks it. A never-merge rule needs careful transitive wording and the compiler cannot check it. A checked row beats a prose rule.
>
> ```blink
> pub fn Stmt.fresh() -> Stmt ! State
> pub fn Stmt.mock(id: Int) -> Stmt
> ```
>
> 2. Pick: still F. With `State` on the table, F is now the strongest option, and PLT's argument for I does not hold against F.
>
> PLT says that under F the fresh call runs in each `prepare` clause, so "a mock becomes `Handler[DB ! State]`". That holds for N, not for F. Under F a mock never calls `Stmt.fresh()`. It writes `Ok(Stmt.mock(1))`, which has no row. So the mock's clause row stays empty, and fact 8 ("the mock has an empty clause row") holds as written. Only a real driver calls `Stmt.fresh()`, so only a driver's clause row gets `State`.
>
> Compare where `State` lands:
> - F: driver clause row only. Mocks: nothing. `scripted_db()` and the §4.4.10 examples do not change.
> - I: `connect` gets `! State`, and every mock builder gets `! State` too (`fn scripted_db() -> Handler[DB] ! State`). Every mock in the docs changes its signature.
> - N: every mock clause row gets `State`. Fact 8 fails.
>
> On the driver side, F and I cost the user the same: the user's fn that opens a connection carries `State` either way (from the clause row under F, from `connect` under I).
>
> So F is the only option where the 90% user, a mock author, sees no change at all. It still has no key-reuse contract (I-v3) and keeps the `Child` pattern.
>
> On sys's point that two mocks that both use `Stmt.mock(1)` accept each other's tokens on a forward: that is a mock talking to a mock, and the author chose both keys. The ticket's promise is about a forward to a real handler, and F keeps it. A mock author who wants to avoid it can call `Stmt.fresh()` and accept `State`.
>
> Variations unchanged: Eq + Hash on the serial or the mock key, Debug `Stmt(fresh)` / `Stmt.mock(3)`, no F-v2, `finalize` keeps a finalized record.
>
> stable, ready to vote

- **PLT:**

> PLT B3: I take the rule with no row, in sys's transitive form, and I withdraw `State`. My pick goes back to N. Second I, third F.
>
> Q1, row or rule: the rule. The panel showed me a mistake. In round 2 I said Map.new() and StringBuilder.new() are safe because their freshness "shows only through writes". But writes are exactly how merging two such calls becomes visible: two maps would share one cell. So the spec already depends on fresh results not being merged, and §07 claim 2 already calls a fresh result pure. A Stmt serial is the same thing as an allocation: a value that no other call gets. Charging it `State` while Map.new() is free would be inconsistent. It would also break fact 8 for N and F (the mock clause row would hold State). So the rule is the sound answer, and `State` is not.
>
> The form must be sys's: narrow the reuse license, do not mark one fn. "A compiler may reuse the result of a pure call only when the call, directly or through its callees, makes no fresh result." A list of named constructors fails through a wrapper (`fn mint() -> Stmt { Stmt.new() }`). A compiler that cannot see through a callee must not reuse the call. Today that costs nothing: our emitter does no call CSE.
>
> Signature (N):
> ```blink
> pub fn Stmt.new() -> Stmt    // no row; each call gives a fresh token
> ```
> `==` and `Hash` compare the token's hidden serial, a value in the representation. To min: "equal only to its copies" is how Child from spawn already behaves, and how any freshly made value behaves. It is not a second meaning of `==`. The runtime fills the value, and `==` compares values.
>
> Q2, pick: N. My case for I was where the State row landed. With no row, that case is gone, and what remains favors N:
> - One function and no new type.
> - No key-reuse contract (I-v3). A serial is never reused, so the stale-key bug cannot happen. A spec contract is weaker than a bug that cannot happen.
> - F's `Stmt.mock(1)` lets two nested mocks accept each other's tokens. N and I close that hole. F does not.
>
> N details: Eq and Hash on the serial. No Debug, or Debug with no number. The owner Err text stays as fixed. finalize keeps a "finalized" entry in the driver's map, so a later op gets "statement is finalized" and not the owner Err (web's point). That holds for N and F alike.
>
> If N loses, I prefer I (no Stmt.mock beside it) over F.
>
> stable, ready to vote

- **DevOps/Tooling:**

> DevOps B3: I take `State` and drop the never-merge rule. My pick stays F. F is the option where `State` costs the least.
>
> Q1, row or rule: `State`.
> - Sys's demand shows the problem with the rule. To be safe, the rule must be transitive: "makes a fresh result, directly or through callees". The compiler must then track that fact through every call, and it is not visible in any signature. That is an effect in all but name, but with no syntax, no hover text and no error code. I would rather have the real row. The LSP shows it, `blink check` reports it (E0552), and the spec does not need a second, hidden way to describe effects.
> - `State` has the right traits (fact 7). It has no handler, so it never goes to an outer handler. `main` and each test block hold it, so E0539 never fires. Budgets ignore it, and it changes no generated code. The process-wide counter is exactly the "foreign state" case.
> - PLT is right that `Map.new()` is a different case. Its freshness shows only through writes. A serial shows through `==`.
>
> Signature (F):
> ```blink
> pub fn Stmt.mock(id: Int) -> Stmt        // no row; Stmt.mock(n) == Stmt.mock(m) iff n == m
> pub fn Stmt.fresh() -> Stmt ! State      // a new serial on each call
> ```
>
> Q2, pick: F. PLT's case against F does not apply to F. PLT says that under F the fresh call runs in each `prepare` and so a mock becomes `Handler[DB ! State]`. That is true of N, not F. Under F, a mock writes `Ok(Stmt.mock(1))`, which has no row. Only a driver calls `Stmt.fresh()`. So fact 8 ("the mock has an empty clause row") stays true for every mock in the spec. A driver gets `Handler[DB ! State]`. Under I, the driver's `connect` carries `State` instead. The user pays the same either way: a fn that opens a connection holds `State`.
>
> Under N, every mock pays `State` and fact 8 breaks. N is last for me now.
>
> The rest of my position is unchanged:
> - I keeps the stale-key bug (I-v3), which only prose can guard. F cannot have it.
> - Eq + Hash on the serial or the mock key, as value equality like `Child` (fact 1). Debug: `Stmt.mock(3)` and `Stmt(fresh)`, with no number.
> - F-v2 stays withdrawn.
> - `finalize` keeps a "finalized" entry in the driver map.
>
> Ranking: F (`State` on `fresh`), then I (`State` on `new`, keeping `Stmt.mock`), then N.
>
> stable, ready to vote

- **AI/ML:**

> AI/ML round 3: I switch from the generative rule to `State`. My pick stays F, and `State` makes F stronger. Rank: F, then I, then N.
>
> **1. Row or rule: `State` on the fresh constructor.**
> ```blink
> pub fn Stmt.fresh() -> Stmt ! State    // a new serial on each call
> pub fn Stmt.mock(id: Int) -> Stmt      // pure; equal iff the keys are equal
> ```
> Why I change, from the AI view:
> - A rule is invisible. A model reads signatures, not a list of exempt constructors in §3. `Stmt.fresh() -> Stmt` with no row looks pure, so a model will treat it as pure: it will hoist it, cache it, or wrap it in a no-row helper. `! State` says in the signature what the call does. The spec already teaches that shape with `next_id() -> Int ! State`, so this is a pattern a model has seen, not a new one.
> - Sys's transitive problem goes away with no new text. A wrapper `fn mint() -> Stmt { Stmt.fresh() }` must carry `State` through ordinary row inference, and a `pub` wrapper must declare it (E0552). Under the rule, the same wrapper silently loses the protection unless the spec adds a transitive clause. That is a rule a model will get wrong.
> - Fact 7 removes every cost I worried about. `State` has no handler (no outer-handler trap), `main` and tests hold it (no E0539), budgets ignore it, and it adds no code.
> - The `Map.new()` question is separate. PLT is right that its freshness shows only through writes, which §07 already allows. This ticket should not open it.
>
> **2. Pick: F, now with a clear edge over I.**
> PLT's case for I is that the row should land where it costs least. Under F, it lands only in the driver:
> - A mock uses `Stmt.mock(1)`, which is pure. A mock's clause row stays empty, so fact 8 ("the mock has an empty clause row") still holds with no change. PLT's objection holds for N, not for F.
> - A driver's `prepare` clause gets `State`, so its handler is `Handler[DB ! (FS..., State)]`. The user's fn already sits under `main` or a test, which holds `State`, so the user writes nothing new.
> - Under I, every mock builder gets `! State` (`fn scripted_db() -> Handler[DB] ! State`), and so does each helper that builds a mock. F charges the mock author nothing. I charges every mock author.
> - I keeps the stale-key bug (I-v3). It is silent and only a contract in prose prevents it. F cannot have it.
>
> Variations: F-v1 `Stmt(fresh)` with no number. F-v2 stays withdrawn. Eq + Hash on the serial or the mock key; this is value equality, as with `Child`. Web's note for the writer stands: `finalize` keeps a "finalized" entry in the map. If it deletes the entry, a later op gets the owner Err.
>
> If the panel picks I, I want `State` on `StmtIssuer.new()`, not the rule, for the same reasons.
>
> stable, ready to vote

- **Minimalism:**

> Minimalism B3: I change from the never-merge rule to PLT's `State` row. My pick stays I. Ranking I > N > F.
>
> 1. Row or rule: `State`. My round-2 claim was "no existing row fits". Fact 7 shows I was wrong. `State` is the existing fallback for exactly this case: a hidden counter that a later call sees. It has no ops, no handler, no cost in generated code, it is not a capability, and the roots hold it. So it adds nothing to the language. The rule adds a new spec rule. The smaller answer is the one that uses what already exists.
>
> `State` also solves sys's transitive point for free. A wrapper `fn mint() -> StmtIssuer { StmtIssuer.new() }` must carry `! State` (and E0552 makes a `pub fn` declare it), so the compiler never merges two `mint()` calls. The rule would need new spec text to get the same result. The effect system already does it.
>
> I accept PLT's split on `Map.new()`: its freshness shows only through writes to the result, which §07 claim 2 allows. A token's freshness shows through `key_of`, which is a hidden channel. If the panel finds that `Map.new()` merge is still a hole, that is a separate ticket, not this one.
>
> ```blink
> pub opaque type StmtIssuer
> pub fn StmtIssuer.new() -> StmtIssuer ! State
> pub fn StmtIssuer.make(self, key: Int) -> Stmt
> pub fn StmtIssuer.key_of(self, s: Stmt) -> Option[Int]
> ```
>
> 2. Pick: I. `State` makes the case for I stronger. Under N or F, the fresh call runs in each `prepare` clause, so `State` enters the clause row. Every mock that makes a token becomes `Handler[DB ! State]`, and fact 8 ("the mock has an empty clause row") breaks in two places in the spec. Under I, the issuer is made once, outside the handler: in `connect` for a driver, in the builder fn for a mock. The clause row stays empty. The builder fn and the test hold `State`, which costs nothing (roots hold it).
>
> To sys: your move to N depended on "no row". With `State` the row is back, and it lands in the clause under N. I-v3 key reuse is still the cost of I. It is one sentence of driver contract and one counter in the example. I take that over a row in every mock clause.
>
> Variations:
> - I-v2: no Eq or Hash on Stmt. Debug that prints only the key (`Stmt(key 5)`): I do not want it, but I will not block it if no issuer number shows.
> - I-v3: yes, sys's text, with a counter in the example.
> - devops's issuer-less `Stmt.mock(k)` beside I: against. Two ways to make a token. Not a blocker.
> - F-v2: against.
> - Names: writer's call, lean `StmtIssuer`.
>
> stable, ready to vote

#### Phase C — Final vote

Ballot:

- **Q1 — Row on the call that makes a fresh token.** R-State: the fresh constructor carries `! State` (§4.16.1); a wrapper carries it by row inference, and a `pub` wrapper declares it (E0552). R-Rule: no row; the spec narrows the reuse license so that a compiler never reuses a call that, directly or through its callees, makes a fresh result.
- **Q2 — Shape of the token API (ranked, instant run-off).** F: `Stmt.mock(id)` with no row, plus `Stmt.fresh() ! State`. N: `Stmt.new() ! State` only. I: `StmtIssuer.new() ! State`, with `make(key)` and `key_of(s)`, and a driver contract that one issuer never reuses a key.
- **Q3a — Debug, if F or N wins.** D-text: a fresh token prints `Stmt(fresh)`, a mock token prints `Stmt.mock(3)`. D-none: no `Debug` on `Stmt`. Under F or N, `Eq` and `Hash` compare the hidden serial (or the mock key); no panelist opposed this.
- **Q3b and Q4 — only if I wins.** Q3b: traits on `Stmt` under I. Q4: keep an issuer-less `Stmt.mock(k)` beside the issuer, or drop it.

Not on the ballot: the owner Err text stays as fixed, and `finalize` keeps a "finalized" entry in the driver's map. All agreed.

PLT moved to R-State in this vote: "The round-3 replies convinced me." Minimalism moved from I to N.

- **Systems:** R-State; N, I, F; Q3a D-none

> Systems ballot.
>
> Q1. Vote: R-State.
> Reasoning: A row passes through wrappers with the checker we already have (row inference, E0552). The rule needs a new analysis across fns that no signature shows. `State` changes no generated code, has no handler, and the roots hold it, so the row costs nothing at run time and nothing in capabilities. A counter that a later call sees is the "foreign state" case of §4.16.1, word for word.
> Concern: PLT's point about consistency stays open. If the spec later rules that two `Map.new()` calls must not merge, we will have two ways to say "fresh": a row for Stmt and a rule for Map.
>
> Q2. Vote: N first, I second, F third.
> Reasoning: N cannot have the stale-key bug, because a serial is never reused. The token is the smallest of the three (8 bytes), and it adds one function and no type. Its cost is `State` in the clause row of a mock that mints inside a clause. That is a row with no code, and a fixed-set mock avoids it by minting in the builder. I is close behind: one contract sentence that a counter meets. F last: two constructors, and two mocks that both use `Stmt.mock(1)` accept each other's tokens on a forward.
> Concern: under the winner, a driver's `finalize` must keep a "finalized" entry (N/F) or never reuse a key (I). If it does not, the finalized Err turns into a wrong Err or a silent wrong statement. So the spec example must show the correct driver table.
>
> Q3a. Vote: D-none.
> Reasoning: `Stmt(fresh)` prints the same text for two tokens that are not equal, so an `assert_eq` failure reads "Stmt(fresh) != Stmt(fresh)". That message misleads, and it is worse than no Debug. Adding Debug later is not a breaking change. Removing it is.
> Concern: a mock author who wants to assert on a token gets no printed value, only pass or fail.
>
> Q3b. Vote: I-none.
> Reasoning: Same YAGNI. `key_of` already gives a plain Int that the author can print. I will not block I-debug if it prints the key only.
> Concern: without Debug, an `assert_eq` on a `Stmt` does not compile, so authors must compare `key_of` results instead.
>
> Q4. Vote: M-drop.
> Reasoning: An issuer-less token is a second way to make a token, and a mock that holds two of them cannot tell them apart. `iss.make(1)` is just as short inline, and the issuer is built once in the builder fn.
> Concern: every mock builder that makes tokens declares `! State`, which changes the signature of each mock in the docs.

- **Web/Scripting:** R-State; F, N, I; Q3a D-text

> Web ballot.
>
> Q1. Vote: R-State.
> Reasoning: The row shows the effect in the signature, on hover and in `blink check`. A never-merge rule is an invisible effect that only spec readers know about. The row also covers wrappers through normal row inference and E0552, with no new spec text. `State` has no handler, no run-time cost, and every root holds it, so a user never has to handle it.
> Concern: A user who opens a real connection inside a `pub fn` must now write `! State` (E0552). If the error message does not say why, that will puzzle people.
>
> Q2. Ranking: F, N, I.
> I changed my order of N and I since round 1. With `State`, an N mock can make its tokens up front in the builder fn, and then it pays the same as an I mock. N then does the same job with one fn and no key-reuse contract, so it beats I.
> Reasoning: F is the only option where a mock author changes nothing. `Ok(Stmt.mock(1))` stays inline with no row, and every mock in the spec keeps an empty clause row. Only a driver author calls `Stmt.fresh()` and carries `State`, and there are few of them. F matches `Child`, and it cannot have the stale-key bug, because a fresh token is never reused.
> Concern: Two mocks that both use `Stmt.mock(1)` accept each other's tokens on a forward. The spec should say so in one line, so that nobody reads "can never succeed" as covering a forward from one mock to another.
>
> Q3a. Vote: D-text.
> Reasoning: An `assert_eq` on a `Stmt` that fails with no Debug tells the user nothing. `Stmt(fresh)` and `Stmt.mock(3)` are stable from run to run, so golden output does not change.
> Concern: People may write tests that match `Stmt(fresh)` text and expect it to tell two fresh tokens apart. It cannot.
>
> Q3b. Vote: I-debug.
> Reasoning: Same reason as Q3a. A failed assert or a log line needs to show something. Printing the key only keeps output stable.
> Concern: Two issuers can both print `Stmt(key 5)`, so the text can suggest that two tokens are equal when they are not.
>
> Q4. Vote: M-keep.
> Reasoning: If I wins, the inline `Ok(Stmt.mock(1))` keeps the 90% mock as simple as it is today: no issuer, no `let`, and no `State` on the builder fn. The forward still gets the owner Err, because no issuer matches it.
> Concern: Two ways to make a token. The docs must say which one a driver uses and which one a mock uses.

- **PLT:** R-State; N, I, F; Q3a D-none

> PLT ballot.
>
> Q1: R-State.
> Reasoning: The round-3 replies convinced me. A row is checked and shows in every signature, and row inference carries it through wrappers with no new analysis. The rule makes the compiler track a fact that no signature shows, which is an effect with no syntax. Koka does the same thing with `alloc<h>` on ref creation. My Map.new() consistency point is real, but it is a separate question about §07 claim 2 and should not hold this ticket.
> Concern: The merge hole for Map.new(), Set.new(), Bytes.new() and StringBuilder.new() under the fact-6 reuse license stays open. It needs its own friction ticket, so the spec does not keep two models of freshness by accident.
>
> Q2: N first, I second, F third.
> Reasoning: Under R-State, N costs a mock the same as I: a mock that makes its tokens up front (`let a = Stmt.new()` in the builder fn) keeps an empty clause row, and only the builder holds State. A mock that makes tokens in a clause shows State, which is true and costs nothing. N also has no key-reuse contract, so the stale-key bug cannot happen. I puts that bug behind a sentence of prose that no compiler checks. F is last because two mocks that both make `Stmt.mock(1)` accept each other's tokens. That breaks the decided first-Err bullet ("a handler that did not make the Stmt", which names a mock) by design, not by a driver bug.
> Concern: Under N, the spec examples must show the up-front `let` pattern, or readers will put `Stmt.new()` in a `prepare` clause and wonder why the mock type changed.
>
> Q3a: D-none.
> Reasoning: Under N, every fresh token would print the same `Stmt(fresh)`. An `assert_eq` failure would then read "Stmt(fresh) != Stmt(fresh)", which misleads more than it helps. Under F, printing `Stmt.mock(3)` is a getter for the key in text form, which contradicts "there is no getter that reads the key back".
> Concern: Tools and test output have less to show for a Stmt. LSP hover can cover that without a language trait.
>
> Q3b: I-none.
> Reasoning: The same getter argument. Under I, only the issuer may read a key back. `Stmt(key 5)` hands the key to any code that formats the token.
> Concern: Debugging a driver with many statements is harder. The driver can log its own keys through `key_of`.
>
> Q4: M-drop.
> Reasoning: An issuer-less mock token is sound, but it is a second way to make a token, and an inline `iss.make(1)` covers the same use. One constructor path is easier to specify and to learn.
> Concern: Every mock builder fn gets `! State` from `StmtIssuer.new()`, so the spec's mock examples change their signatures.

- **DevOps/Tooling:** R-State; F, I, N; Q3a D-text

> DevOps/Tooling Phase C ballot.
>
> Q1. Vote: R-State.
> Reasoning: A row shows in the signature, on hover, and in `blink check` (E0552 at each pub wrapper). The transitive rule is an effect that no tool can show and no error code reports. A wrapper that loses the guard would give a silent miscompile that depends on the optimization level. `State` has no handler, no run-time cost, and the roots hold it, so it costs the user nothing.
> Concern: users may read `State` on a driver's handler type as "this driver keeps hidden globals" and file confused bug reports. The spec should give one sentence on why it is there.
>
> Q2. Vote: 1st F, 2nd I, 3rd N.
> Reasoning: Under F, `State` lands only in a driver's prepare clause. Every mock keeps `Ok(Stmt.mock(1))` and an empty clause row, so every mock example in §4.4.10 stays as written. I adds a key-reuse contract that the compiler cannot check, and a broken contract runs a stale statement with no Err. That is the worst bug class for tools. N puts `State` in each mock that makes tokens in a clause, and it removes the inline mock token.
> Concern: under F, two nested mocks that both use `Stmt.mock(1)` accept each other's tokens on a forward. The spec must say that the "can never succeed" promise covers a forward to a real driver, not mock to mock.
>
> Q3a. Vote: D-text.
> Reasoning: An `assert_eq` failure or a `{s}` in a log on a Stmt with no Debug says nothing, and the user must guess. `Stmt(fresh)` and `Stmt.mock(3)` print with no run-varying number, so golden tests stay stable. It matches `Child`, so docs, hover and test output follow one pattern.
> Concern: users may ask for the serial in the text to tell two fresh tokens apart. The spec should say the text never holds one.
>
> Q3b. Vote: I-debug.
> Reasoning: Same need as Q3a: a failed assert on a Stmt must show something. `Stmt(key 5)` is stable because it prints only the driver's key, not the issuer.
> Concern: two issuers can each print `Stmt(key 5)`, so two tokens that are not the same look the same in output.
>
> Q4. Vote: M-keep.
> Reasoning: A mock writes `Ok(Stmt.mock(1))` inline, with no `State` on its builder and no issuer to set up. `key_of` never matches it, so a forward with it always gets the owner Err, and the promise holds by construction.
> Concern: two ways to make a token, so a reader may not know which one a mock should use. The spec example must show the mock using `Stmt.mock` and the driver using the issuer.

- **AI/ML:** R-State; F, I, N; Q3a D-text

> AI/ML ballot.
>
> Q1. Vote: R-State.
> Reasoning: A model learns effects from signatures. `! State` puts the fact "each call differs" where a model reads it, and the spec already teaches that shape with `next_id() -> Int ! State`. The rule is invisible. A no-row `Stmt.new()` looks pure, and a model will cache it, hoist it, or wrap it. Only an analysis across fns that no signature shows would catch that. The row gets that transitive check from E0552, with no new spec text.
> Concern: If PLT is right that `Map.new()` merges are the same hole, the spec ends up treating two kinds of fresh value differently, and a model may then add `! State` to `Map.new()` wrappers. The writer should state the split (fresh value seen through writes vs seen through `==`) once, with an example.
>
> Q2. Vote: F first, I second, N third.
> Reasoning: Under F, `State` lands only in a driver's `prepare`. Every mock keeps `Ok(Stmt.mock(1))` inline with an empty clause row. No spec mock example changes, and the pattern matches `Child`, so a model learns one shape for both. I charges every mock builder `! State`, and its stale-key bug is guarded only by prose. A model writes drivers from examples, not from contracts. N puts `State` in every mock clause and breaks the "empty clause row" text.
> Concern: Under F, two nested mocks that both use `Stmt.mock(1)` accept each other's tokens on a forward. The writer should say that the "can never succeed" promise covers a forward to a handler that makes tokens with `Stmt.fresh()`, not a forward from one mock to another.
>
> Q3a. Vote: D-text.
> Reasoning: An `assert_eq` or a panic that involves a `Stmt` must print something a model can act on. `Stmt.mock(3)` names the mock key, and `Stmt(fresh)` says that a real driver made the token. With no number, golden output and spec examples stay the same from run to run. With no Debug, a failure on a `Stmt` prints nothing useful, and repair turns into guessing.
> Concern: Two fresh tokens print the same, so a failing assert on two driver tokens shows `Stmt(fresh) != Stmt(fresh)`. That is odd, but it is still correct.
>
> Q3b. Vote: I-debug.
> Reasoning: Same reason as Q3a. A key-only text is stable and gives a failing test something to show.
> Concern: A model may read `Stmt(key 5)` as a value it can build. The writer must say there is no constructor that takes that text.
>
> Q4. Vote: M-keep.
> Reasoning: It keeps the inline mock line and the match with `Child`, and a mock needs no `State` and no issuer just to answer a test. The forward always gets the owner Err, so the core promise holds.
> Concern: There are two ways to make a token under I. Examples must show which one a mock uses (`Stmt.mock`) and which one a driver uses (the issuer), or models will mix them.

- **Minimalism:** R-State; N, I, F; Q3a D-none

> Minimalism ballot.
>
> Q1. Vote: R-State.
> Reasoning: State already exists for a hidden counter that a later call sees, and it costs no code, no handler, no capability. The row carries through wrappers by the checker we already have; the rule needs new transitive prose that no signature shows. Use what exists before adding text.
> Concern: authors may read `! State` on a token maker as "this touches global data" and avoid it, or the panel may later find Map.new() needs the same treatment and the two answers disagree.
>
> Q2. Vote: N first, I second, F third. (Change from my B3 pick of I.)
> Reasoning: web and devops are right that my B3 claim was wrong for F, and it is weaker than I said for N: a mock that makes its tokens in the builder fn (`let a = Stmt.new()`) keeps an empty clause row, the same cost as I's builder. With that, N is the smallest surface: one fn, no new type, and no key-reuse contract for a driver to break. I keeps a clean clause row too, but it adds a type, three fns and a prose contract. F gives two ways to make one thing, and two mocks that both write `Stmt.mock(1)` accept each other's tokens.
> Concern: Eq on a serial that no code can read is identity in all but name, and a later reader may use it to argue for identity Eq on other types.
>
> Q3a. Vote: D-none.
> Reasoning: no user has asked for it. `Stmt(fresh)` tells a reader nothing that the type name does not, and any number in it would make output change from run to run. Add it when a real need shows.
> Concern: assert_eq on two Stmt values gives a less helpful failure message.
>
> Q3b. Vote: I-none.
> Reasoning: the key is the driver's business; printing it leaks a driver detail into program output for no stated need.
> Concern: harder to debug a mock with many statements.
>
> Q4. Vote: M-drop.
> Reasoning: one way to make a token. A mock writes `iss.make(1)` inline, which costs one `let` for the issuer.
> Concern: mock authors who learned `Stmt.mock(1)` from the old spec text hit an unknown-function error; the CHANGELOG line must name the replacement.

| Question | Result |
|----------|--------|
| Q1 | R-State, 6-0 |
| Q2, first choices | F 3 (web, devops, aiml), N 3 (sys, plt, min), I 0. I drops. F against N on the full rankings: 3-3 |
| Q3a | D-text 3 (web, devops, aiml), D-none 3 (sys, plt, min) |
| Q3b, Q4 | Moot: I dropped |

#### Phase D — Focused round on Q2 and Q3a

The moderator added two facts. Fact 9 is the `Child` text: `Child` implements `Eq`, `Hash` and `Debug`, and its `Debug` text "is not a format: code must not parse it or compare it. Use `==` to compare two `Child` values." Fact 10 is the decided first-Err bullet: "A handler that did not make the `Stmt` gets it ... The handler may be another connection, a mock, or an outer handler."

- **Systems:**

> Systems D: N holds on Q2. On Q3a I make my vote depend on Q2: D-none under N, and D-text is fine under F.
>
> Q2, F or N.
> The F side's case is "a mock changes nothing". Its cost is the mock-to-mock hole, and all three F voters now ask the writer to narrow the promise. Fact 10 says that rule is already decided. The first Err goes to "a handler that did not make the Stmt", and that handler "may be ... a mock". Under F, mock B gets `Stmt.mock(1)` from mock A and cannot tell that it did not make it. So F does not just narrow a sentence. It breaks a decided rule by design, and the fix the F side proposes is to change that rule's text. That is reopening a closed ticket.
>
> N's cost is one `let` line in a mock builder, or an honest `State` in the clause row of a mock that makes tokens in a clause. `State` compiles to nothing, so nothing differs at run time. A row with no code is a small price for a rule that holds for every handler, driver or mock.
>
> On "F matches `Child`": `Child.mock` is safe because only an effect op (`spawn`) makes a real `Child`, and a mock never needs to tell two mock `Child` values apart in order to answer an owner check. `Stmt` has an owner check in every handler, mocks included. The two types differ exactly where it matters.
>
> Min's concern (identity in all but name) is real, but it is the `Child` case again: a value that the runtime fills and that `==` compares. No new rule.
>
> Q3a. I change: my vote depends on Q2.
> - Under N: D-none. Every token prints `Stmt(fresh)`, so the text carries no information, and `Stmt(fresh) != Stmt(fresh)` misleads. PLT's point stands too: a printed key would be a text getter.
> - Under F: I accept D-text. `Stmt.mock(3)` tells the reader something, and it matches `Child`'s Debug, which the spec already accepts with the same "no getter" line (fact 9). The spec must say that the text is not a format and holds no serial.
> So in the silent vote I will vote D-none if N wins Q2 and D-text if F wins. If the ballot does not allow that, I vote D-none.
>
> stable, ready to vote

- **Web/Scripting:**

> Web, Phase D. I hold F. On Q3a I hold D-text under F, and if N wins I accept D-none.
>
> Q2, F or N.
>
> The main case against F is PLT's: two mocks that both use `Stmt.mock(1)` accept each other's tokens, so the first-Err bullet ("the handler may be ... a mock") fails by design. That bullet never held for mocks under any option. Look at `scripted_db()` in §4.4.10: `fn step(s: Stmt) { Ok(101) }`. It never looks at `s`. A mock answers the owner Err only if its author writes the check. Under N that is the same. A mock that ignores its argument accepts any token, fresh or not. So the bullet is a promise about drivers, and about mocks whose authors chose to check. F keeps that promise for drivers in full. For mocks, the author picks the keys. One writer line covers it: "the promise holds for a forward to a handler that makes its tokens with `Stmt.fresh()`".
>
> What N costs the 90% user: every mock example in §4.4.10 changes. `Ok(Stmt.mock(1))` becomes `let a = Stmt.new()` in the builder, the builder gets `! State`, and the handler captures `a`. Or the author writes `Stmt.new()` in the clause, and the mock type changes to `Handler[DB ! State]`. PLT names that trap as its own concern. F has neither cost. The `State` row lands only on driver authors, and there are few of them.
>
> N's real wins are one fn instead of two, and closing the mock-to-mock case. Both are small next to touching every mock. Both options are free of the stale-key bug.
>
> Q3a, Debug.
>
> PLT says `Stmt.mock(3)` in text is a getter for the key. `Child` does exactly this today (fact 9). Its Debug prints `Child.mock(3)`, and the spec says the text "is not a format: code must not parse it". The same sentence works for `Stmt`. So D-text adds no new idea. It copies a decided rule.
>
> Sys and min say "Stmt(fresh) != Stmt(fresh)" misleads. That is true, and it is the rare case: two driver tokens in one assert. The common case is a mock test, `assert_eq(s, Stmt.mock(2))`. A failure prints `Stmt.mock(1) != Stmt.mock(2)`, and the fix is clear. With D-none the same failure prints nothing useful.
>
> That value exists only under F. Under N every token prints `Stmt(fresh)`, and sys and min are right that it says little. So: D-text if F wins; if N wins, I switch to D-none. Add the `Child` line: the text is not a format, and a golden test prints only `Stmt.mock` values.
>
> Writer notes I want under F: the mock-to-mock line above, the `Child` "not a format" line, and `finalize` keeping a "finalized" entry in the driver's map.
>
> stable, ready to vote

- **PLT:**

> PLT Phase D: N stays my pick on Q2. On Q3a I change: D-text if F wins, D-none if N wins.
>
> Q2, F or N. The F side admits the cost: two mocks that both use `Stmt.mock(1)` accept each other's tokens. Web, devops and aiml each answer it by narrowing the promise, so that "can never succeed" covers only a forward to a real driver. That is not a writer's note. It changes the decided first-Err bullet, which says the handler that did not make the Stmt "may be another connection, a mock, or an outer handler" (fact 10). Under F that sentence is false for a mock, and the spec would have to say "except when two mocks chose the same key". A rule with an exception for one maker is the soundness gap this ticket exists to close. N keeps the decided sentence true with no exception.
>
> The F side's main gain is that no mock example changes. Under N, the change is one line per token in the builder fn, and the clause row stays empty:
>
> ```blink
> fn scripted_db() -> Handler[DB] ! State {
>     let s1 = Stmt.new()
>     handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(s1) }
>         // ...
>     }
> }
> ```
>
> Fact 8 still holds for this handler. The only new text is `! State` on the builder, and the root holds `State`, so no test changes. Pre-1.0, that is a small edit to examples, set against an exception in a decided rule. To aiml's "one shape for both": Child keeps its mock because Child has a built-in handler that makes real Childs through an effect op. Stmt has none after the driver moves to a package. The two cases differ, so one shape is not owed.
>
> Q3a. Fact 9 refutes my getter argument. Child prints `Child.mock(3)`, and the spec still says "no getter", because Debug text "is not a format". The same holds for Stmt. So:
> - If F wins: D-text. `Stmt.mock(3)` carries real information, and it matches Child.
> - If N wins: D-none. Every N token prints the same `Stmt(fresh)`. That text adds nothing beyond the type name, and "Stmt(fresh) != Stmt(fresh)" misleads. Sys's point also holds: adding Debug later breaks nothing, and removing it does.
>
> So Q3a only matters if F wins, and then I join D-text. That should end the 3-3 split there.
>
> stable, ready to vote

- **DevOps/Tooling:**

> DevOps Phase D: I stay on F. On Q3a I stay on D-text, and I now tie it to F: if N wins, I vote D-none.
>
> Q2, F or N.
>
> The N side has one strong point: two mocks that both write `Stmt.mock(1)` accept each other's tokens. PLT says this breaks the decided first-Err bullet "by design". I do not agree. The owner Err is the answer of a handler that CHECKS ownership. Look at the spec's own `scripted_db()`: its clauses never look at `s`. They answer any Stmt. That is true under N too. A mock with `let a = Stmt.new()` and `fn step(s: Stmt) { Ok(101) }` still accepts a token from another mock. So for the common mock, N closes nothing. The hole matters only for a mock that compares `s == mine`. Under F, that author can call `Stmt.fresh()` and accept `State`. F gives the choice. N forces the cost on every mock.
>
> The N cost is not zero. Every mock builder in the spec changes: `fn scripted_db() -> Handler[DB]` becomes `-> Handler[DB] ! State`, and a `let` goes above the handler. That is the signature people copy most. Under F, only the few driver authors change. Both options have no stale-key bug, which was my main test. The tie breaks on who pays, and under F it is the driver author, not the mock author.
>
> Min's point that Eq on a serial is "identity in all but name" hits N and F alike. It does not pick between them. Child already has it (fact 9).
>
> Q3a, Debug.
>
> Sys and PLT are right about one case. Under N, every token prints `Stmt(fresh)`, so `assert_eq` fails with "Stmt(fresh) != Stmt(fresh)". With no key to show, the text misleads. So under N, D-none is the better choice.
>
> Under F the case is different. Most Stmt values in tests are mock tokens. They print `Stmt.mock(1) != Stmt.mock(2)`, which tells the author at once what went wrong. The misleading case happens only with two driver tokens, and a test seldom compares those.
>
> PLT says printing `Stmt.mock(3)` is a getter in text form. Fact 9 answers that: `Child` prints `Child.mock(3)` under the same "no getter" sentence. The text is not a format, and code must not parse it. One rule for both types.
>
> Min says no user has asked. The first failing `assert_eq` on a Stmt is the ask. "Adding Debug later is not breaking" is true, but until then that failure prints nothing useful.
>
> Position: Q2 F. Q3a D-text if F wins, D-none if N wins.
>
> stable, ready to vote

- **AI/ML:**

> AI/ML Phase D: no change. F over N, and D-text over D-none. A new fact settles Q3a.
>
> **Q3a: D-none breaks `assert_eq` on Stmt.** §2 (line ~2691, a 6-0 decision): `fn assert_eq[T: Eq + Debug](left: T, right: T)`. "There is no placeholder: a `T` with no `Debug` does not compile." So under D-none, `Stmt` has `Eq` but `assert_eq(s, Stmt.mock(1))` is a compile error. So is `assert_eq(db.prepare(q), Ok(Stmt.mock(1)))`, and so is `@derive(Debug)` on any struct that holds a `Stmt`. That is the first test a model writes for a mock: "prepare gave my token". An `Eq` type that `assert_eq` rejects is a trap that no other type in the language sets. The repair path is `assert(s == Stmt.mock(1))`, which a model reaches only after a failed compile.
> - To sys and plt ("`Stmt(fresh) != Stmt(fresh)` misleads"): that output needs an assert on two driver tokens. A driver test asserts on rows, not on tokens. The common case is mock tokens, and there `Stmt.mock(1) != Stmt.mock(2)` is exact. Child has the same shape (two unreaped Childs differ only by pid), and the spec accepts it there.
> - To plt ("the text is a getter for the key"): fact 9 answers this for Child in so many words. The text "is not a format: code must not parse it". The same sentence carries over. No code can get the key back as an `Int`.
> - To sys ("adding Debug later is not breaking"): true, but until then every mock test above fails to compile. That is a cost paid now, by every user, for a risk that is small.
>
> **Q2: F.**
> - To plt (F breaks the first-Err bullet because two mocks accept each other's `Stmt.mock(1)`): the spec's own `scripted_db()` ignores `s` in every clause, so under N it also answers a token it did not make. The bullet binds drivers, and it binds mocks only when they check. Under F, a mock that wants the check calls `Stmt.fresh()` and pays `State`, the same as under N. So F loses nothing there.
> - Sys, plt and min each answer the N cost with "mint up front in the builder". That changes every mock builder in the spec to `! State`: `scripted_db() -> Handler[DB] ! State`, plus a `let` per token and a captured binding. Under F, none of those lines change. A model learns from those examples. F keeps them as they are and keeps them the same as `Child`.
> - Min's identity worry also applies to N: N's only `Eq` is on the hidden serial. F at least gives `Stmt.mock(n)` a plain key equality that anyone can see.
> - Both F and N have no stale-key bug. The "two constructors" cost is one line, and `Child` already has it (spawn + mock).
>
> stable, ready to vote

- **Minimalism:**

> Minimalism D: I hold N on Q2. On Q3a I hold D-none under N, but I tie it to Q2: if F wins, I accept D-text.
>
> Q2, F or N.
>
> The F side makes one real point: under F no mock example changes. I grant it. But the cost of that is in the decided text, not in style. Fact 10 says the first Err goes to "a handler that did not make the Stmt ... a mock". Under F, an outer mock that wrote `Stmt.mock(1)` accepts an inner mock's `Stmt.mock(1)` as its own. All three F votes see this and each asks the writer to narrow the promise to "a forward to a real driver". So F does not close the gap this ticket opened. It moves the gap from driver-vs-mock to mock-vs-mock and asks the spec to say so. N has no such hole and needs no narrowing sentence.
>
> On "matches Child": Child has one real maker, the built-in handler, behind an effect op. Mocks there can never collide with a real Child. Stmt has many makers (every driver and every mock), so the Child pattern does not carry over. Copying a shape whose reason does not apply is not consistency.
>
> On "mock authors change nothing": under N the change is one line, `let a = Stmt.new()` in the builder, and the builder holds `State`, which roots hold for free. A one-line change to examples is a small price for a promise with no exceptions. Pre-1.0, breaking examples is allowed.
>
> Two constructors (F) against one (N) is still my core reason. N is the smaller language.
>
> Q3a, D-text or D-none.
>
> Under N, every token would print `Stmt(fresh)`, so a failing `assert_eq` reads `Stmt(fresh) != Stmt(fresh)`. That misleads (sys and plt are right). No Debug is better than a Debug that says two unequal things look the same. Adding Debug later does not break code; removing it does.
>
> Under F, the case is different. `Stmt.mock(3)` tells a mock author which key they wrote, and Child already does exactly this beside the same "no getter" sentence (fact 9). So plt's "Debug is a getter" point does not hold against Child's precedent. If F wins Q2, I vote D-text for F, to keep one pattern with Child. If N wins, D-none.
>
> If the re-vote must be one answer per question with no condition: Q2 N, Q3a D-none.
>
> stable, ready to vote

Before the re-vote, the moderator checked a citation from AI/ML and added fact 11 (§2.20 *Built-in Assertions*): `assert_eq` is `fn assert_eq[T: Eq + Debug](left: T, right: T, msg: Str = "")`, and "There is no placeholder: a `T` with no `Debug` does not compile." The panel voted Q3a twice: once for the case where F wins, once for N.

- **Systems:** N; D-text under F and under N

> Systems Phase D re-vote.
>
> Q2. Vote: N.
> Reasoning: Web and devops are right that a mock which ignores `s` accepts any token under both options. That is the author's choice, and it does not separate F from N. What separates them is the mock that does check. Under N, `s == mine` is always correct. Under F, a checking mock that uses `Stmt.mock(k)` can be wrong by design, and the fix is "use `fresh` instead", which is N with a second constructor beside it. On cost, the row compiles to nothing and the roots hold it. The only change is one `let` and `! State` on a builder, which pre-1.0 allows.
> Concern: every mock example in §4.4.10 changes. The writer must show the up-front `let` pattern, or readers will put `Stmt.new()` in a clause and be surprised by `Handler[DB ! State]`.
>
> Q3a-F. Vote: D-text.
> Reasoning: `Stmt.mock(3)` carries real information, and fact 9 shows that `Child` prints its key beside the same "no getter" sentence. Fact 11 makes Debug necessary in any case: without it `assert_eq` on a `Stmt` does not compile.
> Concern: two fresh tokens print the same, so the rare failure that compares two driver tokens reads oddly.
>
> Q3a-N. Vote: D-text. This is a change from my Phase D answer.
> Reasoning: Fact 11 changes it. With D-none, `assert_eq(db.prepare(q), Ok(s1))` does not compile, and neither does `@derive(Debug)` on any struct that holds a `Stmt`. A driver's own state types and a user's row wrappers would lose Debug just because they hold a `Stmt`. That cost hits every user, at once, and at compile time. Against it stands one misleading failure text (`Stmt(fresh) != Stmt(fresh)`) in the rare test that compares two tokens. A constant text costs nothing at run time and is stable in golden output. The spec should say the text is not a format and that `==` is the only way to compare.
> Concern: a user reads two identical printed tokens as equal values. The writer should put the "compare with `==`, not text" line next to the Debug rule.

- **Web/Scripting:** F; D-text under F and under N

> Web, Phase D re-vote.
>
> Q2. Vote: F.
> Reasoning: The mock-to-mock hole is real, but N does not close it for the common mock. The spec's own `scripted_db()` never looks at `s`, so under N it also answers a token it did not make. The owner Err binds a handler that checks. Under F, a mock that checks can call `Stmt.fresh()` and pay `State`, the same as under N. N puts `! State` and a `let` on every mock builder, which is the signature people copy most. F puts the cost only on driver authors.
> Concern: The writer must restate the first-Err bullet carefully, so that "a mock" means a mock that checks its tokens and does not read as a promise that `Stmt.mock` keys never collide.
>
> Q3a-F. Vote: D-text.
> Reasoning: Fact 11 decides it. `assert_eq` needs `Debug`, so under D-none `assert_eq(s, Stmt.mock(1))` does not compile, even though `Stmt` has `Eq`. That is the first test a mock author writes. `Stmt.mock(1) != Stmt.mock(2)` is exact, and `Child` already prints this way beside the same "no getter" sentence.
> Concern: People may parse the text. The spec must carry Child's "not a format" line.
>
> Q3a-N. Vote: D-text. I change from my Phase D answer (D-none under N), because of fact 11.
> Reasoning: Under N with D-none, `Stmt` has `Eq` but `assert_eq(s, a)` is a compile error, and so is `@derive(Debug)` on any struct that holds a `Stmt`. A Python or JS dev sees "this type can be compared but not asserted" and has no idea why. `Stmt(fresh) != Stmt(fresh)` is an odd failure message, but it compiles, it is true, and it points at the right line. A confusing message beats a compile error on the most common assert.
> Concern: Under N every token prints the same text, so a failing assert on two tokens gives the user no hint about which token is which.

- **PLT:** N; D-text under F and under N

> PLT Phase D re-vote.
>
> Q2: N.
> Reasoning: Web and devops are right that a mock which ignores `s` answers any token under either option. So the first-Err bullet binds handlers that check ownership. That point does not favor F. Under N, a mock that checks can never be fooled by a token it did not make. Under F, a checking mock is safe only if its author knows to avoid `Stmt.mock` and call `Stmt.fresh()`, and the spec must say so. One constructor whose guarantee holds for every checking handler beats two constructors, one of which carries a caveat. The cost is a `let` and `! State` on mock builders, which compiles to nothing.
> Concern: Every mock example in §4.4.10 and §4.7.2 must move to the up-front `let` pattern, or readers will put `Stmt.new()` in a clause and get `Handler[DB ! State]`.
>
> Q3a-F: D-text.
> Reasoning: Fact 9 answers my getter objection. Child prints `Child.mock(3)` beside the same "no getter" sentence, and the text is not a format. Fact 11 settles the rest: an Eq type with no Debug cannot be used in `assert_eq`.
> Concern: The writer must carry over Child's "not a format, no serial in the text" line, or people will parse it.
>
> Q3a-N: D-text. I change from D-none.
> Reasoning: Fact 11 decides it. `assert_eq` needs `T: Eq + Debug`, with no placeholder. Under D-none, `assert_eq(db.prepare(q)?, a)`, the first test a mock author writes, does not compile, and neither does `@derive(Debug)` on a struct that holds a Stmt. A failure that prints "Stmt(fresh) != Stmt(fresh)" is weak but true. It says the two are different tokens and does not claim they are equal. A compile error for a type that has Eq is a worse trap.
> Concern: Two unequal tokens print the same text. The spec should say that `==` compares tokens and the text never tells them apart.

- **DevOps/Tooling:** F; D-text under F and under N

> DevOps/Tooling Phase D re-vote.
>
> Q2. Vote: F.
> Reasoning: Neither option has the stale-key bug, so the tie breaks on who pays. Under F, the few driver authors carry `State`. Under N, every mock builder in the spec gets `! State` and a `let`, and those are the lines people copy most. The mock-to-mock case exists only for a mock that checks its token. The spec's own `scripted_db()` ignores `s`, and it accepts any token under N too. A mock that wants the check can call `Stmt.fresh()` under F.
> Concern: the writer must add one clear line that two mocks which both use `Stmt.mock(1)` accept each other's tokens. Without it, a reader trusts the first-Err bullet for mocks.
>
> Q3a-F. Vote: D-text.
> Reasoning: Fact 11 makes this concrete. With no Debug, `assert_eq(s, Stmt.mock(1))` does not compile, and that is the first test a mock author writes. `Stmt.mock(1) != Stmt.mock(2)` tells them at once what went wrong. It matches `Child`, with the same "the text is not a format" line.
> Concern: a test that compares two driver tokens prints `Stmt(fresh) != Stmt(fresh)`, which looks odd.
>
> Q3a-N. Vote: D-text. (Change from my Phase D reply, because of fact 11.)
> Reasoning: In Phase D I said D-none under N because every token prints the same text. Fact 11 changes the trade. Under D-none, `Stmt` has `Eq` but `assert_eq` rejects it at compile time, and so does `@derive(Debug)` on any struct or `Result` that holds a `Stmt`. No other `Eq` type sets that trap. `Stmt(fresh) != Stmt(fresh)` is weak output, but it still says "these differ" next to the line of the assert. A compile error that sends the user to `assert(s == a)` gives them even less on failure.
> Concern: users may read the matching texts as a bug in `assert_eq`. The spec should say once that two fresh tokens print the same text and that only `==` tells them apart.

- **AI/ML:** F; D-text under F and under N

> AI/ML Phase D re-vote.
>
> Q2. Vote: F.
> Reasoning: The spec's mock examples are the code models copy most. F keeps every one of them as written: `Ok(Stmt.mock(1))` inline, `scripted_db() -> Handler[DB]`, an empty clause row, and the same shape as `Child`. The mock-to-mock hole does not separate the options. The spec's own `scripted_db()` ignores `s`, so under N it too accepts a token it did not make. The owner Err comes from a handler that checks, under either option. Under F, a mock that wants the check calls `Stmt.fresh()` and pays the same `State` that N charges every mock.
> Concern: The writer must state the scope of "can never succeed" (a forward to a handler that makes tokens with `Stmt.fresh()`) in one plain line with an example. If not, the N side's reading of the first-Err bullet becomes a real ambiguity in the spec.
>
> Q3a-F. Vote: D-text.
> Reasoning: Fact 11: `assert_eq` needs `Eq + Debug`. With D-none, `Stmt` is `Eq` but `assert_eq(s, Stmt.mock(1))` does not compile, and that is the first test a model writes for a mock. Under F the text is useful too: `Stmt.mock(1) != Stmt.mock(2)` names the wrong key. The "no getter" worry is answered by `Child`'s own "not a format" line (fact 9).
> Concern: Someone may parse `Stmt.mock(3)` text in a test. Copy `Child`'s line that the text is not a format, and that golden tests print only `Stmt.mock` values.
>
> Q3a-N. Vote: D-text.
> Reasoning: Fact 11 applies under N too, and none of the Phase D replies answered it. N's mock pattern is `let a = Stmt.new()` plus a test that checks `prepare` gave `a`. With D-none, `assert_eq(s, a)` and `assert_eq(db.prepare(q), Ok(a))` are compile errors on a type that has `Eq`, a trap no other `Eq` type sets. `Stmt(fresh) != Stmt(fresh)` is a weak message, but it is true (the two differ), and it runs. A compile error that forces `assert(s == a)` costs a failed build for every model that writes the natural test.
> Concern: A user may read the identical texts as a bug in `==`. The spec should say that every fresh token prints the same text, and that `==` is the only way to tell two of them apart.

- **Minimalism:** N; D-text under F and under N

> Minimalism Phase D re-vote.
>
> Q2. Vote: N.
> Reasoning: one constructor does the job, and two constructors is the larger language. Devops and aiml are right that a mock which ignores `s` accepts any token under either option, so my "F leaves a hole" point is weaker than I said: it bites only a mock that checks. But under N a checking mock needs nothing extra, while under F it must know to use the second constructor and pay State anyway. The N cost is `! State` on each mock builder and a `let` per token, which roots hold for free and pre-1.0 allows.
> Concern: every mock example in the spec changes its builder signature, and authors who write `Stmt.new()` inside a clause will be surprised by `Handler[DB ! State]`.
>
> Q3a-F. Vote: D-text.
> Reasoning: `Stmt.mock(3)` carries the key the author wrote, matching Child's decided Debug under the same "no getter, not a format" rule (fact 9). Fact 11 also makes Debug needed for `assert_eq` at all.
> Concern: tests may match the text and expect it to tell two fresh tokens apart.
>
> Q3a-N. Vote: D-text. (Change from D-none.)
> Reasoning: fact 11 decides it. `assert_eq` needs `T: Debug`, and so does `@derive(Debug)` on any struct that holds a Stmt. Under D-none, `assert_eq(s, mine)` in a mock test and a derived Debug on a wrapper struct both fail to compile, for a type that has Eq. That trap costs more than a vague failure message. `Stmt(fresh) != Stmt(fresh)` is weak text, but it compiles and the assert is still correct.
> Concern: the same text for unequal tokens may confuse a reader of a failed assert; the spec should say the text holds no serial and is not a format.

| Question | Result |
|----------|--------|
| Q2 | F 3 (web, devops, aiml), N 3 (sys, plt, min). Tie |
| Q3a if F wins | D-text, 6-0 |
| Q3a if N wins | D-text, 6-0 (sys, web, plt, devops and min changed under N because of fact 11; aiml held) |

**User tiebreak on Q2: N.** The user gave no reason. With N, the D-text form is the one for N: every token prints `Stmt(fresh)`.

### Final Spec

```blink
// std.db
pub fn Stmt.new() -> Stmt ! State

// a mock makes its tokens up front, so its clause row stays empty
fn scripted_db() -> Handler[DB] ! State {
    let s1 = Stmt.new()
    handler DB {
        fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] { Ok(s1) }
        // ...
    }
}

// a driver makes a token in `prepare` and keeps it in a map
fn sqlite_handler(handle: Sqlite3)
    -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
    let mut stmts: Map[Stmt, Entry] = Map.new()
    handler DB {
        fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] {
            let raw = sqlite_prepare(handle, sql)?
            let s = Stmt.new()
            stmts.insert(s, Entry.Open(raw))
            Ok(s)
        }
        // ...
    }
}

test "two calls give two tokens" {
    let a = Stmt.new()
    let b = Stmt.new()
    assert(a != b)
    assert_eq(a, a)    // on a failure, each token prints as Stmt(fresh)
}
```

- **Q1 (6-0):** `Stmt.new()` carries `! State`. A call with an empty row is pure, and a compiler may reuse, merge, move or delete it, so a constructor with no row and no arguments could give two calls the same token. A private wrapper gets `State` by inference. A `pub fn` declares it (E0552). `State` has no run-time cost, and the roots hold it.
- **Q2 (3-3, user tiebreak N):** `Stmt.new()` is the one constructor. `Stmt.mock(id)` is removed. Each call gives a token that is not `==` to any other.
- **Q3 (no vote needed after Q2):** the owner is not in the `Stmt` value. Each handler keeps its own record of its tokens, usually a `Map[Stmt, ...]` that it captures. A token that is not in the record gets the owner Err. `finalize` keeps the token in the record and marks it as finalized, so a later operation gets "statement is finalized".
- **`Eq` and `Hash` (no panelist opposed):** a token holds a hidden serial that the runtime fills in, and `==` and `Hash` compare it as a value. There is no getter for the serial.
- **Q3a (6-0, D-text):** every token prints `Stmt(fresh)`. The text holds no serial and is not a format. Only `==` tells two tokens apart. `Debug` lets `assert_eq` and `@derive(Debug)` take a `Stmt`.
- **Q3b and Q4:** moot, because I dropped in Phase C.
- A clause that calls `Stmt.new()` puts `State` in the clause row of the handler, so a driver's handler type ends in `State`. A mock that makes its tokens before the `handler` expression keeps an empty clause row.
- Out of scope: whether a compiler may merge two calls of `Map.new()`, `Set.new()`, `Bytes.new()` or `StringBuilder.new()` (raised by PLT in Phase B and Phase C). That is a separate question.
