[< All Decisions](../DECISIONS.md)

# TemplateValue Bytes — Design Rationale

> **Amends [Template Surface](template-surface.md) Q3.** That vote went 4-2 for five variants, with sys and web dissenting for `Bytes`. This panel revisits the dissent before any third-party handler exists.

### Problem Statement

The Template surface ruling made `TemplateValue` the closed enum `{ Int, Float, Bool, Str, Null }`. A `Bytes` hole was `error[TemplateHoleType]` (E0534) with no `help:` line. Every shipped driver binds a BLOB as its own kind (`sqlite3_bind_blob`, libpq binary parameters), and a variant added later breaks every exhaustive handler `match`. The question: add `Bytes(Bytes)` now, or keep five variants.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim.

#### Phase A — Independent proposals

##### Systems

**Systems (sys) proposal for xbsmyt: add `TemplateValue.Bytes(Bytes)` now**

**P1 (main proposal): add a sixth variant before any handler ships**
[code: six-variant enum; bind_template with `TemplateValue.Bytes(b) => sqlite_bind_blob(stmt, i, b)`; `fn save_avatar(uid: Int, img: Bytes) -> Void ! DB { db.execute("UPDATE users SET avatar = {img} WHERE id = {uid}") }`]

New rows for the hole table: `Bytes` maps to `TemplateValue.Bytes`, and `Option[Bytes]` maps to `Bytes` or `Null`. `List[U8]` stays E0534, with a help line: `{Bytes.from_list(xs)}`.

**What it compiles to.** In the runtime (`bootstrap/runtime_core.h`), `Bytes` is a `blink_bytes*`: one pointer to `{data, len, cap}`. The union already holds a `const char*`, so the value stays at 16 bytes and needs no box. The tag set grows from 5 to 6. The `match` stays one jump table. The cost of this variant is zero for every program that does not use it.

**What we lose without it.** Every driver we would ship binds a BLOB as its own kind: `sqlite3_bind_blob`, libpq binary-format params, MySQL `MYSQL_TYPE_BLOB`. Without the variant, a `{img}` hole gets E0534 today. The only repairs are `{img.to_hex()}`, which doubles the payload and makes the database do a hex decode, or `Raw`, which defeats the injection model. Both fixes cost more at runtime than the arm costs in the type.

**PLT's "meaningless arm" point is weaker than it looked:**
- **Shell:** POSIX `argv` and file names are byte strings, not UTF-8. `Bytes` is the correct type for a non-UTF-8 path argument. Here `Str` is the arm that is less exact.
- **HTML:** the handler rejects the arm in one line, the same as a Shell handler does with `Null`. The panel already accepted a context-free `Null` that means nothing to Shell. One more arm does not change the principle.

**Timing.** `TemplateValue` is not implemented in lib/std yet, and no handlers exist. Adding the variant now costs nothing. After 1.0, it breaks every third-party handler. This is the cheapest the change will ever be.

**One semantic rule the spec must add.** `Bytes` is mutable in place (`set_u32_le` and the rest of the `set_*` family). `Str` is immutable. §3b.5 already says that changes to `parts()` do not change the template. The same must hold for values: a handler that calls `b.set_u32_le(0, 0)` on the `Bytes` it gets from `values()` must not change what the next `values()` call returns. My spec text: "`values()` returns an independent copy of each `Bytes` value." That is one memcpy per BLOB per call. The driver copies the BLOB anyway with `SQLITE_TRANSIENT`, so the extra cost matters very little. An implementation may share storage until the first write, under the same non-normative note that `parts()` has. A caller that changes its own `img` between the literal and the handler call is ordinary aliasing. It cannot inject, because a `Bytes` value is always a parameter and never text.

**Related stdlib work (a chore, not spec):** add `sqlite3_bind_blob` with `SQLITE_TRANSIENT`, `Stmt.bind_bytes`, and `Row.get_bytes`. Without them, the variant has nothing behind it in-tree.

**Cross-language.** Rust's sqlx/rusqlite `Value` enums have a `Blob(Vec<u8>)` arm. Go's `database/sql` gives `[]byte` its own driver.Value kind. JDBC has `setBytes`. No mature driver value set leaves out BLOB.

**Keeps:** the closed, context-independent enum (Q3 structure), E0534 at typecheck, no `Raw` help line, no `Any` (8vcj2c), Display never invoked, `Bytes` as-is with no `Display` added.
**Amends:** the Q3 value set, from five variants to six. The reason is that the break-later cost was the only argument for deferring, and it grows every day after 1.0. The E0534 note line must also list `Bytes`.

**P2 (fallback if P1 loses): reserve the variant, gate the hole**
Put `Bytes(Bytes)` in the enum now, so handler matches are complete from day one. But keep a `{b: Bytes}` hole as E0534 until a later vote turns it on. Handlers write the arm once, and nothing breaks later. The cost is an arm that is unreachable for now. I prefer P1, because P2 costs the same but gives users nothing yet.


##### Web/Scripting

###### Proposal W1: add `Bytes(Bytes)` to `TemplateValue` now, before anyone writes a handler

**Rule.** `TemplateValue` gets a sixth variant [six-variant enum]. Two rows join the hole table. A `Bytes` hole maps to `.Bytes`. `Option[Bytes]` maps `Some(b)` to `.Bytes(b)` and `None` to `.Null`. `List[U8]` is still E0534, with one new help line: `{Bytes.from_list(xs)}`. `Raw[Bytes]` is still an error, because no text exists to fold into the parts.

[code: `fn save_avatar(user_id: Int, img: Bytes) -> Result[Int, DBError] ! DB.Write { db.execute("INSERT INTO avatars (user_id, data) VALUES ({user_id}, {img})") }` and the six-arm handler match]

**Why, from the web seat.** Ask how many Stack Overflow questions the current rule makes. Today a `{img}` hole gets E0534 with only a `note:` line. `Bytes` has no `Display`, so no help line applies. The user has only three ways out, and all are bad:
1. Hex- or base64-encode to a `Str`. This compiles, but it stores TEXT in a BLOB column and doubles the size. The data is wrong and nothing warns.
2. Use `{Raw(...)}`. That is an injection hole, the exact thing this feature exists to stop.
3. Leave the template API and look for a hand-written `bind_blob` that does not exist.

File uploads, image thumbnails, password hashes and session tokens are ordinary web backend work, not edge cases. A JS or Python developer expects the code above to work on the first try, and in every language they know, it does.

**PLT's objection: "Shell and HTML get an arm with no meaning."** I take it seriously, but it is weaker than it looks:
- `Null` already has this problem. An HTML handler gets `.Null` and must decide what it means. The panel accepted a context-free enum when it accepted `Null`.
- In Shell, `Bytes` *does* have a meaning. `execve` argv entries are byte strings, not UTF-8. A Shell handler can pass `.Bytes` as a raw argument, which is more correct than `.Str`.
- In HTML, the arm is one obvious line: `TemplateValue.Bytes(_) => return Err(HtmlError.BinaryValue)`. Or the handler can accept `b.to_str()` when the bytes are valid UTF-8. The decision is easy, so it does not invite a `_ =>` catch-all.
- The "a later break is loud, so it is fine" argument has a cost that grows over time. Today the cost is zero: `TemplateValue` is not even implemented, and the one in-tree handler still uses `type_tag`. Once there is an ecosystem, adding the variant becomes a breaking prelude release that hits every handler author at once. We are pre-1.0, so we should decide now, while it costs nothing.

**What it needs at the same time** (a stdlib chore, not spec work): an `sqlite3_bind_blob` FFI binding, `Stmt.bind_bytes`, and a `Row` getter that returns `Bytes`. Without the matching getter, users can write BLOBs but not read them back. That would be worse than the current state and would generate its own wave of SO questions.

**Cross-language.** Python `sqlite3` binds `bytes` as BLOB automatically, and psycopg sends it as `bytea`. Node's `better-sqlite3` and `pg` bind a `Buffer` as BLOB/bytea. In JDBC, `setBytes` sits beside `setString`. Every mainstream driver treats binary data as its own kind of parameter, and none makes the user encode it.

**Keeps:** a closed, compiler-known enum that is the same for every `C`; E0534 at typecheck; help lines that never suggest `Raw`; the `Option` rules; no `Any`; Display never invoked on a hole.
**Amends:** Q3 (from five variants to six), with a stated reason. The "four against" weighed a cost that is now zero against a break that comes later, and the dead-end E0534 for `Bytes` was not on the table at the vote.

###### Proposal W2 (fallback, only if W1 loses): document the dead end now
If the panel keeps five variants, the E0534 note for a `Bytes` hole must say outright: "binary values are not Template values yet; bind this parameter through the driver's binary-binding API." The stdlib must also ship `Stmt.bind_bytes`, so that sentence points to something real. Without it, users will hex-encode their way into corrupt schemas. I vote W1. W2 is the minimum.


##### PLT

**Position: add `Bytes(Bytes)` now. I change my Q3 vote.**

I voted against this in Q3 because the value enum is the same for every context, so Shell and HTML handlers would carry a `Bytes` arm with no meaning. That argument fails, and it fails on a precedent that already passed: `Null` has no meaning in Shell, and `Float` has little in HTML. A uniform sum over every context already carries arms that some contexts must reject or encode, so the objection does not single out `Bytes`. The fix I named then, a value set indexed by `C` (a type family or GADT), is still too much for v1. So the question is only which arms the uniform sum holds. On that, the type theory points one way.

**P1. `TemplateValue` gains `Bytes(Bytes)`, with a snapshot rule** [code: six-variant enum + `bind_one` six-arm match]

The hole table gains two rows: `Bytes` maps to `TemplateValue.Bytes`, and `Option[Bytes]` follows the existing Option row. `List[U8]` stays E0534, with the help line `{Bytes.from_list(xs)}`.

Why the typing argument favours it:
1. **This is the only lossless map.** `Str` has a UTF-8 invariant and `Bytes` does not, so no total injection from `Bytes` into `Str` exists. Without the variant, the only repairs are `to_hex` or base64. Those change the value's kind (a BLOB column gets TEXT), not just its form. The display-format Q3 ruling (5-0) rejected exactly this: a protocol that throws away the type the driver needs.
2. **Adding to a closed sum is not a conservative extension.** Each exhaustive eliminator breaks. Removing an arm breaks too, but only code that names it. So the costs are lopsided: an arm added now that turns out unused costs one line per handler, while an arm added later costs a breaking release of a prelude type. Today the count of affected handlers is zero third-party and one in-tree (not yet written). It will never again be this cheap.
3. **Soundness condition (new, required).** The existing five payloads are immutable values. `Bytes` is not: `set_*_le/be` write in place through `self`. If the coercion captures the caller's buffer, then `b.set_u32_le(0, x)` after the template is built changes the template. That breaks the normative rule "A `Template[C]` does not change after it is built". A handler that mutates `TemplateValue.Bytes(b)` from one `values()` call would also change what the next call returns. So the rule is: **the coercion snapshots each `Bytes` hole, and `values()` returns a `Bytes` that does not alias the template's copy.** Copy-on-write may implement this, under the same "no program can observe the sharing" clause that §3b.5 already has.
4. **Non-binary contexts:** a Shell handler passes the bytes as an argv element (POSIX argv is bytes, minus NUL). An HTML handler returns its own error, or encodes. That is the same burden `Null` already places on them. The spec's illustrative Shell and HTML handlers should show the arm, so no example teaches `_ =>`.

**Rejected: P2, mark the enum non-exhaustive (Rust `#[non_exhaustive]`).** This makes later variants non-breaking, but every handler then needs a wildcard arm. At an injection boundary, a wildcard silently routes an unknown kind into whatever fallback the author wrote. That gives up the decided "E0004 names each site" property, which is the reason the enum is closed.

**Timing and stdlib (conditions of P1, not separate features):** build the variant together with the first `TemplateValue` implementation, which does not exist yet, so the variant needs no 3-step migration. The same change must ship the `sqlite3_bind_blob` FFI binding, `Stmt.bind_bytes`, and a `Row` `Bytes` getter. Otherwise the spec has an arm that no in-tree driver can honour, and no round-trip test proves it.

**Cross-language:** JDBC has `setBytes` and psycopg has `bytea`; both treat binary as its own parameter kind. Python's DB-API separates `bytes` from `str` for the same reason as point 1. OCaml's Caqti has `octets` as a distinct field type.

**Keeps:** Q1 opaque, Q2 closed enum with `values()`, Q4 (no `Raw` help), one enum for every `C`, 8vcj2c, and Display never invoked on a hole.
**Amends:** Q3, from five variants to six, because the meaningless-arm objection does not hold given `Null`, and because no lossless repair exists without the variant. Also §3b.5 immutability: the text must state the `Bytes` snapshot rule explicitly, because this is the first payload that can change after the template is built.


##### DevOps

**Position: I change my Q3 vote. Add `Bytes(Bytes)` now, with three tooling rules attached.**

In Q3 I voted A. My reason was that a later `Bytes` variant gives one loud E0004 break, and I called that the right failure. That holds for a language feature with no users. Two facts change the sum:
1. **Today's diagnostic for `{blob}` gives no fix.** `Bytes` has no `Display`, so E0534 shows the `note:` line and nothing else. That breaks the §3.1 rule that a repair must exist. Users (and models) will find `{blob.to_hex()}`. It compiles and stays a parameter, but it stores a hex `Str` in a BLOB column. The column type changes with no warning, and none of our tools can see it. That bug is worse than a compile error.
2. **The break costs nothing now.** One handler exists (`db_sqlite.bl`), and it is not migrated yet. After 1.0, every third-party handler gets the break. E0004 lists each site, but a release still breaks.

**P1. The variant and the hole map** [code: six-variant enum + bind_template]
New hole-table rows: `Bytes` maps to `.Bytes`, and `Option[Bytes]` follows the existing Option row. `List[U8]` stays E0534 (it is a different type), and its help line is a repair that compiles: `` help: convert to `Bytes`: `{Bytes.from_list(xs)}` ``. The E0534 `note:` list adds "Bytes".

**P2. Shell/HTML handlers reject the arm by name, not with `_`**
plt's point was that the arm has no meaning for some contexts. My concern was the result: a `_ => ...` catch-all turns off exhaustiveness for every later variant. The fix is to make the explicit form the one people copy: [code: HTML match with `TemplateValue.Bytes(_) => return Err(HtmlError.BinaryHole)`]
The §3b.5 handler examples must show a named reject arm, never `_`. As an option, `blink lint` gets a warning for a `_` arm in a match on `TemplateValue`: "a wildcard hides variants added later; name each variant." The lint is cheap and covers one type. I would take it, but I will not block if min calls it YAGNI.
The cost: an HTML template with a `{blob}` hole fails at run time, not at compile time. `Null` already has the same cost in Shell. Per-context hole sets would fix both, but that reopens the context-independence decision, so I do not propose it.

**P3. The variant ships only with BLOB support**
A `Bytes` variant that no driver can bind is a lie in the type. One change must deliver the `sqlite3_bind_blob` FFI binding, `Stmt.bind_bytes`, a `Row` `Bytes` getter, and the `db_sqlite` migration to `TemplateValue`. If that work slips, the variant waits with it. It must still land before 1.0 and before any third-party handler exists.

**Cross-language.** sqlx and rusqlite carry a `Blob` in the value enum (`rusqlite::types::Value::Blob`). Go's `database/sql` takes `[]byte` as a distinct driver kind. JS tagged templates have no value types, so they give no precedent either way.

**Keeps:** opaque `Template[C]`, `parts()`/`values()`, the closed context-independent enum, E0534 at typecheck, no `Raw` help line, no `Any`, Display never invoked on a hole, the Option rules.
**Amends:** Q3 (A to B). The reason is that the dead-end E0534 and the silent `.to_hex()` fix it invites break §3.1's rule that a repair must exist, and the break only costs nothing before 1.0. §3b.5's example also changes to six arms.


##### AI/ML

Proposal from the AI/ML seat: **add `Bytes` now (B1)**. This changes my Q3 vote, from A to B.
[code: six-variant enum] New rows in the hole table: `Bytes` maps to `TemplateValue.Bytes`. `Option[Bytes]` maps to `.Bytes`, or to `.Null` for `None`. This is the existing `Option[T]` row, so it needs no new rule. `List[U8]` stays E0534. It gets one compiling help line, `{Bytes.from_list(xs)}`, and the E0534 note adds "Bytes" to the list of value types.
The DB handler gets one more arm: `TemplateValue.Bytes(b) => sqlite_bind_blob(stmt, i, b)`
A handler with no binary meaning names the arm and fails. It does not use `_`: [code: `render_arg` Shell match with `TemplateValue.Bytes(b) => b.to_str().map_err(fn(e) { ShellError.NotUtf8 })`, `TemplateValue.Null => Err(ShellError.NullArg)`]

**Why, from my seat**
1. **Without the variant, the wrong code compiles and nothing reports it.** That is the worst case for generated code. Today `{blob}` gets E0534 with only a `note:`, because `Bytes` has no Display and the brief notes the `{p.display()}` help does not apply. A model that wants to compile will try `{blob.to_hex()}`. That type-checks, binds TEXT into a BLOB column, and fails later at runtime. Equality on that column goes wrong and the stored size doubles. Every stage stays green while the data goes bad. A `Bytes` variant gives one obvious spelling, `{blob}`, so there is nothing to decide.
2. **plt's argument does not separate `Bytes` from `Null`.** It says Shell and HTML handlers would carry an arm with no meaning. `Null` has no meaning in a shell argv either, and we accepted it. Once one arm per handler may say "this context rejects this kind", a second arm adds no new kind of choice. `Bytes` is actually less meaningless than `Null` for Shell, because execve argv are byte strings. The fair cost is that each non-SQL handler makes one runtime decision. There are few handlers and many template users, so the per-user cost wins.
3. **Training data locks in the shape.** CLAUDE.md says this codebase is training data. If v1 ships five-arm handler matches in the spec, lib/std and tutorials, models learn five arms. Adding a sixth variant later makes all of that generated code fail E0004, and stale code keeps being generated long after the change. A loud break is fine for people, who read the E0004 list. For models it costs more, because the old form stays in the corpus. Today the cost is zero: no handlers exist, `bind_template` is not on `TemplateValue` yet, and we are pre-1.0.
4. **Token cost:** one line per handler, nothing at the use site. The rule stays one sentence: a hole is a scalar, `Str`, `Bytes`, or `Option` of one of these.

**The catch-all risk** (my Phase B worry). Make the spec's Shell/HTML sample handlers name every arm. Add one sentence to §3b.5: "A handler names each variant; a `_` arm hides the next language change from E0004." No lint for now (YAGNI).

**Other languages** — Go `database/sql/driver.Value` is a closed set: int64, float64, bool, []byte, string, time.Time, nil. Python sqlite3 binds None, int, float, str and bytes, which is the B1 set exactly. JDBC has `setBytes`. Every mainstream driver interface puts binary in its closed set. A model trained on any of them expects a byte variant to exist.

**Keeps:** the opaque `Template[C]`, `values()`, a closed prelude enum that is the same for every `C`, E0534 at typecheck with help lines that keep the value a parameter and never offer `Raw`, the exclusions (Char, U64, `Option[Option[T]]`), "Display never invoked", and no `Any`.
**Amends:** Q3 (4-2, variant set). Reason: the tie-breaking argument applies to `Null` just as much, and the later-break cost falls hardest on generated code. Note that `Bytes` is Tier 1, not prelude. It is still compiler-known (§10.6), so a prelude enum may carry it.

**Related work, filed as chores, not part of this vote:** an FFI binding for `sqlite3_bind_blob`, `Stmt.bind_bytes`, and `Row.get_bytes`. The variant must not wait on them, but the first `bind_template` port to `TemplateValue` should include the arm.

**Fallback (B2), if the panel keeps A:** the E0534 note for a `Bytes` hole must say: "Bytes has no Template value; bind it with the driver's binary API." This tells the model the hole is not supported, so it stops trying conversions. Under A, nothing else blocks the `to_hex()` path that compiles and stores the wrong kind. That is why I rank B2 well below B1.


##### Minimalism

I'm changing my Q3 vote, as Minimalism. My recommendation is to **add `Bytes` now, with one admission rule that closes the enum to all further variants.**

###### Why I'm changing my vote
My Q3 "no" was YAGNI: no spec line and no in-tree handler needed `Bytes`. YAGNI fits when we don't know if a feature will be needed. Here we do know.
1. **The language can't express a binary parameter today.** `Str` must be valid UTF-8 (§3, line 100). So an arbitrary blob has no lossless path into any of the five variants: base64 or hex in a `Str` silently changes the column's stored kind from BLOB to TEXT; `Raw` is an injection bypass, and it is still UTF-8. E0534 for a `Bytes` hole has no help line. The user hits a dead end, and both workarounds are the bad outcomes the Q3 concern lines predicted. Filling a real gap is the one kind of addition I vote for.
2. **Adding it costs nothing now, and costs more every month we wait.** `TemplateValue` isn't implemented yet: `bind_template` still uses `type_tag`/`get_*`. Today the variant breaks zero handlers. After 1.0 it breaks every third-party handler at once.
3. **plt's Shell/HTML argument is already conceded.** `Null` has no meaning in Shell or HTML either, and we accepted it. Once one arm with no meaning is in, a second one doesn't change the design. Also, the only real consumer of `Template[C]` is `Template[DB]`, and every DB binds BLOBs.

###### Proposal M1: `Bytes` variant plus an admission rule that closes the enum
[code: six-variant enum + bind_template]
**Hole mapping:** `Bytes` maps to `.Bytes`, and `Option[Bytes]` follows the existing Option row. `List[U8]` stays E0534, with the help line "convert first: `Bytes` from the list". The exact constructor name needs checking against §10.6.

**Admission rule (normative).** This is the part I care about most. A new `TemplateValue` variant is admitted only if both are true:
- (a) A value of that kind can't be sent losslessly as an existing variant.
- (b) A driver we ship binds it as its own kind.
`Bytes` passes both, because of the UTF-8 invariant and `sqlite3_bind_blob`. `Instant`, `Uuid`, `Decimal` and `Json` all fail (a): they convert to `Int` or `Str` with a help line. That gives a principled "no" to the requests that will follow, so the enum can't grow by small steps the way C++ did.

**Timing.** The variant lands in the same slice as the `TemplateValue` implementation, with three driver parts: the `sqlite3_bind_blob` FFI binding; a `Stmt` binder; a `Row` getter that returns `Bytes`. A variant with no driver to bind it is unused surface, so I'd make the driver work a condition of the change.

**Non-DB handlers.** A handler in a context where bytes have no meaning rejects the arm explicitly, for example by returning an error code. It must never use `_ =>`. Tell handler authors this in §3b.5, because a catch-all turns off E0004 for every later variant. That was aiml's real concern in Q3.

**Keeps:** the closed enum that is the same for every context; the opaque `Template[C]`; E0534 at typecheck; no help line ever offers `Raw`; 8vcj2c (no `Any`); Display is never invoked on a hole.
**Amends:** Q3, from the five-variant enum to six. Reason: the UTF-8 invariant makes `Bytes` the one kind no existing variant can carry, and the cost of adding it is zero today. §3b.5, to add the admission rule and the "no catch-all" note.

**Cross-language:** Go's `database/sql` closed its `driver.Value` set early, as int64, float64, bool, `[]byte`, string and time.Time. `[]byte` was in it from the start, and it has had no variant churn since. Python DB-API and JDBC also treat bytes as a first-class parameter kind.

###### Proposal M2 (fallback): reject the variant, ship a positional binder
M2 keeps the five variants and adds a stdlib `stmt.bind_bytes(i, b)` for BLOBs outside templates. The language surface stays the same. The cost: any query that has one BLOB column must drop the template path entirely. That leaves two parameter styles for one job, which is more total surface than one enum arm, and E0534 still has a dead end. I list it only for completeness, and I vote against it.

**I vote M1.**


#### Phase A.5 — Mechanical dedupe and codebase facts

##### Deduped option space (mechanical grouping)

- **Option A — add `Bytes(Bytes)` now.** Proposed by sys (P1), web (W1), plt (P1), devops (P1), aiml (B1), min (M1). Shared content: six-variant enum `{ Int, Float, Bool, Str, Bytes, Null }`; a `Bytes` hole maps to `.Bytes`; `Option[Bytes]` follows the existing Option row; `List[U8]` stays E0534 with help `{Bytes.from_list(xs)}`; the E0534 `note:` lists `Bytes`.
- **Option R — reserve the variant, gate the hole** (sys P2, fallback): `Bytes(Bytes)` in the enum now, `{b: Bytes}` hole stays E0534 until a later vote.
- **Option N — keep five variants, document the dead end** (web W2, aiml B2, fallbacks): E0534 note for a `Bytes` hole points to the driver's binary-binding API; stdlib ships `Stmt.bind_bytes`.
- **Option P — keep five variants, positional binder only** (min M2, fallback, proposer votes against).

##### Variations inside Option A that need debate

- **V1 — Mutability of a `Bytes` payload.** sys: "`values()` returns an independent copy of each `Bytes` value"; "A caller that changes its own `img` between the literal and the handler call is ordinary aliasing." plt: "the coercion snapshots each `Bytes` hole, and `values()` returns a `Bytes` that does not alias the template's copy." Others did not address it.
- **V2 — Admission rule for future variants** (min only): a new variant is admitted only if (a) a value of that kind can't be sent losslessly as an existing variant, and (b) a driver we ship binds it as its own kind.
- **V3 — Catch-all guidance.** Named reject arms in every §3b.5 example (devops, aiml, min, plt, web's example). A normative/§3b.5 sentence telling handlers not to use `_` (aiml, min). An optional `blink lint` warning for `_` in a match on `TemplateValue` (devops: "I would take it, but I will not block"; aiml: "No lint for now (YAGNI)").
- **V4 — Coupling to driver work** (`sqlite3_bind_blob`, `Stmt.bind_bytes`, `Row` Bytes getter, db_sqlite migration). devops: "If that work slips, the variant waits with it." min: "I'd make the driver work a condition of the change." plt: "conditions of P1." web: "What it needs at the same time." aiml: "The variant must not wait on them." sys: "a chore, not spec."
- **V5 — `Raw[Bytes]`.** web: "`Raw[Bytes]` is still an error, because no text exists to fold into the parts." Others did not address it.

##### Codebase facts (moderator-supplied, facts only)

- F1 (V1): sections/03_types.md:2600-2608, §3.6 *Shared cells*: "The shared cells are: `List`, `Map` and `Set`; `StringBuilder`; a closure or handler that captured a `let mut` binding (§2.8, §4.7). This list is the only one; other sections refer to it. Only a shared cell can change through a second name. A value of any other type, at any depth, cannot. This holds for every copy: bind, pass, return and `clone()`." `Bytes` is not on that list. The Bytes method table (03_types.md:787-792) describes `set_*` as "in-place, bounds vs `len`".
- F2 (V5): §3b.5 says `Raw[T]` "concatenates the wrapped value into the adjacent literal segment"; the spec does not state which `T` a `Raw[T]` may wrap in a template. `parts()` is `List[Str]`.
- F3: aiml's note that `Bytes` is "Tier 1, not prelude" — §3b.5 prelude table lists `Template[C]`, `Raw[T]`, `TemplateValue` as prelude; `Bytes` is "compiler-known (§10.6)".

#### Phase B — Round 1

Every panelist sent `STABLE: ready to vote` after round 1. Position changes: sys and plt withdrew their Template-specific snapshot rules (V1); devops withdrew the `_` lint (V3); devops and min withdrew the wait-for-driver timing (V4).

##### Systems

sys, Phase B round 1: I back Option A and drop my P2.

**1. Option A.** All six of us proposed Option A, so I drop my fallback, P2. P2 has the same cost as A (the arm is in every handler) and gives users nothing. N and P leave BLOB users with only `to_hex()` or `Raw`. That costs more at runtime and breaks the injection model.

**V1. Amend, and I retract part of my Phase A text.** F1 settles this one. `Bytes` is not a shared cell (§3.6). So no value of type `Bytes` can change through a second name, through any bind, pass, return or `clone()`. That covers both the coercion and `values()`. My claim of "ordinary aliasing" for a caller that changes `img` after the literal was wrong: by §3.6, that change cannot be seen in the template. plt's snapshot rule is correct, but the spec already implies it.

So §3b.5 should not add a template-only rule. It should add one sentence that points to the existing one: "A `Bytes` value is not a shared cell (§3.6), so a change to the caller's buffer, or to a `Bytes` from `values()`, does not change the template."

From my seat, the real question is how the compiler meets §3.6 when `set_*` writes "in-place": copy-on-write or copy-on-bind. That is a codegen question for every `Bytes`, not just templates. If gen1 aliases today, it is a bug to file separately. It is not a reason to put an implementation rule in §3b.5.

**V2. Agree** with min's admission rule. It turns "closed" from a hope into a test, and it lets future proposals (`Instant`, `Decimal`) be rejected in one line. I would not add a layout condition (such as "the payload fits the union without a box"). That is an implementation detail, and it does not belong in the spec.

**V3. Agree** with named reject arms in every §3b.5 example, plus aiml's one normative sentence. The lint can wait (YAGNI): E0004 does the work once the examples teach the right form. I will not block devops on it.

**V4. Agree** with plt, min and web, but I amend my "a chore, not spec" framing. The spec ruling stands on its own. The *implementation* must ship as one change: the variant, `sqlite3_bind_blob` (`SQLITE_TRANSIENT`), `Stmt.bind_bytes`, a `Row` `Bytes` getter, and a round-trip test. Without that test, nothing proves the arm reaches the driver as a BLOB rather than as text. It costs nothing to do it together, because `TemplateValue` is not implemented yet.

**V5. Agree** with web: `Raw[Bytes]` is an error. `parts()` is `List[Str]`, and `Str` has a UTF-8 invariant that `Bytes` does not. Folding bytes into a part would break that invariant or need a hidden validation that can fail. The help line should be `{b}` (send it as a parameter). Per F2, the spec should also say which types `Raw[T]` may wrap. That is a separate gap, so it should get its own ticket and not grow this one.

STABLE: ready to vote


##### Web/Scripting

Web, Phase B round 1: Option A. All six panelists proposed it, so R, N and P are fallbacks that no one needs now. I drop W2.

V1, mutability: I agree with the result, but amend the wording. F1 already settles it. `Bytes` is not on the §3.6 shared-cell list, so "only a shared cell can change through a second name" already applies. A `set_u32_le` on the caller's `img` or on a handler's copy cannot reach the template. The spec should not add a new "snapshot" rule, because that suggests `Bytes` aliases, and users will then ask on Stack Overflow whether `Str` holes need it too. Instead, add one line to the §3b.5 immutability paragraph: "A `Bytes` value is not a shared cell (§3.6), so a change to the caller's buffer or to a buffer from `values()` does not change the template." It gives the same guarantee as sys and plt want, with one rule for the language instead of two.

V2, admission rule: I agree. It puts a reason in the spec for the next "add Instant/Decimal/UUID?" question. Without it, that question gets a new debate each time. I also accept min's two tests as written.

V3, catch-all: I agree with named arms in every §3b.5 example, plus aiml's one sentence: "A handler names each variant; a `_` arm hides the next language change from E0004." Most people copy the examples, so the examples matter more than any lint. No lint for now. I would vote for one later if real handlers turn out to use `_`.

V4, coupling: I side with devops, plt and min. The spec text lands now. The implementation slice that first builds `TemplateValue` must also ship `sqlite3_bind_blob`, `Stmt.bind_bytes`, a `Row` getter that returns `Bytes`, and a round-trip test. If users can write a BLOB but not read it back, that is worse than E0534. aiml's worry is the variant getting stuck. The fix for that is to keep the driver parts small, which they are: three functions.

V5, `Raw[Bytes]`: I keep my position and want it normative, because F2 shows the spec is silent. A `Raw[Bytes]` hole in a `Template[C]` is E0534. The help line `send it as a value: {b}` is a repair that compiles, keeps the value a parameter and never suggests `Raw`. That fits §3b.5's help-line rule exactly. Which other `T` a `Raw[T]` may wrap is a separate gap. I would file it as its own ticket and not widen this vote.

STABLE: ready to vote


##### PLT

plt Phase B round 1: Option A, with V1 revised by F1.

1. Option A. I reject R: a variant that no hole can produce gives every handler an arm it can never reach, and the add-later break still comes when the gate lifts. That is the cost of both paths with the benefit of neither. N and P keep the lossy dead end that point 1 of my Phase A text rejects: no total injection from Bytes into Str exists.

2. V1, revised. F1 settles this, and I withdraw my snapshot rule as a separate rule. §3.6 says only shared cells can change through a second name, and Bytes is not a shared cell. It also says "A method cannot change its caller's value through `self`." So Bytes already has value semantics, and the Template immutability rule already covers a Bytes payload with no new text. Both sys's "ordinary aliasing" sentence and my snapshot clause contradict §3.6, so neither belongs in §3b.5. At most, add one non-normative cross-reference to §3.6. The `set_*` row text "in-place" conflicts with §3.6 on its own. That is a separate spec defect in the Bytes table, to file as its own ticket and not to decide here.

V2: agree. Criterion (a) is the typing argument in its general form: admit a kind only if no lossless map into an existing variant exists. Criterion (b) keeps the enum tied to real drivers. Together they make the enum closed by rule, not by habit.

V3: named reject arms in every §3b.5 example, plus aiml's one sentence. No lint. A lint for wildcards over one prelude type is ad hoc. If wildcards on closed enums need a warning, that is a general rule for every closed enum, with its own ticket.

V4: amend my Phase A text. A spec rule must not wait on a stdlib schedule (the spec is the blueprint). The variant enters the spec now. The driver work is a chore, and the first `bind_template` port to TemplateValue must include a real Bytes arm, never a stub. I side with aiml and sys on timing, and with devops and min on the point that no shipped handler may bind it falsely.

V5: agree with web. `parts()` is `List[Str]`, and Bytes has no total map to Str, so `Raw[Bytes]` cannot fold. Which `T` a `Raw[T]` may wrap in general (F2) is a separate gap; do not decide it here.

STABLE: ready to vote


##### DevOps

devops, Phase B round 1: Option A, and I am ready to vote.

**1. Option A.** R is the worst choice for tooling. Every handler must write a `.Bytes` arm that can never run, while `{b}` still ends at an E0534 that offers no fix. N and P keep that dead end. A note that sends users to a driver API helps, but `{b.to_hex()}` still compiles and quietly stores text in a BLOB column. Only A takes that trap away.

**2. V1 (mutability): agree with the outcome, amend the wording.** F1 settles it already: `Bytes` is not on the §3.6 shared-cell list, so no change can be seen through a second name. sys's "independent copy" and plt's "snapshot" both write the implementation into the spec. §3b.5 should instead say one sentence: "`Bytes` values in a template follow §3.6: a later write to the caller's buffer, or to a `Bytes` from `values()`, does not change the template." How it is done (copy, COW) stays a codegen chore. F1 also shows a separate spec conflict: `set_*` writes "in-place" through `self` on a type that is not a shared cell. That needs its own friction ticket, not this vote.

**V2 (admission rule): agree.** It gives docs and the E0534 `note:` a stated reason to cite when someone asks for `Char` or `Decimal`. A rule that answers the next feature request is cheap.

**V3 (catch-all): agree with named arms in every §3b.5 example plus aiml's sentence ("a `_` arm hides the next language change from E0004"). I withdraw the lint.** The sentence and the examples are the parts people and models copy. If third-party handlers later show `_` in the wild, a lint is a later non-breaking addition.

**V4 (coupling): amend my own position.** The spec ruling should not wait on stdlib work; aiml is right. The one rule I keep is an ordering rule for the implementation: no in-tree handler ships a `.Bytes` arm that panics or reports "unsupported". The variant, `sqlite3_bind_blob`, `Stmt.bind_bytes`, `Row.get_bytes` and the `bind_template` port land in one change (or the bindings land first). Writing BLOBs with no way to read them back is a bug report factory (web).

**V5 (`Raw[Bytes]`): agree it is an error. Add the diagnostic.** F2 shows the spec does not say which `T` `Raw[T]` may wrap. Say it: `Raw[T]` requires `T: Display`, which matches what it does (it folds text into the parts). Then `{Raw(b)}` on `Bytes` gets a help line that is a real fix and is also the safe one:

    error[TemplateHoleType]: `Raw[Bytes]` has no text to fold into the query
      = help: send it as a parameter: `{b}`

The compiler then never tells a user to swap a safe path for an unsafe one, and here it does the reverse.

STABLE: ready to vote


##### AI/ML

aiml Phase B round 1: Option A, ranked A > R > N > P. STABLE.

**Options.** I back A, as six panelists already do. My second choice is R, then N, then P.
- R stops the later break, but users still hit the dead end. It also puts an arm in the spec that is "unreachable for now", and a model cannot reason about that state.
- N keeps the `to_hex()` path that compiles and stores the wrong kind.
- P gives two ways to bind a parameter, which means two decision points for one task.

**V1, Bytes mutability: amend.** No new rule is needed, because F1 already settles this. §3.6 says the shared-cell list "is the only one", and `Bytes` is not on it. "Only a shared cell can change through a second name. A value of any other type, at any depth, cannot." So a `Bytes` hole is already a snapshot, and a `set_*` call on the `Bytes` from `values()` already cannot change the template. If §3b.5 adds its own copy rule, the spec has two sources of truth, and a model that reads one may think the other is an exception. I propose one non-normative sentence in §3b.5: "`Bytes` is not a shared cell (§3.6), so a `Bytes` value cannot change after the template is built." If the runtime passes `blink_bytes*` without copy-on-write, that is a conformance bug in codegen and gets a ticket. It is not new spec text.

**V2, admission rule: agree.** It is a clear test, and it gives one answer to future requests for `Instant`, `Uuid` and `Json`. That leaves fewer open questions for people and models. Put it in the §3b.5 "Why" paragraph and in decisions/. It governs how the language changes, not how programs behave.

**V3, catch-all guidance: keep my Phase A position.** Every §3b.5 example handler names each arm, and §3b.5 gets one sentence saying not to use `_`. Models copy examples more than they obey rules, so the examples do most of the work. A lint stays optional; I do not block it, but I do not ask for it.

**V4, driver coupling: I revise to meet plt, devops and min.** The spec ruling lands now. The compiler and stdlib implementation lands as one slice: the variant, the `sqlite3_bind_blob` FFI binding, `Stmt.bind_bytes`, `Row.get_bytes`, and a round-trip test. web's point decides this for me. A variant that can write a BLOB but not read it back makes models generate write-only code. The spec text does not wait for the slice, but the compiler does not ship the variant without it.

**V5, `Raw[Bytes]`: agree, it is an error.** No text exists to fold into the parts, and `parts()` is `List[Str]`. Its `help:` line now has a repair that compiles: "remove `Raw`: `{b}` sends the bytes as a parameter". That is the best case for a model: the wrong spelling points directly to the correct one. F2 says no rule states which `T` a `Raw[T]` may wrap. That is a separate gap, so I would file it as a friction ticket and not grow this ruling.

STABLE: ready to vote


##### Minimalism

min, Phase B round 1: Option A, add Bytes now. Of the fallbacks, I reject R, N and P.

**1. Option A.** All six of us arrived at A independently. R is the worst of the fallbacks. It gives a variant that no hole can make, so handlers carry an arm that never fires, and a later vote must still open the hole. That is all the surface cost of A with none of the use. N and P leave E0534 as a dead end and give two ways to bind parameters for one job.

V1, mutability: I amend this. No new rule is needed, only a cross-reference. F1 settles it. §3.6 says only shared cells can change through a second name, the shared-cell list is the only one, and Bytes is not on it. So value semantics already gives the snapshot that sys and plt want. A Bytes copy taken by the literal, or returned by `values()`, cannot see a later `set_*` through another name, and the rule holds "for every copy". If we write a Template-only snapshot rule, we state one rule in two places, and someone will later read the second as an exception. Put one non-normative sentence in §3b.5: "A `Bytes` value follows §3.6: it is not a shared cell, so a later write through another name cannot change the template." If the current implementation aliases a Bytes buffer through `set_*`, that is a compiler bug against §3.6 and needs its own bug ticket. It is not a Template rule.

V2, admission rule: keep it. It is what turns the "add one variant" argument into a closed door. Without it, Instant, Uuid, Decimal and Json each come back with the same "breaks later, so add now" argument.

V3, catch-all: I agree with the named reject arm in every §3b.5 example, plus one sentence: "A handler names each variant; a `_` arm hides the next variant from E0004." No lint. The admission rule makes new variants rare, and the examples carry the pattern. If a lint is ever added, it should be general (a wildcard over a closed prelude enum), not keyed to one type.

V4, coupling: I amend my own position. The spec vote does not wait on driver work. The implementation slice that first ports `bind_template` to TemplateValue must ship the Bytes arm, `sqlite3_bind_blob` (SQLITE_TRANSIENT), `Stmt.bind_bytes` and a `Row` Bytes getter, with a round-trip test. That is devops/plt/web's "same change", without blocking the spec. It is not aiml's version, which lets the getter slip. A write-only BLOB path is worse than none.

V5, `Raw[Bytes]`: I agree it is an error, because `parts()` is `List[Str]` and Bytes has no text. F2 shows that the general question of which `T` a `Raw[T]` may wrap is unspecified. That is a separate gap, and it belongs in its own ticket, not in this ruling. Here, say only that `Raw[Bytes]` is rejected.

STABLE: ready to vote


#### Phase C — Final vote

- **Q1: The variant** (6-0, A)
  - **Systems:** A — In the union, a `Bytes` payload is one `blink_bytes*`, so the value stays at 16 bytes with no box, and the jump-table `match` is unchanged. Every driver we would ship binds a BLOB as its own kind. Without the variant, the only repairs are `to_hex()`, which doubles the payload and adds a decode at the database, or `Raw`, which breaks the injection model. Adding it now costs nothing, because no handler exists yet. *Concern:* Shell and HTML handlers may treat the arm as dead code and write it poorly, for example as a panic in place of a returned error.
  - **Web/Scripting:** A — Storing uploads, hashes and tokens is normal web backend work, and every driver a JS or Python developer knows binds binary data as its own kind of parameter. A gives `{img}` a correct path. It also removes the two traps, `to_hex()` into a BLOB column and `Raw`. The cost is zero today because `TemplateValue` is not built yet. *Concern:* HTML and Shell example handlers that show the `.Bytes` arm badly will teach a wrong reject pattern, and people will copy it.
  - **PLT:** A — `Bytes` is the one kind that has no lossless map into an existing variant, because `Str` has a UTF-8 invariant and `Bytes` does not. Adding an arm to a closed sum breaks every exhaustive match, and today that break costs nothing. The "meaningless arm" objection does not hold, because `Null` already passed with the same property. *Concern:* Shell and HTML handlers will each invent their own reject error, so the meaning of a rejected kind can differ from one context to the next.
  - **DevOps:** A — Today a `{b: Bytes}` hole gets an E0534 with no help line, and the one fix users find, `{b.to_hex()}`, compiles and quietly stores text in a BLOB column. A is the only option that takes away both the dead end and the silent trap. Pre-1.0 with zero third-party handlers, the E0004 break costs nothing. *Concern:* until the db_sqlite port lands, the spec shows a sixth arm that no in-tree handler has, and users who read the spec before the stdlib will hit a mismatch.
  - **AI/ML:** A — Without the variant, `{blob.to_hex()}` compiles and stores TEXT in a BLOB column. Models will find that path, and nothing reports it. With the variant, the one obvious spelling, `{blob}`, is also the correct one. Adding it before any handler exists also keeps the five-arm shape out of the spec, stdlib and training data, so stale generated code never fails E0004. *Concern:* If the driver slice slips, the spec shows a six-arm handler that no in-tree code demonstrates, and models then have no example to copy.
  - **Minimalism:** A — The UTF-8 invariant on Str means arbitrary bytes have no lossless path through any existing variant. So this fills a real gap in what the language can express, which is the one kind of addition I vote for. The cost is lowest now: TemplateValue is not yet implemented, so zero handlers break. *Concern:* Users may read the six-variant enum as an open set and file a request for each new kind, unless Q3 closes the door.

- **Q2: Mutability of a `Bytes` payload** (6-0, X)
  - **Systems:** X — §3.6 already makes `Bytes` a value and not a shared cell, so a rule only for templates would duplicate it and could drift from it. The actual work is in codegen: `set_*` writes "in-place" while the type has value semantics. So the compiler must copy on write or copy on bind for every `Bytes`, not only for template holes. *Concern:* If gen1 shares the buffer today, the sentence in §3b.5 will promise something the compiler does not do. So we must check this before the implementation slice lands.
  - **Web/Scripting:** X — §3.6 already gives the guarantee, so a second rule just for Template would make users ask whether `Str` or `List` holes have their own rules too. One sentence that points to §3.6 answers the question where the reader meets it. *Concern:* If gen1 aliases `Bytes` through `set_*` today, the sentence promises something the compiler does not do. That needs its own bug ticket.
  - **PLT:** X — §3.6 already gives `Bytes` value semantics: it is not a shared cell, and a method cannot change its caller's value through `self`. A Template-specific copy rule would restate a general rule in one place and suggest that the general rule does not hold elsewhere. *Concern:* the `set_*` rows say "in-place", which contradicts §3.6. If that defect is resolved toward mutation, X stops holding, so the Bytes table ticket must be filed and settled first.
  - **DevOps:** X — §3.6 already makes the guarantee, because `Bytes` is not a shared cell. A second Template-specific copy rule would state the same thing twice, and the two texts could drift apart. How it is done (copy or COW) is a codegen choice, not spec text. *Concern:* the `set_*` "in-place through `self`" wording in the Bytes table conflicts with §3.6 and needs its own friction ticket, or readers will doubt the pointer sentence.
  - **AI/ML:** X — §3.6 already says the shared-cell list "is the only one", and `Bytes` is not on it. A second, Template-specific copy rule gives the spec two sources of truth, and a model that reads only one of them may treat the other as an exception. A sentence that points to §3.6 teaches the general rule once. *Concern:* If the runtime passes `blink_bytes*` without copy-on-write, the gap shows only at runtime, so we need a conformance test, not only the spec sentence.
  - **Minimalism:** X — §3.6 already gives Bytes value semantics, and the shared-cell list is the only such list. A Template-specific snapshot rule would state the same rule in a second place, and a reader would take it as an exception. One pointer sentence is the smallest correct text. *Concern:* If the current runtime aliases a Bytes buffer through set_*, the pointer sentence is true in the spec and false in the binary. That needs its own bug ticket and test.

- **Q3: Admission rule for future variants** (6-0, AR-W)
  - **Systems:** AR-W — The rule controls how the language changes, not how a program behaves. No program and no diagnostic can observe it, so it belongs in the rationale and in decisions/, not in normative text. Its value is that a later panel can reject `Instant` or `Decimal` in one line. *Concern:* Rationale text does not bind as strongly as normative text, so a later panel could ignore it more easily.
  - **Web/Scripting:** AR-W — The rule tells the panel when to change the language. It does not change what any program does, so a handler author never needs it to write correct code. Rationale text in §3b.5's "Why" and in decisions/ still gives the next "add Decimal?" request a one-line answer, without adding normative text that users will read as behaviour. *Concern:* As rationale only, a later panel could quietly ignore it, so the decision record must state it plainly.
  - **PLT:** AR-W — the rule says how the language may change, not what a program does. No program can observe it, and no compiler can check it, so it is not a typing rule and does not belong in normative text. In the rationale and decisions/, it still binds future panels, which is its real audience. *Concern:* as text outside the normative spec, a future panel may ignore it under pressure and add a variant such as `Instant` that fails criterion (a).
  - **DevOps:** AR-W — the rule governs how the panel changes the language. It does not govern what a program does, so it belongs in the rationale and decisions/. There it still gives docs a reason to cite when someone asks for `Char` or `Decimal`. *Concern:* rationale text is easy to overlook, so a later panel may admit a variant without checking it.
  - **AI/ML:** AR-W — The test is useful, because it gives one answer to future requests for `Instant`, `Uuid` and `Json`. It governs how the language changes, though, not what a program does. Normative text about the spec's own evolution is a rule no compiler checks and no program can break. In the "Why" paragraph and in decisions/, it does the same job without that confusion. *Concern:* If it is adopted as normative text, readers may expect a diagnostic or a conformance test for a rule that has neither.
  - **Minimalism:** AR-W — I proposed this rule, and aiml is right about where it goes. It constrains how the language changes, not how any program behaves, so it belongs in the "Why" rationale and decisions/, not in normative text. Normative spec text that no program can test is surface clutter. The rule binds the panel just as well from decisions/. *Concern:* Rationale text has less weight, so a future panel could skip the two-part test without amending anything. The decision record should say that a later variant vote must apply it.

- **Q4: Catch-all guidance** (6-0, E)
  - **Systems:** E — E0004 is the mechanism. The examples are what users and models copy, so making them name every arm gives most of the benefit at no cost. A lint for one type is extra surface that the E0004 rule plus correct examples already covers. *Concern:* Third-party authors who never read §3b.5 may still write `_ =>`, and nothing will warn them.
  - **Web/Scripting:** E — People copy examples, not lints. Named arms in every §3b.5 handler, plus one sentence, teach the right form where people look. A lint can come later, and adding it then breaks nothing. *Concern:* Third-party handler authors who never read §3b.5 will still write `_ =>`, and nothing will tell them.
  - **PLT:** E — the closed enum exists so that E0004 lists every site when the enum changes, and examples are what users and models copy. A lint against `_` on one prelude type is an ad hoc rule. If wildcards on closed enums need a warning, that is a general rule for every closed enum, with its own ticket. *Concern:* generated handlers will still reach for `_`, and nothing mechanical will catch them.
  - **DevOps:** E — the examples and the one sentence are what people and models copy, and those are the parts that matter. A lint can come later as a non-breaking addition if `_` arms show up in real handlers. I withdrew E+L in round 1. *Concern:* generated handlers may still write `_ =>` from habit in other languages, and nothing flags it.
  - **AI/ML:** E — Models copy examples more than they obey rules, so example handlers that name each arm do most of the work, and the one sentence states the reason. A lint keyed to one type is extra surface. The admission rule keeps new variants rare. YAGNI. *Concern:* Handler code outside the spec (blog posts, third-party crates) may still teach `_ =>`, and without a lint nothing catches it.
  - **Minimalism:** E — Named arms in the examples plus one sentence give the pattern people copy, and that costs no tooling. With the admission rule, new variants are rare, so a lint for one type is not worth its surface. If a wildcard lint is ever added, it should cover every closed prelude enum. *Concern:* Third-party handlers copied from code outside the spec will still use `_`, and E0004 goes quiet for them on the next variant.

- **Q5: Timing and driver coupling** (6-0, T)
  - **Systems:** T — The spec decision is independent of the stdlib. But the implementation must prove the arm reaches `sqlite3_bind_blob` as a BLOB and not as text, so the round-trip test is required. Doing it together costs nothing, because `TemplateValue` is not implemented yet. *Concern:* The slice may bind with `SQLITE_STATIC` to avoid a copy and depend on how long the GC keeps the buffer alive. It should use `SQLITE_TRANSIENT`.
  - **Web/Scripting:** T — A write-only BLOB path is worse than E0534, so the getter and the binder must ship with the port. The spec vote does not need to wait for that, because it is three small functions and a test. *Concern:* If the port slice slips, the spec promises `.Bytes` with nothing in-tree behind it. The ticket for the port should block the next release, not sit in the backlog.
  - **PLT:** T — the spec is the blueprint, and a rule should not wait on a stdlib schedule. The implementation condition (no stub arm, and a round-trip test) is the right place to prevent a `Bytes` arm that the in-tree driver cannot bind. *Concern:* if the port slips, the spec documents a variant that no shipped driver binds, and early users find a hole that type-checks but has no in-tree driver behind it.
  - **DevOps:** T — the spec ruling does not need to wait on stdlib work. The rule that matters to users is that no in-tree handler ships a `.Bytes` arm that panics, and that writes and reads land together with a round-trip test. T makes both of those conditions of the implementation slice. *Concern:* the bindings could slip and leave the TemplateValue port blocked, which keeps the old `type_tag` surface alive longer.
  - **AI/ML:** T — The ruling must not wait on stdlib scheduling, but no in-tree handler may ship a stub `.Bytes` arm, and no driver may write BLOBs that cannot be read back. Code that can only write is exactly what models then generate. One slice with a round-trip test proves the arm end to end. *Concern:* The slice is large (FFI, binder, getter, migration, test), so it can stall, and someone may then add the variant with a panicking arm "for now".
  - **Minimalism:** T — The spec ruling costs nothing to land now. The real risk is a write-only BLOB path, and T prevents it by making the getter and the round-trip test part of the same implementation change. No stub arms means no variant that is false in the type. *Concern:* The bind_template port may be split up under time pressure, and the Row getter could slip out of it.

- **Q6: `Raw[Bytes]`** (6-0, RB)
  - **Systems:** RB — `parts()` is `List[Str]`, and `Str` must be valid UTF-8. Folding bytes into a part would break that rule, or need a hidden validation that can fail. The general rule for which types `Raw[T]` may wrap needs its own ticket, so it does not get decided as a side effect here. *Concern:* Until that ticket is decided, other `Raw[T]` cases stay unspecified, and the compiler may pick an answer by accident.
  - **Web/Scripting:** RB — `{Raw(b)}` on `Bytes` must fail, and help `{b}` is the safe fix that compiles. Which types `Raw[T]` may wrap in general is a real gap. It deserves its own vote with all its cases (Int, Float, user Display types), not a rider on this ticket. *Concern:* Until that ticket is decided, other `Raw[T]` cases stay unspecified, and the compiler may handle them in ways the later rule must undo.
  - **PLT:** RB — `parts()` is `List[Str]`, and `Bytes` has no total map to `Str`, so `Raw[Bytes]` cannot fold into the parts. Whether `Raw[T]` requires `T: Display` is a separate question about how `Raw` works for all types. Deciding it here, without its own analysis, risks a rule that is inconsistent with how `Raw` treats `Str` today. *Concern:* until the general `Raw[T]` ticket is settled, other non-text types may reach `Raw` with behaviour the spec does not state.
  - **DevOps:** RB — the part I cared about is the help line: the compiler sends `{Raw(b)}` to the safe `{b}`, never the reverse, and RB gives that. The general `Raw[T]` bound touches every context and every hole type, so it deserves its own ticket and panel rather than a rider on this one. I withdraw RB+D. *Concern:* until the general rule is decided, other non-Display `Raw[T]` cases may get different errors, or none.
  - **AI/ML:** RB — The wrong spelling, `{Raw(b)}`, gets a help line that points directly to the right one, `{b}`. That is the best diagnostic shape for a model. The general rule for which `T` a `Raw[T]` may wrap is a real gap, but `T: Display` is not obviously right (it may be too wide or too narrow for an audited bypass), so it needs its own ticket and its own debate. *Concern:* Until the general `Raw[T]` ticket lands, other non-text `T` (for example `Raw[List[Int]]`) still have no rule in the spec.
  - **Minimalism:** RB — Raw[Bytes] has no text to fold into `parts()`, so rejecting it with "send it as a parameter" is correct and has a small scope. The general Raw[T] rule touches Display, injection auditing and every context. To decide it as a side effect of a Bytes ticket is how scope creep starts, so it gets its own ticket. *Concern:* Until the general Raw[T] ticket is resolved, other non-text T in Raw may behave inconsistently.

#### Phase D

Not triggered: every question passed 6-0.

#### AI-First Review

5/5 pass. Learnability: one more variant in a closed enum, and the examples name every arm. Consistency: follows the `Null` precedent and the hole-table shape. Generability: the one obvious spelling, `{blob}`, is the correct one. Debuggability: `Raw[Bytes]` and `List[U8]` get E0534 with a `help:` that compiles. Token efficiency: `{blob}` needs no `.to_hex()`.

### Final Spec

```blink
type TemplateValue {
    Int(Int)
    Float(Float)
    Bool(Bool)
    Str(Str)
    Bytes(Bytes)
    Null
}
```

- **Q1 (A):** `Bytes(Bytes)` joins `TemplateValue`. A `Bytes` hole gives `.Bytes`; `Option[Bytes]` follows the Option row. `List[U8]` stays E0534 with help `{Bytes.from_list(xs)}`. The E0534 `note:` lists `Bytes`.
- **Q2 (X):** no Template-specific copy rule. §3b.5 points to §3.6 *Shared cells*: `Bytes` is not a shared cell, so a write through another name does not change the template.
- **Q3 (AR-W):** admission rule, in the §3b.5 rationale and here only, not normative text: a new variant needs (a) no lossless map into an existing variant and (b) a shipped driver that binds it as its own kind. **Every later vote on a `TemplateValue` variant must apply this test.**
- **Q4 (E):** every §3b.5 example handler names each arm, plus: "A handler names each variant; a `_` arm hides the next language change from E0004." No lint.
- **Q5 (T):** the ruling lands now. The slice that first ports `bind_template` to `TemplateValue` ships the variant, `sqlite3_bind_blob` (with `SQLITE_TRANSIENT`), `Stmt.bind_bytes`, a `Row` `Bytes` getter and a BLOB round-trip test together. No in-tree handler ships a stub or panicking `.Bytes` arm.
- **Q6 (RB):** `{Raw(b)}` with `b: Bytes` is E0534 with help `{b}`. Which `T` a `Raw[T]` may wrap in general is a separate ticket.

### Follow-ups the panel raised

- The Bytes method table calls `set_*` "in-place", which conflicts with §3.6 (plt: settle this first, or Q2 stops holding).
- Check that gen1 does not let a `Bytes` write show through a second name (sys, min, web, aiml: needs a conformance test).
- The general rule for which `T` a `Raw[T]` may wrap (all six).
- A wildcard lint, if ever, covers every closed prelude enum, not `TemplateValue` alone (plt, min).
