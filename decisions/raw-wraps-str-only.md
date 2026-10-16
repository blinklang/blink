[< All Decisions](../DECISIONS.md)

# Which T a `Raw[T]` May Wrap — Design Rationale

### Problem Statement

§3b.5 said that `Raw(expr)` constructs a `Raw[T]` from a `T`, and that a `Raw[T]` hole "concatenates the wrapped value into the adjacent literal segment". It did not say which `T` may fold. `Raw[Bytes]` was settled as E0534 with help `{b}` ([TemplateValue Bytes](template-value-bytes.md) Q6). Every other `T` was not stated: `Raw[Int]`, `Raw[Float]`, `Raw[List[Int]]`, a user type with or without `Display`, and `Raw[Option[Str]]`.

Measured with gen1 before the panel: a `Raw` hole skips the `Display` check, `Raw(...)` builds a `Raw[T]` for any `T`, codegen folds a scalar by its own text form (Float `3.0` folds as `"3"`), and a `Raw` held in a binding fails in codegen with ICE `RawBindingNotFolded`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim.

#### Phase A — Independent proposals

##### Systems

**Proposal S1 (recommended): `Raw[T]` folds only `T = Str`.**

Rule text: "A `Raw[T]` hole folds only when `T` is `Str`. The folded text is the `Str` itself, byte for byte. Any other `T`, including `Option[Str]`, `Raw[Raw[Str]]` and a type parameter, is `error[TemplateHoleType]` (E0534) at the hole, at typecheck, before mono." This also fixes the existing sentence "each hole has a Template value type or a `Raw[T]` of one", which today admits `Raw[Option[Str]]` (no text for `None`) and `Raw[Float]` (no stated text form).

```blink
fn page(db: Db, table: Str, n: Int) -> Result[Row, DbError] {
    db.query_one(t"SELECT * FROM {Raw(table)} LIMIT {n}")      // ok: Str folds, n is a parameter
}

fn bad(db: Db, n: Int, x: Float) {
    db.execute(t"SELECT {Raw(n)}")     // error[TemplateHoleType]: `Raw[Int]` cannot fold
                                       //   help: send it as a value: `{n}`
                                       //   note: `Raw` folds only a `Str`
    db.execute(t"SELECT {Raw(x)}")     // error[TemplateHoleType], help: `{x}`
}

fn g[T](db: Db, x: T) {
    db.execute(t"{Raw(x)}")            // error[TemplateHoleType] at the generic definition
}
```

Every help line keeps the value a parameter (`{n}`) or, for a type with Display, `{p.display()}` as a parameter. None offers `Raw`, per the settled rule. An author who truly wants folded text writes `Raw(n.display())` themselves. That is explicit, and it is what the audit pin sees.

Systems tradeoffs:
- **What it compiles to:** one fold path, a `Str` append into the adjacent part. No per-type formatter dispatch inside the fold, no Display lookup, no mono-time decision. The codegen surface for Raw shrinks to one case, and every ICE row the moderator measured (List, Option, Bytes, Raw[Raw], no-Display struct, generic) becomes a typecheck error. Errors before mono is the property I want: a generic body is checked once, not per instance.
- **No hidden text form.** Today `Raw(3.0)` folds `3`. In SQL that changes a REAL literal into an INTEGER literal; integer division follows. Bool folds `true`, which SQLite before 3.23 and SQL Server do not accept. Any implicit text form for a non-Str `T` is a choice the spec must fix forever and every dialect will disagree with some of it. With Str only, the author picks the text and the reviewer sees the call that made it.
- **Display stays Str-context only.** Folding `Raw[UserType]` through Display is Display invoked on a hole by another name. S1 keeps Q3 exact.
- **Audit is tighter.** W0310 pins the code that builds the `Str`. With `T: Display`, the injection surface would include every Display impl in the dependency graph, which the audit pin does not cover.
- **Cost to users:** `Raw(n.display())` is 10 more characters in the rare case where an integer must fold (e.g. DDL `VARCHAR({Raw(w.display())})`, where drivers refuse parameters). I accept that.

**Proposal S2 (fallback): `Str` plus the integer hole types** (`Int`, `I8`..`I32`, `U8`..`U32`), folded as base-10 ASCII with a leading `-` for negatives, nothing else. Integers cannot carry an injection and have one text form every dialect reads, so this covers DDL widths and LIMIT in drivers that refuse to bind there. Float, Bool, Option, Char, U64, user types stay E0534. Cost: a second fold path (an int-to-decimal call) and a second rule to teach. I prefer S1; S2 is acceptable.

**Reject:** `T: Display`. Too wide for an audited bypass, re-introduces Display on holes, and makes the fold text depend on user code that the audit pin does not cover.

Cross-language: psycopg `sql.SQL(...)` takes `str` only; jOOQ plain-SQL `DSL.sql(String)` takes `String` only. Rust sqlx `QueryBuilder::push(impl Display)` is the wide model, and it is the one with the documented injection footgun. Go and Zig have no bypass type; they make you build the string, which is S1 with extra steps.

##### Web/Scripting

###### Proposal W1 (my pick): `Raw` takes a `Str`, and nothing else

Rule: `Raw(expr)` requires `expr: Str`. `Raw[T]` stays a real generic marker type (decided), but the only `T` that can be built is `Str`, so the only `T` a hole ever folds is `Str`. The fold text is the string itself, byte for byte. No fold-form table is needed.

```blink
fn page(db: Handler[DB], table: Str, n: Int, desc: Bool) -> Result[List[Row], DbError] with DB {
    let dir = if desc { "DESC" } else { "ASC" }
    db.query(t"SELECT * FROM {Raw(table)} ORDER BY id {Raw(dir)} LIMIT {Raw(n.display())}")
}

t"... LIMIT {Raw(n)}"
// error[RawNotStr]: `Raw` takes a `Str`, found `Int`
//   = note: the text that `Raw` folds into the query must be text you can see
//   = help: render it first: `Raw(n.display())`
//   = help: or keep it a parameter: `{n}`
```

Diagnostics, per T (all at the `Raw(...)` call, at typecheck, never codegen):
- `Int`, `Float`, `Bool`, sized ints, `Char`, user type with `Display`: help `Raw(x.display())`, then help `{x}` when x is a Template value type.
- `Option[Str]`: help "decide what `None` means": `Raw(col.unwrap_or("id"))`. No help with `.display()`.
- type without `Display` (`List[Int]`, struct): note only; help `{x}` when it applies.
- `Bytes`: keep the decided E0534 with help `{b}`.
- Generic `fn g[T](x: T)` with `Raw(x)`: same error (T is not Str). With `T: Display`, `Raw(x.display())` compiles.
- `Raw(Raw(s))`: error, `Raw[Str]` is not `Str`.

Code: new code, or E0530-family; not E0534, because E0534 help lines may never offer `Raw(...)` and here the user already chose `Raw`. The help just repairs the argument.

Why (DX):
1. **One sentence to learn.** "Raw takes a string." A JS/Python dev gets it in 5 seconds. "Raw takes any Template value type except Bytes and except Option" is a table to look up.
2. **Each other T makes a Stack Overflow question.** What does `Raw(None)` fold to: `""`, `"NULL"`, `"None"`? What does `Raw(true)` fold to in SQLite (`1`) vs Postgres (`TRUE`)? Does `Raw(3.0)` give `3`, `3.0` or `3e0`? (Note: gen1 gives `"3"` today; §3.6 says `"3.0"`. So the question is real already.) With Str only, the author writes the text, and the audit reviewer reads the text at the site.
3. **Display stays Str-context only.** `.display()` is a call in a Str context, in plain sight. We never call Display implicitly inside a Template, so the Q3 vote holds with no special case.
4. **The cost is small.** The real Raw cases are table names, column lists, `ASC`/`DESC`, generated clauses: all already `Str`. The only common non-Str case is `LIMIT n`, and that should be `{n}` (a parameter) in nearly every driver. The extra `.display()` is a small speed bump on a path we want to be slow: it is an audited bypass.
5. **Closes every ICE in the list** with one check, and the typechecker gets one rule, not a set.

Cross-language: every JS/Python SQL lib I know takes a string here and only a string: Prisma `Prisma.raw(str)`, Kysely `sql.raw(str)`, Drizzle `sql.raw(str)`, psycopg `sql.SQL(str)`. Nobody asked them for `raw(42)`.

###### Proposal W2 (fallback): Template value set minus Bytes and Option

If the panel wants `Raw(n)` for numbers: allow `Int`, sized ints, `Float`, `F32`, `Bool`, `Str`. Fold text = that type's `Display` text as §3.6 gives it (`Float` per *Float Text Form*, so `3.0`; `Bool` gives `true`/`false`). Reject `Option[T]` (help: unwrap_or), `Bytes` (decided), and everything else, with the same help lines as W1. This is still closed and cheap to state, but it needs a fold-form table in §3b.5 and it brings back the SQL-dialect Bool question.

###### Against `T: Display`

Too wide. User `Display` impls are for humans (`Point(1, 2)`), not for a query. It makes the folded text depend on an impl that can sit in a different module from the audited site, and it calls Display implicitly in a Template, which breaks the spirit of Q3. With W1 the user can still get it, but they must write `.display()` where the reviewer can see it.

##### PLT

**Core claim.** Folding `Raw[T]` into the parts needs a map T -> Str. For any T other than Str, the only map the language has is Display. "Display is Str-context only" (5-0) says Display is never invoked on a Template hole. A `Raw[Int]` that folds as "42" calls Display on a Template hole under another name. So the decided rules already force the answer: T = Str.

**Proposal P1 (my pick): Raw folds only a Str.**

Typing rule: `Raw(e)` checks if `e : Str` and gives `Raw[Str]`. `Raw[T]` is well-formed only at T = Str. The check runs where the Raw arises (the `Raw(...)` argument, or a written `Raw[X]` annotation), so every Raw value in a program is a `Raw[Str]`. Fold is plain concatenation: no rendering, no Float text form, no None text, and nothing new to specify. The hole rule "a Raw[T] of a Template value type" becomes "a `Raw[Str]`".

```blink
fn page(table: Str, limit: Int, ratio: Float) -> Template[DB] {
    t"SELECT * FROM {Raw(table)} LIMIT {limit}"     // ok: Raw[Str] folds; limit is a parameter
    // t"... LIMIT {Raw(limit)}"     error[TemplateHoleType]: Raw folds only a `Str`, found `Int`
    //                               = help: send it as a parameter: `{limit}`
    // t"... {Raw(name_opt)}"        error[TemplateHoleType]: found `Option[Str]`
    //                               = help: send it as a parameter: `{name_opt}`
    // t"... {Raw(p)}" (p: Point)    error[TemplateHoleType]
    //                               = help: send its text as a parameter: `{p.display()}`
}
```

Diagnostic: E0534 TemplateHoleType for every T != Str, at the `Raw(...)` argument span. That matches the Raw[Bytes] ruling (same code, help sends the value as a parameter). Help lines, in order: T is a Template value type -> `{x}` (drop the Raw). T has Display -> `{x.display()}`. Otherwise note only. No help offers `Raw(...)` or `Raw(x.display())`, as the decided rule requires. An author who truly wants the text writes `Raw(n.display())`. The audit then covers one visible Str, and the call to Display sits in Str context, where the spec allows it.

Generics: `fn g[T: Display](x: T)` with `Raw(x)` is E0534 at the definition, never at mono. Blink has no trait for "Str-like", and should not get one for this. The rule reads off the static type, so it is parametric and gives no late errors. That matches "reported at typecheck, at the hole, and never at codegen". `fn wrap(s: Str) -> Raw[Str] { Raw(s) }` stays valid, and so do bindings and returns (the marker survives).

Tradeoffs:
+ Sound by construction: one fold rule, one type, no text form chosen inside a Template context. The bypass surface is exactly "a Str the author audited", which answers aiml's "too wide" concern.
+ Option[Str] is out. None has no context-free text (SQL NULL? empty? "None"?), and any choice embeds a context-specific meaning in a context-generic fold.
+ Codegen: the ICE cases (List, Option, Bytes, Raw[Raw], no-Display structs) all become typecheck errors. The fold path only ever sees Str.
- `Raw(n.display())` is longer than `Raw(n)`. That is deliberate. Spliced numbers (LIMIT, column index) should be parameters, and the help says so.
- Minimalism may ask why Raw keeps a parameter at all. I keep `Raw[T]` so the decided spec text and E0534's `Raw[Bytes]` ruling stay valid. A non-generic `Raw` would be a separate, larger change.

**Proposal P2 (fallback if the panel wants numbers): scalar Template value types.** T in {Str, Int, I8..U32, Float, F32, Bool}. Each folds by its §3.6 display form, stated in normative text (Float uses the *Float Text Form*: 3.0 -> "3.0", NaN -> "NaN", inf -> "inf"; Bool -> "true"/"false"). Option, Bytes, and everything else are E0534 with the same help lines. A generic T is E0534 at the definition. Cost: the spec must state that this fold is a built-in rendering, not a call to Display, to keep Q3 intact. That distinction is thin. Also, `NaN`/`inf` folded into SQL become identifiers, an injection-shaped surprise under an audit that claims "cannot carry an injection".

Codebase note (either option): gen1 folds Float 3.0 as "3". That breaks §3.6 *One form everywhere* for plain interpolation too, so it is a bug whatever the vote. It needs its own ticket.

Cross-language: Python 3.14 t-strings have no fold at all; the handler decides. JS tagged templates use `String.raw` only for literal text. psycopg `sql.SQL`/`sql.Identifier` and sqlx `QueryBuilder::push` both take only string-like text for raw splicing. Haskell `postgresql-simple` `Query` is a newtype over ByteString text. None of them splice a typed non-text value raw. P1 matches all of them.

##### DevOps

**P1 (preferred): `Raw[T]` folds only when `T = Str`. Every other `Raw[T]` hole is E0534, and its help lines are the E0534 repairs for `T` itself.**

```blink
fn report(table: Str, n: Int, tag: Option[Str], p: Point) -> Result[List[Row], DBError] ! DB.Read {
    db.query(t"SELECT * FROM {Raw(table)} LIMIT {n}")   // OK: W0310, audit-gated
    db.query(t"SELECT * FROM t LIMIT {Raw(n)}")         // error[TemplateHoleType]
    db.query(t"SELECT * FROM t WHERE tag = {Raw(tag)}") // error[TemplateHoleType]
    db.query(t"SELECT * FROM {Raw(p)}")                 // error[TemplateHoleType]
}
```

```
error[TemplateHoleType]: a `Raw[Int]` cannot fold into the parts
 --> report.bl:3:41
  |
3 |     db.query(t"SELECT * FROM t LIMIT {Raw(n)}")
  |                                       ^^^^^^ only a `Raw[Str]` folds
  |
  = note: `Raw` folds text, and only a `Str` is text
  = help: send it as a parameter: `{n}`
```

For `Raw[Point]`, the diagnostic has the same first two lines, then the existing E0534 list for `Point`: `{p.display()}`, `{p.x}`. For `Raw[List[Int]]`, it gives the `note:` only. `Raw[Raw[Str]]` gets `help: remove one Raw`. A help line still never offers `Raw(...)`.

Why, from the tooling seat:

1. **One rule, one diagnostic shape, and Q6 is a special case.** Q6 already gives `Raw[Bytes]` E0534 with help `{b}`. P1 makes that the general rule: drop the wrapper, then apply the hole table to `T`. The compiler needs no new error code and no new help table, and it reuses the existing `help:` list. An LSP quick-fix "remove Raw" is always safe, and it compiles whenever `T` is a value type.
2. **Audit fatigue is the real risk to W0310.** `Raw(n)` with `n: Int` cannot carry an injection. If it folds, the user gets an audit-gated warning that they can only silence with an audit record that claims the obvious. Teams that write such records learn to stamp IDs without reading. An audit-gated warning must fire only where the claim means something. With `Str` only, every W0310 marks text that can hold an injection.
3. **No hidden text forms.** Each other `T` would need a fold form for the spec to state: Float `NaN`/`inf` (not valid SQL), `Option` `None` (`NULL`? `""`?), and Bool `true` versus `1`. A user `Display` impl is worse: library code that the author of the query never sees sets the query text, and Display is Str-context only (5-0). gen1 already proves the drift: Float `3.0` folds to `3`, but §3.6 says `3.0`. With `Str` only, nothing can drift.
4. **Generics need no bound.** `fn g[T](x: T) { ... t"{Raw(x)}" ... }` is E0534 at the definition: "`Raw[T]` folds only when `T` is `Str`; `T` is a type parameter." The check is local and happens at typecheck. A `Display` bound would let an instantiation choose the query text.
5. **The escape stays explicit.** A user who must splice an `Int` (some drivers refuse a parameter in `LIMIT`) writes `{Raw(n.display())}`. That is legal, it raises W0310, and the audit record says what was folded. The help does not offer it, by design.

Spec change: in *Raw(expr)*, replace "a `Raw[T]` of one" with "a `Raw[Str]`". Add: "A `Raw[T]` hole with `T` other than `Str` is E0534. Its help lines are those for a hole of type `T`, and when `T` is a Template value type the first one is `{x}`." Bytes stays as decided. Today's corpus and lib use only `Raw(Str)` (I checked tests/, lib/, src/), so the change breaks nothing.

**P2 (fallback): the Template value set minus Bytes, with fold forms stated.** Ints fold as decimal, Float as §3.6 text (NaN and inf are an E0534 error? no, they are runtime values, so the fold fails at run time; that is why I rank this second), Bool as `true`/`false`, and `Option` is E0534. P2 adds four rows of normative text and one runtime failure mode, and it keeps the noisy W0310 on Int.

**I reject `T: Display`.** It hands query text to impls that the query's author does not control. It also contradicts "Display is Str-context only", and it makes the help lines depend on trait resolution.

Cross-language: Rails `raw` / Django `mark_safe` / Jinja2 `Markup` all take a string, and none of them take an arbitrary object. Python 3.14 t-strings have no raw marker at all. Go `template.HTML(s)` is a conversion from `string` only.

##### AI/ML

**A1 (preferred): `Raw[T]` folds only when `T` is `Str`.** Every other `Raw[T]` hole is E0534 TemplateHoleType, at typecheck, at the hole.

Rule text: "A `Raw[T]` hole folds when `T` is `Str`, and its text is the `Str` itself. Any other `Raw[T]` hole is `error[TemplateHoleType]` (E0534)." That one sentence replaces the open list. `Raw[Bytes]` stops being a special case and becomes one row of the general rule (the 6-0 help `{b}` is unchanged).

```blink
fn page(table: Str, n: Int) -> Template[DB] {
    t"SELECT * FROM {Raw(table)} LIMIT {n}"       // ok: Raw[Str] folds; n is a value
}

fn bad(n: Int, xs: List[Int], p: Point) -> Template[DB] {
    t"... {Raw(n)} {Raw(xs)} {Raw(p)}"            // E0534 x3
}
// error[TemplateHoleType]: `Raw[Int]` cannot fold: only `Raw[Str]` folds into the parts
//   = help: send it as a value: `{n}`
// (Raw[List[Int]] / Raw[Point]: note only, or the existing field/display() help rows on the inner value)

fn g[T](x: T) -> Template[DB] { t"{Raw(x)}" }   // E0534 at the definition, not at mono:
                                                  // `Raw[T]` folds only when T is Str
```

Help lines follow the existing E0534 rules with `Raw` removed. If the inner `T` is a value type, the help is "send it as a value: `{x}`". Otherwise the help is the inner type's existing E0534 help (`{p.display()}`, `{p.id}`), with no `Raw` wrapper. No help line ever offers `Raw(...)`, which keeps the rule already in the spec. An author who really needs a number's text in the parts writes `Raw(n.display())`. That is an explicit choice that the audit can see, and the compiler never suggests it.

Why, from the AI seat:

1. **Zero new fold-text table.** With Str only, the fold text is the string itself. Every wider option must also state what each `T` folds to: Float, `Bool`, `None` and the narrow ints. That is one more table for a model to learn, and the moderator confirms the spec has no such table today.
2. **The wider forms make broken SQL that compiles.** The §3.6 Float form gives `1.0e16`, `1.0e-5`, `NaN` and `inf`. `Bool` gives `true`, which SQLite before 3.23 and MSSQL reject. An `Option` fold has no right text for `None` (`NULL`? empty? `None`?). A model that writes `{Raw(x)}` gets text that depends on the dialect and is often wrong, and every stage stays green. With Str only, the author owns the text.
3. **The `T: Display` bound contradicts a 5-0 ruling.** "Display is never invoked on a Template hole." Folding `Raw[Point]` through Display does exactly that, and it lets a user `impl Display` choose text that goes into SQL unchecked. An audited bypass should cover the narrowest input that is still useful.
4. **One decision point, and the safe path is shorter.** `{n}` costs fewer tokens than `{Raw(n)}`, so the wrong spelling costs more and the diagnostic points to the shorter, safe one. The rare need costs about 3 extra tokens (`Raw(n.display())`).
5. **No generic surprises.** The check happens before mono, so `Raw[T]` with a type parameter `T` is an error at the definition. Today Display types pass, and List, Option and non-Display types reach an ICE. A1 turns every ICE case into E0534 and needs no Display lookup.

Cost: `{Raw(n)}` with an Int compiles today, so this breaks it. That is acceptable before 1.0 (no third-party code exists), and the fix is mechanical: delete `Raw`.

**A2 (fallback, ranked second): Str plus the integer types (Int, I8–I32, U8–U32).** Integer text is plain decimal, has no form that depends on the dialect, and cannot carry an injection. Float, Bool, Option, Bytes and every other T get E0534 as in A1. Tradeoff: two members in the rule instead of one, and a one-line fold-text rule ("decimal, `-` sign"). Its only gain is DDL that cannot take a parameter (`VARCHAR({Raw(n)})`), and `Raw(n.display())` covers that already. I vote A1 over A2.

**Against "the Template value set minus Bytes":** this needs the full fold-text table (Float, Bool, Option None), and it brings back problem 2.

Cross-language note: Python's PEP 750 t-strings give no raw fold at all. The library chooses, and `psycopg.sql.SQL`/`Identifier` take only `str`. JS `sql.raw()` in slonik and drizzle takes a string. Prior art agrees on Str only for the bypass.

##### Minimalism

###### Proposal M1 (preferred): `Raw[T]` folds only when T is `Str`

Rule (one sentence, replaces "a `Raw[T]` of one" in §3b.5): *A `Raw[T]` hole folds only when T is `Str`; the folded text is the string, byte for byte. Any other T is `error[TemplateHoleType]` (E0534).*

```blink
fn fetch(db: Db, table: Str, n: Int, ok: Bool) -> Row {
    db.query_one(t"SELECT * FROM {Raw(table)} WHERE id = {n}")     // OK: Raw[Str], W0310
    db.query_one(t"SELECT * FROM t LIMIT {Raw(n)}")                 // E0534
    // help: `{n}` sends `n` as a parameter
    db.query_one(t"SELECT * FROM t WHERE {Raw(clause_for(ok))}")    // OK if clause_for -> Str
}

fn g[T](x: T, db: Db) {
    db.execute(t"DELETE FROM {Raw(x)}")   // E0534 at the definition: T is not Str
}
```

Help lines per T (all compile as the first repair, none adds a new `Raw`):
- Int family, Float, Bool, `Option[...]` of those, `Option[Str]`: drop the `Raw` — `{n}` sends it as a parameter. That is what the user should do anyway; a number or a flag has no injection risk that parameters do not already handle.
- Bytes: unchanged (`{b}`).
- Char, user types with Display, anything else Display-able: build the text in a Str context first — `let s = "{x}"` then `{Raw(s)}`. This keeps the bypass the author already chose and makes the text visible. (Debate point: I read "help never offers `Raw(...)`" as "Raw is never the repair for a type error". Here the author already wrote Raw, so keeping it is not a new bypass. If the panel reads the rule strictly, give the `note:` line only.)
- No Display, `Raw[Raw[Str]]`, collections: `note:` only.

Generics: no new bound, no new mechanism. The hole check uses the declared type. A type parameter is not `Str`, so `Raw[T]` with free T is E0534 at the definition. Mono never sees an unchecked fold.

###### Why this is the minimal answer
1. **Zero fold-text rules.** Every other option must state what text each T becomes, and each answer is a footgun the spec then owns: Float `3.0` folds to `"3"` today (an integer in SQL; type change in Postgres), Bool `"true"` vs dialect `TRUE`/`1`, `None` → `""` or `"NULL"`? Str needs no rule: the text is the string.
2. **Matches the stated use case.** §3b.5 names table names, column lists, generated clauses. All are Str. No example in the spec needs a non-Str Raw.
3. **Audit is smaller.** An auditor pinning `@trusted(audit: K)` reviews one kind of value. "Is this Display impl injection-safe?" is a question about code far from the call site and can change without the pin moving. Str-only keeps the audited text local.
4. **Display stays Str-context only.** A Display bound would invoke Display on a template hole by the back door, against the 5-0 vote.
5. **Narrowing later is a break; widening is not.** Start with Str; if real users show a need for `Raw[Int]`, widen by a vote. The reverse removes working code.
6. **Closes the ICE list in one rule.** List, Option, Bytes, Raw[Raw], no-Display struct, generic: all become E0534.

###### Rejected
- **T: Display** — reintroduces Display on holes; audit surface leaves the call site; generic bound needed.
- **Template value set minus Bytes** — needs a fold-text table for Float, Bool, every narrow int, and None, for no stated use case.
- **Do nothing** — not an option: today's typecheck accepts everything and codegen ICEs.

###### Cross-language
Every mature raw-SQL escape takes a string only: Prisma `Prisma.raw(string)`, Slonik `sql.unsafe` / `sql.identifier([string])`, Knex `knex.raw(string)`, psycopg `sql.SQL(str)`, Rust `sqlx::query(&str)`. Go's `database/sql` has no bypass at all. None formats a number into the query text for you; they push numbers to parameters, which is the help line above.

###### Proposal M2 (fallback, only if the panel wants numbers)
Str plus the Int family, folded as decimal digits with a leading `-` (one sentence, no locale). Float, Bool, Option stay E0534 with the "drop Raw" help. I still vote M1.

#### Phase A.5 — Dedupe

All six put **S** (only `Raw[Str]` folds) first. Fallbacks: **SI** (Str plus the integer hole types) from sys, aiml and min; **SC** (the scalar Template value types by their §3.6 form) from web, plt and devops. All six rejected `T: Display` by name. Three variations went to Phase B: V1, where the check runs and which code; V2, whether a help line may offer `Raw(x.display())`; V3, the help for `Raw[Raw[Str]]`.

#### Phase B — Debate (one round)

##### Systems

**S vs SI vs SC: S.** SI was my fallback, and I drop it. Six first choices for S, and SI's only real case (DDL widths, LIMIT where a driver refuses a bind) costs one `.display()` that the author writes and the audit pin sees. SC: no. plt makes the point that matters in my domain. `NaN`/`inf` folded into SQL become identifiers, and `true` does not parse on every dialect. A fold-form table is codegen the spec must freeze forever.

**V1: I move from (a) to (b), with code E0534.** plt's construction check is the better systems choice. Under (a), a well-typed `Raw[Int]` can exist. A library fn `-> Raw[T]` then moves the error to a caller's hole in another module, away from the code that chose the value. Under (b), no `Raw[X]` with X ≠ Str can exist. The error lands at the `Raw(...)` argument or at the written `Raw[X]` annotation, and nothing downstream (bindings, returns, generics, mono) ever has to consider another T. Codegen sees exactly one case. Generic `fn g[T](x: T) { Raw(x) }` fails at the definition, because T is not Str. Keep E0534, not web's new code (c). `Raw[Bytes]` is already E0534 at this exact span (6-0), and two codes for "Raw got a non-Str" is one too many.

**V2: No.** Answering web and min: "the author already chose Raw" is true, but `Raw(n.display())` is not a neutral repair. The compiler would choose the text form for them, Float `3.0` against `3` and Bool `true` against `1`. S exists so that the author makes that choice in plain sight, unprompted. The rule "a help line never offers `Raw(...)`" is settled, and it has no exception for "already chose it". Help lines: `{x}` when x is a Template value type, `{x.display()}` when T has Display, otherwise note only. For `Option[Str]`, help `{opt}` (it becomes a parameter, None → Null).

**V3:** `Raw(Raw(s))` is E0534 because the argument is `Raw[Str]`, not `Str`. Use a `note:` only ("the value is already a `Raw[Str]`"), not a `help:`, so it stays consistent with V2. The fix is obvious from the note, and a help that rewrites to `Raw(s)` is still a help line that offers `Raw`.

STABLE, ready to vote

##### Web/Scripting

**S vs SI vs SC: S.** All six of us picked it first, so I will not argue it again. My ranking for the fallbacks is SI before SC: integers give one obvious text, but Float and Bool do not (Float `3.0` vs `3`, Bool `true` vs `1`/`TRUE`).

**V1: I move from (c) to (b).** I still want the error at `Raw(...)`. If a user writes `let r = Raw(n)` on line 3 and uses `{r}` on line 20, the error belongs on line 3, where the mistake is. But I drop my new code. One code for "this cannot be a template hole" (E0534) is simpler to learn and search for than two, and it already covers `Raw[Bytes]`. So `Raw(b)` and `Raw(n)` give the same code at the same place. Under (b), a written `Raw[Int]` annotation fails too, which is good: it can never be used.
Against (a): it delays the error until the hole. In a generic or a returned `Raw[Int]`, the user then gets an error far from the code they must change.

**V2: I concede "No".** The rule "a `help:` line never offers `Raw(...)`" is short, and an exception for it makes a Stack Overflow question of its own. `{n}` is also the better repair in nearly every case, because it keeps the value a parameter. To keep a user who truly needs `Raw` from getting stuck, the `note:` line states the fact, but not as a repair:

```
error[TemplateHoleType]: `Raw` folds only a `Str`, found `Int`
  = note: `Raw` folds only a `Str`; a `Raw[Int]` has no text form
  = help: keep it a parameter: `{n}`
```

A JS/Python dev reads "folds only a Str" and works out `.display()` without help. The note does not offer `Raw`, so the rule holds.

**V3: yes to devops's `help: remove one Raw`.** That help removes a `Raw`, it does not offer one, so it obeys the rule. `Raw(Raw(s))` is a likely typo or a wrapper-around-wrapper mistake, and the fix is clear.

**Option[Str] under V2 "No":** help `{col}` (it is a valid hole type, None gives Null). That is fine.

STABLE, ready to vote

##### PLT

**S vs SI vs SC: S.** No change. A fold of any T other than Str needs a map T -> Str, and the only such map in the language is Display. SI and SC need a new rule: "a built-in rendering that is not Display". That rule exists only to work around the Q3 vote. If the panel splits, my fallback order is SI, then SC. SI's base-10 form is context-free. SC adds Float NaN/inf and Bool forms that SQL reads as identifiers.

**V1: I prefer (b) and accept (a). I reject (c).**
- Both (a) and (b) are sound, provided the hole check reads the static type at typecheck. A hole of type `Raw[T]`, with T a type parameter, is E0534 at the definition, never at mono. That condition is not negotiable for me.
- (b) reports at the cause, not at a hole that a binding or return may put far away. It also leaves no inhabited `Raw[List[Int]]` that no consumer can use. (a) keeps the current sentence "Raw(expr) constructs a Raw[T] from a T" unchanged, so it is the smaller spec edit. I will vote with the majority between them.
- Against (c), for web: Q6 (6-0) fixes `{Raw(b)}` as E0534. A new `RawNotStr` code either contradicts that ruling or splits the codes by T (Bytes gets E0534, Int gets RawNotStr), with no principle behind the split. Use one code for every T other than Str: E0534.

**V2: No.** "A help: line never offers Raw(...)" is in the normative text, so a yes needs an amendment, not a reading. Web's point ("the author already chose Raw") does not hold. With `help: Raw(n.display())`, the compiler picks the text form and keeps the audited bypass, which the error had stopped. The author then accepts a W0310 that the compiler wrote. The note line can state the rule without suggesting a repair: "= note: Raw folds only a `Str`". An author who wants the text can write `Raw(n.display())` from that note, and the audit covers a choice the author made. For min: give the note line only.

**V3:** E0534 with `help: remove one Raw`. I agree with devops. Removing a Raw is not offering one, so the rule allows it.

STABLE, ready to vote

##### DevOps

**S, not SI or SC.** SI's only gain is `LIMIT {Raw(n)}`, and that case is exactly the audit noise I object to. Every SI fold of an Int raises W0310 for a value that cannot inject, so teams learn to stamp audit IDs. The author who must splice an Int can write `Raw(n.display())`, and then the record is honest about the text. SC adds Float NaN/inf, which no SQL dialect reads as a number, and a Bool form that differs by dialect. It also adds normative text that gen1 already gets wrong (`3.0` → `3`).

**V1: (b), check at construction, code E0534.** plt convinced me. The error lands where the fix is, the `Raw(...)` call, and not at a hole that may be three lines away through a binding. Hover never shows a type such as `Raw[Int]` that has no legal use. A generic `fn f[T](x: T) -> Raw[T]` fails at its definition, and no later instantiation reports it. I keep E0534 rather than a new code (contra web's (c)) for two reasons. Q6 already uses E0534 for `Raw[Bytes]`, and one code for "this type cannot go into a template" lets `blink explain E0534` cover it in one page. The message carries the specific text: "`Raw` wraps only a `Str`; found `Int`". Under (b), Q6's text needs one edit: the span moves to the argument, and the help is unchanged. I accept (a) as a second choice. Both close the gap.

Help at construction through a binding: `let r = Raw(n)` → `help: drop the wrapper: let r = n`, and the hole `{r}` then sends a parameter.

**V2: No.** web says the author already chose `Raw`. But the E0534 help rule exists so that a type error never ends with a suggestion to bypass. If the compiler offers `Raw(n.display())`, a model or a tired human applies it as a quick fix, and every Int becomes text. The repair that keeps the value a parameter, `{n}`, always compiles for a value type. For a type with no repair, the diagnostic gives the `note:` only, as the spec already says.

**V3: help: `remove the inner Raw`: `Raw(s)`.** It is machine-applicable and always compiles. It is cheap to state, so I ask for it in the text and not left to the implementation.

STABLE, ready to vote

##### AI/ML

**S over SI and SC.** I drop A2. All six seats put S first, and no Phase A text names a real case that needs SI. `Raw(n.display())` covers DDL like `VARCHAR(n)`.

**V1: I move from (a) to (b).** Check at construction: `Raw(e)` requires `e: Str`, and the code is E0534. plt's argument decides it for me. Under (a), `let r = Raw(n)` type-checks, and the error comes later at a hole, maybe in another function, after `r` was returned. A model fixes a diagnostic at the span it is given. (b) puts the span on the `Raw(...)` argument, where the repair goes. (b) also means no `Raw[Int]` value ever exists, so a `Raw[X]` annotation is checked by the same rule and never yields a dead type. The Q6 text still holds: `{Raw(b)}` is E0534 with help `{b}`. Only the span moves to the argument, and that is inside the same hole.

**Against (c), a new code.** One code for "this is not a template value" gives one thing to learn and to search. web wants a new code so that a help line can offer `Raw`. That reason fails if V2 is No.

**V2: No.** This is my strongest point. Models apply the first `help:` line mechanically. If E0534 says `help: render it first: Raw(n.display())`, every generated `{Raw(n)}` becomes an audited bypass with the injection warning, when `{n}` was right in nearly every case. web says the author already chose `Raw`. For generated code that is often false: the model copied `Raw` from a nearby table-name hole. The diagnostic is the one place to redirect it, and the decided text forbids offering `Raw(...)` anyway. min's `let s = "{x}"` then `{Raw(s)}` is the same suggestion through a binding, so it also gets No. A human who truly needs the text writes `Raw(n.display())`, and the audit sees that choice.

**V3: `Raw(Raw(s))`.** Under (b) the argument is `Raw[Str]`, not `Str`, so the code is E0534. I accept devops's `help: remove the inner Raw`, because it deletes a bypass and adds none. The help shows the result `Raw(s)` only because the author's outer `Raw` stays.

**Separate:** I agree with plt that gen1 folding Float `3.0` as `"3"` breaks §3.6 for plain interpolation too. That needs its own bug ticket, whatever this vote decides.

STABLE, ready to vote

##### Minimalism

**S vs SI vs SC: S.** Six first choices agree. SI and SC each add fold-text rules for no use case in the spec. SC also ties the fold to §3.6, and plt's own note proves the risk: gen1 already gets Float display wrong, so SC would put a known bug into SQL text. If a real need for `Raw[Int]` appears, widen later by vote; narrowing later breaks code.

**V1: (a), check at the hole, E0534.** Reasons, all on surface cost:
- It changes no existing text. §3b.5 already says "`Raw(expr)` constructs a `Raw[T]` from a `T`", and the settled `Raw[Bytes]` rule (6-0) already puts E0534 at the hole. (a) is one sentence that makes Bytes a case of the general rule, not an exception.
- (b) makes `Raw[T]` a type that is well-formed at one T only. That is a non-generic type with a parameter on it, plus a new well-formedness check on written annotations. It also forces a rewrite of the Q6 text. More rules, same programs rejected.
- (c) adds a new code. Reject: E0534 TemplateHoleType already means "this hole type cannot go in a template", which is exactly the fault.
- plt's point that (a) reports late (a `let r = Raw(n)` compiles until used) is true but cheap: an unused `Raw[Int]` does nothing, and a used one errors at the hole with a precise span.

**V2: No.** I withdraw my open point. The strict reading is one rule with no exception; my reading needs a sentence on "when the author already chose Raw". Help drops the `Raw` (`{n}`, field help) or gives `note:` only. The author may still write `Raw(x.display())` by hand; that keeps the audit and needs no help line. web: a help that offers `Raw(n.display())` for an Int steers users away from the parameter, which is the safe repair.

**V3: accept devops `help: remove one Raw`.** It compiles, it adds no bypass (the inner Raw is still audited), and it costs one help line. If the panel prefers `note:` only, I do not object.

STABLE, ready to vote

Position shifts: on V1, sys, aiml and devops moved from (a) to (b), and web moved from (c) to (b) and dropped the new code. plt preferred (b) and accepted (a). min kept (a) **(dissent)**. On V2, web and min moved to No. On V3, five seats took devops's help line; sys kept a note only **(dissent)**. All six sent "STABLE, ready to vote" after one round.

#### Phase C — Final vote

- **Q1: Which T may a `Raw[T]` fold?** (6-0) — **S: only `Str`**
  - **Systems:** S  
    Reasoning: The fold becomes one `Str` append, with no per-type formatter inside the fold and no text form the spec must freeze forever. SI and SC choose a text form for the author, such as Float `3` against `3.0`, or Bool `true` against `1`, and `NaN`/`inf` fold into SQL as identifiers. The rare integer case costs one visible `.display()`, which the audit pin then covers.  
    Concern: Users who want `LIMIT {Raw(n)}` may move to the `let s = "{n}"` then `{Raw(s)}` pattern by habit, rather than `{n}`, so the docs must show the parameter form first.
  - **Web/Scripting:** S  
    Reasoning: "Raw takes a string" is one rule that a JS or Python dev learns at once, and it is what Prisma, Kysely, Drizzle and psycopg already do. Each other T brings a question with no clear answer (Float `3` or `3.0`, Bool `true` or `1`), and the reviewer must look up a table to know what text went into the query. With S the author writes the text, and the reviewer reads it at the site.  
    Concern: users who want `LIMIT {Raw(n)}` will write `Raw(n.display())` from memory and treat it as a habit, when `{n}` would serve them better.
  - **PLT:** S  
    Reasoning: Folding any T other than Str needs a map T -> Str. The only such map in the language is Display, and Q3 of display-format (5-0) bars Display from a Template hole. With S the fold is plain concatenation with one typing rule. It needs no new text form and no new rendering rule beside Display.  
    Concern: Authors will write `Raw(n.display())` to splice numbers. The spec should say that a number should stay a parameter, so this does not become a habit that W0310 audits must then accept without thought.
  - **DevOps:** S  
    Reasoning: An audit-gated warning should fire only where its claim means something, and only a Str can carry an injection. SI and SC would raise W0310 on values that cannot inject, and that trains teams to stamp audit IDs without reading them. With S, the spec needs no fold text rule for each type, so no form can drift (gen1 already folds Float 3.0 as "3"). The diagnostic is one rule: drop the wrapper, then apply the hole table to T.  
    Concern: Users who must splice an Int into a place that takes no parameter (LIMIT in some drivers) will meet the error first, and they need the docs, not the help line, to find `Raw(n.display())`.
  - **AI/ML:** S  
    Reasoning: The rule is one sentence, and no fold-text table is needed, so a model can learn it from the spec alone. With SI or SC the model must know each type's folded form, and those forms make SQL that compiles but is wrong (`1.0e16`, `NaN`, `true` in some SQL dialects). Only S keeps Display out of every Template hole. The safe spelling `{n}` is also shorter than `{Raw(n)}`, so the safe form is also the cheap form.  
    Concern: Code from before this ruling and examples in training data contain `{Raw(n)}` with an Int, so models will keep writing it for a while. The E0534 help must be good enough to correct them every time.
  - **Minimalism:** S  
    Reasoning: Str is the only T whose fold needs no rule of its own: the text is the string. SI and SC each add a fold table for no use case the spec names, and SC ties SQL text to §3.6, which gen1 already gets wrong for Float. Widening later by vote breaks nothing; narrowing later breaks working code.  
    Concern: users who write `Raw(limit)` for an Int will get an error and may feel the rule is fussy, but the help (`{limit}` as a parameter) is the safer fix.

- **Q2: Where is a non-Str `Raw` rejected, and with which code?** (5-1, Minimalism dissent) — **(b): at construction, E0534**
  - **Systems:** (b)  
    Reasoning: If no `Raw[X]` with X ≠ Str can exist, bindings, returns, generics and mono never need to consider another T, and codegen sees exactly one case. The error lands on the `Raw(...)` argument the author wrote, not on a hole in another module that received a `Raw[Int]` from a library. E0534 keeps one code with the settled `Raw[Bytes]` ruling at the same span.  
    Concern: A written `Raw[X]` annotation check is a new well-formedness rule on a generic type, so the implementation must check it everywhere a type is written (params, returns, fields, aliases, type args), or a gap lets a `Raw[Int]` through to the ICE path.
  - **Web/Scripting:** (b)  
    Reasoning: the error belongs where the user must make the change. With `let r = Raw(n)` on one line and `{r}` twenty lines later, or a `Raw[Int]` returned from a helper, (a) reports far from the cause. One code (E0534) for "cannot be a template hole" already covers `Raw[Bytes]`, so a new code only adds a name to learn and search for.  
    Concern: the message must say "`Raw` folds only a `Str`" in plain words. If it reads like a generic E0534 hole error at a site with no hole, users will be confused.
  - **PLT:** (b)  
    Reasoning: A check at construction reports at the cause, not at a hole that a binding or a return puts far away. It also leaves no inhabited `Raw[List[Int]]` type that no consumer can use. E0534 keeps one code for every T other than Str, in line with the 6-0 `Raw[Bytes]` ruling. Under (a) or (b), the check must read the static type at typecheck. A `Raw[T]` with T a type parameter is E0534 at the definition, never at mono.  
    Concern: If (a) wins, the spec must still state that a hole of type `Raw[T]` with a generic T fails at the definition. If it does not, the implementation can let the error slip to mono or to codegen, where gen1 ICEs today.
  - **DevOps:** (b)  
    Reasoning: The error lands where the fix is, on the `Raw(...)` call, even when the value goes through a binding. Hover never shows a `Raw[Int]` type that has no legal use. A generic `Raw[T]` fails at its definition and never at a later instantiation. E0534 keeps one code, and one `blink explain` page, for "this type cannot go into a template", consistent with Q6's `Raw[Bytes]`.  
    Concern: E0534's name, TemplateHoleType, reads oddly at a span that is not a hole, so the primary message must say "`Raw` wraps only a `Str`; found `Int`", or users will look for a hole.
  - **AI/ML:** (b)  
    Reasoning: A model fixes the span the diagnostic points to. Construction puts that span on the `Raw(...)` argument, where the fix goes, and not on a hole that may be in another function after a return. No `Raw[Int]` value or annotation can exist, so the type is never inhabited and never dead. Keeping E0534 gives one code to learn and search for "this is not a template value", and it stays consistent with the Q6 `Raw[Bytes]` ruling.  
    Concern: The spec text must change in step: "constructs a `Raw[T]` from a `T`" and "a `Raw[T]` of one" in §3b.5 must become `Raw[Str]`. If one sentence keeps the general `T`, models will read the two rules as a conflict.
  - **Minimalism:** *(dissent)* (a)  
    Reasoning: (a) changes no existing text: §3b.5 already says `Raw(expr)` builds a `Raw[T]` from any T, and the settled `Raw[Bytes]` rule already puts E0534 at the hole. Bytes becomes one case of the general rule, not an exception. (b) adds a well-formedness check on a type parameter that only one type may fill; (c) adds a code for a fault E0534 already names.  
    Concern: an unused or passed-along `Raw[Int]` compiles until it reaches a hole, so the error can show far from the `Raw(...)` call; the spec text must make the E0534 note point back to where the `Raw[T]` came from when it came through a binding or return.

- **Q3: May a help line for this error offer `Raw(...)`?** (6-0) — **No**
  - **Systems:** No  
    Reasoning: "A help line never offers `Raw(...)`" is settled, and it has no exception for "the author already chose Raw". If the help offered `Raw(n.display())`, the compiler would pick the text form, and that choice S exists to leave with the author, in plain sight.  
    Concern: An LLM user who gets only `{n}` may read it as "the compiler did not understand that I wanted folded text", and then hand-build the `Str` anyway, so the `note:` must say plainly that `Raw` takes a `Str`.
  - **Web/Scripting:** No  
    Reasoning: the rule "a help line never offers `Raw`" is short, and an exception makes a question of its own. `{n}` is the better repair in nearly every case because it keeps the value a parameter. A `note:` that states "`Raw` folds only a `Str`" lets a user who truly needs the bypass work it out without the compiler suggesting it.  
    Concern: with no note, a user who truly needs `Raw` for an int (a driver that will not take a parameter in that place) gets stuck. So the note line must state the Str-only fact.
  - **PLT:** No  
    Reasoning: "A help: line never offers Raw(...)" is normative text. With a help that offers `Raw(x.display())`, the compiler picks the text form and keeps an audited bypass that the error had stopped. The W0310 audit would then cover a choice the compiler made, not the author. A `note:` line ("Raw folds only a `Str`") gives the rule and leaves the choice to the author.  
    Concern: Without help, authors who need to splice text may find the path slow. The note text must be clear enough that they do not guess.
  - **DevOps:** No  
    Reasoning: The rule that a help line never offers `Raw` exists so that a type error never ends with a suggestion to bypass. LSP quick-fixes and models apply the help text as given, and `Raw(n.display())` would turn every Int into query text with one click. `{x}` always compiles for a Template value type, and the note-only fallback already covers the other types.  
    Concern: If no help line applies (for example `Raw[List[Int]]`), the user gets a note only, and some will reach for `Raw(xs.debug())` on their own.
  - **AI/ML:** No  
    Reasoning: Models apply the first `help:` line mechanically. `help: Raw(n.display())` would turn each `{Raw(n)}` copied from a nearby table-name hole into an audited injection bypass, where `{n}` was correct. The decided text already says a help line never offers `Raw(...)`. Offering it through `let s = "{x}"` is the same suggestion through a binding. A human who truly needs the text can still write `Raw(n.display())`, and the audit will see it.  
    Concern: A small number of real users who need a non-Str value's text (DDL sizes) will find no help line for it. The §3b.5 prose should show `Raw(n.display())` once as an example, so that this choice stays in plain sight.
  - **Minimalism:** No  
    Reasoning: one rule with no exception is smaller than "never, unless the author already wrote Raw". A help that offers `Raw(n.display())` steers users away from the parameter, which is the safe repair. The author may still write `Raw(x.display())` by hand; that keeps the audit.  
    Concern: for a user type with Display, users who truly need folded text get only `{x.display()}` (a parameter), and may not see the by-hand `Raw(x.display())` route without docs.

- **Q4: `Raw(Raw(s))`, or a `{Raw(r)}` hole with `r: Raw[Str]`** (5-1, Systems dissent) — **H: E0534 with a help that removes one `Raw`**
  - **Systems:** *(dissent)* N  
    Reasoning: The fix is obvious from the note. A help that rewrites to `Raw(s)` is still a help line that offers `Raw`, so N stays consistent with Q3 at no cost.  
    Concern: The note text must name both forms (`Raw(Raw(s))` and `{Raw(r)}` with `r: Raw[Str]`), or the binding case reads as a confusing type mismatch.
  - **Web/Scripting:** H  
    Reasoning: `Raw(Raw(s))` is nearly always a slip, such as a helper that already returns `Raw[Str]`. The fix is clear and mechanical, and "remove the inner Raw" removes a bypass, it does not offer one, so it obeys the Q3 rule. A note-only error makes the user work out a fix the compiler already knows.  
    Concern: if the outer `Raw` is in a hole and the inner one comes from a binding or a return, the help must point at the right `Raw`, or the rewrite will not compile.
  - **PLT:** H  
    Reasoning: Removing a Raw is not offering one, so the help rule allows it, and the repair compiles with the same audit obligation. One edit to the H text: say "remove one `Raw`". For `{Raw(r)}` with `r: Raw[Str]`, the repair drops the outer call (`{r}`), not an inner one.  
    Concern: A tool that applies the help to `Raw(Raw(s))` must make sure the result is still a single `Raw[Str]` hole. It must not remove both calls and turn the bypass into a parameter, which would change the program's meaning.
  - **DevOps:** H  
    Reasoning: A tool can apply "remove the inner Raw" mechanically, and the result always compiles, which is the best case for an LSP. For a binding (`{Raw(r)}` with `r: Raw[Str]`), the same help reads `{r}`. The text is one sentence in the spec.  
    Concern: The help must give `{r}` for the binding case and `Raw(s)` for the inline case. If the implementation picks the wrong form, the quick fix produces a second error.
  - **AI/ML:** H  
    Reasoning: A help line that compiles beats a note-only line for generated code. "Remove the inner Raw" deletes a bypass and adds none, so it keeps the rule behind Q3: no new `Raw` appears. Note-only leaves the model to guess, and it may guess `.display()` or worse.  
    Concern: For the binding form `{Raw(r)}` with `r: Raw[Str]`, the help must rewrite to `{r}`, not to `Raw(r)` or a wrong span. The spec example should show both forms.
  - **Minimalism:** H  
    Reasoning: `help: remove the inner Raw` compiles, adds no bypass (the outer Raw is still audited), and costs one help line. It is a mechanical fix the compiler can state with certainty.  
    Concern: for the binding case (`{Raw(r)}` with `r: Raw[Str]`) the help must say "write `{r}`", not "remove the inner Raw", or the text will not match the source.

No question was closer than 5-1, so Phase D did not run. The user signed off on the tally with the two dissents recorded.

#### AI-First Review

Learnability, Consistency, Generability, Debuggability and Token Efficiency all pass (5/5). The rule is one sentence ("`Raw` wraps only a `Str`"), it uses the existing code E0534, the span is where the fix goes, and the safe form `{n}` is shorter than `{Raw(n)}`.

### Final Spec

```blink
fn page(n: Int, table: Str) -> Result[List[Row], DBError] ! DB.Read {
    db.query(t"SELECT * FROM {Raw(table)} LIMIT {n}")   // Raw wraps a Str; n stays a parameter
}

fn make_table(name: Str, width: Int) -> Result[Int, DBError] ! DB.Write {
    let w = width.display()                            // the author writes the text form
    db.execute(t"CREATE TABLE {Raw(name)} (title VARCHAR({Raw(w)}))")
}
```

- **Only `Str` (Q1):** `Raw(e)` requires `e: Str`; the fold text is the string, byte for byte. No type needs a fold-text rule.
- **Checked at construction (Q2):** any other type of `e` is `error[TemplateHoleType]` (E0534) at the argument. A written `Raw[X]` with `X` not `Str` is E0534 at the annotation, in every place a type is written. A generic `Raw(x)` with `x: T`, or `-> Raw[T]`, fails at the definition, never at mono. No `Raw[X]` with `X` other than `Str` can exist. The primary message says "`Raw` wraps only a `Str`, found `X`". `Raw[Bytes]` is one case of this rule; its help stays `{b}` and its span moves to the argument.
- **No help offers `Raw` (Q3):** help lines remove the `Raw` and apply the *Template Values* repairs (`{n}`, `{p.display()}`, a field, `let r = n` in a binding), or give the `note:` only.
- **`Raw` of a `Raw[Str]` (Q4):** E0534 with `help: remove one Raw`: `{Raw(Raw(s))}` → `{Raw(s)}`, and `{Raw(r)}` → `{r}`. The repair keeps exactly one `Raw[Str]`.
- The spec shows `Raw(n.display())` once, for DDL, and says a non-`Str` value stays a parameter.

Amends [TemplateValue Bytes](template-value-bytes.md) Q6: the `Raw[Bytes]` span moves from the hole to the `Raw(...)` argument; the code and help are unchanged. §3b.5, §2.4.3, §3.6, §9.1.
