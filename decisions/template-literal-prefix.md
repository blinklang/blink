[< All Decisions](../DECISIONS.md)

# Template Literal Prefix (`t"..."`) — Design Rationale

The gap: the meaning of a string literal depended on the type the site expected. A plain `"..."` literal turned into a `Template[C]` where a `Template[C]` was expected, and the shipped compiler did this only for a literal written directly as a call argument. The panel replaced the coercion with a prefix: `t"..."` makes a template literal, and a plain `"..."` is always a `Str`.

The spec text is in §2.4.3 *Template Literals* and §3b.5 *Context-Sensitive Template Types*.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist's text below is verbatim.

#### Brief

<details>
<summary>Moderator brief sent to every panelist</summary>

#### Panel brief — spec gap d9sc2p

##### The spec gap (br ticket, verbatim)

Title: Spec: string literal meaning depends on the expected type

Problem: the same string literal is Str concat or a Template[DB] with params, chosen by the expected type. An agent cannot tell which from the text.
Evidence: 02_syntax.md:152.
Principle: local reasoning; no type-directed change of meaning.
Proposal (for panel): put an explicit tag on template literals (for example sql"...").

##### Current spec text (facts)

sections/02_syntax.md (§2.4, string literals), verbatim:

> **Context-sensitive interpolation.** When an interpolated string literal appears where `Template[C]` is expected (e.g., `db.query_one("SELECT * FROM users WHERE id = {id}")`), the compiler extracts `{expr}` as bound parameters instead of concatenating. The *receiving type* determines behavior: `{id}` in a `Str` context is concatenation, `{id}` in a `Template[DB]` context is parameterization. No new string syntax is needed — the same `"..."` literal does the right thing based on where it appears. See section 3.12 for details.

The full rules live in sections/03b_contracts.md §3b.5 "Context-Sensitive Template Types" (read it: lines ~634-900) and §9.3 in sections/07_trust_modules_metadata.md (~line 1505). Key normative points there:
- `Template[C]` is opaque, immutable, no fields, no constructor. Only the literal coercion and `Raw` folding build one. Observers: `parts() -> List[Str]`, `values() -> List[TemplateValue]`.
- §3b.5: "At the coercion, the literal takes `C` from the type the site expects, by the same bidirectional check as any other expression. `C` is never inferred from the effects in the enclosing signature."
- §3b.5: a pre-built `Str` variable cannot be passed where `Template[C]` is expected (`let q: Str = "...{id}"; db.query_one(q)` is a compile error). "The auto-decomposition only works on string *literals* at the call site."
- `Raw(expr)` is a real marker type `Raw[T]`; folding it into a template raises the audit-gated warning `RawBypassesParam`; a `Raw[T]` anywhere else is `RawOutsideTemplate` (E0530).
- Hole types are restricted (`TemplateHoleType`, E0534) to Int-family, Float-family, Bool, Str, Bytes, Option of those, Raw[T].

##### Already decided (prior panel votes — constraints, not options)

From DECISIONS.md and decisions/template-*.md:
- Interpolation injection safety: `Template[C]` structural+phantom type; compiler decomposes the interpolated string into parts/values; handler reassembles with dialect-specific syntax. Taint tracking deferred to v2. (3-0 original, refined 3-1-1 / 3-2 / 4-1). The original design's stated goal: "makes the obvious code the safe code without changing developer syntax."
- Naming `Template` over `Query`/`Interpolation` (3-1-1).
- Structural+phantom type identity (4-1).
- `Raw(expr)` per-interpolation escape hatch (2-1); later made a real marker type `Raw[T]` with no Display (6-0); `RawOutsideTemplate` E0530.
- Display and Template[C]: Display is Str-context only; Template holes pass raw typed values (5-0).
- Template Surface (decisions/template-surface.md): opaque + immutable (6-0); `parts()`/`values()` (5-1); closed `TemplateValue` enum (4-2, later + Bytes 6-0); `TemplateHoleType` E0534 (6-0); effect name denotes an uninhabited nominal type usable as `C` (6-0); **Q9: "C comes from the expected parameter type", replacing "C is inferred from the surrounding effect context" (6-0)**.
- Backtick suppression inside strings rejected (6-0); `\{` and `#"..."#` are the brace escapes.
- §3.4 Explicit Type Application: bidirectional checking; brackets for under-determined binders.

##### Facts from the current compiler (gen1, built from today's main)

Probe, with `type Ctx {}` and `fn sink(t: Template[Ctx]) -> Int`:
- `sink("x = {id}")` — accepted (literal directly as a call argument).
- `sink(#"raw {id}"#)` — accepted.
- `let t: Template[Ctx] = "y = {id}"` — rejected: `error[TypeError]: variable `t`: declared type Template[Ctx] but got Str`.
- `sink(if id > 2 { "p {id}" } else { "q" })` — rejected: `error[TemplateMismatch]: expected Template[Ctx], found Str — string variables cannot be implicitly converted to Template`.
So the compiler coerces only a literal written directly as a call argument; the spec text says "where `Template[C]` is expected ... by the same bidirectional check as any other expression". (The `parts()`/`values()` surface is not yet implemented; the shipped compiler still has `count()`/`type_tag`/`get_*`.)

Usage: `Template[C]` appears in lib/std/db.bl and lib/std/db_sqlite.bl (DB effect ops `query`, `query_one`, `prepare`, `exec`, `execute`, all `sql: Template[DB]`) and in tests. No file in examples/ uses it.

##### Sibling open spec tickets (facts; not in scope, but any answer here must compose with them)

- jfwr2r "Spec: universal string interpolation forces escapes in brace text". Verbatim: "Problem: every string interpolates {}, so JSON and other brace text needs escapes. Two escape forms exist: \{ and #"..."#. ... Principle: match LLM priors; one way to do it. Proposal (for panel): require an explicit marker for interpolation, or keep one escape form only."
- caqzsw "Which T may a Raw[T] wrap in a Template[C]?"
- h313w9 "Spec: language surface is too large" (surface-reduction pass).

##### Blink syntax reminders for code examples

`fn` keyword, `{ }` braces, no semicolons, double quotes for strings, `.len()` method-call style, `[T]` for generics, effects after `!` (e.g. `-> Result[Row, DBError] ! DB.Read`), `type Name { ... }` for structs/enums. Run `blink llms --topic <name>` (use `build/gen1/bin/blink llms ...`) if you need syntax detail. You may read any file in /home/nhumrich/blinklang/blink. Do NOT edit any repo file.

</details>

#### Phase A — Independent proposals

Every panelist put forward the same first choice: a `t` prefix that makes a template literal, with a plain `"..."` always a `Str`.

<details>
<summary><b>Systems</b></summary>

##### Systems position: an explicit `t"..."` template literal; `C` still comes from the expected type

###### The problem, seen from codegen
The same text `"SELECT ... {id}"` compiles to two different programs:
- In `Str` context: a format buffer is allocated, `Display` runs on each hole, and the result is one heap string.
- In `Template[C]` context: a parts list and a values list are built, `Display` never runs, and each hole gets its own type-tagged value.

The allocation pattern, the cost, and the security property all change, and the text gives no sign of it. That is the kind of hidden cost I object to. The compiler also makes this choice only for a literal written directly as a call argument (the `let` form and the `if` form both fail today), so the spec's "same bidirectional check as any other expression" is not what ships. The rule is harder to state than it looks.

###### Proposal S1 (my preference): the prefix `t` marks a template literal

```blink
fn get_user(id: Int) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn find(name: Str, active: Bool) -> Result[List[Row], DBError] ! DB.Read {
    let q: Template[DB] = if active {
        t"SELECT * FROM users WHERE name = {name} AND active = 1"
    } else {
        t"SELECT * FROM users WHERE name = {name}"
    }
    db.query(q)
}

let raw_q: Template[DB] = t#"SELECT '{"k": 1}' WHERE id = {id}"#   // raw form composes
```

Rules:
1. `t"..."` (and `t#"..."#`) has type `Template[C]`. `C` comes from the expected type by the normal bidirectional check, so it works in a `let` with a type, in `if`/`match` arms, and in returns. No checking position is special. With no expected type, `C` is under-determined and the error tells you to add an annotation (§3.4 rule).
2. A plain `"..."` is always `Str`. A plain literal where `Template[C]` is expected is an error. The fix is one character: `help: write t"..."`.
3. `t"..."` where `Str` is expected is an error. `Template` has no `Display` and no conversion to `Str`.
4. `Raw(expr)` is legal only inside a `t"..."` hole. That makes E0530 a simple syntactic check.

**Why this is better for systems work:**
- **You can read the codegen from the text.** `t"..."` lowers to a static, read-only parts array (the parts are compile-time constants, known in full at the literal) plus one values array built from the holes. There is no formatting and no `Display` dispatch. A plain `"..."` never builds a `Template`. You can predict the cost of every literal without knowing its expected type.
- **The parts can live in `.rodata`.** That is allowed now, but it is a lowering detail of a special coercion. With a separate literal kind, it is the normal lowering. Handlers can cache prepared statements keyed by the address of the parts array, which gives a free statement-cache key per call site, with no hashing.
- **Safety stays the same.** The obvious code is still safe: `db.query_one("... {id}")` does not compile, so it cannot inject. The type gives the safety. The tag only removes the guessing. Forgetting the `t` costs a compile error, never a vulnerability.
- **The compiler gets simpler.** The "literal directly as an argument" check in typecheck goes away. A template literal is an ordinary expression with an ordinary type.

**Cross-language:** Python 3.14 (PEP 750) chose the same thing: `t"..."` gives a `Template` with `.strings` and `.interpolations`, next to `f"..."`. JS tagged templates (`` sql`...` ``) and Rust's `format_args!` (a separate, lazily formatted value) also mark the literal. No mainstream language picks the meaning of a string literal from its expected type. Swift's `ExpressibleByStringInterpolation` comes closest, and it is a well-known source of "which overload did I hit" confusion. LLM priors strongly match `t"..."` because of Python.

###### Proposal S2 (rejected by me): context-named tags `sql"..."`, `sh"..."`
This needs a namespace that maps tag names to context types, so the language needs a registry, user contexts need a declaration form, and we get a second way to name `C`. `C` is already in the parameter type. One generic tag plus bidirectional `C` is less surface and costs nothing at runtime. YAGNI.

###### Proposal S3 (rejected by me): keep the type-directed rule and fix the compiler to full bidirectional checking
It keeps the hidden-cost problem and the local-reasoning problem in the ticket, and it adds more positions (`let`, `if` arms) where one text has two meanings.

###### Composition with sibling tickets
- **jfwr2r (brace escapes):** if the panel later makes interpolation opt-in (`f"..."`), `t"..."` is the natural sibling, as in Python. If interpolation stays universal, `t` still stands alone. S1 does not depend on that result.
- **caqzsw (`Raw[T]`):** no change. The `Raw` hole rules apply inside `t"..."`.
- **h313w9 (surface size):** S1 adds one literal prefix and removes one special coercion rule plus its "literal only at call site" exception. The net surface stays about the same, and the rules get smaller.

Vote intent: S1.

</details>

<details>
<summary><b>Web/Scripting</b></summary>

Web/Scripting Phase A proposal: one `t"..."` prefix for template literals (Python 3.14 PEP 750), C still comes from the expected type.

##### Position: P1, a single `t` prefix. A plain `"..."` is always Str.

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn find(name: Str) -> List[Row] ! DB.Read {
    let q: Template[DB] = t"SELECT * FROM users WHERE name = {name}"
    db.query(q)
}

let msg = "User {id} not found"     // always Str, everywhere
```

Rules:
1. `t"..."` (and `t#"..."#`) is a template literal. Its type is always `Template[C]`. A plain `"..."` is always `Str`, whatever the site expects. You can tell what a literal means from its own text.
2. `C` still comes from the expected type by the normal bidirectional check, as Q9 (6-0) decided. That is ordinary type inference on a phantom parameter, not a change in what the literal means. If nothing fixes `C`, you get E0301, the same as any generic.
3. A template can still come only from a literal. `let q: Str = ...; db.query(q)` stays an error, so the anti-laundering rule does not change.
4. `Raw(x)` is legal only inside a `t"..."` hole. Anywhere else it is E0530, as today.
5. A plain literal at a `Template[C]` site is an error, with a fix-it:
```
error[TemplateMismatch]: expected `Template[DB]`, found `Str`
  help: write a template literal: t"SELECT * FROM users WHERE id = {id}"
```

**Why this is safe and still easy.** The SQL injection guard never rested on the literal. It rests on `db.query` taking `Template[DB]` and never `Str`. Forget the `t` and you get a compile error with a one-character fix. You do not get an injection. So the obvious code is still the safe code; it just takes one character, and the compiler tells you which one.

**Why the familiar choice wins.**
- Python 3.14 shipped exactly this: `t"..."` gives a `Template` with `.strings` and `.interpolations`, next to `f"..."`. We already named the type `Template` "because every Python developer will recognize it" (3-1-1). Matching their literal syntax too costs nothing and gives LLMs the strongest prior we can get.
- JS has `` sql`...` `` tagged templates. Every JS dev knows that a marked literal is "not a normal string". They will read `t"..."` at once.
- Today's rule ("same literal, meaning picked by the callee's signature") is the kind of magic that produces Stack Overflow questions. "Why does my query work inline but break when I move it into a `let`?" That exact case fails in the shipped compiler today. With a prefix, both forms just work. Rule 1 removes the whole class of "where does coercion stop" questions (if-arms, match arms, lets, returns, closures).
- An agent or reviewer can grep `t"` to find every parameterized site. Under the current rule, auditing needs the type checker.

**Fixes the let/if gap for free.** The brief shows `let t: Template[Ctx] = "..."` and `if ... { "p {id}" }` are rejected while the spec says "bidirectional like any expression". With an explicit `t`, the literal has a type of its own, so it flows through lets, ifs and returns with no special coercion rule. We delete the "only literals written directly as call arguments" special case from the spec and the compiler.

##### Rejected: P2, per-context tags (`sql"..."`, `sh"..."`, `html"..."`)

This looks friendly, but it needs a registry that maps prefixes to contexts (user effects too?), and it repeats information the parameter type already carries. When the tag and the type disagree (`sql"..."` passed to a `Template[Shell]` sink), you get a second error class. One prefix with type-directed `C` is smaller. JS needed the tag name because JS has no types; we have types.

##### Rejected: P3, keep untagged and limit coercion to direct call arguments (today's compiler)

This is honest about where it fires, but it still fails the ticket's test: `foo("a {x}")` means concat or binding depending on `foo`'s signature, which you cannot see at the call. It also keeps the confusing "inline works, `let` fails" rule.

##### How it fits with sibling tickets

- jfwr2r (brace escapes): the prefixes become one small family: `"..."`, `#"..."#`, `t"..."`, `t#"..."#`. If jfwr2r later adds an interpolation marker (for example `f"..."`), `t` sits next to it the way it does in Python. Nothing here blocks either answer there.
- h313w9 (surface size): net change is +1 literal prefix and −1 coercion rule, with its special cases. That is about even, and much easier to explain.
- caqzsw: no change.

##### Costs I accept

- This reverses the original "without changing developer syntax" goal. I think that goal was wrong: a hidden change in meaning hurts more than one character costs.
- `t` is one more lexer prefix to reserve. `t` followed by `"` with no space between them is currently invalid, so no existing code breaks. The migration is mechanical: the compiler error names each site in lib/std/db*.bl and tests.

Vote: P1.

</details>

<details>
<summary><b>PLT</b></summary>

PLT Phase A proposal (d9sc2p): a literal's syntax must fix how it is built; the type may fix only the phantom C.

##### Diagnosis
The rule today is not one typing rule. It is two rules with different premises, and the checking mode picks one:

- Str: `Γ ⊢ "s0{e1}…sn" ⇒ Str` if each `ei ⇒ Ti` and `Display(Ti)`. Raw[T] is an error (E0530).
- Template: `Γ ⊢ "s0{e1}…sn" ⇐ Template[C]` if each `Ti ∈ HoleTy`. Display is never called. Raw[T] folds into the parts.

The two results differ in what runs and in which programs typecheck. That is ad-hoc overloading on the expected type. It is not like Haskell's `fromInteger` or `IsString`, where one term elaborates through one class method. It also breaks principality now that we have HM metavariables. Take `fn id[T](x: T) -> T` and the call `sink(id("q {x}"))`. When the literal is checked, its expected type is a metavariable α, and α unifies with `Template[Ctx]` only later. The literal's meaning then depends on the order in which constraints are solved. The same thing happens with list elements, if/match branches and `let` without an annotation. The shipped compiler gets out of this only by coercing nothing but a literal written directly as a call argument. That contradicts §3b.5's "the same bidirectional check as any other expression". The spec promises a rule it cannot keep soundly.

##### Proposal P1 (preferred): one tag, `t"..."`, and C comes from the type
The text fixes how the value is built. The type fixes only the phantom index.

```blink
fn get_user(id: Int) -> Result[Row, DBError] ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn report(table: Str, id: Int) -> Result[Row, DBError] ! DB.Read {
    let q = t"SELECT * FROM {Raw(table)} WHERE id = {id}"   // OK: Template[?C], solved at the call
    db.query_one(q)
}

fn oops(id: Int) -> Result[Row, DBError] ! DB.Read {
    db.query_one("SELECT * FROM users WHERE id = {id}")
    // error[TemplateNeedsTag]: expected Template[DB], found Str
    // help (machine-applicable): t"SELECT * FROM users WHERE id = {id}"
}
```

Typing rules:
- `"…"` ⇒ Str, always, in every mode.
- `t"s0{e1}…sn"` ⇒ `Template[α]` with α fresh, if each `ei ⇒ Ti` and `Ti ∈ HoleTy ∪ Raw[HoleTy∖Bytes]`. If α is still unsolved when the enclosing definition is generalized, that is E0301, and the help names `f[DB](…)` (§3.4 as written).
- `t#"…"#` uses `#{e}` holes. This is the same composition as today.

Why this is sound and principal:
- The literal now synthesizes a type, so its elaboration (decompose, no Display) does not depend on solving order.
- The only thing left to inference is α. α is phantom, and every `Template[C]` has the same layout, so solving it late cannot change behaviour.
- The injection invariant holds without the "literal at the call site" special case: the parts come only from literal text or from `Raw`. Binding a template, returning it, or putting it in a list cannot add text to the parts. So we delete the "literal at the call site" rule and the probe gaps it left (the `let` annotation case and the `if` branch case). Str-to-Template stays an error because Str ≠ Template. No special rule is needed.

Is it still safe? The "obvious" untagged code does not compile, and the fix is one character that the compiler inserts. A compile error is the safe failure. Silent concatenation is the unsafe one, and P1 has no path to it. So the original goal "obvious code is safe code" still holds; the only cost is the "no new syntax" half of it.

Precedent: Python 3.14 (PEP 750) uses exactly `t"..."` → `Template`, with `f"..."` → str. That is a strong LLM prior. JS tagged templates are also syntactically explicit. C# `FormattableString` is the type-directed design, and it is the cautionary case: overload resolution prefers `string`, so EF Core had to split its API into `FromSqlInterpolated` and `FromSqlRaw`.

Why not per-context tags (`sql"…"`): that needs a tag→C registry, which is a new open namespace with user extension and its own resolution rules (Scala's `StringContext`). One tag plus phantom inference costs less and keeps decisions/template-surface Q9 ("C from the expected type") intact for C.

It composes with the sibling tickets:
- jfwr2r: if Str interpolation later needs a marker (`f"…"`), `t` is its sibling in one prefix family. If it does not, `t` is the only prefix.
- caqzsw: the Raw[T] rules stay hole-local.
- h313w9: P1 removes a context-sensitive rule and a special case, so the surface gets smaller even though it gains a prefix.

Migration: lib/std/db.bl, lib/std/db_sqlite.bl and tests. Nothing in examples/.

##### Proposal P2 (fallback, I vote against): keep untagged, make it honest
Coerce only when the expected type's head is already a rigid `Template[_]` at check time. A metavariable defaults to Str. This has to be written down as a rule that depends on the order of checking. That makes it non-principal by construction, and it explains rather than fixes the bug in the ticket. If the panel keeps untagged literals, the spec must at least state this restriction rather than claim "the same bidirectional check".

Vote intent: P1.

</details>

<details>
<summary><b>DevOps</b></summary>

DevOps/Tooling Phase A proposal (full text): make the template visible in the text with a `t"..."` prefix.

**Position:** Keep `Template[C]`, the phantom `C`, `Raw[T]` and the hole rules. Change one thing: a literal that decomposes into a template must say so in its own text. The marker is the prefix `t`. The literal's kind (template or string) is then visible in the text. Only the context `C` still comes from the expected type, the same way an `Int` literal's width does.

###### Proposal 1 (primary): `t"..."` template literals

```blink
fn get_user(id: Int) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn find(name: Str, by_email: Bool) -> Result[List[Row], DBError] ! DB.Read {
    let col = if by_email { "email" } else { "name" }
    let q: Template[DB] = t"SELECT * FROM users WHERE {Raw(col)} = {name}"
    db.query(q)
}

let json = t#"{"user": #{name}}"#    // the prefix composes with #"..."#
```

Rules:
1. `t"..."` and `t#"..."#` are expressions of type `Template[?C]`. `C` comes from ordinary bidirectional checking, so `let`, `if` arms and returns all work. That also closes today's gap between the compiler and the spec, where only a literal written directly as a call argument coerces. If `C` stays unbound, the error is E0301 with `help: write log_query[DB](t"...")`.
2. A plain `"..."` is always `Str`. It never coerces to `Template[C]`, with or without holes. That gives one way to write a template.
3. `Raw(x)` is legal only in a hole of a `t"..."` literal. The parser can now report E0530 with no type information.
4. Laundering stays blocked, because `Str` still does not convert to `Template`. Templates also become ordinary values that you can bind and pass. They still have only one constructor: the `t` literal.

**Diagnostics (the core of my case).** Today, if an API changes from `Template[DB]` to `Str`, or someone writes a `fn run(sql: Str)` wrapper, `run("... {id}")` compiles with NO diagnostic. That is silent SQL injection. Type-directed meaning cannot produce a warning, because both readings type-check. With the prefix, both directions are hard errors, and each has a fix the tool can apply itself:

```
error[TemplateMismatch]: expected `Template[DB]`, found `Str`
 --> user.bl:3:18
  |
3 |     db.query_one("SELECT * FROM users WHERE id = {id}")
  |                  ^ a plain string literal is always `Str`
  |
  = help: add the template prefix: t"SELECT * FROM users WHERE id = {id}"
```

```
error[TypeError]: expected `Str`, found `Template[?]`
 --> user.bl:7:16
  |
7 |     io.println(t"hello {name}")
  |                ^ `t"..."` builds a Template, not a Str
  |
  = help: remove the `t` prefix: "hello {name}"
```

`blink fix` applies both. Migration is cheap: about 5 effect ops in lib/std/db.bl, the sqlite tests, and nothing in examples/. Ship a warning with the fix first, then make it an error (the 3-step bootstrap).

**Editors and the LSP.** The editors that matter most have no type checker: GitHub rendering, tree-sitter and TextMate grammars, and an agent reading a diff. With `t"`, a grammar can colour template holes as parameters and `Raw(...)` as a hazard, with no type information. `rg 't"'` finds every template in a codebase. Security review can grep for the risk, which it cannot do today. On hover, `t` shows the resolved `Template[DB]`. `blink fmt` only needs to keep the prefix.

**Lexer.** `t"` is a prefix only when no space separates the two characters. For `t "..."` (with a space), report `help: did you mean t"..."?`. No current construct puts an identifier directly before a string literal. Test names use `test "name"`, with a space.

###### Proposal 2 (rejected by me): context tags such as `sql"..."`, `sh"..."`

This is more readable at first look, but it is worse for tooling:
- It needs a registry that maps a tag to `C`, plus declaration syntax for user contexts, an unknown-tag error, tag imports and LSP completion for tags. That adds surface, which works against h313w9.
- It duplicates information the callee's type already holds, so you get a new class of error: `sql"..."` passed to `Template[Shell]`. That needs a two-part diagnostic, where today one invariant-type error does the job.
- The question the ticket asks is "concat or parameters?". `t` answers it. The context (`db.query`) is already visible at the call site.

###### Proposal 3 (fallback only): keep the current design and rely on tooling

Inlay hints and semantic tokens could mark holes in a template context. I reject this as the fix: it helps only LSP users, never the agent or reviewer who reads plain text, and it does nothing about the silent flip to `Str`. Template-only colouring is still worth adding on top of Proposal 1.

###### Cross-language notes
Python 3.14 PEP 750 chose exactly this: `t"..."` gives a `Template` and `f"..."` gives a `str`. It is a lexical prefix, and the library decides the use. JS tagged templates (`` sql`...` ``) are Proposal 2: a tag per context, at the cost of function-valued tags. C# `FormattableString` is today's Blink design, and the C# team's own guidance says the silent overload choice between `string` and `FormattableString` is a known trap. EF Core added `FromSqlInterpolated` and `FromSqlRaw` as separate names to undo it.

###### How this fits the sibling tickets
If jfwr2r adopts an interpolation marker for plain strings (for example `f"..."`), `t"..."` joins the same family of prefixes, and an unmarked `"..."` holds no holes. If jfwr2r keeps universal interpolation, `t` still works without change. Proposal 1 does not depend on how jfwr2r is decided.

**Vote intent:** Proposal 1.

</details>

<details>
<summary><b>AI/ML</b></summary>

AI/ML Phase A proposal (full text): add a template prefix `t"..."`, so a literal never changes meaning by type.

**My lens.** Can a model know what a line does from the line alone? Today it cannot. `db.query_one("... {id}")` and `log("... {id}")` look the same, but one binds parameters and the other concatenates. A model learns the difference only from a signature it may never have seen. The risk is not injection, because a `Str` never becomes a `Template`, so the design fails safe. The risk is **silent wrong behavior** that follows directly from model priors:

```blink
db.query_one("SELECT * FROM users WHERE name = '{name}'")
```

Every f-string SQL example in training data puts quotes around the hole. In a `Template[DB]` context this becomes `WHERE name = '?'`, which compares against the literal text `?`. It compiles, it runs, and it returns no rows. The model wrote it because nothing on the line told it the holes were parameters.

###### Proposal A (preferred): a generic template prefix `t"..."`

A plain `"..."` is always `Str`. Only `t"..."` builds a `Template[C]`, and it takes `C` from the expected type by the ordinary bidirectional check. The prefix is not a dialect tag.

```blink
fn get_user(id: Int) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn report(table: Str, id: Int) -> Result[Option[Row], DBError] ! DB.Read {
    let q: Template[DB] = t"SELECT * FROM {Raw(table)} WHERE id = {id}"
    db.query_one(q)
}

fn pick(id: Int, active: Bool) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one(if active { t"SELECT * FROM live WHERE id = {id}" } else { t"SELECT * FROM old WHERE id = {id}" })
}
```

Rules:
- `db.query_one("... {id}")` is a type error: expected `Template[DB]`, found `Str`. Its `help:` is machine-applicable: "prefix the literal: `t\"...\"`". Safety stays the same as today, because the unprefixed form still never reaches the database.
- `t"..."` where `Str` is expected is a type error. Its `help:` says to drop the `t`.
- `let x = t"..."` with no expected type gives E0301 (under-determined `C`). That reuses an existing rule.
- `Raw(...)` outside a `t"..."` stays E0530. Inside one it stays `RawBypassesParam`.

**Why `t` and not `sql"..."`.** A `sql` tag puts dialect names into the lexer. It breaks the 6-0 rule "C comes from the expected type" and the rule "the compiler never encodes dialect knowledge". It also needs a new tag for each new context (`html`, `sh`). With `t` there is one prefix, the name matches the type `Template`, and it is the exact spelling of Python 3.14 t-strings (PEP 750). Those are now in training data and carry the same meaning: parts plus values, and the library reassembles.

**What it removes.** Today's special rule "the coercion works only on a literal written directly as a call argument" goes away. The compiler implements that rule, but the spec text contradicts it (see the brief's probe: the `let t: Template[Ctx]` and `if` forms are rejected). With a prefix, a template literal is an ordinary expression. Bindings, `if`, `match` and returns all work, and the special case does not need to be learned.

**Tradeoffs.**
- Token cost: one character per template literal. Template literals appear in a few places: the five DB ops, plus handlers.
- Decision points: one (`t` or not). The compiler enforces it with a fix-it at each wrong site, so a model that forgets the `t` loses one compile round trip and never ships a bug. That is the best kind of decision point: a wrong answer is loud.
- "Obvious code is the safe code" survives. The obvious code is still safe, because it fails to compile. The original decision's phrase "without changing developer syntax" does not survive. I accept that cost, and I think it was the wrong goal: being readable from the line alone is worth more than leaving the syntax untouched.
- Composes with jfwr2r. If interpolation ever gets an explicit marker, `t"..."` is the same kind of literal prefix, not a second mechanism. A raw form `t#"..."#` is not needed: a template with no holes is `t"..."` with `\{`.

**Cross-language.** Explicit marker: Python `t"..."`, JS tagged templates (sql`...`), Scala `sql"..."`. Type-directed: C# `$"..."` to `FormattableString`, and Swift `ExpressibleByStringInterpolation`. C# is the warning case. EF Core had to ship both `FromSqlRaw` and `FromSqlInterpolated` because users and tools could not tell which one a `$"..."` reached, and the `Raw` overload silently took interpolated strings.

###### Proposal B (fallback, if the panel keeps an untagged literal)

1. Write down the shipped rule exactly: the coercion applies only to a string literal written directly as an argument whose parameter type is `Template[C]`. Delete "by the same bidirectional check as any other expression", which promises `let` and `if` forms that the compiler rejects.
2. Add a warning `QuotedTemplateHole` for `'{x}'` or `"{x}"` quoting around a hole in a template literal. Its help: "a hole is a parameter; remove the quotes".
3. Add a `blink fmt`/LSP inlay that marks template literals.

B fixes the spec-versus-compiler mismatch, but it keeps the line-level ambiguity, and it relies on tooling that a model writing code from the spec does not see.

**Vote intent:** A. Under either option I want the quoted-hole lint, because it catches the most likely wrong output from a model in any `Template` context.

</details>

<details>
<summary><b>Minimalism</b></summary>

Minimalism Phase A proposal (complete text): replace the type-directed coercion with one prefix, t"...". Reject per-context tags.

###### Proposal M1 (preferred): `t"..."` is the only literal that builds a `Template[C]`

```blink
fn get_user(id: Int) -> Result[Option[Row], DBError] ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}

fn find(name: Str, by_email: Bool) -> Result[List[Row], DBError] ! DB.Read {
    let q: Template[DB] = if by_email {
        t"SELECT * FROM users WHERE email = {name}"
    } else {
        t"SELECT * FROM users WHERE name = {name}"
    }
    db.query(q)
}

db.query_one("SELECT * FROM users WHERE id = {id}")
// error[TemplateMismatch]: expected `Template[DB]`, found `Str`
//   help: write a template literal: t"SELECT * FROM users WHERE id = {id}"
```

Rules:
1. A `"..."` literal always has type `Str`. Nothing depends on the context.
2. A `t"..."` literal has type `Template[C]`, and `C` comes from the ordinary bidirectional check. This is the same as `None` or `[]`. If `C` is still unbound, the existing E0301 rule applies (`log_query[DB](t"...")`).
3. `t#"..."#` combines with the extended delimiter. No other string form needs a template variant.
4. `Raw(expr)` is legal only in a hole of a `t"..."`. E0530 becomes a check on the text alone.
5. Delete the "Context-sensitive interpolation" paragraph in §2.4, and delete the literal-coercion rule in §3b.5. The opaque type, `parts()`/`values()`, `TemplateValue`, E0534 and the `Raw[T]` rules all stay as they are.

**Why this is a subtraction, not an addition.** The spec today has a special coercion rule plus an exception ("auto-decomposition only works on string *literals* at the call site"). The compiler does not even match it: the probe rejects `let t: Template[Ctx] = "..."` and the `if` form, both of which the spec allows. M1 deletes the coercion and the exception. It replaces them with one lexer token, and every other part is ordinary typing. The `if`/`let` cases work with no extra rule, and the compiler/spec gap closes because we remove the rule, not because we add another implementation of it.

**Safety stays the same.** The safety never came from the coercion. It came from the parameter type `Template[DB]` and the rule that `Str` cannot become a `Template`. If you forget the `t`, you get a compile error with a fix-it, not an injection. The 3-0 goal "the obvious code is the safe code" still holds. We only lose "without changing developer syntax", and the cost of that is one character.

**The meaning really does differ, so the text must show it.** A hole in a template does not call `Display`, accepts only a small set of types (E0534), and permits `Raw`. A hole in a `Str` is the opposite on all three. Two literals with the same spelling but those different rules defeat local reasoning, for humans and for agents.

**Cross-language.** Python 3.14 (PEP 750) chose the same design: `t"..."` gives a `Template`, plain strings never do, and the reason was explicitness. That gives LLMs a strong prior that matches ours. C# `FormattableString` used target typing like our current spec, and it is a well-known trap: `var` silently gives you a `string`.

###### Reject: per-context tags (`sql"..."`, `sh"..."`, `html"..."`)

That is an open set of prefixes, like JS tagged templates. Each prefix needs a registry, the prefixes collide with identifier lexing, and the tag duplicates what `C` already says. `t` says "this is a template". The parameter type says which kind, as with every other generic. One mechanism, not N.

###### Fallback M2: do nothing to the syntax, and narrow the spec to what ships

If the panel keeps the bare-literal form, then at minimum restrict the spec to "a literal written directly as a call argument". Drop the "same bidirectional check as any other expression" claim. That is honest, but it leaves a special case that agents still cannot see in the text. I rank it well below M1.

###### Interactions

- **jfwr2r (brace escapes):** M1 does not change how `"..."` interpolates. If that panel later makes interpolation opt-in with a prefix, `t` fits that family as one more prefix. No new design is needed here.
- **h313w9 (surface size):** M1 is net-neutral or net-negative. It adds one token and removes one coercion rule and one exception.
- **caqzsw:** not affected.

**Vote intent:** M1 > M2 > tags.

</details>

#### Phase A.5 — Deduped option space

<details>
<summary>Moderator's mechanical grouping of Phase A (Phase B round 1 broadcast)</summary>

#### Phase B, round 1 — deduped option space (mechanical grouping of Phase A)

All six Phase A proposals are saved verbatim in this directory: A_sys.md, A_web.md, A_plt.md, A_devops.md, A_aiml.md, A_min.md. Read all of them.

##### Options (from panelist proposals only)

- **Option T — one generic prefix `t"..."`.** A plain `"..."` is always `Str`. Only a `t`-prefixed literal builds a `Template[C]`; `C` comes from the expected type by the ordinary bidirectional check. The literal-coercion rule and the "literal directly at the call site" exception are deleted. Preferred by: sys (S1), web (P1), plt (P1), devops (Proposal 1), aiml (Proposal A), min (M1).
- **Option U — keep the untagged literal; narrow the spec to the shipped rule** (coerce only a literal written directly as an argument whose parameter type is `Template[C]` / whose expected head is a rigid `Template[_]`; drop "same bidirectional check as any other expression"). Listed as a fallback by: plt (P2), min (M2), aiml (Proposal B, plus a `QuotedTemplateHole` lint and an LSP/fmt marker), devops (Proposal 3, tooling-only). Rejected by sys (S3), web (P3).
- **Option K — per-context tags (`sql"..."`, `sh"..."`, `html"..."`).** Proposed by no one; rejected by all six.

##### Variations inside Option T that differ between proposals (for debate)

- **V1 — extended-delimiter form.** sys, web, plt, devops, min include `t#"..."#`. aiml: "A raw form `t#"..."#` is not needed: a template with no holes is `t"..."` with `\{`." (devops's example writes `t#"{"user": #{name}}"#`.)
- **V2 — `let q = t"..."` with no annotation.** plt: `Template[α]`, α fresh, "solved at the call"; E0301 only if α is still unsolved when the enclosing definition is generalized. aiml: "`let x = t"..."` with no expected type gives E0301 (under-determined `C`)." sys / web / min / devops: E0301 when `C` stays unbound (not stated at which point).
- **V3 — where `Raw` is checked.** sys: "`Raw(expr)` is legal only inside a `t"..."` hole. That makes E0530 a simple syntactic check." devops: "The parser can now report E0530 with no type information." min: "E0530 becomes a check on the text alone." plt: hole types `Ti ∈ HoleTy ∪ Raw[HoleTy∖Bytes]` (a typing rule).
- **V4 — quoted-hole lint.** aiml: add warning `QuotedTemplateHole` for `'{x}'` / `"{x}"` around a hole in a template literal ("Under either option I want the quoted-hole lint"). Not mentioned by others.
- **V5 — diagnostic for an untagged literal at a `Template[C]` site.** web / min / devops: `error[TemplateMismatch]` with a machine-applicable `help:` adding `t`. plt: `error[TemplateNeedsTag]`. aiml: "a type error ... `help:` is machine-applicable".
- **V6 — rollout.** devops: "Ship a warning with the fix first, then make it an error (the 3-step bootstrap)." Not mentioned by others.

##### Facts from the codebase (no position implied)

1. DECISIONS.md "Rejected features" table: `| **Multiple string delimiters** | One string syntax. No 'single' vs "double" vs `backtick`. |` and `| **Implicit conversions** | Action-at-a-distance. The AI (and the human) should see exactly what types flow where. |`
2. §2.4.1 (#embed) closing note: "No new string syntax — the locked "one string syntax" decision is preserved." The `#"..."#` extended-delimiter form (§2.4.2) exists alongside `"..."`; inside it, interpolation is `#{expr}` (depth 1), `##{expr}` (depth 2), up to depth 3; `{expr}` is literal text; W1111 warns on `{identifier}` without `#`.
3. §3b.5 (decided 6-0): "The marker survives a binding. `let t = Raw(table)` has type `Raw[Str]`, and interpolating `t` into a template is the same bypass as writing `Raw(table)` inline — with the same audit obligation."
4. The current compiler's probe: `sink(#"raw {id}"#)` is accepted today at a `Template[Ctx]` parameter (the `{id}` there is literal text, not a hole).

##### What to send back

Reply via SendMessage to team-lead with: your response to the other proposals, your position on each of V1–V6 (and on Option T vs U), any change of position, and whether you are **"stable, ready to vote"**. Keep it under ~500 words.

</details>

#### Phase B — Debate

One round. All six panelists said "stable, ready to vote" after round 1. Each panelist states any change of position in their own text below.

<details>
<summary><b>Systems</b>, round 1</summary>

##### Systems, Phase B round 1

**Option T or U:** T, with no change. All six of us prefer T. Fact 1 makes the case stronger. The DECISIONS.md row that rejects **Implicit conversions** condemns the current rule: the literal turns into a `Template` because of what the site expects. Option U writes that conversion down instead of removing it. The **Multiple string delimiters** row does not block T, because `t` is a prefix and not a new delimiter. The quote character, the escapes and the interpolation syntax all stay the same. I agree with PLT's diagnosis, that U is not principal once the expected type can be a metavariable, so the literal's meaning would depend on the order constraints are solved. I also agree with the C# precedent that PLT and AI/ML cite: EF Core had to add `FromSqlInterpolated`/`FromSqlRaw`.

**V1 (`t#"..."#`): include it.** The rule should be that `t` is a prefix that works with every string-literal form, and it should not define a form of its own. Whatever jfwr2r decides for `Str` (keep `#"..."#`, drop it, or add a marker), `t` applies to the result unchanged. Without the raw form, SQL that holds JSON or regex text needs a `\{` for each brace, which is the jfwr2r problem again. AI/ML's view that the raw form is "not needed" is true only for templates with few braces. The cost to the compiler is close to zero: one prefix check before the delimiter scan we already have.

**V2 (`let q = t"..."` with no annotation): PLT's rule.** `Template[α]`, with α fresh and solved by the time the enclosing definition is generalized, and E0301 only if α is still unsolved then. This costs nothing at codegen, because `C` is phantom: every `Template[C]` has the same layout and lowering, so solving α late cannot change the code we emit. AI/ML's "E0301 at the `let`" would bring back the special rule we are deleting, because a template could then not be bound without an annotation while every other generic value can.

**V3 (where `Raw` is checked): I withdraw my claim.** Fact 3 proves me wrong: `let r = Raw(table)` has type `Raw[Str]`, and the marker survives the binding. So E0530 cannot be a check on the text alone. Devops and Minimalism make the same mistake. Use PLT's typing rule: hole type `Ti ∈ HoleTy ∪ Raw[HoleTy∖Bytes]`, and E0530 for a `Raw[T]` in any other position. It is still a typecheck error at the use site, so the cost stays the same.

**V4 (`QuotedTemplateHole` lint): against it as a language diagnostic; for it as a handler or library check later.** The lint encodes dialect knowledge. `'{x}'` is a mistake in SQL, but in HTML `<a href="{url}">` is correct, because an HTML handler escapes for the attribute. The 6-0 decision says that "the compiler never encodes dialect knowledge". Put the check in the handler: the DB handler can reject a part that ends in `'` before a value, at runtime, for a few cycles per query, or in a lint that the library declares. File it as its own ticket and keep it out of this one.

**V5 (diagnostic): reuse `TemplateMismatch`.** It already exists and fires today. Add a `help:` that a machine can apply ("prefix with `t`") for the untagged case, and one that drops the `t` for the opposite case. A new code such as `TemplateNeedsTag` adds a name to learn and gives no extra precision, because the message already says what went wrong.

**V6 (rollout): the 3-step bootstrap, with no warning period in the spec.** Step 1: add `t"..."` next to the old rule. Step 2: move lib/std/db*.bl and the tests to `t"..."`. Step 3: delete the coercion. That is an implementation detail and belongs in the chore. No user code in examples/ uses the old rule, and we are before 1.0, so a deprecation warning period in the spec is surface that nobody would use.

**Change of position:** V3 only. I withdraw my claim that E0530 is a check on the text alone.

**Stable, ready to vote.**

</details>

<details>
<summary><b>Web/Scripting</b>, round 1</summary>

Web/Scripting Phase B round 1: Option T, with one correction to my own Phase A text on V3. Stable, ready to vote.

**T vs U: T.** All six of us reached T on our own, and that matters. U writes down a rule that depends on order: "inline works, `let` breaks". That is the Stack Overflow question I named in Phase A. aiml's quoted-hole example (`'{name}'` becomes `'?'`, which returns zero rows) is the best argument on the table: under U, the same line silently does two different things.

**Fact 1 ("one string syntax", "implicit conversions" rejected).** Both facts favor T. `t` is not a new delimiter: it uses the same quotes, the same escapes and the same holes, and it is a prefix like `#`. The "implicit conversions" rejection is an argument *against* today's rule, because the type-directed coercion of `Str` to `Template` is an implicit conversion.

**V1 (`t#"..."#`): keep it.** aiml says no holes means plain `t"..."`, but that misses the use case. `#` is for brace-heavy text *with* holes, for example a Postgres jsonb filter: `t#"data @> '{"id": #{id}}'"#`. "Prefix and delimiter compose" is one rule, and banning one combination is an exception to learn. Fact 4 also shows that `#"..."#` works at a Template site today, so dropping it would remove a current capability.

**V2 (`let q = t"..."` with no annotation): plt's rule.** The type is `Template[α]`, solved where the value is used, with E0301 only if α is still unsolved when the definition is generalized. `let q = t"..."` followed by `db.query(q)` is the most common refactor any Python or JS dev will make. If that gives E0301, we have rebuilt the "inline works, let breaks" trap under a new name. We already have HM metavariables, so this costs nothing.

**V3 (Raw check): I correct my Phase A wording and side with plt.** Fact 3 rules out a check on the text alone. `let r = Raw(table)` is legal (decided 6-0), and `t"... {r}"` is the bypass. E0530 must stay a type rule: a `Raw[T]` value used anywhere other than as a hole in a template literal. sys, devops and min ("parser can report it", "check on the text alone") are wrong on this point. My "legal only inside a `t` hole" should read "*consumed* only by a `t` hole".

**V4 (QuotedTemplateHole lint): support it, as a separate item.** It catches the main mistake that comes from Python and JS habits. It needs to apply only to `t"..."` literals, so it gives no false positives in plain strings. I would vote for it with T, but it should not block T.

**V5 (diagnostic): reuse `TemplateMismatch`, with a machine-applicable `help:` in both directions** (devops's pair: add `t`, or remove `t`). A new code `TemplateNeedsTag` adds a name for something the existing code already says. That is a weak preference; the fix-it is what matters.

**V6 (rollout): an implementation detail, not a spec item.** The spec says it is an error. The 3-step bootstrap is how the compiler gets there, and it belongs in the implementation ticket. There are no external users and nothing in examples/, so a deprecation-warning period in the spec is not needed.

No change of position. Stable, ready to vote.

</details>

<details>
<summary><b>PLT</b>, round 1</summary>

PLT, Phase B round 1: Option T. I am stable and ready to vote. On V3 I object: E0530 must stay a typing rule. A purely textual check contradicts the 6-0 decision on Raw[T].

**Other proposals.** All six of us reached T on separate grounds: hidden cost (sys), priors (web, aiml), grep and the silent flip to Str (devops), subtraction (min), and principal typing (mine). That agreement is strong evidence. I keep my point that U is not principal: it has to fix the order in which types are checked, so it records the defect rather than fixing it. U is out for me. K is out, as everyone agrees.

**V1, `t#"..."#`: include it.** A prefix should compose with each delimiter. Dropping one pair leaves a gap, and gaps are what agents trip on. The need is real: a Postgres jsonb literal inside a query (sys's example) would otherwise need a `\{` for each brace. The interpolation-depth rules for `#{e}` carry over unchanged.

**V2, `let q = t"..."` with no annotation: use the same rule as `[]` and `None`.**
- The literal has type `Template[α]` with α fresh.
- Any later use in the same function body may solve α. α is phantom, so a late solution cannot change behaviour.
- E0301 fires only if α is still unsolved when inference of that function body ends.
- aiml's "E0301 at once" would make the template literal the one expression whose metavariable must be solved at the point where it is bound. That is a special case, and removing special cases is the reason for T.
- The spec text should say "as for `[]` (§3.4)", not invent a new rule.

**V3, where Raw is checked: this must be a typing rule, not a check on the text.** sys, devops and min say E0530 becomes syntactic. That contradicts fact 3 (6-0): `let r = Raw(table)` is a legal binding, and `{r}` in a template is the bypass. So `Raw[T]` values exist outside holes, and the parser cannot see that `{r}` is Raw. The rules stay type-based:
- A hole of type `Raw[T]` in a plain `"..."` is E0530.
- A hole of type `Raw[T]` in `t"..."` folds and raises `RawBypassesParam`.
- A `Raw[T]` anywhere `Display` would be needed is E0530.

T does make one thing easier: the check needs only the literal's own prefix and the hole's synthesized type, never the expected type. That is enough. Please do not write "syntactic" into the spec.

**V4, `QuotedTemplateHole`: reject it as a language lint.** Whether a quote around a hole is wrong depends on the dialect. In SQL, `'{x}'` is a bug. In HTML, `<a href="{url}">` is correct, because the handler escapes the value and the quotes belong to the attribute. A compiler lint keyed on `'`/`"` therefore encodes dialect knowledge, which §3b.5 forbids ("the compiler never encodes dialect knowledge"), and it gives false positives in HTML. The right home is the handler library: a lint the context declares, or a runtime check in the SQL handler. That belongs on its own ticket, not this one.

**V5, diagnostic name: reuse `TemplateMismatch`.** It exists already (the brief's probe shows it), so I withdraw `TemplateNeedsTag`. Keep the machine-applicable `help:` that adds `t`. Add the reverse case: `t"…"` where `Str` is expected is a type error, with `help:` to remove the `t`. Template has no Display and no conversion to Str.

**V6, rollout: fine as implementation, but not in the spec.** The spec states only the final rule. A warning-first phase is how the bootstrap dance migrates lib/std. It is not a property of the language. Hardly anything uses templates (db*.bl and tests), so a single 3-step bootstrap is enough.

**Changes from my Phase A text:**
1. I drop the `TemplateNeedsTag` name.
2. I spell the typing judgment for `Raw` in holes as above.
3. I add the reverse-direction error.

**Small additions to T:**
- One spec sentence on the safety invariant: "Every part of a `Template[C]` is literal source text, or text folded in from a `Raw[T]`." Binding, returning and storing templates then need no further rule.
- The sentence "The auto-decomposition only works on string literals at the call site" must be deleted from §3b.5, not reworded.

</details>

<details>
<summary><b>DevOps</b>, round 1</summary>

DevOps Phase B round 1: Option T; one retraction (V3); V4 accepted only if scoped to DB; stable, ready to vote.

**Option T vs U.** T. Option U pins down the shipped rule but leaves the bug I care about most: if a sink's type changes from `Template[DB]` to `Str`, every untagged call site still compiles with no diagnostic. Inlay hints do not reach a reviewer, an agent or a diff. All six of us chose T, so I see nothing left to debate there.

**V1 (`t#"..."#`): keep it.** The prefix is one rule: "`t` may precede any string literal form." If we forbid `t#`, that adds a rule and a diagnostic ("t# is not allowed; use \{"), and SQL with JSON in it (`'{"k":1}'`) becomes a wall of `\{`. Banning the combination costs more than allowing it.

**V2 (unannotated `let q = t"..."`): I side with plt.** `Template[α]` is solved at use. This is how HM metavars already work in the compiler, and it is the principal answer. Diagnostic requirements:
- If α is never solved, report E0301 at the literal, with the help `let q: Template[DB] = ...`.
- If two uses conflict (`db.query(q)` then `shell(q)`), report the error at the second use, as `expected Template[Shell], found Template[DB]`, with `note: C was fixed to DB here` pointing at the first use.
- Hover on `q` shows the solved `Template[DB]`.

**V3 (Raw checking): I retract my claim.** I said "the parser can report E0530 with no type information". Fact 3 makes that false: `let r = Raw(table)` has type `Raw[Str]`, so `io.println("{r}")` needs types to catch. The normative rule stays a typing rule (plt's `Ti ∈ HoleTy ∪ Raw[HoleTy∖Bytes]`). A literal `Raw(` written inside a plain `"..."` hole can still get the fast lexical diagnostic, but that is a tool convenience, not the spec rule. sys and min should drop "syntactic" for the same reason.

**V4 (QuotedTemplateHole): yes, but only for `Template[DB]`, not for every `C`.** Counterexample: in HTML, `t"<a href=\"{url}\">"` puts quotes around the hole and it is CORRECT, because the attribute quotes are markup and the handler escapes the value. A lint for every `C` would fire falsely, and it would put dialect knowledge into the compiler, which §3b.5 forbids. My suggestion: either the std DB module owns the lint (it fires when `C` = `std.db.DB`, and skips `Raw` holes), or we file it as a follow-up ticket so this vote is not blocked. I prefer the follow-up ticket. It is a lint, not part of the spec decision.

**V5 (diagnostic): reuse `TemplateMismatch` (E0310), not a new `TemplateNeedsTag`.** E0310 already means "Str where Template is expected". A new code for the same type pair splits `blink explain` and search results. Required: the `help:` that adds `t` is machine-applicable (`blink fix` applies it), and the opposite direction (`t"..."` where `Str` is expected) gets the help "remove the `t` prefix". plt's name reads well, but one code per type pair matters more.

**V6 (rollout): I withdraw it from the decision.** The call sites are lib/std/db*.bl plus tests, and nothing in examples/. A warning phase would be a bootstrap detail (the 3-step regen), not language text. The spec should just state the end rule: an untagged literal at a `Template[C]` site is an error.

**Other proposals.** aiml's quoted-hole case (`'{name}'` becomes `'?'`) is the strongest argument for T: the tag tells the author the hole is a parameter. sys's codegen point (static parts array, no `Display` dispatch) belongs in the spec rationale. min's framing (remove the coercion and its exception, add one token) is the one to record in DECISIONS.md.

**Change of position:** only V3 (retracted) and V6 (withdrawn).

**Stable, ready to vote.**

</details>

<details>
<summary><b>AI/ML</b>, round 1</summary>

AI/ML Phase B round 1: Option T. I correct myself on V1 and withdraw V4 as a language lint. Stable, ready to vote.

**On the other proposals.** All six of us reached T on our own, which is a signal in itself. Three arguments from the others go further than my proposal did, and I adopt them:
- plt shows that the type-directed rule is not principal with HM metavariables. In `sink(id("q {x}"))`, the meaning depends on the order in which constraints are solved. That means the spec text cannot be implemented as written, not only that a model reads it badly.
- devops shows the reverse flip: change a parameter from `Template[DB]` to `Str`, and every call site silently goes back to concatenation, with no diagnostic. Under T this is a hard error.
- web and devops point out that `rg 't"'` finds every parameterized site. A model working on a codebase can audit it with text search alone.

**T vs U: T.** U leaves the decision point in the callee's signature, where the model cannot see it.

**V1 (`t#"..."#`): accept. My Phase A claim was wrong.** `#"..."#` has holes (`#{e}`), so `t#"..."#` is a real template with literal braces. That is exactly what SQL holding JSON needs (`t#"... '{"k": 1}' ... #{id}"#`). One consequence: today the probe accepts `sink(#"raw {id}"#)` because it has no holes. Under T that becomes an error, which is correct.

**V2 (unannotated `let q = t"..."`): adopt plt's rule.** The type is `Template[α]` with α fresh, solved at use. E0301 fires only if α is still unsolved when the definition is generalized. My "E0301 at once" was too eager. It would force an annotation on the natural "bind, then pass" pattern, which costs tokens for no safety gain, because α is phantom. Models already know this pattern from `let xs = []`.

**V3 (where `Raw` is checked): keep plt's typing rule. Reject the syntactic "Raw only inside a `t` hole".** Codebase fact 3 is a 6-0 decision: `let t = Raw(table)` gives a `Raw[Str]`, and interpolating `{t}` is the same bypass. A syntactic rule either forbids that binding, which silently amends a 6-0 vote, or misses it. E0530 stays type-based: a `Raw[T]` value reaching a plain `"..."` hole, or any non-template position, is the error. Constructing a `Raw` anywhere stays legal. If sys, devops and min meant only "the diagnostic is easy to produce at an inline `Raw(...)`", I agree, but the rule must stay the type.

**V4 (`QuotedTemplateHole` lint): withdraw it as a language lint.** Quotes around a hole are a bug in SQL, but correct in HTML: `<a href='{url}'>` with a handler that escapes attribute values. A compiler lint would encode dialect knowledge, which breaks the decided rule that the compiler holds no dialect knowledge. The `t` prefix also removes most of the prior that caused the bug, because the reader now sees that holes are parameters. I propose that the stdlib DB handlers reject a part ending in `'` followed by a part starting with `'`, at runtime or in debug. That is non-normative library work, not spec.

**V5 (diagnostic): reuse the existing `TemplateMismatch` code.** Don't add `TemplateNeedsTag`: every new code is one more thing a model has to learn. Both directions get a machine-applicable `help:` ("add `t`" and "remove `t`"), as devops wrote them.

**V6 (rollout): no user-facing warning period.** Use the normal 3-step bootstrap: add `t"..."`, migrate lib/std/db*.bl and the tests, then remove the coercion. A deprecation window would put both spellings into code that becomes training data, for nothing: the code that uses this is about 5 ops in-tree and none in examples/.

**Change of position:** V1 and V2 corrected, V4 withdrawn as above. The vote stays T.

**Stable, ready to vote.**

</details>

<details>
<summary><b>Minimalism</b>, round 1</summary>

Min, Phase B round 1: Option T (stable, ready to vote). I retract one claim on V3.

**T vs U.** I vote T. Fact 1 supports T. DECISIONS.md already rejects "Implicit conversions" as action at a distance, and the current coercion is exactly that: a `Str`-looking literal that turns into another type because of where it sits. T makes the spec obey a decision we already locked. The "one string syntax" row does not block T. That row rejects alternative quote characters. A one-letter prefix on the same `"..."` form is no more of a new syntax than `#"..."#` already is. Under U the special rule stays, and it needs a lint and an LSP marker (aiml B, devops 3) to make the hidden meaning visible. That much tooling to explain a rule tells us we should delete the rule.

**V1, `t#"..."#`: include it, with no extra rule.** The prefix applies to every string-literal form. A ban on that one combination would be the extra rule, an exception we would have to write, test and explain. JSON-in-SQL (`jsonb` literals) is a real case, and devops's example shows it. Fact 4 adds a note: today `sink(#"raw {id}"#)` is accepted. Under T that line is a `Str` at a `Template` site, so it fails with the same fix-it.

**V2, `let q = t"..."` with no annotation: plt's reading.** Do the same thing as `let x = None` does today. `C` is a fresh variable that a later use solves, and E0301 fires only if it is still unsolved where the existing 8vcj2c rule checks it. Add no rule that is specific to templates. An earlier E0301 at the `let` would be a special case.

**V3, where E0530 is checked: I retract "a check on the text alone".** Fact 3 (6-0) says `let r = Raw(table)` has type `Raw[Str]`, and `t"... {r}"` is the same bypass. So the check must stay type-based, as plt writes it: hole type in `HoleTy ∪ Raw[HoleTy∖Bytes]`, and a `Raw[T]` anywhere else is E0530. sys and devops made the same error. The parser cannot see a `Raw` that went through a binding.

**V4, `QuotedTemplateHole` lint: not in this decision.** It is a lint, not a language change, and it applies under both T and U. Log it as its own friction or feature ticket if aiml wants it. YAGNI until a user writes `'{x}'` and gets bitten.

**V5, diagnostic: reuse `TemplateMismatch`.** Do not add `TemplateNeedsTag`. The mismatch already exists, and it is the same error: `Str` where `Template[C]` is expected. Change only the `help:`, which becomes machine-applicable and adds the `t`. One error code fewer.

**V6, rollout: no user-facing warning phase.** The only users are lib/std/db.bl, db_sqlite.bl and tests, and examples/ has none. The 3-step bootstrap is an internal compiler procedure that CLAUDE.md already requires. It is not a language rule and must not go into the spec. Pre-1.0, a deprecation window for code that does not exist is waste.

**Response to the others.** All six of us put T first, and none of us proposes K. My only real disagreements are V3 (I now side with plt against sys, devops and my own earlier text) and V4 (out of scope).

**Stable, ready to vote:** T with `t#"..."#`, V2 plt, V3 plt, V4 out, V5 reuse `TemplateMismatch`, V6 no spec-level rollout.

</details>

#### Phase C — Final vote

<details>
<summary>Ballot</summary>

Phase C: silent vote. Phase B is closed: all six panelists said "stable, ready to vote" in round 1. Vote on your own. Do not message other panelists. Reply to team-lead only.

For EACH question give: (1) Vote: the option label; (2) Reasoning: 2-4 sentences from your domain; (3) Concern: one sentence on what could go wrong with the option you expect to win.

Each option below was put forward by one or more panelists in Phase A or B.

Q1. Template literal form.
  T: a `t"..."` prefix makes a template literal. A plain `"..."` literal never becomes a `Template[C]`.
  U: no prefix. Narrow the spec to the shipped rule (an untagged literal coerces only when written directly as a call argument).

Q2. (V1) `t#"..."#`.
  Yes: `t` may precede every string-literal form, including `#"..."#` (holes `#{e}`, depths as in §2.4.2).
  No: only `t"..."`.

Q3. (V2) `let q = t"..."` with no annotation.
  A: `Template[α]`, α fresh; any later use in the same definition may solve α; E0301 only if α is still unsolved when inference of the definition ends (as for `[]` / `None`, §3.4).
  B: E0301 at the `let` unless it has an annotation.

Q4. (V3) Where `Raw` is checked.
  Typing rule: hole type `Ti ∈ HoleTy ∪ Raw[HoleTy∖Bytes]` in `t"..."` (Raw folds, raises `RawBypassesParam`); a `Raw[T]` in a plain `"..."` hole or any other non-template position is E0530. Binding a `Raw` stays legal (§3b.5, 6-0).
  Textual: E0530 is a check on the source text: `Raw(...)` is legal only inside a `t` hole.

Q5. (V4) `QuotedTemplateHole` lint (quotes around a hole, e.g. `'{name}'`).
  In: a compiler lint on every `t"..."` literal, part of this decision.
  Out: not a language lint; file a separate ticket for a handler- or library-owned check (e.g. std DB).

Q6. (V5) Diagnostic for a plain literal where `Template[C]` is expected.
  Reuse: the existing `TemplateMismatch` code, with a machine-applicable `help:` that adds `t`; the reverse case (`t"..."` where `Str` is expected) is also a type error, with a `help:` that removes `t`.
  New: a new code `TemplateNeedsTag`.

Q7. (V6) Rollout.
  Final-rule-only: the spec states only the end rule; migration (add `t`, move lib/std/db*.bl and tests, delete the coercion) is the implementation ticket's job.
  Warning-phase: the spec defines a deprecation-warning period for untagged literals.

Q8. Spec text additions put forward by plt.
  Yes: (a) add the invariant "Every part of a `Template[C]` is literal source text, or text folded in from a `Raw[T]`."; (b) delete, not reword, "The auto-decomposition only works on string literals at the call site" in §3b.5.
  No: neither.

Q9. Prior rows "Multiple string delimiters — One string syntax" and "Implicit conversions" (DECISIONS.md, rejected features), and the §2.4.1 note "No new string syntax".
  Prefix-not-delimiter: both rejected-feature rows stand unchanged; `t` is a prefix on the existing delimiters, not a new string syntax; the spec text that says "no new string syntax is needed" for templates is rewritten to say so.
  Amend: amend the "One string syntax" row to admit `t"..."` as an exception.

</details>

| Question | Result | Tally |
|---|---|---|
| Q1. Template literal form | **T**: `t"..."` makes a template literal; a plain `"..."` never becomes a `Template[C]` | 6-0 |
| Q2. `t#"..."#` | **Yes**: `t` precedes every literal form, depths 1–3 | 6-0 |
| Q3. `let q = t"..."` with no annotation | **A**: `Template[α]`, α solved by a later use; E0301 only if still unsolved | 6-0 |
| Q4. Where `Raw` is checked | **Typing rule** | 6-0 |
| Q5. `QuotedTemplateHole` lint | **Out**: separate ticket for a handler- or library-owned check | 6-0 |
| Q6. Diagnostic | **Reuse** `TemplateMismatch` (E0310), help adds or removes `t` | 6-0 |
| Q7. Rollout | **Final-rule-only** | 6-0 |
| Q8. plt's spec additions | **Yes**: state the parts invariant; delete the "call site" sentence | 6-0 |
| Q9. Prior rows | **Prefix-not-delimiter**: both rejected-feature rows stand | 6-0 |

No question was closer than 6-0, so Phase D did not run.

<details>
<summary><b>Systems</b> ballot</summary>

##### Systems, Phase C ballot

**Q1. Vote: T**
- Reasoning: Concatenation and decomposition lower to different code. They differ in what they allocate, whether `Display` runs, and the security property, so the text alone must tell you which one you get. With `t"..."` you can see the cost of any literal without looking up its expected type, and the parts lower to a fixed array in `.rodata` as the normal case. Option U keeps a non-principal rule that depends on where the literal is written.
- Concern: Wrappers written before the change will reject a plain literal. Users who forget the `t` must get a clear help line that a tool can apply, so they do not reach for `Raw` to make the error go away.

**Q2. Vote: Yes**
- Reasoning: `t` should be a prefix that works with every string-literal form, so it composes with whatever jfwr2r decides about delimiters. SQL that holds JSON or regex text needs the raw form, or it fills up with `\{`. The cost to the lexer is one prefix check before a scan we already have.
- Concern: If jfwr2r later removes `#"..."#`, `t#"..."#` must go with it in the same change, so the two forms do not drift apart.

**Q3. Vote: A**
- Reasoning: `C` is phantom. Every `Template[C]` has the same layout and is lowered the same way, so solving α late cannot change the emitted code. Option B would make a template the only generic value that needs an annotation to be bound, and that is the kind of special case we are removing.
- Concern: Mono must never see an unsolved α. The E0301 check at the end of inference has to be strict, with no silent default.

**Q4. Vote: Typing rule**
- Reasoning: Fact 3 shows the `Raw` marker survives a binding, so a check on the text alone is unsound. I withdrew that claim in Phase B. The typing rule still reports the error at typecheck, so the compiler cost stays the same.
- Concern: The rule must cover `Raw` reached through generic code, for example `id(Raw(x))` in a hole. Write a test for it.

**Q5. Vote: Out**
- Reasoning: The lint encodes dialect knowledge. `'{x}'` is a mistake in SQL, but `href="{url}"` is correct in HTML. The 6-0 decision keeps dialect knowledge out of the compiler. A check in the DB handler, on the part text before each value, costs a few cycles per query and goes in the place that knows the dialect.
- Concern: No one may write the separate ticket's check, so a model's habit of quoting a hole still returns zero rows with no error.

**Q6. Vote: Reuse**
- Reasoning: `TemplateMismatch` already exists and fires today. A help line that a tool can apply gives all the precision we need, and a new code only adds a name to learn.
- Concern: The help must point at the literal, not at the whole argument, or the automatic fix will put the `t` in the wrong place in a nested expression.

**Q7. Vote: Final-rule-only**
- Reasoning: We are before 1.0, examples/ does not use the old rule, and the migration is the normal 3-step bootstrap. A warning period in the spec is surface that nobody would use.
- Concern: The implementation ticket might merge steps 2 and 3. The tree must still compile itself at every step.

**Q8. Vote: Yes**
- Reasoning: The invariant states the property that makes templates safe. It also allows handlers to key a prepared-statement cache on the identity of the parts, because the parts are fixed per call site apart from text folded in from `Raw`. The "only works on string literals at the call site" sentence describes a rule that no longer exists, so it must be deleted, not reworded.
- Concern: Folding a `Raw` makes the parts depend on runtime values, so a handler that caches by parts identity must handle templates that contain `Raw`.

**Q9. Vote: Prefix-not-delimiter**
- Reasoning: The quote character, the escapes and the hole syntax stay the same, so there is still one string syntax with an optional prefix. The "Implicit conversions" row gets stronger, because T removes the one implicit conversion string literals had. Amending the row would weaken a principle that this change actually obeys.
- Concern: A later prefix, such as `f"..."` under jfwr2r, could use the same argument to justify a growing set of prefixes. Each new prefix must still go through the panel.

</details>

<details>
<summary><b>Web/Scripting</b> ballot</summary>

Web/Scripting Phase C ballot: T, Yes, A, Typing rule, Out, Reuse, Final-rule-only, Yes, Prefix-not-delimiter.

**Q1. Vote: T.**
Reasoning: You can tell what a literal does from its own text. Python 3.14 uses exactly this spelling for exactly this meaning, so both JS/Python devs and LLMs read it right the first time. If you forget the `t`, you get a compile error with a one-character fix, not a silent bug, so the obvious code is still the safe code.
Concern: Python users may also write `f"..."`, or write `t"..."` where a `Str` is expected. The help in both directions has to be very good, or this becomes the new top Stack Overflow question.

**Q2. Vote: Yes.**
Reasoning: "A prefix composes with every literal form" is one rule. Banning one combination is an exception that people must learn. Brace-heavy templates that also have holes (JSON filters, HTML with inline JS) are a real case, and `#"..."#` already works at a template site today.
Concern: In `t#"..."#`, `{x}` is literal text and `#{x}` is a hole, so a dev can type `{x}` and expect a parameter. W1111 must fire inside `t#` literals as it does in `#"..."#`.

**Q3. Vote: A.**
Reasoning: Pulling a query out into `let q = t"..."` and then calling `db.query(q)` is the most common refactor anyone will do. If that needs an annotation, we bring back the "works inline, breaks in a let" trap under a new name. It also matches how `[]` and `None` already work.
Concern: When α is never solved, E0301 points at the `let` while the cause is a missing use further down. The help must name both places.

**Q4. Vote: Typing rule.**
Reasoning: §3b.5 (6-0) lets you bind a `Raw`, and `let r = Raw(t)` followed by `t"...{r}"` is the bypass, so a check on the text alone is wrong. I correct my own Phase A wording on this.
Concern: none beyond the existing caqzsw question about which `T` a `Raw[T]` may wrap.

**Q5. Vote: Out.** (This changes my Phase B lean.)
Reasoning: Quotes around a hole are a bug in SQL, but in HTML `<a href='{url}'>` is correct: the HTML handler escapes for the attribute. Only the handler knows its dialect, and the 6-0 design says the compiler encodes no dialect knowledge. A compiler-wide lint would give false positives for every HTML template user, and false positives teach people to ignore warnings. The std DB handler, or a lint that a library declares, should own this check.
Concern: Without the lint, the `'{name}'`-returns-zero-rows bug that aiml found stays silent until someone files and builds the separate ticket. Please file it.

**Q6. Vote: Reuse.**
Reasoning: There is one error class with one code, and the fix-it in both directions is what helps devs. A new code adds a name without new information.
Concern: The current message, "string variables cannot be implicitly converted to Template", would be wrong for a literal. The text must be rewritten, not just the help added.

**Q7. Vote: Final-rule-only.**
Reasoning: The spec says what the language is. There are no outside users and nothing in examples/ uses templates, so a deprecation period in the spec is noise. The bootstrap steps belong in the implementation ticket.
Concern: During the migration, lib/std and the spec disagree for a while. The implementation ticket should land as one chain.

**Q8. Vote: Yes.**
Reasoning: The invariant is the safety promise stated in one plain sentence, which is the line a security reviewer looks for. The "at the call site" sentence is the exact special case T removes, so rewording it would keep a ghost of it.
Concern: none.

**Q9. Vote: Prefix-not-delimiter.**
Reasoning: The rejected row is about competing quote characters ('single' vs "double" vs `backtick`). `t` uses the same quote, escapes and holes, the same way `#` already does. The "Implicit conversions" row actually supports T, since today's coercion is one.
Concern: Readers may still see `t"` and `#"` as "more string syntax". The rewritten §2.4 text should say clearly that there is one delimiter and two optional prefixes.

</details>

<details>
<summary><b>PLT</b> ballot</summary>

PLT, Phase C ballot: Q1 T, Q2 Yes, Q3 A, Q4 Typing rule, Q5 Out, Q6 Reuse, Q7 Final-rule-only, Q8 Yes, Q9 Prefix-not-delimiter.

Q1. Vote: T.
Reasoning: Under U, the literal has two typing rules with different premises (Display or not, HoleTy, Raw), and the checking mode picks one. Once HM metavariables exist, the expected type can be an unsolved α, so the literal's meaning depends on the order in which constraints are solved. That is not principal typing. With T, the literal produces its own type. Inference fixes only the phantom index, and a phantom index cannot change behaviour.
Concern: users may read the `t` itself as the safety guarantee and then write their own `fn run(sql: Str)` wrappers. The safety comes from the parameter type, and the docs must say so.

Q2. Vote: Yes.
Reasoning: A prefix should compose with every delimiter. A missing pair is a gap in the grammar that each user has to learn. Brace-heavy SQL such as jsonb literals is a real need, and the depth rules of §2.4.2 carry over unchanged.
Concern: if jfwr2r later changes the `#"..."#` hole rules, `t#` changes with them, so the two decisions must stay linked.

Q3. Vote: A.
Reasoning: `t"..."` should follow the same rule as `[]` and `None` (§3.4). B would make it the one expression whose metavariable must be solved where it is bound, which brings back a special case. α is phantom, so solving it late is sound.
Concern: the error for an unsolved α appears at the end of the function, far from the literal. The E0301 span must point at the `t"..."`, not at the end of the function.

Q4. Vote: Typing rule.
Reasoning: Under the 6-0 decision, `Raw[T]` is a real type that survives a binding (`let r = Raw(t)`, then `{r}`), so the source text cannot show where a Raw is. A textual rule would either reject the legal binding or miss the bypass through a variable. Only the typing judgment, which uses the literal's prefix and the hole's synthesized type, is both sound and complete.
Concern: implementers may still write a parser shortcut, so the spec should say "type" explicitly.

Q5. Vote: Out.
Reasoning: Whether a quote around a hole is wrong depends on the dialect. It is wrong in SQL (`'{x}'`) and correct in an HTML attribute (`href="{url}"`). A compiler lint would encode dialect knowledge, which §3b.5 forbids.
Concern: the separate ticket may stall, and the most common LLM mistake in SQL templates then stays undetected.

Q6. Vote: Reuse.
Reasoning: Str and Template are now simply different types, so a mismatch is an ordinary type mismatch. The existing code fits, and a machine-applicable fix in each direction keeps the cost of a wrong guess to one compile cycle.
Concern: in its new role the message must not say "string variables cannot be converted" when the argument is a literal. The note must name the `t` prefix.

Q7. Vote: Final-rule-only.
Reasoning: A deprecation period is a property of how we bootstrap the change, not of the language. The spec should describe the language only.
Concern: none of substance, since only lib/std/db*.bl and tests use the feature today.

Q8. Vote: Yes.
Reasoning: (a) This is the soundness invariant that injection safety rests on. Once it is stated, binding, returning and storing templates need no further rule. (b) The call-site sentence describes the restriction that T removes. Rewording it would leave a stale special case for readers and for training data.
Concern: the invariant must also hold for an implementation that shares storage (§3b.5 note), so the copy-on-write wording must stay.

Q9. Vote: Prefix-not-delimiter.
Reasoning: The "One string syntax" row is about delimiters (single, double, backtick), and `t` adds none. The "Implicit conversions" row is made stronger, because T removes an implicit conversion. However, §3b.5's "Why not a new string syntax" paragraph calls a prefix a violation of that principle, so that paragraph must also be rewritten, not only §2.4.
Concern: if the §3b.5 rationale paragraph is left in place, the spec will contradict itself.

</details>

<details>
<summary><b>DevOps</b> ballot</summary>

DevOps Phase C ballot: T, Yes, A, Typing rule, Out, Reuse, Final-rule-only, Yes, Prefix-not-delimiter.

Q1. Vote: T.
Reasoning: Only T makes both mistakes loud. A plain literal at a `Template[C]` site and a `t"..."` literal at a `Str` site are each a type error with a fix that `blink fix` can apply. Under U, if a sink changes from `Template[DB]` to `Str`, the code still compiles with no diagnostic, and no lint can see it, because both readings type-check. Grammars with no type checker (GitHub, tree-sitter) and reviewers can see `t"` and search for it.
Concern: agents trained on today's untagged spec examples will keep leaving out the `t` until every spec and std example is migrated in the same change.

Q2. Vote: Yes.
Reasoning: "`t` may precede any string form" is one rule for the grammar, highlighters and the formatter. If we forbid `t#`, we need a second rule, a second diagnostic, and SQL that holds JSON becomes a wall of `\{`.
Concern: `t#"...{x}..."#` keeps `{x}` as literal text, which can surprise a reader. W1111 must still fire inside `t#` literals.

Q3. Vote: A.
Reasoning: This matches `[]`, `None` and how HM metavariables already work, so it adds no special case to learn or explain. Hover shows the solved `Template[DB]`. When two uses conflict, the error must point at the second use, with a note that names the use that fixed `C`.
Concern: if the note naming the first use is left out, a conflicting-context error will point at a line that looks correct.

Q4. Vote: Typing rule.
Reasoning: Under the 6-0 rule, `let r = Raw(table)` keeps its `Raw[Str]` type, so `io.println("{r}")` can only be caught with types. A text-only rule would be wrong. A tool may still give a fast early warning for a literal `Raw(` inside a plain-literal hole, but that is not the normative rule.
Concern: an implementation may ship only the text check and miss `Raw` values that come through a binding. The conformance tests must include the bound case.

Q5. Vote: Out.
Reasoning: In HTML, `href="{url}"` puts quotes around a hole and is correct, so a lint over every `C` gives false alarms and builds dialect knowledge into the compiler, which §3b.5 forbids. A check owned by std DB catches aiml's `'{name}'` case without that cost. File it as its own ticket.
Concern: if the follow-up ticket is not filed and done, the strongest real-world misuse that aiml found stays silent.

Q6. Vote: Reuse.
Reasoning: E0310 already means "Str where Template is expected". One code for each type pair keeps `blink explain`, search results and the docs in one place. The help text is what matters, and both directions get a help that adds or removes `t` and that `blink fix` applies.
Concern: the existing note "string variables cannot be implicitly converted" must be reworded for the literal case, or it will mislead.

Q7. Vote: Final-rule-only.
Reasoning: The migration covers lib/std/db*.bl and tests only, and nothing in examples/. A warning period is bootstrap mechanics, not language text.
Concern: if the implementation splits the parser and std changes across regens badly, CI can break for a short time. That is an implementation risk, not a spec risk.

Q8. Vote: Yes.
Reasoning: (a) states the safety property in one sentence that conformance tests and reviewers can check. (b) Once a template is an ordinary expression, the "at the call site" sentence is false. If we reword it instead of deleting it, the old special case lives on in agents' training data.
Concern: none of note. The invariant has to hold for `t#` literals as well, which it does.

Q9. Vote: Prefix-not-delimiter.
Reasoning: The delimiter set does not change. `#"..."#` already sits alongside `"..."` under the same reading, and `t` is a prefix token in front of existing forms. The rewritten §2.4 text must say this in plain words, so the reasoning does not depend on how someone reads the row.
Concern: readers may see this as a loophole in "one string syntax". A short sentence in DECISIONS.md that names the prefix and states its limit (one prefix, no tags per context) will prevent that.

</details>

<details>
<summary><b>AI/ML</b> ballot</summary>

AI/ML Phase C ballot: T, Yes, A, Typing rule, Out, Reuse, Final-rule-only, Yes, Prefix-not-delimiter.

**Q1: T.**
Reasoning: With T, a model knows from the line alone whether a hole is a parameter or concatenated text. It does not need to look up a signature. A forgotten `t` gives a loud compile error with a one-character fix, never silent wrong behavior. Python 3.14 t-strings give the strongest training-data prior we could ask for.
Concern: Models trained on Python f-string SQL will often leave out the `t` at first. Each miss costs one compile round trip, so the fix-it must be machine-applicable and must name `t"..."` exactly.

**Q2: Yes.**
Reasoning: One rule ("`t` goes in front of any string form") has fewer decision points than a list of allowed forms. SQL that holds JSON needs literal braces and holes in the same literal.
Concern: `t#"..."#` uses `#{e}` holes. A model may write `{e}` there and get literal text, which then fails at the database. The existing W1111 warning for a `{identifier}` without `#` must also fire inside `t#"..."#`.

**Q3: A.**
Reasoning: "Bind, then pass" is the natural pattern. Forcing an annotation costs tokens and gives no safety, because `C` is phantom. A matches how `[]` and `None` already work, so a model learns nothing new.
Concern: When α stays unsolved, the E0301 points at the end of the definition and not at the literal. Its span and `help:` must name the `t"..."` site.

**Q4: Typing rule.**
Reasoning: A textual rule either quietly overturns the 6-0 decision that keeps the marker after a binding (`let t = Raw(table)`) or misses that case. With the typing rule, one mechanism covers inline and bound `Raw` values, so there is one thing to learn.
Concern: Implementers may still take the textual shortcut for the inline case and forget the bound case. The corpus needs a test of `{t}` where `t: Raw[Str]` is bound outside the literal.

**Q5: Out.**
Reasoning: Quotes around a hole are a bug in SQL and correct in HTML attributes. A compiler lint would put dialect knowledge into the language, against a prior decision. The `t` prefix already removes most of the model prior that caused the bug.
Concern: If no one files and finishes the follow-up ticket, the `'{name}'` → `'?'` bug for std DB stays silent. The ticket must be filed when this decision is recorded.

**Q6: Reuse.**
Reasoning: Each new diagnostic code is one more thing a model must learn and keep in mind. `TemplateMismatch` already names the exact problem, and fix-its in both directions cover the repair.
Concern: The message must not still say "string variables cannot be implicitly converted" for a literal. The note needs a separate wording for literals.

**Q7: Final-rule-only.**
Reasoning: A deprecation period puts both spellings into code that becomes training data. The only users are about five in-tree ops and some tests, so a user-facing transition has no audience. The spec should describe one way to do it.
Concern: The 3-step bootstrap must actually delete the coercion in step 3. If it stalls, the tree runs two rules for a long time.

**Q8: Yes.**
Reasoning: (a) states the safety invariant in one sentence a model can check code against. (b) removes text that would contradict the new rule, and keeping contradictory spec text is the worst case for learning from the spec.
Concern: Some other spec section (§9.3, `blink llms` topics) may still describe the old coercion. The edit has to sweep every mention, not only §3b.5.

**Q9: Prefix-not-delimiter.**
Reasoning: The row is about delimiters (single vs double vs backtick quotes), and `t` adds none. Calling it an "exception" would teach models that the rule has holes, and invite more of them.
Concern: A reader may still see "one string syntax" and `t"..."` as a contradiction. The rewritten §2.4 text should state plainly that prefixes (`#`, `t`) change the meaning of the content, never the delimiter.

</details>

<details>
<summary><b>Minimalism</b> ballot</summary>

Min, Phase C ballot: T / Yes / A / Typing rule / Out / Reuse / Final-rule-only / Yes / Prefix-not-delimiter

Q1. Vote: T.
Reasoning: T deletes a special coercion rule and its "literal at the call site" exception, and puts one lexer token in their place. Everything else is ordinary typing, so the net surface is smaller. The safety comes from the parameter type, not from the coercion. If you forget the `t`, you get a compile error, not an injection.
Concern: authors who copy SQL from other languages will keep writing the bare form. That costs them one fix-it round trip each time, and the help line must be good.

Q2. Vote: Yes.
Reasoning: when a prefix composes with every literal form, there is no rule to write. A ban on one combination would be the exception that we must spec, test and explain. JSON-in-SQL is a real use for it.
Concern: `t#"..."#` with `#{e}` holes is the densest form in the language, and few people will learn it.

Q3. Vote: A.
Reasoning: it is the same rule as `[]` and `None`, with nothing specific to templates. Option B would add a special case to the spec only to make the error come sooner.
Concern: when α stays unsolved, the E0301 points at the end of the definition, far from the `let`. The diagnostic must point at the literal.

Q4. Vote: Typing rule.
Reasoning: the 6-0 ruling that "the marker survives a binding" means that `let r = Raw(x)` followed by `t"{r}"` must work. A check on the text cannot see that `Raw`. My Phase A claim was wrong, and I withdrew it.
Concern: none specific. This is the rule we already have.

Q5. Vote: Out.
Reasoning: a lint is not a language rule, and it is equally relevant under every option. YAGNI until a real report exists. If one comes, a handler or library owns a context-specific check better (quoting is wrong in SQL but can be correct in other contexts).
Concern: the separate ticket gets no priority, and nobody files it.

Q6. Vote: Reuse.
Reasoning: it is the same mismatch, `Str` vs `Template[C]`, so one code with a better help line is enough. A new code adds a registry entry and gives nothing new.
Concern: none of note.

Q7. Vote: Final-rule-only.
Reasoning: the only users are lib/std/db*.bl and tests, and none are in examples/. A deprecation period in the spec would describe migration for code that does not exist. The bootstrap steps are a compiler procedure, not language text.
Concern: the implementation ticket could ship the error before it moves lib/std over. The usual bootstrap order prevents that.

Q8. Vote: Yes.
Reasoning: (a) states in one line the invariant that the whole design depends on, so later changes cannot quietly break it. (b) The sentence protects an exception that no longer exists, and rewording it would keep dead text in the spec.
Concern: none.

Q9. Vote: Prefix-not-delimiter.
Reasoning: the row rejects other quote characters (`'`, backtick). `#"..."#` already exists next to that row with no amendment, so a prefix on the same delimiters follows the precedent we already have. Under T the "Implicit conversions" row is upheld, not weakened, so neither row needs a change.
Concern: a reader may see "`t` is not new string syntax" as a fine split of words. The rewritten §2.4 text must say plainly what `t` adds.

</details>

### AI-First Review

| Criterion | Result | Reason |
|---|---|---|
| Learnability | Pass | Python 3.14 uses the same spelling for the same meaning; the spec states one rule |
| Consistency | Pass | Removes an implicit conversion and a call-site special case; α follows the `[]`/`None` rule |
| Generability | Pass | The literal alone shows whether a hole is a value or text |
| Debuggability | Pass | A forgotten or extra `t` is E0310 with a machine-applicable help |
| Token efficiency | Pass | One character per template literal |

### Final Spec

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    let q = t"SELECT * FROM users WHERE id = {id}"   // Template[α], α = DB from the use below
    db.query_one(q)
}

fn active_docs(owner: Int) -> List[Row] ! DB.Read {
    db.query(t#"SELECT * FROM docs WHERE meta @> '{"active": true}' AND owner = #{owner}"#)
}

fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")    // plain literal: always Str
}
```

- `t` is a prefix on the one delimiter, as `#` is. It composes with every literal form: `t"..."`, `t#"..."#`, `t##"..."##`, `t###"..."###`. W1111 fires inside `t#"..."#`.
- A plain `"..."` is always a `Str`. A `Str` where `Template[C]` is expected, and a template where `Str` is expected, are `TemplateMismatch` (E0310). For a literal, the help adds or removes the `t`, points at the literal, and is machine-applicable. No help offers `Raw(...)`.
- A template literal has type `Template[α]`. The expected type or a later use in the same definition solves α. If α is still unsolved at the end of inference, E0301 fires with its span at the literal.
- Every part of a `Template[C]` is literal source text, or text folded in from a `Raw[T]`.
- `Raw` is a typing rule: a `Raw[T]` hole of a template literal folds and raises `RawBypassesParam`; a `Raw[T]` anywhere else, including a hole of a plain literal, is E0530. Binding a `Raw` stays legal.
- The safety comes from the parameter type, not from the `t`.
- One prefix, no tags per context (`sql"..."`, `html"..."`). Each new prefix needs a panel vote.
- A check for quotes around a hole (`'{name}'`) is not a language lint; it belongs to the std DB handler or a library.
- The spec states only the final rule. The migration (add `t`, move lib/std and tests, delete the coercion) is the implementation's job.
