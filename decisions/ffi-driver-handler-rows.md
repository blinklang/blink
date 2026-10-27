[< All Decisions](../DECISIONS.md)

# Effect Rows of @ffi Bindings Inside a Built-in Effect's Handler — Design Rationale

**Question.** What effect row does an `@ffi` binding get when it implements a built-in effect's handler (std's SQLite driver under `DB`)?

**Answer.** The row names what the foreign code touches. It never names the effect that the handler implements. `! DB` gives `Handler[DB ! DB]`, a forwarder that never discharges `DB`. `! ()` on every binding is also wrong, because a file write is visible to a later call through no argument. The std handler is `Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand)]`. `with db.connect(p)? { }` discharges `DB` and charges that row to the enclosing code. A new warning, `ForeignRowNamesRoutingEffect` (W0553), fires at the decl of an `@ffi` binding whose row names `DB`, `Crypto`, a child of either, or a user-declared effect. §4.3 divides the built-in effects into interface effects and world effects. The routing guarantee of §9.1 gets one more exemption: std's SQLite driver.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. The quotes below come from the seats' own replies. The quoted rows use bare commas inside `Handler[E ! ...]`; the spec form takes parentheses when the clause row has two or more effects (§4.15.1), and the Final Spec below uses that form. Where a quote has a "[...]", the text there was a ticket reference or a source line number. Phase D ran for Q4 only.

#### Phase A — Independent proposals

All six seats proposed the same rule: a binding names what the C code touches, and never the effect that the handler implements.

- **Systems**: "No foreign call "performs DB"."
- **Web/Scripting**: "The DB driver should name what it touches (the file), never the effect it implements."
- **PLT**: "So the binding's row has to name the capability the foreign code uses, and that is the file, not the interface the Blink handler around it provides."
- **DevOps/Tooling**: "It compiles at main and never fails, so only a warning can catch it."
- **AI/ML**: "A binding names what the C code touches. It never names the effect that its handler implements."
- **Minimalism**: "The wrong `! DB` row loses by §4.7.1 alone."

#### Phase B — Debate highlights

Phase B ran one round. The seats agreed on the S1 rule and moved toward one row for each group of bindings. Position changes:

- **Systems** gave up the narrow `prepare` row: "I take aiml's FS.Delete. I give up my narrow prepare row. I keep Time.Read and Rand on the four decls that run SQL."
- **Web/Scripting** moved to the full union: "I move to the full union: sys's leaves plus aiml's FS.Delete." Web also withdrew `FS` on `bind_*`.
- **PLT** moved to the full union: "D2 makes the assumed row an *upper bound*. A row is a promise about what the call can observe, and the promise is checked against what SQLite does, not what a typical query does."
- **DevOps/Tooling** conceded two points: "I concede. The default journal_mode is DELETE, so every commit unlinks `<db>-journal`." and "I concede. `SELECT random()` and `datetime('now')` give results that come from no argument and no file." Devops also conceded `reset` and `finalize` to the FS triple.
- **AI/ML** took Time.Read and Rand and moved `finalize` to the FS row: "I take sys's Time.Read and Rand, and I keep FS.Delete." AI/ML also moved from an error for the routing-effect row (its first proposal) to a warning.
- **Minimalism** added one leaf that no one had named: "`PRAGMA busy_timeout = N` through exec installs a busy handler, after which a locked step sleeps. That makes Time.Sleep honest too."

One more point from this phase, from PLT: "A row gets shorter only when the shim provably removes a behaviour, and the audit claim records that."

#### Phase C — Final vote

The AG block, Q1, Q2, Q3 and Q5 passed. Q4 went to Phase D. A seat marked "changed" held another position at the end of Phase B or at the start of Phase C.

##### AG. The agreed block — AG-yes (6-0)

The block holds the S1 to S5 rules, the rows of the SQLite bindings, the tooling items (`blink audit` prints each handler's clause row and its audit key; the E0500 note traces a leaf to the assumed binding; the E0500 help for a handler body names the clause row), and the rule that `Stmt.step` outside a `with` declares the step row.

- **Systems** — AG-yes. "Every item matches what the C code does on the machine: the unlink of the journal, a commit at reset or finalize, and the clock and PRNG reads that SQL can make."
- **Web/Scripting** — AG-yes. "The rows are honest upper bounds, and a user who installs `db.connect` gets one E0500 with a fix line they can paste."
- **PLT** — AG-yes. "Every item applies one rule: the assumed row is an upper bound on what libsqlite3 does, and it names resources, never the interface the handler provides." Concern: "names a leaf that §4.3 defines as the structured logging subsystem, not a raw stderr write. The writer must fix the leaf, or point the row at the leaf `io.eprint` takes, before this becomes text." (This is about the `! IO.Log` row of the Net and Crypto default bodies. See the implementation notes.)
- **DevOps/Tooling** — AG-yes. "The tooling items (audit prints clause rows, E0500 traces a leaf to its binding and key, the help names `Handler[E ! R]`) are what make the long rows usable."
- **AI/ML** — AG-yes. "Together they give one rule a model can learn: a binding states what the C code touches."
- **Minimalism** — AG-yes. "Every item follows from rulings we already have: D2's upper bound, the hidden-state fix order and the fd-table maker rule."

##### Q1. Does `Time.Sleep` go on `exec`, `execute`, `query` and `step`? — TS (6-0)

TS: add `Time.Sleep`. 0: leave it out. In B1 the rows of five seats had no `Time.Sleep`, because only Minimalism had addressed it. All five voted TS.

- **Systems** — TS (B1 row: 0). "`PRAGMA busy_timeout` through exec installs a busy handler, so a later locked step calls sqlite3_sleep, which is VFS xSleep and then usleep. WAL mode also sleeps with no busy handler at all."
- **Web/Scripting** — TS (B1 row: 0). "A test sandbox that forbids Time.Sleep must see it. The user cost is one more leaf in the same pasted line."
- **PLT** — TS (B1 row: 0). "An upper bound that leaves out a reachable behaviour is unsound under D2. Length is not a counter-argument."
- **DevOps/Tooling** — TS (B1 row: 0). "Any caller can send `PRAGMA busy_timeout = N` through exec_raw. After that, a locked step really sleeps, and no Time handler sees it."
- **AI/ML** — TS (B1 row: 0). "A fn without Time.Sleep can then block on the clock, and the row must be an upper bound (D2)."
- **Minimalism** — TS. "`PRAGMA busy_timeout = N` is plain SQL that the shim passes through today with no authorizer."

##### Q2. The row of `prepare` — PF (6-0)

PF: the full FS row. PR: `! FS.Read`.

- **Systems** — PF. "Before prepare can read the schema it must take a read lock. If a hot journal is there, that lock runs crash recovery, which writes the db and unlinks the journal."
- **Web/Scripting** — PF (B1: PR). "I withdraw PR. devops's hot-journal case shows prepare can roll back and delete the journal, so `! FS.Read` would be a false claim."
- **PLT** — PF. "The shared lock that prepare takes for the schema read can roll back a hot journal, which writes and deletes. So `! FS.Read` alone is an unsound claim."
- **DevOps/Tooling** — PF. "If a hot journal exists (a crash in another process), taking that lock rolls the journal back into the file and deletes it. So prepare can write and delete."
- **AI/ML** — PF. "On a hot journal, prepare writes and deletes."
- **Minimalism** — PF. "The first schema read takes a shared lock, and that can roll back a hot journal, which writes the file and deletes the journal."

##### Q3. A diagnostic for a routing effect in an `@ffi` row — WR (5-1)

WR: a warning at the decl when the row names `DB`, `Crypto`, a child of either, or a user-declared effect; `@allow` suppresses it and `@trusted` does not. WH: a warning at a direct `@ffi` call inside an op body of `handler E`. H: no new code; a help line on the existing diagnostics.

- **Systems** — WR. "It stays a warning, because a C library that calls back into Blink can run a DB op, and then the row is honest."
- **Web/Scripting** — WR (B1: WH, with H as the fallback). "The warning at the decl points at the line with the mistake, which is better DX than my call-site version. It also catches a `! DB` binding called from business code outside any handler, which WH misses."
- **PLT** — WR. "The trap row is wrong at the decl, so the fix belongs there. WH fires only on a direct call, and sqlite's op bodies reach the bindings through helpers, so WH misses the real case."
- **DevOps/Tooling** — WR. "The silent case is a `with` reached from main, where the root DB holds and nothing fires. H only adds text to diagnostics that do not fire in that case."
- **AI/ML** — WR. "My probe p1.bl passes `blink check` with no output today, so H's "existing machinery catches it" is false for every script." AI/ML keeps this minimum: "the handler-type mismatch must point at the binding and must never offer `Handler[E ! E]`."
- **Minimalism** — H (dissent, about the help text only). "A warning at the decl would fire on a true row, such as sys's case of a C library that calls back into Blink, and that author must then `@allow` a correct decl. A help line that points at the binding, and never suggests `Handler[E ! E]`, fixes the confusion without a new code or the interface/world split in §4.3."

DevOps/Tooling's text of the warning:

```
warning[ForeignRowNamesRoutingEffect]: foreign call `pq_exec` claims `DB`, which only a handler implements
  --> pg.bl:4:1
  note: a foreign call does not run through a handler; this row is charged to the caller's handler and never discharged by this call (§4.5 invariant)
  help: name what the C library touches, such as `Net.Connect` or `FS.Read, FS.Write`, or write `! ()`
```

Four seats named the same concern: the split of the built-in effects must be stated as a table in §4.3. PLT: "Each new built-in effect must be classed, or the warning is ill-defined for it."

##### Q4. What the std gate exemption for std.db passes — L (4-2 in Phase C; 6-0 in Phase D1)

M: exempt only the maker calls, each by name; the handle ops pass under the existing-fd exemption. L: exempt calls to bindings under the driver's audit key (STD-DB-SQLITE) from std.db, std.db_sqlite and std.db_stmt.

- **Systems** — L. "M depends on the existing-fd exemption, but step and exec do not act only on existing fds. ATTACH opens a new path, hot-journal recovery opens the -journal file, and sorts open temp files."
- **Web/Scripting** — M. "Maker-only, by name, fails closed. A later path-based FS binding in the driver (such as `stat`) fails the gate instead of passing under a module-wide or key-wide grant."
- **PLT** — L (changed from M). "`ATTACH '/path'` opens a *new* file, so these calls are not "only on an fd that already exists". Under M they fail the gate on a correct tree unless each is listed as a maker, and then M is the same per-binding list as L."
- **DevOps/Tooling** — L. "M passes them under an exemption whose words they do not meet. L says what is true: the whole driver is exempt, and the exemption is bounded by module and audit key and printed site by site."
- **AI/ML** — L. "M's premise is that step and exec "act only on an fd that already exists". That is false on the facts."
- **Minimalism** — M. "step, exec, close and the other handle ops act on an fd that already exists, and the libc-wrapper ruling already exempts that case. So M passes the current tree."

##### Q5. A std alias for the sqlite handler type — 0 (6-0)

A: `pub type SqliteHandler = Handler[DB ! (...)]` in std. 0: no alias.

- **Systems** — 0. "The long list is the fn's `!` row, and an alias of the handler type does not shorten it."
- **Web/Scripting** — 0. "Users never spell the handler type; it is inferred at `with`."
- **PLT** — 0 (changed from A). "Users seldom write the handler type: they write `with db.connect(p)? { }` and the row on their fn. An alias is std surface with no demonstrated use (YAGNI)."
- **DevOps/Tooling** — 0. "An alias also hides the row in hover unless the LSP expands it."
- **AI/ML** — 0. "A second spelling of the same type adds one more form for models to learn and to mix up."
- **Minimalism** — 0. "It hides the row a user must copy into `!`, and that row is the long part."

#### Phase D — Round 2

Phase D settled Q4. In D1 all six seats chose L over M. The D1 positions:

- **Systems** (L, amended to a list by name): "A gate that is green because a call is filed under a rule it does not meet is worse than a gate whose grant is wide but printed site by site."
- **Web/Scripting** (changed from M): "Both need a reviewed edit, so the difference is which file the reviewer touches. It is not a silent pass versus a fail."
- **PLT** (L, "pinned and current"): "Then a new `sqlite_stat_path` binding under the key fails the gate until someone pins it."
- **DevOps/Tooling** (L): "The two options pass and fail the same calls in the current tree."
- **AI/ML** (L, bindings listed by name in the record): "With that tightening, L and M pass and fail the same set."
- **Minimalism** (changed from M): "The existing-fd exemption does not cover them honestly, and stretching it to fit would bend a ruling we already have. That is the opposite of minimal."

Every seat kept the condition that the gate prints every exempt site on every run. D2 asked what decides that a binding is in the exempt set. LP: the binding holds a current pin under STD-DB-SQLITE, and it is called from std.db, std.db_sqlite or std.db_stmt. LN: a list of binding names in the gate (sys's list: sqlite_open, sqlite_open_or_none, sqlite_exec_raw, sqlite_execute_raw, sqlite_query_raw, sqlite_step, sqlite_prepare, sqlite_reset, sqlite_finalize, sqlite_close). The D2 revote was LP 5, LN 1.

- **Systems** — LP. "Under LN that edit is a new line on the gate's list. Under LP it is a new pin in the STD-DB-SQLITE record. [...] LN would add a second list that can drift from it." Concern: "If a tool can re-pin every binding under a key in one step, a new binding gets its pin without anyone reviewing it, and LP becomes the silent key-wide pass. So a pin must be added one binding at a time."
- **Web/Scripting** — LP. "LP keeps one source of truth, the audit record that already names each binding under STD-DB-SQLITE." Concern: "The pin must name each binding, not just the key, and the gate's printed line must name the pin it matched."
- **PLT** — LP. "Under LP, a widened row or a changed signature on `sqlite_step` (for example adding Net) breaks its pin (R3), and the gate fails until someone reviews it and pins it again. Under LN, the name still matches, so the changed binding passes silently." Concern: "the STD-DB-SQLITE claim text should say that these bindings are driver bindings that open files, and a reviewer has to know that a pin under this key also grants a gate pass."
- **DevOps/Tooling** — LN (changed from LP). "Under R2, every `@trusted` binding needs a pin anyway. So an author who adds `sqlite_stat_path` under STD-DB-SQLITE adds a pin as a routine step of writing the binding, and under LP that routine step also grants the gate exemption with no separate decision." Concern: "the gate list and the audit record can drift. The gate must fail on a listed name that no longer exists, and on a listed name that does not hold a current pin, and it must print each exempt site on every run."
- **AI/ML** — LP. "A current pin also ties the exemption to the binding's reviewed row, so a changed row breaks the pin and fails the gate. A bare name in a list would still pass." Concern: "A stale or missing pin must fail closed, with a message that names the binding and the record to edit."
- **Minimalism** — LP. "LP puts it in the audit record, which already lists and pins each binding." Concern: "the gate must check that each pin is current, not merely present, and print every exempt site on every run."

### Final Spec

```blink
// libpq: the row names what the C library touches
@ffi("pq", "PQexec")
@trusted(audit: "PG-001")
fn pq_exec(conn: Ptr[Void], sql: Ptr[U8]) -> Ptr[Void] ! Net.Connect

impl Scoped for PgConnection {
    type Context = Handler[DB ! Net.Connect]
    // ...
}

// wrong: W0553 ForeignRowNamesRoutingEffect at the decl
@ffi("pq", "PQexec")
@trusted(audit: "PG-001")
fn pq_exec(conn: Ptr[Void], sql: Ptr[U8]) -> Ptr[Void] ! DB

// std's SQLite driver: with db.connect(p)? { } discharges DB and charges this row
// Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand)]
fn load(p: Str) -> Result[(), DBError] ! FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand {
    with db.connect(p)? { }
    Ok(())
}
```

- An `@ffi` row names what the foreign code touches. `DB` never appears in a foreign row.
- Rows of std's SQLite driver: the maker (`sqlite_open`, `sqlite_open_or_none`), `sqlite_close`, `sqlite_reset`, `sqlite_finalize` and `sqlite_prepare` take `! FS.Read, FS.Write, FS.Delete`. `sqlite_exec_raw`, `sqlite_execute_raw`, `sqlite_query_raw` and `sqlite_step` add `Time.Read, Time.Sleep, Rand`. `bind_*`, `errmsg`, `last_insert_rowid`, `is_closed`, `is_finalized`, `column_*`, `result_*` and `result_free` take `! ()`.
- The row covers every behavior reachable from SQL text. It gets shorter only when the shim provably removes a behavior, and the audit claim records that.
- The pub pure-Blink helpers declare the row. A test under `with mock_db(...)` is charged no FS. A missing leaf is E0500 at the `with`, and the fix line prints the whole row on one line.
- `Stmt.step` outside a `with` declares the step row (E0500 if it does not).
- W0553 `ForeignRowNamesRoutingEffect` fires at the decl when the row names `DB`, `Crypto`, a child of either, or a user-declared effect. `@allow` suppresses it. `@trusted` does not.
- The handler-type mismatch for such a binding points at the binding and never offers `Handler[E ! E]`.
- §4.3 has a table of interface effects (`DB`, `Crypto`, `Async`) and world effects (`FS`, `Net`, `IO`, `Env`, `Time`, `Rand`, `Process`, `State`, `Arena`).
- `blink audit` prints each handler's clause row and its audit key. The E0500 note traces a leaf to the assumed binding and its key.
- The routing guarantee has a second exemption: std's SQLite driver. Its file I/O does not go through `fs.*` ops, so a `mock_fs` handler does not see it, and `":memory:"` still charges the row.
- No handler-type alias.
- Spec: §4.3, §4.5, §4.7, §4.7.1, §4.7.2, §9.1.

### Implementation notes

- Order of work (DevOps): parse `Handler[E ! R]` and fix the E0500 help for a handler body first, so that the help names the clause row and not the fn that builds the handler. Only then migrate the decls. Otherwise a user gets a fix that the spec contradicts.
- Rewrite the 26 `db_sqlite` decls and the private `sqlite_open_or_none` in `std.db` to the rows above. The pub helpers (`sqlite_query` and the rest) declare the row. The `Context` and `enter` types of `Connection` repeat the handler row in three places. A row change must edit all three.
- Add the warning W0553 at the decl, with `@allow` and without `@trusted` suppression. Fix the spec examples that gave `Crypto` to a foreign row: a pure computation on its arguments takes `! ()`.
- Add a std test that checks the clause row of the handler for drift (DevOps).
- The Q4 gate exemption. The gate exempts only bindings that hold a current pin under audit key STD-DB-SQLITE, called from std.db, std.db_sqlite or std.db_stmt. A new binding fails the gate until someone pins it. A changed row or signature breaks the pin (R3) and fails the gate. A new module fails. The gate prints every exempt site on every run and names the pin it matched. A stale or missing pin fails closed with a message that names the binding and the record. Pins are added one binding at a time; there is no bulk re-pin. The STD-DB-SQLITE claim text says that these are driver bindings that open files, and that a pin there also grants the gate pass.
- The Net and Crypto runtime default bodies (the C runtime, bound only by a test) get `! IO.Log` today. Once the bodies are real, they take the leaves that they touch. PLT's concern: "names a leaf that §4.3 defines as the structured logging subsystem, not a raw stderr write. The writer must fix the leaf, or point the row at the leaf `io.eprint` takes, before this becomes text." The spec does not carry this row, because `IO.Log` is the structured-logging leaf (`io.log`) and a raw stderr write (`io.eprint*`) has no named leaf.
- Follow-ups, each a separate ticket:
  - A `! Kv` binding inside `handler Kv` gives no diagnostic today (AI/ML's probe).
  - The E0500 help names the fn that builds the handler, not the clause row.
  - `Stmt` operations bypass the `DB.Read` and `DB.Write` accounting. PLT: "should they be DB ops, or should Stmt not escape the `with`?"
  - The `IO.Log` versus raw stderr leaf gap.
