[< All Decisions](../DECISIONS.md)

# With Forms: `Closeable` Folds into `Scoped` — Design Rationale

Spec ticket: the `with` keyword has two shapes, a five-row disambiguation table, two check orders that depend on `as`, and two cleanup traits (`Closeable` and `BlockHandler`) with overlapping jobs. The ticket counted five `with` forms. The panel found one keyword and two shapes (`with x { }` and `with x as n { }`), and it worked on the rule text and the two traits.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim or excerpted with attribution. A local ticket ID in quoted text shows as [ticket]. In Phase A, a heading inside a quoted proposal shows as a bold line, and the words are unchanged.

#### Phase A — Independent proposals

Each panelist's preferred proposal follows. Systems preferred S1 (delete `Closeable`) and named S2 (the fold, which became option K) as the fallback, so both appear.

##### Systems

**Proposal S1 (preferred): one cleanup trait. Remove `Closeable` and keep `BlockHandler`**

**Spec change**
- Delete `trait Closeable` from §3.6, §5.5 and `lib/std/traits.bl`.
- A resource is a `BlockHandler` with `type Context = Self`, `enter` returns `self`, and `exit` releases the resource.
- §5.5 keeps its subject (deterministic release) and points to §4.7.2 for the mechanism.
- The disambiguation table goes from 5 rows to 2:

| Syntax | Type of expr | Meaning |
|---|---|---|
| `with expr { }` | `Handler[E]` | install handler |
| `with expr { }` / `with expr as name { }` | `T: BlockHandler` | call `enter`, run the body, call `exit(ok)`. `as` binds `Context`. If `Context` is `Handler[E]`, also install it. Without `as`, `Context` must be `()` or `Handler[E]` (E0839). |

- These go away: the Closeable-first lookup order and the error for a type that implements both traits.
- The E0601 escape rule (`CloseableEscapesScope`) becomes a rule for every `as` binding of a `BlockHandler`. Today a `tx` from `db.transaction()` can be sent to a spawned task with no error. A resource can't. That gap is a soundness hole, and this change closes it.

**Code**
```blink
pub type File {
    fd: Int
}

impl BlockHandler for File {
    type Context = File

    fn enter(self) -> File { self }

    fn exit(self, ok: Bool) ! FS.Write {
        libc_close(self.fd)
    }
}

fn copy(src: Str, dst: Str) -> Result[(), FsError] ! FS.Read, FS.Write {
    with open(src)? as a, create(dst)? as b {
        b.write(a.read_all()?)?
    }
    Ok(())
}
```

**Cost (systems view)**
- Zero runtime cost:
  - An identity `enter` inlines to nothing, because it is a static function in the same TU.
  - `ok` is a constant on each exit path. A `close`-style `exit` ignores it, so it is dead.
- One honest exception: under `--link-archive`, a lib/std `enter` lives in the archive. Without LTO it costs one direct call per `with` entry. That is noise next to the I/O a resource wraps.
- Codegen loses one protocol, one trait lookup and one diagnostic path. That includes the code that produced the second bug above.
- Two smaller semantic points:
  - The `as` binding is now a copy of `self` returned by `enter`, not the original.
  - Bindings are immutable and handles are pointer-shaped, so `exit` sees the same handle. Nothing changes for users.
- Downside: each resource impl is 3 lines longer (`type Context = Self`, the identity `enter`, and `ok` in `exit`). I accept that: what you write is what runs.

**Migration cost**
- About 44 `impl Closeable` across lib/, src/, tests/ and examples/. The rewrite is mechanical and an ast-grep rewrite can do it.
- Compiler: remove `CleanupProtocol.Closeable` and generalize E0601. W0610/W0611 already treat both traits as one class, so nothing changes there.
- Spec: rewrite §5.5, the §4.7 table and the §2.18 table. §2.18 is already stale. §5.5 also still shows the old `with conn = db.connect()` syntax, which this rewrite would fix.
- Bootstrap follows the 3-step dance:
  1. Accept both traits (no change).
  2. Migrate src and lib.
  3. Delete `Closeable`.
- Nothing has been released that this breaks for users.

**Other languages:** Python's `__enter__`/`__exit__` is this model, and `enter` returns the bound value. Rust uses one trait (`Drop`). Zig and Go `defer` are one mechanism. None of them has two cleanup traits.

---

**Proposal S2 (fallback): keep `Closeable` as a compiler-defined `BlockHandler`**

**Spec change**
- `Closeable` stays as the name users write.
- The spec says that `impl Closeable for T` gives `T` a `BlockHandler` with `Context = T`, an identity `enter`, and `exit(ok)` that calls `close()`.
- A blanket impl can't express this today (brief fact 9), so it is a compiler rule.
- The table shrinks to the same 2 rows as S1, and codegen still collapses to one protocol.

**Tradeoffs**
- Shorter resource impls.
- It keeps two ways to write one thing, plus a hidden impl that the compiler adds and the user cannot see.
- I like hidden impls less than 3 extra lines.

**Migration:** about zero lines of user code. You need the compiler rule.

---

##### Web/Scripting

**Proposal A (preferred): "One rule for `as`", with Closeable defined as a short form of BlockHandler**

**Spec change**
1. The table goes from 5 rows to 2.
   - **Rule 1:** if `expr: Handler[E]`, install it for the block. `as` is not allowed, and the error says why.
   - **Rule 2:** if `expr` is a *scoped value* (`Closeable` or `BlockHandler`), run enter, then the body, then exit. If `Context` is `Handler[E]`, also install it.
2. `as name` is **optional** on every scoped value. When present, it binds the context.
3. The spec defines `Closeable` as exactly equal to a BlockHandler with:
   - `Context = Self`
   - `enter(self) = self`
   - `exit(self, ok) = self.close()`

   This is a compiler rule, because a blanket impl cannot express it today (fact 9). With that rule, `with f as x` binds the resource itself, as it does now. The order of checks in the table disappears, because a scoped value has only one behaviour.
4. Drop E0839's "non-`()` Context without `as`" case. A discarded context is legal, as in Python's `with open(p):`.
   - E0839 stays only for "not a handler and not a scoped value", for example `with 5 { }`.
   - The generic `fn run[T: BlockHandler](t: T) { with t { } }` case becomes legal (it installs nothing).
5. Implementing both traits stays an error. The text changes to "Closeable already is a BlockHandler" instead of "ambiguous".
6. W0610 and W0611 do not change. They already treat the two traits as one class.

**Examples**
```blink
// lock guard, no binding needed: legal now
with mutex.lock() {
    counter.incr()
}

// resource, bound
with sqlite_open(path)? as conn {
    conn.exec("select 1")?
}

// transaction, savepoint handle discarded: legal now
with db.transaction() {
    db.execute(t"insert into t values (1)")?
}

// same transaction, bound
with db.transaction() as tx {
    log_savepoint(tx)
}

// handler literal and arena: just values
with handler Log { fn log(msg: Str) { } }, arena {
    work()
}
```

**Tradeoffs (DX)**
- A dev learns one sentence: "`with` installs a handler or scopes a value, and `as` gives you the value."
- No rule asks "did I need `as` for this type?"
- `Closeable` stays a one-method trait for the 90% case (files, sockets, statements). This matches JS `[Symbol.dispose]`, Kotlin `Closeable`, and C# `IDisposable`.
- Cost: a resource opened without `as` can't be used in the body. That is harmless, and it is what Python allows. If the panel wants it, a lint for a non-unit Context dropped on a `Closeable` would cover it.

**Migration**
- No existing code breaks. Every program that is legal today stays legal: this proposal only relaxes rules.
- Spec work:
  - §4.7 table;
  - §2.18 table (that table is already stale);
  - §5.5 text, plus a fix for the `with conn =` example;
  - §4.7.2 Context paragraph at ~2465.
- Compiler work: one typecheck branch, the E0839 narrowing, and Closeable lowering through the BlockHandler path.
- No change to lib/std, the ~88 impls, or the tests. Existing E0839 tests that use a non-unit Context need their expected result changed.

**Cross-language note:** this is Python's model (one protocol, optional `as`) with Kotlin/C#'s one-method short form for plain resources.

---

##### PLT

**P1 (preferred): one bracket rule; Closeable is shorthand for it**

**Spec changes**

1. **Replace the §4.7 disambiguation table** with two typing rules and one bridge rule:

```
(W-Handler)
Γ ⊢ e : Handler[E] ! ρe        Γ, x : Handler[E] ⊢ body : U ! ρ ∪ {E}
──────────────────────────────────────────────────────────────
Γ ⊢ with e as x { body } : U ! ρ ∪ ρe

(W-Block)
Γ ⊢ e : T ! ρe     T : BlockHandler     C = norm(T.Context)
δ = {E}  if C ≡ Handler[E] and E is concrete at this site,  else ∅
Γ, x : C ⊢ body : U ! ρ ∪ δ
──────────────────────────────────────────────────────────────
Γ ⊢ with e as x { body } : U ! ρ ∪ ρe ∪ eff(enter) ∪ eff(exit)

(Bridge)
impl Closeable for T { fn close(self) ! ρc { ... } }
⟹ the compiler synthesizes
   impl BlockHandler for T {
       type Context = T
       fn enter(self) -> T { self }
       fn exit(self, ok: Bool) ! ρc { self.close() }
   }
```

2. **`as` is only a binder.** `with e { }` means `with e as _ { }`. Drop the rule "without `as`, Context must be `()`". E0839 stays for an item that is neither `Handler[E]` nor `BlockHandler`.
3. **Coherence.** `impl Closeable` plus an explicit `impl BlockHandler` on one type is an overlapping-impl error. The rule is the same as today; the reason is now ordinary coherence instead of a special ambiguity rule.
4. **Arena.** §5.2.1 says arena "behaves as a `BlockHandler`". Change this to: arena is a keyword item with its own typing rule (promotion and escape boundary), sequenced like a block handler whose Context is `()`. No change to what arena does.
5. **Handler expression.** No longer listed as a `with` form. §4.7 keeps "Handlers are values".

**Examples**

```blink
type FileHandle { fd: Int }

impl Closeable for FileHandle {
    fn close(self) ! FS {
        fs_close_fd(self.fd)
    }
}

fn read_config(path: Str) -> Result[Str, FsError] ! FS {
    with open_file(path)? as f {
        f.read_all()
    }
}

// A lock guard: the context is not needed, so no `as`
with mutex.lock() {
    counter.bump()
}

// Generic code over every scoped value; Closeable types now meet the bound
fn timed[T: BlockHandler](label: Str, t: T) ! Time.Read, IO.Log {
    with timer(label), t {
        do_work()
    }
}

timed("tx", db.transaction())
timed("file", open_file("a.txt")?)
```

**Tradeoffs**

- **Sound by construction.** Today's Closeable desugar (§5.5) is: evaluate, bind, body, `close()` on every catchable unwind. The bridge gives: evaluate, `enter` (which returns the value unchanged), bind, body, `exit(ok)` (which calls `close()`). The steps match one for one, so Closeable behaviour does not change.
  - The catchable-unwind table, the E0824 rule for a cleanup that panics, W0610/W0611 and E0601/E0602 already treat both traits as one "scoped value" class. Under P1 that class is simply "T : BlockHandler".
- **Composes better.** Today `fn f[T: BlockHandler]` cannot take a Closeable, so generic code over scoped values has to be written twice. The bridge has to be visible to bound solving, not only to `with` dispatch, so that `timed` above works.
- **No blanket-impl machinery needed.** Fact 9 says `impl[T] BlockHandler for T where T: Closeable` cannot be written today. The bridge is a synthesized impl, emitted per type at each Closeable impl site, the way a derive is. It is monomorphic, so `ImplBinderUnused` and `PolyImplUnsupported` do not apply.
- **The "Context must be `()`" rule protects nothing.** Without `as` the context is unreachable, so no ill-typed use is possible. Forgetting `as` on a file gives "unknown name `f`" at the first use. Removing the rule makes `as` a pure binder, which is the orthogonal design, and matches the compiler.
- **Generic code with an abstract Context.** Parametricity requires that generic code never installs a handler. The rule already says this (`δ = ∅`). There is one trap: generic code with an abstract Context can silently use an outer handler where a reader expects an install. Today's E0839 guard covers only the case without `as`, so it was already partial. I keep the parametric rule. If the panel wants the trap covered, use a lint on any `with` whose Context is abstract, with or without `as`, not a type error tied to `as`.
- **Handler[E] stays primitive (W-Handler) and gets no BlockHandler impl.** Handler values are first-class: they are stored, returned and put in tuples (`make_test_env`). An impl would make every handler a "scoped value", and W0610, W0611 and E0601 would misfire on correct code.

**Migration cost**

- No source change in lib/std, tests or examples. The 44 Closeable impls and 45 BlockHandler impls all stay valid.
- Compiler work:
  - synthesize the bridge impl and let bound solving see it;
  - route `with` dispatch through two rules instead of five rows;
  - replace the ambiguity check with the overlap check.
- Spec work: §4.7 table, §2.18 table (already stale; the chore ticket can be folded in), §5.5 desugaring text, the §5.2.1 wording.

**Cross-language note**

Haskell's `bracket` is the single primitive here, and `withFile` is `bracket` with `return` as the acquire step. That is exactly the bridge. Rust uses one `Drop` trait. Python's `with` uses one protocol (`__enter__`/`__exit__`), and `contextlib.closing` is the same Closeable-to-protocol adapter. Koka keeps handler installation (`with h`) as a primitive separate from finalization (`finally`), the same split as W-Handler versus W-Block.

---

##### DevOps

**Proposal 2 (PREFERRED): Closeable is shorthand for BlockHandler**

**(b) Spec change.**
- One `with` protocol: `BlockHandler`. `Closeable` stays as the short way to write it. A compiler rule (fact 9 rules out a lib impl) says `impl Closeable for T { fn close(self) }` gives `T` this BlockHandler:
  - `type Context = T`
  - `enter(self) -> T` returns `self`
  - `exit(self, ok)` calls `close()`
- The table drops to three rows and one check order, the same with or without `as`:

  | Item type | Meaning |
  |---|---|
  | `Handler[E]` | install the handler |
  | `BlockHandler` with `Context == Handler[E]` | `enter()`, install the handler, `exit(ok)` |
  | `BlockHandler`, any other `Context` | `enter()`, `exit(ok)` |

- Plus one sentence: "`as name` binds the value of `enter()` (for a `Handler[E]` item, the handler itself). Without `as`, `Context` must be `Handler[E]` or `()`, else E0839."
- "`as` never changes what a `with` item does" becomes true for every row. Today it is false for Closeable.
- The both-traits error goes away as a special rule. A type that writes both impls gets the ordinary duplicate-impl error: "Closeable already provides BlockHandler for File".

**(c) Examples.** No user code changes.
```blink
impl Closeable for DbConnection {
    fn close(self) {
        self.handle.finalize()
    }
}

fn load(path: Str) -> Result[Int, DbError] ! DB {
    with db.open(path)? as conn, conn.transaction()? {
        conn.execute("UPDATE t SET n = n + 1")?
        Ok(1)
    }
}
```

**(d) Tooling.**
- One check function covers both shapes, so the `as`-path hole cannot recur as a separate bug.
- LSP hover on a `with` item shows one line: `DbConnection: BlockHandler (via Closeable), binds DbConnection`.
- Go-to-definition on the `with` keyword can jump to `enter`/`exit`, or to `close` for Closeable types.
- One error family:
```
error[NonHandlerWithItem]: a with-item must be a Handler[E] or a BlockHandler (Closeable counts), got Result[DbConnection, DbError]
  help: add ? or .unwrap() to use the DbConnection the Result holds
```
```
error[NonHandlerWithItem]: `with` without `as` drops the value of enter(): DbConnection
  --> app.bl:7:10
   |
 7 |     with db.open(path)? {
   |          ^^^^^^^^^^^^^^
  help: bind it: `with db.open(path)? as conn`
```
- Tradeoff: Closeable gets a hidden derived impl. Hover and `blink doc` must show it, or the user will not know where `enter`/`exit` come from.
- `close()` cannot see `ok`. Same as today.

**(e) Migration.**
- lib/std, tests, examples: zero source edits for the 44 Closeable and 45 BlockHandler impls, the 1 `with...as` in lib and the 301 in tests.
- Compiler: a derived impl, one check path, and removal of the both-traits error. Per CLAUDE.md a 3-step refactor (add the rule, move the checks, remove the old path), because Closeable is compiler-known.
- Spec: §4.7 table, §5.5 desugar text, §2.18.
- `blink fmt`: no change.

**(f) Cross-language.** Python `with` has one protocol, `as` binds the result of `__enter__`, and there is one error. This makes Blink's `with` that model plus effect handlers, and keeps Java's one-method convenience for the simple case.

##### AI/ML

**Proposal A (preferred): "`as` means you want a name". One rule, three rows, both traits kept**

**Spec change**

1. Replace the five-row §4.7 table with one rule: **`as name` binds the item's Context. Leave out `as` to discard it.** Whether `as` is present never depends on the type.
2. Define Closeable by a compiler rule in terms of BlockHandler. A blanket impl cannot do this today (brief fact 9). The rule: a `T: Closeable` item acts as a BlockHandler whose `Context` is the value itself, whose `enter` returns it, and whose `exit(ok)` calls `close()`. Users and LLMs see one model, and Closeable is the short form for the common case.
3. The new table, keyed only on type:

   | Type of item | On enter | `as name` binds | On exit |
   |---|---|---|---|
   | `Handler[E]` | install for `E` | the handler | uninstall |
   | `T: BlockHandler` | `enter()`; if `Context == Handler[E]` with concrete `E`, install it | `Context` | uninstall, then `exit(ok)` |
   | `T: Closeable` | nothing | the value | `close()` |
   | anything else | E0839 (keep the "this is a Result; add `?`" hint) | | |

4. Keep these rules unchanged: a type that implements both traits is an error; comma items nest left to right; teardown is LIFO; `?` runs before enter; the catchable-unwind set; W0610 and W0611; E0601 and E0602.
5. Remove the "other Context without `as` is E0839" rule and the abstract-Context paragraph at §4.7.2 line 2465. Generic `with t { }` on `T: BlockHandler` simply discards the Context.

```blink
fn copy_header(src: Str, dst: Str) -> Result[(), FsError] ! FS {
    with fs.open(src)? as input, fs.create(dst)? as output {
        output.write(input.read_line()?)?
    }
    Ok(())
}

fn migrate(rows: List[Row]) -> Result[(), DBError] ! DB.Write {
    let conn = db.connect(path)?
    with conn {
        for r in rows {
            db.execute(t"INSERT INTO t VALUES ({r.id})")?
        }
    }
    Ok(())
}

fn timed[T: BlockHandler](t: T) ! IO {
    with t {
        io.println("inside")
    }
}
```

Today `with conn { }` is an error for a Closeable `conn`, and `with t { }` is E0839 in the spec. Proposal A makes both legal.

**Why I prefer it (decision points)**

- **Using a `with` today:** about 4 type-driven choices. Is it a Handler? Which trait is it? Is its Context `()`, `Handler[E]` or something else? So is `as` legal, required or forbidden?
- **Using a `with` under A:** 1 choice, and it is the writer's own intent: "do I need a name?" The only remaining type error is "not a scoped value", and its fix (`?`) is already spec'd.
- **Authoring a type:** no change. Pick Closeable for "release only", and BlockHandler for enter/exit with `ok`.
- **Tokens:** no change for code that is legal today. The spec loses about two rows and two paragraphs.
- **Learning from the spec alone:** "`as` binds the Context; for a Closeable the Context is the value" fits in one sentence. The current check order needs a table plus ordering prose, and the compiler already does not follow that prose.

**On minimalism's earlier objection**

At scoped-effect-handler.md:76, minimalism objected that "the no-`as` form silently discards a non-`()` Context... a separate language change". I agree this is that separate change, and this is the panel where it belongs. I bring it now for three reasons:
- the compiler already discards (finding 2), so the spec text is the outlier;
- discarding is harmless, because `enter` and `exit` still run;
- the error forces an `as _` that carries no information.

If a type has a Context that is unsafe to drop, its author can ask for a must-use marker later (YAGNI for now). If the panel wants it, this can be voted on its own as **A2** (discard rule), separate from **A1** (the Closeable fold and Closeable without `as`). A1 alone already removes the worst trap.

**Tradeoff to name**

`let f = open()?` then `with f { }` leaves `f` in scope after `close()`, so a use-after-close is possible. This hazard already exists for BlockHandler values (`let tx = db.transaction()`). The idiomatic form stays `with open()? as f`, and docs and examples should lead with it. A later lint can extend W0611's flow analysis to "use after `with`".

**Migration**

Zero of the 44 Closeable impls and zero of the about 44 BlockHandler impls change. No user code breaks, because the change only widens what is accepted. On the compiler side:
- lowering for a Closeable without `as`;
- remove the NonHandlerWithItem path for Closeable;
- update the spec text.

Tests that assert the current errors must flip: test_typecheck_with_item_must_be_a_handler.bl, test_typecheck_with_scoped_effect_handler_item_rules.bl, and possibly test_with_resource.bl and test_with_parse.bl. Do not delete them. Turn the rejections into acceptance cases, and keep the Result-without-`?` rejection.

**Cross-language**

Python `with x [as n]` (the name is always optional, and `__enter__`'s return is what gets bound), C# `using (x)` or `using (var n = x)`, Java try-with-resources, Kotlin `use { }`. In each of these, whether you give a name is the writer's choice and never a type rule. Python's model (bind enter's return; for most file types that is `self`) matches A almost exactly, and LLM training data is dense with it.

---

##### Minimalism

**Proposal M1: one rule, `Closeable` as the short form of `BlockHandler` (PREFERRED)**

**What changes in the spec.** Replace the 5-row table (§4.7, and the stale copy in §2.18) with one rule:

> Each `with` item has a scope protocol, found from its type alone:
> - `T: BlockHandler`: the user's `enter`/`exit`.
> - `T: Closeable`: compiler-known as a `BlockHandler` with `Context = T`. `enter` returns the value, and `exit(ok)` calls `close()`.
> - `Handler[E]`: `Context = Handler[E]`. `enter` returns the handler, and `exit` does nothing.
>
> When `Context` is `Handler[E]`, the item installs that handler for the body. `as name` binds the value that `enter()` returned. Without `as`, `Context` must be `()`/`Void` or `Handler[E]`; anything else is E0839.

What this removes:
- The two check orders ("no `as`: Handler, then BH-with-Handler, then BH-()" and "`as`: Closeable first, then BH").
- The special "Closeable and BlockHandler both is an error" rule. It becomes an ordinary duplicate-impl conflict, because `Closeable` already provides the `BlockHandler` protocol.
- The text that is split between §5.5 and §4.7.2. §5.5 keeps the lints and refers to the one rule.

It also makes the sentence "`as` never changes what a `with` item does" true. Today the `as`-dependent check order contradicts it.

The new rule allows one more case, `with h as g` on a `Handler[E]`. This does not add a concept: the case follows from the rule, and the compiler already accepts it.

```blink
import std.traits

type FileHandle { fd: Int }

impl Closeable for FileHandle {
    fn close(self) { sys_close(self.fd) }
}

type Timer { label: Str, start: Int }

impl BlockHandler for Timer {
    type Context = Void
    fn enter(self) { }
    fn exit(self, ok: Bool) { log_duration(self.label, self.start, ok) }
}

fn copy(src_path: Str, dst_path: Str) -> Result[Void, IoError] ! IO {
    // Each item: find the protocol by type, enter, maybe install, maybe bind.
    with timer("copy"), open(src_path)? as src, create(dst_path)? as dst {
        dst.write(src.read_all()?)?
    }
    Ok(())
}

fn greet_twice(h: Handler[Greeter]) ! IO {
    with h as g {    // legal under the one rule: binds the handler that enter() returns
        io.println(greeter.greet())
        run_with(g)
    }
}
```

**Tradeoffs (minimalism view).**
- One rule replaces six (5 rows plus the "both is an error" rule).
- No new trait, no new syntax and no new feature such as default associated types. The common file-handle case stays at one method.
- Cost: the spec says `Closeable` is compiler-known as a `BlockHandler`, which is a hidden link and not a visible impl. It is already compiler-known (hygiene list §3.x, lints W0610/W0611, E0601/E0602), so this only says what it is.

**Migration.**
- Code: none. All 44 `Closeable` impls stay (in `lib/`: `db_sqlite.bl`, `db_stmt.bl`; in `examples/`: `json_validator.bl`; the rest are tests). All 45 `BlockHandler` impls stay.
- Spec text: §2.18 (table), §3.6 (`Closeable` row), §4.7 (table), §4.7.2 (shorter), §5.5 (point to the rule), §7 `ffi.scope` (no change in meaning).
- Compiler: the `with` dispatch in typecheck can follow the rule directly. Diagnostics stay the same, except that the "both traits" error becomes the general duplicate-impl message.

**Other languages.**
- Python has one context-manager protocol, and file objects implement it with `__enter__` returning `self`. M1 is that, with `close()` as the short form.
- Java's `AutoCloseable` plus try-with-resources is the one-method form only, with nothing like `BlockHandler`.

---

#### Moderator facts

Between Phase A and Phase B the moderator posted these facts. They come from the codebase and were not voted. Text of the option digest and the ballot:

##### F1 (arena)

> - **F1. Brief fact 4 was wrong.** sections/05_memory_compile_errors.md line 110 says: "`with arena { body }` behaves as a `BlockHandler` (§4.7.2), as if the compiler builds a new scope value at each `with arena`. `arena` is a keyword form, not a value that a program can store and enter again." devops found this.

##### V6 (no vote needed)

> Moderator fact for V6: sections/04_effects.md line 2489 already says: "`BlockHandler` bindings follow the
> same scoping rules as `Closeable` bindings (E0601, E0602)." The missing emit site is bug [ticket]. V6 is
> therefore not on the ballot.

#### Phase B — Debate highlights

Position shifts, quoted from the round 1 replies. All six panelists ended the round with "STABLE, ready to vote".

##### Systems: D to K

> **Main: K (changed from D).**
> - D and K give the same machine code if the bridge is a real per-type impl. Either way, one cleanup protocol remains in codegen. The cost I cared about (two lowering paths, two bugs in [ticket]) goes away under K too.
> - min's point decides it for me: "`close` is a verb that users call directly ... types would need a separate `close` method anyway". Under D a resource writes `close` plus an `exit` that calls it, which is more code for the same C.
> - **My condition for K:** the bridge must be a synthesized, monomorphic `impl BlockHandler for T`. It must not be a third row in the dispatch table. Only one lowering path may remain, so `CleanupProtocol.Closeable` goes away.
>   - aiml A keeps a separate "`T: Closeable` | nothing | the value | `close()`" row. That keeps two paths, and two paths is how today's bugs happened.
>   - I vote for the plt P1 and devops P2 wording: one bracket rule, with Closeable derived.
> - Order: K > D > Z > U. U keeps both paths and adds a third binding rule.

##### Systems: V1, E0839 to discard

> **V1 (discard Context without `as`): legal (changed from E0839).**
> - plt is right: "Without `as` the context is unreachable, so no ill-typed use is possible."
> - Dropping the Context costs nothing at run time: `enter` and `exit` still run, and the unused value is dead.
> - gen0 and gen1 already accept it. Keeping E0839 means making the compiler stricter, which breaks code that compiles today to stop no fault.
> - plt's abstract-Context trap is real, but `as` does not fix it. It is a lint question, not this vote.

##### DevOps: V1, E0839 to discard

> **V1: CHANGED to "legal, Context discarded"** (web A4, plt P1.2, aiml A2). Phase A I kept E0839. plt convinced me: "Forgetting `as` on a file gives 'unknown name `f`' at the first use." The mistake fails loudly at the first use anyway, so E0839 only adds a rule users must learn. Condition: the unknown-name diagnostic gets a help line when a `with` item of a matching type sits just above, for example `help: bind it: with fs.open(p)? as f`. The abstract-Context trap plt names should be a lint later (YAGNI now).

##### DevOps: withdrew U

> **Main: K.** D second, Z third, U last (I drop U; K does what it does with less).

##### Minimalism: V1, E0839 to discard

> **V1, a `with` item with no `as`: I CHANGE to legal; the Context is discarded.**
> - In Phase A I kept E0839 because that is how the M1 rule was written. The plt and aiml texts changed my mind.
> - Dropping the rule deletes a rule, and that is my lens.
> - The compiler already discards the Context (F2).
> - The guard prevents no harm: `enter` and `exit` still run.
> - It makes `as` a pure binder, which is the claim §4.7 already makes.
> - E0839 stays for "not a handler and not a scoped value".
> - plt's trap with an abstract Context in generic code is real. It exists today with `as` too, so I would add a lint only when someone hits it.

##### Web/Scripting: V2, reject to allow

> - **V2 (`with h as name` on `Handler[E]`): allow it; it binds the handler.** This changes my Phase A position (Rule 1 forbade it), for three reasons:
>   - The compiler accepts it today, and it is harmless.
>   - Forbidding it adds an exception to "`as` binds what the item gives you". No exceptions is easier to learn.

##### PLT: correction after F2

> ## Correction (F2)
> My a.bl result came from the stale build/blink. With gen1, a Closeable item without `as` gives E0839. Under K, then, V1 relaxes a rule the compiler enforces today. It does not write down existing behaviour, as I claimed in Phase A. My other two probes still hold.

#### Phase C — Final vote

The ballot, in the moderator's words, followed by each vote. Each vote is silent: panelists did not see the others' votes. All four questions passed 6-0.

- **Q1: Main option** (6-0, K)

> Ballot text:
>
> - **K.** Keep `Closeable`. The compiler synthesizes, at each `impl Closeable for T`, a monomorphic
>   `impl BlockHandler for T` with `type Context = T`, an `enter` that returns `self`, and an `exit(ok)` that
>   calls `close()` (the effects of `close` become the effects of `exit`). The bridge is visible to bound
>   solving, so `T: BlockHandler` accepts a Closeable type (V5). `Handler[E]` stays a primitive rule with no
>   BlockHandler impl, and it is not a scoped value (V7, plt W-Handler). A type with both impls gets the
>   ordinary overlap error, reported once, with the help note "Closeable already provides BlockHandler for T"
>   (V8). Arena wording follows plt (V3).
> - **D.** Delete `Closeable`. `BlockHandler` is the only trait.
> - **U.** Keep both traits with no fold, and make the `as` rule uniform.
> - **Z.** Keep the current design. Fix the table and the diagnostic holes.

  - **Systems:** K

    > **Vote:** K
    >
    > **Reasoning:** With a monomorphic synthesized impl, K and D give the same C: one cleanup protocol, a static identity `enter` that inlines away, and a constant `ok` that is dead in a `close`-style `exit`. K gets that with no source churn and keeps `close()` as a verb users call. Because bound solving sees the bridge (V5), `fn f[T: BlockHandler]` gets a Closeable type through monomorphization with no extra work.
    >
    > **Concern:** The implementer could do the bridge as a dispatch special case and leave `CleanupProtocol.Closeable` in codegen. Then the two effectful-cleanup bugs ([ticket]) stay two separate fixes. The spec text should say the bridge is an impl, so that one lowering path is the only correct implementation.

  - **Web/Scripting:** K

    > **Vote:** K
    >
    > **Reasoning:**
    > - A dev learns one model, Python's context manager: `with` brackets the block, and `as` gives you the value.
    > - `Closeable` stays the one-method trait that JS, Kotlin, C# and Java devs already know, for the 90% case of releasing a handle.
    > - Zero existing impls break.
    > - The bridge must reach bound solving (V5). Otherwise `fn f[T: BlockHandler]` rejecting a File is a new Stack Overflow question.
    >
    > **Concern:** if hover and `blink doc` do not show "BlockHandler (via Closeable)", users will not know where `enter`/`exit` come from when they read errors or generic bounds.

  - **PLT:** K

    > **Vote:** K
    > **Reasoning:** Two typing rules remain: W-Handler and W-Block. `Closeable` becomes one equation (the bridge), not a parallel mechanism. Closeable keeps its current meaning because the bridge's steps match today's desugar one for one: evaluate, bind, body, close on every catchable unwind. Since bound solving sees the bridge (V5), generic code over scoped values composes, and the "both traits" rule becomes ordinary coherence.
    > **Concern:** the bridge must be one synthesized impl that the dispatch, the trait solver, the lints and codegen all share. If a compiler path still special-cases `Closeable`, the spec's "a Closeable is a BlockHandler" judgment will drift from what the checker does.

  - **DevOps:** K

    > **Reasoning:** K leaves one check path for both `with` shapes. Today the `as` shape has no check at all ([ticket]), so one path closes that hole for good. K keeps the one-method impl and avoids the UnusedVariable `ok` noise that D puts into 44 impls. Hover and `blink doc` can show the synthesized impl, the way rust-analyzer shows a derive.
    > **Concern:** the synthesized impl may stay invisible in hover, `blink doc` and `blink query`. Then users see "File: BlockHandler" with no source line to jump to. Ship the tooling with the rule, not later.

  - **AI/ML:** K

    > **Vote:** K
    >
    > **Reasoning:** K gives users and models one model of a scoped value and one `as` rule. It keeps `close()`, the release verb every model already writes, and none of the 44 impls have to change. sys is right that the bridge must be a real synthesized impl and not a separate dispatch row. The ballot text says so, and I accept it over the separate Closeable row in my Phase A table. With V5, `T: BlockHandler` accepts a Closeable type, so a model that writes that bound does not hit a contradiction.
    >
    > **Concern:** If hover, `blink doc` and `blink llms` do not show "BlockHandler (via Closeable)", models will not learn the bridge from the docs. They will write a redundant `impl BlockHandler` and hit the overlap error.

  - **Minimalism:** K

    > **Vote:** K
    > **Reasoning:** K removes the check order, the special "both traits" error, three table rows and one codegen path, and zero user lines change. D gets the same removals but deletes a one-method trait at the cost of 44 rewrites and the loss of `close()` as a verb users call. Each of those types would then need `close()` back as a plain method, so D only moves the duplicate. The bridge is one equation, the same kind of rule as `@derive`, not a new mechanism.
    > **Concern:** If the bridge ships as a third dispatch row instead of a real synthesized impl, we keep two lowering paths and the rule text grows back. sys's condition (one protocol, `CleanupProtocol.Closeable` removed) must be in the spec text.

- **Q2: A `with` item without `as` whose Context is neither `()` nor `Handler[E]`** (6-0, Discard)

> Ballot text:
>
> - **Discard.** Legal. `enter` and `exit` run and the Context is discarded. E0839 stays only for an item that
>   is neither a `Handler[E]` nor a scoped value.
> - **E0839.** An error, as the spec says today.

  - **Systems:** Discard

    > **Vote:** Discard
    >
    > **Reasoning:** `enter` and `exit` still run, and the unbound Context is a dead value, so this costs nothing at run time. It is also not unsafe: no name exists to misuse it. gen0 and gen1 already accept it, so keeping E0839 would make the compiler stricter to stop no fault. It also makes `with t { }` legal in generic code over `T: BlockHandler`.
    >
    > **Concern:** In generic code with an abstract Context, a reader can expect a handler install that does not happen (plt's trap). That needs a lint later, not a type rule.

  - **Web/Scripting:** Discard

    > **Vote:** Discard
    >
    > **Reasoning:**
    > - Under K, keeping E0839 would make `let f = open()?` followed by `with f { }` an error for a file but legal for a transaction. Whether `as` is allowed would hang on a type the writer can't see.
    > - A forgotten `as` already fails at once as "unknown name".
    > - Python has allowed `with x:` for 20 years with no footgun.
    >
    > **Concern:** the "unknown name" error must get a help line that points at the `with` item above (devops' condition). If it doesn't, the first-hour user experience suffers.

  - **PLT:** Discard

    > **Vote:** Discard
    > **Reasoning:** `as` then only binds a name: `with e { }` means `with e as _ { }`. A discarded Context has no name, so no ill-typed use of it can occur. E0839 there protects nothing, and it rejects the basic generic form `fn run[T: BlockHandler](t: T) { with t { } }`. Parametricity holds either way, because an abstract Context never installs a handler.
    > **Concern:** in generic code with an abstract Context, the body can silently use an outer handler where a reader expected an install. If this shows up in real code, a lint on abstract Contexts (with or without `as`) is the right tool, not E0839.

  - **DevOps:** Discard

    > **Reasoning:** A forgotten `as` fails loudly at the first use with "unknown name", so E0839 guards nothing harmful. It also adds a rule that depends on a type the writer cannot see at the call site. Condition: the unknown-name diagnostic gets the help line "bind it: `with <expr> as f`" when a matching `with` item is in scope above it.
    > **Concern:** plt's abstract-Context case in generic code becomes silent. Watch for it, and add a lint when someone hits it.

  - **AI/ML:** Discard

    > **Vote:** Discard
    >
    > **Reasoning:** With this vote, whether to write `as` depends only on whether the writer wants a name. It never depends on a Context type the writer cannot see at the call site. That is the main decision point this panel removes. It makes `let f = open()?` followed by `with f { }` legal, and it makes the generic `with t { }` legal. Lock guards such as `with mutex.lock() { }` also become legal, and that is the most common `with` shape in training data. A forgotten `as` still fails loudly as "unknown name" at the first use.
    >
    > **Concern:** The unknown-name error needs devops's help line ("bind it: `with ... as f`"). Without it, a model loops on the wrong fix.

  - **Minimalism:** Discard

    > **Vote:** Discard
    > **Reasoning:** This deletes a rule. `as` becomes a pure binder, so leaving out `as` no longer depends on a type the writer cannot see at the call site. The guard stops no unsound use: `enter` and `exit` still run, and a forgotten name fails at its first use.
    > **Concern:** Generic code with an abstract Context can silently use an outer handler where a reader expects an install. Answer that with a lint when someone hits it, not now.

- **Q3: `with h as name { }` where `h: Handler[E]`** (6-0, Allow)

> Ballot text:
>
> - **Allow.** It installs the handler and binds it to `name`.
> - **Reject.** An error.

  - **Systems:** Allow

    > **Vote:** Allow
    >
    > **Reasoning:** It installs as before and binds a copy of a first-class value, so it costs nothing and needs no new lowering. The compiler accepts it today. Rejecting it would add an exception to "`as` binds what the item gives".
    >
    > **Concern:** The name could be classed as a scoped value, and then E0601/W0610 would fire on correct code when it is stored or sent to a task. The spec must say it is a plain handler value.

  - **Web/Scripting:** Allow

    > **Vote:** Allow
    >
    > **Reasoning:**
    > - "`as` binds what the item gives you" should have no exceptions, and the compiler already accepts this form.
    > - My Phase A reject would have added a rule and an error for a harmless case.
    >
    > **Concern:** a user may think `name` is a new, scoped copy of the handler. The spec should say it is the same first-class value, and it is not a scoped value.

  - **PLT:** Allow

    > **Vote:** Allow
    > **Reasoning:** W-Handler binds the handler and installs it. `as` does the same on every item kind, so allowing it here adds no rule, and banning it would bring back an `as` rule that depends on the item's type. The binding is not a scoped value, so no lint applies to it.
    > **Concern:** a reader may think `name` is a scoped resource. The docs must say that handler bindings are ordinary values that may escape.

  - **DevOps:** Allow

    > **Reasoning:** "`as` binds what the item yields" with no exceptions is one rule, needs one hover text and gets no special error. The compiler accepts the form today, and the form does no harm.
    > **Concern:** none worth a rule. W0610/W0611 must not start to treat a handler that `as` binds as a scoped value.

  - **AI/ML:** Allow

    > **Vote:** Allow
    >
    > **Reasoning:** "`as` binds what the item gives" has no exception to learn. The compiler accepts this form today, and it is harmless.
    >
    > **Concern:** None of weight. The spec must state that the bound handler is a first-class value and not a scoped value, so W0610 and E0601 do not fire on it.

  - **Minimalism:** Allow

    > **Vote:** Allow
    > **Reasoning:** It follows from "`as` binds what the item gives". The compiler already accepts it. Rejecting it would add an error to ban a harmless case.
    > **Concern:** A reader may take the bound handler for a scoped value. The spec must say plainly that `Handler[E]` is not a scoped value, so W0610, W0611 and E0601 do not apply to it.

- **Q4: Rename `BlockHandler` to `Scoped`** (6-0, Yes)

> Ballot text:
>
> - **Yes.** Rename the trait (3-step bootstrap, about 45 impls).
> - **No.** Keep the name `BlockHandler`.

  - **Systems:** Yes (weak)

    > **Vote:** Yes (weak)
    >
    > **Reasoning:** It has no runtime or codegen cost. It removes the "Handler[E] or a BlockHandler" wording, which reads as two kinds of effect handler. It matches the existing term "scoped value". Pre-release is the cheapest time to do it.
    >
    > **Concern:** The 3-step bootstrap and gen0 re-pin for about 45 impls should not run at the same time as the K compiler work. Do the rename and the fold as separate steps, so that a miscompile in one does not hide in the other.

  - **Web/Scripting:** Yes

    > **Vote:** Yes
    >
    > **Reasoning:**
    > - Today "handler" names four things in one feature, and a new user will assume a BlockHandler handles effects.
    > - `Scoped` matches the spec's own term "scoped value" and the lint names.
    > - Pre-release is the cheapest time to pay for the rename.
    >
    > **Concern:** a half-done rename (spec, docs, `blink llms` topics, or diagnostics still saying "BlockHandler") is worse than no rename. All of them must change in the same release.

  - **PLT:** Yes

    > **Vote:** Yes
    > **Reasoning:** Today "handler" names both `Handler[E]` (effect interpretation) and `BlockHandler` (bracketing). These are different concepts, and the shared word misleads readers about W-Block. `Scoped` matches the spec's existing term "scoped value". The rename changes no semantics.
    > **Concern:** the 3-step bootstrap must keep both names for one cycle without a second bridge; a type alias is enough.

  - **DevOps:** Yes

    > **Reasoning:** Today the E0839 message says "a Handler[E] or a BlockHandler", which reads as two kinds of handler. `Scoped` matches the lint names users already see (`ScopedValueWithoutWith`). The LSP rename makes the migration mechanical, and pre-release is the cheapest time to do it.
    > **Concern:** the 3-step bootstrap rename could get mixed into the K work. Land K first and rename in a separate change, so a regression bisects to one of the two.

  - **AI/ML:** Yes

    > **Vote:** Yes
    >
    > **Reasoning:** Today "handler" names four things, and two of them are not effect handlers. Name overlap is a known source of model confusion. A model reading `BlockHandler` will assume it relates to `Handler[E]` and `handler E { }`. `Scoped` matches the spec's own term, "scoped value". Pre-release is the cheapest time for a mechanical rename.
    >
    > **Concern:** For a while, old `BlockHandler` text in examples, docs and model context will compete with the new name. The rename must update every example and the `blink llms` output in the same change, with no alias left behind.

  - **Minimalism:** Yes

    > **Vote:** Yes
    > **Reasoning:** A rename adds no surface. It removes a real name clash: "handler" now names four things, and two of them handle no effect. "Scoped value" is already the spec's own term, and pre-release is the cheapest time to pay for the 3-step bootstrap.
    > **Concern:** The rename churns about 45 impls and every diagnostic text. If it lands in the same slice as the K bridge, a failed bootstrap step is harder to bisect, so land it as its own change.

### Final Spec

```blink
// A Closeable type is a Scoped value with Context = Self.
fn read_config(path: Str) -> Result[Str, FsError] ! FS {
    with fs.open(path)? as f {
        f.read_all()
    }
}

// Without `as`, enter() and exit(ok) run and the Context is discarded.
with db.transaction() {
    db.execute(t"INSERT INTO orders ...")?
}

// `as` on a Handler[E] binds the same first-class handler value.
with mock_db(fixtures) as h {
    run_with(h)
}

// A Closeable type meets a Scoped bound.
fn timed[T: Scoped](t: T) ! IO {
    with t {
        io.println("inside")
    }
}
```

- `with` has two typing rules. (1) `Handler[E]`: install the handler. (2) A scoped value: `enter()`, install the returned handler if `Context` is `Handler[E]` with a concrete `E`, run the body, `exit(ok)`.
- `as` only binds a name: the handler for rule 1, the `Context` for rule 2. `as` never changes what a `with` item does.
- Without `as`, a scoped value runs `enter()` and `exit(ok)` and the compiler discards the `Context`, for every `Context`. E0839 stays only for an item that is neither a `Handler[E]` nor a scoped value.
- `Closeable` stays. A type that implements `Closeable` also implements `Scoped`, with `type Context = Self`, an `enter` that returns `self`, and an `exit(ok)` that calls `close()`. The effects of `close` are the effects of `exit`. The impl counts for trait bounds, so `T: Scoped` accepts a `Closeable` type.
- A type that writes both `impl Closeable` and `impl Scoped` gets the ordinary overlapping-impl error, with the help note "`Closeable` already provides `Scoped` for `T`".
- `Handler[E]` keeps its own rule. It does not implement `Scoped` and it is not a scoped value, so W0610, W0611 and E0601 do not apply to a handler. `with h as name` binds the same first-class value.
- `arena` is a keyword item with its own typing rule for promotion and escape. It runs in order like a scoped value whose `Context` is `()`.
- The trait `BlockHandler` is now `Scoped`. Lint and error names (`ScopedValueWithoutWith`, `CloseableEscapesScope`, and the rest) keep their names and codes.
- E0601 and E0602 already apply to every `as` binding of a scoped value (§4.7.2, *Interaction with async*). Their missing emit site is a compiler bug, not a spec question.
