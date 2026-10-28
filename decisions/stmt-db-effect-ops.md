[< All Decisions](../DECISIONS.md)

# Stmt Ops as DB Ops — Design Rationale

This ruling settles how a prepared statement (`Stmt`) meets the effect system. Before it, `s.step()` and the other `Stmt` methods charged no row, so a fn with no `DB` row could run SQL through a `Stmt` it was handed, and a mock `DB` handler could not see the call.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim; "[...]" marks a cut.

Options. **Q1**: **K** keep `Stmt`; each `Stmt` op is a `DB` op that the handler runs, and `Stmt` is a token that the handler makes; **X** remove `Stmt` and `db.prepare` from the public `std.db` surface; **S** `Stmt` is `Scoped` and may not leave the `with` that made it. **Q2** (if K): **R-W** `step` is `DB.Write`, the other ops are `DB.Read`, one `Stmt` type; **R-2T** two types, `Stmt` with `DB.Read` ops and `WriteStmt` with `DB.Write` ops; **R-SW** one type, `step` is `DB.Read` and refuses a writing statement at run time, `step_write` is `DB.Write`. **Q3** (if K): what a `DB` handler that omits a `Stmt` op gets. **F** the §4.7.1 forward rule as written; **D** default op bodies that return an `Err`; **R** a compile error for the omission. **Q4** (if K): **C** `Stmt` stays `Closeable`; **N** `Stmt` is not `Closeable`.

#### Phase A — Independent proposals

##### Systems

> "KEY FACT: an escape rule does not fix the bug. In the lead probe, `sneaky(s)` INSIDE the `with` ran the INSERT (rc 101) from a fn whose row is `! IO`. Stopping the Stmt from leaving the `with` does not stop it going down into a callee." — Systems

##### Web/Scripting

> "A JS/Python dev reads `! IO` as "this fn cannot touch the database"; today that is false, and that is the Stack Overflow question we must not ship." — Web/Scripting

##### PLT

> "**Invariant.** The DB budget holds if and only if every site that can run SQL is dominated by a `DB` discharge. `prepare` is a DB op but `step` is not, so the site that runs SQL can move anywhere, including into a `! IO` fn while still inside the `with` (the lead's probe, first call)." — PLT

##### DevOps/Tooling

> "Key point first: an escape rule alone does not close the hole. In the lead probe, the FIRST `sneaky(s)` call ran inside the `with` and still ran an INSERT from a fn whose row is `! IO`." — DevOps/Tooling

##### AI/ML

> "KEY FACT FIRST. The leak is not only "Stmt outside the with". In the lead's probe, `sneaky(s) ! IO` ran an INSERT INSIDE the with. `db.prepare` is DB.Read, so a fn with only `! DB.Read` can prepare an INSERT and step it today." — AI/ML

##### Minimalism

> "First choice is A (cut Stmt), fallback is B (route Stmt through the effect). I reject any "Stmt must not escape the with" rule." — Minimalism

> "Escape analysis closes neither." — Minimalism

Minimalism sent one correction after its proposal:

> "One sentence in what I sent is wrong. I wrote that no user code outside the repo calls prepare. I can only vouch for this repo, where only tests use it." — Minimalism

#### Phase B — Debate highlights

##### Minimalism moves from free ops to methods, and on `reset`

Minimalism's Phase A shape put the operations on `db` as free functions: "They are free functions on `db`, not StmtOps methods." After round 1:

> "Methods as thin wrappers are fine, and sys and plt both checked that a trait method with a row charges its caller. They add no language surface. I drop the free-ops-only shape." — Minimalism

On `reset`, Minimalism had put it in `DB.Write` ("`step` and `reset` are `DB.Write`"). After round 1:

> "Position change: `reset` charges `DB.Read`, as web/plt/aiml say. It runs no new SQL, and its FS row arrives through the clause row anyway." — Minimalism

Minimalism kept X first but did not block K:

> "I keep X first. If the panel goes with K, I vote K with no objection. Cutting a public API later costs more than adding one now, so if K wins it must ship complete, mocks included." — Minimalism

##### DevOps/Tooling withdraws the `stmt_outlives_connection` lint

> "`stmt_outlives_connection`: I withdraw it from the ballot. Under K with owner checks and the exit sweep, an escaped Stmt is inert and gets a defined Err. The lint is tooling polish for a later chore, not spec." — DevOps/Tooling

##### AI/ML drops S (Scoped Stmt)

AI/ML had listed S as its fallback (Proposal 2). After round 1:

> "S: everyone agrees it does not close the in-with leak. I drop it as my fallback." — AI/ML

Systems, PLT and Minimalism had rejected S in Phase A. PLT gave the reason that S "adds new escape analysis and does not fix the in-`with` call."

##### R-2T: the argument for and the argument against

DevOps/Tooling had proposed R-2T. After round 1 it moved to R-W:

> "sys is right that R-2T duplicates every op on a second type, and my own R-2T still used a runtime guard on the read path. So it gives the cost of two types without a fully static answer." — DevOps/Tooling

The argument that decided the seats came from PLT:

> "`sqlite3_stmt_readonly` returns true for BEGIN, COMMIT, ROLLBACK, SAVEPOINT, RELEASE, ATTACH and DETACH. So a `DB.Read` fn could `prepare("COMMIT")` and commit, and `db.commit` is `DB.Write`. The guard must reject those by name. A libpq driver has no such API at all." — PLT

##### R-SW: the argument for and the argument against

Systems had proposed R-SW and dropped it in round 1:

> "plt also says `sqlite3_stmt_readonly` "reports BEGIN/COMMIT as readonly". So the read check in my R-SW needs a special-case list. That is the kind of hidden fragility I dislike, so I drop R-SW." — Systems

> "`s.step()` compiles under `! DB.Read` and then fails in prod on the one code path that builds an UPDATE." — Web/Scripting

> "R-SW moves the misuse into production as `exec_error: statement writes; use step_write`, and no lint or LSP can show that." — DevOps/Tooling

##### Whether the variant of the foreign-token Err matters

> "This is a behavior difference, not only in text: user code matches on the variant. Use `ExecError("statement belongs to another connection")`. devops's `ConnectionError("...closed connection")` reads wrong under a mock or a live second connection, where nothing has closed." — Minimalism

DevOps/Tooling dropped its own text for the foreign case: "I drop my `ConnectionError` text for the foreign case, since the connection that handles it is not closed."

##### Existing handlers (Q3 seeds)

> "§4.7.1 *Completeness and auto-delegation* already says an omitted primitive op forwards to the enclosing handler, and that forward goes into the handler's clause row. So nothing breaks at compile time, and no default bodies are needed." — Minimalism

> "I keep them. plt: "every driver must implement them. That cost is correct." A pg driver that never mints a Stmt still has to write seven clauses that do nothing." — AI/ML

Every seat reported "stable, ready to vote" after round 1.

#### Phase C — Final vote

##### Q1. Keep `Stmt`, or remove it: K 5, X 1

| Seat | Vote |
|---|---|
| Systems | K |
| Web/Scripting | K |
| PLT | K |
| DevOps/Tooling | K |
| AI/ML | K |
| Minimalism | X **(dissent)** |

> "Prepared statements are the only path in std.db with bounded memory. `db.query` builds the whole `List[Row]`, so a large scan needs O(N) heap. Plan reuse also removes a parse and plan step from each row of a bulk insert. To cut them now and add them back later as K means two breaking changes instead of one, and K costs only about 7 ops." — Systems, K

> "Bulk-insert loops and streaming a big table are the first things Python/Node devs reach for after query/exec, and X leaves them with no answer. K closes the hole the probe showed (a `! IO` fn running INSERT inside the with) with a diagnostic users already know from `db.exec`." — Web/Scripting, K

> "K brings back the invariant that every site that can run SQL is dominated by a `DB` discharge. It needs no new language rule, only stdlib ops checked by the existing E0500 machinery. X is also sound, but it takes away the basic driver primitive, and its "nothing uses it" premise only covers this repo." — PLT, K

> "K closes the in-`with` callee hole and gives the same E0500, with the same help text, that users already get for `db.exec`, so there is nothing new to learn. X gives a clean "no op `prepare`" today. But the first user who needs streaming or plan reuse brings back K as a second breaking change, and the migration diagnostics for that change are worse than keeping the op now." — DevOps/Tooling, K

> "Models expect prepare/bind/step from every SQL library. If prepare is gone, they write it anyway, get an unknown-op error with no fix-it, and fall back to SQL built from strings in a loop. K closes both holes (narrower callee, Read fn stepping a write) with the effect-row mechanism the language already teaches. The E0500 + fix-it path repairs a missing row in one edit." — AI/ML, K

> "X and K both leave the language rules as they are. K adds about 7 effect ops, a token and owner table, and a cross-handler error path, and nobody has asked for what it buys: reusing a prepared plan and streaming rows. `db.query`/`db.execute` already cover every use the repo has. Removing a public API later costs more than adding one when a need shows up, and K is additive." — Minimalism, X **(dissent)**

##### Q2. The rows of the `Stmt` ops: R-W 6, R-2T 0, R-SW 0

| Seat | Vote |
|---|---|
| Systems | R-W |
| Web/Scripting | R-W |
| PLT | R-W |
| DevOps/Tooling | R-W |
| AI/ML | R-W |
| Minimalism | R-W |

> "Only R-W is fully static. It needs no SQL classification and no run-time flag, and every SQL-running site charges at least what `exec` charges. R-SW, my own Phase A option, needs a `sqlite3_stmt_readonly` special case for BEGIN/COMMIT, a hidden fragility I no longer defend. A read-only split can come later and only adds API." — Systems, R-W

> "One type and one sentence to teach: "stepping a Stmt needs DB.Write." Misuse fails at compile time. It never fails at run time on the one path that builds an UPDATE. A read-only step can be added later without breaking anything if users ask for it." — Web/Scripting, R-W

> "R-W is sound with nothing trusted. No driver-side SQL classifier can weaken a row. R-2T rests on `sqlite3_stmt_readonly`, which reports BEGIN/COMMIT/ROLLBACK/SAVEPOINT/RELEASE/ATTACH/DETACH as read-only, and libpq has no equivalent. A move to R-2T later only loosens a row (read `step` goes from `DB.Write` to `DB.Read`), so it breaks no caller and stays open." — PLT, R-W

> "Only R-W puts a misuse in compile-time E0500, where the LSP and `blink check` can show it. R-SW moves it into a production `exec_error` string. R-2T copies every op onto a second type and still needs a runtime readonly guard, and that guard is wrong for BEGIN/COMMIT (plt). A read-only `step_read` stays additive later." — DevOps/Tooling, R-W

> "One type and one rule ("step runs SQL, so it is DB.Write"), checked at compile time with a fix-it. That is the fewest decision points and the best signal for generated code. R-2T adds a choice at every prepare and a runtime guard that needs a keyword fallback for BEGIN/COMMIT. R-SW lets a wrong program compile and fail only at run time, which is the worst case for generated code." — AI/ML, R-W

> "one type, and the compiler proves every row (§4.5). The rule takes one sentence: "step runs SQL, so it is DB.Write". R-2T doubles the type and the API and guesses SQL kind from keywords. R-SW lets a `DB.Read` fn compile and then fail at run time, and plt showed the readonly check leaks on BEGIN/COMMIT." — Minimalism, R-W

##### Q3. A `DB` handler that omits a `Stmt` op: F 5, D 1, R 0

| Seat | Vote |
|---|---|
| Systems | F |
| Web/Scripting | F |
| PLT | F |
| DevOps/Tooling | F |
| AI/ML | D **(dissent)** |
| Minimalism | F |

> "The ballot's fact shows §4.7.1 already defines the omitted-op path. The op forwards outward, the outer handler did not mint the token, and the owner check returns a defined Err for two integer compares. R would carve an exception to the forward rule for one stdlib effect. That is a language rule bent to fit a library, and I will not back it now that F is sound. `@handle_all` gives the compile-time W0545 to driver authors who want it." — Systems, F

> "F is §4.7.1 as written, so there is no special case to learn and no language exception. My objection in round 1 was to default clauses that would need new language rules, and F needs none. A mock that only does query/exec keeps compiling, which is the common test case. `@handle_all` users get W0545 if they want the strict check." — Web/Scripting, F

> "§4.7.1 already gives an omitted primitive op a meaning: it forwards outward, and the effect is in the clause row. That composes, and the outer handler's owner check makes the result a defined Err. R would be a special case of the handler rule for one effect, and D would add derived-op defaults that hide the omission at run time." — PLT, F

> "Position changed since round 1. The §4.7.1 forward rule already gives a compile-time signal: a mock that omits `step` forwards DB outward, so DB lands in its clause row, and a test fn without DB gets E0500 at the `with` ("handler performs `DB` outside the handler"). A one-effect exception to a general language rule (R) is a special case that users and the LSP must learn." — DevOps/Tooling, F

> "D reuses the existing derived-op rule, adds no exception to §4.7.1, and keeps every current mock and driver compiling. The Err text names the real cause ("statement ops not handled"). F reports a misleading "belongs to another connection" and pulls DB into the clause row." — AI/ML, D **(dissent)**

> "§4.7.1 already defines what an omitted primitive op does. An exception just for DB is a new rule with its own interactions, and the minimalist answer is to apply the rule we have. D turns DB into a derived-op special case to hide a forward that the spec already makes safe. R makes partial handlers, which §4.7.1 allows on purpose, illegal for one effect." — Minimalism, F

Several seats flagged that the owner-mismatch text can mislead a mock author. Systems: "The writer should have the error text name the forwarding case, or have std.db docs tell driver authors to use `@handle_all`." DevOps/Tooling: "the W0545 via `@handle_all` on `DB` must not be optional." The panel did not rule that `DB` must carry `@handle_all`.

##### Q4. Is `Stmt` `Closeable`: C 2, N 4 in Phase C (re-voted in Phase D)

| Seat | Vote |
|---|---|
| Systems | C |
| Web/Scripting | N |
| PLT | N |
| DevOps/Tooling | C |
| AI/ML | N |
| Minimalism | N |

> "Scope-based release frees the statement on every exit path: a `?` early return, a panic, or a `break` in a long loop. An explicit `s.finalize()` misses those paths, and with N such a statement lives until the outer `with` ends, so memory grows with the loop count. Closeable adds no new mechanism: it is the existing `with ... as` lowering, and the exit sweep still catches anything the program does not release." — Systems, C

> "The exit sweep already does the cleanup, so Closeable would be a second way to do the same job. One way is easier to teach. `s.finalize()` covers early release in long loops, and Python devs already expect `with conn:` to clean up at block end." — Web/Scripting, N

> "with the exit sweep, the handler's `with` already bounds the Stmt's life. A second lifetime mechanism (Closeable) adds the E0601/E0602 and `with...as` interplay and buys nothing the sweep and an explicit `finalize` do not give. One lifetime owner per resource is the principled shape." — PLT, N

> "`with ... as` on a `Closeable` is the one documented release pattern (§4.7.2, llms-full.md:594). Making Stmt the one handle that rejects it gives an error a user cannot predict. With the exit sweep, forgetting it is never a leak, so C costs nothing and keeps early release in a long loop." — DevOps/Tooling, C

> "The exit sweep already frees every Stmt, so `with ... as s` would be a second way to do the same thing. That is a decision point with no gain in the common case, and early release keeps `s.finalize()`. One pattern means models generate it the same way every time." — AI/ML, N

> "the exit sweep already finalizes every open Stmt, and `s.finalize()` covers early release. Closeable would add a second way to do the same thing, and `close` would have to carry a `DB.Read` row, which pulls Closeable's row semantics into the effect question. One mechanism is enough." — Minimalism, N

#### Phase D — Round 2

Q4 only. Q1 (K, 5-1), Q2 (R-W, 6-0) and Q3 (F, 5-1) stayed closed. The Phase C result for Q4 was 4-2 for N. The digest gave the panel one fact: llms-full.md:594 already documents `with...as` for `Stmt`:

```
db.prepare(tpl)                 // -> Result[Stmt, DBError] (Closeable — use with...as)
```

Systems and DevOps/Tooling kept C. Web/Scripting, PLT, AI/ML and Minimalism changed from N to C.

##### Systems (C, unchanged)

> "The spec has already settled this. §3 (03_types.md:6518) and §5 (05_memory_compile_errors.md:215) both declare `trait Closeable { fn close(self) ! _ }`, so close is effect-polymorphic." — Systems

> "They are not the same job. The sweep bounds the lifetime at the connection. `with ... as` bounds it at the statement." — Systems

##### Web/Scripting (N to C)

> "Under N, that code is an error, and the error buys no safety, because the exit sweep is there either way. That is the "why can't I with a Stmt when I can with a file?" question, asked forever. Under C, the code people write compiles and does the right thing. "Just works" beats "one way" here." — Web/Scripting

> "My Phase C reason ("Closeable is a second way to do the same job") was wrong. The two do different jobs. The sweep is a safety net at connection scope. `with ... as` is release at the scope the user picks." — Web/Scripting

##### PLT (N to C)

> "I withdraw my "second lifetime mechanism" argument. Under C the two scopes nest: the `with ... as s` region sits inside the connection's region, and the sweep is only the fallback for the outer one. Nested regions that each have one owner compose cleanly. That is not two owners for one resource." — PLT

> "`close` is the `finalize` op, run by the handler. It never calls sqlite directly, so a mock's `with ... as s` works." — PLT

##### DevOps/Tooling (C, unchanged)

> "To min ("`close` would have to carry a `DB.Read` row"): the row costs nothing. `with db.prepare(sql)? as s` already calls `prepare`, which is `DB.Read`, so the enclosing fn already declares the row that `close` charges. No new E0500 site appears, and the diagnostic for a fn that lacks it stays the one that `prepare` already gives." — DevOps/Tooling

> "A concern that every N voter shares is the case for C." — DevOps/Tooling

##### AI/ML (N to C)

> "Under C both choices are right: `with db.prepare(sql)? as s { }` finalizes at once, and a bare `let s` is caught by the sweep. So the model cannot pick wrong. Under N, the choice models will make most often is a compile error." — AI/ML

##### Minimalism (N to C)

> "My main reason for N was wrong. I said `close` "would have to carry a `DB.Read` row, which pulls Closeable's row semantics into the effect question". The spec already handles that. §3 (03_types.md:6518) declares `fn close(self) ! _`: "each impl declares the effects of its own `close` (§4.15.2)". So `impl Closeable for Stmt { fn close(self) ! DB.Read { self.finalize() } }` needs no new rule." — Minimalism

##### Re-vote: C 6, N 0

> "`with db.prepare(sql)? as s { }` frees the statement on every exit path (`?`, `break`, panic). It uses the `with ... as` lowering that already exists, so it adds no run-time cost and no new mechanism. The exit sweep stays as the safety net at connection scope." — Systems, C

> "Devs and models will write `with db.prepare(sql)? as s { }` because it is the release pattern they know from files and from Python cursors. Under C, that code compiles and frees the statement on every exit path (`?`, `break`, panic), which N's explicit `finalize()` misses." — Web/Scripting, C

> "`with ... as s` frees the statement on every exit path (`?`, panic, `break`), and N has no answer for those paths inside a long connection `with`. The inner Stmt scope nests inside the connection's scope. Each scope has one owner, and the sweep catches only what the inner block did not free, so the design composes with no new rule." — PLT, C

> "`with db.prepare(sql)? as s { }` is what users, docs (llms-full.md:594) and models already write, and under C it compiles and releases on every `?`, `break` and panic path. N would turn that code into an error that a user cannot predict and that buys no safety." — DevOps/Tooling, C

> "Under C, both release choices a model can make are correct. `with db.prepare(sql)? as s { }` frees at once, and a bare `let s` is caught by the sweep, so the choice costs nothing." — AI/ML, C

> "C is the status quo. Stmt is Closeable today (db_stmt.bl:93), and llms-full.md:594 teaches `with...as`, so C adds nothing." — Minimalism, C

Every C voter named the same condition: `finalize` is idempotent and clears the handler's record of the `Stmt`, so the exit sweep skips a `Stmt` that `with ... as` already freed. PLT: "The spec must require that `finalize` can run more than once safely and clears the slot, and a test must cover the double-release path."

### Final Spec

```blink
fn add_all(p: Str, xs: List[Int]) -> Result[Void, DBError] ! FS, Time, Rand {
    with db.connect(p)? {
        for x in xs {
            with db.prepare("INSERT INTO t VALUES ({x})")? as s {
                s.step()?
            }   // s is finalized here, on every exit path
        }
    }   // the handler finalizes any Stmt still open here
    Ok(())
}

fn sneaky(s: Stmt) ! IO {
    let _ = s.step()   // E0500: `s.step()` performs the DB operation `step`, which requires `DB.Write`
}
```

- Each `Stmt` method performs a `DB` operation that the handler runs. `Stmt` is an opaque token that the handler makes in `prepare`. A mock `DB` handler can make one and see every `Stmt` op (§4.4.10).
- `step` is `DB.Write`. `prepare`, `bind_*`, `column_*`, `reset` and `finalize` are `DB.Read`. There is one `Stmt` type. The E0500 help for a `DB.Read` fn that steps points to `db.query` and `db.query_one`. The error names the method the code wrote and the operation it performs.
- The row of the foreign calls that the sqlite driver makes is part of the handler's clause row. The `with` charges it. The §9.1 sentence about a `Stmt` stepped outside its `with`, and the sentence "The `Stmt` operations carry no wider `DB` row", are gone.
- A `Stmt` that reaches a handler that did not make it gives `Err(ExecError("statement belongs to another connection"))`. The handler that made it, after its connection closed, gives `Err(ConnectionError("connection is closed"))`. A call after `finalize` gives `Err(ExecError("statement is finalized"))`.
- `finalize` is idempotent and clears the handler's record of the `Stmt`. The handler finalizes every open `Stmt` when the connection's `with` exits, also when it exits by panic.
- A `DB` handler that omits a `Stmt` op is the forward case of §4.7.1. The op goes to the enclosing handler, which did not make the token, so the call gets the owner-mismatch Err. A handler for an effect marked `@handle_all` gets W0545 for each omitted op.
- `Stmt` stays `Closeable`. `close` performs the `finalize` op through the handler, so `with ... as s` works under a mock. The binding follows E0601 and E0602.

### Implementation notes

- `Stmt.step` charges no row at all today, not even the `sqlite_step` row that the old §9.1 text promised. The fix lands with this spec.
- `finalize` and `close` must go through the handler op, never sqlite directly, so a mock works (PLT, Systems). A test covers the double-release path: explicit `finalize`, then the `with ... as s` close, then the exit sweep (Web/Scripting, PLT).
- The stdlib `Closeable` trait declares `fn close(self)` without the spec's `! _`. It must change in the same change, so the `close` of `Stmt` can carry `! DB.Read` (Systems, DevOps/Tooling).
- Existing `DB` mocks and drivers must add the `Stmt` clauses, or they get the forwarded owner-mismatch Err. Minimalism: "K must ship complete, mocks included."
- The constructor name `Stmt.mock(id)` in §4.4.10 follows `Child.mock(id)`. The panel ruled that the handler makes the token. It did not name the constructor.
- The panel did not rule whether `DB` carries `@handle_all`. DevOps/Tooling and AI/ML want driver docs to show it. The spec leaves `DB` unmarked.
