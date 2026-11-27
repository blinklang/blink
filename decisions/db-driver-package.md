[< All Decisions](../DECISIONS.md)

# Opening a Database: the SQLite Driver Is the Package blinklang/sqlite — Design Rationale

**Gap:** the owner moved the SQLite driver out of std: `std.db` holds only the `DB` interface (the effect, `Template[DB]`, `Row`, `DBError`, `Stmt`). The spec still used `with db.connect(path)? { }` as the std way to open SQLite in §4.4, §4.7, §5 and §9.1. The duplicate-apis rows named it as the rewrite target for `db_connect`, `sqlite_connect` and `sqlite_handler`, and §9.1 gave "the standard SQLite driver" its own exemption and binding rows. Once std holds no driver, none of that text is true:

```blink
import std.db

fn run() -> Result[Int, DBError] {
    with db.connect("app.db")? {    // std.db has no driver: what does a program write here?
        count_users()
    }
}
```

**Already decided (not on the ballot):** the owner direction that std.db holds only the interface and that the bindings, the C shim, the vendored sqlite3 source and the audits move to a package; the scoped effect handler rule (a `Scoped` type whose `Context` is `Handler[E]`, keyed on the type, never on a name); the foreign-row rules of §9.1; the `Stmt` owner checks (§4.4.10); the duplicate-apis removals; pre-1.0 removals ship at once. How a package makes `Stmt` values is a separate question.

**Names.** The panel wrote `BlockHandler`, the name of the trait in `lib/std` and in the brief. The spec names the trait `Scoped` (§4.7.2), so the spec text uses `Scoped`. The quotes below keep `BlockHandler`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round; all six said they were stable. Phase D did not run (both questions 6-0).

#### Phase A — Independent proposals

All six proposed that `db.connect` leaves std, with no std stub, no driver registry and no Driver trait: a driver package exports its own `connect`. All six rejected `db.connect("sqlite:...")` with a driver lookup at run time.

- **Systems:**

> Sys Phase A: db.connect leaves std. Each driver package exports its own concrete `connect`. I reject a std `db.connect(url)` that looks up drivers at run time.
>
> **Proposal S1: driver-qualified connect, static dispatch**
>
> Q0: The spec changes. `std.db` has no `connect`, and `std.db_sqlite` and `std.db_stmt` leave std. There is no std stub and no driver registry.
>
> Q1: The convention is a free fn named `connect` in the driver's top module. It returns `Result[<Driver>.Connection, DBError]`, and `Connection` impls `BlockHandler` with `Context = Handler[DB]`. The module name qualifies the call: `sqlite.connect(p)`, `pg.connect(url)`. The `with` site knows the concrete type, so `enter` and `exit` monomorphize to direct calls. There is no vtable and no lookup by string.
>
> blink.toml:
> ```
> [dependencies]
> blinklang/sqlite = "0.1"
> ```
> ```blink
> import std.db
> import blinklang.sqlite
>
> fn count_users(path: Str) -> Result[Int, DBError] ! DB, FS, Time.Read, Time.Sleep, Rand {
>     with sqlite.connect(path)? {
>         let rows = db.query(t"SELECT id FROM users")?
>         Ok(rows.len())
>     }
> }
> ```
> (The effect row is whatever that package's bindings declare. It is not new.)
>
> The org must not be `blink`, because `blink.ffi` and `blink.core` are already compiler pseudo-modules. `import blink.sqlite` would collide with them.
>
> Q2: The three rows point at `with sqlite.connect(path)? { }` from the driver package. The fix rewrites the call and the import only when the package is already in blink.toml. Otherwise the fix is not machine-applicable, and the help prints the exact `[dependencies]` line. The compiler must not add a dependency on its own, because that changes the build graph and fetches code. `import std.db_sqlite` and `import std.db_stmt` get the existing unknown-module error, with the same help line.
>
> Q3: Examples about DB semantics (owner checks, `Scoped.exit`, transactions, E0500 at the `with`) use `with mock_db(...)` where no disk is needed. They use `sqlite.connect` with an explicit import line where a real file matters, such as the FS-exemption example. Every example that calls `sqlite.connect` must show its import, so it reads as a package call and not as a std call.
>
> §9.1: the "standard SQLite driver" exemption becomes a general rule. A handler that calls foreign code does its own I/O, and an `FS` handler does not see it. This was already true for any FFI handler. It is not a special grant for std. The rows of the sqlite bindings move into the package's audit, and the spec keeps one short example.
>
> **Tradeoffs (systems)**
> - Pro: A binary links sqlite only when the program depends on it. The compiler drops a 9.7 MB vendored C tree and a CI system dep. The objcache builds the sqlite C sources once for each consumer.
> - Pro: The dispatch is fully static. A `with` on a concrete `Connection` costs what it costs today.
> - Con: Changing the driver changes the call site (`sqlite.connect` to `pg.connect`). That is the honest cost: the effect rows and the error modes are different. Code that must not care about the driver takes a `Handler[DB]`, or runs under a `with` that the caller installs.
> - Con: A dependency line is required for a "hello DB" program. That is acceptable, because the `with` row already shows foreign I/O.
>
> Rejected: `db.connect("sqlite://app.db")` with drivers registered at run time. It needs global mutable state, init-order side effects and a call through a function pointer. Every driver would link even when unused, or the program would fail at run time on an unknown scheme instead of at compile time.
>
> **Cross-language:** Go's `database/sql` uses `sql.Open("sqlite3", dsn)` plus a blank import that registers the driver. That is a string lookup at run time, and a missing driver fails at run time. Rust's `rusqlite::Connection::open` and `sqlx::SqlitePool` are concrete types, and the call names the driver. S1 follows the Rust model.

- **Web/Scripting:**

> Web Phase A proposal: the driver's module name is the noun, and every driver exports `connect`.
>
> **Proposal W1: `sqlite.connect(path)` from a first-party package**
>
> Q0: Yes, the spec changes. `db.connect` leaves std. If std keeps a `connect` with no driver behind it, users will assume it works and get a confusing error.
>
> Q1: Each driver package exports `pub fn connect(...) -> Result[Connection, DBError]`, where `Connection` is the package's own BlockHandler type. The import's last segment is the driver name, so the call reads `sqlite.connect(path)` or `postgres.connect(url)`. The arguments belong to each driver. std does not fix a shared signature.
>
> What the user writes:
> ```toml
> # blink.toml
> [dependencies]
> blinklang/sqlite = "0.1"
> ```
> ```blink
> import std.db
> import blinklang.sqlite
>
> fn count_users() -> Int ! DB.Read {
>     let rows = db.query("SELECT id FROM users")?
>     rows.len()
> }
>
> fn main() ! IO, DB {
>     with sqlite.connect("app.db")? {
>         io.println("{count_users()}")
>     }
> }
> ```
> Business code imports only `std.db` and the DB effect. Only `main`, where the handler is installed, imports the driver.
>
> Errors:
> - `db.connect(...)`: the existing unknown-member error, with a help line: "the SQLite driver is a package: add `blinklang/sqlite` to blink.toml and call `sqlite.connect(path)`". That help line will stop most of the Stack Overflow questions.
> - `import blinklang.sqlite` without the dependency: the existing unresolved-import error, with help to add the blink.toml line.
>
> Org name: do NOT use `blink/sqlite`. `blink.*` is already the pseudo-module namespace (`blink.ffi`, `blink.core`). A `blink.sqlite` that is a real package would confuse people and the resolver. Use any org outside `std` and `blink`. `blinklang` is one example.
>
> Q2: The duplicate-apis rows for `db_connect`, `sqlite_connect` and `sqlite_handler` change to point at `with sqlite.connect(path)? { }` from the package. The fix changes the call and adds `import blinklang.sqlite`. If blink.toml has no dependency on the package, the fix cannot be applied automatically. The note says to add the dependency first. `sqlite_handler(handle)` stays not machine-applicable for the same reason as now: its argument is a handle, not a path.
>
> Q3: Most spec examples should use `with mock_db(...)` or an inline `handler DB { }`. Those need no driver, and they teach the effect, not SQLite. Keep one example in §4.7.2 that shows the real path end to end: the blink.toml line, the import and `sqlite.connect`. Examples that need a real database use `sqlite.connect` and give no other explanation. The §9.1 "standard SQLite driver" exemption leaves std. It becomes a package-audit matter (a native dep doing its own file I/O), not a std rule. §10.7.1 removes "SQLite driver" from the std.db row.
>
> **Rejected: `db.connect("sqlite:app.db")` in std with a driver registry**
> This is Go's `database/sql` model: a blank import `_ "github.com/mattn/go-sqlite3"` registers the driver. It is the best-known source of "sql: unknown driver" questions. It is a runtime failure, it uses a string for dispatch, and it hides an import side effect. W1 is checked when the program compiles.
>
> **Tradeoffs**
> - Plus: Python devs already know this shape (`sqlite3.connect(path)`, `psycopg.connect(url)`). It reads like the spec's current pattern, with one word changed.
> - Plus: `db.*` stays "the interface" and `sqlite.*` is "the implementation". A new user can see the difference.
> - Minus: Hello-world with a database now needs a blink.toml edit. That is a small cost, and the error's help text covers it.
> - Minus: Drivers can drift. One driver might call its function `open`. A spec convention, "a DB driver exports `connect`", stops that.

- **PLT:**

> PLT Phase A: remove db.connect from std; a driver package exports `connect`; the duplicate-apis rows point at the package and lose machine-apply; the §9.1 std exemption goes away.
>
> **Q0: the spec must change.** A std `db.connect` with no driver behind it has no meaning: its row, `Handler[DB ! R]`, would have no R. The only way to keep it is a run-time dispatch on the path or URL scheme to registered drivers. That loses row precision: the `with` would have to charge the union of all drivers' rows, or charge a row it cannot know at compile time. Reject. The scoped-handler vote already keys on the type, not on a name, so a package `Connection` with `impl BlockHandler` (`Context = Handler[DB ! R]`) works with no language change. The language rule stays the same. Only the std surface changes.
>
> **Q1: the package exports `connect`**, so the call reads `sqlite.connect(path)`. This is a convention, not a rule. The shape is `fn connect(...) -> Result[C, DBError]` where `C: BlockHandler` with `Context = Handler[DB ! R]`. Driver errors stay `DBError` from std, so error code works with every driver. Do not add a `Driver` trait to std. The BlockHandler bound is already the interface (YAGNI).
>
> ```blink
> // blink.toml: [dependencies]  blinklang/sqlite = "0.1"
> import std.db
> import sqlite
>
> fn count_users(path: Str) -> Result[Int, DBError] ! DB.Read {
>     let rows = db.query("SELECT id FROM users")?
>     Ok(rows.len())
> }
>
> fn main() -> Result[Int, DBError] {
>     with sqlite.connect(path: "app.db")? {
>         count_users("app.db")
>     }
> }
> ```
>
> What breaks: `import std.db_sqlite` and a call to `db.connect` both fail with the existing unresolved-import and UndefinedFunction errors. No new code.
>
> **Q2: rows** `db_connect`/`sqlite_connect`/`sqlite_handler` → `with sqlite.connect(path)? { }` from the driver package. Set machine-applicable to **no** for all three, and take `sqlite_handler` off the machine-rewrite list. A fix that changes one source file cannot add a blink.toml dependency. Also, `sqlite_handler(handle)` → `connect(path)` changes what the argument means (a handle is not a path), so it was never a rewrite that keeps meaning. The rows stay so that the removed names still get a hint.
>
> **Soundness point for §9.1 (important).** The "second exemption: the standard SQLite driver" is a trust grant to std code. If the driver moves to a package and that grant does not follow it, a package can do file I/O that an FS handler never sees, under a row nobody audited. Delete the exemption. The package's bindings must declare their rows (FS.Read/Write/Delete, Time.*, Rand) under the normal FFI and audit rules like any other package. `with sqlite.connect(p)? { }` charges the package's declared row. "An FS handler does not see SQLite file I/O" then reads as a general fact about foreign code, not a std privilege. The row table becomes an example of a package driver, not normative std content.
>
> **Q3: examples.** The typing rules must not depend on a package the spec does not define. So: (a) examples about effect semantics (§4.4.x, §4.7.x, sections/05) use `with mock_db(...)` or an inline `handler DB { }`; (b) where a real disk is the point (§9.1, the one "open a real database" example), use one fixed package name everywhere, marked as illustrative.
>
> Tradeoffs: users pay one dependency line. We gain an honest row for each driver, a smaller trusted base, and a std that is only the interface (the same split as Haskell's `persistent` with its `-sqlite` backends, and Rust's `sqlx` drivers behind a trait). The cost: there is no zero-config "open SQLite" in std. I accept that cost for soundness.
>
> ---
> PLT correction to my Phase A example: the example has two errors. Use this one in its place:
>
> ```blink
> import std.db
> import sqlite
>
> fn count_users() -> Result[Int, DBError] ! DB.Read {
>     let rows = db.query("SELECT id FROM users")?
>     Ok(rows.len())
> }
>
> fn run() -> Result[Int, DBError] {
>     with sqlite.connect("app.db")? {
>         count_users()
>     }
> }
> ```
>
> The position does not change.

- **DevOps/Tooling:**

> DevOps/Tooling Phase A: db.connect leaves std. Each driver package exports `connect`, and an old name gets a diagnostic that names the package and `blink add`.
>
> **Q0: the spec changes.** If `db.connect` stays in std as a shell with nothing behind it, either it fails at run time with "no driver" (the Go `sql.Open("sqlite3", ...)` trap, where a missing `_` import becomes a runtime error) or it needs a string-keyed driver registry. A registry hides the driver from the type checker and the LSP. Today the handler type tells the compiler which driver runs, so keep that. std.db keeps the interface only. Users import the connect fn from the driver package.
>
> **Q1: name.** The package is `blinklang/sqlite`, module `sqlite`, fn `sqlite.connect(path) -> Result[sqlite.Connection, DBError]`. Every driver uses the same verb: `postgres.connect(url)`, `mysql.connect(url)`. Then typing `sqlite.` in the LSP shows `connect` first, and code moves between drivers by changing one word. Do not use the org `blink/`: §10.7 reserves `blink.*` (`blink.ffi` and `blink.core` resolve as inert pseudo-modules), so `import blink.sqlite` would collide.
>
> ```
> # blink.toml
> [dependencies]
> blinklang/sqlite = "0.1"
> ```
> ```blink
> import blinklang.sqlite
>
> fn main() ! IO, DB {
>     with sqlite.connect("app.db")? {
>         let rows = query_users()?
>         io.println("{rows.len()} users")
>     }
> }
> ```
>
> **Q2: rewrite rows.** A `--fix` changes source only. It never edits blink.toml or fetches code. The rows for `db_connect`, `sqlite_connect`, `sqlite_handler` and `db.connect` point to `with sqlite.connect(path)? { }` from `blinklang/sqlite`. The fix applies only when the manifest already has that dependency. In that case it rewrites the call and adds the import. When the dependency is missing, nothing is machine-applicable, and the diagnostic says so:
>
> ```
> error[ModuleNotFound]: module `std.db_sqlite` not found
>  --> main.bl:1:8
>   = note: the SQLite driver moved out of std to the package `blinklang/sqlite`
>   = help: run `blink add blinklang/sqlite`, then use `with sqlite.connect(path)? { }`
> ```
>
> An undefined `db.connect` reads the same: "std.db has no driver; see `blinklang/sqlite`." The table of moved names stays fixed in the compiler, the same way Go reports "package X is not in std". This reuses E1200 and the existing undefined-function code. It adds no new diagnostic name, and it fits pre-1.0: break now, with one CHANGELOG line.
>
> **Q3: spec examples.** Most DB examples in §4.4, §4.7 and §5 show effect semantics, not SQLite. Switch those to `handler DB { }` or `mock_db(...)`. They then compile with no dependency, and doc tests in CI need no native C build. A few examples (§4.7.2 scoped handlers, one end-to-end in §5) show `sqlite.connect` with the blink.toml line next to them, so a reader sees the whole setup. §9.1 "the standard SQLite driver" exemption can no longer name std modules. Its rows move to the package's audit, or the rule becomes general for any package driver. That is the next Stmt/driver ticket's question; flag it there.
>
> **Tradeoffs.**
> - Plus: the LSP knows which driver is in play, there is no runtime registry error, and the doc examples need no C toolchain.
> - Minus: hello-world with a DB takes one more step (`blink add`). Python ships sqlite3 in std, and new users feel that gap. The diagnostic help line covers most of the cost.
> - Minus: the registry does not exist yet, so `blink add blinklang/sqlite` resolves through the git fallback for now. The help line must still work in that case, so the diagnostic should print the exact `blink add` argument that works today.
>
> Cross-language: Rust std has no SQL. `rusqlite::Connection::open` and `sqlx` each name their own connect fn. Go has the registry trap described above. Elixir's Ecto adapters are packages behind one interface, which matches this proposal.

- **AI/ML:**

> AI/ML Phase A: the driver package exports `connect`, users write `with sqlite.connect(path)? { }`, and std.db has no `connect` at all.
>
> **Proposal A (my pick): `<driver>.connect`, named by the package**
>
> Q0: The spec changes. `db.connect` leaves std. No stub, no dispatch on a URL scheme.
> Q1: Each driver package exports `pub fn connect(...) -> Result[Connection, DBError]`, where its `Connection` implements `BlockHandler` with `Context = Handler[DB]`. The module name tells you which driver it is. The fn name is always `connect`.
> Q3: The project publishes one canonical package with a real name, for example `blinklang/sqlite`. The spec uses only that name and never "acme/sqlite" or "a driver such as".
>
> ```toml
> [dependencies]
> blinklang/sqlite = "0.1"
> ```
> ```blink
> import std.db
> import blinklang.sqlite
>
> fn count_users(path: Str) -> Result[Int, DBError] ! DB, FS {
>     with sqlite.connect(path)? {
>         let rows = db.query("SELECT id FROM users")?
>         Ok(rows.len())
>     }
> }
> ```
>
> What compiles and what errors:
> - With old code, `db.connect(p)` is an unknown-member error. It needs a duplicate-apis row: `db.connect(path)` in `std.db` -> `sqlite.connect(path)`. Fix: "no". The help line names the `blink.toml` line and the import. Models trained on today's spec WILL write `db.connect` for a long time. A bare "no member connect" makes them guess. A help line that names the exact package fixes it in one try.
> - Q2: the rows for `db_connect`, `sqlite_connect` and `sqlite_handler` point at `with sqlite.connect(path)? { }`. Fix: "call yes, dependency no". The fix rewrites the call and the import, and the help line names the dependency to add.
>
> Spec examples (Q3):
> - When an example shows the DB effect, Template, Stmt or handler rules, it uses `with mock_db(...)` or `handler DB { }`. Those need no driver, so they stay self-contained and teach only std.
> - When an example opens a real file (scoped handlers, the FS exemption, cleanup on exit), it uses `sqlite.connect` and shows BOTH `import blinklang.sqlite` and the toml line, at least the first time in each section. Models copy snippets whole. A snippet with `sqlite.connect` and no import teaches them that it is std.
>
> Tradeoffs for model learning:
> - `sqlite.connect(path)` is the shape in the training data: Python `sqlite3.connect(path)`, `psycopg.connect(...)`. A first try lands on it with no spec lookup.
> - One fixed name for each driver is better than a generic entry point. If the spec has no real canonical name, models make up `std.sqlite`, `db.sqlite.open` and `sqlite.open`, and each one costs a repair round.
> - Cost: two extra lines (toml and import) for the common case. That is acceptable, and the duplicate-apis help line makes that cost visible.
> - §9.1 "standard SQLite driver" exemption: it can no longer name std modules. The exemption must belong to the package's declared native dependency. That is the systems panelist's call. I only ask that the rule is general, so a Postgres package gets the same rule with no new spec text.
>
> **Proposal B (rejected): keep `db.connect(url)` in std and dispatch on the scheme or a registered driver**
> It looks easiest for models, because no names change. But it is a name-keyed lookup, which goes against the "keyed on the type, never on a name" vote. A missing driver becomes a runtime Err, not a compile error, and models cannot repair a runtime Err from the compiler output.
>
> Cross-language: Go's `sql.Open("sqlite3", dsn)` with a blank-import driver is the known failure. LLMs often leave out the `_` import, and the error only shows at run time. Rust `rusqlite::Connection::open` and Python `sqlite3.connect` fail at compile time or import time. Blink should do what Rust and Python do.

- **Minimalism:**

> Minimalism Phase A: db.connect leaves std, and "connect" becomes a naming convention, not a rule; examples use mocks.
>
> PROPOSAL M1: remove it, add nothing new.
>
> Q0. The spec changes. A std `db.connect` that holds no driver can only fail or dispatch, and dispatch needs a registry or a Driver trait. Both add surface that nothing needs today (YAGNI). §10.7 already says that if a module does not belong in std, it is an ecosystem package with no `std.` prefix. The driver leaves std, and the spec follows that rule. Also remove: the §10.7.1 words "SQLite driver", the §9.1 "standard SQLite driver" rows, and the "second exemption". The general §9.1 rule (a handler that calls foreign code declares what the code touches) already covers a package driver. The exemption becomes that package's audit, not language text.
>
> Q1. No language rule, only a convention: a driver module exports `connect(...) -> Result[Connection, DBError]`, where `Connection` is a BlockHandler whose Context is `Handler[DB]`. The module name is the namespace, so each driver can use the plain name `connect`. The compiler checks nothing new, because the scoped-handler vote already keys on the type, not the name.
>
> Q2. Keep the rows so a porting user learns where the names went. Point them at "a driver package's `connect`, for example `with sqlite.connect(path)? { }`". Remove `sqlite_handler` from the machine-applicable list: a fix-it cannot add a blink.toml dependency, so an automatic rewrite gives code that does not compile. An old call gets the existing undefined-function error plus the table note. No new code.
>
> Q3. Most spec examples teach the DB effect, not SQLite. Rewrite them to use `with mock_db(...) { }` or `handler DB { }`, which need no driver. Show a real open in one place only (§4.7.2), with the toml line and the import, and use a first-party package (name for the owner to pick; I use `blink/sqlite` below).
>
> ```toml
> [dependencies]
> blink/sqlite = "0.1"
> ```
>
> ```blink
> import std.db
> import blink.sqlite
>
> fn user_count(path: Str) -> Result[Int, DBError] {
>     with sqlite.connect(path)? {
>         count_users()?
>     }
> }
>
> test "count with no driver" {
>     with mock_db(rows: []) {
>         assert_eq(count_users(), Ok(0))
>     }
> }
> ```
>
> `db.connect(p)` after the change gives the existing undefined-function error, with the duplicate-apis note.
>
> Tradeoffs:
> + std gets smaller and honest: interface only, no stub fn and no registry.
> + No new language rule, diagnostic or trait.
> + Examples that use mocks are shorter and run with no native dep, which is better training data.
> - The convention is not enforced, so a driver can name its fn `open`. I accept that risk: a convention plus one first-party example is enough, and we can add a rule later if drivers drift.
> - A real-DB example now needs a toml line. That is the true cost of the owner's decision, and the spec should show it.
>
> Cross-language: Python DB-API (PEP 249) is exactly this, a convention that each driver module exposes `connect()`, with no language support, and it has worked for 25 years. Go's `sql.Open("sqlite3", dsn)` with a blank-import driver registry is the pattern to avoid: it uses string keys, global state and a hidden init side effect. Rust (rusqlite, sqlx) also uses one connect per crate and no std registry.

#### Phase B — Round 1 (variations V1-V5)

The moderator merged the six proposals into one option and listed five variations that differ in behavior:

- **V1** — the package name and import path that the spec uses (`blinklang/sqlite`, `blink/sqlite`, or a bare `import sqlite`).
- **V2** — the duplicate-apis fix for `db_connect`, `sqlite_connect` and `sqlite_handler`: machine-applicable when blink.toml lists the package, or a suggestion always.
- **V3** — a new row or help line for `db.connect` itself.
- **V4** — the §9.1 "second exemption: the standard SQLite driver": delete it, or make it a general rule.
- **V5** — how many spec examples open a real database, and what they show.

The moderator added two facts. §10.7 reserves `blink.*` for compiler pseudo-modules that resolve as inert no-ops, so `import blink.sqlite` would compile and do nothing. `sqlite_handler` was already in the list of rewrites whose fix is a suggestion.

Position shifts: Systems moved to PLT on V2 and to PLT and Minimalism on V4. Minimalism moved to `blinklang/sqlite` on V1. PLT dropped the bare `import sqlite` on V1. DevOps moved to PLT on V2 and to fewer real examples on V5. Web/Scripting moved to PLT on V2. AI/ML kept a conditional fix on V2 in this round and moved to the unconditional suggestion in Phase C.

- **Systems:**

> Sys Phase B1: positions on V1-V5. I am stable and ready to vote.
>
> V1: The package is `blinklang/sqlite`, imported with `import blinklang.sqlite`. The moderator's fact makes `blink.sqlite` worse than a name collision. Every `blink.*` import resolves as an inert no-op, so `import blink.sqlite` compiles silently and then `sqlite.connect` fails far from the cause. I also reject a bare `import sqlite`, because it breaks the org/name to org.name mapping in §8.9.7. The spec uses this one name everywhere and never says "a driver such as".
>
> V2: I change my position to plt's. The fix is not machine-applicable for any of the three rows. I drop my "applies when the dependency is present" idea. A fix that is only sometimes applicable is extra machinery, and `sqlite_handler` is already in the list of suggestion-only fixes. The fix is a suggestion, and its help line names the dependency line and the new call:
> ```
>   = help: add `blinklang/sqlite` to [dependencies], `import blinklang.sqlite`, then use `with sqlite.connect(path)? { }`
> ```
>
> V3: There is no new row and no new code. `db.connect` gets the existing undefined-function error, and `import std.db_sqlite` and `import std.db_stmt` get the existing ModuleNotFound error, each with the same help line. A help note costs nothing and fits pre-1.0.
>
> V4: I change my position to plt and min: delete the exemption. The general rule at sections/07 line 906 ("A handler for a built-in interface effect ... can call foreign code ... the row names what the foreign code touches") already covers a package driver. The package declares its rows under the normal FFI and audit rules. If the general text also states that an FS handler cannot see foreign I/O, then std needs no SQLite-specific text at all.
>
> V5: The spec has one full example in §4.7.2, with the toml line, the import and `with sqlite.connect(p)? { }`. Every other DB example uses `mock_db` or `handler DB { }`. Any other example that needs a real file shows the import line, so the call never reads as a std call.
>
> stable, ready to vote

- **Web/Scripting:**

> Web Phase B round 1: my positions on V1-V5, and I am stable, ready to vote.
>
> V1: `blinklang/sqlite`, imported as `import blinklang.sqlite`. Against `blink/sqlite`: §10.7 says an import from `blink.*` resolves as an inert no-op. So `import blink.sqlite` compiles and does nothing, and the user then gets a confusing "unknown `sqlite`" error further down. That would generate a lot of Stack Overflow questions. Against plt's bare `import sqlite`: §10.5 maps `org/name` to `org.name`, so `import sqlite` does not match a `blinklang/sqlite` dependency. The spec would teach an import that does not resolve. I agree with aiml: use one fixed name everywhere, and do not hedge with "a driver such as".
>
> V2: I am moving to plt's position. For all three rows, make the fix a suggestion, not machine-applicable. Applicability that depends on what is in blink.toml means the same source gets different fix behavior on two machines. That is harder to explain than "this one is a suggestion". It also matches how `sqlite_handler` works today. The help line prints the dependency line:
> ```
> error[ModuleNotFound]: module `std.db_sqlite` not found
>   = help: run `blink add blinklang/sqlite`, then use `with sqlite.connect(path)? { }`
> ```
>
> V3: Add a duplicate-apis row for `db.connect(path)` that points to `sqlite.connect(path)`, with fix "no" (aiml). The help comes from the existing row machinery, so there is no new diagnostic. `db.connect` is in the spec, in llms.md, and in model training data. Users will type it. I want them to see the help line, not a bare UndefinedFunction error.
>
> V4: Make it a general rule (sys/aiml). Foreign code that a handler calls does its own I/O, and an FS handler does not see it. The SQLite rows move to the package's audit. A Postgres package then needs no new spec text.
>
> V5: §4.7.2 has one full example with the toml line, the import and `sqlite.connect`. Every other example that calls `sqlite.connect` shows `import blinklang.sqlite` (sys), so no reader takes it for std. Everything else uses `mock_db` or `handler DB { }`.
>
> ```blink
> import std.db
> import blinklang.sqlite
>
> fn run() -> Result[Int, DBError] {
>     with sqlite.connect("app.db")? {
>         count_users()
>     }
> }
> ```
>
> stable, ready to vote

- **PLT:**

> PLT Phase B round 1, positions on V1-V5:
>
> **V1:** `blinklang/sqlite`, `import blinklang.sqlite`. I drop my bare `import sqlite`, because §10.5 maps an import path to `org/name`. I object to min's `blink.sqlite`, and the reason is soundness, not taste. §10.7 says an import from `blink.*` resolves as a recognized no-op: it is accepted, it does nothing, and it never gives ModuleNotFound. So `import blink.sqlite` would compile and bind nothing, and the error would surface later at `sqlite.connect` as a confusing undefined name. A namespace cannot be both an inert language namespace and a home for packages.
>
> **V2:** All three rows are suggestions, never machine-applied, even when blink.toml already has the package. Line 649 already makes `sqlite_handler` a suggestion only, because the fix changes the code's shape. `db_connect(path)` becomes `with ...? { }`, which is also a shape change (a call turns into a block), so the same rule covers it. `sqlite_handler(handle)` changes what the argument means. A "machine-apply when the dep is present" rule would still rewrite code into a different meaning. The help line prints the dependency line, as in devops's output, and I accept that output.
>
> **V3:** No new diagnostic code. Add a help line on the existing undefined-name error for `db.connect`. A duplicate-apis row for `db.connect` is fine if it has Fix: no.
>
> **V4:** Delete the std exemption in this change. Do not defer it. Today it gives trust to `std.db_sqlite` and `std.db_stmt`, and those modules will not exist. Spec text that trusts modules that do not exist is wrong text. sys's wording is the same as my position: "a handler that calls foreign code does its own I/O, and an FS handler does not see it" is a general fact, and the package declares its rows under the normal FFI/audit rules. The `with` charges the declared row. The Stmt ticket keeps only the question of how the package makes Stmt values.
>
> **V5:** Two examples: §4.7.2 and §9.1. Each shows the toml line and `import blinklang.sqlite`. All other DB examples use `mock_db` or `handler DB { }`.
>
> ```blink
> // blink.toml  [dependencies]  blinklang/sqlite = "0.1"
> import std.db
> import blinklang.sqlite
> ```
>
> Stable, ready to vote.

- **DevOps/Tooling:**

> DevOps/Tooling, Phase B1, positions on V1-V5: stable, ready to vote.
>
> **V1: package name.** Use `blinklang/sqlite` with `import blinklang.sqlite`. `blink/sqlite` is worse than a name clash. Under §10.7, `import blink.sqlite` resolves as an inert no-op: no error, nothing bound. The user then gets an undefined `sqlite` at the call site, and nothing points back to the import. I reject plt's bare `import sqlite`: §10.5 maps `org/name` to `import org.name`, so a spec example would teach an import path that does not resolve.
>
> **V2: the fix.** I move to plt's position: machine-applicable is "no" for all three. The moderator's fact settles it, because `sqlite_handler` is already suggestion-only. A fix whose output depends on the state of blink.toml is hard to test and gives different results in CI and on a laptop. One rule is simpler. The help line prints the toml line, the import and the call:
> ```
>   = help: the SQLite driver is the package `blinklang/sqlite`; run `blink add blinklang/sqlite`, add `import blinklang.sqlite`, then write `with sqlite.connect(path)? { }`
> ```
>
> **V3: `db.connect`.** Add no new code. A call to `db.connect` keeps the existing undefined-function error, and `import std.db_sqlite` keeps the existing unknown-module error. Both get the help line above. Add one duplicate-apis row for `db.connect(path)` in `std.db`, so the help text comes from the table and not from separate strings.
>
> **V4: §9.1 exemption.** Delete the exemption. The general FFI rule covers it: foreign code does its own I/O, and an FS handler does not see it. The binding rows move to the package audit. A Postgres package then follows the same rule with no new spec text.
>
> **V5: real-database examples.** I move to fewer: one example in §4.7.2 and the §9.1 example. Each one shows the toml line and the import, so neither reads as a std call. All other examples use `mock_db(...)` or `handler DB { }`, so doc tests need no native build in CI.

- **AI/ML:**

> AI/ML Phase B1: blinklang/sqlite; fix applies only with the dep; help line on db.connect; general exemption; few, complete examples. Stable, ready to vote.
>
> V1, the package name: `blinklang/sqlite`, written `import blinklang.sqlite`.
> - Against `blink/sqlite`: the fact from §10.7 decides it. `import blink.sqlite` resolves as an inert no-op and never gives ModuleNotFound. The import passes without a word, and the model gets a confusing "unknown `sqlite`" error at the call, far from the real mistake. That is the worst case for self-repair.
> - Against plt's `import sqlite`: the §8.9.7 mapping gives `blinklang.sqlite`, so the spec would teach an import that does not resolve. Also, a name "marked as illustrative" makes models invent their own names. One real name, used the same way everywhere.
>
> V2, the fix for old names: I take the sys/devops/web form, which makes my Phase A answer precise. The call and import rewrite is machine-applicable only when blink.toml already lists the package. If it does not, the fix is not machine-applicable and the help prints `blink add blinklang/sqlite`. An agent loop that applies every machine-applicable fix must never get code that still fails to compile.
>
> V3, `db.connect` itself: the existing unknown-member/UndefinedFunction error, plus a help line (web/devops). This needs no new code. Old training data makes `db.connect` the most likely model mistake for a long time, so it is the one place a help line pays for itself the most.
> ```
> error[UndefinedFunction]: `std.db` has no function `connect`
>   = help: the SQLite driver is the package `blinklang/sqlite`: run `blink add blinklang/sqlite`, then `import blinklang.sqlite` and `with sqlite.connect(path)? { }`
> ```
> Against plt/min "no help line": a bare error makes the model guess `db.open` and `std.sqlite`.
>
> V4, the §9.1 exemption: one general rule (sys/plt). An FS handler does not see I/O that foreign code does, and the package declares its row. No text names sqlite.
>
> V5, examples: few, but each one complete. §4.7.2 scoped handlers, the §9.1 FS example, and §5 only if it needs a real resource. Each shows the import. The first one in a section also shows the toml line. Everything else uses `mock_db` or `handler DB { }`.

- **Minimalism:**

> Minimalism, Phase B round 1: I change V1 to `blinklang/sqlite` and keep my positions on V2-V5. Stable, ready to vote.
>
> V1: I change to `blinklang/sqlite` with `import blinklang.sqlite`. sys is right: §10.7 reserves `blink.*` for pseudo-modules, so `blink/sqlite` was wrong. I am against plt's `import sqlite`: §10.5 maps an import path to `org/name`, so a bare `import sqlite` would need an alias rule that we do not have. Use one name everywhere, as aiml says.
>
> V2: All three rows are a suggestion only, as plt says. Today `sqlite_handler` is already suggestion-only, and the other two are not on the machine-applicable list. A fix that is machine-applicable only when blink.toml already has the package gives the fixer a new branch for a case that no real user has: before this change nobody had that package. The help text can name the package. That is only diagnostic text, so it needs no rule.
>
> V3: No new duplicate-apis row for `db.connect`. That table maps duplicate names to the one name we keep, and `db.connect` is not a duplicate. It is a removed std fn. A call to it gets the existing UndefinedFunction error, and `import std.db_sqlite` gets the existing ModuleNotFound error. A help line that names `blinklang/sqlite` is fine, but it is wording, not spec behavior. The CHANGELOG Breaking Changes line covers the rest.
>
> V4: Delete the exemption now. Do not defer it. Line 906 already gives the general rule: a handler that calls foreign code declares what that code touches. A Postgres package (aiml's case) is covered with no new text. The spec must not name a package's bindings or rows.
>
> V5: Show one real open, in §4.7.2. I accept aiml's rule that an example that calls `sqlite.connect` shows its import, and the toml line on its first use. All other examples use mocks:
>
> ```blink
> test "count users" {
>     with mock_db(rows: [row1, row2]) {
>         assert_eq(count_users(), Ok(2))
>     }
> }
> ```
>
> If §9.1 keeps an "FS mock does not see a foreign driver's I/O" example, it shows the import too. Two real opens is the most I accept.
>
> Stable, ready to vote.

**Moderator ruling on V3.** Systems and Minimalism wanted no new row for `db.connect`; DevOps, Web/Scripting and AI/ML wanted a row whose fix is "no", and PLT accepted either. The question was not put on the ballot, because the error that a user sees is the same either way. The writer added a row, as the `net.connect` and `fs.errno()` rows do.

#### Phase C — Final vote

Ballot:

- **Q1 — The core answer.** A: `db.connect` leaves std (no std stub, no registry, no Driver trait). The driver is the package `blinklang/sqlite`, imported as `import blinklang.sqlite`, and it exports `connect(...) -> Result[Connection, DBError]`, where `Connection` is a scoped effect handler for `DB`. `connect` is a convention, not a compiler check. A call to `db.connect` and an import of `std.db_sqlite` or `std.db_stmt` get the existing errors, with a help line that names the package, the import and the call. The §9.1 exemption and its binding rows are deleted, and the general foreign-code rule covers a package driver. Examples use `mock_db(...)` or `handler DB { }`; at most §4.7.2 and §9.1 open a real database, each with the import and the toml line. B: reject A.
- **Q2 — The duplicate-apis fix for `db_connect(path)`, `sqlite_connect(path)` and `sqlite_handler(handle)`.** A: a suggestion for all three, never machine-applicable, whatever blink.toml holds (`"fixes": []` for the call). B: machine-applicable only when blink.toml already lists `blinklang/sqlite`; otherwise a suggestion.

- **Systems:** A, A

> Sys Phase C votes: Q1 A, Q2 A.
>
> **Q1 — Vote: A.**
> Reasoning: The `with` site knows the concrete `Connection` type, so `enter` and `exit` monomorphize to direct calls. There is no vtable, no driver lookup at run time and no global registry. A program links sqlite only when it depends on the package, and the compiler drops the vendored C tree and the CI system dep. The general foreign-code rule already covers a handler that does its own I/O, so deleting the std-only exemption takes away no guarantee.
> Concern: The help line names `blink add`. If that command does not exist or has a different shape, the help sends users to a dead end. The writer must check it against §8.9, or print the literal `[dependencies]` line instead.
>
> **Q2 — Vote: A.**
> Reasoning: B makes the fix depend on the state of blink.toml. The same diagnostic then changes between machine-applicable and suggestion depending on a file outside the source, so the JSON output is not deterministic for the same source file. `sqlite_handler` already changes the shape of the code: its argument changes from a handle to a path, so no rewrite of the call can be correct on its own. A also meets aiml's goal: an agent that applies every machine-applicable fix never gets code that still fails to compile, because nothing here is machine-applicable.
> Concern: Agents cannot fix these old calls on their own and must read the help line. That is a small, one-time cost, because the three removed names are pre-1.0.

- **Web/Scripting:** A, A

> Web Phase C votes: Q1 A, Q2 A.
>
> Q1. Vote: A
> Reasoning: Python and JS devs already use this shape (`sqlite3.connect(path)`, `psycopg.connect(url)`, `new Database(path)` after an npm install). The interface stays in std and the driver comes from a package, so a reader can tell which is which from the imports. The help line on UndefinedFunction tells a user what to do when they type `db.connect` from old docs or training data, and that stops most of the questions it would cause. There is no run-time driver lookup, so there is no Go-style "unknown driver" error.
> Concern: Hello-world with a database now needs a toml edit before it compiles, and new users will hit that error before they read §4.7.2. The help line must be exact and must work when it is copied and pasted.
>
> Q2. Vote: A
> Reasoning: Use one rule for all three names, "this fix is a suggestion", so the result does not depend on what blink.toml holds on a given machine. A fix that applies only sometimes is harder to explain and harder to trust. aiml's agent-loop point also argues for A. A suggestion never produces code that fails to compile, and the help line gives the agent the exact `blink add` command.
> Concern: An editor's "fix all" will skip these three names. A user migrating a large codebase does each call by hand, which is slow but rare, because this is a one-time pre-1.0 migration.

- **PLT:** A, A

> PLT Phase C votes: Q1 A, Q2 A.
>
> **Q1 — Vote: A.**
> Reasoning: A scoped handler is matched by its type, so a package `Connection` with `impl BlockHandler` needs no change to the language. Each driver's row stays precise and static. A std stub or a registry would have to charge a row that nobody can know at compile time. Deleting the §9.1 std exemption removes trust given to modules that no longer exist, and the package's foreign code then falls under the normal declare-and-audit rules. Using the package name `blinklang.*` keeps clear of the no-op `blink.*` namespace.
> Concern: The spec text for the general foreign-code rule must say outright that the `with` charges the package's *declared* row. If it does not, a package can under-declare FS/Time/Rand with no audit catching it.
>
> **Q2 — Vote: A.**
> Reasoning: All three rewrites change the shape of the code: a call becomes a `with ...? { }` block, and in `sqlite_handler` the argument changes from a handle to a path. Line 649 already makes such fixes suggestions only. A fix that depends on blink.toml makes the fix's meaning depend on state outside the file. It also does not solve aiml's case: the handle-to-path rewrite can compile and still mean something different. "Compiles" is weaker than "keeps the meaning".
> Concern: Agent loops that apply only machine-applicable fixes get no automatic fix here and must read the help line. That makes clear, exact help text load-bearing.

- **DevOps/Tooling:** A, A

> DevOps/Tooling votes for Phase C: Q1 A, Q2 A.
>
> **Q1: A**
> Reasoning: With A, the driver lives in the type system, so the LSP can autocomplete `sqlite.` and the type checker knows which handler runs. No run-time "unknown driver" error can happen. The two existing error codes carry a help line that names the exact `blink add` command, the import and the call, so the change adds no new diagnostic name. The import path follows the `org/name` mapping in §10.5 and does not touch the `blink.*` reserved namespace. Doc tests for most examples need no native C build in CI.
> Concern: The registry does not exist yet, so `blink add blinklang/sqlite` may not resolve on day one. If the command in the help line fails when a user copies it, that error is worse than no help line.
>
> **Q2: A**
> Reasoning: The fix output must be deterministic. If it depends on what blink.toml holds, the same source gives a different `fixes` list on a laptop and in CI, and tests of the fix need fixture manifests. `sqlite_handler` is already suggestion-only, so A makes the three rows match. A also meets aiml's goal: an agent that applies every machine-applicable fix never gets code that still fails to compile, because nothing here is machine-applicable.
> Concern: Users who already have the dependency must make a by-hand edit that a tool could do. If that becomes common friction, a separate `blink fix --with-deps` mode can come later, but it should not reach into the base fix contract.

- **AI/ML:** A, A

> AI/ML Phase C votes: Q1 A, Q2 A.
>
> Q1 — Vote: A
> Reasoning: `sqlite.connect(path)` matches what models already write from Python `sqlite3.connect`, so the first try usually lands. The help line on `db.connect` turns the most likely mistake from old training data into a one-step repair. One real package name, with its import shown in every real-database example, stops models from making up `std.sqlite` or `blink.sqlite`. The compile-time errors are things a model can repair. Go's run-time missing-driver error is not.
> Concern: older spec text, blog posts and the corpus keep `db.connect` for a long time, so the help line must stay until that text is gone. The writer must also sweep llms*.md and the examples, not only sections/.
>
> Q2 — Vote: A (a change from my B1 position)
> Reasoning: these rewrites change the shape of the code. A `let h = db_connect(p)` handle becomes a `with` block, and `sqlite_handler` already counts as suggestion-only (sections/04 line 649). So even when blink.toml lists the package, an edit to one call cannot be machine-applicable in a sound way. With B, the agent-loop risk I raised comes back: a "machine-applicable" edit that leaves code which does not compile. A is simpler and always honest: `"fixes":[]`, and the model reads the help.
> Concern: with no fix diff, a model only has the help text. The help must show the complete `with sqlite.connect(path)? { }` form and the `blink add` line, not only name the package.

- **Minimalism:** A, A

> Minimalism, Phase C votes: Q1 = A, Q2 = A.
>
> Q1. Vote: A.
> Reasoning: std keeps only the interface, and we add no stub, no registry, no trait and no new diagnostic. "connect" is a convention, as in Python's database API, and the existing scoped-handler rule already makes it work. The §9.1 exemption is deleted, because the general foreign-code rule covers any driver. This removes spec text and adds none.
> Concern: with no check on the name, a later driver can export `open` instead of `connect`, and users will see two shapes. If drivers drift, we add the check then, not now.
>
> Q2. Vote: A.
> Reasoning: one behavior, whatever blink.toml holds, keeps the fixer simple and makes the result easy to predict. The conditional fix in B covers users who already added `blinklang/sqlite` but still call removed std names. Almost nobody is in that state, and it does not justify a fixer that reads blink.toml. A also satisfies aiml's goal: a fix that is never machine-applicable can never give an agent loop code that fails to compile.
> Concern: a user who has the dependency must edit three call shapes by hand, and that is a small one-time cost before 1.0.

Q1: A, 6-0. Q2: A, 6-0.

### Final Spec

```blink
// blink.toml  [dependencies]  blinklang/sqlite = "0.1"
import std.db
import blinklang.sqlite

fn run() -> Result[Int, DBError]
    ! FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand {
    with sqlite.connect("app.db")? {
        count_users()
    }
}
```

```
error[UnresolvedMethod]: no member `connect` on module `db`
 --> app.bl:4:13
  |
4 |     with db.connect("app.db")? {
  |             ^^^^^^^ `db` has no function `connect`
  |
  = note: `std.db` holds the DB interface and no driver
  = help: the SQLite driver is the package `blinklang/sqlite`: run `blink add blinklang/sqlite`, then `import blinklang.sqlite` and `with sqlite.connect(path)? { }`
```

- `std.db` holds the `DB` interface: the effect, `Template[DB]`, `Row`, `DBError` and `Stmt`. It holds no driver, no registry and no Driver trait (§10.7.1).
- The SQLite driver is the package `blinklang/sqlite`, imported as `import blinklang.sqlite` (§8.9.7). A driver package exports `connect(...) -> Result[Connection, DBError]`, where `Connection` implements `Scoped` with a `Context` of `Handler[DB ! R]`. This is a convention, not a compiler check (§4.7.2).
- A call to `db.connect` is the existing E0505 (a member that the module does not declare), and an import of `std.db_sqlite` or `std.db_stmt` is the existing E1200. Each gets the help line above. No new code (§4.4).
- The duplicate-apis rows for `db_connect`, `sqlite_connect` and `sqlite_handler`, and a new row for `db.connect`, point at `with sqlite.connect(path)? { }` from `blinklang/sqlite`. Their fix is a suggestion, whatever blink.toml holds: `"fixes": []` (§4.4).
- §9.1 has no exemption for any driver. `with <handler>` discharges `DB` and charges the declared row of the handler; a package's bindings declare their rows under the normal FFI and audit rules. An `FS` handler does not see the I/O of foreign code.
- Examples about `DB` semantics use `mock_db(...)` or `handler DB { }`. Only §4.7.2 and the §9.1 `FS` example open a real database, and each shows the toml line and `import blinklang.sqlite`.
- The compiler-managed native dependency list (§9.1.2) no longer holds sqlite3.

**Error name.** The ballot printed `UndefinedFunction` for `db.connect`. Under the E0505 row of ERROR_CATALOG.md, a member that a module qualifier does not declare is `UnresolvedMethod` (E0505), as for `term.width()` and `fs.errno()`. The panel voted for "the existing error, no new code", so the spec uses E0505.

**Amends:** [Stdlib tier architecture](stdlib-tier-architecture.md) (the §10.7.1 `std.db` row loses the SQLite driver); [Duplicate APIs](duplicate-apis.md) (the rewrite target of the `db_connect`, `sqlite_connect` and `sqlite_handler` rows, and their fix); [Scoped effect handler](scoped-effect-handler.md) (its `db.connect` example becomes `sqlite.connect` from the package); [FFI driver handler rows](ffi-driver-handler-rows.md) (the rows of std's SQLite driver and its exemption are deleted; the general rule stays). Related: [DB module design](db-module-design.md), [Web service stdlib tier](web-service-stdlib-tier.md), [Stmt as DB effect ops](stmt-db-effect-ops.md).
