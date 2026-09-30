[< All Decisions](../DECISIONS.md)

# Template Surface — Design Rationale

### Problem Statement

Three spec gaps in §3b.5 had one root: the spec and the compiler disagreed on what a `Template[C]` is.

- The spec declared `Template[C]` as a struct whose `values` field has type `List[Any]`. The no-surface-any rule ([under-determined-types.md](under-determined-types.md), Q2) says no program can name `Any`.
- The spec showed two public fields. The compiler and stdlib ship a seven-method API (`parts`, `count`, `type_tag`, `get_*`) and `TPL_*` integer tags.
- The spec said "`C` is inferred from the surrounding effect context". The compiler takes `C` from the expected parameter type, and an effect name such as `DB` in `Template[DB]` resolved by accident, not by a rule.

This ruling amends [template-type-design.md](template-type-design.md) (the decomposed, phantom-typed design stays) and makes its Key Design Points current.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds, then one focused round (Phase D) that the user added. Each panelist text below is the panelist's file, verbatim; only heading levels are shifted.

#### Phase A — Independent proposals

<details>
<summary><b>Systems</b></summary>

### Systems panelist, Phase A: proposals for `Template[C]`

The question I ask of every design: what does the handler's loop compile to? Today each value costs two `blink_list` pushes: one list of `void*` words and a second, parallel list of tags. Each getter checks the tag at runtime and can panic. So the tag is checked twice, once by the handler's `if` chain and once again inside the getter. The spec's `List[Any]` would be worse: it needs a box and RTTI per value, which is exactly what 8vcj2c ruled out.

#### Proposal S1: a sealed value enum, with methods as the normative surface (8qewfn, fqy7bz)

**Rule.** `Template[C]` is a compiler-known **opaque** type, not a struct with fields. Its normative surface is three methods:

- `parts() -> List[Str]`
- `count() -> Int`
- `value(i: Int) -> TemplateValue`

`TemplateValue` is a compiler-known, closed prelude enum:

```blink
type TemplateValue {
    Int(Int),
    Float(Float),
    Bool(Bool),
    Str(Str),
}
```

The invariant becomes `t.parts().len() == t.count() + 1`. `type_tag`, `get_*` and `TPL_*` are removed through the 3-step path: add `value`, migrate `db_sqlite`, then delete the old surface. `List[Any]` leaves the spec, and the 8vcj2c ruling stands unamended.

**Handler:**

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let mut i = 0
    while i < tpl.count() {
        let rc = match tpl.value(i) {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i + 1, n),
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i + 1, f),
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i + 1, if b { 1 } else { 0 }),
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i + 1, s),
        }
        if rc != 0 { return rc }
        i = i + 1
    }
    0
}
```

**Call site:** unchanged, `db.query_one("SELECT * FROM users WHERE id = {id}")`.

**What it compiles to.** Each value is `struct { int64_t tag; union { int64_t; double; const char*; } }`, 16 bytes and no box. Store the values as one flat array sized to `count`, which is known at the literal site. That is one allocation instead of two growable lists. `match` becomes a jump table with one tag read. A wrong-kind getter can no longer panic, and the match is checked for exhaustiveness at compile time.

**Tradeoffs.**
- It is a closed set. Adding a variant later breaks every exhaustive handler `match`, so the set must be right now (see S2).
- It is not a user-extensible protocol. That is intended: a Display-based protocol throws away the type the driver needs (the display-format decision Q3, 5-0).
- I reject a `values() -> List[TemplateValue]` accessor. It forces a list allocation for each call, where indexed `value(i)` costs nothing extra.

**Cross-language.** C# `FormattableString.GetArguments()` returns `object[]`, which means boxing, and that is what we avoid. Python 3.14 `Interpolation.value` is dynamically typed. Rust `fmt::Arguments` is opaque and erased through trait objects. A closed tagged union is closest to the driver-level binding APIs (libpq, sqlite3_bind_*), where the enum lands.

**Keeps:** the template-type design decisions (decompose, handler reassembles, phantom); the display-format decision Q3 ("compiler-known param type set"); 8vcj2c; Raw.
**Amends:** §3b.5's `type Template[C] { parts; values }` block and "Why structural type" paragraph. The structure becomes observable through methods, not fields. Say explicitly that a user phantom declaration may copy the `[C]` form but not the field list.

#### Proposal S2: the hole set is enforced at typecheck (fqy7bz Q3, §3.1)

**Rule.** A `Template[C]` hole must have one of these types:

| Hole type | Maps to |
|---|---|
| `Int`, `I8`, `I16`, `I32`, `U8`, `U16`, `U32` | `.Int` (widened, lossless) |
| `F32`, `Float` | `.Float` |
| `Bool` | `.Bool` |
| `Str` | `.Str` |
| `Raw[T]` | folded into the parts |

Any other type is a **typecheck** error, `TemplateHoleType`. Its first repair must compile, per §3.1: "convert explicitly, e.g. `{p.to_str()}`". The result is still a parameterized `Str` value, not a concatenation. Today a Display struct passes typecheck and then reaches ICE I0004, and this rule removes that.

- **`U64`** is excluded. It does not fit in `Int` without loss, and a silent wraparound in a bound DB parameter is a correctness bug. The repair is an explicit conversion.
- **`Char`** is excluded rather than silently turned into a string. The repair is `.to_str()`.

**Open, for the panel:** do `Option[scalar]` → a `Null` variant and `Bytes` → a `Bytes` variant belong in the set? SQL NULL and BLOB are real driver needs. Adding them after release breaks exhaustive matches, so decide now, not later. I lean yes on both: each is one more union arm and costs nothing.

#### Proposal S3: the phantom is a nominal type-namespace reference (kfefsy)

**Rule.** The spec already says effects share the type namespace (§7 line 2024; the builtin-type-name-shadowing decision). So `resolve_type_ann` must resolve an effect name in a type position to a **nominal effect-reference type**. `Template[DB]` and `Template[Shell]` are then distinct, compared by declaration identity and invariant in `C`. This is a compiler bug fix to match the spec, not new language. A dedicated phantom namespace (option 2) would add a fourth namespace to fix what is really a resolution bug, so I reject it.

**`C` as a type parameter** of the enclosing fn is ordinary generics over contexts:

```blink
fn log_and_run[C](t: Template[C]) -> Int { t.count() }
```

**Cost:** the phantom is erased, so every `Template[C]` has the same layout. Mono must share one instance of the body across all `C`, so contexts cause no code bloat. I want that stated as normative.

**Keeps:** the 4-1 phantom decision, "cannot pass" (it becomes true), and the 6-0 ruling that phantoms are legal in user code. **Amends:** nothing. The decision text's claim that the phantom "is inferred from the surrounding effect context" is really inference from the parameter's expected type, and should say so.

#### Sub-questions for a vote

1. Is the surface methods-on-an-opaque-type (S1) or fields? And is `value(i) -> TemplateValue` accepted, with `type_tag`, `get_*` and `TPL_*` retired?
2. Which types are in `TemplateValue`? Four scalars only, or also `Null` (from `Option`) and `Bytes`?
3. Is a hole outside the set a typecheck error with an explicit-conversion repair (S2)? And are `U64` and `Char` excluded, or converted?
4. Do effect names in type position resolve nominally (S3), or is a separate phantom namespace used?
5. Is `Template[C]` with `C` a type parameter generic over contexts? And is one mono instance shared across all `C` normative?

</details>

<details>
<summary><b>Web/Scripting</b></summary>

Web/Scripting panelist, Phase A. I have two proposals. They are separable, and each could go to its own vote.

#### W1: `values()` returns a compiler-known `TemplateArg` enum, and methods are the normative surface (8qewfn, fqy7bz)

**Rule.** `Template[C]` is opaque. You get at it through methods only: `parts() -> List[Str]`, `values() -> List[TemplateArg]` and `count() -> Int`. `TemplateArg` is a closed, compiler-known enum (a sealed enum whose variants the compiler fixes):

```blink
type TemplateArg { Int(Int), Float(Float), Bool(Bool), Str(Str), Null }
```

The spec already fixes the set of hole types, at sections/03_types.md:3155: "`Int`, `Float`, `Str`, `Bool`, `Option[T]`". Nobody in the brief cited this line. `Option[T]` becomes the inner variant when it holds a value and `Null` when it holds none. Sized integers widen to `Int`, as codegen does today. Typecheck rejects any other hole type (struct, `List`, `Char`, `U64`) with its own diagnostic, which offers repairs that compile:
- interpolate a field;
- stringify explicitly with `{p.to_str()}`;
- use `Raw(...)`.

Today a struct hole passes typecheck and then fails at codegen. That breaks §3.1, and this rule fixes it. `List[Any]` leaves the spec, and `type_tag`, `get_*` and `TPL_*` are removed through the 3-step migration.

Handler:

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let mut i = 0
    for v in tpl.values() {
        i = i + 1
        let rc = match v {
            TemplateArg.Int(n) => sqlite_bind_int(stmt, i, n),
            TemplateArg.Float(f) => sqlite_bind_double(stmt, i, f),
            TemplateArg.Bool(b) => sqlite_bind_int(stmt, i, if b { 1 } else { 0 }),
            TemplateArg.Str(s) => sqlite_bind_text(stmt, i, s),
            TemplateArg.Null => sqlite_bind_null(stmt, i),
        }
        if rc != 0 { return rc }
    }
    0
}
```

Call site (unchanged):

```blink
fn find(id: Int, nick: Str?) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one("SELECT * FROM users WHERE id = {id} AND nick IS {nick}")
}
```

**Tradeoffs (DX).**
- A TS or Kotlin developer knows a discriminated union plus `match` at once. A magic `Int` tag plus four getters that check the tag at runtime is C-style, and it generates bugs. We already have one: `blink llms` documents the tags as 1..4, but the runtime uses 0..3. Anyone who copied the doc has a broken handler now.
- Exhaustive `match` means that if the set ever grows (`Bytes`, `Instant`), the compiler lists every handler that needs a new arm. A tag `if/else` chain drops the new type silently.
- **Methods, not fields.** A pub struct with pub fields can be built with a struct literal: `Template[DB] { parts: [user_input], values: [] }`. That brings back the laundering that E0310 exists to stop. Only the literal coercion may build a `Template`. Methods also fit Blink, which has no index operator.
- Cost: the handler allocates one enum per value. A driver does a network round trip per query, so this cost does not matter.
- `TemplateArg` is compiler-known, so hygiene (§3.1681) protects its variant names `Int` and `Str` from user shadowing.

**Cross-language.** Python 3.14 `Template.values` and `Interpolation`, JS `strings`/`values`, C# `GetArguments()`. All three give the handler a walkable list of values. Ours is typed, not `object`/`any`.

**Constraints.**
- Keeps: no surface `Any` (8vcj2c Q2); handler reassembles; Display is Str-context only (display-format Q3, "compiler-known param type set", which this proposal makes concrete); `Raw` semantics.
- Amends: the struct declaration in the §3b.5 text and in decisions/template-type-design.md. The "structural" design survives as "decomposed and introspectable", not as "public fields".

#### W2: The phantom resolves nominally, and an unresolved name is an error (kfefsy)

**Rule.** This needs no new namespace, because the spec already settles it. sections/07 (line 2024) and decisions/builtin-type-name-shadowing.md put `effect` names in the type namespace. So:
- `Template[DB]` names the effect `DB` nominally.
- `Template[DB]` and `Template[Shell]` are distinct types, as §3b.5:566 promises.
- The compiler turning `DB` into a type variable is a conformance bug, not a spec question.

Two further rules:
1. Blink declares type parameters explicitly (`fn f[T]`). A name inside `Template[...]` that resolves to no type, effect or declared type parameter is an unknown-type error. It must never silently become a typevar, or the typo `Template[Db]` turns off the protection without any message.
2. `Template[C]`, where `C` is a declared type parameter of the enclosing fn, is ordinary generic code. For example, `fn log_query[C](t: Template[C]) -> Template[C]` forwards any context without changing it. This is not a hole: `C` binds at the call, invariantly.

```blink
pub effect Shell { effect Run { fn run(cmd: Template[Shell]) -> Int } }

fn go(q: Template[DB]) -> Int ! Shell.Run {
    shell.run(q)   // error[E0310]: expected Template[Shell], found Template[DB]
}
```

**Tradeoffs.** Users write `Template[DB]` because the effect is called `DB`. Options 3 and 4 in the ticket would make them declare a marker `type DB {}` beside the effect, or remove the promise altogether. Either one generates Stack Overflow questions ("why do I need an empty type?"), and option 4 removes the safety the feature is sold on. The phantom-namespace option (option 2 in the ticket) invents a third namespace for one type, which is too clever.

**Cross-language.** TypeScript branded types work only because the brand is a real, resolvable name, and a misspelled brand is an error. We want the same behaviour.

**Constraints.** Keeps the 4-1 phantom decision, 8w0yj9 (phantoms legal in user code) and §3.1. Amends nothing in the spec. It only strikes the "inferred from the surrounding effect context" wording in template-type-design.md:57, because `C` comes from the declared parameter type, not from inference.

#### Sub-questions the panel must vote on

1. Normative surface: methods only (opaque type, no struct-literal construction) or public fields?
2. How values are represented: a compiler-known `TemplateArg` enum, or keep `type_tag` plus getters (and, if so, which tag numbering)?
3. The hole-type set: confirm 03_types.md:3155 (`Int`/`Float`/`Str`/`Bool`/`Option[T]`, sized ints widen). Is it closed at typecheck, with its own diagnostic?
4. Phantom resolution: effect names resolve nominally in `Template[...]` (spec as written), or real marker types, or a phantom namespace?
5. Is an unresolved phantom name an error, not a silent typevar?
6. Is `Template[C]` with a declared fn type parameter `C` sanctioned as generic forwarding?

</details>

<details>
<summary><b>PLT</b></summary>

**PLT panelist — Phase A proposals**

The root claim behind all three proposals is that `Template[C]` is an abstract type. Its only introduction form is the interpolated-literal coercion (plus `Raw` folding). Once that is fixed, the other rulings follow from it.

---

**P1. Abstract type with observers only, no fields (fqy7bz Q1, 8qewfn)**

*Rule.* `Template[C]` is opaque. User code cannot construct it with a struct literal and cannot reach its fields. It has these observers:

```
parts(self)  -> List[Str]
values(self) -> List[TemplateValue]
count(self)  -> Int
```

The invariant is `t.parts().len() == t.count() + 1` and `t.values().len() == t.count()`.

*Why this is a soundness question.* The spec's field form lets anyone write `Template[DB] { parts: [user_input], values: [] }`. That is a second introduction form, and it launders a runtime `Str` into the literal segments. It gets around E0310 completely, with no `Raw` and no audit. The E0310/`Raw` design is only sound if the parts come from compile-time literal text. A record type with public fields cannot uphold that invariant, but an abstract type can. So I reject fields in any form, and I call this out because users will copy the declaration.

*Amends:* the §3b.5 struct text and "Key Design Points". *Keeps:* decomposition, handler reassembly, and Display being Str-context only (5-0).

**P2. A closed sum type for values, which replaces `List[Any]` and `type_tag` (8qewfn, fqy7bz Q2/Q3)**

*Rule.* The compiler knows this enum, and user code cannot extend it:

```blink
type TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str) }
```

*Typing rule for the coercion (checking mode only):*

```
expected = Template[C],   for each i:  Γ ⊢ eᵢ : Tᵢ,  Tᵢ ∈ Interp  or  Tᵢ = Raw[U]
────────────────────────────────────────────────────────────────
Γ ⊢ "s₀{e₁}s₁…{eₙ}sₙ" ⇐ Template[C]
```

Here `Interp = {Int, I8, I16, I32, U8, U16, U32, Float, Bool, Str}`. The narrow integer types widen to `Int`. The literal never *synthesizes* `Template`, and `C` comes only from the expected type. If a hole's type is outside `Interp`, typecheck reports a new diagnostic, `TemplateHoleType`, with a repair that exists: convert explicitly (`{p.id}`, `{c.to_str()}`) or wrap in `Raw`. This closes today's §3.1 violation, where a Display struct passes typecheck and then hits ICE I0004.

*Handler side:*

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[Sql]) -> Int {
    let mut i = 0
    for v in tpl.values() {
        i = i + 1
        let rc = match v {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i, s)
        }
        if rc != 0 { return rc }
    }
    0
}
```

*Tradeoffs.* The integer tag plus four getters is a sum encoded by hand, and it loses exhaustiveness. The in-tree handler silently binds nothing when it meets a tag it does not know (`rc` stays 0). With the enum, a new variant makes every handler fail with E0004, which is what we want. The set is closed on purpose: a hole must have a type the driver can bind, and there is no top type (8vcj2c Q2 holds, with no amendment). Heap-free scalars stay unboxed in the payload.

*Cross-language.* C#'s `GetArguments()` returns `object[]`, the top type we refuse. Python's `Interpolation.value` is dynamically typed. OCaml's `Format` GADTs give the typed precedent. We take the first-order version: a closed ADT.

*Migration:* 3-step. Add `values()` and `TemplateValue`, move db_sqlite over, then retire `type_tag`/`get_*`/`TPL_*`.

**P3. The phantom is an ordinary type-kinded parameter; context markers are types (kfefsy)**

*Rule.* `C` is an ordinary type parameter of kind `Type`. It is resolved in the type namespace, it is invariant, and identity is the resolved declaration, qualified by module. Comparing by name only (ticket option 2) is unsound, because two modules can each declare `DB`. An effect name used as `C` is a kind error: "expected a type, found effect `DB`". The error comes with a working repair: declare a marker type such as `type Sql {}`. Stdlib re-spells `Template[DB]` as `Template[Sql]` and `Template[Shell]` as `Template[Sh]`.

*Why type-kinded and not effect-kinded (as `Handler[E]` is):*
1. The phantom indexes the **object language** (SQL, sh, HTML). It does not index the capability. HTML escaping is pure, so it should not need an effect declared only to name it.
2. The phantom gives no authority. Any code can coerce a literal to `Template[C]` for any `C` it can name, so tying `C` to an effect adds no security.
3. Generic helpers stay legal in v1. `fn f[C](t: Template[C])` is plain parametric polymorphism, and under mono each instance stays distinct. With an effect-kinded `C`, that would need effect-kinded generics, which §4.7.1 defers to v2.
4. It is exactly the 8w0yj9 mechanism with no special case.

*Required regardless of the kind choice.* A free, unbound name in type position must be an error, not an implicit `make_typevar`. That silent fallback is what actually makes the check vacuous: a type variable may only come from a binder. Also, the §3.1 example `type Template[C] { source: Str }` shadows the builtin (W1010). Rename it (say `Query[C]`) so we do not teach users to shadow.

*Amends:* template-type-design.md's "C is inferred from the surrounding effect context". It becomes "C is fixed by the expected parameter type". Also the spec's `Template[DB]`/`Template[Shell]` spellings. *Keeps:* the phantom, erasure, and the "cannot pass" sentence, which becomes true.

*Alternative (P3′), for the vote:* make `C` effect-kinded like `Handler[E]`, restricted to top-level effects, with no subsumption through the effect lattice. This keeps the `DB` spelling, but it makes `fn f[C](t: Template[C])` a kind error until v2, and it forces pure contexts to declare an empty effect.

---

**Sub-questions the panel must vote on**

1. Is `Template[C]` abstract (observers only, literal coercion as the only constructor)? Or does it expose constructible fields?
2. Values surface: closed `TemplateValue` enum with `values()`? Or keep integer tags and typed getters?
3. Interpolatable set: exactly {Int family, Float, Bool, Str}? Should it also include `Bytes` and/or a `Null`/`Option` variant now, since adding a variant later breaks handlers?
4. Should an out-of-set hole type get a typecheck diagnostic (`TemplateHoleType`) in place of today's codegen ICE?
5. Kind of `C`: type-kinded markers (P3), or effect-kinded like `Handler[E]` (P3′)?
6. Should an unbound name in type position be an error everywhere, not an implicit type variable? (This is a soundness fix. I hold that it needs no vote, but I record it here.)
7. Should the §3.1 phantom example be renamed so it does not shadow the builtin `Template`?

</details>

<details>
<summary><b>DevOps</b></summary>

**DevOps/Tooling panelist: Phase A proposals**

My test for each option: what does the error say, can the LSP complete it, and what does `blink fmt` do with it. The current surface fails that test in three places. The spec shows a field that does not exist. The value type is a magic `Int` tag with an unchecked `if` chain. And a typo in the phantom (`Template[Db]`) silently turns into a type variable and gives no error at all.

---

##### P1: Methods are normative, and values are a compiler-known sealed enum (8qewfn, fqy7bz Q1–Q2)

**Rule.** `Template[C]` is an opaque compiler-known type. Its whole surface is two methods: `parts() -> List[Str]` and `values() -> List[TemplateValue]`. `TemplateValue` is a compiler-known sealed enum with one variant per carried kind: `Int(Int)`, `Float(Float)`, `Bool(Bool)`, `Str(Str)`. `count()` stays as a shorthand for `values().len()`. `type_tag`, `get_*` and `TPL_*` are retired, using the 3-step migration. The spec replaces its struct declaration with a signature block, so no `List[Any]` is left for users to copy. The invariant `parts().len() == values().len() + 1` is stated in these spellings.

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let vals = tpl.values()
    let mut i = 0
    while i < vals.len() {
        let rc = match vals.get(i).unwrap() {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i + 1, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i + 1, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i + 1, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i + 1, s)
        }
        if rc != 0 { return rc }
        i = i + 1
    }
    0
}
```

Main misuse, a handler that forgets a kind:

```
error[E0004]: non-exhaustive match on `TemplateValue`
  = note: missing variant `TemplateValue.Str`
  = help: add an arm `TemplateValue.Str(s) => ...`
```

**Tradeoffs.**
- Exhaustiveness is the reason to do this. Today a handler that skips `TPL_STR` binds nothing and fails at run time with no signal. With the enum, adding a variant later (for example a SQL `Null`) makes every handler fail to compile until it handles the new kind. That is correct, and it is what we want.
- The LSP completes `TemplateValue.` for free. It cannot complete a magic `0..3`.
- Methods, not fields: field access (`t.parts`) would imply the fields can be set and that a user can build a `Template` with a struct literal. Either would let a caller break the invariant.
- Cost: one more compiler-known name in the prelude.

**Cross-language.** Python 3.14 `Interpolation.value` is `object`, which is the thing we cannot have. C# `GetArguments()` returns `object[]`, the same problem. Rust's `serde_json::Value` shows that a closed enum is the idiomatic answer in a language without a top type.

**Keeps** 8vcj2c Q2 (no surface `Any`), Display Q3 (raw typed values, compiler-known param set), and decomposition done in the handler. **Amends** the §3b.5 "Why structural type" text and template-type-design.md, from "`.parts` + `.values` fields" to method spelling. Decomposition is unchanged; only the spelling changes.

---

##### P2: Hole types are closed at typecheck (fqy7bz Q3)

**Rule.** A hole in a `Template[C]` coercion must have one of these types:
- `Int`
- `I8`, `I16`, `I32`, `U8`, `U16`, `U32` (widened to `Int`)
- `Float`
- `Bool`
- `Str`
- `Raw[T]` (folded into the text)

Any other type is a **typecheck** error at the hole and never reaches codegen. This fixes today's §3.1 breach, where a Display struct passes typecheck and then hits ICE I0004.

```blink
fn find(p: Point) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one("SELECT * FROM pts WHERE p = {p}")
}
```

```
error[TemplateHoleType]: `Point` cannot be a Template parameter
 --> geo.bl:2:47
  |
2 |     db.query_one("SELECT * FROM pts WHERE p = {p}")
  |                                               ^ `Point` is not Int, Float, Bool or Str
  |
  = help: send it as a string parameter: `{p.to_str()}`
  = help: or bind its fields: `... x = {p.x} AND y = {p.y}`
```

Both repairs compile, as §3.1 requires. `Char`, `U64` and `Option` get the same error, each with its own hint: `.to_str()`, a checked conversion to `Int`, or an explicit `match`.

**Tradeoff.** The rule is strict, but it is honest. The alternative, sending a struct through Display to a string, is exactly the lossy path Display Q3 rejected 5-0.

---

##### P3: The phantom resolves in the type namespace, effects included, and never makes an implicit type variable (kfefsy)

**Rule.** The spec already says effects share the type namespace (sections/07:2024, builtin-type-name-shadowing.md). The compiler is the part that disagrees. Fix the compiler, not the spec:
- `C` in `Template[C]` resolves to a declared type, effect, or in-scope type parameter.
- Comparison is nominal on the resolved declaration, so `Template[A]` and `Template[B]` from two different effects are distinct.
- An unresolved name is **E-unknown-type**, not a fresh type variable.
- A declared type parameter (`fn log[C](t: Template[C])`) is generic over contexts, which is a legitimate use (a tracing wrapper, for example).
- A sub-effect (`Template[DB.Read]`) is an error that points to the parent effect `DB`. This keeps one spelling per context.

```
error[E0310]: type mismatch
  |     sink(t)
  |          ^ expected `Template[DB]`, found `Template[Shell]`
  = note: the context parameter prevents a Shell template from reaching a DB handler
```

```
error[UnknownType]: no type or effect named `Db`
  |     fn query(sql: Template[Db]) -> ...
  |                            ^^ help: did you mean effect `DB`?
```

**Tradeoff.** The typo case is the one that matters to me. Today it compiles clean and turns off the protection. A new "phantom namespace" (ticket option 2) would give the LSP a third namespace to model and give hover nothing to jump to. Resolving to the real effect gives go-to-definition on `DB` at no extra cost.

**Keeps** the 4-1 phantom decision (the "cannot pass" sentence becomes true), phantom erasure, and the 8w0yj9 ruling that user phantoms are legal. **Amends** template-type-design.md line ~57: `C` is *not* inferred from the surrounding effect context. It comes from the declared parameter type. The spec text should say that.

**Fmt:** none of the three proposals adds syntax, so `blink fmt` is unaffected.

---

##### Sub-questions the panel must vote on

1. Is the Template surface fields or methods? (I propose methods.)
2. Values: a sealed `TemplateValue` enum, or a spec of the current tag and getters?
3. Is the set of hole types closed at typecheck? Which types are in it, and are sized ints widened or rejected?
4. Does the phantom resolve to effects through the existing shared type namespace, or to marker types only?
5. Is an unresolved phantom name an error, or an implicit type variable?
6. Is `Template[DB.Read]` legal, and if so, is it distinct from `Template[DB]`?
7. Should `TemplateValue` reserve a `Null` variant now for `Option` holes, or wait until there is a need (YAGNI)?

</details>

<details>
<summary><b>AI/ML</b></summary>

**AI/ML panelist, Phase A proposals**

My lens: the spec is what a model learns from. Today the spec shows one surface (fields, `List[Any]`) and the one working handler uses another (a numeric tag plus four getters). Any model that writes a handler from the spec will write code that does not compile. The fix has to leave one spelling that is learnable from the spec alone.

---

##### P1: Opaque `Template[C]` with `parts()` and `values()`, where `values()` returns a closed enum (8qewfn, fqy7bz)

**Rule.** `Template[C]` is a compiler-known **opaque** type, on the same terms as `Instant` and `MsgFlags`: it has no public fields and no user-callable constructor. Only the decomposition of an interpolated literal at a `Template[C]` site creates one. It exposes three methods:

- `parts() -> List[Str]`
- `values() -> List[TemplateValue]`
- `count() -> Int`

`TemplateValue` is a compiler-known enum:

```blink
type TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str) }
```

The invariant becomes `t.parts().len() == t.values().len() + 1`. `type_tag`, `get_*` and `TPL_*` are removed: they go through the 3-step dance and leave no public surface. `List[Any]` leaves the spec, and 8vcj2c Q2 stands unamended.

Handler:

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let vals = tpl.values()
    let mut i = 0
    while i < vals.len() {
        let rc = match vals.get(i).unwrap() {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i + 1, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i + 1, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i + 1, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i + 1, s)
        }
        if rc != 0 { return rc }
        i = i + 1
    }
    0
}
```

Call site, unchanged:

```blink
db.query_one("SELECT * FROM users WHERE id = {id}")
```

**Why opaque and not fields.** Blink has no rule for private fields. Public fields would give a public constructor, and then `Template { parts: [user_input], values: [] }` would launder a `Str` past E0310 and past the `RawBypassesParam` audit gate. Methods close that hole with no new visibility feature.

**Tradeoffs (my domain).**
- *Generability.* An exhaustive `match` over a closed enum is the pattern models produce best. A magic-int `if` chain over `TPL_*` is the pattern they get wrong: a missing arm, the wrong constant, a getter that does not match its tag. The enum turns those mistakes into compile errors. The tag design adds 4 decision points and 4 imported names. The enum adds one type.
- *Token cost.* About the same as the tag chain, and shorter once you count the `TPL_*` import.
- *Learnability.* `parts` + `values` matches JS `strings[]/values[]` and Python 3.14 `.strings/.values`, the patterns with the most training data. The only difference is the `()`. The field-on-method diagnostic must carry `help: call it: t.values()`, because models will write `.values` first.
- *Cost.* Removing the getters touches the one in-tree handler. `values()` allocates a list. That is acceptable for a DB call.

**Cross-language.** C# `GetArguments()` returns `object[]`, which is exactly the top type we rejected. The Rust-style closed enum is the monomorphization-friendly answer.

---

##### P2: Hole types = the `TemplateValue` set, checked at typecheck (fqy7bz Q3)

**Rule.** A hole at a `Template[C]` site must have a type that maps to a `TemplateValue` variant:

| Hole type | Maps to |
|---|---|
| `Int`, and every signed or unsigned integer width that widens without loss (I8–I32, U8–U32) | `Int` |
| `Float` | `Float` |
| `Bool` | `Bool` |
| `Str` | `Str` |
| `Raw[T]` | folded into the parts, as today |

Any other type is a new typecheck error, `TemplateHoleType`. Its first `help:` is a repair that compiles:

- `{c.to_str()}` for Char or a type with Display
- `{Raw(x)}` if the value is known safe

The error does **not** say "implement Display". Display is Str-context only (5-0), so Display was never the right gate here. This removes today's §3.1 violation, where a program passes typecheck and then hits ICE I0004 in codegen.

**Open point.** Adding a variant later (Bytes, a NULL/Option) breaks every exhaustive handler `match`. We should decide now whether `Bytes` (DB BLOBs) and SQL NULL belong in v1. My vote: add `Bytes` now. Defer NULL; it needs its own ruling.

---

##### P3: The phantom is nominal, a type or an effect; an undeclared name is an error (kfefsy)

**Rule.** The spec already puts effects in the type namespace (§7, builtin-type-name-shadowing). So `Template[DB]` resolves `DB` to the effect declaration and compares it nominally. This is ticket option 1, but it is a **compiler fix to match the existing spec**, not a new rule.

Separately, a name in a type annotation that resolves to nothing, and is not a declared `[T]` binder, is an unknown-type error. It is never a fresh type variable. The silent typevar fallback is the root bug, and it has effects beyond Template.

A declared binder is generic over contexts, with invariant `C`:

```blink
fn log_sql[C](t: Template[C]) -> Str { t.parts().join("?") }
fn cross(t: Template[Shell]) -> Int { db.execute(t) }  // error: expected Template[DB], found Template[Shell]
```

I would also strike the decision note that `C` "is inferred from the surrounding effect context". `C` comes from the expected type only. One rule is easier to learn than two.

**Why not marker types (option 3).** Every spec example and every in-tree effect op writes `Template[DB]` with the effect's name. The model will copy that spelling. Keeping it valid and enforced costs nothing to learn.

**Why not advisory (option 4).** A sentence in the spec that the compiler does not enforce teaches models a false rule.

**Kept:** template-type-design Q1–Q3, Display 5-0, 8vcj2c Q2, phantom-legal 6-0, Raw rules, E0310.

**Amended explicitly:** the `type Template[C] { parts, values }` declaration in §3b.5 and in template-type-design.md, which become an opaque type with methods.

---

##### Sub-questions the panel must vote on

1. Normative surface: fields, methods, or opaque type with methods (P1)?
2. Value representation: a closed `TemplateValue` enum, or tag + getters (spec the tags)?
3. Hole-type set: the four scalars only, or also `Bytes`? When is NULL/Option handled, and how?
4. Is a non-member hole a typecheck error (`TemplateHoleType`) with a `.to_str()`/`Raw` repair?
5. Phantom: an effect name resolves nominally (spec as written), or marker types only?
6. Does an undeclared name in a type annotation become an error everywhere, retiring the typevar fallback?
7. `Template[C]` with a declared binder `C`: allowed, generic over contexts, invariant in `C`?

</details>

<details>
<summary><b>Minimalism</b></summary>

**Minimalism panelist: Phase A proposal for the `Template[C]` surface (8qewfn, fqy7bz, kfefsy)**

I find no new concept needed for any of the three tickets. The fixes remove things: `Any`, five of the seven methods, four magic Int constants, a namespace exception, and one sentence in the spec that contradicts itself.

---

##### Proposal M1: A closed value enum and two methods (8qewfn and fqy7bz)

**Rule.** `Template[C]` is an opaque, compiler-known type with exactly two methods: `parts() -> List[Str]` and `values() -> List[TemplateValue]`. `TemplateValue` is a compiler-known closed enum:

```blink
type TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str) }
```

The invariant `t.parts().len() == t.values().len() + 1` is normative. `type_tag`, `get_int`, `get_float`, `get_bool`, `get_str`, `count` and `TPL_*` are removed. `count()` is the same as `values().len()`. The spec's struct-with-fields block is replaced by these two signatures. The fields stay non-public on purpose: if a user could write `Template[DB] { parts: [user_input], ... }`, that would bypass the E0310 laundering rule.

**Hole typing.** An interpolation hole in a `Template[C]` literal must have type Int, Float, Bool or Str. Narrow integers (I8..U32) widen to Int. Any other type is a typecheck error, `TemplateHoleType`, and the first repair it offers compiles: `{p.display()}`, which interpolates as a Str value, or `{Raw(p)}`. Display is not consulted, which matches the 5-0 ruling that Display belongs to Str context only. This removes today's §3.1 violation, where a struct passes typecheck and then fails with an ICE in codegen.

```blink
fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let vals = tpl.values()
    let mut i = 0
    while i < vals.len() {
        let rc = match vals.get(i).unwrap() {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i + 1, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i + 1, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i + 1, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i + 1, s)
        }
        if rc != 0 { return rc }
        i = i + 1
    }
    0
}
// call site: unchanged
db.query_one("SELECT * FROM users WHERE id = {id}")
```

**Tradeoffs.**
- The hand-made sum type becomes a real sum type.
- Exhaustive `match` takes the place of an `if` chain that fails silently when a new tag appears.
- No `Any`, so 8vcj2c stays intact.
- The runtime already stores a tag and a value per slot. Lowering is a relabel, not a redesign.

The cost is that adding a variant later (for example `Null` or `Bytes`) breaks every handler's exhaustive match. I accept this: the break is loud, and that is correct for an injection boundary. I reject adding "any Display type" or "any T" as holes. Either one needs RTTI or a boxed trait object, which 8vcj2c already refused. YAGNI: SQL NULL can wait until a real handler needs it, and then it is one variant plus one vote.

**Cross-language.** C#'s `GetArguments()` returns `object[]`, and Python's `Interpolation.value` is untyped. Both depend on a top type that Blink has chosen not to have. JS tagged templates are the same. Go's `database/sql` limits its driver values to a small closed set (`driver.Value`), and that is the model here.

**Constraints.** Keeps 8vcj2c Q2, the Display 5-0 ruling (the "compiler-known param type set" is now named), and decomposed parts plus values (3-2). Amends the spec text at §3b.5 lines 428-432 and Key Design Points. The *spirit* of the decomposition decision is kept; only its *spelling* changes.

---

##### Proposal M2: The phantom uses the type namespace the spec already has (kfefsy)

**Rule.** The spec already says effects share the type namespace (07:2024, builtin-type-name-shadowing). So an effect name in type-argument position denotes a nominal, uninhabited type, and `Template[A]` equals `Template[B]` only when A and B resolve to the same declaration. A name that resolves to nothing is an unknown-name error. It is not a fresh type variable. This is a compiler bug fix against the existing spec, not a new rule. No marker types, and no separate phantom namespace.

```blink
pub effect Shell { effect Run { fn run(cmd: Template[Shell]) -> Output } }
fn cross(t: Template[Shell]) -> Int { db.exec(t) }
// error[E0310]: expected `Template[DB]`, found `Template[Shell]`
```

**Type-parameter C.** `fn reassemble[C](t: Template[C]) -> Str` is ordinary parametric polymorphism: it works for any context. Because the phantom is erased, it needs one instance only. A literal whose expected type is `Template[C]` with C still unbound is under-determined, and the 8vcj2c rule already rejects that. No hole and no new rule.

**Tradeoffs.**
- Option 3 (write `type DB {}`) cannot work: `type DB` and `effect DB` collide in the shared namespace, so every handler author would need a second name such as `DBCtx`. That is more surface.
- Option 2 (a phantom namespace) adds a fourth kind of name for one feature. That is the C++ committee move.
- Option 4 (the phantom is advisory) keeps a parameter that has no function. If we reject enforcement, the honest subtraction is to delete `[C]` entirely. I rank that second, since the 4-1 decision already paid for the phantom.

**Constraints.** Keeps structural plus phantom (4-1) and phantom-legal-in-user-code (6-0). Amends template-type-design.md: "C is inferred from the surrounding effect context" becomes "C comes from the expected parameter type". Effect context never supplies it, and one inference source is enough.

---

##### Rejected up front
- A surface `Any` in a restricted position. It reopens a 6-0 decision to save one enum.
- Keeping the seven-method API and only speccing the tags. That would put Int constants into the spec as a poor copy of an enum Blink already has.

##### Sub-questions for the vote
1. Surface: two methods (`parts`, `values`) over a closed `TemplateValue` enum, versus the current tag and getter API, versus fields.
2. The hole type set: exactly Int, Float, Bool and Str (narrow integers widen). Are Char, I64/U64 or a Null variant in now or later?
3. A non-scalar hole is a typecheck error (`TemplateHoleType`), with `.display()` and `Raw()` as repairs.
4. Phantom namespace: effect names resolve nominally (M2), versus marker types, versus a phantom namespace, versus deleting `[C]`.
5. An unresolved name in a phantom position is an error, not a type variable.
6. A literal passed to `Template[C]` with C generic is under-determined (8vcj2c). Confirm there is no special case.

</details>

#### Phase A.5 — Moderator dedupe and codebase facts

The moderator's grouping (labels only) and the facts surfaced to the panel, verbatim:

<details>
<summary><b>Round 1 digest</b></summary>

### Phase B, round 1: deduped option-space (mechanical grouping of Phase A)

All six Phase A proposals, verbatim, are in this directory: A_sys.md, A_web.md, A_plt.md,
A_devops.md, A_aiml.md, A_min.md. Read all six before you reply.

#### Grouping (who proposed what; labels only, no ranking)

##### Q1. Template surface
- Q1-OPAQUE: opaque compiler-known type, methods only, no fields, only the literal coercion constructs it — sys, web, plt, devops, aiml, min.
- No panelist proposed public fields.

##### Q2. How a handler reads values
- Q2-ENUM: a closed compiler-known enum replaces `type_tag` / `get_*` / `TPL_*` (3-step retirement) — sys, web, plt, devops, aiml, min.
- Variation (a) accessor:
  - `values() -> List[<enum>]` — web, plt, devops, aiml, min.
  - `value(i: Int) -> <enum>`, and sys rejects a `values()` list accessor (allocation per call) — sys.
- Variation (b) `count()`:
  - keep `count()` — sys, web, plt, devops, aiml.
  - remove `count()` (same as `values().len()`) — min.
- Variation (c) enum name:
  - `TemplateValue` — sys, plt, devops, aiml, min.
  - `TemplateArg` — web.

##### Q3. Which kinds the enum carries (the hole set)
- Q3-FOUR: Int, Float, Bool, Str only; add more later — plt, devops, min.
- Q3-NULL: the four plus `Null`, fed by `Option[T]` holes — web.
- Q3-NULL+BYTES: the four plus `Null` and `Bytes` now (sys: "I lean yes on both").
- Q3-BYTES: the four plus `Bytes` now; defer Null to its own ruling — aiml.
- Variation: `F32` widens to `.Float` — sys only states it. Char and U64 excluded — sys, devops, aiml state it explicitly; web lists Char and U64 as rejected.

##### Q4. A hole outside the set
- Q4-TYPECHECK: a typecheck error `TemplateHoleType` at the hole, never a codegen ICE — sys, web, plt, devops, aiml, min.
- Variation, the first repair offered:
  - `{p.to_str()}` — sys, web, devops, aiml, plt (plt: "`{p.id}`, `{c.to_str()}`").
  - `{p.display()}` — min.
  - `{Raw(...)}` also offered — web, plt, aiml, min.
  - bind fields (`{p.x}`) also offered — web, plt, devops.

##### Q5. What the phantom `C` resolves to
- Q5-EFFECT-NOMINAL: effect names resolve in the (spec-shared) type namespace, nominal by declaration; `Template[DB]` stays valid — sys, web, devops, aiml, min.
- Q5-TYPE-MARKER: `C` is type-kinded; an effect name is a kind error ("expected a type, found effect `DB`"); stdlib respells `Template[DB]` as `Template[Sql]` — plt (P3).
- Q5-EFFECT-KINDED: `C` effect-kinded like `Handler[E]`, top-level effects only — plt (P3′, listed "for the vote").
- Variation: `Template[DB.Read]` is an error pointing to parent `DB` — devops only.

##### Q6. An unresolved name in the phantom position
- Q6-ERROR: an unknown-type error, never an implicit type variable — web, plt, devops, aiml, min. (sys: not addressed.)
- Variation, scope:
  - every type annotation — plt, aiml.
  - phantom / `Template[...]` position — web, devops, min.

##### Q7. `C` as a type parameter of the enclosing fn
- Q7-GENERIC: ordinary parametric generics, invariant in `C` — sys, web, plt, devops, aiml, min.
- Variation: one shared mono instance across all `C` stated as normative — sys; "needs one instance only" — min.
- Variation: a literal to `Template[C]` with `C` still unbound is under-determined (8vcj2c), no special case — min.

##### Q8. The §3 phantom example `type Template[C] { source: Str }`
- Q8-RENAME: rename it (e.g. `Query[C]`) so it does not shadow the builtin — plt only.

##### Q9. template-type-design.md "C is inferred from the surrounding effect context"
- Strike / replace with "C comes from the expected parameter type" — sys, web, plt, devops, aiml, min.

#### Codebase facts surfaced by the moderator (facts, not votes)

F1. sections/03_types.md:3155 (normative) already says: "The set of types valid as Template values is
compiler-known: `Int`, `Float`, `Str`, `Bool`, `Option[T]` (where `T` is a valid value type). Using a
type outside this set in a Template interpolation is a compile error." Web cited this line; the other
five proposals did not. The same passage (3146-3150) shows `values: [42, "Alice"]` field notation.

F2. The Display trait in the spec (sections/03_types.md:2309-2316) defines `fmt(self, sb: StringBuilder)`
and a sealed default `display(self) -> Str` ("enables x.display()"). The spec's Display trait does not
define a `to_str()` method. `to_str()` appears on StringBuilder (lib/std/traits.bl:146).

F3. sections/03_types.md:1391-1396 is the user-phantom example: `type Template[C] { source: Str }` with
`let db: Template[DB] = Template { source: "SELECT 1" }`. sections/07 lists prelude-name shadowing as W1010.

F4. Per sections/07:2024 and decisions/builtin-type-name-shadowing.md, `type`, alias, `trait` and `effect`
share one type namespace. (min's Phase A text draws from this that `type DB {}` and `effect DB` collide.)

</details>

#### Phase B — Round 1 responses

Position shifts are stated at the top of each response. All six ended `STATUS: ready to vote`.

<details>
<summary><b>Systems</b></summary>

### Systems panelist, Phase B round 1

I agree with the five other panelists on Q1 (an opaque type), Q2 (an enum), Q4 (a typecheck error) and Q9 (strike "inferred from effect context"). Below are my position changes and my answers to each flagged variation.

#### Position changes

1. **Q2(a) accessor: I move from `value(i)` to `values() -> List[TemplateValue]`.** My objection was one allocation per call. That is an implementation question, not a surface question, and five of six panelists want `values()`. `for v in tpl.values()` (web's handler) is also the shortest correct loop, and it removes the `i + 1` off-by-one hazard. I ask for one condition in the spec text:
   - A `Template` is immutable. `parts()` and `values()` return lists, and mutating a returned list (`let mut v = t.values(); v.push(...)`) must not change the template.
   - Whether the runtime copies or shares until the first write is up to the implementation.
   - Mutability belongs to the binding, not the type (03_types.md:317), so without this rule a `let mut` binding would alias the template's store.
   - Implementation note, not normative: the runtime should build the `List[TemplateValue]` once at the literal site. Then `values()` on an immutable binding is O(1).

2. **Q4 repair spelling: I move from `{p.to_str()}` to `{p.display()}`.** F2 settles it. The spec's Display trait defines the sealed `display()`, and `to_str()` belongs to StringBuilder. A hint whose repair does not compile breaks §3.1, so `.to_str()` is out for any Display type. Hints are fixed by the hole's type:
   - A Display type: `{p.display()}`.
   - Any type: `{Raw(...)}` is offered only as a second hint, because it carries the audit warning.
   - A struct: binding its fields is also a correct hint.

3. **Q3 set: F1 changes the question.** 03_types.md:3155 is normative and already puts `Option[T]` in the set. So "the four only" is the option that **amends** the spec, not the one that keeps it. Panelists voting Q3-FOUR should say they are amending 3155. I keep my Phase A lean, now on firmer ground:
   - **`Null` now**, fed by `Option[T]` holes. `Some(x)` maps to x's own variant and `None` maps to `.Null`. This keeps 3155 as written.
     - One restriction: `T` must be a non-Option member of the set. `Option[Option[Int]]` would collapse two different "none" states into one `Null`. That is lossy, and 3155's recursive wording ("`T` is a valid value type") allows it today. The error's repair is to flatten the value first.
     - Cost: one arm with no payload, and no allocation. SQL NULL is the most common bind a DB driver makes after Int and Str. Leaving it out forces the user to write two templates, a dynamic query built with `Raw`, or a sentinel value, and all three are worse.
   - **`Bytes`**: I still lean yes. BLOB binding is a real driver need, the arm costs one pointer and a length, and adding it after v1 breaks every exhaustive handler. It extends 3155, though, so it needs its own vote. I will not make it a condition of my vote on the rest.
   - **`F32` widens to `.Float`**, which loses nothing. The spec should list it with the narrow integer types.
   - **`U64` and `Char` are excluded**, with repairs that compile: `{c.display()}` for Char, and a checked conversion for U64.

#### Other variations

- **Q2(b) `count()`: I accept removing it (min).** With `values()` it only duplicates `values().len()`. The invariant reads cleanest as `parts().len() == values().len() + 1`. I have no strong view either way.
- **Q2(c) name: `TemplateValue`.** It matches the accessor name `values()`. `TemplateArg` fits C# naming but not ours.
- **Q5 kind: effect-nominal, and a declared marker type is legal too.** Types and effects share one namespace (F4). So "C resolves to any declaration in the type namespace, compared nominally by declaration identity, qualified by module" covers both:
  - `Template[DB]`, which names an effect;
  - PLT's `Template[Sql]`, which names a marker type for a pure context such as HTML.

  This meets PLT's point 1 (a pure context needs no effect) without a kind error and without re-spelling stdlib. It also meets PLT's soundness point (identity is the declaration, not the name). I reject P3′ (effect-kinded `C`), because it makes `fn f[C](t: Template[C])` illegal until v2.
- **Q5 `Template[DB.Read]`: I support devops.** It should be an error that points to `DB`. One spelling per context, and it keeps sub-effect subsumption out of the type relation.
- **Q6 scope: every type annotation.** A silent type variable fallback anywhere means the compiler may monomorphize on a name nobody bound. That is the same class of bug outside `Template`. It is a conformance fix to the explicit-binder rule, not new language. If the panel prefers, record it as a separate `type:bug` so this ruling's scope stays narrow. I vote for "everywhere" either way.
- **Q7: generic over contexts, invariant in `C`; min's under-determined rule applies.** I withdraw "one shared mono instance is normative". How much code is shared is an implementation quality issue, and the spec already says the phantom is erased. The spec should say only that `Template[C]` has one runtime layout for every `C`.
- **Q8: rename the §3 example (e.g. `Query[C]`). Yes.** A spec example that triggers W1010 teaches users to shadow a builtin.

#### Summary of my votes, as of now

| Question | My vote |
|---|---|
| Q1 | opaque |
| Q2 | enum `TemplateValue`, `values()` with the immutability rule, no `count()` |
| Q3 | four scalars + `Null` (per 3155, non-nested Option); `Bytes` as its own vote (I vote yes); F32 widens |
| Q4 | typecheck `TemplateHoleType`, first repair `.display()` or field binding, `Raw` second |
| Q5 | any type-namespace declaration, nominal; `DB.Read` is an error |
| Q6 | error everywhere |
| Q7 | generic, invariant |
| Q8 | rename |
| Q9 | strike |

STATUS: ready to vote

</details>

<details>
<summary><b>Web/Scripting</b></summary>

### Web/Scripting panelist, Phase B round 1

Q1 (opaque, methods only) and Q9 (strike "inferred from the surrounding effect context") are unanimous. I have nothing to add on them.

#### Position changes

1. **Enum name: `TemplateValue`, not `TemplateArg`.** Five panelists chose it. It also pairs with `values()`, and it is the word Python 3.14 and JS users already know.
2. **Drop `count()` (join min).** With `values()` in the surface, `count()` is a second spelling of `values().len()`. Two spellings mean two answers on Stack Overflow. The invariant becomes `t.parts().len() == t.values().len() + 1`. If the panel picks sys's `value(i)`, then `count()` must stay, and I would accept that pairing.
3. **Repair spelling: `{p.display()}`, not `{p.to_str()}` (per F2).** `display()` is the sealed Display method that the spec defines. `to_str()` is not on Display, so a hint that offers it breaks §3.1 for most types. I withdraw `to_str()`.
4. **Remove `Raw(...)` from the `TemplateHoleType` hints (a new point, and it withdraws part of my Phase A).** The user in front of this error had a struct in a SQL hole. A `help:` line that says "or wrap it in Raw" points a new user at the injection bypass, and new users copy the last suggestion that compiles. Raw has its own audit-gated door, and a type error should not advertise it. The hints are: (a) bind a field, `{p.id}`; (b) `{p.display()}`, sent as a Str parameter, still parameterized. For U64: a checked conversion to `Int`.

#### Q2(a): `values()` list vs `value(i)`

I keep `values()`. sys's cost is one list allocation per call. That call precedes a network or disk round trip, so the cost does not show up in any profile. `for v in tpl.values()` is what every JS and Python user types first, while `while i < tpl.count() { tpl.value(i) }` is C written in Blink. We also get the indexed form without a new method: `tpl.values().get(i)`. If sys needs it for the stdlib driver, the runtime can hand out the stored array without copying, and that is an implementation choice, not a spec surface.

#### Q3: the hole set (my main point this round)

**F1 changes the default.** sections/03_types.md:3155 is normative today, and it already puts `Option[T]` in the set. So "four only" is not the status quo. It **amends** a normative line and removes a feature. Q3-FOUR voters should say so explicitly.

On the merits, `Null` is the 90% case, not the 10% edge case. Every web backend has a nullable column:

```blink
fn update_nick(id: Int, nick: Str?) -> Result[Int, DBError] ! DB.Write {
    db.execute("UPDATE users SET nick = {nick} WHERE id = {id}")
}
```

Without `Null`, this needs a `match` and two near-identical queries. Users will not write them. They will write `{nick ?? ""}`, which stores an empty string where the column should hold NULL, a silent data bug. Python DB-API maps `None` to NULL, as do JDBC `setNull` and node-postgres `null`. Every driver users know does this.

Everyone agrees that a variant added later breaks every handler's exhaustive match. So the choice is not "Null now or Null later cheaply". It is "Null now, or a breaking change later that we already know we need". Mapping: `Option[T]` with `T` in the scalar set; `None` becomes `.Null`, `Some(v)` becomes v's variant. `Option[Option[T]]` is rejected with `TemplateHoleType`.

**Bytes:** I join sys and aiml on adding it now, for the same break-later reason. BLOB columns and binary shell args are common. `Bytes` is already compiler-known (§10.6), so it needs no new type.

**F32:** it widens to `.Float` (as sys proposes). It is compiler-known, and the widening is lossless. **Char, I64/U64:** excluded, with the hints above.

My final set: `Int, Float, Bool, Str, Bytes, Null`.

#### Q5: the phantom's kind

I stay on EFFECT-NOMINAL. To plt:
- **Pure contexts (HTML).** Nothing in EFFECT-NOMINAL bans a marker `type Html {}`. The shared namespace resolves both types and effects, so an author with no effect declares a marker type. We lose nothing, and `Template[DB]` stays valid.
- **Generic helpers.** Following min's framing, an effect name in type-argument position denotes a nominal, uninhabited type. `fn f[C](t: Template[C])` stays ordinary type-kinded generics, and `C` binds to that type. We need no effect-kinded generics.
- **Cost of the respelling.** Respelling stdlib to `Template[Sql]` makes every spec example, every test, and the one real handler change spelling, all to fix a compiler bug. Users see the effect named `DB` in the effect row (`! DB.Read`) and will write `Template[DB]` anyway. They should not get a kind error for the natural spelling.

On devops's `Template[DB.Read]` rule, I agree: it is an error, with a hint to use the parent `DB`. One spelling per context.

#### Q6: the scope of the unresolved-name error

I widen my position: **every type annotation** (plt, aiml). The typo `fn f(u: Usr)` silently becoming generic is the same bug outside Template, and a JS/TS user expects "Cannot find name 'Usr'". Blink declares binders (`fn f[T]`). `Self` inside a trait is a keyword-bound implicit parameter, not a free name, so it is unaffected. If the moderator finds a spec construct that relies on the fallback, keep the phantom-position scope for this ruling and file the wider one separately.

#### Q7

Generic forwarding: agree. min's "under-determined, no special case": agree. sys's "one shared mono instance is normative": the phantom is already spec-erased, so I would state the instance sharing as a guarantee in a note and keep it out of the typing rules. I will not block on this.

#### Q8

I agree with the rename, because the example teaches users to shadow a prelude name (W1010). I prefer not to use `Query[C]`, which was the name this feature carried before the 3-1-1 vote and would confuse readers of the decision history. Any unused, domain-neutral name works, for example `Tagged[C]`.

STATUS: ready to vote

</details>

<details>
<summary><b>PLT</b></summary>

**PLT panelist — Phase B, round 1**

#### New finding: opaque is not enough, the observers alias

All six of us argued "methods, not fields" to stop `Template[DB] { parts: [user_input] }`. The method surface as built has the same hole. `blink_template_parts` (bootstrap/runtime_core.h, template block) returns `t->parts`, the template's own list. §3 (03_types.md:2342) makes `List` a shared cell. So:

```blink
fn launder(t: Template[DB], evil: Str) -> Result[Int, DBError] ! DB.Write {
    let mut ps = t.parts()
    ps.push(evil)            // mutates t's own parts: no Raw, no audit
    db.execute(t)
}
```

A `values()` that returns the stored list would have the same hole. **Proposed normative rule (Q1 addendum):** a `Template[C]` is immutable after construction. No observer returns a value through which a caller can change the template. Concretely, `parts()` and `values()` each return a fresh list (a copy). This is a soundness condition, not a performance choice. I ask the moderator to log the current `parts()` aliasing as a `type:bug`, whatever the vote on the rest.

#### Q2: accessor, `count`, name

- **Accessor.** Given the rule above, the choice is between a total observer that allocates (`values() -> List[TemplateValue]`, fresh) and a partial one that does not (`value(i) -> TemplateValue`, which panics out of range). I keep `values()` as the normative surface. It is total, it matches `parts()`, and a template is already built per call, so one more allocation per handler call is in the noise. That answers sys's cost objection. I do not object to sys adding `value(i)` *as well*, but then it should follow `List.get` and return `Option[TemplateValue]`. A second spelling that panics is the worse half.
- **`count()`.** Keep it. Once `values()` copies, `count()` is the only O(1), allocation-free way to write the invariant and the reassembly loop. That is enough reason for one method. This changes min's premise that it is only `values().len()`.
- **Name.** `TemplateValue` (5 of 6). It pairs with `values()`, and "Arg" suggests call arguments.

#### Q3: the set

F1 matters here. 03_types.md:3155 already puts `Option[T]` in the set, normatively. Dropping it would be an amendment nobody has argued for. So I move from FOUR to **FOUR + `Null`**, with one tightening. `Option[T]` is valid only when `T` is one of the four scalars (or a widening integer), **not recursively**. The spec's "where `T` is a valid value type" admits `Option[Option[Int]]`, and there `Some(None)` and `None` both map to `Null`. That is a non-injective encoding, and a handler cannot recover the value from it. Mapping: `Some(x)` goes to x's variant, `None` goes to `.Null`.

**Bytes:** no, for now. The value enum is context-independent, but the phantom is not. Every Shell and HTML handler would carry a `Bytes` arm that has no meaning in its context. The honest fix (a value set indexed by `C`) is a type family, which is too much for v1. A later `Bytes` variant is one loud, exhaustive-match break, which is the correct failure mode. F32 → `.Float` (sys): agree, it is lossless. Char and U64 stay excluded.

#### Q4: the repair spelling

F2 settles it: the spec's `Display` defines `display()`, not `to_str()`. `{p.to_str()}` would be a repair that does not compile for a user type, which §3.1 forbids. **The first repair is `{p.display()}`** (min). It is explicit, and the result is a *parameterized* `Str` value, not text folded into the parts, so injection safety holds. That does not conflict with 03_types.md:3159, which forbids *implicit* stringification. The field hint (`{p.x}`) and `Raw` are good second and third hints. I withdraw my `.to_str()` wording.

#### Q5: the kind of C — position change

I move to **Q5-EFFECT-NOMINAL**, using min's formalization: *each effect declaration induces an uninhabited nominal type of kind Type, with the same name in the shared type namespace.* That answers my Phase A objection. `C` stays an ordinary type-kinded parameter, so `fn f[C](t: Template[C])` works in v1 with no effect-kinded generics, and F4's collision argument against marker types stands. I vote for it with four conditions, which I ask be part of the ruling:

1. **Argument position only.** An effect-induced type may appear only as a type argument. `fn f(x: DB)` is an error ("effect `DB` is not a value type"). Otherwise we admit uncallable functions and a new class of uninhabited annotations.
2. **No leak into effect kinds.** `Handler[E]` still takes an *effect*. `fn f[C](h: Handler[C])` stays a kind error in v1 (§4.7.1). The induced type is not the effect.
3. **Top-level effects only.** `Template[DB.Read]` is an error that points to `DB` (devops). Under invariance, `Template[DB.Read]` ≠ `Template[DB]`, and users would read it as sub-effect subsumption, which does not hold.
4. **Marker types stay legal.** `C` may be any type, so a pure context (`type Html {}`) needs no empty effect. Identity is the resolved declaration, qualified by module.

I withdraw P3 (the `Template[Sql]` respelling). I keep P3′ only as a fallback if condition 2 is rejected.

#### Q6: scope

**Everywhere.** A free name in any type annotation that silently becomes a type variable makes `fn f(x: Strr)` a generic function. That is unsound for exactly the reason kfefsy gives, in every position. Blink declares its binders (`[T]`), so the spec already implies this, and it is a conformance fix, not new language. If the panel wants to keep the tickets' scope narrow, rule on the phantom position here and log the general case as a `type:bug`. The narrow rule alone should not ship as the answer.

#### Q7

Agree: ordinary generics, invariant in `C`. min's point holds: a literal whose expected type is `Template[C]`, with `C` unbound, is under-determined under 8vcj2c, and needs no special case. On sys's "one shared mono instance is normative": erasure is normative already, and instance sharing cannot be observed (only code size). The spec should *permit* it as an expected implementation, not make it a language rule.

#### Q8

I keep it: rename the §3 user-phantom example to `Query[C]` (or similar). As written, the passage that teaches phantoms also teaches shadowing a builtin (W1010), and after this ruling its `Template[DB]` would resolve against the *user* `Template`. That is a confusing lesson.

STATUS: ready to vote

</details>

<details>
<summary><b>DevOps</b></summary>

### DevOps/Tooling, Phase B round 1

We agree on the core: an opaque type, a closed enum, a typecheck-time hole error, and nominal phantoms. What is left are the variations. My lens is unchanged: what the diagnostic says, what the LSP can complete, and whether the spec gives one spelling to copy.

#### Position changes

1. **Null is in (Q3). I change from Q3-FOUR.** F1 settles it. sections/03_types.md:3155 already lists `Option[T]` as a valid Template value type, and it is normative. Dropping Null would *amend* the spec, not follow YAGNI. The five panelists who deferred Null did not see that line; I was one of them. So `Option[T]` maps to the inner variant, or to `TemplateValue.Null` when it holds nothing.
   - **New sub-rule:** the `T` in `Option[T]` must be a non-Option member of the set. `Option[Option[Int]]` is `TemplateHoleType`, because `None` and `Some(None)` would both map to `Null` and the handler cannot tell them apart. That loses information without any message, which is exactly the class of bug this whole design exists to prevent. The line at 3155 ("where `T` is a valid value type") is recursive as written, so it needs this fix.
2. **The first repair is `{p.display()}`, not `.to_str()` (Q4). I adopt min's spelling.** F2: the spec's Display defines `display()`. Nothing defines `to_str()` on Display. A help line that names a method that does not exist breaks §3.1, which is the exact rule this ticket exists to enforce. sys, web, plt and aiml should move too.
3. **Bytes: I now lean yes (Q3), weakly.** Every driver we would ship binds a BLOB as its own kind (`sqlite3_bind_blob`, binary params in libpq). A variant added after v1 is a breaking change to a prelude type, and it reaches every third-party handler at once. The E0004 list does make the fix mechanical, but the cost is still a breaking release. If the panel keeps the set minimal, I will not block.

#### The flagged variations

**Q2(a), `values()` vs `value(i)`.** I keep `values() -> List[TemplateValue]`. With it, `for v in tpl.values()` works, completion is plain, and the name matches JS and Python. `value(i)` makes the out-of-range case awkward: Blink's `get` convention returns `Option`, so either `value(i)` panics (a second convention) or every handler unwraps twice.

**New point that affects Q1/Q2, which nobody raised.** §3 says a `List` in a copied value is a *shared cell*. If `parts()` returns the backing list, then generic middleware such as `fn log[C](t: Template[C])` can call `t.parts().push(user_input)`. That changes the literal text of a template that later reaches the DB handler: laundering with no `Raw` and no audit. So the spec must say that **`parts()` and `values()` each return a fresh list, and mutating it does not change the template.**
- That gives sys's allocation-per-call cost a correctness reason, and I accept the cost. A DB call dwarfs it.
- The same rule holds whatever accessor wins.
- If sys wants a copy-free path, `value(i)` could be added later without breaking anything. Adding a variant later breaks handlers; adding a method does not.

**Q2(b), `count()`.** Remove it (min). Given `values().len()`, a second spelling of the invariant is the kind of drift that produced fqy7bz. The invariant has one spelling: `t.parts().len() == t.values().len() + 1`.

**Q2(c), the name.** `TemplateValue` (5 of 6). It matches the method `values()`, so completion of `values` suggests `TemplateValue`. `TemplateArg` breaks that link.

**Q4, what `TemplateHoleType` offers.**
- **Order:** `{x.display()}` when the type has Display, then field binding (`{p.x}`), then an explicit `match` for `Option` of a non-member type.
- **`Raw` must NOT appear as a help line.** A help line is what an LLM or a hurried developer applies without reading. "Fix" the error with `Raw` and you have concatenated user data into SQL. That is the injection this feature prevents, and `RawBypassesParam` then fires on code the compiler told you to write. §3.1 asks for repairs that exist, not repairs that are safe; here the repair must also be safe. This is a firm position (web, plt, aiml and min all listed `Raw`).
- **Proposed text:**
  ```
  error[TemplateHoleType]: `Point` cannot be a Template value
    = note: Template values are Int, Float, Bool, Str, Option of these, and narrow integers
    = help: send it as a string value: `{p.display()}`
    = help: or send its fields: `{p.x}`
  ```

**Q3 details.** Narrow ints widen to `.Int`. `F32` widens to `.Float` (sys). `Char` and `U64` are excluded, with repairs `{c.display()}` and an explicit conversion.

**Q5, PLT's P3 (type markers only).** I stay with Q5-EFFECT-NOMINAL, and I do not think PLT's reasons force P3:
- An effect name in type position denotes a nominal *type*, uninhabited. So `C` stays type-kinded. `fn f[C](t: Template[C])` is ordinary v1 generics, with no need for effect-kinded generics, which removes P3 reason 3.
- Marker types stay legal under Q5-EFFECT-NOMINAL. A pure HTML context writes `type Html {}` and needs no dummy effect, which removes P3 reason 1.
- P3 turns every spec example and both in-tree stdlib files into a kind error, and (min, F4) forces a second name next to each effect, since `type DB` and `effect DB` collide. That is churn with no diagnostic gain.
- I keep one piece of P3: identity is module-qualified by declaration, not by bare name.

**`Template[DB.Read]`.** Nobody else addressed it. Under nominal identity it would be a third context, distinct from `Template[DB]`, which no user expects. I keep "error, help: use the parent effect `DB`". I will fold this into Q5 if the panel prefers.

**Q6 scope: everywhere.** I change from phantom-only. Blink declares binders explicitly. The only sanctioned implicit type parameter is `Self` in a trait (03_types:2347). A fallback to an implicit typevar at *any* annotation turns a typo into a silent generic, and the best diagnostic the user gets is something later and unrelated. The rule: unknown-type error with a did-you-mean over types, effects and in-scope binders. If the panel judges "everywhere" out of scope for these tickets, `Template[...]` is the minimum, and the general rule goes on its own ticket.

**Q7.** Generic, invariant in `C` (all). min's point that a literal reaching an unbound `C` is under-determined under 8vcj2c, with no special case: agreed. sys's "one mono instance across all `C`" is a codegen promise, not language semantics. Put it in a non-normative note, not in normative text.

**Q8.** Rename the §3 example to `Query[C]` (plt). As it stands, the spec example raises W1010 shadowing in teaching text, and both LLMs and users copy it.

**Q9.** Strike it, and replace it with "C comes from the expected parameter type" (all).

STATUS: ready to vote

</details>

<details>
<summary><b>AI/ML</b></summary>

**AI/ML panelist, Phase B round 1**

Q1 (opaque type) and Q9 (strike "inferred from the surrounding effect context") are 6-0 in substance, so I say nothing more on them. Below: two position changes, forced by F1 and F2, then my view on each flagged variation.

---

##### Position changes

**1. Q3: I now back the four scalars plus `Null` fed by `Option[T]` holes (web's set). I move `Bytes` to "nice to have".**

F1 decides this for me. sections/03_types.md:3155 is normative, and it already lists `Option[T]` in the hole set. If we "defer Null", we are not holding a line. We are cutting a promise the spec makes today, and that cut would need its own explicit amendment. We also all agree that adding a variant later breaks every exhaustive handler `match`. So the time to add `Null` is now.

Proposed wording: `Option[T]` is a valid hole when `T` is in the scalar set. `Some(x)` maps to the variant for `x`, and `None` maps to `.Null`. A nested `Option[Option[T]]` is `TemplateHoleType`.

For generability, `IS {nick}` with a `Str?` is exactly the SQL a model writes, and `.Null => sqlite_bind_null(...)` is an obvious arm.

On `Bytes`: it is not in F1, and no in-tree handler needs it. I will vote for it if sys or web push, but I do not hold it.

**2. Q4: the first repair must follow the hole's type. `.to_str()` is wrong for a struct.**

F2 shows the spec's Display trait has `display()`, not `to_str()`. So `help: {p.to_str()}` on a `Point` hole prescribes a repair that does not compile. That is precisely the §3.1 violation this ruling exists to remove. A model will copy the `help:` text verbatim, so the help must be right for each case.

| Hole type | First `help:` |
|---|---|
| Implements Display | `{p.display()}` (min's spelling) |
| `Char` | `{c.to_str()}` (Char has `.to_str()`) |
| `U64` | a checked conversion to `Int` |
| No Display, no conversion | bind a scalar field: `{p.id}` |
| Always last | `Raw(...)` |

`Raw` goes last because it is the unsafe exit. If a model sees `Raw` first, it reaches for `Raw` first. A struct whose fields are all non-scalar gets no field hint. The help then offers only what exists, as §3.1 requires.

---

##### Flagged variations

**Q2(a): `values() -> List[TemplateValue]` vs `value(i) -> TemplateValue`.**

I hold `values()`. `for v in tpl.values() { match v {...} }` is the shape with the most training data (JS `values`, Python `.values`, web's and plt's handlers). It also needs no index arithmetic, which is where models make off-by-one binding errors.

Sys's allocation point is real, and there is a second point sys did not raise. §3 says a `List` is a shared cell. If `values()` handed back the stored list, a handler's `.push` would break the `parts/values` invariant for every other holder of the template. So the rule should be: **`values()` and `parts()` each return a fresh list.** One allocation per query is noise next to a driver round trip.

Offering both accessors doubles the decision points, so I am against that.

**Q2(b): `count()`.**

With `values()`, `count()` is a second spelling of `values().len()`, and the invariant is then written in two ways. I now side with min: drop it. If the panel picks `value(i)`, then `count()` is needed, and I would accept that pair as a unit.

**Q2(c): the enum's name.**

`TemplateValue`. It pairs with `values()`: a model that reads `values()` guesses `TemplateValue`, not `TemplateArg`.

**Q5: effect-nominal, with one change that answers plt.**

Plt's objection (P3, point 1) is that a pure context such as HTML should not need a fake effect. That is right. But effect-nominal does not force that. Under Q5-EFFECT-NOMINAL, `C` resolves to **any** type-namespace declaration: a type *or* an effect, compared by declaration identity. So an HTML library writes `type Html {}` and `Template[Html]`, and `db` keeps `Template[DB]`.

- Plt's point 3 (generics): with this rule, `fn f[C](t: Template[C])` stays ordinary type-kinded polymorphism. An effect name used as an argument is just a nominal type argument, so v2 effect-kinded generics are never needed.
- Plt's P3 would respell every stdlib op and every spec example. Models trained on the spec write `Template[DB]` beside `! DB.Read`, and a kind error on the spelling the spec taught is the worst outcome for learnability.
- I oppose P3′ (effect-kinded `C`): it breaks generics until v2.

**Q5 variation: `Template[DB.Read]`.** I back devops: this is an error that points to `DB`. That gives one spelling per context.

**Q6 scope: every type annotation, not just the phantom position.**

A phantom-only rule is a special case that a model cannot guess. "A free name in a type is an error; type variables come only from `[T]` binders" is one rule that holds everywhere. `Self` is a declared implicit binder (§3 *Operations on `Self`*), so it is not an exception.

If there is a program where the typevar fallback is intended, it should be found before the vote. I know of none.

**Q7.** Generic and invariant. Min's point stands and I adopt it: a literal whose expected type is `Template[C]` with `C` unbound is E0301, with no special case. On sys's "one shared mono instance": I back it as an implementation guarantee, but it adds nothing a user or a model can observe. I would put it in a note, not the normative rule. I will not block either way.

**Q8: rename the §3 phantom example.** Yes. That example is the one users copy, and today it teaches them to shadow a builtin (W1010) and to add a public field on a type whose real version has none. The new name should not collide with anything: for example `Tagged[C] { source: Str }`, or plt's `Query[C]`.

---

##### New option for the ballot

**Q3-FIVE: Int, Float, Bool, Str, Null (from `Option[scalar]`).** This is F1 as written. It is the option that needs no amendment to the spec.

STATUS: ready to vote

</details>

<details>
<summary><b>Minimalism</b></summary>

### Minimalism panelist, Phase B round 1

We agree on the big items. All six of us chose: an opaque type, a closed enum, a typecheck error for an out-of-set hole, generic `C`, and striking "inferred from effect context". I only address where we differ. F1 and F2 change two of my positions.

#### Q2: the accessor, `count()`, and the name

**(a) `values()` versus `value(i)`.** I keep `values()`. Sys's objection is allocation per call. But the compiler owns the runtime layout, so the stored values can *be* the `List[TemplateValue]`, built once at the literal site. Then `values()` returns it and allocates nothing. `values()` also gives handlers `for v in t.values()`, which web, plt and aiml all wrote on their own, and it keeps the invariant in one spelling. `value(i)` needs `count()` beside it, so it is two methods for one job.

One point of correctness for the text: if `values()` returns the stored list, a handler that calls `.push()` on it must not be able to change the template. The spec must say `values()` returns a copy, or that the list is not shared. I prefer the rule "returns a fresh list" and leave the cost to the implementation.

**(b) `count()`.** It is the same as `values().len()`, so I still prefer to drop it. This is a weak preference. I will not block a majority that keeps it.

**(c) Name.** `TemplateValue`. Five of six chose it, and it says what it is.

#### Q3: the hole set. Position changed

F1 settles it for me. sections/03_types.md:3155 already includes `Option[T]` in the normative set. So a `Null` variant is not an addition. Leaving it out would remove something from the normative spec, and that needs its own reason. I have none: SQL NULL is a real need in the one real handler domain. I now vote for **the four scalars plus `Null`**. `Some(x)` maps to x's variant, and `None` maps to `Null`.

This needs one limit: `T` in `Option[T]` must itself be one of the four scalars (after widening). `Option[Option[Int]]` has no single meaning as a bound parameter, so it gets `TemplateHoleType`.

**`Bytes`: defer it.** No spec line includes it and no in-tree handler binds a BLOB. The "adding a variant later breaks handlers" cost is real, but it is small today: there is one in-tree handler and the language is before 1.0. It is also a loud break at compile time, which is the good kind. When a handler needs BLOBs, the change is one variant plus one vote.

`F32` widens to `.Float` (sys). I agree, because the widening is lossless. `U64` and `Char` stay out.

#### Q4: the repair spelling. F2 decides it

§3.1 requires the first repair to compile. F2 shows that `.to_str()` is **not** a Display method. On a Display struct, `{p.to_str()}` is a repair that does not exist, which is the same §3.1 breach we are fixing, only moved into the help text. The repair that works for every Display type, Char included, is `{p.display()}`. So:

- The type has Display: `help: {p.display()}` sends it as a Str parameter.
- The type has no Display: `help: bind a field, e.g. {p.id}`.
- `U64`: `help:` a checked conversion to `Int`.

I withdraw `Raw(...)` as an offered repair, and I ask web, plt and aiml to drop it too. On an injection boundary, a help line that suggests the unparameterized path trains users, and models, to take the unsafe fix. That fix then fires `RawBypassesParam`, so the "repair" produces an audit warning. Users who want Raw know about it already.

#### Q5: what `C` resolves to

I stay with EFFECT-NOMINAL, and here I answer PLT's P3 directly.

- **"HTML is pure and should not need an effect."** Under the shared namespace it does not need one: `type Html {}` is also a type-namespace name, so `Template[Html]` works. EFFECT-NOMINAL accepts both kinds of name. P3 accepts only one kind, and so it forces stdlib to declare a second name next to every effect (`Sql` beside `DB`). For the common case that is more surface for no gain.
- **Identity.** I agree with PLT: identity is the resolved *declaration*, not the text of the name. Two modules that each declare `DB` produce distinct contexts. My M2 already said this, and I restate it so the vote wording does not say "by name".
- **Generics.** PLT is right that a bare "effect-kinded" `C` would need effect generics, which §4.7.1 defers. My M2 avoids this: an effect name used as a type argument denotes a nominal, uninhabited type. So `C` stays `Type`-kinded, and `[C]` binds to it like any other type. No v2 feature is needed.
- **New limit, to prevent a stray surface.** An effect name is legal *only as a type argument*. `fn f(x: DB)` or `let x: DB` is an error: "effect `DB` is not a value type". Without this limit we would quietly add parameters of uninhabited types.

I rank P3′ (effect-kinded) last. It blocks `fn f[C](t: Template[C])` until v2.

**DevOps' `Template[DB.Read]` is an error that points to `DB`.** I agree: one spelling per context.

#### Q6: scope. Position changed, to "everywhere"

One rule is smaller than two. "A type variable comes only from a declared binder" everywhere is simpler than an exception for the phantom position. A phantom-only scope would leave the same silent hole in `fn f(x: Lst[Int])`. I side with plt and aiml. We should check whether any stdlib code relies on the fallback, but that is an implementation step, not a spec question.

#### Q7: shared instance, and one small point

I agree with generic `C`, invariant. Sys wants "one mono instance across all `C`" as normative. The instance count cannot be observed from the language, so it belongs in an implementation note, not in the spec. I keep my point that a literal with `C` still unbound is under-determined under 8vcj2c, with no special rule.

#### Q8

Rename the §3 example to `Query[C]`: yes. We should not teach users to shadow a builtin. The rename costs nothing.

STATUS: ready to vote

</details>

#### Phase C — Final vote

Tally:

- **Q1 Template surface:** A, opaque and immutable, fresh lists — **6-0**
- **Q2 Accessor and `count()`:** A, `parts()` + `values()`, no `count()` — **5-1** (sys dissent: B, keep `count()` as the allocation-free length)
- **Q3 Value set:** A, `Int`, `Float`, `Bool`, `Str`, `Null` — **4-2** (sys, web dissent: B, add `Bytes`). The user accepted this as soft consensus; a `Bytes` variant is a follow-up ticket.
- **Q4 Out-of-set hole:** A, `Raw` never a `help:` line — **6-0** (aiml, plt, sys changed from B)
- **Q5 What `C` resolves to:** A, effect-induced nominal type with four conditions — **6-0**
- **Q6 Unresolved type name:** A, an error in every annotation — **6-0**
- **Q7 Generic `C`:** A, ordinary generics, sharing in a non-normative note — **6-0**
- **Q8 §3 phantom example:** B, rename to `Tagged[C]` — **6-0**
- **Q9 Inference sentence:** A, "C comes from the expected parameter type" — **6-0**

The ballot, verbatim:

<details>
<summary><b>Phase C ballot</b></summary>

### Phase C: silent vote

All six round-1 responses are in this directory (B1_sys.md … B1_plt.md), and all six end with
`STATUS: ready to vote`. Read the ones you have not read yet before you vote. This is a silent vote:
do not message other panelists.

Options come from panelist text only; the proposer is named after each option.

For EACH question write:
1. **Vote**: the option letter.
2. **Reasoning**: 2-4 sentences, from your domain.
3. **Concern**: one sentence on what could go wrong with the option you expect to win.

Write your ballot to this directory as C_<yourname>.md and reply "voted" to team-lead.

---

**Q1. Template surface.**
- A: `Template[C]` is opaque and compiler-known. It has no fields. Only the literal coercion (plus `Raw` folding) constructs it. A `Template` is immutable after construction: no observer returns a value through which a caller can change it, so each list-returning observer returns a fresh list (plt, devops, aiml, min, sys).
- B: opaque, as in A, without the immutability / fresh-list rule.

**Q2. Value accessor and `count()`.** (The enum is named `TemplateValue` in every option; `type_tag`, `get_*` and `TPL_*` are retired through the 3-step path.)
- A: `parts() -> List[Str]` and `values() -> List[TemplateValue]` only; `count()` removed; invariant `t.parts().len() == t.values().len() + 1` (min, web, sys, aiml, devops).
- B: `parts()`, `values()` and `count() -> Int`, kept as the allocation-free length (plt).

**Q3. The value set (what `TemplateValue` carries).** Common to every option: `Int` (with I8/I16/I32/U8/U16/U32 widening), `F32` widening to `Float`, `Float`, `Bool`, `Str`; `Char`, `I64`/`U64` excluded; `Option[T]` is a hole only when `T` is a non-Option member of the set (`Some(x)` → x's variant, `None` → `.Null`), and `Option[Option[T]]` is `TemplateHoleType`.
- A: `TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str), Null }` (aiml "Q3-FIVE", min, plt).
- B: A plus `Bytes(Bytes)` (web, sys).

**Q4. A hole outside the set.** Common: a typecheck error `TemplateHoleType` at the hole, never a codegen ICE; the first `help:` depends on the hole's type: `{x.display()}` for a Display type, a field binding (`{p.x}`) for a struct, a checked conversion for `U64`.
- A: `Raw(...)` never appears as a `help:` line (devops, web, min).
- B: `Raw(...)` may appear, always as the last `help:` line (aiml, plt, sys).

**Q5. What `C` in `Template[C]` resolves to.**
- A: `C` resolves to any declaration in the shared type namespace, compared by declaration identity, qualified by module. Each effect declaration induces an uninhabited nominal type of kind Type with the same name, so `Template[DB]` is valid and distinct from `Template[Shell]`. Conditions (plt, min, devops): (1) an effect-induced type may appear only as a type argument, and `fn f(x: DB)` is an error; (2) it does not leak into effect kinds, so `Handler[E]` still takes an effect; (3) top-level effects only, so `Template[DB.Read]` is an error that points to `DB`; (4) marker types (`type Html {}`) stay legal (sys, web, devops, aiml, min, plt in round 1).
- B: type-kinded marker types only; an effect name is a kind error; stdlib respells to `Template[Sql]` (plt P3, withdrawn by its proposer in round 1).
- C: `C` is effect-kinded like `Handler[E]` (plt P3′, kept by plt as a fallback only).

**Q6. An unresolved name in a type annotation.**
- A: an unknown-type error in every type annotation; a type variable comes only from a declared binder (`[T]`) or `Self` (plt, aiml, sys, web, min, devops in round 1).
- B: an error only in the phantom position (`Template[...]`); the general case goes to its own ticket.

**Q7. `C` as a type parameter of the enclosing fn.**
- A: ordinary generics, invariant in `C`. A literal whose expected type is `Template[C]` with `C` unbound is under-determined under 8vcj2c, with no special rule. Every `Template[C]` has one runtime layout; sharing one mono instance across `C` is a permitted implementation choice in a non-normative note (all six in round 1).
- B: A, with one shared mono instance across `C` made normative (sys, Phase A; withdrawn in round 1).

**Q8. The §3 user-phantom example `type Template[C] { source: Str }` (03_types.md:1391).**
- A: rename it to `Query[C]` (plt, min, devops).
- B: rename it to `Tagged[C]` (web; `Query` was this feature's pre-vote name).
- C: keep it as is.

**Q9. template-type-design.md: "C is inferred from the surrounding effect context".**
- A: replace with "C comes from the expected parameter type" (all six).
- B: keep.

</details>

<details>
<summary><b>Systems</b></summary>

### Systems panelist, Phase C ballot

#### Q1. Template surface
**Vote: A**
**Reasoning:** Plt and devops found a real hole: the runtime's `blink_template_parts` returns `t->parts` itself, and `List` is a shared cell, so `t.parts().push(evil)` launders text into the query with no `Raw` and no audit. That makes immutability a soundness condition, not a cost question. A copy of a few words per call is noise next to a driver round trip.
**Concern:** A fresh list on every call turns a careless loop such as `while i < t.values().len()` into O(n²) allocation, and nothing in the language warns the author.

#### Q2. Value accessor and `count()`
**Vote: B**
**Reasoning:** This is a position change from round 1. There I dropped `count()` on the premise that `values()` could be O(1). Q1-A now makes `values()` allocate a fresh list every time, so `count()` is the only allocation-free way to get the length, write the invariant, or bound a loop. That is a reason one method can carry. The Q1 concern is the practical case: `count()` gives users an O(1) spelling for the loop bound.
**Concern:** With two spellings of the length, some handlers will write `values().len()` in a loop condition anyway. Docs and examples must show `count()` there.

#### Q3. The value set
**Vote: B**
**Reasoning:** A BLOB is its own bind kind in every driver we would ship (`sqlite3_bind_blob`, binary params in libpq). The arm costs a pointer and a length, with no box. Plt says Shell and HTML handlers would carry an arm with no meaning, but a binary argument to a process is real, and an HTML handler can reject the arm in one line. A variant added after v1 breaks every third-party handler at once, and that cost only grows.
**Concern:** If A wins, the first BLOB user will reach for `Raw` or a base64 `Str`, and the later `Bytes` variant becomes a breaking release.

#### Q4. A hole outside the set
**Vote: A** (a change from round 1)
**Reasoning:** `Raw` folds its value in through Display formatting. So for any type where `Raw(p)` would compile, `{p.display()}` compiles too and stays parameterized. `Raw` therefore adds no repair coverage. All it adds is an unsafe path in the one line that people and models copy without reading. Devops' point stands: the compiler should not prescribe code that trips its own audit warning.
**Concern:** A type with no Display and no scalar fields can be left with no hint at all. The rule must still give each out-of-set type one repair that compiles (an explicit `match` or conversion), or §3.1 is broken again in the help text.

#### Q5. What `C` resolves to
**Vote: A**
**Reasoning:** It fixes the compiler to match the spec's shared namespace. It keeps `Template[DB]`, and `C` stays type-kinded, so generics need no v2 feature. The phantom is erased, so none of this reaches codegen. Condition 3 keeps effect subsumption out of the type relation.
**Concern:** Condition 1 still allows an effect-induced type in an argument position such as `List[DB]` or `Option[DB]`. Mono would then build a layout for an uninhabited element type. The implementation must either handle a zero-inhabitant type argument or restrict effect-induced types to phantom parameters. The ruling should say which.

#### Q6. An unresolved name in a type annotation
**Vote: A**
**Reasoning:** A silent type-variable fallback lets mono instantiate on a name nobody bound. That is the same bug in every position, not only in `Template[...]`. Blink declares its binders explicitly, so this is a conformance fix.
**Concern:** Stdlib, tests or compiler source may lean on the fallback today. Turning it into an error needs a sweep first, or it breaks the gate in one commit.

#### Q7. `C` as a type parameter
**Vote: A**
**Reasoning:** I withdrew B in round 1. Instance count cannot be observed from the language, and the one-layout-for-every-`C` rule is the part users can rely on. Sharing the instance stays a permitted implementation choice.
**Concern:** If mono does not share the instance, each context produces a copy of every generic Template helper. That is code size nobody specifies or measures.

#### Q8. The §3 user-phantom example
**Vote: B** (`Tagged[C]`)
**Reasoning:** Both names remove the W1010 shadowing, which is the part that matters. `Query` was this feature's name before the vote, so using it here would confuse readers of the decision record. `Tagged` is neutral and says what the phantom does.
**Concern:** None of substance. Whichever name wins, the example must also drop any suggestion that the real `Template` has public fields.

#### Q9. "C is inferred from the surrounding effect context"
**Vote: A**
**Reasoning:** `C` comes only from the expected parameter type. One source is simpler to implement, and resolution never has to consult the effect row.
**Concern:** None. The spec text that uses the same phrase (§3b.5 Key Design Points) must change in the same edit.

</details>

<details>
<summary><b>Web/Scripting</b></summary>

### Web/Scripting panelist, Phase C ballot

#### Q1. Template surface
**Vote: A** (opaque, immutable, and each observer returns a fresh list)
**Reasoning.** A JS or Python user reads `let ps = t.parts()` as a read. They will never guess that `ps.push(x)` rewrites the query that later reaches the DB. plt and devops found that aliasing is a live laundering path that needs no `Raw` and raises no audit warning. Also, "a template never changes after it is built" is a rule a user learns once and never has to think about again.
**Concern.** The runtime today returns `t->parts` itself, so this rule is false until the fix lands. The aliasing needs its own `type:bug` now, not after the spec text changes.

#### Q2. Value accessor and `count()`
**Vote: A** (`parts()` + `values()` only)
**Reasoning.** With only these two methods, a handler has one spelling of the loop, `for v in tpl.values()`, and one spelling of the invariant. A second spelling means two answers on Stack Overflow that drift apart, and a split surface is how fqy7bz began. The allocation per call happens right before a network or disk round trip, so no one will see it in a profile.
**Concern.** If the fresh-list copy turns out to matter for a hot local path (an in-process HTML render loop, say), someone will want `count()` or `value(i)` back. Adding a method later does not break anyone, so this is fine.

#### Q3. The value set
**Vote: B** (the four scalars + `Null` + `Bytes`)
**Reasoning.** `Null` is the 90% case for a web backend: every app has a nullable column, and 03_types.md:3155 already promises it. BLOB columns and file uploads are common too, and all six of us agree that a variant added later breaks every third-party handler at once. That break lands on users after 1.0. plt argues that a `Bytes` arm means nothing for Shell or HTML. `Null` means just as little there, so a context-free enum already accepts meaningless arms; one more costs no clarity.
**Concern.** If A wins, the first user who stores an upload will reach for `{Raw(...)}` or hex-encode by hand, and the later `Bytes` addition will be a breaking change to a prelude enum.

#### Q4. A hole outside the set
**Vote: A** (`Raw` never appears as a `help:` line)
**Reasoning.** New users apply the last help line that compiles. On an injection boundary, a help line that says "wrap it in Raw" steers them to the one unsafe fix. Users who need Raw already know it exists, because it is documented beside Template.
**Concern.** A struct with no Display and no scalar field gets no help line at all, and that error can read as a dead end. The note line that lists the allowed types has to carry that case.

#### Q5. What `C` resolves to
**Vote: A** (effect-induced nominal type, with the four conditions)
**Reasoning.** Users see `! DB.Read` in the signature and will write `Template[DB]`. That spelling has to work, and to be enforced. The marker-type option (B) would give a kind error on the most natural spelling. Marker types stay legal for pure contexts, so nothing is lost.
**Concern.** Condition 1 (an effect name is legal only as a type argument) is a new special case. Its message, "effect `DB` is not a value type", must be clear, or `fn f(x: DB)` will confuse users.

#### Q6. An unresolved name in a type annotation
**Vote: A** (an error everywhere)
**Reasoning.** Every TS user expects "Cannot find name 'Usr'". A typo that silently becomes generic is the worst kind of bug, because it compiles and then fails somewhere unrelated. One rule everywhere is easier to learn than a phantom-only exception.
**Concern.** Some stdlib or test code may depend on the fallback without anyone knowing. The implementation should sweep lib/ and tests/ before the error lands, so the gate does not surprise us.

#### Q7. `C` as a type parameter
**Vote: A**
**Reasoning.** Generic forwarding (logging, tracing middleware) is ordinary code, and users should not need to know about mono instances. The instance count cannot be observed, so it belongs in a note, not in the spec.
**Concern.** None of substance. The under-determined error on a literal with `C` unbound must name `C` and suggest a concrete context, or users will not know what to write.

#### Q8. The §3 user-phantom example
**Vote: B** (`Tagged[C]`)
**Reasoning.** All six of us agree on the rename. `Query` is the name this feature had before the 3-1-1 vote, so a reader of decisions/ would see `Query[C]` and think it is the old builtin. A domain-neutral name teaches the phantom pattern without pointing at SQL.
**Concern.** A is likely to win. That is acceptable, but the example text then needs a line saying it is unrelated to the retired `Query[C]` design.

#### Q9. "C is inferred from the surrounding effect context"
**Vote: A**
**Reasoning.** "`C` comes from the parameter's type" is a single rule that users already know from any generic function. A second, hidden inference source is exactly the kind of magic that produces "why did this compile?" questions.
**Concern.** Nothing else in the spec or the decisions should repeat the old wording. A grep of sections/ and decisions/ for "effect context" should be part of the change.

</details>

<details>
<summary><b>PLT</b></summary>

**PLT panelist — Phase C ballot**

**Q1. Vote: A**
Reasoning: The literal coercion must be the only introduction form. That holds only if no observer returns an alias into the template. `parts()` today returns `t->parts`, a shared cell (03_types.md:2342), so being opaque without immutability still leaves the laundering hole open. The fresh-list rule is the soundness condition. It is not an optimisation choice. An implementation may share storage until the first write, as long as no one can observe the sharing.
Concern: Someone may implement "fresh list" as sharing the list until the first write, and get it wrong on the `let mut` path. So a test must mutate a returned list and check that the template did not change.

**Q2. Vote: A** (I change from B)
Reasoning: I argued for `count()` as the allocation-free length. But adding a method later breaks nothing, while a second spelling of the invariant adds drift now. With one spelling, `parts().len() == values().len() + 1`, the invariant is stated once and can be checked once. The cost question can be settled later by adding a method, without a breaking vote.
Concern: With fresh-list semantics, a handler that calls `t.values()` inside a loop condition allocates on every iteration. The spec's example handler should bind `let vals = t.values()` once, so no one copies that trap.

**Q3. Vote: A**
Reasoning: F1 makes `Null` the status quo (03_types.md:3155). The non-nested restriction fixes a real problem: `Option[Option[T]]` would map `None` and `Some(None)` to the same `Null`, which is a non-injective encoding. The value enum is not indexed by the context `C`, so every Shell and HTML handler would carry a `Bytes` arm that means nothing to it. A `Bytes` added later is one loud exhaustive-match break, which is the correct failure mode before 1.0.
Concern: A nullable column is the common case, so a later `Bytes` addition will be a real breaking release for third-party handlers. That cost goes up with every month we wait.

**Q4. Vote: A** (I change from B)
Reasoning: §3.1 requires that the prescribed repair exists. Devops shows that on an injection boundary it must also preserve the property the diagnostic defends. A `Raw` hint turns a type error into an audited bypass, and `RawBypassesParam` then fires on code the compiler itself suggested. The repairs by type (`display()`, a field binding, a checked conversion) are each total and safe.
Concern: A struct with no Display and no scalar field has no hint that compiles. The implementation must then give only the note and no `help:`, not invent a repair.

**Q5. Vote: A**
Reasoning: Each effect induces an uninhabited nominal type of kind Type. This keeps a single kind and keeps `fn f[C](t: Template[C])` as ordinary v1 polymorphism. It also answers F4, where a marker type and an effect of the same name collide. Identity is the module-qualified declaration. Conditions 1-3 keep the induced type from leaking into value positions, into effect kinds, and into a false subsumption between `DB.Read` and `DB`. Condition 4 keeps pure contexts free of dummy effects.
Concern: Condition 2 is easy to lose in the implementation. If `resolve_type_ann` hands back the effect itself, and not its induced type, then `Handler[C]` with a type-parameter `C` could quietly start working as effect-kinded generics, which is a v2 feature arriving by accident.

**Q6. Vote: A**
Reasoning: A type variable must come from a binder. Anything else makes a typo quantify silently, so `fn f(x: Strr)` becomes a polymorphic function. This is the same unsoundness in every annotation position, and a rule scoped to the phantom position would leave it open everywhere else. Blink already declares its binders explicitly, so this is conformance, not new language.
Concern: Some stdlib or test code may rely on the fallback today. The fix must be measured with a corpus run and not assumed free, and each hit must get a real binder, not an exception.

**Q7. Vote: A**
Reasoning: The phantom is erased and the parameter is invariant, so parametricity holds and the instance count cannot be observed. An unobservable property belongs in a note, not in the typing rules. The rule for an under-determined literal comes from 8vcj2c with no special case.
Concern: Mono may still stamp one copy per `C`. That is code bloat only, but "permitted" must not be read later as "required" by a codegen reviewer.

**Q8. Vote: B**
Reasoning: Any non-colliding name removes the W1010 lesson. Web's point holds: `Query` was this feature's pre-vote name, and reusing it muddles the decision record. `Tagged[C]` also says what a phantom is.
Concern: The example must still show why it is phantom (distinct instantiations, neither assignable to the other). A rename must not drop that line.

**Q9. Vote: A**
Reasoning: Bidirectional checking gives `C` exactly one source: the expected type at the coercion. A second source ("effect context") would be a separate inference rule with no typing rule written for it.
Concern: No one should read this as permission to infer `C` from a `let` with no annotation. That case stays under-determined.

</details>

<details>
<summary><b>DevOps</b></summary>

### DevOps/Tooling ballot, Phase C

**Q1. Vote: A** (opaque + immutable, fresh lists)
Reasoning: B leaves the hole where `t.parts().push(evil)` launders text into a template with no `Raw` and no `RawBypassesParam`. No diagnostic can ever catch that, because nothing in the source looks wrong. A soundness rule that the tooling cannot see has to be stated in the spec, not left to the implementation.
Concern: the current runtime `parts()` returns the backing list, so until the aliasing bug is fixed the spec promises something the compiler breaks. Log it as a `type:bug` together with this ruling.

**Q2. Vote: A** (`parts()` + `values()`, no `count()`)
Reasoning: one spelling of the invariant and one loop shape (`for v in t.values()`), so completion shows two methods, not three that overlap. The fqy7bz divergence came from two spellings drifting apart, and `count()` would reopen that. PLT's allocation-free argument is real but belongs to the implementation. A handler calls `values()` once per query.
Concern: handlers that call `t.values()` inside a `while` condition allocate once per iteration. A lint for "fresh-list observer called in loop condition" may be needed later.

**Q3. Vote: A** (four scalars + `Null`)
Reasoning: F1 makes `Null` the status quo. The `Option[Option[T]]` restriction closes a silent information loss. I leaned toward `Bytes` in round 1, but PLT's point is decisive for the diagnostic surface: every Shell/HTML handler would carry a `Bytes` arm with no meaning in its context, and a meaningless arm tends to get a `_ => 0` catch-all, which turns off exhaustiveness for every later variant. A later `Bytes` addition is a loud E0004 break that names every site, which is the right failure.
Concern: a nullable `Str?` bound in a `WHERE x = {v}` hole becomes `= NULL`, which is always false in SQL. The handler docs must say `IS` vs `=` belongs to the query author, or users will file it as a compiler bug.

**Q4. Vote: A** (`Raw` never in a `help:` line)
Reasoning: users and models apply help lines without reading them. On an injection boundary, a help line that compiles into the unparameterized path is a hint that tells you to write the vulnerability. It also produces code that trips `RawBypassesParam`, so the compiler would warn about code it prescribed. §3.1 asks that a repair exist, and `.display()` and field binding cover every case. Putting `Raw` "last" does not help: the last line is the one people try once the first two fail.
Concern: a type with neither Display nor scalar fields leaves a single help line (a `match`/conversion) that is weak. The diagnostic text needs real examples for that case before release.

**Q5. Vote: A** (effect-induced nominal type, four conditions)
Reasoning: this keeps the spelling every spec example, test and stdlib file already uses, and it makes the "cannot pass" sentence true. It gives go-to-definition on `DB` in `Template[DB]` with no third namespace for the LSP to model. The four conditions each come with a clear message: "effect `DB` is not a value type", "use the parent effect `DB`".
Concern: hover and completion must show the effect-induced type as the effect, not as an anonymous uninhabited type. Otherwise `expected Template[DB], found Template[Shell]` points users to a declaration that looks empty.

**Q6. Vote: A** (unknown-type error everywhere)
Reasoning: the silent typevar fallback is the worst kind of diagnostic surface: a typo compiles, and the error, if any, appears later and elsewhere. "Cannot find type `Usr`, did you mean `User`?" at the annotation is the rust-analyzer/tsc baseline, and Blink's explicit binders make it cheap.
Concern: stdlib or tests may depend on the fallback without anyone knowing. Sweep the corpus with the new error before enforcing it, so the release does not ship a wave of new errors in existing code.

**Q7. Vote: A** (ordinary generics; shared instance in a non-normative note)
Reasoning: a user or a tool cannot observe the instance count, so it does not belong in normative text. The under-determined case reuses the existing 8vcj2c diagnostic instead of inventing one.
Concern: the E0301 message for an unbound `C` must name `Template[C]` and suggest annotating the context, not print a generic "cannot infer type".

**Q8. Vote: B** (`Tagged[C]`)
Reasoning: the aim is to stop the example raising W1010 and to stop it looking like the builtin. `Query` was this feature's pre-vote name, and a reader of the decision history would take it for the builtin again. A neutral name removes both confusions.
Concern: none of substance. I accept A if it wins.

**Q9. Vote: A** (C comes from the expected parameter type)
Reasoning: one inference source means one place for the "cannot determine context" diagnostic to point to: the parameter annotation.
Concern: none.

</details>

<details>
<summary><b>AI/ML</b></summary>

### AI/ML panelist, Phase C ballot

#### Q1. Template surface: **A** (opaque type, immutable, fresh lists)
**Reasoning.** Plt's `launder` example shows that "methods only" is not enough while `parts()` aliases the stored list: `ps.push(evil)` alters the SQL text with no `Raw` and no audit. A model writing generic middleware will call `.push` on a returned list without a second thought. So the only safe rule is one where no call a model can make changes the template. "Returns a fresh list" is one sentence and needs no exceptions.
**Concern.** The spec may say "fresh list" while the runtime keeps returning the stored `t->parts`, as it does today. The aliasing bug must be logged and get a test that fails today, not live on as prose.

#### Q2. Accessor and `count()`: **A** (`parts()`, `values()`, no `count()`)
**Reasoning.** `for v in tpl.values() { match v {...} }` is the loop with the most training data, and it has no index arithmetic to get wrong. Plt's point that `count()` is the only O(1) length is fair, but it trades one allocation per query for a second spelling of the invariant. A second spelling is the exact drift that produced fqy7bz. If a copy-free path is ever needed, adding a method later breaks nothing.
**Concern.** Handlers that need the 1-based bind index will write `let mut i = 0` plus `i = i + 1` in the wrong place, binding at 0. The spec's handler example should show the counter bumped once, at the top of the loop, so models copy a correct pattern.

#### Q3. Value set: **A** (Int, Float, Bool, Str, Null)
**Reasoning.** This is F1 as the spec writes it, so no amendment is needed. `Null` covers the most common nullable-column case, and `.Null => bind_null` is an obvious arm. Plt's point decides `Bytes` for me: an enum shared by every context would force Shell and HTML handlers to carry a `Bytes` arm with no meaning there. That is a decision point with no right answer, which is the worst kind for a model. Adding `Bytes` later is a loud, compile-time break. I accept that cost.
**Concern.** The first third-party BLOB handler hits the gap and works around it with a base64 `Str`. That is a silent data-shape bug we could have avoided.

#### Q4. Out-of-set hole: **A** (`Raw` never appears as a `help:` line). I change my vote
**Reasoning.** I proposed "Raw last", but devops, web and min make my own domain's argument better than I did: models apply help lines without reading them, and in any order. A `Raw` hint on an injection boundary is a generated injection that then fires `RawBypassesParam` on code the compiler suggested. `Raw` stays learnable from §3b.5, where it comes with its audit context.
**Concern.** A hole type with no Display and no scalar field then gets only a `note:` and no working `help:`. The spec must list the per-type hints fully, so that no type is left with an empty help list.

#### Q5. What `C` resolves to: **A** (any type-namespace declaration, nominal, four conditions)
**Reasoning.** `Template[DB]` next to `! DB.Read` is the spelling every spec example teaches, and a model will write it. A kind error on that spelling is the worst learnability outcome. Marker types stay legal for pure contexts, and `C` stays type-kinded, so generics work in v1. Each of the four conditions is one plain sentence and has a diagnostic that names its fix.
**Concern.** Condition 1 (an effect name is legal only as a type argument) means `List[DB]` is legal but pointless. Models may produce odd code like `Map[Str, DB]` that compiles and means nothing. A lint may be needed later.

#### Q6. Unresolved type name: **A** (error in every annotation)
**Reasoning.** One rule, "type variables come only from `[T]` or `Self`", is guessable. A phantom-only rule is a special case that no model can infer. A typo such as `fn f(u: Usr)` silently becoming generic is the same bug in every position.
**Concern.** Some stdlib or test code may depend on the fallback today, so the fix could land as a large breaking change that someone is tempted to scope back down quietly.

#### Q7. Generic `C`: **A** (ordinary generics; mono sharing in a non-normative note)
**Reasoning.** Instance sharing cannot be seen by a user or a model, so it does not belong in normative text. Min's rule, that an unbound `C` gets the existing under-determined error E0301, adds zero new rules to learn.
**Concern.** An E0301 on a Template literal may read oddly. The help text must name the type-argument fix (`f[DB](...)`), not a generic "annotate the binding".

#### Q8. The §3 phantom example: **B** (`Tagged[C]`)
**Reasoning.** `Query[C]` was this feature's pre-vote name, and in training data it means SQL. A model reading `Query[DB]` in the phantom example will assume it is the DB-template feature under an old name, which is the confusion the rename exists to remove. `Tagged` is neutral, collides with nothing, and teaches only the phantom mechanism.
**Concern.** Whatever name wins, the example must also drop `Template[DB]`/`Template[Shell]` in favour of neutral marker types. Otherwise it still suggests a link to the builtin.

#### Q9. "C is inferred from the surrounding effect context": **A** (replace with "C comes from the expected parameter type")
**Reasoning.** One source of `C` is one rule to learn. "Inferred from effect context" invites models to omit the type and expect the compiler to guess from the `!` clause.
**Concern.** Other prose, such as the §3b.5 intro and `blink llms` topics, may still carry the old wording. The docs sweep has to cover the llms output too, not only decisions/.

</details>

<details>
<summary><b>Minimalism</b></summary>

### Minimalism panelist, Phase C ballot

**Q1. Vote: A.**
Reasoning: An opaque type with observers only is smaller than a struct, because it has no constructor and no field surface. The immutability rule is not an addition. Without it, `t.parts().push(x)` in generic middleware launders text past E0310 with no `Raw` and no audit, and that is a soundness hole, not a style point. The rule is one sentence, and it removes a whole class of bug.
Concern: If an implementation hands out the backing list "for speed", it breaks the rule without any message. The rule needs a test that mutates a returned list and checks the template is unchanged.

**Q2. Vote: A.**
Reasoning: With `values()` in the surface, `count()` is a second spelling of `values().len()`, and fqy7bz exists because the invariant already had two spellings. PLT's point is that `count()` is the only O(1) length once `values()` copies. It is fair, but it is an implementation cost: copy-on-write or a cached list removes it, and a handler calls `values()` once to iterate anyway. A spec method should not exist to work around a copy the runtime can avoid.
Concern: If the implementation copies eagerly, handlers that call `t.values().len()` in a loop condition pay O(n) per test, and someone will ask to add `count()` back. That is a legitimate later request, and it is cheap to add.

**Q3. Vote: A (four scalars + `Null`, no `Bytes`).**
Reasoning: `Null` is not an addition, because 03_types.md:3155 already admits `Option[T]`. Leaving it out would amend the spec. `Bytes` *is* an addition, and no spec line or in-tree handler needs it. PLT's point decides it: the enum is context-independent, so every Shell and HTML handler would carry a `Bytes` arm with no meaning in its context. When a driver needs BLOBs, a later variant is one loud E0004 break. That is the correct failure mode, and it costs little before 1.0.
Concern: Adding `Bytes` after third-party handlers exist is a breaking change to a prelude type. If the ecosystem grows before a BLOB need appears, we will pay that break then, not now.

**Q4. Vote: A (`Raw` never appears as a `help:` line).**
Reasoning: The `help:` lines must be repairs that exist (§3.1) and that are safe on an injection boundary. A `Raw` hint on a type error trains users, and models, to take the bypass, and then `RawBypassesParam` fires on code the compiler suggested. `Raw` already has its own documented, audit-gated door, so the help line adds nothing but risk.
Concern: A struct with no Display and no scalar fields gets few or no hints. The diagnostic must still say *why* (the value set is closed) so the user does not reach for `Raw` on their own.

**Q5. Vote: A.**
Reasoning: The spec already shares one namespace (F4). "An effect induces an uninhabited nominal type, legal only as a type argument" fixes the vacuous check with no new namespace, no respelling of stdlib, and no v2 dependency. Marker types stay legal for pure contexts. The four conditions keep the change small: no value-position use, no leak into `Handler[E]`, top-level effects only, identity by declaration.
Concern: "Effect-induced type" is a new idea inside the type checker. If the "argument position only" condition is not enforced at every annotation site, it leaks, and we get uninhabited parameter types by accident.

**Q6. Vote: A (error everywhere).**
Reasoning: One rule ("a type variable comes only from a declared binder or `Self`") is smaller than a phantom-only exception, and it closes the same silent-generic typo bug in every position. The spec already implies it, since Blink declares binders explicitly.
Concern: Stdlib or tests may rely on the fallback today. The implementation must sweep for it before it lands, or the gate breaks in unrelated places.

**Q7. Vote: A.**
Reasoning: This is ordinary generics with no special case, and 8vcj2c already covers an unbound `C` at a literal. How many mono instances exist cannot be observed from the language, so it belongs in a non-normative note.
Concern: A non-normative note on sharing may be ignored, and mono will then copy a handler body per context. That costs code size but is still correct.

**Q8. Vote: B (`Tagged[C]`).**
Reasoning: The goal is to stop the example shadowing a builtin. `Query` was this feature's own pre-vote name, so a reader of the decision history could take the example for the old design. `Tagged` names only what the example shows: a phantom tag on a value.
Concern: Some other spec section may already use `Tagged` for a different example. Check with a grep before the edit.

**Q9. Vote: A.**
Reasoning: One source for `C` (the expected parameter type) is smaller than two. "Inferred from effect context" was never implemented, and it would be a second inference path.
Concern: None of substance. The decision file and §3b.5 Key Design Points must both change, or they will disagree again.

</details>

#### Phase D — Scope of an effect-induced type (D1)

The user added this round after the tally, from four Phase C concern fields.

- **D1:** D1-A, any type-argument position — **5-1** (web dissent). `List[DB]` is legal and always empty, as `List[Never]` is.

<details>
<summary><b>Phase D brief</b></summary>

### Phase D: one focused round on the scope of an effect-induced type

The user (BDFL) has signed off on the Phase C tally: Q1-Q9 as voted, with Q3 (no `Bytes`) accepted as
soft consensus. Those are decided and not open here.

One question is open. It came from Phase C concern fields, quoted verbatim:

- **sys (Q5 concern):** "Condition 1 still allows an effect-induced type in an argument position such as
  `List[DB]` or `Option[DB]`. Mono would then build a layout for an uninhabited element type. The
  implementation must either handle a zero-inhabitant type argument or restrict effect-induced types to
  phantom parameters. The ruling should say which."
- **aiml (Q5 concern):** "Condition 1 (an effect name is legal only as a type argument) means `List[DB]`
  is legal but pointless. Models may produce odd code like `Map[Str, DB]` that compiles and means
  nothing. A lint may be needed later."
- **min (Q5 concern):** "If the 'argument position only' condition is not enforced at every annotation
  site, it leaks, and we get uninhabited parameter types by accident."
- **plt (Q5 concern):** "If `resolve_type_ann` hands back the effect itself, and not its induced type,
  then `Handler[C]` with a type-parameter `C` could quietly start working as effect-kinded generics,
  which is a v2 feature arriving by accident."

**Question D1: In which type-argument positions may an effect-induced type appear?**

Options as sys worded them (you may propose another, with a Blink example):
- D1-A: any type-argument position; the implementation handles a zero-inhabitant type argument
  (sys, option 1; aiml's text reads this as the status quo of condition 1).
- D1-B: phantom type parameters only (sys, option 2).

Codebase facts (facts, not votes):
- F5. sections/03_types.md:1621 treats a phantom parameter as "a type parameter named by no field",
  determined only by an annotation or a type-argument list. The spec has no separate "phantom
  parameter" kind or declaration marker; `Template[C]`'s `C` is phantom by that use.
- F6. `Never` (sections/03_types.md:989, §2.20) is the spec's bottom type: it has no values and is a
  subtype of every type. A program may write it as a type argument (03_types.md:1646 cites
  `Result[Int, Never]`).

This is a single round. Write your reply to this directory as D_<yourname>.md with:
1. **Position** (D1-A, D1-B, or a new option you state with an example).
2. **Reasoning**: 2-4 sentences from your domain.
3. **Vote**: your final vote on D1 (a new option counts; the moderator tallies all options named).
4. **Concern**: one sentence on what could go wrong with the option you expect to win.

Read the other panelists' Phase C ballots (C_*.md) if you have not. Do not message other panelists.
Reply "done" to team-lead.

</details>

<details>
<summary><b>Systems</b></summary>

### Systems panelist, Phase D

#### Position: D1-A, with the layout stated

An effect-induced type may appear in any type-argument position. Its runtime layout is the same as a marker type with no fields (`type Html {}`). It has no constructor, so no value of it ever exists. I withdraw the option 2 half of my own Phase C concern.

```blink
fn fwd[C](t: Template[C]) -> List[Template[C]] {
    let mut out: List[Template[C]] = List.new()
    out.push(t)
    out
}
let xs: List[DB] = List.new()     // legal; always empty
fn f(x: DB) -> Int { 0 }          // still an error (condition 1): effect `DB` is not a value type
```

#### Reasoning

1. **F6 and marker types already cover the codegen cost I raised.**
   - `List[Html]` with `type Html {}` is legal today, so mono already builds layouts for an element type with no fields.
   - `Result[Int, Never]` is legal today, so codegen already handles a type argument that has no values.
   - An effect-induced type reuses the empty-struct layout. It needs no new machinery and adds no runtime cost, which answers the question I asked.

2. **D1-B cannot be enforced at typecheck.**
   - F5: "phantom" is not a kind the spec declares. It is a property of use: a type parameter that no field names.
   - Through generics, `C` bound to `DB` in `fn fwd[C]` flows into `List[C]` inside the body. So "phantom positions only" is known for certain only after mono.
   - That is a rule enforced only at codegen, which §3.1 forbids.
   - Doing it at typecheck would need a new phantom-parameter marker and a propagation analysis across every generic declaration. That is new language to prevent something harmless.

3. **Harmless, because no value exists.** `List[DB]` can only ever be empty. `fn h[T](x: T)` instantiated at `DB` can never be called. Nothing uninhabited reaches a runtime slot that needs a real value.

4. **The pointless-code worry is a lint question.** Aiml's `Map[Str, DB]` belongs in a lint that can be added later, not in the type rules.

#### Vote

**D1-A.** The implementation lowers an effect-induced type exactly as a field-less nominal type. Condition 1 (never as a direct value annotation) holds at typecheck.

#### Concern

Plt's point is the real risk under D1-A. If `resolve_type_ann` returns the effect declaration rather than a separate induced type, the same path that makes `List[DB]` work could let `Handler[C]` with a type parameter `C` start working. That would ship effect-kinded generics by accident. The implementation needs a test asserting that `fn f[C](h: Handler[C])` is still a kind error.

</details>

<details>
<summary><b>Web/Scripting</b></summary>

### Web/Scripting panelist, Phase D

#### 1. Position

**D1-B: phantom type parameters only**, with phantom defined by F5 (a type parameter named by no field) and checked at typecheck.

```blink
type Tagged[C] { source: Str }         // C is named by no field: phantom

fn run(t: Template[DB]) -> Int { 0 }   // ok: Template's C is phantom
let x: Tagged[DB] = Tagged { source: "a" }   // ok: user phantom, on the same terms (8w0yj9)
fn fwd[C](t: Template[C]) -> Int { 0 } // ok: fwd(t) with t: Template[DB] binds C = DB, used only in a phantom slot

let xs: List[DB] = []                  // error: effect `DB` has no values, so it cannot be a List element
                                       //   = note: an effect name is allowed only as a context marker, e.g. Template[DB]
fn f(m: Map[Str, DB]) { }              // error: same message
```

For a generic fn, the check runs where a type parameter bound to an effect-induced type reaches a non-phantom slot: at the explicit type application, or at the annotation that makes the call. For example, `make_list[DB]()` where `make_list[T]() -> List[T]` is an error at that call. This happens in typecheck, not codegen (§3.1).

#### 2. Reasoning

`List[DB]` compiles to nothing a user can use. It can never hold an element, and "why does my empty list of effects type-check?" is a Stack Overflow question we should not create. A JS/TS user reads `List[DB]` as a list of database handles and tries to push one, and D1-A lets that confusion compile. One plain sentence covers D1-B: "an effect name is a context marker: it may appear only where a type is a tag, like `Template[DB]`". F6 shows the spec already has a real empty type, `Never`, for the rare case where someone wants an uninhabited argument. We need no second one, and the effect name does not need to double as it.

#### 3. Vote

**D1-B.**

#### 4. Concern

The generic-fn case (a type parameter bound to `DB` that reaches `List[T]` inside a callee's signature) must fire at the call site with a message that names both `DB` and the callee's `T`. If it fires only deep inside the instantiated body, or at mono, the user gets an error on code they did not write.

</details>

<details>
<summary><b>PLT</b></summary>

**PLT panelist — Phase D**

**Position: D1-A** (any type-argument position), with one clarification.

**Reasoning.**
D1-B is not stable under substitution, so it cannot be enforced soundly. Take `fn g[C](t: Template[C]) -> List[C] { [] }`. It is legal as written, because `C` is an ordinary binder. At the call `g(q)` with `q: Template[DB]`, mono instantiates `List[DB]` anyway. The only way to stop that is to track "may carry an effect-induced type" through binders. That is a new kind, or a phantom marker on declarations, and F5 says the spec has neither. D1-A also costs nothing new: F6 shows the language already admits an uninhabited type argument (`Result[Int, Never]`, and so `List[Never]`). An effect-induced type is a nominal uninhabited type without `Never`'s subtyping, so mono already needs whatever layout it uses for `Never`, since no value of that type is ever built.

**Clarification of condition 1.** Condition 1 ("argument position only", so `fn f(x: DB)` is an error) is a rule about what may be *written*. It does not hold under substitution: `fn h[T](x: T)` at `T := DB` has a parameter of an uninhabited type. That is sound and harmless, because the function can never be called, exactly as with `T := Never`. The ruling should say so, so that no one "fixes" it with a kind check that repeats the D1-B problem.

**Vote: D1-A.**

**Concern.** If the implementation gives an effect-induced type argument a different layout path from `Never` (for example, by returning the effect entry from `resolve_type_ann`), `List[DB]` could reach an ICE at codegen and break §3.1 again. A corpus test for `List[DB]` and for `g[C] -> List[C]` at `C := DB` should gate the change.

</details>

<details>
<summary><b>DevOps</b></summary>

### DevOps/Tooling, Phase D

#### 1. Position: D1-A (any type-argument position), plus a non-normative note that permits a later warning lint

#### 2. Reasoning

**D1-B has no good error site.** F5 says the spec has no phantom-parameter *kind* or marker. A parameter is phantom only because no field names it. So D1-B must follow an effect-induced type through generic binders:

```blink
fn wrap[C](t: Template[C]) -> List[C] { [] }   // C used in a non-phantom position
fn go(q: Template[DB]) { let xs = wrap(q) }      // D1-B: error here? in wrap? at mono?
```

- If D1-B reports this at mono time, that breaks §3.1's rule that no rule is enforced only at codegen.
- If D1-B reports it at typecheck, it needs a new "phantom-only" kind on type binders. That is a v2-sized feature, and the error would send the user from the call site into a body they may not own.

A diagnostic with no good site is the kind of rule I reject.

**D1-A costs nothing new.** F6: `Never` is already an uninhabited type that a program may write as a type argument (`Result[Int, Never]`). Mono must already build layouts over a zero-inhabitant argument. An effect-induced type needs the same path, not a new one. This settles sys's concern without a new rule.

**`List[DB]` is odd but not wrong.** The list can only ever be empty, and nothing is unsound. That is a lint question, not a type-rule question (aiml's concern). Tooling can add a warning later, for example `EffectTypeAsElement`, at a written annotation where an effect-induced type fills a parameter that some field names. It fires at the annotation only, never through generics, and suggests `Template[DB]` or a marker type. It needs no vote now: put it in a note as permitted, not required.

**min's leak concern is already covered.** Condition 1 is checked where a type is written, and a written annotation is the only place a bare `DB` can appear. Generics cannot bring `DB` into a value position: `fn f[C](x: C)` called with `C = DB` has no value to pass. So that path is unreachable, not a leak.

**plt's concern is an implementation invariant that fits any D1 option.** Resolution returns the induced *type*, never the effect. It belongs in the ruling text as a normative sentence ("an effect name in type-argument position denotes its induced type; `Handler[E]` still requires an effect"), with a typecheck test for `fn f[C](h: Handler[C])` staying a kind error.

#### 3. Vote: D1-A

#### 4. Concern

A zero-inhabitant argument can reach code paths that `Never` never exercised, for example `Map[Str, DB]` with key/value kops, or a `@derive(Debug)` over a field `Option[DB]`. Mono and derive need a test for each container over an effect-induced type before the ruling is marked implemented, or the first `List[DB]` a model writes becomes an ICE, which is the §3.1 failure this ruling set out to remove.

</details>

<details>
<summary><b>AI/ML</b></summary>

### AI/ML panelist, Phase D

#### Position: D1-A (any type-argument position), with `Never` named as the precedent

The rule as a model should learn it is two sentences:

- An effect name in a type position is a type with no values.
- It may be written as any type argument. It is never the type of a value directly: `fn f(x: DB)` and `let x: DB` are errors, per Q5 condition 1, which stands.

`List[DB]` and `Option[DB]` compile, exactly as `List[Never]` and `Result[Int, Never]` do today (F6).

```blink
fn sink(t: Template[DB]) -> Int { t.values().len() }   // the intended use
fn odd(xs: List[DB]) -> Int { xs.len() }               // legal, always 0; no error
fn bad(x: DB) -> Int { 0 }                             // error: effect `DB` is not a value type
```

#### Reasoning

D1-B is not a rule a model can apply from the call site. F5 says "phantom" is not a declared kind. It is a property of the declaration body: no field names the parameter. So to know whether `Foo[DB]` is legal, a model must read `Foo`'s fields. Worse, the property must pass through generics. With `fn g[T](x: Template[T]) -> List[T]`, the call `g[DB](...)` would be rejected for a reason inside the callee. That is a diagnostic that points away from the edit the user can make.

D1-A needs no new idea. `Never` already puts a type with no values into type-argument positions, so mono must handle that case today (sys's option 1 is a cost we already pay). The only thing D1-A allows that D1-B forbids is code that is useless but harmless: an empty `List[DB]` can never hold a value, and it cannot cause an injection.

#### Vote: **D1-A**

#### Concern

Useless shapes such as `Map[Str, DB]` will compile with no message. So I still want a later lint, a warning and not an error: "effect-induced type `DB` in a non-phantom position has no values". It should be filed as a follow-up so it is not forgotten. It must not become a hard error, which would bring back the D1-B diagnostic problem.

(Plt's `Handler[C]` concern is a separate issue. Q5 condition 2 covers it: the induced type is not the effect. D1-A does not weaken that.)

</details>

<details>
<summary><b>Minimalism</b></summary>

### Minimalism panelist, Phase D

**Position: D1-A.** An effect-induced type may appear in any type-argument position. It behaves as a nominal type with no values, laid out the same way the compiler already lays out `Never` as a type argument (F6). It is **not** a subtype of anything, so it does not share `Never`'s subtyping. Condition 1 still bans it as the direct type of a value (`fn f(x: DB)`, `let x: DB`).

```blink
fn a(t: Template[DB]) -> Int { 0 }          // ok: the intended use
fn b(xs: List[DB]) -> Int { xs.len() }      // ok: legal, always empty, pointless
fn c(x: DB) -> Int { 0 }                    // error: effect `DB` is not a value type
```

**Reasoning.**

1. D1-A adds no mechanism. The spec already has a type with no values that programs pass as a type argument (`Result[Int, Never]`), so mono already has to handle a type argument with no values. The effect-induced type reuses that path.

2. D1-B adds a rule, and the rule cannot be checked where the spec requires. By F5, being phantom is not something a declaration states. It is derived: "named by no field". Inside a generic body it is not decidable at all:

   ```blink
   fn f[C](t: Template[C]) -> Int {
       let xs: List[C] = []   // legal only if C is not effect-induced
       xs.len()
   }
   ```

   `f(db_template)` binds `C` to `DB`, and only then does `List[C]` become `List[DB]`. D1-B can reject this only at instantiation, and that is a mono-time rule, which §3.1 forbids ("no rule enforced only at codegen"). Rejecting it at definition would need a kind or bound that separates "effect-induced" from "any type", which is the second kind that we voted not to add in Q5.

3. D1-B also makes phantom-ness part of a type's API by accident. If a library adds a field that uses `C` to `Tagged[C]`, every user's `Tagged[DB]` breaks, and the declaration itself says nothing about that risk.

**Vote: D1-A.**

**Concern:** `List[DB]` and `Map[Str, DB]` will compile and mean nothing. Models will sometimes write them. If that shows up in practice, the fix is a lint ("effect-induced type in a non-phantom position"), not a type rule. A lint may warn on a derived property without breaking §3.1, and it can come later, when the need is real.

</details>

### Final Spec

```blink
// Opaque, immutable, compiler-known. No fields, no constructor.
// t.parts()  -> List[Str]             fresh list each call
// t.values() -> List[TemplateValue]   fresh list each call
// t.parts().len() == t.values().len() + 1

enum TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str), Null }

fn bind_template(stmt: Sqlite3Stmt, tpl: Template[DB]) -> Int {
    let vals = tpl.values()
    let mut i = 0
    for v in vals {
        i = i + 1                        // SQL parameters count from 1
        let rc = match v {
            TemplateValue.Int(n) => sqlite_bind_int(stmt, i, n)
            TemplateValue.Float(f) => sqlite_bind_double(stmt, i, f)
            TemplateValue.Bool(b) => sqlite_bind_int(stmt, i, if b { 1 } else { 0 })
            TemplateValue.Str(s) => sqlite_bind_text(stmt, i, s)
            TemplateValue.Null => sqlite_bind_null(stmt, i)
        }
        if rc != 0 { return rc }
    }
    0
}
```

- `Template[C]` is opaque. Only the literal coercion and `Raw` folding build one. Each observer returns a fresh list, so a caller cannot change a template.
- `count()`, `type_tag`, `get_*` and `TPL_*` retire through the 3-step path.
- Hole types: `Int`, `Float`, `Bool`, `Str`; `I8`/`I16`/`I32`/`U8`/`U16`/`U32` widen to `Int`; `F32` widens to `Float`; `Option[T]` of a non-Option member (`None` → `Null`). `Char`, `U64` and `Option[Option[T]]` are excluded.
- Any other hole type is `TemplateHoleType` (E0534) at typecheck. Its `help:` lines depend on the type; `Raw` is never offered.
- An effect name used as a type denotes an uninhabited nominal type. It is written only as a type argument (`EffectTypeAsValue`, E0535), never enters effect positions, and only a top-level effect gives one (`SubEffectAsType`, E0536). Any type-argument position is allowed (D1-A).
- `C` comes from the expected parameter type. A generic `C` is an ordinary invariant binder; an unbound `C` is E0301.
- An unknown name in any type annotation is E0507, never a type variable.
- The §3 phantom example is `Tagged[C]` with marker types `Meters` and `Feet`.
