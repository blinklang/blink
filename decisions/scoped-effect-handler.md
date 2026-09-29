[< All Decisions](../DECISIONS.md)

# Scoped Effect Handler (`with db.connect(path)? { }`) — Design Rationale

**Gap:** `decisions/db-module-design.md` gave `db.connect(path)` a scoped connection handler, `with db.connect(":memory:") { db.exec(..) }`, but no language construct was both a `Handler[E]` and a cleanup. The pre-rewrite codegen special-cased the spelling `db`+`connect` by string; the rewrite removed it. The owner ruled (2026-09-28) to build it as a general handler-plus-cleanup `with` item. The panel decided the mechanism, what `db.connect` returns, and the rules around it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round; all six signalled "stable, ready to vote" after it. No question came closer than 5-1, so Phase D did not run.

#### Phase A — Independent proposals

Five of six panelists proposed the same first choice on their own: a `BlockHandler` whose `Context` is `Handler[E]` has the handler that `enter()` returns installed for the block. AI/ML proposed a new prelude type `ScopedHandler[E]` built with `.on_exit(...)`. Excerpts, each panelist's own stated preference:

- **Systems:**

> S1. It reuses BlockHandler (5-0) and Handler[E] (5-0) and adds one type-keyed table row, not a new construct; codegen is static dispatch plus the existing handler push, with zero cost added to ordinary handlers. S2 puts a one-shot resource lifetime on a reusable first-class value, which is how you get double-close bugs.

- **Web/Scripting:**

> P1. It keeps the exact user spelling from the decision doc and the tests, and it reuses BlockHandler, which the panel already chose 5-0 as the general scoped mechanism. It adds one row to a table instead of a new construct. P2 breaks the handler-reuse property the panel voted for, and P3 makes every user do by hand what the compiler can do for them.

- **PLT:**

> I prefer P1. It gets the scoped-handler behavior from the two existing primitives, with one principled typing rule. The effect row is discharged statically through `T.Context`, and `enter`/`exit` get checked against the outer row, so the order of install and cleanup is fixed by the type rule. P2 does not work with first-class handlers. P3 is sound but gives up the requested spelling.
>
> One separate item for the moderator: the by-value `self` in `BlockHandler` means no state can pass from `enter` to `exit`. P1 works around this with eager acquisition. A future `exit(self, ctx: Self.Context, ok: Bool)` would remove the need for that workaround, and it should get its own ticket next to f631xv.

- **DevOps:**

> Proposal A. It widens one row of the table and needs no new syntax or traits. It keeps the owner's spelling apart from a `?`. Its effect shows in the type, so hover, quick-fixes and the scope lint come from types rather than names. B hides ownership inside a type that people can store and install twice. C is correct but wordy, and its errors point at the wrong place.
>
> **Open items for the panel:**
> 1. `enter()` cannot fail, so A opens eagerly in `connect`. Should BlockHandler have a fallible `enter` in general? `Transaction`'s BEGIN has the same problem. It belongs in a separate ticket.
> 2. Fix the W0600 code clash before any new lint takes a code.

- **AI/ML:**

> I prefer Proposal 1. The user side stays the one pattern that models already produce, `with <handler-expr> { }`. The ownership rule lives in one type, which gives one diagnostic when a scoped handler is created outside `with` or used twice. Proposal 2 adds a hidden rule where `as` changes the meaning, and Proposal 3 moves the cost to every call site.

- **Minimalism:**

> M1. It closes the gap by widening a rule the panel already built as *the* general scoped-block mechanism, instead of growing a second one. Handlers stay simple values and cleanup stays in exactly one place (`exit`). It also lets us delete two half-working stdlib functions. M2 is the fallback if the panel won't widen the table. M3 should be rejected.

#### Phase B — Debate highlights

- **AI/ML (moved Y → X):**

> **Options: I move from Y to X.** Y's advantage over X was one thing: in my P2, adding `as h` would stop the install. That was a hidden rule. Variation (b), where the handler still gets installed and `as` binds it too, removes the hidden rule. After that, Y's remaining costs have no return:
> - a new prelude type
> - a new "already consumed" error
> - a type that is not `Handler[E]`

- **Systems (moved plain value → `Result`):**

> (a) I CHANGE my position: Result[Connection, DBError]. I checked the runtime: bootstrap/runtime_sqlite.h:16 `blink_sqlite3_open` returns NULL on failure, and `sqlite_open` gives the NULL back as a Sqlite3 with no error. With a plain return, a bad path gives a with-block where every db.* call runs on a NULL handle. sqlite3_close(NULL) is a no-op, so exit hides it too. That is a silent fault, not a cost trade. `with db.connect(p)? { }`, with `?` firing before the scope is entered (§5.5), so a failed open needs no exit. The three tests take `?` or `.unwrap()`. sqlite_open itself should return Result or Option; that is a stdlib fix, not spec.

- **Minimalism (moved plain value → `Result`):**

> **(a) Result.** I change my position: `connect` returns `Result[Connection, DBError]`. An open can fail. The spec (§5.5) already puts a `?` in a with-item before the scope, so this adds no new rule, and it matches `fs.open(p)?`. The three tests change to `?`/`.unwrap()`; changing a test to the correct API is not a cost. `sqlite_open` must then report failure, which is stdlib work.

- **PLT (rebuttal of Y):**

> - "A second `with` on the same binding is a compile error ('scoped handler already consumed')." This is an affine type check limited to one binding. It does not compose. Once the value goes into a struct field, a `List`, a closure capture, or a function argument, the check either loses track of it, which is unsound, or grows into a partial linearity system with no rules for aliasing. Blink has no linearity, and bolting it onto one prelude type is the corner we should not paint ourselves into. X has the same double-use hazard, but it handles it honestly with the same lint as `Closeable`, and it does not claim a guarantee it cannot keep.

- **PLT (abstract `Context`, new in round 1):**

> A precision point, new in this round: the rule applies only when `T.Context` *normalizes* to `Handler[E]` with a concrete `E` at the `with` site. In `fn f[T: BlockHandler](t: T) { with t { } }`, `Context` is abstract, so the item cannot discharge an effect and falls under row 2's `Context == ()` requirement, which gives an error. v1 has no effect-kinded generics (sys), so `E` is always ground and the rule is decidable. The spec must say this.

- **DevOps (W0601 is taken):**

> - plt's W0601 is already SetButNotRead in ERROR_CATALOG.md, so it collides too.

- **Minimalism (row-2 wording):**

> **(c) Either shape is fine, but I oppose plt's row-2 text.** "any `T.Context` that is not `Handler[_]`" also lets the no-`as` form silently discard a non-`()` Context. That is a separate language change with its own cost, it is not needed here, and it contradicts devops's `NonHandlerWithItem` diagnostic, which I support. So: a separate row, or a widened row 2 limited to `() or Handler[E]`. Nothing wider.

- **Web/Scripting (moved widened row 2 → separate row):**

> - **(c) Separate row (plt, sys).** I switch from a widened row 2. A learner reads the table one row at a time, and "Scoped effect handler" as its own meaning is easier to find and easier to cite in a diagnostic.

#### Phase C — Final vote

Each panelist voted alone. Reasoning and concern are quoted from the ballots.

- **Q1: Mechanism** (6-0 X)
  - **Systems:** X — T is static at the with site, so enter/exit are direct calls that mono resolves, and the install is the existing evidence push. It adds no slot to Handler[E] and no closure alloc per exit, unlike Y and R. It reuses the 5-0 BlockHandler mechanism. *Concern:* eager open means a Connection entered twice closes its handle twice (use-after-free in sqlite); only the lint and the lazy-open follow-up ticket guard it.
  - **Web/Scripting:** X — The user writes one familiar line, `with db.connect(p)? { }`. It reads like a Python context manager, and a JS or Python dev understands it at once. It adds no new type, keyword or consumption rule. Library authors reuse the BlockHandler that they already know. *Concern:* The docs and hover must say in plain words that a BlockHandler can "hand back a handler". If they do not, library authors will not find the pattern and will copy the Z pair.
  - **PLT:** X — X gets its typing rule from two existing types. `T.Context ≡ Handler[E]` discharges `E` from the body's effect row, and `enter`/`exit` are checked against the outer row. It needs no new ownership rule. Y needs an affine "consumed" check on one binding, and that check does not survive aliasing through fields, collections or closures. R conflicts with first-class, storable handlers (4-1). *Concern:* a `Connection` used as a `with` item twice still closes its handle twice. Only the lint guards against that, and it is not a type guarantee.
  - **DevOps:** X — With X, the effect a with-item installs can be read from its type (`T.Context`). Hover, inlay hints ("installs DB") and the "add a handler" quick-fix all come from the type, with no special cases keyed on names. It adds no syntax, so `blink fmt` does not change. Y's "already consumed" error loses track of a value once it is stored or passed along. A diagnostic that fires only on the easy cases teaches users that a missing error means safe, and it does not. *Concern:* users will not guess that `exit` runs under the outer handlers. A `db.*` call inside `exit` needs a clear note, or it will reach a different connection without any error.
  - **AI/ML:** X — The user writes one pattern, `with <expr> { }`, which models already produce for mocks and handlers. X adds no type, trait or syntax, so the spec has nothing new to learn. Python's `__enter__` model carries over directly. *Concern:* an AI may not guess that `exit` runs after the uninstall and write `db.*` calls in `exit`. The spec example and the diagnostic must show this.
  - **Minimalism:** X — X joins two primitives the panel already voted in (BlockHandler 5-0, Handler[E] 5-0) with one type-keyed rule. It adds no type, no trait, no syntax and no new analysis. Y adds a prelude type, a method, a table row and an affine "consumed" check that nothing else in Blink has. R puts a one-shot lifetime on a reusable value. *Concern:* A later change may treat "Context installs" as a precedent and add more type-keyed with-meanings (for example `Context == List[Handler]` or tuples). Each new case must pass the same burden of proof.

- **Q2: What `db.connect` returns** (6-0 A)
  - **Systems:** A — blink_sqlite3_open returns NULL on failure, and a plain value lets a NULL handle run through every db.* call, with sqlite3_close(NULL) hiding it at exit. `?` fires before the scope is entered, so a failed open needs no exit and costs nothing on the success path. *Concern:* until the sqlite_open follow-up lands, connect must check the NULL itself or A is only a type-level promise.
  - **Web/Scripting:** A — A bad path or a locked file must not panic a long-running server. `?` is the Blink idiom that every user already writes. Python's and Node's `connect` both report failure to the caller. *Concern:* `sqlite_open` returns a raw handle today, so the stdlib must detect a failed open correctly. If it does not, `Result` is only for show.
  - **PLT:** A — opening a file path is a partial operation. A total return type must either hide divergence (a panic) or produce a value that holds an invalid handle, which gives use-after-invalid inside the block. §5.5 already puts `?` before scope entry, so a failed open needs no cleanup and the semantics stay clean. *Concern:* the `?` in `with db.connect(p)? { }` is easy to leave out. The resulting type error ("Result is not a BlockHandler") must suggest `?` or `.unwrap()`.
  - **DevOps:** A — A failed open should report its error on the line that caused it. With a plain value, the failure shows up as a SQL error at the first `db.exec`, far from the path that failed. This is the same rule as `fs.open(p)? as f` in §5.5: the `?` fires before the scope is entered, so no cleanup is needed. *Concern:* people will write `with db.connect(p) { }` without `?`. The resulting E0839 must say "this is a Result; add `?` or `.unwrap()`" and not the generic "not a handler" text.
  - **AI/ML:** A — Models put `?` after calls that can fail. A connect that panics on a bad path teaches a wrong pattern to every model trained on this corpus. It costs one token at the call site. *Concern:* models may leave out the `?` in `with db.connect(p) { }`, the spelling in decisions/db-module-design.md. The error for a with-item of type Result must say "add `?`".
  - **Minimalism:** A — An open can fail, and a plain value would have to panic or hide the failure. §5.5 already puts `?` on a with-item before the scope starts, so A adds no new rule, and it matches `fs.open(p)?`. *Concern:* Users will write `.unwrap()` in examples, and that will spread. Docs and the tests should show `?`.

- **Q3: Table shape** (5-1 S, Minimalism dissent)
  - **Systems:** S — a separate row names the case in diagnostics and makes the check order readable from the table. The codegen branch is distinct (install vs discard), so the table should show it as distinct. *Concern:* none of weight; W would work.
  - **Web/Scripting:** S — A learner reads the table one row at a time, and "Scoped effect handler" is a meaning they can find and cite. A diagnostic can also point at that row by name. *Concern:* The table grows to five rows, and the check order paragraph must list the new row explicitly or readers will guess it.
  - **PLT:** S — this row discharges `E` from the body's effect row, and row 2 does not. A judgment with a different conclusion deserves its own row, so readers and the checker see the typing rule on its own. W is acceptable only if its meaning column states the discharge explicitly. *Concern:* if W wins, row 2 becomes one cell with two typing rules. The discharge must then be written out in §4.6.3 so it is not lost.
  - **DevOps:** S — A separate row has its own "Meaning" cell. Hover text and E0839's explain page can quote it word for word. A widened row 2 would put two meanings in one cell. *Concern:* the check order across rows must be written out in full, or the checker and the spec text will drift apart.
  - **AI/ML:** S — Models read the table one row at a time. A row of its own, with its own Meaning text, is easier to retrieve and gives diagnostics a row to cite. The surface is the same as W. *Concern:* the check order (Handler[E], then the scoped row, then row 2) must be written out, or implementations will differ.
  - **Minimalism:** *(dissent)* W — One widened cell is less surface than a new row, and the check order does not change. The limit "nothing wider" matters more than the shape, and W states that limit in the cell itself. *Concern:* A reader can miss that the meaning of row 2 splits on Context. The meaning column must say "installed" plainly.

- **Q4: `with expr as name` on a scoped effect handler** (6-0 I)
  - **Systems:** I — the binder must not change what the block runs; one lowering path for both forms, no hidden branch. *Concern:* the bound Handler[E] closes over a handle freed at exit, so Q7 must pass or `as` gives a use-after-close path.
  - **Web/Scripting:** I — If adding a name changed what the block does, that would cause one Stack Overflow question per week. Install and bind is the only rule a user can guess. *Concern:* A few users will expect `as h` to mean "bind only, do not install". The §4.6.3 example must show both effects.
  - **PLT:** I — the binder must never change what the block does. Otherwise the meaning of `with` depends on syntax that is not part of the item's type, which breaks compositionality. With `as`, the handler is installed and the name binds to the same `Handler[E]`. *Concern:* a name bound to a handler over a handle that `exit` releases is exactly the value that must not escape. Q7 must pass together with this.
  - **DevOps:** I — The binder must never change what the block does. Otherwise adding `as h` to debug something silently removes the install, and the next error is an unhandled-effect error with no link back to the `as`. The inlay hint shows "installs DB" in both forms. *Concern:* users may think `h` is the connection itself and try `h.close()`. Hover on `h` must show `Handler[DB]`.
  - **AI/ML:** I — The binder must never change what the block does. Otherwise adding `as` produces UnhandledEffect errors far from the cause, which is the worst kind of error for generated code to repair. *Concern:* a bound Handler[E] over a handle that `exit` closes invites a model to store it. That depends on Q7 being Y.
  - **Minimalism:** I — A binder that changes what the block does is a hidden rule, and aiml correctly calls that out as a trap. With I, `as` means one thing everywhere: it binds what enter() returns. *Concern:* Nobody may ever need the bound handler, so the `as` form risks being dead surface. That is acceptable, because forbidding it would need a new rule of its own.

- **Q5: Comma-list order** (6-0 Y)
  - **Systems:** Y — `db.connect(p)?, db.transaction()` has no defined meaning without it, and codegen needs a fixed nesting order to emit install/cleanup frames. It costs nothing at runtime. *Concern:* none.
  - **Web/Scripting:** Y — `with db.connect(p)?, db.transaction() { }` is the most common use, and it must work the way it reads, left to right. *Concern:* Where a `?` failure in item i fires relative to the teardown of items 0..i-1 must be stated too, or cleanup will leak on a failed open.
  - **PLT:** Y — the typing of item *i* must see the handlers that items *0..i-1* install. Otherwise `with db.connect(p)?, db.transaction() { }` has no derivation, because `transaction` requires `DB`. The order must therefore be part of the static semantics, not left to the implementation. *Concern:* readers may expect a comma list to evaluate in parallel or in either order, so the spec must say plainly that it is sugar for nested `with` blocks.
  - **DevOps:** Y — `with db.connect(p)?, db.transaction() { }` has to type-check in a defined way, and the LSP needs a defined order to resolve effects inside the list. A normative order also makes this error possible when the items are written the wrong way round: "this item installs DB but comes later; move it first". *Concern:* the unhandled-effect error for that mistake must point at the later item that installs the effect, or users will not find the fix.
  - **AI/ML:** Y — `with db.connect(p)?, db.transaction() { }` will be the most common generated form. Leaving the order unspecified makes it work in one implementation and fail in another. *Concern:* none of note. This order is what readers already expect.
  - **Minimalism:** Y — `db.connect(p)?, db.transaction()` works only under this order, so leaving it unspecified makes correct code depend on the implementation. It is one sentence of spec and codifies what nesting already implies. *Concern:* Evaluating item i after items 0..i-1 are entered means a `?` failure in item i runs exit() on items 0..i-1. The unwind text must state that explicitly.

- **Q6: Scope lint** (6-0 ONE)
  - **Systems:** ONE — one rule, one code, zero runtime cost; I find no valid program where a Closeable or BlockHandler never reaches a with-item or a return. Flow-based avoids the false positive on `let tx = ...; with tx { }`. *Concern:* a flow-based lint across fn boundaries (returned, then stored in a struct) will have gaps; it must say "warning", never imply the resource is safe.
  - **Web/Scripting:** ONE — One rule, "scoped values go in a `with`", is easier to teach than a rule tied to a Context type. A Transaction made outside a `with` is a bug too. The flow-based form avoids false alarms on `let tx = ...; with tx { }`. *Concern:* A flow-based lint can miss a value that passes through a helper function. Users may trust a green result too far.
  - **PLT:** ONE — one flow-based rule for every scoped value is the uniform, compositional choice. A forgotten `Transaction` is as much a bug as a forgotten `Connection`, and NARROW adds a special case that depends on the associated type. Defining the trigger by flow rather than by construction avoids false positives for `let tx = ...` followed by `with tx { }`. *Concern:* a flow-based lint is only as precise as the flow analysis. Values that pass through generic helpers or collections may produce false positives or be missed.
  - **DevOps:** ONE — One code gives one suppression key, one `blink.toml` line and one explain page for every scoped value. Because the check is flow-based, `let tx = db.transaction()` followed by `with tx { }` does not warn, so the lint stays quiet on correct code. A narrower lint would leave a forgotten `Transaction` unreported, and that is a bug of the same kind. *Concern:* the flow analysis has to cover values passed to helper fns and returned from them. Otherwise false positives will push people to `@trusted`.
  - **AI/ML:** ONE — One rule ("scoped values go into a `with`") is easier to learn than a separate rule for each kind, and the flow-based exemption removes the false positive I cared about. A forgotten `with db.transaction()` is a real bug that models make. *Concern:* flow analysis may miss values passed through helper functions or returned from them. That would make the lint noisy or silent in ways a model cannot predict.
  - **Minimalism:** ONE — One trigger ("a scoped value that reaches anything other than a with-item") is simpler than a trigger keyed on Context. A Transaction or a Closeable that never reaches `with` is the same bug. Flow-based checking removes the `let tx` false positive I was worried about. *Concern:* "Flow-based" can grow into a full ownership analysis. Keep it to the existing W0600 checks and do not add a second analysis.

- **Q7: E0601 covers the `as` binding** (6-0 Y)
  - **Systems:** Y — the handler closes over a handle that exit frees; letting the binding escape to a spawned task is use-after-close. E0601 already covers BlockHandler bindings, so this states it. *Concern:* none.
  - **Web/Scripting:** Y — The bound handler closes over a handle that `exit` frees. Letting it escape gives a use-after-close that no web developer will be able to debug. *Concern:* The error text must say "this handler's connection closes at the end of the block", not only name the escape rule.
  - **PLT:** Y — the bound `Handler[E]` closes over a handle that `exit` releases, so any escape is a use after close. §4.6.3 already applies E0601 to `BlockHandler` bindings. This vote just confirms that the rule covers this case. *Concern:* E0601 catches escape through a spawn, a return or an assignment. It cannot catch a handler that escapes by being captured inside another handler literal installed further out, unless that path is checked too.
  - **DevOps:** Y — The bound handler closes over a handle that `exit` releases. If it escapes into a spawned task, that task uses a closed handle. E0601's message already exists for BlockHandler bindings, so this adds no new diagnostic surface. *Concern:* none beyond E0601's existing coverage limits.
  - **AI/ML:** Y — This is consistent with the existing BlockHandler and Closeable bindings, so there is no exception to learn. *Concern:* the error text must say that the handler closes when the block exits. "Escapes scope" alone does not explain why a Handler, normally first-class, cannot escape.
  - **Minimalism:** Y — §4.6.3 already puts BlockHandler bindings under the Closeable scope rules, so this only states that the rule reaches the bound handler. It needs no new code. *Concern:* None beyond making sure the implementation reuses the existing E0601 path instead of adding a copy.

- **Q8: Abstract `Context`** (6-0 Y)
  - **Systems:** Y — installing a handler needs a concrete E to pick the vtable layout at codegen; an abstract Context has none, and v1 has no effect-kinded generics. Say it so the checker does not guess. *Concern:* a generic wrapper fn over a Connection silently becomes an error until v2 effect generics; the diagnostic must say why.
  - **Web/Scripting:** Y — Generic code that silently stops installing an effect would give a confusing unhandled-effect error far from its cause. The spec should state the limit, and the error should point at the `with`. *Concern:* The error for this case must say "Context is abstract here". A plain row 2 mismatch message would confuse the user.
  - **PLT:** Y — the rule must be decidable at the `with` site. With an abstract `Context`, the checker cannot know which effect, if any, gets discharged. Stating the rule makes the static semantics complete and prevents an implementation from guessing. v1 has no effect-kinded generics, so `E` is always ground where the rule applies. *Concern:* users who write generic `with` helpers will hit this error. The diagnostic must say that the `Context` is abstract, not only that it is not `()`.
  - **DevOps:** Y — The spec has to say which program is legal, or the checker and the LSP will disagree about generic code. The error for this case must name the cause: "`T.Context` is abstract here, so this `with` installs no effect; add a bound `T: BlockHandler[Context = Handler[DB]]` or use `as`". *Concern:* without that explain text, the generic case gives a baffling "Context must be ()" error.
  - **AI/ML:** Y — A rule the spec does not state is a rule models guess wrong. One sentence prevents generic wrapper code that looks right but discharges no effect. *Concern:* the resulting error inside a generic fn will confuse users unless it says "Context is abstract here; the effect cannot be installed".
  - **Minimalism:** Y — Without this sentence, a generic `with t { }` would have to discharge an unknown effect, which would bring in effect-kinded generics through a side door. v1 deferred those (4-1). One sentence closes that door. *Concern:* Generic helpers over BlockHandler get an error that users may find surprising. The diagnostic must name the abstract Context as the cause.

Ballot options: Q1 X = BlockHandler with `Context == Handler[E]` installs it; Y = `ScopedHandler[E]`; Z = stdlib pair; R = cleanup clause on the handler literal. Q2 A = `Result[Connection, DBError]`; B = plain value. Q3 S = separate table row; W = widen row 2 to `() or Handler[E]`. Q4 I = install and bind. Q6 ONE = one flow-based lint for every `Closeable` or `BlockHandler` value; NARROW = only for `Context == Handler[E]`.

The owner approved the tally on 2026-09-29, including the spelling change from `with db.connect(p) { }` to `with db.connect(p)? { }`.

### Final Spec

```blink
pub type Connection {
    handle: Sqlite3
}

impl BlockHandler for Connection {
    type Context = Handler[DB]

    fn enter(self) -> Handler[DB] {
        sqlite_handler(self.handle)
    }

    fn exit(self, ok: Bool) {
        sqlite_close(self.handle)
    }
}

pub fn connect(path: Str) -> Result[Connection, DBError] {
    let handle = sqlite_open(path)?
    Ok(Connection { handle: handle })
}

with db.connect(":memory:")?, db.transaction() {
    db.exec("CREATE TABLE users (name TEXT)")?
}
```

- A `BlockHandler` whose `Context` is `Handler[E]` is a **scoped effect handler**. Order: evaluate, `enter()`, install, body, uninstall, `exit(ok)`. `exit()` runs under the outer handlers. §4.6.3 *Scoped effect handlers*.
- It gets its own row in the §4.7 disambiguation table. Without `as`, the check order is `Handler[E]`, then `Context == Handler[E]`, then `Context == ()`; any other `Context` is E0839.
- `as` installs and binds; it never changes what the block does.
- The rule applies only when `Context` normalizes to `Handler[E]` with a concrete `E`. An abstract `Context` in generic code installs nothing and is E0839.
- Comma-separated `with` items nest from left to right; teardown is LIFO; a `?` on item *i* fires before item *i* is entered.
- `db.connect(path)` returns `Result[Connection, DBError]`.
- One lint, `ScopedValueWithoutWith`, covers every `Closeable` and `BlockHandler` value that does not go into a `with` (flow-based). Its numeric code waits for the W0600 clash fix.
- E0601/E0602 cover the `Handler[E]` that `as` binds.
- Not decided here (separate tickets): a fallible `enter`; `exit(self, ctx, ok)` or a lazy open; retiring `sqlite_connect`, `db_connect` and `DbConnection`; the std.db / db_sqlite import cycle; `sqlite_open` reporting failure.

### AI-First Review

| Criterion | Result | Note |
|---|---|---|
| Learnability | Pass | One table row and one §4.6.3 subsection; the example is the stdlib type itself |
| Consistency | Pass | Reuses `BlockHandler` and `Handler[E]`; `?` on a with-item follows §5.5 |
| Generability | Pass | Users write `with db.connect(p)? { }`, the same shape as every other `with` handler item |
| Debuggability | Pass | E0839 names the missing `?` and the abstract `Context`; the lint names the `with` fix |
| Token efficiency | Pass | One `?` over the old spelling; no second item or binder |
