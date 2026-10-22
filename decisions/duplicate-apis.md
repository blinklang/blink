[< All Decisions](../DECISIONS.md)

# Duplicate APIs for the Same Operation — Design Rationale

Spec ticket: duplicate APIs for the same operation. Several operations had two or more public forms: `read_file` and `fs.read`; `db.connect`, `sqlite_connect`, `db_connect` and `sqlite_handler`; `process_run` and `process.run`; `Map.contains` and `Map.contains_key`; `process_pid_kill` and `process_pid_send_signal`; `io.print`, `io.write` and `io.print_raw`; and list concatenation through `.append`, `.chain`, `[..a, ..b]` and `list_concat`. Principle 2 says there is one way to do each thing. The fs, process and pid items were already decided in §4.4; the panel settled the rest.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim.

#### Phase A — Independent proposals

##### Systems

**Verified in the repo:**
- `io.write` lowers to `blink_stdout_write`, which does `fwrite` and then `fflush` (`bootstrap/runtime_stdio.h:242`).
- `io.print_raw` lowers to `printf("%s")` with no flush (`bootstrap/runtime_core.h:3989`). So the two are not the same operation on the hardware today.
- `io.write_bytes` is the only stdout path that is safe for NUL bytes (`runtime_stdio.h:252`).
- `sqlite_connect` and `db_connect` call `sqlite_open` and do not check the result (`lib/std/db_sqlite.bl:356-365`).

###### P1. List concat: two forms, one code path

Keep `a.append(b)` and the literal `[..a, ..b]`. The two do not overlap: `append` is the binary method, and spread is literal syntax that mixes elements and lists (`[x, ..a, y]`). Remove the rest.

```blink
fn merge(a: List[Int], b: List[Int]) -> List[Int] {
    a.append(b)                 // one exact-size alloc + 2 memcpy
}
fn framed(xs: List[Int]) -> List[Int] {
    [0, ..xs, 0]                // one exact-size alloc, sized from the operands' lengths
}
fn lazy(a: List[Int], b: List[Int]) -> Int {
    a.iter().chain(b.iter()).fold(0, fn(s, x) { s + x })   // no alloc
}
```

- **`list_concat`:** add a row to the §3.2 removed-forms table that points to `a.append(b)`. The result type does not change, so the third column stays unmarked. The 6-0 rule already bans it (a function form of a built-in method). This closes the ticket note.
- **`List.chain`:** remove it, with no alias. Give the unknown-method diagnostic a fix that names `.append(other)` (eager) or `.iter().chain(...)` (lazy). The reason is cost: `Iterator.chain` allocates nothing, while `List.chain` allocates O(n+m). One name with two cost models hides cost.
- **Spec addition:** "`a.append(b)` and `[..a, ..b]` make one allocation of exactly `a.len() + b.len()`." Users can then pick either form with the same cost guarantee, and codegen has a contract to test.
- **Cross-language:** Rust has `extend` / `concat` / `chain` with the same eager/lazy split. Go's `append(a, b...)` is one form whose cost you can predict.

###### P2. Map: remove `contains_key`

`m.contains(k)` (from the `Contains` trait) and `m.contains_key(k)` monomorphize to the same hash probe. Two names for one machine operation is the textbook Principle 2 case. Keep `contains`, because generic code needs the trait. Remove `contains_key` from `MapOps`, which gives a 7-method surface, and give the unknown-method error a fix that names `.contains(k)`. This reopens the 3-2 surface vote on one method. "Reads more clearly" does not justify a second name with identical semantics; the rationale paragraph at `03_types.md:891` already admits that.

If the panel will not reopen that vote, my fallback is to keep both and add a lint (W-level) that prefers one name in a non-generic context. That is the worse option: a lint is a cost the user pays because the stdlib is not consistent.

###### P3. io output: remove `io.write`, specify `io.write_bytes`

- **`io.write(Str)`:** add a §4.4 removed row that points to `io.print_raw(s)`. The row is not marked (Void to Void).
- **The real gap is `io.write`'s flush:** the LSP and daemon depend on it. The spec must say what `_raw` does on the hardware, so I propose: "`_raw` operations write every byte of the `Str` (including NUL) and flush before they return. Each call is at least one `write(2)`." This is the price of an escape hatch. Code that wants buffering uses `print`. The lowering of `print_raw` must then change from `printf("%s")` to `fwrite(len)` + `fflush`. Today it truncates at the first NUL, which is a latent bug either way.
- **`io.write_bytes(b: Bytes)`:** keep it and specify it as a new table row. It is the binary counterpart of `io.read_bytes(n)`, and nothing else can put arbitrary bytes on stdout: `Str` is UTF-8 text, and protocol framing, image output and pipes need binary. Row: `Bytes`, raw stdout, flushes, not handler-dispatched, no trace (same class as `_raw`). Add no stderr twin until something needs one (YAGNI).

```blink
fn send_frame(body: Str) ! IO {
    io.print_raw("Content-Length: {body.len()}\r\n\r\n{body}")   // flushed before return
}
fn dump_png(img: Bytes) ! IO {
    io.write_bytes(img)
}
```

- **Interaction with [the open `_raw` ticket]:** if `_raw` is later removed, `write_bytes` and the flush rule move with whatever replaces it. The contract (exact bytes, flushed) must survive.

###### P4. DB: one constructor, every failure in the type

`db.connect(path)?` stays the only public form (Q1 5-0).

- **`sqlite_connect`, `db_connect`:** make them private (not `pub`). They are the worst offenders on systems grounds: `sqlite_open` failure has no error path, so a bad path becomes a use of a null handle later, far from the cause.
- **`sqlite_handler(handle)`:** make it private, as the backend internals of `db.connect`.
- **Removed rows:** llms-full.md documented all three, so they exist in training data. Add §4.4 removed rows that point to `db.connect(path)`. Mark the third column on `sqlite_connect` and `db_connect`, because the result changes to `Result[_, DBError]`. `blink fix` must not apply those rows automatically.
- **Spec example:** fix `04_effects.md:1803` (`with sqlite_handler(path)`) to `with db.connect(path)? { }`.

###### P5. Finish the items the spec already decides

- **Built-ins to remove from the compiler:** `read_file`, `write_file`, `file_exists`, `is_dir`, `file_mtime`, `process_run`, `process_spawn`, `process_pid_kill` and `process_pid_send_signal`. Each one gets E0504 plus the §4.4 fix. Mark the `file_exists` and `is_dir` rows: Int becomes `fs.stat` + `err.not_found()`, so `blink fix` must not apply them. The ticket's "file_exists returns Bool" is already overruled by "Blink has no fs.exists". Existence checks before an open are a TOCTOU race anyway.
- **`lib/std/process.bl`:** make the `Pid`-returning `spawn` and the `PidOps.kill` / `send_signal` methods private behind `process.spawn` / `process.signal(child, sig)`. Two signal paths into the same `kill(2)` is the same duplication.
- **Gate:** the stdlib API-surface lint fails on any `pub fn` in `lib/std` that the spec does not name. Without it, these duplicates return.

**Cross-language note:** Zig and Go both keep one stdout writer with explicit buffering. Python's `sys.stdout.buffer.write` versus `print` is the same text/binary split as P3.

##### Web/Scripting

My test is simple: a Python or JS developer writes the first name that comes to mind. If it compiles, good. If it fails, E0504 names the right call. They should never have to ask "which of these four is correct?" Every duplicate on this list will become a Stack Overflow question, and LLM training data will learn all of the duplicates.

###### P1. List concat: keep `.append` and spread, remove the rest

```blink
fn merged(a: List[Int], b: List[Int]) -> List[Int] {
    let ab = a.append(b)           // two lists
    let all = [..a, 0, ..b]        // literal with extra items
    let lazy = a.iter().chain(b.iter())  // lazy stays on Iterator
    all
}
```

- **Keep** `List.append(other)` as the method form and `[..a, ..b]` as the literal form. They do different jobs: spread can mix in single items. Both are voted already.
- **Remove** `list_concat` and add it to the §3.2 table with the fix `a.append(b)`. Same result type, so `blink fix` can apply it.
- **Remove** `List.chain`. It is not in the spec, and the danger is real. `Iterator.chain` is lazy and `List.chain` is eager, so the same word means two things. A Kotlin dev expects `chain` to be lazy, and a Rust dev expects it only on iterators. Add a row: `list.chain(x)` -> `list.append(x)`. It is a method, not a free function, so the row goes in a methods subsection of §3.2, or E0599 carries the same fix. The panel should state which.
- **Cross-language:** JS `concat`/spread and Python `+`/`[*a, *b]`. Spread already matches JS and Python. Don't add `+`. That rule is sealed, and E0504/E0599 can suggest `append` when someone tries `a + b`.
- **The one cost:** `append` reads as mutating to Python people (`list.append(x)` mutates there). W0606 already catches a discarded result, so the rename isn't worth it. Keep `append`.

###### P2. Map: remove `contains_key`, keep `contains`

```blink
if headers.contains("Content-Type") { ... }
```

The spec's own text says the two have "identical semantics". That is the definition of a Principle 2 violation. Users already learn `x in list` / `list.contains(x)` / `set.contains(x)` / `str.contains(s)`, so `map.contains(k)` is the one that transfers. Python's `k in d` checks keys, and so does JS `Map.has(k)`. Nobody expects map `contains` to check values. Remove `contains_key` from `MapOps`. The Map surface drops from 9 methods to 8 (the vote said 8, the text at 03_types.md:893 says 9, so this also fixes that drift). Add a removed-method row with the fix `m.contains(k)`.

This revisits a 3-2 surface vote, so the panel has to vote on it here. I favor it: an identical alias is the clearest case there is.

###### P3. io: spec `io.write_bytes`, remove `io.write`

- `io.write(Str)` does exactly what `io.print_raw(Str)` does: raw stdout, no newline. **Remove** it into the §4.4 table with the fix `io.print_raw(s)`. Migrate src/lsp.bl and src/daemon.bl. The `io.write("")` calls in daemon.bl (714, 729, 847, 1368) look like flush workarounds. If they are, that shows a missing `io.flush()`. File it as friction, not as an alias.
- `io.write_bytes(Bytes)` fills a real gap. The spec has no way to put binary on stdout (LSP framing, piping images, `cat`-style tools). Python has `sys.stdout.buffer.write`, Node has `process.stdout.write(buf)`. **Spec it** in the §4.4.9 table as `io.print_raw_bytes(b)`: Bytes, raw stdout, no handler, no trace. Then it sits in the `_raw` family with the same rules, and nobody wonders why `write` and `print` differ. Remove the `io.write_bytes` spelling into the §4.4 table with the fix `io.print_raw_bytes(b)`. If [the open `_raw` ticket] later removes `_raw`, this op moves with that decision.
- `print`, `println`, `eprint` and `log` stay as they are.

###### P4. DB: one public connect, make the others private

```blink
fn main() ! DB, IO {
    with db.connect("app.db")? {
        let rows = db.query("select * from users")?
    }
}
```

- **Keep** `db.connect(path) -> Result[Connection, DBError]` (5-0).
- **Make private** `sqlite_handler(handle)`. `db.connect` needs it inside, but it takes a raw `Sqlite3`, so users shouldn't touch it.
- **Remove** `sqlite_connect` and `db_connect` into the §4.4 table with the fix `db.connect(path)?`, and mark both rows *result type changes*: they returned a bare value with no error path. These two are the worst items on the list. They hide open failures, and a beginner would pick them because they need no `?`.
- **Fix** the spec example at 04_effects.md:1803 to `with db.connect(path)? { }`. Today it teaches a signature that does not exist.

###### P5. Finish the already-decided items

The spec is right, and the compiler and llms-full.md lag behind. Treat this as chore work, not panel work: remove the `read_file`/`file_exists`/`process_*` builtins, remove `Pid.kill`/`send_signal` and `spawn -> Pid` from lib/std/process.bl, and regenerate llms-full.md. llms-full.md matters most: it is the training surface, and today it documents `List.chain`, `io.write`, `sqlite_connect` and `db_connect` as real. The ticket asks that `file_exists` return Bool. That is moot: the name goes away, and the answer is `fs.stat` plus `err.not_found()`. I would accept a later proposal for `fs.exists(path) -> Bool` as a 90%-case helper, but that is a separate ticket.

###### Tradeoffs

- More E0504/E0599 rows. That costs little, and each row teaches the right name.
- P2 reopens a voted surface, and P3 adds a new name to the `_raw` family. Both stay small.
- Overall result: each operation has one documented spelling, every wrong guess gets a fix, and there are no aliases.

##### PLT

**PLT panel: one name per operation**

The test I apply to every item: each name should have one typing rule and one evaluation strategy. Where two names share one rule, one of them goes. Where one name has two rules, the name splits.

**P1. List concat: spread is the one form.**

- `[..a, ..b]` is kept as the only concat form. It is n-ary, it mixes elements and lists (`[x, ..a, y]`), and it is already eager (5-0). It is a term former, so it has one typing rule: every part is `T` or `List[T]`, and the result is `List[T]`.
- `List.chain` is removed. Today the same name is lazy on `Iterator` and eager on `List`. That is one name with two evaluation strategies, which breaks parametric reading: generic code cannot tell what `x.chain(y)` costs. The spec never had it.
- `list_concat` is made private. It is the lowering target for spread and append, so the stdlib rule (03_types.md:115) already forbids exporting it. It gets a §3.2 row.
- `List.append` should also be removed, and the panel needs to reopen it. Python's `append` and Rust's `Vec::append` both mutate, so the name promises mutation that Blink does not do. W0606 exists mainly to patch that trap. A warning that patches a name is a design smell. There is also precedent: §3.2 already dropped `int_to_str` in favour of the syntax form `"{n}"`.
- Fallback if the 3-2 surface vote stands: keep `append`, still remove `chain`, and spread stays.

```blink
fn merge_ids(a: List[Int], b: List[Int], extra: Int) -> List[Int] {
    [..a, extra, ..b]
}
```

New §3.2 rows (all "Result changes: no"):

| Removed name | Replacement |
|---|---|
| `list_concat(a, b)` | `[..a, ..b]` |
| `xs.chain(ys)` on `List` | `[..xs, ..ys]`, or `xs.iter().chain(ys.iter())` for lazy |
| `xs.append(ys)` (only if removed) | `[..xs, ..ys]` |

The table holds function forms today. These method rows need one sentence saying the table is also checked when method lookup fails.

**P2. Map membership: keep `contains_key`, drop `impl Contains[K] for Map`.**

The spec itself says the two have "identical semantics". Two names with one meaning is exactly what Principle 2 forbids. The instance is the unsound part, not the method:

- `Map` iterates `(K, V)`.
- The membership law I want stated for `Contains` is: if `C: Contains[E]` and `C` iterates `E`, then `c.contains(x) == c.iter().any(fn(e) { e == x })`.
- Map's `Contains[K]` breaks that law, because it tests keys while iteration yields pairs.
- Haskell agrees: `elem` on `Data.Map` (through `Foldable`) tests *values*, and key membership is the separate `member`. That is a confusion we should not inherit.

```blink
fn has_user(users: Map[Str, User], id: Str) -> Bool {
    users.contains_key(id)
}
```

- Cost: generic code that wants "any keyed container" must pass `m.keys()`, which is `List[K]` and O(n) to build. I accept that for a sound law.
- Fallback: if the panel keeps the hybrid instance, remove `contains_key` instead. Either way, one name.

**P3. io: remove `io.write`, spec the bytes operation.**

- `io.write(Str)` lowers to `stdout_write`, the same as `io.print_raw`, so it is a pure alias. Remove it with a §4.4 row: `io.write(s)` → `io.print_raw(s)`, no change. The two in-tree callers (src/lsp.bl:84, src/daemon.bl:714) migrate.
- `io.write_bytes(Bytes)` is a real operation. Its argument type has no `Display` and no `Str`, and nothing in the §4.4.9 table covers it. Spec it as `io.print_raw_bytes(b: Bytes)`: raw stdout, no handler, no trace. The name puts it in the `_raw` class so dispatch mode stays readable from the name (the rule DECISIONS.md:376 already uses). Add a row: `io.write_bytes(b)` → `io.print_raw_bytes(b)`.
- Interaction with [the open `_raw` ticket]: if that ticket later moves `_raw` into a handler op such as `IO.Write`, the bytes op moves with it, so we need not settle `_raw` here.

**P4. DB: `db.connect` only.**

Both `db_connect` and `sqlite_connect` are typed wrongly: `sqlite_open` can fail, and their return types cannot express that failure. The type lies.

| Name | What it becomes | Result changes |
|---|---|---|
| `db_connect(path)` and `DbConnection` | removed → `db.connect(path)?` | yes: `DbConnection` becomes `Result[Connection, DBError]` |
| `sqlite_connect(path)` | removed → `db.connect(path)?` | yes: `Handler[DB]` becomes `Result[Connection, DBError]` |
| `sqlite_handler(h)` | private (lowering target of `Connection.enter`) | — |

Also fix 04_effects.md:1803, which passes a path to `sqlite_handler`:

```blink
fn run_with_sqlite(path: Str) ! DB, IO.Log {
    with db.connect(path)? {
        start_server()
    }
}
```

**P5. Finishing the already-decided items.**

- `file_exists` should not become `Bool`. An exists check is a time-of-check-to-time-of-use race (the file can change between the check and the use). `fs.stat(p)` returning `Result[Stat, FsError]` with `err.not_found()` is the honest type, and the spec already says there is no `fs.exists`. The §4.4 rows for `read_file`, `file_exists` and the others must mark "Result changes: yes", so `blink fix` does not auto-apply them. The typecheck builtins that type `file_exists` as `Int` are deleted, not retyped.
- `std.process`: `spawn -> Pid`, `PidOps.kill` and `PidOps.send_signal` are made private or removed. The public surface becomes `process.spawn`, `process.wait` and `process.signal(child, sig)`, all `Result[_, ProcessError]` on effect `Process`.
- `Pid` keeps no public signal methods. Otherwise process control has two receivers, `Pid` and `Child`, with different error types, which brings back the duplicate the "no alias" vote removed.

**Cross-language**

- OCaml `List.append` / `(@)` and Haskell `(++)` are each a single concat.
- Rust keeps `Vec::append` (mutating) apart from `Iterator::chain` (lazy), and never uses one name for both.

##### DevOps

**DevOps/Tooling proposal: duplicate APIs**

**Main idea: one removal mechanism for every kind of name.** The §3.2 and §4.4 tables cover free functions only (E0504). This ticket also removes methods and `io` handle ops, so I propose the same table mechanism for E0505 (UnresolvedMethod). A failed method or handle-op lookup checks a "removed methods" table and gives the same `= fix:` line. Rows marked "result changes: no" are machine-applicable, so `blink fix` rewrites them. Rows marked "yes" are suggestions only. A removed name never shows up in LSP completion. If someone types it anyway, the diagnostic names the replacement, so they never have to search docs for it.

```
error[UnresolvedMethod]: no method `contains_key` on `Map[Str, Int]`
 --> cfg.bl:7:10
  |
7 |     if m.contains_key("port") {
  |          ^^^^^^^^^^^^ removed; use `contains`
  = fix: m.contains("port")
```

**P1. List concat: one method, one literal.**
- Keep `a.append(b)`. It is the canonical method, it is in the voted 12-method List surface, it shows up in LSP completion after `xs.`, and W0606 already catches the "Python users expect it to mutate" trap.
- Keep `[..a, ..b]`. It is literal syntax, not a second concat API. Its job is building a list from mixed parts (`[head, ..mid, tail]`), which `append` cannot do. The formatter leaves both alone. A lint that rewrites `[..a, ..b]` into `a.append(b)` would just be noise.
- Remove `List.chain` into the removed-methods table: fix `a.append(b)`, result changes: no. It lowers to the same runtime call today, so `blink fix` can apply it with no risk. Leaving it in place does real harm: it has the same name as the lazy `Iterator.chain` but is eager, and that split confuses every reader and every LLM.
- Add `list_concat(a, b)` to the §3.2 table: fix `a.append(b)`, result changes: no. Make the `@ffi` function in lib/std/list.bl private, because `append` lowers to it (03_types.md:115).
- `Iterator.chain` stays. It is a different operation: lazy, with a different result type.

```blink
fn all_ids(a: List[Int], b: List[Int]) -> List[Int] {
    a.append(b)
}
let row = [0, ..all_ids(xs, ys), -1]
```

**P2. Map: drop `contains_key`, keep `Contains.contains`.** The spec says the two "have identical semantics." Two completion entries with the same hover text is a tooling smell. The LSP cannot rank one above the other, `blink fmt` cannot normalize between them, and an AI picks one at random, which splits the training data. The trait method has to stay, because generic code over `Contains[K]` needs it on Map. That leaves `contains_key` as the one to remove: removed-methods row, fix `m.contains(k)`, result changes: no. This overturns part of the 3-2 Map vote, and I say so openly. The cost is the "key or value?" question when reading the code. Hover docs and Python's `k in dict` (keys) already answer it. Cross-language: Rust uses `contains_key`, JS uses `has`, Go uses `_, ok := m[k]`. None of them offers two names.

**P3. `io.write` / `io.write_bytes`.**
- `io.write(s)` is the same as `io.print_raw(s)`. Remove it into the removed-methods table: fix `io.print_raw(s)`, result changes: no. Migrate src/lsp.bl:84 and the four `io.write("")` calls in src/daemon.bl. The daemon calls write empty strings, so check whether they exist only to flush. If so, that is a missing op, not an alias, and needs its own ticket.
- `io.write_bytes(b)` fills a real gap: no specced op writes binary to stdout. LSP framing and binary pipelines need one. Spec it as a raw-tier row in the §4.4.9 table, renamed `io.print_bytes_raw(b: Bytes)`: no handler, no trace. The name matches the `_raw` rule ("the split follows the `_raw` name"), so the name alone tells users it skips handlers. The old name gets a removed-methods row (no result change). Add no stderr twin until someone needs one. Interaction with [the open `_raw` ticket]: if that ticket removes the `_raw` tier, this op moves with `print_raw` into whatever replaces it, so the two must not be decided separately.

**P4. DB: only `db.connect(path)?`.**
- `db_connect(path)` and `sqlite_connect(path)` get §4.4 removed rows: fix `db.connect(path)?`, result changes: **yes** (a bare value becomes `Result[_, DBError]`, which adds an error path). So `blink fix` offers the change as a suggestion only.
- `sqlite_handler(handle: Sqlite3)` becomes private. It is what `db.connect` lowers to, the same pattern as `list_concat`.
- Fix the spec example at 04_effects.md:1803 to `with db.connect(path)? { ... }`. As written, it calls `sqlite_handler(path)` with a `Str`, which does not type-check against the real function. The `postgres_handler(config)` example beside it is also unspecced. Flag it as friction; do not invent a spec for it here.

```blink
fn main() ! DB, IO.Print {
    with db.connect("app.db")? {
        io.println(db.query_one("select 1")?)
    }
}
```

**Finishing what is already decided.**
- Add a "Result changes" column to the §4.4 table, the same as §3.2. `file_exists` / `is_dir` / `file_mtime` → `fs.stat` is "yes" (Int becomes `Result[Stat, FsError]`). So are all the `process_*` rows (Pid becomes `Child`, bare values become `Result[_, ProcessError]`). The prose at 04_effects.md:357 already says this for some of these names. A column makes it something `blink fix` can read.
- lib/std/process.bl: remove `spawn -> Pid` and the `PidOps` methods `kill` / `send_signal`. Add removed-methods rows: fix `process.signal(child, sig)`, result changes: yes.
- Typecheck still types `file_exists` as Int. Once the table lookup ships, that builtin goes away, so nobody needs to change it to Bool. The ticket's "file_exists returns Bool" is overtaken by the spec, which has no `fs.exists`.

**A gate so this does not come back.** llms-full.md is why duplicates spread: it documents `List.chain`, `io.write`, `sqlite_connect` and `db_connect`. Add a `task ci` check that fails if any name in a removed-forms table, or any std `pub` name with no spec row, appears in generated `blink llms` output. Go's `go vet` and rust-analyzer's "deprecated" tags work because one source of truth feeds the docs. We need that one source too.

##### AI/ML

**My test for every item:** if a model reads only `blink llms --full`, does it write the one correct form on the first try? Each extra name for the same operation is a coin flip. It also becomes training data: whatever we ship now, future models will repeat. The worst case is two names with the same meaning but different hidden behaviour, such as a lazy name that is eager.

###### P1. List concat: keep `.append` and spread; remove `List.chain` and `list_concat`

```blink
fn merge_ids(a: List[Int], b: List[Int]) -> List[Int] {
    a.append(b)            // two lists, eager
}
fn with_header(rows: List[Str]) -> List[Str] {
    ["id,name", ..rows]    // literal with mixed parts
}
```

- **`list_concat`:** make it private in lib/std/list.bl, since only the lowering calls it. Add a §3.2 row: `list_concat(a, b)` → `a.append(b)`, result changes: no.
- **`List.chain`:** remove it. It never was in the spec. It is the riskiest duplicate in the whole ticket because `Iterator.chain` is lazy (03c:69). A model that sees `xs.chain(ys)` cannot tell eager from lazy, and Rust training data says lazy. It is a method, not a function form, so the §3.2 table does not fit. Instead, give UnresolvedMethod on `List` a fix: "use `a.append(b)` (eager) or the lazy `Iterator.chain`".
- **Spread stays.** It is literal syntax, not a second method. Add one line to §3.2: "Two lists: `a.append(b)`. A literal with extra elements or three or more sources: `[..a, x, ..b]`." That is a single rule with no overlap, and both forms cost the same tokens.
- **Cross-language:** Python's `list.append(x)` pushes one element in place. Here the type check (element vs list) and W0606 (unused result) catch that mistake. I would still rename to `concat`, which matches JS `Array.concat` exactly, but the 3-2 List surface vote stands. I note it and do not move it.

###### P2. Map: remove `contains_key`; `contains` is the only key check

```blink
if config.contains("port") { ... }
```

- The spec defends the pair with "reads more clearly" (03_types.md:891). That is a decision point with zero payoff: same meaning, two names.
- `contains` must stay, because generic `Contains` code needs it, and it gives one membership name across List, Set, Map and Str. One name across four types is the cheapest thing for a model to learn.
- Rust and Java habits will produce `m.contains_key(k)`. The UnresolvedMethod fix "use `m.contains(k)`" turns that into a one-shot correction.
- Update the Map surface count and the line 891 note. This reverses one method of the 3-2 Map vote, and Principle 2 is the reason.

###### P3. io output: remove `io.write`; spec `io.write_bytes`

```blink
fn send_frame(body: Bytes) ! IO {
    io.write_bytes(body)
}
fn progress(n: Int) ! IO {
    io.print_raw("\r{n}%")
}
```

- **`io.write(Str)`:** it is `print_raw` with a flush (runtime_stdio.h:240). Remove it and make the §4.4.9 table say `_raw` ops flush on every call. That is what the stated use case (progress, streaming fragments) needs anyway. Add a §4.4 removed-forms row: `io.write(s)` → `io.print_raw(s)`, no. The repo's own uses (lsp, daemon, cli) migrate; `io.write("")` used as a bare flush becomes `io.print_raw("")`.
- **`io.write_bytes(Bytes)`:** keep it and add it to the table: raw stdout, not handler-dispatched, no trace, flushes. Binary framing (LSP Content-Length) has no other spelling, so it is not a duplicate.
  - I keep the name because it pairs with `io.read_bytes(n)`, the name a model guesses first.
  - The cost is that `read_bytes` is interceptable and `write_bytes` is not. The table must state this plainly.
  - A handler op for byte output is YAGNI.
- If [the open `_raw` ticket] removes `_raw`, `write_bytes` goes with it.

###### P4. DB: `db.connect(path)?` only

```blink
fn main() ! DB, IO {
    with db.connect("app.db")? {
        db.exec(t"CREATE TABLE t (x INT)")?
    }
}
```

- `sqlite_connect`, `db_connect` and `sqlite_handler` become private (not `pub`).
- Add §4.4 rows:
  - `sqlite_connect(p)` → `db.connect(p)?`, result changes: yes, `Handler[DB]` becomes `Result[Connection, DBError]`.
  - `db_connect(p)` → `db.connect(p)?`, result changes: yes, `DbConnection` with no error path becomes `Result`.
  - `sqlite_handler(h)`: no replacement row. A raw `Sqlite3` handle is not user surface.
- Both connect rows hide open failures today. That is a correctness bug, not just a duplicate.
- Fix the spec example at 04_effects.md:1803 to `with db.connect(path)? { }`. It names a function signature that does not exist, and models copy examples before they read prose.

###### P5. Finish the items the spec already decided

These are compiler and lib lag, not spec questions:

- Remove the builtins `read_file`, `write_file`, `file_exists`, `is_dir`, `file_mtime`, and `process_run`, `process_spawn`, `process_pid_kill`, `process_pid_send_signal`. Each gets E0504 plus a fix from the existing §4.4 table.
- Mark result changes: yes on `file_exists` (Int becomes `fs.stat` + `err.not_found()`) and on the process rows.
- lib/std/process.bl: `spawn -> Pid` becomes `Result[_, ProcessError]`, and PidOps `kill`/`send_signal` are removed.

###### P6. Treat llms-full.md as surface, not docs

Every duplicate in this ticket shows up in llms-full.md (lines 446-534, 669). That file is what a model actually reads, so a name it documents is in effect a public API.

**Proposal:** a CI check that every callable name llms-full.md documents for io, fs, process, db, and List or Map methods appears in the sections/ spec. Without it, these duplicates come back.

###### Net change

| Change | Count |
|---|---|
| Names removed | 7 user-visible names: `List.chain`, `list_concat`, `contains_key`, `io.write`, and three db functions, plus the fs and process builtins the spec already removed |
| Names specced | 1: `io.write_bytes` |
| Learning rule added | 1: append vs spread |

Every removed name gets a fix-carrying diagnostic, so a model that guesses wrong recovers in one compile.

##### Minimalism

Principle 2 puts the burden of proof on the second name. Every proposal below removes names and adds none. Each removed name gets a row in the §3.2 or §4.4 removed-forms table. No name gets an alias or a deprecation cycle.

###### P1. List concat: spread is the one form (my first choice)

```blink
let all = [..a, ..b]
let framed = [header, ..rows, footer]
let lazy = a.iter().chain(b)          // Iterator.chain stays: lazy is a different operation
```

| Removed name | Replacement | Result changes |
|---|---|---|
| `list_concat(a, b)` | `[..a, ..b]` | no |
| `xs.chain(ys)` on `List` | `[..xs, ..ys]` | no |
| `xs.append(ys)` | `[..xs, ..ys]` | no |

- **Why remove `append`:** the spread form has to exist for literals anyway (5-0) and covers every concat. `append` is a trap. In Python, `append` mutates and takes one element. The spec had to add W0606 because readers write `xs.append([3])` as a statement and lose the result. A name that needs a warning to stop misuse fails the subtraction test. With `append` gone, the W0606 list loses one row and the List surface goes from 12 methods to 11.
- **Cost:** `xs.filter(p).append(ys)` becomes `[..xs.filter(p), ..ys]`. That reads inside-out but stays short.
- **Fallback (P1-min):** if the panel will not reopen the 3-2 List vote, remove only `List.chain` and `list_concat`. Neither is in the spec, so removing them costs nothing. `List.chain` is worse than useless: it has the same name as the lazy `Iterator.chain` but runs eagerly. Then add one line to §3.2: "`append` is the method form; `[..a, ..b]` is for building a literal from many parts."
- **Cross-language:** Go has one concat, `append(a, b...)`. Scheme has `append`. Python's two forms, `+` and `.extend`, are the confusion we want to avoid.

###### P2. Map: remove `contains_key`

```blink
if m.contains("host") { ... }   // the Contains trait means key presence on Map
```

| Removed name | Replacement | Result changes |
|---|---|---|
| `m.contains_key(k)` | `m.contains(k)` | no |

The spec itself says the two have "identical semantics" (03_types.md:891). That is an alias by the spec's own words, and Principle 2 forbids aliases. "Reads more clearly" is the argument every alias uses. Generic code must use `contains` anyway, so the generic name is the one to keep. MapOps goes to 7 methods.

Cross-language: JS has `Map.has` and Go has `_, ok := m[k]`, one form each. Rust has `contains_key` only because it has no shared `Contains` trait. Blink has one.

###### P3. io output: no new names, fold `write` into `_raw`

I checked the facts. `io.write` is `print_raw` plus `fflush` (runtime_stdio.h:242 against runtime_core.h:3989). `io.write_bytes` writes Bytes to stdout. The specced `libc.write_bytes(1, data)` already does that (07_trust:1320).

```blink
io.print_raw(lsp_frame(body))        // was io.write
libc.write_bytes(1, png)?            // was io.write_bytes
```

- **Spec change, one sentence in §4.4.9:** "`print_raw` and `eprint_raw` write through: each call flushes before it returns." Raw should mean no buffer as well as no handler and no trace. The tooling users that §4.4.9:246 reserves `_raw` for (LSP framing, the daemon) need exactly that.
- **Removed rows in §4.4:**
  - `io.write(s)` → `io.print_raw(s)`, result change: no.
  - `io.write_bytes(b)` → `libc.write_bytes(1, b)?`, result change: yes. `Void` becomes `Result[Int, Errno]`, and a short write is visible.
- **Flushing:** the daemon's `io.write("")` call, used only to flush, becomes `io.print_raw("")`. I reject an `io.flush` until someone shows a need outside `_raw`.
- **If [the open `_raw` ticket] later removes `_raw`:** these two rows move with it. Only the replacement column changes.

###### P4. DB: `db.connect` only

```blink
fn run_with_sqlite(path: Str) ! DB, IO.Log {
    with db.connect(path)? {
        start_server()
    }
}
```

| Removed name | Replacement | Result changes |
|---|---|---|
| `db_connect(path)` | `db.connect(path)?` | yes: `DbConnection` becomes `Result[Connection, DBError]`; an open failure gives `Err` |
| `sqlite_connect(path)` | `db.connect(path)?` | yes: `Handler[DB]` becomes `Result[Connection, DBError]` |
| `sqlite_handler(h)` | `db.connect(path)?` | yes |

- `sqlite_handler` becomes private to `std.db_sqlite`. It is an implementation detail, and nothing voted it public. `DbConnection` goes with `db_connect`.
- Fix the spec example at 04_effects.md:1803 to the form above. It calls `sqlite_handler(path)`, which does not even match the real signature, so it teaches a form that never existed.
- Cross-language: Go has one entry point, `sql.Open`. Today Blink has four connect names, and three of them never went to a vote.

###### P5. Finishing the items the spec already decides

The spec already removed these names (§4.4: `read_file`, `file_exists`, `process_*`), and the compiler still lags behind it. Treat that as a chore, not a panel question. Two points need the panel's attention:

- **Do not add a Bool `file_exists`.** The ticket proposes one. The spec says there is no `fs.exists` (04_effects.md:1032), and a check-then-act exists test races with the next operation. Use `fs.stat(p)` with `err.not_found()`. The §4.4 row for `file_exists` must carry Result changes = yes, because `Int` becomes `Result[Stat, FsError]`.
- **lib/std/process.bl still exports `spawn -> Pid` and `PidOps.kill`/`send_signal`.** Make them private or remove them, per §4.4 ("no alias").

###### Ranking

1. P4, P5 and P1-min. These cost nothing, because the names are unspecced or already removed.
2. P3.
3. P2.
4. P1 in full.

If the panel keeps both `contains` and `contains_key`, or both `append` and spread, it should write down why Principle 2 does not apply there. "Discoverability" alone is the reasoning that led to four connect functions.

#### Phase A.5 — Moderator dedupe


###### Proposed by all six (no rival option was proposed)
- U1. Remove `List.chain` (never specced). Fix names `.append` or spread for eager, `.iter().chain(...)` for lazy. (all six)
- U2. `list_concat`: removed-forms row in §3.2; the lib `@ffi` fn becomes private. Replacement column depends on Q1. (all six)
- U3. Remove `io.write(Str)` into the §4.4 removed table; replacement `io.print_raw(s)`; migrate src/lsp.bl and src/daemon.bl. (all six)
- U4. DB: `db.connect(path)?` is the only public form. `db_connect` and `sqlite_connect` get removed rows marked "result changes: yes"; `sqlite_handler` becomes private; fix the example at 04_effects.md:1803. (all six; variation: Min also gives `sqlite_handler(h)` a removed row → `db.connect(path)?` (result changes: yes); AI/ML says no row for it; the rest make it private without stating a row)
- U5. Already-decided items (fs builtins, process builtins, PidOps kill/send_signal, Pid-returning spawn): finish the removal in compiler + lib/std; no Bool `file_exists` (spec already says fs.stat + not_found). (all six)

###### Q1. List concat: the canonical form(s)
- Q1-A. Keep `a.append(b)` (method, two lists) AND `[..a, ..b]` (literal, mixed parts). — Sys, Web, DevOps, AI/ML
  - Variation (Sys): spec that both make one allocation of exactly a.len() + b.len().
  - Variation (AI/ML, Min fallback): one §3.2 line: "two lists: a.append(b); literal with extra elements or 3+ sources: [..a, x, ..b]".
- Q1-B. Spread `[..a, ..b]` is the only concat form; remove `append` into the removed table (reopens the 3-2 List surface vote). — PLT, Min (both give Q1-A as fallback)

###### Q2. Map membership
- Q2-A. Remove `contains_key`; `contains` (Contains trait) is the one name (reopens one method of the 3-2 Map surface vote). — Sys, Web, DevOps, AI/ML, Min (PLT as fallback)
  - Variation (Sys fallback): if the vote is not reopened, keep both + a lint preferring one in non-generic context.
- Q2-B. Keep `contains_key`; drop `impl Contains[K] for Map` (the instance breaks the membership law c.contains(x) == c.iter().any(e == x), since Map iterates (K, V)). — PLT

###### Q3. Binary stdout (`io.write_bytes(Bytes)`)
- Q3-A. Keep the name `io.write_bytes`; spec it as a raw-tier row (no handler, no trace). Pairs with `io.read_bytes`. — Sys, AI/ML
- Q3-B. Spec it as `io.print_raw_bytes(b)`; old name gets a removed row. — Web, PLT
- Q3-C. Spec it as `io.print_bytes_raw(b)`; old name gets a removed row. — DevOps
- Q3-D. Add no io op; `io.write_bytes(b)` → `libc.write_bytes(1, b)?` removed row (result changes: yes, Void → Result[Int, Errno]). — Min

###### Q4. `_raw` write semantics (raised by Sys, Min, AI/ML; not addressed by Web, DevOps, PLT)
- Q4-A. Spec that `_raw` ops flush before return (Min, AI/ML); Sys adds: write every byte of the Str including NUL (fwrite of len, not printf "%s"), at least one write(2) per call.
- Q4-B. (no proposal) — panelists may state whether flush belongs in the spec, and Web/DevOps raised a separate `io.flush` op as a possible friction ticket instead.

###### Q5. How a removed METHOD (List.chain, contains_key, append if removed) is diagnosed
- Q5-A. A "removed methods" table checked when method lookup fails (E0505 UnresolvedMethod), same columns and blink-fix rules as §3.2/§4.4; removed names never appear in LSP completion. — DevOps; PLT ("one sentence saying the table is also checked when method lookup fails"); Web asked the panel to state which
- Q5-B. No table: the UnresolvedMethod diagnostic carries a fix naming the replacement. — Sys, AI/ML

###### Extras proposed by one or two panelists (keep, drop, or defer to a follow-up ticket)
- X1. CI gate: generated `blink llms` output must not name a removed form or an unspecced std pub name. — DevOps, AI/ML
- X2. Lint: fail on any `pub fn` in lib/std the spec does not name. — Sys
- X3. Add a "Result changes" column to the §4.4 removed table (yes for file_exists/is_dir/file_mtime and process_* rows). — DevOps

###### Fact check (moderator, from the repo)
- `io.write` lowers to `blink_stdout_write` (src/cg_call.bl:2269): `fwrite(data, 1, strlen(data), stdout); fflush(stdout)` (bootstrap/runtime_stdio.h:242-246).
- `io.print_raw` lowers to `blink_io_default_print_no_nl` (src/cg_call.bl:2314): `printf("%s", msg)`, no flush (bootstrap/runtime_core.h:3988-3990).
- `io.write_bytes` lowers to `blink_stdout_write_bytes`: `fwrite(b->data, 1, b->len, stdout); fflush(stdout)` (runtime_stdio.h:250-254).
- So `io.write` and `io.print_raw` do not lower to the same runtime call today: they differ in flushing.

#### Phase B — Debate (round 1; all six reported stable)

##### Systems

###### U items
- **U1, U2, U3, U5:** agree.
- **U4:** agree. Take Min's variation: `sqlite_handler(h)` also gets a removed row marked "result changes: yes". llms-full.md taught it, so it is in training data, and a row costs nothing at run time.

###### Q1. List concat: Q1-A
PLT's argument (the name `append` suggests mutation, and W0606 is a patch for that) is the strongest case against my position, and I take it seriously. But it does not change the cost or the code, because `[..a, ..b]` with two parts and `a.append(b)` are the same runtime call. The real difference is pipelines. `xs.filter(p).append(ys)` reads left to right. `[..xs.filter(p), ..ys]` reads inside out, and the deeper it nests, the worse it gets. So I keep Q1-A.

Whatever the vote, keep my variation: both forms make one allocation of exactly `a.len() + b.len()`. That is a contract for codegen, and it holds under Q1-B too. Collapse AI/ML's one-line guidance into Q1-A as its §3.2 text.

###### Q2. Map membership: Q2-A
PLT's law is correct for containers whose elements are what they iterate. But Q2-B costs too much on the hardware. Generic code that wants key membership must build `m.keys()`, which is an O(n) allocation where there was an O(1) probe. That is the cost-hiding outcome I am on the panel to stop. The law can be stated against `Contains[E]`'s own element domain (for Map, the key set, `m.keys()`). It then holds, and nothing allocates. JS `Map.has` and Python `k in d` both test keys, so users expect key semantics. I drop my lint fallback: if the panel keeps both names, write down why Principle 2 does not apply, as Min says.

###### Q3. Binary stdout: Q3-B (I move from Q3-A)
- **Against Q3-D, firmly:** `libc.write_bytes(1, b)` is a raw `write(2)` that goes around the stdio buffer that `io.print` uses. In `io.print("hdr"); libc.write_bytes(1, body)?`, the body can reach the fd before the header. That reorders output silently, and it only shows when stdout is a pipe. It also pushes an `FFI`-tier call into ordinary binary output. Any binary stdout op must use the same stream as the other io ops.
- **On the name:** PLT's point is right: the dispatch class must be readable from the name. I take `io.print_raw_bytes(b)`. Q3-B and Q3-C differ only in word order, so collapse them, with B as the spelling, because it keeps the `_raw` suffix rule.

###### Q4. `_raw` semantics: Q4-A, with all three clauses
The spec must state these. Each one is behaviour a user can see, not an implementation detail:
1. `_raw` writes every byte of its argument, NUL included. Today `printf("%s")` truncates at the first NUL, which is a bug.
2. A `_raw` call flushes before it returns.
3. New: output from `print`/`println` and `_raw` to the same stream appears in call order. Clause 3 is the rule that makes Q3-D wrong, and it constrains codegen to one stream per fd.

A separate `io.flush`: defer it to a friction ticket (YAGNI). The daemon's `io.write("")` becomes `io.print_raw("")`.

###### Q5. Removed methods: Q5-A (I move from Q5-B)
A table costs nothing at run time. It gives methods the same `blink fix` safety rules (the "result changes" column) and the LSP exclusion that function forms already have. Q5-B is a subset of Q5-A, because the fix text comes from the table row. Collapse them into Q5-A.

###### Extras
- **X1:** keep.
- **X2:** keep, and merge it with X1 into one gate: "the public std surface equals the specced surface, and generated docs name no removed form". It is two checks with one purpose, and duplicates like these come back without it.
- **X3:** keep. It is needed: §4.4 rows where Int becomes Result must not be applied by `blink fix`, and the §3.2 twin already has the column.

STABLE: ready to vote

##### Web/Scripting

###### U1-U5: agree with all five
- U4 variation: give `sqlite_handler(h)` a removed row as well (Min's form, result changes: yes). Some code already calls it, and llms-full.md teaches it. A user who hits a privacy error should still see `db.connect(path)?` as the fix. A row costs nothing.

###### Q1. List concat: Q1-A
I accept the AI/ML/Min one-line rule in §3.2: "two lists: `a.append(b)`; a literal with extra elements or 3+ sources: `[..a, x, ..b]`". Sys's single-allocation guarantee is fine with me, but it is a cost promise. Put it in the method doc, not the panel decision.

Against Q1-B. PLT and Min are right that `append` sounds like it mutates. Removing it costs more than that does:
- Method chains turn inside-out: `rows.filter(p).append(extra).map(f)` becomes `[..rows.filter(p), ..extra].map(f)`. JS and Kotlin devs read and write left to right.
- When you type `xs.`, completion shows `append`. Nobody finds spread through completion.
- W0606 already catches the one mistake, a discarded result, at compile time. A Python dev who writes `xs.append(ys)` as a statement gets told at once.
Leave the 3-2 List vote alone. Reopening it gains little.

###### Q2. Map membership: Q2-A
Against Q2-B. The PLT law is tidy, but users do not reason from it. Python `k in d`, JS `Map.has(k)`, Kotlin `k in map` and Java `containsKey` all test keys. Nobody, not people and not LLMs, expects `map.contains(x)` to test pairs. Q2-B removes the name every Python dev types first, and it breaks generic `Contains` code that runs on maps today. If PLT wants the law, it can say "iterates its key type" for Map. Sys's fallback lint is a second name with a warning attached, and I reject it.

###### Q3. Binary stdout: Q3-B (Q3-A second)
- Collapse Q3-B and Q3-C. They differ only in word order. I take `print_raw_bytes` because it keeps the `print_raw` prefix, so `io.print_raw` completion shows both.
- Q3-A has one real argument: it pairs with `io.read_bytes`. But `write` next to `print` brings back the very "which one?" question this ticket exists to kill. Still my second choice.
- Against Q3-D. "Use `libc.write_bytes(1, b)?`" asks a script writer to know that fd 1 is stdout and to import libc. It does give an honest Result, but an LSP server or a `cat` clone is a normal program, not FFI work. Binary stdout belongs in `io`.

###### Q4. `_raw` semantics: Q4-A
The fact check settles this. `io.write` flushes and `print_raw` does not. U3 migrates the LSP to `print_raw`, so without a flush rule the migration silently breaks LSP framing. Spec it: `_raw` ops flush before they return, and they write every byte of the Str, NUL included. Drop Sys's "at least one write(2) per call". That is an implementation detail and should stay out of sections/. Once `_raw` flushes, `io.flush` is not needed now. I withdraw my friction note.

###### Q5. Removed methods: Q5-A, in PLT's short form
One sentence: "the removed-forms tables are also checked when method lookup fails (E0505)". Same columns, same `blink fix` rules, and removed names never appear in completion. Q5-B leaves each fix up to whoever writes the diagnostic, with no table that records it for good. The tables are the one place an LLM or a doc tool can read. Q5-A and Q5-B are close, and Q5-A is Q5-B with a record kept.

###### Extras
- X1: keep. llms-full.md is what models learn from. Today it documents four names this ticket removes.
- X2: defer to a chore ticket. It is a good tool check, but it is not spec text.
- X3: keep. `file_exists` goes from Int to Result, and `blink fix` must not apply that row on its own. The §4.4 table needs the column §3.2 already has.

STABLE: ready to vote

##### PLT

**Correction first.** In Phase A I said `io.write` lowers to the same call as `io.print_raw`. The moderator's fact check shows that is wrong: `io.write` flushes and `print_raw` does not. That changes U3 and Q4 (see below).

###### U items
- **U1, U2:** Agree.
- **U3:** Agree, on one condition. The row `io.write(s)` → `io.print_raw(s)` is only "result changes: no" if Q4-A passes. Without Q4-A the replacement changes observable output order (unflushed stdout interleaves differently with stderr and child processes), and `blink fix` must not auto-apply it.
- **U4:** Agree. On the `sqlite_handler` variation I side with Min: make it private AND give it a removed row → `db.connect(path)?` (result changes: yes). llms-full.md documents it, so users and models will write it. A row costs nothing and gives them a fix in place of a bare E0504.
- **U5:** Agree.

###### Q1. List concat: I hold Q1-B, but would accept Q1-A plus the AI/ML rule line
Q1-A's argument is "different jobs". But spread does every job that append does, so the overlap is total in one direction. That is the same relation `"{n}"` had to `int_to_str`, and §3.2 removed `int_to_str`. Still, the W0606 trap is caught today, and `xs.filter(p).append(ys)` reads better in a pipeline than `[..xs.filter(p), ..ys]`. That is a real compositional cost. If Q1-A wins, the AI/ML/Min line ("two lists: `a.append(b)`; extra elements or 3+ sources: spread") is required, not optional.
- **Sys variation:** spec the observable, not the allocation. Say "O(a.len() + b.len()); the operands do not change." "One allocation" is a lowering detail and belongs in docs/build/. Fold that wording into Q1-A.

###### Q2. Map membership: I move to Q2-A, with a condition
Five seats, and Python `in` / JS `Map.has`, show that key membership is what users expect from `m.contains(k)`. My objection was a law, but the spec states no law for `Contains`. So I ask for this when Q2-A passes: §3 states what `Contains` means for each instance (Map: key presence) and does NOT state the general law `contains(x) == iter().any(e == x)`. Then no coherence rule is broken. The Sys fallback (keep both plus a lint) is still two names with one meaning. Reject it.

###### Q3. Binary stdout: Q3-B; merge B and C
- B and C differ only in word order. Collapse them into one option and pick `print_raw_bytes`: the `print_raw` stem is the class marker, and `_bytes` adds the argument type.
- Against Q3-A: `io.read_bytes` goes through a handler (`IO.Read`). A `write_bytes` that pairs with it by name says "handler-dispatched", which is false. Names should show dispatch mode (DECISIONS.md:376).
- Against Q3-D: it makes the LSP and daemon framing need effect `FFI` plus a trust audit to write to stdout. It also moves an IO-effect operation under a different effect, which hides IO from the effect row. That is unsound for effect tracking. Reject it.

###### Q4. `_raw` semantics: Q4-A, stated as observables
Spec two rules for `print_raw`, `eprint_raw` and the bytes op:
- (a) Every byte of the argument is written, NUL included.
- (b) The bytes reach the file descriptor before the call returns (flushed).

`printf("%s")` cutting a `Str` at an embedded NUL is a latent correctness bug. Drop "at least one write(2) per call": it is a lowering detail. A separate `io.flush` is a friction ticket, not part of this ticket.

###### Q5. Removed methods: Q5-A
`blink fix` needs data in the form of a table: the replacement and the "result changes" column. A free-text fix on a diagnostic gives the tool nothing to check. The rows extend the §3.2 rule; they do not add a new mechanism. "Not in LSP completion" holds already, because a removed method does not exist.

###### Extras
- **X1:** Keep, as a chore ticket. It is a gate, not spec text.
- **X2:** Defer to a chore. "pub fn not named in the spec" will flag real lib modules that the spec does not list one function at a time. Scope it to the lib modules for built-in types first.
- **X3:** Keep. It is needed for consistency: the `file_exists` → `fs.stat` row changes `Int` to `Result[Stat, FsError]`. Without the column, `blink fix` would auto-apply a type-changing rewrite.

STABLE: ready to vote

##### DevOps

**U1–U5: agree.**
- U4: give `sqlite_handler(h)` a removed row (Min's variation). It was `pub`, so user code can call it today. Without a row, the error is a bare E1003/E0504 with no fix. The row's fix is `db.connect(path)?`, result changes: yes, suggestion only, because a handle becomes a path.
- U5: the §4.4 rows need X3 (see below), or `blink fix` will auto-apply `file_exists` → `fs.stat`.

**Q1: A (keep `append` and spread).** PLT and Min are right that the name `append` sounds like it mutates. But W0606 already catches that misuse at the call site, and the fix is mechanical. Two tooling points decide it for me:
- Completion after `xs.` cannot offer spread. Users and models find operations by typing a dot.
- Pipelines read left to right: `xs.filter(p).append(ys)` against `[..xs.filter(p), ..ys]`. Inside-out code is harder to read in diffs and harder for `blink fmt` to break across lines.

Take the AI/ML one-line guidance into §3.2 ("two lists: `a.append(b)`; a literal with extra parts or 3+ sources: `[..a, x, ..b]`"). Drop Sys's "one allocation" wording, because it is an implementation detail. State the cost as O(a.len() + b.len()) instead.

**Q2: A (remove `contains_key`).** PLT's law argument is the strongest case for B, and I accept that the law is real. But B costs more:
- Python's `k in d` tests keys, so users already expect key membership.
- B breaks every generic `Contains` caller that takes a Map, and gives them O(n) `m.keys()` instead.
- Either option leaves one name, so the tooling surface is the same.

If the panel adopts PLT's law, the spec can state it with Map excluded: Map's `Contains` is over its key set.

**Q3: B (`io.print_raw_bytes`). I am withdrawing C.** B and C differ only in word order, so collapse them. B wins because the prefix `io.print_raw` shows both ops together in completion.
- Against A: `write_bytes` sounds like the twin of `read_bytes`, but `read_bytes` goes through a handler and this op does not. The name pair would hide that difference. Keep dispatch mode readable from the name (DECISIONS.md:376).
- Against D: `libc.write_bytes(1, b)` writes straight to fd 1 and skips the stdout buffer. Output from it interleaves out of order with buffered `io.print` output, which is a classic bug class that is hard to diagnose. It also sends normal binary output through the FFI tier and its audit surface. Reject D.

**Q4: A, and it is required, not optional.** The moderator fact check shows that `io.write` flushes and `print_raw` does not. U3 marks `io.write → io.print_raw` as "result changes: no", so `blink fix` auto-applies it. That marking holds only if `_raw` flushes before return. Without Q4-A, U3 must be marked "yes".
- Take Sys's "every byte, including NUL" as well. Today `printf("%s")` truncates at the first NUL, which is a latent bug.
- Drop "at least one write(2) per call". It describes the implementation, and the observable contract is the flush.
- The `print_raw_bytes` row also flushes.
- No `io.flush` op. Under Q4-A, the daemon's `io.write("")` becomes `io.print_raw("")`.
- Collapse Q4-B into "no".

**Q5: A (table).** B is A without the table, so these are near-duplicates. Pick A because the table also carries the result-changes column, which tells `blink fix` and the LSP code action whether they may apply the fix. With B, every diagnostic invents its own policy. A is one sentence in §3.2 plus the rows.

**X1 + X2: collapse into one "spec coverage gate" and defer it to a `type:chore` ticket.** X1 checks the docs output and X2 checks lib/std `pub` names. Both are repo tooling, not language spec, so neither goes in sections/. File the chore when this ticket closes.

**X3: keep.** It is spec text, and `blink fix` needs it for U5. The column is "yes" for `file_exists`/`is_dir`/`file_mtime`, the `process_*` rows, and the db rows.

STABLE: ready to vote

##### AI/ML

**U1 to U5:** I agree with all five. On the U4 variation, I now accept Min's removed row for `sqlite_handler(h)` → `db.connect(path)?` (result changes: yes). llms-full.md documented it, so it is in training data. A model will type it, and a fix row is cheaper than a bare E0504. Making it private and giving it a row are compatible, so collapse the variations into "private + row".

**Q1: A.** Against Q1-B:
- Models write method chains: `xs.filter(p).append(ys)`. Spread turns that into the inside-out `[..xs.filter(p), ..ys]`, which costs more tokens and has a higher chance of a bracket error.
- The Python trap PLT and Min cite is real. But `xs.append(x)` with an element is a type error, and a discarded result is W0606. Both give a fix in one compile.
- Removing a voted method to cure a naming trap trades a caught error for a style decision.
- Sys's allocation contract and my one-line "which form" rule fit together. Collapse them into one Q1-A text.

**Q2: A.** Against Q2-B:
- PLT's law argument is correct as a law, but B makes Map the one collection where `contains` does not compile.
- Python (`k in d`) and JS (`Map.has`) both mean key membership. So `m.contains(k)` is the first guess for most models, and B turns that guess into an error.
- B also keeps the Rust-only name and deletes the shared one.
- Fix the law's text instead: define `Contains` per type (Map: key presence), which 03_types.md:658 already does.
- Also fix the 8-vs-9 Map count drift Web found.

**Q3: I change to B (`io.print_raw_bytes`).** Read against my own Phase A test, my Q3-A was wrong:
- I said the worst case is one name pair with hidden different behaviour. `read_bytes` (interceptable) beside `write_bytes` (not interceptable) is exactly that.
- DECISIONS.md:376 says the dispatch class follows the `_raw` name. A model that learns that rule predicts the bytes op's behaviour from its name alone.
- Q3-C is a near-duplicate of B. Collapse them and pick B: `print_raw` + a type word sorts next to `print_raw` in completion, and models extend a known stem more reliably than they move a suffix.
- Against Q3-D: it sends app code (binary pipes, image output) into `libc` with the magic fd `1`. That is a low-level trust surface for an ordinary task. The honest `Result` is a good point, but it belongs to [the open `_raw` ticket]'s question about `_raw`, not to this one.

**Q4: A, with Sys's addition.** The spec states: `_raw` ops write every byte (`fwrite` of len, so NUL survives) and flush before return.
- Without this, `io.write` → `print_raw` is not a no-change row: the fact check shows the flush is the only difference.
- `io.flush` is a separate friction ticket. Do not add it here.

**Q5: I change to A (the table).**
- One removal mechanism (table, fix line, result-changes column, `blink fix` rules) for functions, handle ops and methods is one concept to learn. Q5-B gives each method an ad hoc fix with no persistence rule.
- "Kept for good" matters most for stale names in training data, which is this ticket's whole problem.
- Removed names out of LSP completion: yes.
- PLT's "one sentence" is the same option. Collapse it into A.

**X1: keep.** **X2: keep.** They are two ends of one gate: X2 checks the source (lib/std `pub`) and X1 checks the output (llms text names no removed form). Make them one chore ticket. Neither is spec text.

**X3: keep.** It is the same column §3.2 already has, and `blink fix` needs it.

**Collapse summary:**

| Collapse | Into |
|---|---|
| Q3-C | Q3-B |
| PLT's one-sentence Q5 option | Q5-A |
| Sys's allocation contract and my "which form" line | one Q1-A text |
| U4 variations | private + removed row |
| X1, X2 | one chore ticket |

STABLE: ready to vote

##### Minimalism

###### U items
- **U1 to U3, U5:** agree.
- **U4:** agree. My `sqlite_handler(h)` row is optional. It only helps people who imported the name, and they get an import error either way. I will not split the vote over it, so collapse it into U4 as is.

###### Q1. List concat: I still favor Q1-B, with Q1-A as fallback
- `append` is the only name on the list that needs a warning (W0606) to stop people misusing it. Python and Rust both teach that `append` mutates. Spread can't be misread that way, and it has to exist anyway.
- Without a warning, a misread like that is a silent bug.
- If Q1-A wins, I want the AI/ML split line in the spec: "two lists: `a.append(b)`; a literal with extra elements or three or more sources: `[..a, x, ..b]`". Without that line, Q1-A is two ways to do one thing with nothing to choose between them.
- **Against the Sys variation** (spec one allocation of exactly `a.len() + b.len()`): that is an implementation detail, not language meaning. Leave it to codegen.

###### Q2. Map membership: I still favor Q2-A
- PLT's law is a good argument, but the spec does not state that law today. To justify Q2-B, we would first have to add a new law to `Contains`. Adding a rule in order to remove something is still an addition.
- Q2-A removes one method and adds nothing.
- Users expect `contains` on a map to test keys: Python's `k in d` and JS's `Map.has` both do.
- I rank Q2-B above the status quo, because either option leaves one name. I reject Sys's "keep both plus a lint" fallback. A lint that picks one of two aliases admits that one of them should not exist.

###### Q3. Binary stdout: I withdraw Q3-D and now favor Q3-A
- Q3-D has a real flaw. `libc.write_bytes(1, b)` goes around the stdout stream. A buffered `io.print` followed by a raw fd write can then come out in the wrong order. It also sends ordinary binary output through the FFI tier. My fault for missing it.
- I favor Q3-A, keeping the name `io.write_bytes`. Zero renames and zero removed rows is the smallest change, and the name pairs with `io.read_bytes`.
- **Cost:** the name does not say the op skips handlers. The table row must say so.
- **Collapse Q3-B and Q3-C into one option, "rename into the `_raw` family".** They differ only in word order. If the rename wins, use `print_raw_bytes`: `print_raw` plus a type suffix.

###### Q4. `_raw` write semantics: I favor Q4-A in contract form
- Spec text: "`_raw` ops write every byte of the text, including NUL, and flush before they return." This fixes the latent `printf("%s")` truncation bug, and it is what makes U3 a true alias.
- **Drop from Sys's version:** "at least one write(2) per call". That names an OS call, so it is an implementation detail.
- **Against a separate `io.flush`:** once `_raw` flushes, no user needs one. `print` stays buffered for throughput. An `io.flush` friction ticket is fine only if someone shows a need that `print_raw` does not meet.

###### Q5. Diagnosing removed methods: I favor Q5-A in PLT's one-sentence form
- The sentence: "The §3.2 and §4.4 tables are also checked when method lookup fails." No new table and no new columns. It reuses the existing `blink fix` rules.
- Q5-B also needs a list of removed names somewhere. Without the tables, that list has no single place, and the `Result changes` rule is lost. So Q5-B is the bigger mechanism, not the smaller one.
- **Drop the LSP completion clause.** Removed names are not on the surface, so completion cannot offer them anyway. It is tooling, not spec.
- **Collapse:** Q5-A, PLT's sentence and Web's request are one option.

###### Extras
- **X1:** defer to a chore ticket. It is a CI gate, not language spec.
- **X2:** defer to a chore ticket. It is a repo lint, and it overlaps X1.
- **X3:** yes. The Q1-R rule (`blink fix` never auto-applies a row whose result changes) needs the column to work. The `file_exists`, `is_dir`, `file_mtime` and `process_*` rows change their result types. Without the column, the fix tool would rewrite them silently.

STABLE: ready to vote

#### Phase C — Final vote

Ballot:

Final option-space after Phase B round 1 (collapses the panel asked for are applied: Q3-B+C → Q3-B `io.print_raw_bytes`; Q3-D withdrawn by its proposer; Q5 variants → one option; X1+X2 merged).

For EACH question give:
1. **Vote** — option label.
2. **Reasoning** — 2–4 sentences from your domain.
3. **Concern** — one sentence on what could go wrong with the option you expect to win (from your point of view).

###### Q0. Shared removals (U1–U5)
- U1 remove `List.chain`; U2 `list_concat` → §3.2 row, lib fn private; U3 `io.write(s)` → §4.4 row → `io.print_raw(s)`; U4 `db.connect(path)?` only — `db_connect`, `sqlite_connect` get §4.4 rows (result changes: yes), `sqlite_handler` private, fix 04_effects.md:1803; U5 finish already-decided fs/process removals in compiler + lib/std.
- **Q0-yes** adopt U1–U5 / **Q0-no** (say which item you reject)

###### Q0v. `sqlite_handler(h)` removed row
- **Q0v-row** private AND a removed row → `db.connect(path)?` (result changes: yes) (Min, Sys, PLT, Web)
- **Q0v-private** private, no row (AI/ML)

###### Q1. List concat
- **Q1-A** keep `a.append(b)` and `[..a, ..b]`, with the §3.2 rule line "two lists: `a.append(b)`; a literal with extra elements or three or more sources: `[..a, x, ..b]`".
- **Q1-B** spread is the only concat form; `append` gets a removed row → `[..a, ..b]`.

###### Q1v. Cost text for concat (applies under either Q1 result)
- **Q1v-alloc** "makes one allocation of exactly `a.len() + b.len()`" (Sys)
- **Q1v-big-o** "O(a.len() + b.len()); the operands do not change" (PLT)
- **Q1v-none** no cost text in the spec (Min)

###### Q2. Map membership
- **Q2-A** remove `contains_key` (removed row → `m.contains(k)`); `Contains` is the one name; §3 states what `contains` means per instance (Map: key presence) and states no general `contains(x) == iter().any(e == x)` law.
- **Q2-B** keep `contains_key`; drop `impl Contains[K] for Map`.

###### Q3. Binary stdout
- **Q3-A** keep the name `io.write_bytes(b: Bytes)`, specced as a raw-tier row (no handler, no trace).
- **Q3-B** spec it as `io.print_raw_bytes(b: Bytes)` (raw tier); `io.write_bytes` gets a removed row.

###### Q4. `_raw` write semantics
- **Q4-A2** spec two observables for `print_raw`, `eprint_raw` and the bytes op: (a) every byte is written, NUL included; (b) the bytes are flushed before the call returns.
- **Q4-A3** Q4-A2 plus (c) output from `print`/`println` and `_raw` ops to the same stream appears in call order (Sys).
- **Q4-none** no rule in the spec.

###### Q5. Removed methods and handle ops
- **Q5-A** the §3.2 / §4.4 removed-forms tables also hold method and handle-op rows (same columns, same `blink fix` rules) and are also checked when method lookup fails (E0505).
- **Q5-B** no table rows; the UnresolvedMethod diagnostic carries a free-text fix.

###### X. Extras
- **X12** one deferred chore ticket: CI gate that generated `blink llms` output names no removed form and the public std surface for built-in types matches the spec. — **X12-yes / X12-no**
- **X3** add a "Result changes" column to the §4.4 removed table. — **X3-yes / X3-no**

Tally: Q0 6-0; Q0v 6-0 (row); Q1 4-2 (A; PLT and Minimalism for B); Q1v 4-1-1 (big-o; Systems alloc, Minimalism none); Q2 6-0 (A); Q3 5-1 (B; Minimalism for A) **(dissent)**; Q4 6-0 (A3); Q5 6-0 (A); X12 6-0; X3 6-0.

##### Systems

###### Q0. Shared removals
**Vote:** Q0-yes
**Reasoning:** Each removed name is either unspecced or already removed by the spec. Two of them (`db_connect`, `sqlite_connect`) hide an open failure behind a type that cannot express it. Removing them costs nothing at run time and closes a null-handle bug class.
**Concern:** U5 means changing compiler builtins that the compiler's own source may use. If the bootstrap dance is not followed, the self-host breaks.

###### Q0v. `sqlite_handler(h)` removed row
**Vote:** Q0v-row
**Reasoning:** llms-full.md taught this name, so it exists in training data. A row turns a bare "undefined function" into a fix that names the replacement, at zero run-time cost.
**Concern:** the replacement takes a path, not a handle, so code that holds an open `Sqlite3` has no one-step fix. The row must be marked so that `blink fix` does not apply it.

###### Q1. List concat
**Vote:** Q1-A
**Reasoning:** Both forms lower to the same runtime call, so the choice is about how code reads, not what it costs. `append` keeps pipelines left to right (`xs.filter(p).append(ys)`). Spread stays for literals with mixed parts, and the §3.2 line says which form to use where.
**Concern:** the `append` name still suggests mutation, so W0606 stays load-bearing. A dropped result keeps showing up in user code.

###### Q1v. Cost text for concat
**Vote:** Q1v-alloc
**Reasoning:** Big-O does not tell a user what the hardware does. A form that does two allocations and an extra copy is still O(n+m). One allocation of the final size is the contract users need when they choose between `append` and spread, and codegen can test it.
**Concern:** "exactly" can over-constrain a future allocator that rounds capacity up or stores small lists inline. The wording may need to become "one allocation, sized for the result".

###### Q2. Map membership
**Vote:** Q2-A
**Reasoning:** `contains` and `contains_key` compile to the same hash probe: two names for one machine operation. Q2-B forces generic key-membership code to build `m.keys()`, an O(n) allocation in place of an O(1) probe, which is the kind of hidden cost this panel exists to stop.
**Concern:** with no general `contains` law, generic code over `Contains` cannot assume iteration agrees with membership. Doc text must make Map's key semantics plain.

###### Q3. Binary stdout
**Vote:** Q3-B
**Reasoning:** The name must show the dispatch class (no handler, no trace), and the `_raw` suffix already does that for the Str ops. `print_raw_bytes` uses the same stream and the same rules as `print_raw`, so codegen has one path per fd.
**Concern:** users who look for the twin of `io.read_bytes` will search for `write_bytes` first, so the removed row must exist on day one.

###### Q4. `_raw` write semantics
**Vote:** Q4-A3
**Reasoning:** All three are visible behaviour, not lowering details. Today `printf("%s")` drops bytes after a NUL, which is a real bug. A missing flush deadlocks LSP clients. Clause (c) is the rule that makes codegen use one buffered stream per fd. Without it, a later change to the lowering (raw `write(2)` beside a stdio buffer) reorders output silently, and only when stdout is a pipe.
**Concern:** per-call flush on `_raw` costs one syscall per call, so code that streams many small `_raw` writes is slow. The docs must point it to `print`.

###### Q5. Removed methods and handle ops
**Vote:** Q5-A
**Reasoning:** One table for every removed form gives the same `blink fix` safety rules and the same LSP exclusion. It costs nothing at run time and only runs when lookup fails. Free text has no "result changes" column, so tooling cannot know when an auto-fix is unsafe.
**Concern:** the table only grows. Lookup-failure checks must stay off the hot path of a correct compile.

###### X12
**Vote:** X12-yes
**Reasoning:** Each duplicate this ticket removes came in through an unchecked `pub fn` or a doc line. Without a gate they come back.
**Concern:** the gate needs a machine-readable list of the specced surface, and keeping that list in step with sections/ is its own chore.

###### X3
**Vote:** X3-yes
**Reasoning:** Rows where Int becomes Result (`file_exists`, `process_*`, the DB rows) must not be applied by `blink fix`, and only the column says so. The §3.2 twin already has the column.
**Concern:** existing §4.4 rows each need a correct yes or no, and one wrong "no" lets `blink fix` change program behaviour.

##### Web/Scripting

###### Q0
- **Vote:** Q0-yes
- **Reasoning:** Every item takes away a name that the spec never voted on or already removed. Each removed name now gets a fix that names the replacement. This is the cheapest Principle 2 win in the ticket.
- **Concern:** llms-full.md and the lib can stay behind the spec again unless the chore work lands in the same release.

###### Q0v
- **Vote:** Q0v-row
- **Reasoning:** Code and llms-full.md already call `sqlite_handler`. A user who hits it should see `db.connect(path)?`, not a bare privacy error. The row costs one line.
- **Concern:** The fix changes the argument from a handle to a path, so `blink fix` must never apply it on its own. The "result changes: yes" mark covers that.

###### Q1
- **Vote:** Q1-A
- **Reasoning:** `.append` keeps method chains left to right, the way JS and Kotlin devs read them, and it shows in completion after `xs.`. Spread covers literals with mixed parts. The rule line tells everyone which to use. W0606 already catches a lost result from someone who thinks `append` mutates.
- **Concern:** Python devs will still write `xs.append(ys)` as a statement at first. We trust W0606 to catch that every time.

###### Q1v
- **Vote:** Q1v-big-o
- **Reasoning:** Users want to know that concat is linear and leaves the operands alone. "Exactly one allocation" is an implementation promise, and it would block later changes, such as reusing a buffer. Big-O tells a script writer all they need.
- **Concern:** Systems users who need the allocation count will not find it in the spec.

###### Q2
- **Vote:** Q2-A
- **Reasoning:** Python `k in d`, JS `Map.has`, Kotlin `k in map`: every language people come from tests keys. `m.contains(k)` is the name people and LLMs type first, and generic `Contains` code keeps working on maps. Stating the meaning per instance is clearer than a general law that Map breaks.
- **Concern:** Rust and Java devs will type `contains_key` out of habit. The removed row must give a fix that is fast and plain.

###### Q3
- **Vote:** Q3-B
- **Reasoning:** `print_raw_bytes` sits next to `print_raw` in completion and follows the rule that dispatch mode reads from the name. `write_bytes` next to `print_raw` brings back "write or print?", the same question this ticket exists to stop.
- **Concern:** It breaks symmetry with `io.read_bytes`, so some users will guess `io.write_bytes` first. The removed row has to catch that.

###### Q4
- **Vote:** Q4-A3
- **Reasoning:** If `println` buffers and `print_raw` does not, mixed output comes out in the wrong order. That is the classic "why is my output scrambled?" question, from Python's unbuffered stderr against buffered stdout. Call order on the same stream is what every user assumes, so the spec should promise it. Flush and NUL-safety are needed so the `io.write` migration does not break LSP framing.
- **Concern:** A user handler that intercepts `IO.Print` breaks the ordering promise. The text must scope (c) to the default handler.

###### Q5
- **Vote:** Q5-A
- **Reasoning:** One table that keeps every removed name for good is a source that tools, docs and LLMs can read. Free-text fixes drift and leave no record. Same columns and same `blink fix` rules mean users learn one mechanism.
- **Concern:** The table grows over time, so the spec should keep it in an appendix and out of the main text.

###### X12
- **Vote:** X12-yes
- **Reasoning:** llms-full.md is the training surface, and today it teaches four names this ticket removes. A CI gate stops that drift for good.
- **Concern:** A strict gate can block unrelated changes if it has false positives.

###### X3
- **Vote:** X3-yes
- **Reasoning:** `file_exists` going from Int to Result must never be auto-fixed, and today §4.4 has no column to say so. §3.2 already has the column, so this makes the two tables the same.
- **Concern:** Someone must fill in the column correctly for each existing row, or `blink fix` will apply a bad rewrite.

##### PLT

###### Q0: Q0-yes
**Reasoning:** Each item removes a name that had no typing rule in the spec, or one whose type lied about failure (`db_connect`, `sqlite_connect`). U5 makes the compiler match decisions that are already made.
**Concern:** The U3 row is only exact if Q4 passes; without Q4, `blink fix` would rewrite `io.write` to a call that does not flush.

###### Q0v: Q0v-row
**Reasoning:** llms-full.md documents `sqlite_handler`, so users and models will write it. A row turns a bare E0504 into a typed fix at no cost. "Result changes: yes" is the honest mark: the argument changes from `Sqlite3` to `Str`, and the result changes to `Result`.
**Concern:** The row's replacement takes a path, not a handle, so code that holds a `Sqlite3` will not have a one-step fix.

###### Q1: Q1-B
**Reasoning:** Spread covers every case `append` covers, so the overlap is total in one direction. §3.2 removed `int_to_str` in favour of `"{n}"` for the same reason. A method name that needs W0606 to stop readers from assuming it mutates is a weak name.
**Concern:** If Q1-A wins, the rule line must ship with it, or models will mix both forms at random.

###### Q1v: Q1v-big-o
**Reasoning:** The spec should state observables: the cost bound and that the operands do not change. "One allocation" is a lowering detail, and stating it would forbid valid strategies such as reuse when the receiver is not shared.
**Concern:** Q1v-alloc would tie codegen to a representation, and spec text is hard to take back.

###### Q2: Q2-A
**Reasoning:** One membership name across List, Set, Map and Str is the most compositional choice. My law objection is met if §3 states the meaning for each instance (Map: key presence) and states no general membership law over iteration. With that, no coherence rule is broken.
**Concern:** A later spec change could add the general `contains`/`iter` law and silently make Map's instance wrong. Whoever writes the text must keep the "no general law" sentence.

###### Q3: Q3-B
**Reasoning:** The name should show the dispatch mode. `write_bytes` pairs by name with `io.read_bytes`, which IS handler-dispatched (`IO.Read`), so the name would claim a dispatch that does not exist. `print_raw_bytes` stays in the `_raw` class.
**Concern:** If [the open `_raw` ticket] later folds `_raw` into a handler op, this name must move with the class, not on its own.

###### Q4: Q4-A3
**Reasoning:** (a) and (b) close a real bug: `printf("%s")` cuts a `Str` at an embedded NUL. Once `_raw` flushes, (c) is the observable users rely on. Without it, a flushed `_raw` write can appear before an earlier buffered `print`, so the order of output no longer matches the order of the program.
**Concern:** The text for (c) must say it holds under the default `IO.Print` handler, because a user handler can send `print` output somewhere else.

###### Q5: Q5-A
**Reasoning:** `blink fix` needs the replacement and the "result changes" column as data it can check. A free-text fix gives it nothing. The rows extend the existing §3.2 rule to method lookup; they add no new mechanism.
**Concern:** The table only grows, so the spec needs an editorial rule that keeps it to names that were once public.

###### X12: X12-yes
**Reasoning:** The duplicates came back because generated docs and lib/std drifted from the spec. A gate stops that, and making it a chore keeps it out of the spec text.
**Concern:** If the "matches the spec" check is scoped too wide, it will flag lib modules that the spec does not list one function at a time.

###### X3: X3-yes
**Reasoning:** `file_exists` → `fs.stat` changes `Int` to `Result[Stat, FsError]`. Without the column, the §4.4 table cannot mark that `blink fix` must not auto-apply that row.
**Concern:** Each existing §4.4 row must be audited when the column is added, or a wrong "no" will let `blink fix` apply a change of type.

##### DevOps

###### Q0
- **Vote:** Q0-yes
- **Reasoning:** Every item removes a name that the spec never voted on, or that the spec already removed. Each removed name gets a table row, so the diagnostic names the fix and `blink fix` knows whether it may apply it. Leaving any of them in place keeps two entries in LSP completion for one operation.
- **Concern:** U3's "result changes: no" is only true if Q4 makes `_raw` flush. If Q4 fails, `blink fix` auto-applies a rewrite that changes output timing.

###### Q0v
- **Vote:** Q0v-row
- **Reasoning:** `sqlite_handler` was `pub`, so user code calls it today. Making it private with no row turns that call into a bare visibility error with no fix. A row costs one line and gives the user the replacement.
- **Concern:** The fix changes a handle argument into a path, so the row must be marked suggestion-only, or `blink fix` produces code that does not compile.

###### Q1
- **Vote:** Q1-A
- **Reasoning:** Completion after `xs.` cannot offer spread, and users and models find operations by typing a dot. Chained calls read left to right in diffs and format cleanly across lines. W0606 already catches the misuse of `append` as a mutating call. The rule line tells users and models which form fits each case.
- **Concern:** The name `append` still suggests mutation to Python and Rust users, so W0606 must stay accurate and visible in the LSP.

###### Q1v
- **Vote:** Q1v-big-o
- **Reasoning:** The user can observe the cost and the fact that the operands do not change. An allocation count is a lowering detail that the spec should not freeze. Big-O also lets users compare `append` with `Iterator.chain`.
- **Concern:** None of note.

###### Q2
- **Vote:** Q2-A
- **Reasoning:** One name either way, but A keeps generic `Contains` callers working with Map, and Python users already expect `k in d` to test keys. Hover docs on `contains` can state the per-instance meaning, and the spec text does the same. The removed row makes the migration a safe auto-fix.
- **Concern:** A reader may still ask whether `contains` on Map tests keys or values, so the hover doc and the spec line must say "key presence" explicitly.

###### Q3
- **Vote:** Q3-B
- **Reasoning:** The name must show the dispatch mode. `write_bytes` reads as the twin of the handler-dispatched `read_bytes`, but the two behave differently. With the `io.print_raw` prefix, completion shows the raw ops together.
- **Concern:** If [the open `_raw` ticket] later removes the `_raw` tier, this name has to move again, which is a second migration for the same callers.

###### Q4
- **Vote:** Q4-A3
- **Reasoning:** Flush and NUL are both needed so that `io.write → io.print_raw` is a true "no result change" rewrite and binary-safe. Call order is the bug class I raised against Q3-D: interleaved output that comes out of order is very hard to diagnose. Stating order as an observable contract stops a future lowering from breaking it.
- **Concern:** A handler can intercept `print`, and then its output never reaches the stream, so (c) must be scoped to the default handler.

###### Q5
- **Vote:** Q5-A
- **Reasoning:** One table with one set of columns gives `blink fix` and the LSP code action a single policy for applying fixes. Free-text fixes (Q5-B) have no "result changes" field, so each diagnostic would decide on its own whether its fix is safe. The tables also serve as the permanent record of what was removed.
- **Concern:** The method rows need receiver-type matching (for example `chain` on `List` but not on `Iterator`), so the table key must include the receiver type.

###### X12
- **Vote:** X12-yes
- **Reasoning:** Unspecced names in llms-full.md are how these duplicates spread to users and models. A gate stops them coming back. It is repo tooling, so it belongs in a chore ticket, not in the spec.
- **Concern:** A "matches the spec" check needs a parseable source for the specced surface, or the gate becomes a hand-kept list that drifts.

###### X3
- **Vote:** X3-yes
- **Reasoning:** `blink fix` must not auto-apply `file_exists → fs.stat` or the `process_*` rows, because their result types change. §3.2 already has this column, and §4.4 should match it.
- **Concern:** None of note.

##### AI/ML

###### Q0
**Vote:** Q0-yes
**Reasoning:**
- Every item removes a name that is unspecced, an alias, or already removed by the spec.
- llms-full.md documents most of them, so they sit in training data today. Removing each one with a fix row is how a model's stale guess gets corrected in one compile.

**Concern:** U5 is chore work, and it can lag again unless the X12 gate lands with it.

###### Q0v
**Vote:** Q0v-row
**Reasoning:**
- I changed from Phase A. llms-full.md taught `sqlite_handler`, so models will type it.
- A row with a fix beats a bare E0504. "Private" and "row" do not conflict.

**Concern:** the fix cannot be applied mechanically: it needs a path, and the caller has a handle. The row must stay suggestion-only.

###### Q1
**Vote:** Q1-A
**Reasoning:**
- Models write method chains (`xs.filter(p).append(ys)`). Spread-only forces an inside-out form that costs more tokens and invites bracket errors.
- The Python mutation trap is already caught by a type error (element argument) and W0606 (discarded result), both with fixes.
- The one-line rule removes the decision point between the two forms.

**Concern:** `append` keeps a name that Python-trained models misread. We rely on W0606 staying in place for good.

###### Q1v
**Vote:** Q1v-big-o
**Reasoning:**
- A model needs to know both forms cost the same, so it does not "optimize" one into the other. O(a+b) with unchanged operands says that.
- "Exactly one allocation of a.len() + b.len()" is a lowering detail, and it does not even fit spread with extra elements.

**Concern:** Big-O alone does not rule out a lazy view, but "the operands do not change" plus the eager spread vote covers it.

###### Q2
**Vote:** Q2-A
**Reasoning:**
- `m.contains(k)` is the first guess from Python (`k in d`) and JS (`Map.has`) habits.
- It gives one membership name across List, Set, Map and Str, which is the cheapest pattern to learn.
- Q2-B would make Map the one collection where `contains` fails, and it keeps the Rust-only spelling.

**Concern:** Rust- and Java-trained models will keep writing `contains_key`, so the removed row and its fix must ship in the same change.

###### Q3
**Vote:** Q3-B
**Reasoning:**
- `write_bytes` beside `read_bytes` is one name pair with hidden different dispatch: read is interceptable, write is not. That is the worst learnability trap.
- With `print_raw_bytes`, the `_raw` rule (DECISIONS.md:376) predicts the behaviour from the name alone.

**Concern:** models that guess `write_bytes` by symmetry will hit the removed row often, so its fix text must be exact.

###### Q4
**Vote:** Q4-A3
**Reasoning:**
- A model writing a progress bar mixes `print` and `print_raw` and assumes the output appears in call order. If the spec does not promise that, generated code is subtly wrong.
- (a) and (b) are what makes `io.write` → `print_raw` a no-change row.

**Concern:** a handler that intercepts `print` breaks (c), so the text must scope (c) to the default handler.

###### Q5
**Vote:** Q5-A
**Reasoning:**
- One removal mechanism (table, fix line, result-changes column, `blink fix` rules) for functions, methods and handle ops is one concept to learn.
- The table is kept for good, which is what stale training-data names need.
- Free-text fixes have no persistence rule and drift.

**Concern:** the E0505 path must check the table only after real lookup fails, or a user method named `chain` on their own type gets a false hit.

###### X12
**Vote:** X12-yes
**Reasoning:**
- llms-full.md is the surface models actually read, and it is how every duplicate in this ticket spread.
- A gate that ties it to the spec stops the next batch.

**Concern:** a check based on a name list can miss names created by the lowering tables (like `List.chain` in cg_call.bl), so the gate should also read the compiler's method table.

###### X3
**Vote:** X3-yes
**Reasoning:**
- It is the same column §3.2 has, and `blink fix` needs a machine-readable signal for rows that change behaviour, such as `file_exists` and `process_*`.

**Concern:** none of substance. The rows must be marked correctly at the time they are written.

##### Minimalism

###### Q0
- **Vote:** Q0-yes.
- **Reasoning:** Each of U1 to U5 removes a name and adds nothing. Most of the names were never specced, or the spec already removed them.
- **Concern:** U5 is a large compiler and lib change. If it is not finished, the spec and the compiler stay out of step.

###### Q0v
- **Vote:** Q0v-row.
- **Reasoning:** The row costs one table line. It turns an opaque "private item" error into a fix that names `db.connect`. Users have seen `sqlite_handler` in llms-full.md and in the spec example, so the row helps them migrate.
- **Concern:** The table grows a little for a name that was never voted public.

###### Q1
- **Vote:** Q1-B.
- **Reasoning:** Spread has to exist for literals anyway and covers every concat. `append` is the only name here that needs a warning (W0606) to stop people misreading it as a mutation. Q1-A needs a rule line to choose between two forms that do the same thing, which is Principle 2's failure stated in the spec.
- **Concern:** If Q1-A wins, the rule line may be ignored in practice, and both forms will spread through training data with no choice between them.

###### Q1v
- **Vote:** Q1v-none.
- **Reasoning:** Concat cost is a codegen property, not language meaning. The spec already says spread is an eager copy, and "the operands do not change" follows from immutable values. Allocation counts and Big-O text lock the implementation in place and add nothing a user can rely on.
- **Concern:** Without cost text, a backend could make concat slow without breaking any rule.

###### Q2
- **Vote:** Q2-A.
- **Reasoning:** Q2-A removes one method and adds no new law. Q2-B needs a membership law that the spec does not state today. Key presence is what Python's `in` and JS's `Map.has` mean, and generic code can still pass a map as `Contains[K]`.
- **Concern:** Readers who expect Haskell's `elem` will read `m.contains(x)` as a test of values, unless §3 states the per-instance meaning plainly.

###### Q3
- **Vote:** Q3-A.
- **Reasoning:** Keeping the name means no rename and no removed row. It also pairs with `io.read_bytes`. The table row already states the raw tier, so a new name adds churn for a small gain in readability.
- **Concern:** Readers cannot tell from `write_bytes` that the op skips handlers, while `read_bytes` does not skip them.

###### Q4
- **Vote:** Q4-A3.
- **Reasoning:** Clause (c) is a contract users can see, not an implementation detail. If a raw write could jump ahead of buffered `print` output, mixed output would be wrong. That is the flaw that made me withdraw Q3-D. It costs nothing when both ops share one stream, and it closes a real bug class.
- **Concern:** Clause (c) ties any future handler-backed `print` to raw-op ordering, and that may restrict [the open `_raw` ticket].

###### Q5
- **Vote:** Q5-A.
- **Reasoning:** Reusing the existing tables and `blink fix` rules adds no new mechanism. Q5-B still needs a list of removed names, but with no single place for it and no Result-changes guard.
- **Concern:** The §3.2 table may slowly turn into a changelog of every name ever removed.

###### X12
- **Vote:** X12-yes.
- **Reasoning:** A deferred chore costs the spec nothing. It stops llms-full.md from teaching forms that this ticket removes, and that is how three unvoted connect functions got in.
- **Concern:** If the gate is strict about the std surface, it may block real lib work until the spec catches up.

###### X3
- **Vote:** X3-yes.
- **Reasoning:** The Q1-R rule needs the column, or `blink fix` cannot tell which §4.4 rows it must not auto-apply. The `file_exists`, `process_*` and DB rows all change their result types.
- **Concern:** The column may be filled in wrongly for older rows, unless someone audits each one.

#### Phase D — Round 2 (Q1 and Q1v)

Q1 (4-2) and Q1v (4-1-1) were closer than 5-1, so the panel had one focused round on those two questions. Each panelist read the others' Phase C text on Q1 and Q1v, wrote a reply, then voted alone.

Tally: Q1 5-1 for Q1-A (PLT moved from B; Minimalism **(dissent)** stays on B). Q1v 6-0 for big-o (Systems moved from alloc, Minimalism from none). The user signed off on the tally.

##### Debate replies

##### Systems

**Q1:** I keep Q1-A. PLT and Min say spread covers everything `append` covers. That is true for meaning, but not for how the code reads. Pipelines read left to right only with a method. `int_to_str` is not a precedent here: it was a function form beside a syntax form, and the ban on function forms of built-in methods removed it. `append` is a method on the voted surface. The rule line removes the choice point, and W0606 already catches the mutation misreading, with a fix.

**Q1v:** I concede to big-o. PLT's point holds: when the receiver is not shared, reusing its buffer makes zero allocations, and "exactly one" would forbid that, which is the better code. AI/ML is right that "exactly a.len() + b.len()" does not fit spread with extra elements. My real worry was hidden extra copies, and "O(a.len() + b.len()), the operands do not change" plus the eager-spread vote cover enough of it. I drop alloc.

##### Web/Scripting

**To PLT and Min (Q1-B):** The `int_to_str` precedent does not fit. That was a free function against syntax, and the call shape stayed the same. Here, removing a method forces inside-out code in every pipeline. Spread does not cover what `append` covers: it does not chain. "Needs W0606" is also weak. W0606 already covers nine copy methods, `sort`, `reverse`, `filter`, `slice`, `merge` and the others (03_types.md:966), so `append` adds no new warning burden. Rule lines are normal, too: Python's "use a comprehension, not `map`" works. I agree with PLT that the rule line must ship with Q1-A.

**To Sys (alloc):** Two allocations is still a valid concern. But "exactly one allocation" does not fit `[..a, x, ..b]` or small-list inlining, and Sys's own concern admits that. Big-O plus "the operands do not change" gives users what they can see. Allocation counts belong in a codegen test.

**To Min (none):** With no cost text, a quadratic backend is legal. Users can rely on O(n+m).

##### PLT

**Q1.** The left-to-right argument holds. `[..xs.filter(p), ..ys]` nests where `xs.filter(p).append(ys)` composes, and nesting is a real cost. I can accept Q1-A if the rule line is enforced, not advisory. A lint (with a `blink fix`) should flag a literal that is exactly `[..a, ..b]`, two spreads and nothing else, and point to `a.append(b)`. Then each case has one form, which meets Principle 2, and Min's concern that "the rule line will be ignored" has a gate.

**Q1v.** Min: "the operands do not change" does not follow from immutability here, because the name `append` suggests mutation. The linear bound is also something users can observe; without it, a backend could make concat quadratic and still meet the spec. Sys: "one allocation" fails for spread with extra elements, and it forbids in-place reuse when the receiver is not shared. Keep big-O.

##### DevOps

**To PLT and Min (Q1-B):** The `int_to_str` precedent points the other way. That row removed a free *function* form so the operation lives on the *method*, and the §3.2 rule is "methods only". Removing the method `append` for syntax inverts that rule.

Min's real concern is that the rule line gets ignored. Tooling can enforce it: a lint on a literal made of exactly two spreads and nothing else (`[..a, ..b]`) with a machine-applicable fix to `a.append(b)`. Then the choice between the two forms is no longer up to the user, and the training data converges on one form.

**To Sys (Q1v-alloc):** Two allocations is a performance bug, not a change in meaning. Write a codegen test for it, not spec text. Your own concern ("exactly" over-constrains) shows the wording is unstable.

**To Min (Q1v-none):** Your concern, "a backend could make concat slow", is the case for big-O. It is a one-line bound that rules out quadratic lowering and freezes no implementation detail.

##### AI/ML

**To PLT and Min on Q1:**
- The `int_to_str` → `"{n}"` precedent does not carry over. `"{n}"` reads in the same order as the call it replaced. Spread inside a chain does not: `xs.filter(p).append(ys)` becomes `[..xs.filter(p), ..ys]`, which is inside-out, longer, and prone to bracket errors in generated code.
- The rule line is not a Principle 2 failure. It splits the domain: two lists use `append`, and literals with extra parts use spread. That is one answer per case, which is what Principle 2 asks.
- W0606 already exists for other non-mutating methods, so `append` adds no new mechanism.

**To Min on Q1v:** your own concern, that a backend could make concat slow without breaking a rule, is the case for Big-O text.

**To Sys on Q1v:** "one allocation, sized for the result" is still a lowering promise. The observable a user relies on is linear cost with operands unchanged.

##### Minimalism

**Q1.**
- The case for `append` rests on two points: completion after `xs.` and left-to-right chains. Both are about how code reads. Neither shows a second operation.
- Sys concedes that W0606 "stays load-bearing". Web and AI/ML say they "trust it every time". A form that needs a permanent warning plus a spec rule line to be used correctly costs more than one inside-out bracket.
- Completion can offer the spread form as a snippet. That is a tooling task, not a reason to keep two names in the language.
- I stay with Q1-B. If Q1-A wins, the rule line is mandatory.

**Q1v.**
- I accept the Big-O argument. A linear bound with unchanged operands is something a user can see, and it is stable. It also answers my own concern that a backend could make concat slow without breaking a rule.
- Q1v-alloc is still a lowering detail. As AI/ML points out, it also does not fit spread with extra elements.
- I move to Q1v-big-o.

##### Votes

##### Systems

###### Q1. List concat
**Vote:** Q1-A
**Reasoning:** Both forms lower to the same runtime call, so the choice is about how code reads. `append` keeps pipelines left to right, and spread covers literals with mixed parts. The §3.2 rule line removes the choice point between them.
**Concern:** the rule line must ship with the change, or both forms will spread at random through user code and training data.

###### Q1v. Cost text for concat
**Vote:** Q1v-big-o
**Reasoning:** The bound and the fact that the operands do not change are what users can observe. A fixed allocation count would forbid buffer reuse when the receiver is not shared, which is cheaper on the hardware, and it does not fit spread with extra elements. Big-O plus the eager-spread vote rules out a lazy view.
**Concern:** Big-O permits a constant-factor regression (an extra copy) that no spec rule catches. A codegen benchmark must guard it.

##### Web/Scripting

###### Q1
- **Vote:** Q1-A
- **Reasoning:** `.append` keeps pipelines left to right, and it shows in completion after `xs.`. Spread cannot chain, so it does not cover every use of `append`. Spread stays for literals with mixed parts, and the rule line removes the choice. W0606 already covers `sort`, `reverse`, `filter` and the other copy methods, so `append` adds no new burden.
- **Concern:** If the rule line is left out of §3.2 or llms-full.md, both forms will show up at random in training data.

###### Q1v
- **Vote:** Q1v-big-o
- **Reasoning:** O(a.len() + b.len()) with unchanged operands is what a user can see and rely on. It also stops a slow backend. "Exactly one allocation" does not fit spread with extra elements, and it freezes a lowering detail that a codegen test should check instead.
- **Concern:** A two-pass copy is still legal under the Big-O text, so systems users who care about allocations must rely on codegen tests, not the spec.

##### PLT

###### Q1: Q1-A
**Reasoning:** The rule line splits the cases with no overlap. Two lists use `append`. A literal with extra elements, or with three or more sources, uses spread. So each case has one form, and pipelines stay compositional (`xs.filter(p).append(ys)`). I give up on spread-only: the `int_to_str` precedent does not fully transfer, because spread forces nesting in method pipelines.
**Concern:** If no lint flags the bare two-spread literal `[..a, ..b]` and points to `a.append(b)`, the rule stays advisory, and both forms will spread through training data.

###### Q1v: Q1v-big-o
**Reasoning:** The spec should state what users can observe: concat runs in O(a.len() + b.len()) and leaves both operands unchanged. That rules out a quadratic backend and lazy views. It does not freeze an allocation count, which fails for spread with extra elements and blocks reuse when the receiver is not shared.
**Concern:** Users who need the allocation behaviour must look in docs/build/, not in the spec.

##### DevOps

###### Q1
- **Vote:** Q1-A
- **Reasoning:** Users find operations through completion after a dot, and chained calls read left to right in diffs and in `blink fmt` output. The `int_to_str` precedent supports method forms, not syntax replacing a method. A lint with a machine-applicable fix (`[..a, ..b]` → `a.append(b)`) makes the rule line enforceable, so the two forms do not drift apart in practice.
- **Concern:** If the rule line ships with no lint behind it, Min's prediction comes true and both forms spread through training data.

###### Q1v
- **Vote:** Q1v-big-o
- **Reasoning:** The bound and "the operands do not change" are what a user can observe. A linear bound rules out a slow backend without freezing an allocation strategy. An allocation count belongs in a codegen test, not in the spec.
- **Concern:** Big-O does not catch a constant-factor regression such as a second copy, so codegen needs its own test for that.

##### AI/ML

###### Q1
**Vote:** Q1-A
**Reasoning:**
- Models write method chains. Spread-only forces inside-out forms that cost tokens and invite bracket errors.
- The rule line gives one answer per case (two lists: `append`; literal with extra parts: spread), so there is no free choice left.
- The Python mutation trap is caught by the type check and W0606, each with a fix.

**Concern:** if the rule line is not in llms-full.md beside `append`, models will mix both forms at random.

###### Q1v
**Vote:** Q1v-big-o
**Reasoning:**
- A model needs to know that `append` and spread cost the same, so it does not rewrite one into the other. It also needs to know concat is linear and not lazy.
- "O(a.len() + b.len()); the operands do not change" states exactly those observables and nothing about the lowering.

**Concern:** Big-O does not stop a constant-factor regression, so codegen needs its own perf check.

##### Minimalism

###### Q1
- **Vote:** Q1-B.
- **Reasoning:** Spread covers every concat and must exist for literals anyway. The case for `append` is about how code reads, and it depends on a warning (W0606) that will never go away, plus a rule line, to stop people misusing it. One form with no trap beats two forms that need a rule to choose between them.
- **Concern:** If Q1-A wins and the rule line is not enforced by a lint, models will mix both forms at random.

###### Q1v
- **Vote:** Q1v-big-o.
- **Reasoning:** A linear bound with unchanged operands is a stable fact a user can see. It closes my own concern that a backend could make concat slow without breaking a rule. "One allocation" stays a lowering detail, and it does not fit spread with extra elements.
- **Concern:** Readers may take the Big-O line as a promise about allocations, which the spec does not make.

### Final Spec

```blink
let all = evens.append(odds)              // two lists
let framed = [header, ..rows, footer]     // literal with extra elements
let lazy = xs.into_iter().chain(ys.into_iter())

ages.contains("ann")                      // key presence; no contains_key

io.print_raw("\r{done}/{total}")         // flushed, in call order with io.println
io.print_raw_bytes(png)                   // binary stdout

with db.connect("app.db")? {
    db.exec(t"CREATE TABLE users (name TEXT)")?
}
```

- Concatenation: `a.append(b)` for two lists; spread for a literal with extra elements or three or more sources. Both run in O(`a.len() + b.len()`), and neither operand changes. No `List.chain`, no `list_concat` (§3.2.2 *Concatenation*, §2.16).
- `Map.contains_key` is removed. `contains` tests key presence on a `Map`. The `Contains` trait states no general law that ties `contains` to iteration (§3.2.2 *The `Contains` Trait*).
- The §3.2 and §4.4 removed tables also hold method and handle-op rows, keyed by receiver type and read only after method lookup fails (E0505) (§3.2 *Removed methods*).
- `io.write` → `io.print_raw`; `io.write_bytes` → `io.print_raw_bytes` (§4.4).
- A `_raw` operation writes every byte and flushes before it returns. Under the default `IO.Print` handler, stdout output keeps call order with `io.print`/`io.println` (§4.4 *`_raw` writes*).
- `db.connect(path)?` is the one DB form. `db_connect`, `sqlite_connect` and `sqlite_handler` have §4.4 rows (§4.4, §4.7.2).
- §4.4's removed table has a Result changes column.
- Follow-up chore: a CI gate on `blink llms` output and the std public surface (X12). A lint that flags a bare two-spread `[..a, ..b]` is a separate spec question (raised by PLT, DevOps and Minimalism in Phase D).
