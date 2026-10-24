[< All Decisions](../DECISIONS.md)

# Template Hole Typed by a Type Parameter — Design Rationale

### Problem Statement

§3b.5 *Template Values* maps the static type of each hole of a `t"..."` literal to one value, and says "Any other hole type is `error[TemplateHoleType]` (E0534) ... The compiler reports it at typecheck, at the hole, and never at codegen." The table has no row for a type parameter. §3b.5 *`Raw(expr)`* says that a hole of static type `Raw[Str]` folds and raises `RawBypassesParam`, and that a `Raw[Str]` in any other position is E0530. The spec did not say what a hole of static type `T` does when a call sets `T` to `Raw[Str]`, or to any other type.

The ticket's example, with the spec form `t"..."` in place of the older plain-literal coercion that the ticket used:

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }
fn q[T](x: T) -> Str { show(t"SELECT {x} END") }
fn main() { io.println(q(Raw("users"))) }
```

Measured with gen1 before the panel (gen1 does not parse `t"..."` yet, so the probes use the older plain-literal coercion; read `show("...")` as `show(t"...")`): `check` passes; `run` stops with internal compiler error `TemplateHoleKindNotBuilt` in codegen. The same ICE happens for a struct (`q(Point { x: 1 })`), so every `T` that a caller sets to a type outside the table reaches codegen, not only `Raw[Str]`. `q(5)` and `fn q[T: Display]` compile. A hole of concrete type `Raw[Str]` (direct, through a binding or through a generic call that returns `Raw[Str]`) raises `RawBypassesParam` and is unchanged.

The ticket named four options: fold at mono with the warning at the instantiation; E0530 at the call that sets `T`; a bound that a `T` hole needs; or treat it as a value hole and reject `Raw` there.

Prior rules that bear on the question: §3b.5 (a hole has one value, "by the hole's static type"); the `Raw[T]` decision ([Raw wraps Str only](raw-wraps-str-only.md) Q2: a generic `Raw(x)` or `-> Raw[T]` fails "at the generic definition, never at mono"); §3.1 *Diagnostic Discipline* (1: no diagnostic whose repair does not exist; 2: "Every typing rule must be visible to `blink check`. No rule is enforced only at codegen"; 3: diagnostics at one point converge); §3.6 *Display Format Protocol* (a template hole does not call `Display`).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim, with ticket IDs removed. A moderator note at the end records the reading gaps.

#### Phase A — Independent proposals

All six seats proposed the same rule: E0534 at the hole, in the generic definition, whatever the bounds. They differed on the spec text, the help lines, the containing types, and a later bound.

##### Systems

**sys-1: a hole whose static type is or contains a type parameter is E0534 at the hole, at the generic definition**

Rule: the table in 03b *Template Values* maps a hole's static type to one value tag. A type parameter `T` has no row. A hole of type `T`, `Option[T]`, `List[T]`, or any type that names `T`, is `error[TemplateHoleType]` (E0534) at the hole, when the compiler checks the generic function. Bounds do not change this: no bound names the table, and `Display` is not called on a hole (03b:795, DECISIONS:196). The rule is the same for the caller's `T`: Template value, `Raw[Str]` or other type. The call that sets `T` is never the site of this diagnostic.

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }

fn q[T](x: T) -> Str { show(t"SELECT {x} END") }
// error[TemplateHoleType] E0534 at {x}: hole type T is not a template value type
//   help: convert in the body, `{x.display()}` with `T: Display`, or take the value as `Str`

fn q2[T: Display](x: T) -> Str { show(t"SELECT {x.display()} END") }   // hole is Str: ok
fn q3(x: Raw[Str]) -> Str { show(t"SELECT {x} END") }                // folds, RawBypassesParam at the hole
```

Repair exists (Diagnostic Discipline 1): `{x.display()}` under `T: Display` gives a `Str` hole, and a `Str` hole is a value. `Raw` has no `Display`, so a caller that passes `Raw` to `q2` gets E0523 or E0530 at the call, as 03_types:5573 says.

Probes:
- p1, p9, p10-template shape: E0534 at the hole in `q`. `check` reports it, so the codegen ICE `TemplateHoleKindNotBuilt` is unreachable (Discipline 2).
- p2, p3: `q(5)` and an uncalled `q` fail the same way. The rule does not depend on a caller. p3 matters most: a definition that is wrong must not pass because nobody calls it.
- p8 (`T: Display`, `{x}`): E0534 too. The hole does not call `Display`, so the bound proves nothing. The `help:` names `.display()`.
- p4 (`{id(Raw("users"))}`): the hole type is `Raw[Str]` after the generic call returns, so it folds and raises `RawBypassesParam`. Unchanged.
- p5, p6, p11: unchanged.

`RawBypassesParam` fires only at a fold, and a fold needs the static type `Raw[Str]` at the hole in the checked body. Under sys-1 no generic body folds a `T` hole, so the diagnostic never moves to an instantiation site. This follows the Q2 5-1 vote (E0534 "at the generic definition", "never at mono").

Cost: zero. Every hole has one tag at typecheck. Mono makes no choice between "value tag" and "fold" per instantiation, so there is no code-size growth and no second audit path. Codegen keeps its "never reaches here" assert.

Tradeoff: a generic library cannot put `T` in a template without a conversion. That is correct: a `T` that is `Int` in one call and `Raw` in another changes whether the text is a value or part of the SQL. A shape that differs by instantiation hides the injection boundary.

**sys-2 (rejected): fold at mono, warn at the instantiation**
Per-instantiation fold makes the audit site the call, not the hole. `@trusted(audit: K)` on the enclosing function (03b:986) then cannot suppress it. It also breaks "never at mono" and Discipline 2.

**sys-3 (rejected here): a sealed `TemplateValue` bound**
A bound like `T: TemplateValue` would allow monomorphized tags at zero cost. It adds a trait for 8 rows, and `Raw[Str]` fits no value tag. If the panel wants generic holes later, add it as a new decision; sys-1 does not block it.

**Cross-language**
Rust checks a generic body against its bounds, not against each instantiation (E0277 at the definition). C++ templates check at instantiation, which gave unreadable errors; concepts moved the check to the call. Swift and Haskell check at the definition. Python t-strings (PEP 750) and JS tagged templates keep hole values as untyped objects, which is why SQL injection stays possible there. sys-1 follows Rust.

##### Web/Scripting

**web-1 (recommended): a T hole is E0534 at the hole, in the generic definition**

The table in 03b *Template Values* lists concrete types. A type parameter is not a row. So a hole whose static type is `T`, `Option[T]`, or any type that contains a type parameter, is `error[TemplateHoleType]` (E0534). It fires at the hole, at typecheck, in the generic definition. Bounds do not change this: `T: Display` does not help, because a hole does not call `Display` (03b:795).

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }

fn q[T](x: T) -> Str { show(t"SELECT {x} END") }
// error[TemplateHoleType] at {x}: T is not a template value type
// help: take a concrete type: fn q(x: Str)
// help: with T: Display, send text: {x.display()}
```

Cases:
- Caller sets T to a Template value type, `Raw[Str]`, or any other type: no new diagnostic at the call. The definition is already rejected, so no instantiation exists. p1, p2, p8, p9 and the T-hole of p10 all fail at `check`, at the hole.
- `RawBypassesParam` stays where the static type is `Raw[Str]`: p4, p6, p11 are unchanged. A `Raw[Str]` can reach a fold only through a concrete `Raw[Str]` hole. Mono never folds, so no warning moves to an instantiation site.
- Repairs exist and compile (Diagnostic Discipline 1): a concrete parameter type; or `{x.display()}` when `T: Display`. A user who wants to pass Raw text writes `fn q(x: Raw[Str])`, and the audit-gated warning fires in `q`.
- Plain `"..."` hole with unbounded `T` (p10): this ticket does not decide it. It is the Display-sink bug. This rule does not touch it.

Check against prior votes:
- Same shape as the `Raw(x)` with `x: T` vote (DECISIONS.md:449, 5-1): error at the generic definition, never at mono.
- Diagnostic Discipline 2: `blink check` sees the rule. Today p1 and p9 pass `check` and stop in codegen. This closes that.
- Rule 3 (converge): one diagnostic, one place.
- Rule 1: the repair exists.

Tradeoffs from my domain:
- Cost: a JS or Python developer expects any value in a hole. In Python t-strings (PEP 750) and JS tagged templates a hole holds any object. The 5-minute explanation here is short: "a hole takes only the types in the table; convert first." The error names the type parameter and shows the repair.
- Benefit: no error appears at a distant call site, inside code the caller did not write. This is the C++ template failure mode. Rust, Swift and Kotlin check a generic body against its bounds at definition, so a Rust or Kotlin developer knows this model.
- Questions on Stack Overflow: few. One rule, one error code already in use.

**web-2 (not now): a sealed bound for the table**

A sealed trait, for example `TemplateValue`, would let `fn q[T: TemplateValue](x: T)` work. It has to exclude `Raw[Str]`, or it creates the T-hole bypass. It adds a trait, a seal rule, and a bound that lists every table row, including `Option[T]`. That is a new surface for a case no one has shown a need for. Add it later if generic query helpers appear in real code. web-1 keeps that path open, because a T hole is an error today and a bound would only turn some errors into successes.

**Rejected**
- Fold at mono: the audit warning would sit at a call, away from the bypass. It breaks 03b:967 ("where the bypass happens") and "never at mono".
- E0530 at the call that sets T to `Raw[Str]`: it leaves p9 (struct) and p2 (Int, which passes by luck) without a rule, and it checks only some instantiations.
- Treat as value hole, reject Raw: it needs a runtime or mono-time test of T, which is the C++ model.

##### PLT

**plt-1 (recommended): a hole is typed by the table or it is E0534, and a type parameter is not in the table**

Typing rule. A hole `{e}` in `t"..."` checks `e : τ` where `τ` is the static type at typecheck of the generic definition. `τ` must be a table row or `Raw[Str]`. `τ = T` (any type parameter, bounded or not) is `error[TemplateHoleType]` (E0534), at the hole, at the generic definition. `Option[T]`, `List[T]` and every type that contains a type parameter follow the same rule: the `Option` row demands a table type inside, and `T` is none. No bound changes this. `T: Display` does not apply, because `Display` is not invoked on a hole (03b:795, DECISIONS:196).

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }

fn q[T](x: T) -> Str { show(t"SELECT {x} END") }   // E0534 at {x}: hole type `T`
fn q2[T: Display](x: T) -> Str { show(t"SELECT {x.display()} END") }  // repair: a Str hole
fn q3(x: Str) -> Str { show(t"SELECT {x} END") }   // ok
```

help lines: "take `Str`", "send text: `{x.display()}` (needs `T: Display`)", "make the function non-generic". The repair exists and compiles (Discipline 1). It is visible to `blink check` (Discipline 2). Nothing reaches mono, so a T hole never exists at codegen.

Caller sets `T`:
- Template value type, `Raw[Str]`, or a struct: the call is fine. The error is already in `q`, which never compiles. Any instantiation needs no check, so p1, p2, p8, p9 and p3 all give E0534 once, at the hole. (p3, `q` never called, also errors: the rule is on the definition, as for `Raw[T]`, DECISIONS:449.)
- `RawBypassesParam` fires only at a hole whose static type is `Raw[Str]`: p4 (`{id(Raw("users"))}`), p6, p11 stay as they are. `id[T](x: T) -> T` is legal: no hole sees `T`. `Raw[Str]` arriving through `T` into a hole is unreachable, so the audit gate cannot be bypassed by a generic.
- p5 (`x: Str`): unchanged. p10 (plain literal `"plain {x}"` with `x: T`): that is the Display-sink bug, out of scope. Under this rule it is `T: Display` at the sink.

Soundness: one judgement, `Γ ⊢ e : τ`, `τ ∈ Table ∪ {Raw[Str]}`. It is closed under substitution because no `T` appears in it. A rule that accepted `T` would need `θ(T) ∈ Table` for each `θ`, and that is a check at mono. That check breaks "no rule enforced only at codegen" and "never at mono". It also moves the audit warning from "where the bypass happens" to the instantiation, where `@trusted(audit:)` on the enclosing function (03b:986) cannot be written by the author of the bypass.

Cross-language. Rust: a generic body must be valid for the bounds alone, with no post-mono errors (C++ templates differ: errors at instantiation, which concepts try to repair). Haskell: a class constraint on `T` is required before a method is used; here the "class" is the table. Swift: same as Rust. PEP 750 and JS tagged templates: holes are dynamic, so no static question.

**plt-2 (deferred): a sealed trait `TemplateValue` as a bound**

`fn q[T: TemplateValue](x: T)`, implemented for the table types, not for `Raw[Str]`. A T hole needs the bound and gives a runtime tag. This is sound and compositional. It costs a new sealed trait, an `Option[T]` impl rule, and a decision on `U64` and `Char` coherence. The spec has no use for it (YAGNI). Add it later; it makes plt-1's error gain a third `help:` line and breaks no program.

**Reject: fold at mono, or E0530 at the call that sets T**
Both contradict the 03b:910 "never at mono" vote and Discipline 2. E0530 at the call blames the caller for a fault in the callee body, and its repair is not at the call.

##### DevOps

**devops-1: E0534 at the hole, at the generic definition. No bound, no mono fold.**

*Rule*

A hole of a template literal whose static type is a type parameter `T`, or a type that contains `T` (`Option[T]`, `List[T]`, a tuple with `T`), is `error[TemplateHoleType]` (E0534). The span is the hole. The compiler reports it at typecheck, in the generic body, once. It does not wait for a caller. Bounds do not change this: `T: Display` does not help, because a hole does not call `Display` (03b:795).

This extends the Q2 vote (DECISIONS.md:449): a `Raw[T]` is E0534 "at the generic definition", "never at mono". The hole rule follows the same line. The table in *Template Values* gets one sentence: "A hole whose type is or contains a type parameter is E0534, whatever the bounds."

*Message*

```
error[TemplateHoleType]: hole `x` has type `T`, a type parameter; a template hole needs a concrete value type
  --> q.bl:3:28
   |  show(t"SELECT {x} END")
   |                ^ `T` can be any type; the caller may pass a type with no template value
   = help: convert in the body: `{x.display()}` (add the bound `T: Display`)
   = help: or take a concrete type: `fn q(x: Str)`
```

Both repairs compile. The first sends a `Str` hole. The second uses a row of the table. So the rule meets *Diagnostic Discipline* (1). The check runs in `blink check`, so it meets (2). One error at one point, and no second error at the call, so it meets (3).

*Cases*

| Case | Result |
|---|---|
| `T` set to a table type (p2, p8) | E0534 in `q`. The caller is not at fault. |
| `T` set to `Raw[Str]` (p1) | The same E0534 in `q`. `Raw` never reaches a T hole, so no fold happens at mono. `RawBypassesParam` stays at typecheck, at a `Raw[Str]` hole that the compiler sees. |
| `T` set to a struct or other type (p9) | The same E0534 in `q`. The ICE is gone: codegen only sees checked holes. |
| `q` never called (p3) | E0534. The error does not depend on a caller. |
| Generic call returns `Raw[Str]` into a hole (p4) | No change. The hole type is `Raw[Str]` after inference. Warning at the hole. |
| `x: Raw[Str]` hole (p6), `let r = Raw(..)` hole (p11) | No change. Warning at the hole. |
| Plain `"plain {x}"` with unbounded `T` (p10) | Not this ticket. It is the Display-sink bug: E0523 at the definition (03_types:5573). With `{x.display()}` and `T: Display`, a caller that passes `Raw[Str]` gets E0530, not E0523 (03_types:5586). |

*Why not the ticket's options*

- Fold at mono, warning at the instantiation: breaks (2) and the Q2 vote. `blink check` of `q` is clean, and the error shows only in a caller, maybe in another package. The audit sits on `@trusted` of the enclosing function, but the fold happens in a function that did not write `Raw`.
- E0530 at the call that sets `T`: the message names code the user did not write, and the repair is in `q`, not at the call. The error would repeat for each instantiation.
- A bound `T: TemplateValue`: no trait names the set, and a sealed trait with `Option[T]` and `Raw` special cases adds language surface. It can come later as a new proposal; E0534 does not block it. The LSP could then offer the bound as a quick fix.
- A value hole that rejects `Raw`: needs the instantiation to reject, so it is the call-site option again.

*Tooling*

- LSP: the hole shows `T` on hover. The quick fix inserts `.display()` and the `Display` bound.
- `blink fmt`: no change.
- Lint: no change.
- One error code, and the existing E0534 text gets one new `help:` form.

*Cross-language*

Rust `format_args!` checks `T: Display` at the definition. A body that lacks the bound does not compile, and no instantiation can fail later. Swift and Haskell check generics at the definition in the same way. C++ templates check at instantiation, and the errors are long and name code the user did not write; this is the failure to avoid. Go checks type sets at the definition. Python t-strings (PEP 750) and JS tagged templates are dynamic: each hole is any value, and the tag decides. Blink does not follow them, because the handler's `TemplateValue` set is closed.

*Cost*

A generic function cannot forward `T` into a hole. The repair is one call. I accept this.

##### AI/ML

**aiml-1 (preferred): a hole type that mentions a type parameter is E0534 at the hole, in the generic definition**

Rule. The table in 03b "Template Values" lists concrete types. A hole whose static type is a type parameter `T`, or any type that contains `T` (`Option[T]`, `List[T]`, `Raw[T]`), is `error[TemplateHoleType]` (E0534). It is reported at typecheck, at the hole, in the generic definition. It does not depend on bounds and does not wait for an instantiation. The caller never matters: `q(5)`, `q(Raw("users"))` and `q(Point {..})` all fail at the definition of `q`, before any call exists.

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }

// error[TemplateHoleType]: hole `x` has type `T`
fn bad[T](x: T) -> Str { show(t"SELECT {x} END") }

// repair 1: a concrete type
fn ok1(x: Int) -> Str { show(t"SELECT {x} END") }

// repair 2: keep T, send its text
fn ok2[T: Display](x: T) -> Str { show(t"SELECT {x.display()} END") }
```

Help text: "a hole needs a concrete type from the table; use `{x.display()}` if `T: Display`, or name the type". Each repair compiles (Diagnostic Discipline 1). The rule is visible to `blink check` (2). One diagnostic, one place, so the error converges (3). This copies the `Raw(x)` with `x: T` precedent (DECISIONS.md:449, 5-1): checked "at the generic definition, never at mono".

Per probe:
- p1, p9: E0534 at the `{x}` hole in `q`. The ICE cannot be reached.
- p2, p3, p8: E0534 at the hole. p3 (`q` never called) now fails too, which is correct: the defect is in `q`. p8 shows a `Display` bound does not help, because a hole does not call `Display` (03b:795, DECISIONS.md:196). The repair `{x.display()}` is in the help.
- p4, p6, p11: no change. The static type at the hole is `Raw[Str]`, so it folds and raises `RawBypassesParam` at the hole. `id(Raw("users"))` is `Raw[Str]` after inference, not `T`.
- p5: no change.
- p10 (plain literal): out of scope. The separate Display-sink bug covers it.

`RawBypassesParam` has no new site. A `Raw[Str]` can reach a `T` hole only by instantiation, and the rule forbids that hole. `Raw[Str]` has no `Display`, so `T: Display` rejects `q(Raw(..))` at the call (E0523/E0530, existing rule). No fold happens at mono, so no audit moves to the instantiation site.

*Why this serves an AI*
- One rule, no mono-time case: "a hole type is a concrete table row." A model learns it from the table alone. The ticket's other options need a second rule about instantiation sites (what the caller sees, where to put `@trusted`). Errors that appear in the caller for code the caller did not write are hard for a model to repair.
- No new trait, no new bound spelling. A `TemplateValue` bound would add a name a model must recall and a decision for each generic wrapper (`T: TemplateValue` or `T: Display`?). The table has no trait today (see facts). Do not add one for a rare pattern.
- The cost: a generic wrapper that forwards `T` into a template must call `.display()` or take a concrete type. This is one token pair and the help line names it. Generic template builders are rare; SQL-style code takes `Str`, `Int`, or `Option[..]`.

**aiml-2 (fallback): accept T holes under a `TemplateValue`-like bound**
Reject. It adds a trait, still needs a rule for `Raw[Str]` through T (a bound that includes Raw makes the fold appear at an instantiation, in code the caller did not audit), and moves the audit away from "where the bypass happens" (03b:967).

**Rejected: fold at mono / E0530 at the call setting T**
Both break Diagnostic Discipline 2 in spirit (the rule shows only after instantiation, and `check` of an uncalled `q` stays silent) and 03b:910 ("never at mono"). The E0530 variant has no repair for the caller: `q` is the one that is wrong.

**Cross-language**
Rust checks generics at the definition against bounds and gives an error in the generic body, not at each call (the aiml-1 shape). C++ templates check at instantiation and give long errors in the caller; that is the pattern to avoid. Swift and Haskell also check generic bodies at the definition. Python PEP 750 t-strings hold any object in an `Interpolation`, so the handler decides; Blink has a closed `TemplateValue` set, so the check must move to the hole.

##### Minimalism

**min-1: No new rule. A hole typed `T` is already E0534, at the hole, at typecheck.**

*Position*

The spec is not silent. 03b:782-795 says each hole becomes one value "by the hole's static type" and "any other hole type is `error[TemplateHoleType]` (E0534) ... at typecheck, at the hole". A type parameter `T` is not a row in the table. So it is "any other hole type". The gap is in the compiler (typecheck lets `T` through), not in the spec. The fix is one sentence of clarification in 03b *Template Values*, and a typecheck change. No new bound, no new syntax, no mono-time fold, no new diagnostic code.

Rule: a hole whose static type is a type parameter `T`, unbounded or with any bounds, is E0534 at the hole, in the generic definition. The same holds for any type that contains `T` (`Option[T]`, `List[T]`, a struct with a `T` field). Only `Option[X]` where `X` is a table row is allowed, as the table says today.

```blink
type Ctx {}
fn show(t: Template[Ctx]) -> Str { "{t.count()}" }

fn q[T](x: T) -> Str { show(t"SELECT {x} END") }          // E0534 at {x}
fn q2[T: Display](x: T) -> Str { show(t"SELECT {x} END") } // E0534 at {x}: holes do not call Display
fn q3[T: Display](x: T) -> Str { show(t"SELECT {x.to_str()} END") } // ok: hole is Str
fn q4(x: Str) -> Str { show(t"SELECT {x} END") }          // ok
```

Repair (exists, so Diagnostic Discipline 1 holds): make the parameter concrete, or turn it into a `Str` first with `x.to_str()` under `T: Display`, or take a `Template[C]` parameter and compose.

*Why this meets the other options' goals with no new surface*

- Raw at `T`: it cannot happen. `q` fails at its definition, so no call can set `T` to `Raw[Str]`. `RawBypassesParam` fires only at a hole of concrete static type `Raw[Str]` (03b:906), as now (p4, p6, p11 unchanged). No fold at mono, so no warning moved to an instantiation site, and no audit gap. This matches Q2 (Raw[T], 5-1): check at the generic definition, never at mono. It also matches Diagnostic Discipline 2 and 3: one rule, one place, visible to `blink check`.
- A `T`-bound option (no `Raw`) needs a trait that names the Template value set. No such trait exists (brief, last fact). Adding one is new surface for a case where a concrete type already works.
- E0530 at the call that sets `T`: the call is fine; the definition is wrong. The diagnostic would point at a caller who cannot repair it. That breaks Discipline 1.
- Value-hole-and-reject-Raw: needs a second hole kind. Not needed.

*Probes*

p1, p9: E0534 at `{x}` in `q`; no ICE, so `TemplateHoleKindNotBuilt` becomes unreachable for `T` holes. p2, p8: now also E0534 (they compile today only because the check is missing). p3 (never called): E0534 still, because the check is at the definition (min dissent in Q2 asked for exactly this). p5: ok. p4, p6, p11: unchanged warning. p10 (plain literal, unbounded `T`): not this ticket. With `T: Display`, `q(Raw(..))` is E0523/E0530 at the call per 03_types 5573/5586.

*Tradeoffs*

Cost: a generic function cannot put a bare `T` in a template hole. It must pick a type, which is the honest answer: the hole kind (int, string, bytes) decides the driver binding, and no `T` can promise one. Gain: zero new rules, monomorphization never decides template safety.

*Cross-language*

Rust `sqlx::query!` and C++ concepts check the bound at the definition; Rust checks a generic body once, before monomorphization. Python PEP 750 t-strings take any object and leave the check to the consumer, which is the unsafe path Blink chose to avoid. Go type sets and Swift generics also check at the definition.

If the panel wants more than this: a Template-value trait is the only follow-up I would hear, and only after a real use case.

#### Phase B — Debate highlights

One round. The moderator sent a digest of the points all six Phase A files state, five variations (V1 to V5) and two repo facts. Each seat replied after it read all six Phase A files.

**Points all six Phase A primaries state** (moderator digest):

- A hole of a `t"..."` literal whose static type is a type parameter `T` is `error[TemplateHoleType]` (E0534), at the hole, at typecheck, in the generic definition. It does not wait for a call or an instantiation.
- Bounds do not change this. `T: Display` does not help, because a hole does not call `Display` (03b:795).
- The same rule covers `Option[T]` and other types that contain `T`.
- No diagnostic fires at the call that sets `T`. No fold at mono. `RawBypassesParam` fires only at a hole whose static type is the concrete `Raw[Str]` (p4, p6, p11 unchanged).
- p1, p2, p8, p9 give E0534 at the hole. p3 (`q` never called) also gives E0534. p5 is unchanged.
- The ticket's options "fold at mono", "E0530 at the call that sets `T`" and "a value hole that rejects Raw" are not proposed by any seat.
- p10 (plain-literal hole) is not this ticket (the Display-sink bug).

**Repo facts surfaced in the digest:**

- p10 uses a plain `"plain {x}"` literal, not a template (brief, Facts).
- `trait Display` declares `fmt` and the sealed default `display(self) -> Str` (03_types.md:3803–3809). `to_str` is declared on `StringBuildOps` (03_types.md:612), on `Ptr[U8]` returning `Option[Str]` (07_trust_modules_metadata.md:759), and on string-backed enum variants (03_types.md:2531). `Display` has no `to_str`.

**Variations** (flagged for debate):

- **V1. Spec text: new sentence or existing rule.** min-1: "The spec is not silent ... The gap is in the compiler (typecheck lets `T` through), not in the spec. The fix is one sentence of clarification in 03b *Template Values*, and a typecheck change." devops-1: "The table in *Template Values* gets one sentence: \"A hole whose type is or contains a type parameter is E0534, whatever the bounds.\""
- **V2. The repairs the spec names (help lines).** Two help lines, a concrete type and `{x.display()}` with `T: Display` (sys-1, web-1, devops-1, aiml-1). plt-1 adds a third: "make the function non-generic". min-1: "make the parameter concrete, or turn it into a `Str` first with `x.to_str()` under `T: Display`, or take a `Template[C]` parameter and compose."
- **V3. `Raw[T]` in the list of `T`-containing types.** aiml-1 lists "`Option[T]`, `List[T]`, `Raw[T]`". devops-1 names a tuple with `T`; min-1 names "a struct with a `T` field". Others say "any type that contains" or "names" `T`.
- **V4. A later sealed `TemplateValue` bound.** Deferred, may come later: web-2, plt-2, devops-1. Rejected: aiml-2, sys-3. min-1: "Adding one is new surface for a case where a concrete type already works." Open: should the spec or the rationale mention a later bound at all?
- **V5. p10.** web-1: "p1, p2, p8, p9 and the T-hole of p10 all fail at `check`, at the hole." sys-1: "p1, p9, p10-template shape: E0534 at the hole in `q`." devops-1: p10 "is the Display-sink bug: E0523 at the definition (03_types:5573)."

##### Systems (B1)

**V1.** I support min: the existing text already covers `T` ("any other hole type", 03b:795), and the gap is in typecheck. I also support devops' one added sentence: "A hole whose type is or contains a type parameter is E0534, whatever the bounds." The sentence costs nothing and answers the next reader's question, since the table has no `T` row and the ticket was filed because of that. It is a clarification, not a new rule.

**V2.** The help lines must name only a repair that compiles. `Display` has `display(self) -> Str` (03_types:3803-3809) and no `to_str`. So min's `x.to_str()` under `T: Display` does not compile, and it breaks Diagnostic Discipline 1. Use `{x.display()}`. Keep two helps: `{x.display()}` under `T: Display`, and a concrete type. plt's third help (make the function non-generic) is the second one in other words; I would fold it in. Message text: take devops' wording for the label, and keep the help lines as the spec text. I do not mind either way on the exact message.

**V3.** Say "a type that contains a type parameter" and give `Option[T]` as the one example. `Raw[T]` already has its own rule (E0534 at definition, Q2). A hole of type `Raw[T]` needs no new text. Do not list every container.

**V4.** Do not mention a later `TemplateValue` bound in the spec. The spec states what is true now. Put one line in the decision file as a non-blocking note.

**V5.** p10 is out of scope. It is a plain-literal Display sink (03_types:5573), not a template hole. Correct my A file: "p10-template shape" meant the T hole of a `t"..."` form, and that form is E0534 under this rule. The plain-literal form is the other bug.

**Ballot.** (1) sys-1/min-1 rule: E0534 at the hole in the generic definition, covers `T` and types containing `T`, bounds ignored. (2) Spec text: add the one devops sentence. (3) Reject: mono fold, E0530 at the call, value hole that rejects Raw, `TemplateValue` bound now.

STATUS: ready to vote

##### Web/Scripting (B1)

**V1. New sentence.** Support devops-1. min-1 is right that the existing text reads "any other hole type is E0534", but the ticket exists because a reader, and the compiler, did not read it that way. A type parameter is not a "hole type" a user can look up in the table. One sentence costs nothing and stops the next filer. Add it: "A hole whose type is or contains a type parameter is E0534, whatever the bounds."

**V2. Help lines.** Two lines: take a concrete type, and `{x.display()}` with `T: Display`. Reject plt-1's third line ("make the function non-generic"): it repeats line one. Reject min-1's `x.to_str()`: per the facts, `Display` has no `to_str`, so the repair would not compile. That breaks Diagnostic Discipline 1. Use `display()`. Take devops-1's message text and label. Both are short and say why.

**V3. Containing types.** Say "is or contains a type parameter" in the spec and list no types. A list (`Raw[T]`, tuple, struct) goes stale. `Raw[T]` is already E0534 by Q2, so naming it adds a second route to the same error.

**V4. Sealed bound.** Do not mention it in the spec. Spec text for a feature that does not exist is a promise, and min-1 is right that a concrete type works today. I keep web-2 only in the decision rationale as "may come later; E0534 does not block it". That costs the spec nothing.

**V5. p10.** I correct my Phase A. The T-hole of p10 is in a plain `"..."` literal. It is the Display-sink bug, not this rule. Remove it from my list.

**Ballot.** Put on the ballot: (a) the one rule that sys-1, web-1, plt-1, aiml-1, devops-1 and min-1 share, E0534 at the generic definition; (b) the spec change as a new sentence (V1), yes or no; (c) help lines as in V2. Do not put the ticket's three other options on the ballot. No seat proposed them.

STATUS: ready to vote

(web's file states that it read B1.md and A/web.md in full, and only the first part of the other five A files.)

##### PLT (B1)

**V1. Add one sentence.** min is right that "any other hole type" covers `T` on a plain reading. But 03_types:2659 says each instantiation is distinct, so "static type" can be read as the instantiated type. That is the reading the ticket's filer and codegen took. One sentence removes the reading: "A type parameter has no row. A hole whose type is or contains one is E0534 in the generic definition, whatever its bounds." I take devops's wording. It is a clarification, not a new rule, so it needs no new vote on substance.

**V2. Help lines: two, not three.** I withdraw my third line ("make the function non-generic"). "Name a concrete type" already covers it. min's `x.to_str()` is wrong: `Display` declares `display`, not `to_str` (03_types:3803-3809). The repair must be `{x.display()}` under `T: Display`. A help line that does not compile breaks Discipline 1. min should concede. min's third repair (a `Template[C]` parameter) is true but long. I do not object, I do not need it. The devops message text is good. The label "the caller may pass a type with no template value" is accurate because it explains why a bound cannot help.

**V3. List only types that contain `T` and can exist.** `Raw[T]` cannot be a hole type: it is E0534 at its annotation (03b:910), so the hole would raise a second error for one fault. That breaks convergence (Discipline 3). Say "a type that contains a type parameter, such as `Option[T]` or `List[T]`", and give no list that includes `Raw[T]`.

**V4. No mention of a later bound in the spec.** The spec describes the language, not plans (blueprint rule). A rationale line in `decisions/` may say that E0534 does not block a later sealed bound. Not on the ballot.

**V5. p10 is out of scope.** Its hole is in a plain literal, so the rule is the Display sink (E0523 at the definition, 03_types:5573). web and sys should drop p10 from their lists for this ticket.

**Ballot.**
- A: E0534 at the hole in the generic definition, any bound, types containing `T` included, one new sentence in 03b (all six primaries).
- B: a sealed `TemplateValue` bound now. I vote against it; keep it only so the panel sees it rejected.
- C: fold at mono, or E0530 at the call. Contradicts DECISIONS:449 and Discipline 2. Keep it for the record.

STATUS: ready to vote

##### DevOps (B1)

**Positions**

**V1. Add the sentence.** min is right that "any other hole type" covers `T` for a careful reader. But the text says "static type" and lists only concrete rows, and the compiler let `T` through. An implementer can fairly ask whether `T` counts. One sentence in *Template Values* ("A type parameter is not a row: a hole whose type is or contains one is E0534, whatever its bounds") costs nothing. The E0534 row in ERROR_CATALOG.md gets the same words. The work stays a spec clarification plus a typecheck change.

**V2. Two help lines.** (a) `{x.display()}` with `T: Display`; (b) take a concrete type. plt's third line ("make the function non-generic") repeats (b). min's repair `x.to_str()` does not compile under `T: Display`: `Display` has `display`, not `to_str` (03_types.md:3803-3809). The spec must say `.display()`. min's "take a `Template[C]` and compose" is a real repair but not a one-line fix; leave it out of the help. The spec fixes the help lines, not the label wording.

**V3. Say "is or contains a type parameter".** Do not list types. A list invites a question about each type left out. `Raw[T]` is already E0534 at its annotation (03b:911). A struct hole is E0534 with or without a `T` field, so that example adds nothing.

**V4. Do not mention a later bound in the spec.** The spec states the rule now, not a plan. The rationale file in decisions/ may say that a `TemplateValue` bound is undecided, that E0534 does not block it, and that it would have to exclude `Raw[Str]`.

**V5. p10 is out of scope.** p10 uses a plain `"..."` literal, which is a Display sink: E0523 at the definition when `T` lacks `Display`. web's claim that the T-hole of p10 gives E0534 is wrong, because E0534 applies only to `t"..."`. The ballot must not say p10 gives E0534.

**Ballot**
1. Rule: E0534 at the hole, in the generic definition, whatever the bounds. All six agree. Put the three ticket options on the ballot as rejected alternatives only if a seat moves one.
2. Spec text: the new sentence plus the catalog row (devops, web), or no spec change (min).
3. Help lines: two, with `.display()`.

STATUS: ready to vote

##### AI/ML (B1)

**V1.** I side with devops: add one sentence to 03b *Template Values*, and change typecheck. min is right that the existing text implies E0534 ("any other hole type"). But a model that reads the table sees only concrete types and has to infer that `T` counts as "other". It is also the exact reading the compiler missed. An explicit sentence costs about 20 tokens and removes a decision point. Do it as a clarification, not a new rule.

**V2.** Two help lines, in this order: `{x.display()}` under `T: Display`, then a concrete type. Reject min's `x.to_str()`: per the facts, `Display` has no `to_str`, so that repair does not compile and breaks Diagnostic Discipline 1. Reject min's "take a `Template[C]` and compose": it is a different design, not a repair for this hole. plt's "make the function non-generic" repeats the concrete-type line. Fewer lines mean fewer choices for a model. devops's message text is good: it names `T` and says why. Quote it.

**V3.** The wording should be "a type parameter, or any type that contains one". A list of examples invites the model to treat unlisted shapes as allowed. Put one example, `Option[T]`, in the text and no other list.

**V4.** Neither the spec nor the rationale should promise a later bound. A promise is a decision point for a model ("should I wait for `TemplateValue`?"). The decision file can record "not decided here". No help line names a bound.

**V5.** p10 is out of scope. web's phrase "the T-hole of p10" is wrong; p10 uses a plain literal. The decision file should not list it as covered.

**Ballot.** One question, two options: (A) E0534 at the hole in the generic definition (aiml-1, devops-1, sys-1, web-1, plt-1, min-1); (B) accept a `T` hole under a sealed bound. I expect A to win. Fold at mono and E0530 at the call need no ballot line; every seat rejects them.

I concede to devops on V1 and message text.

STATUS: ready to vote

##### Minimalism (B1)

I support the shared rule: a `T` hole, or a hole whose type contains `T`, is E0534 at the hole in the generic definition. Nothing else is needed. This is subtraction: no bound, no mono fold, no new code.

**Concession.** My A file said `x.to_str()` under `T: Display`. That is wrong: `Display` has `display()`, not `to_str` (03_types.md:3803-3809). The repair is `{x.display()}`. The other five seats have it right.

**V1. Spec text.** I withdraw "no spec change". The 03b table does not name a type parameter, and one reader sees "not in the table" and another sees "silent". The ticket itself was filed from that doubt. Add devops's one sentence to *Template Values*: "A hole whose type is or contains a type parameter is E0534, whatever the bounds." It adds no rule, and it ends the ambiguity. Do not add more text than that.

**V2. Help lines.** Two: a concrete type, and `{x.display()}` with `T: Display`. Drop plt's third line ("make the function non-generic"); it says the same as the first. Message text is devops's job in the catalog, not in the spec.

**V3. Containing types.** Say "a type that contains a type parameter" and give no list. A list invites "what about X?". `Raw[T]` already has its own E0534 (DECISIONS.md:449), so aiml's listing it adds nothing.

**V4. Later `TemplateValue` bound.** Neither the spec nor the decision rationale should mention it. A future bound needs its own proposal and its own vote. Text about a feature we do not have is surface we maintain. Record the rejection reasons only (new trait, `Raw[Str]` still needs a rule).

**V5. p10.** Out of scope. p10 is a plain `"..."` literal and the Display-sink bug owns it. Say that, and do not rule on it here. Web's "T-hole of p10" wording should go; sys's "p10-template shape" is fine only if it means a `t"..."` variant.

**Ballot.**
- A: E0534 at the hole in the generic definition, any bounds, `T`-containing types included, plus the one spec sentence. (My vote.)
- B: fold at mono, warning at the instantiation.
- C: E0530 at the call that sets `T`.
- D: a sealed `TemplateValue` bound.

Value-hole-and-reject-Raw is the call-site option again; leave it off.

STATUS: ready to vote

#### Phase C — Final vote

Silent ballot. Each seat voted alone and listed the files it read. Web's file states that it read only part of the other five Phase A files. The ballot named these points as stated by all six Phase B replies, so they were not on the ballot:

- A hole of a `t"..."` literal whose static type is a type parameter, or a type that contains one, is E0534 at the hole, at typecheck, in the generic definition, whatever the bounds. No diagnostic at the call that sets `T`. No fold at mono. `RawBypassesParam` fires only at a hole of concrete static type `Raw[Str]`.
- 03b *Template Values* gets one sentence that states this. It is a clarification, not a new rule.
- The spec names two help lines: `{x.display()}` with `T: Display`, and a concrete type. `x.to_str()` is not a repair, because `Display` has no `to_str`.
- The spec does not mention a later `TemplateValue` bound.
- `Raw[T]` is not listed among the types that contain `T`, because it is E0534 at its own annotation.
- A plain `"..."` literal is out of scope.

- **Q1: The rule** (6-0 for A)
  - A: E0534 at the hole in the generic definition, any bounds, types that contain `T` included.
  - B: a sealed `TemplateValue` bound now (`fn q[T: TemplateValue](x: T)`, implemented for the table types, not for `Raw[Str]`).
  - C: fold at mono, with `RawBypassesParam` at the instantiation.
  - D: E0530 at the call that sets `T` to `Raw[Str]`.
  - **Systems:** A — "A hole has one value tag, chosen at typecheck, and a type parameter `T` has no tag. If the tag depended on the instantiation, mono would choose between \"value\" and \"fold\" per instance, and the audit site would move to a call. That breaks \"never at mono\" and Diagnostic Discipline 2. Option A keeps one tag per hole, no per-instance codegen choice, and codegen keeps its assert." Concern: "A generic helper that forwards `T` into a template must convert first with `{x.display()}`, and that is one call the author has to write."
  - **Web/Scripting:** A — "One rule, one error code already in use, at the generic definition. A JS or Python dev who writes `fn q[T](x: T)` sees the error in the code they wrote, with a repair they can type. A `TemplateValue` bound (B) is a new trait for a case with no shown need, and it still needs a `Raw[Str]` rule. C and D put errors at a call site far from the cause and check only some instantiations." Concern: "A dev who wants a generic query helper has no generic path until a bound is added, and may reach for `Str` plus `.display()` everywhere."
  - **PLT:** A — "The hole judgement `Gamma |- e : tau` with `tau` in the table is closed under substitution only if `tau` holds no type parameter. Options C and D move the check to mono or to the caller. That breaks \"never at mono\" (DECISIONS:449) and Diagnostic Discipline 2, and D blames the caller for a fault in the callee body. Option B is sound but adds a sealed trait, an `Option[T]` impl rule and a `Raw[Str]` exclusion for no present use." Concern: "A rejects generic helpers that build templates from `T` values until a later bound exists, so the user must write `{x.display()}` or a concrete type."
  - **DevOps:** A — "`blink check` must report the fault in the generic body, once, at the hole. Then the user sees it before any call exists, and the repair (`{x.display()}` or a concrete type) is at the span shown. B and C move the check to a place `check` does not see, or to a caller who did not write the hole. D blames the caller for a fault in the callee and repeats per instantiation." Concern: "A generic wrapper that forwards `T` into a template now needs a conversion, and users may ask for a bound at once."
  - **AI/ML:** A — "One rule, checked at the generic definition, that a model can learn from the table alone: a hole type is a table row or it is E0534. B adds a trait name the model must recall, and each generic wrapper then needs a choice between `T: TemplateValue` and `T: Display`. C and D put an error in the caller for code the caller did not write, and the repair is not at the call." Concern: "A generic wrapper that forwards `T` into a hole must call `.display()` or name a type, and a model may try a `T` hole first and need one compile cycle to learn it."
  - **Minimalism:** A — "One rule, checked once at the definition, with no new trait, no mono-time case and no new code. It matches the Raw[T] vote (DECISIONS.md:449, \"never at mono\") and Diagnostic Discipline 2. B adds a sealed trait and still needs a Raw[Str] rule; C and D put the error at a caller who cannot repair it." Concern: "A generic wrapper that wants to forward a bare `T` into a template must convert or name a type, and real code may later ask for the bound."

- **Q2: How the sentence names the types that contain `T`** (Phase C: A 3, B 2, C 1; no majority for any option, so Phase D ran; Phase D result 6-0 for B, below)
  - A: "is or contains a type parameter", with no example and no list.
  - B: the same words with one example, `Option[T]`.
  - C: the same words with two examples, `Option[T]` and `List[T]`.
  - **Systems:** B — "The rule must be exact, and \"contains a type parameter\" is exact. One example, `Option[T]`, shows the shape a reader is most likely to miss, because the table already has an `Option` row. A longer list invites the question \"what about the types not listed\", and `Raw[T]` already has its own E0534." Concern: "With no example (A), a reader may think `Option[T]` is allowed because the table has an `Option` row."
  - **Web/Scripting:** A — "\"is or contains a type parameter\" is short and a learner can apply it with no list. A list goes stale and makes people ask about each type left out. The error message at the hole can show the real type, so the user sees an example when they need it." Concern: "A reader may not see that `Option[T]` counts, and the sentence leaves that to the message text."
  - **PLT:** C — "A type-theoretic rule is easier to apply with two examples of different shape, because the reader sees that a contained `T` does not unlock the table row (`Option` demands a table type inside). Both examples exist as hole types, so neither raises a second error (`Raw[T]` is left out for that reason, 03b:911). The cost is a few tokens." Concern: "Two examples invite the reading that only `Option` and `List` are covered, so the words \"a type that contains a type parameter\" must stay the rule and the examples must stay marked \"such as\"."
  - **DevOps:** A — "\"Is or contains a type parameter\" covers every shape. A list goes stale and makes readers ask about each type left out. The diagnostic message can show the real type at the hole (`Option[T]`), so the user sees an example where it helps." Concern: "A reader may not know that `Option[T]` counts, but the error text at the hole names it."
  - **AI/ML:** B — "With no example, a model must infer that `Option[T]` counts. With a long list, a model reads an unlisted shape as allowed. One example, `Option[T]`, shows that \"contains\" means nesting and gives no list to go stale. This costs about five tokens." Concern: "A reader may take `Option[T]` as the only container that counts, and the words \"is or contains\" must carry the rest."
  - **Minimalism:** A — "\"is or contains a type parameter\" is complete. Any example list invites the question \"what about the type not listed\", and a list goes stale. The rule is the same for every containing type, so an example adds no information." Concern: "A reader who does not see an example may not know that `Option[T]` is covered."

- **Q3: What the decision rationale says about a later `TemplateValue` bound** (Phase C: A 4, B 1, C 1; the ballot offered A, B and C; Phase D ran)
  - A: a non-blocking line: the bound may come later and E0534 does not block it.
  - B: record only "not decided here", with no promise.
  - C: no mention; record only the reasons the bound was rejected.
  - **Systems:** A — "Such a bound could give a monomorphized tag at zero cost, so I do not want this decision to close it. One non-blocking line says E0534 does not block it. The line stays in `decisions/` and not in the spec, so the spec makes no promise." Concern: "A reader may take the line as a plan, and a bound would still need a rule that keeps `Raw[Str]` out."
  - **Web/Scripting:** A — "One non-blocking line in the decision file tells the next filer that E0534 does not close the door on a bound. It costs the spec nothing, because the spec text stays silent. It stops a repeat ticket." Concern: "A rationale line can read as a promise and bring requests for the bound before anyone needs it."
  - **PLT:** A — "The decision file records the rationale, not the spec, so a non-blocking line costs the language nothing. It tells a future panel that E0534 does not close the door, and that a bound would have to exclude `Raw[Str]`. That keeps the blueprint rule: the spec says what is true now, the rationale says what was left open." Concern: "A line about a later bound can read as a promise, so it must say \"not decided here\" in the same sentence."
  - **DevOps:** A — "The rationale file records what the panel knew. One non-blocking line stops a later filer from re-opening E0534 as a blocker, and it states the one hard condition: the bound must exclude `Raw[Str]`. It is not in the spec, so no user or model reads it as a promise." Concern: "A reader may take the line as a commitment, so the wording must say \"not decided here\"."
  - **AI/ML:** B — "A promised bound is a decision point for a model that reads the rationale (\"do I wait for `TemplateValue`?\"). \"Not decided here\" records the open question and promises nothing. Option A's line \"E0534 does not block it\" is a soft promise, and C loses the record that the question was raised." Concern: "A future proposal may not know this panel rejected the bound for now, so the rationale must keep the rejection reasons next to \"not decided here\"."
  - **Minimalism:** C *(dissent)* — "The rationale file should record the reasons the bound was rejected (new trait, Raw[Str] still needs a rule, a concrete type already works). A line about a feature we do not have is text we maintain, and \"does not block it\" reads as a promise. A future bound needs its own proposal and vote, and nothing here prevents one." Concern: "A later proposer may not know this decision considered the bound, though the recorded rejection reasons cover that."

- **Q4: The E0534 row in ERROR_CATALOG.md** (5-1 for A, Minimalism dissent)
  - A: the row gets the same words as the new spec sentence.
  - B: no requirement on the catalog row in this decision.
  - **Systems:** A — "The catalog is the text a user reads when the compiler reports E0534. If the row lacks the type-parameter case, the first user to hit it finds no match, and the spec and the catalog drift apart. Same words in both costs nothing." Concern: "Two copies of the sentence can drift if a later change edits only one."
  - **Web/Scripting:** A — "Users meet E0534 through `blink explain` and the catalog before they read 03b. If the catalog row lacks the type-parameter case, the two texts differ and the user sees the gap first. Same words in both is cheap." Concern: "Two copies of one sentence can drift apart over time."
  - **PLT:** A — "The catalog row and the spec must not diverge (Discipline 3, one rule, one statement). One set of words is cheaper to keep correct than two. Tooling reads the catalog row for `blink explain`, so a stale row would hide the `T` case from users." Concern: "Two places holding the same sentence can drift later, so the decision should name the 03b sentence as the source."
  - **DevOps:** A — "`blink explain E0534` and the catalog are the first place a user looks after the error. If the row lacks the type-parameter case, the tool contradicts the spec. The same words in both cost one edit and keep them from drifting. The two help lines (`{x.display()}` with `T: Display`, and a concrete type) go in the row too." Concern: "If the catalog row and the spec sentence are edited in separate commits, they can differ."
  - **AI/ML:** A — "The catalog row is the text a model and a user read when they see E0534. If it differs from the spec sentence, there are two statements of one rule and they drift. Same words costs one line." Concern: "A catalog row that copies spec words will need an edit each time the spec sentence changes."
  - **Minimalism:** B *(dissent)* — "The decision should fix the spec sentence and the typecheck change, not the wording of a derived document. The catalog row for E0534 can follow the spec when the work lands, as for any other row, without a decision requirement that duplicates the words in two places." Concern: "The catalog row may drift from the spec sentence if no one updates it."

#### Phase D — Focused round on Q2 and Q3

Q1 (A, 6-0) and Q4 (A, 5-1) were decided. Q2 and Q3 had no majority option, so they got one focused round. The first reply (D1) let each seat hold or move and propose exact words. The second vote (D2) was silent and used fresh seats.

**D1 replies**

- **Systems.** Q2. Hold B. The A voters say the error text can show the real type. That helps a user after the error fires. It does not help the reader of the spec, who checks the table, sees an `Option` row, and must guess whether `Option[T]` passes. One example costs about six tokens and closes that guess. I do not move to C: a second example (`List[T]`) adds no new shape, because `Option[T]` already shows that "contains" means nesting. Wording: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds."
  Q3. Hold A, with a wording change. The soft-promise concern is fair. I want the line to say "not decided here" in the same sentence, as devops and plt ask. Wording: "Not decided here: a sealed `TemplateValue` bound. E0534 does not block one, and any such bound would have to exclude `Raw[Str]`." This keeps the record that the question was raised and keeps the one hard condition, and it gives no schedule. I do not move to B: aiml's concern (rejection reasons next to the line) is met if the rationale keeps its rejection reasons, and the A line can sit beside them.

- **Web/Scripting.** Q2. I move from A to B. sys and aiml name a real trap: the table has an `Option[...]` row, so a reader may think `Option[T]` passes. My own concern said the same. The message text at the hole helps only after the user hits the error, and the spec sentence is what the compiler author and the model read first. One example is enough. I do not want C: two examples start a list, and `List[T]` adds no new shape. Wording: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds."
  Q3. I hold A. A later bound is a real option, and a filer should see that E0534 does not close it. min and aiml are right that "does not block it" can read as a promise. I accept aiml's fix: the line says "not decided here" first. Wording: "Not decided here: a sealed `TemplateValue` bound. E0534 does not rule it out. It would have to exclude `Raw[Str]`. The reasons it was rejected for now stay above."

- **PLT.** Q2. I move from C to B. The `List[T]` example adds no case. Both examples work the same way, so the second one teaches nothing the first does not. The one shape a reader can misread is `Option[T]`, because the table has an `Option` row. B names that shape and nothing else. I keep my condition: the example must read "such as `Option[T]`", so it stays an example and not a list. Wording: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds."
  Q3. I hold A, with a wording change. A rationale file is where a rejected option and its reasons live. aiml is right that the line must not read as a promise, and that the rejection reasons must stay next to it. min is right that a later bound needs its own vote. The line below does both: "Not decided here: a sealed `TemplateValue` bound. E0534 does not block a later proposal for one. Such a bound would have to exclude `Raw[Str]`. It was not adopted now because it adds a trait, an `Option[T]` impl rule, and a `Raw[Str]` exclusion for no present use." This keeps the record that the question was raised (against C), and it makes no promise (against the A concern).

- **DevOps.** Q2. I move from A to B. All three A voters, me included, wrote the same concern: a reader may not see that `Option[T]` counts. The table has an `Option` row, so this is the one shape a reader is likely to misread as allowed. One example fixes that at the cost of a few words, and it does not create a list that can go stale. I reject C: two examples add no information over one, and `List[T]` has no table row to confuse. Words I want: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds."
  Q3. I hold A, with new wording. Min and aiml are right that "E0534 does not block it" reads as a promise. I drop that phrase. The line records the open question and the one hard condition, and promises nothing. Words I want in decisions/: "Not decided here: a sealed `TemplateValue` bound. This decision neither adds it nor rules it out. Any such bound would have to exclude `Raw[Str]`. Rejected for now: it adds a trait, and `Raw[Str]` needs its own rule." That keeps the record (aiml's point) and the rejection reasons next to "not decided here". If this wording wins A, aiml's concern is met.

- **AI/ML.** Q2. Hold B. The A voters rely on the error message to show `Option[T]`. A model reading the spec alone never sees that message, so the spec sentence must carry the example. min says an example adds no information. For a model it does: the table has an `Option` row, so "contains" is easy to misread as "allowed". One example costs about five tokens. If B loses, I prefer A to C: two examples start a list, and a list makes a model treat other shapes as allowed.
  Q3. Move to A, with exact words. Four seats want the line, and the line can say what the bound must do without a promise. My concern was the phrase "does not block it". Drop that phrase. I ask for these words in the decision file: "Not decided here: a sealed `TemplateValue` bound. Any such bound would have to exclude `Raw[Str]`. The reasons it was not taken now: it adds a trait, and a concrete type already works." This says "not decided here", states no plan, and keeps the rejection reasons next to it (min's request). The line stays out of the spec.

- **Minimalism.** Q2. I move from A to B. The table has an `Option` row. That is a real cause of misreading: a reader sees `Option[...]` as allowed and may not see that a `T` inside breaks it. My Phase C reason ("an example adds no information") was wrong for this case, because the example blocks one specific misreading. A message at the hole is not enough, because the spec sentence is what an implementer reads first. One example costs a few words and adds no list. I reject C: a second example adds nothing the first lacks. Wording I want: "A hole whose type is a type parameter, or a type that contains one, such as `Option[T]`, is `error[TemplateHoleType]` (E0534) in the generic definition, whatever the bounds."
  Q3. I hold C, and I rank B above A. A line in `decisions/` about a feature we do not have is text we maintain. Four of the A voters name the same concern: it reads as a promise. If the panel will not take C, I prefer B over A, with the rejection reasons next to it. Wording I accept for B: "A `TemplateValue` bound is not decided here. It was rejected for now: it adds a trait, and `Raw[Str]` still needs a rule." I do not accept "does not block it" or the sentence about excluding `Raw[Str]`. Those state design for a bound nobody proposed.

**D2 ballot for Q3.** The options after D1:

- A1: "Not decided here", the `Raw[Str]` condition, and a sentence that E0534 does not block a later bound (sys and plt wording).
- A2: "Not decided here", the `Raw[Str]` condition and the reasons, with no "does not block" sentence (aiml, devops and web wording).
- B: "Not decided here" and the reasons, with no `Raw[Str]` condition and no "does not block" sentence (min wording).
- C: no mention; record only the reasons the bound was rejected.

**D2 votes**

| Seat | Q2 | Q3 |
|------|----|----|
| Systems | B | A1 |
| Web/Scripting | B | A2 |
| PLT | B | A1 |
| DevOps | B | A2 |
| AI/ML | B | A2 |
| Minimalism | B | C (ranks B > A2 > A1) |

Q2: B, 6-0. Q3: A2 3, A1 2, C 1. No option has a majority. With Minimalism's ranking (B > A2 > A1), A2 beats A1 4-2, so A2 is the wording of record. Minimalism's first choice (C) was not chosen and stays a dissent.

- **Systems.** Q2. Vote: B. Reasoning: The hole table has an `Option` row, so a reader who checks it must guess whether `Option[T]` passes. One example, marked "such as", closes that guess for about six tokens. A second example (C) adds no new shape and starts a list; no example (A) leaves the guess to the error text, which the spec reader never sees. Concern: A reader may take `Option[T]` as the only container that counts, so the words "is or contains" must carry the rule and "such as" must stay.
  Q3. Vote: A1. Reasoning: A sealed `TemplateValue` bound could give a monomorphized tag at zero cost, so this decision must not close it. The line says "not decided here" in the first words, so it promises nothing, and it states the one hard condition (exclude `Raw[Str]`). It sits in `decisions/` and not in the spec, so the spec makes no promise. Concern: A reader may take the line as a plan, and a later bound would still need its own proposal and vote.

- **Web/Scripting.** Q2. Vote: B. Reasoning: The table has an `Option[...]` row, so a reader can think `Option[T]` passes. One example, marked "such as", closes that guess and starts no list. A second example (C) adds no new shape. A dev who reads only the spec sentence gets the answer without hitting the error first. Concern: A reader may take `Option[T]` as the only containing type, so the words "is or contains a type parameter" must stay the rule and the example must stay marked "such as".
  Q3. Vote: A2. Reasoning: The decision file should say "not decided here", name the one hard condition (`Raw[Str]` excluded), and keep the rejection reasons next to it. That stops a repeat ticket and does not read as a plan. I prefer A2 to A1 because the "does not block" sentence is the part four seats said reads as a promise; "neither adds it nor rules it out" or "does not rule it out" says the same with less promise. The line stays out of the spec. Concern: Any line about a later bound can still bring requests for the bound before anyone needs it, so "not decided here" must open the sentence.

- **PLT.** Q2. Vote: B. Reasoning: The rule is "a type that contains a type parameter". The table has an `Option` row, so `Option[T]` is the one shape a reader can take as allowed: the row asks for a table type inside, and a bare `T` is not one. One example, marked "such as", shows that nesting does not unlock the row. A second example (`List[T]`) adds no new case, and six seats now agree. Concern: A reader may take `Option[T]` as the only covered container, so the words "is or contains a type parameter" must stay the rule and "such as" must stay in the text.
  Q3. Vote: A1. Reasoning: The decision file is the place for a rejected option and the reasons. A1 says "not decided here" in the first words, so it records the open question without a promise. "Does not block a later proposal" is a statement of fact about the typing rule: E0534 is a check on `T` with no bound, and a sealed bound would change what bounds are in scope, so the rule does not forbid it. The `Raw[Str]` condition keeps the one soundness constraint on record, and the reasons stay in the same entry. Concern: A line about a bound we do not have can read as a promise, so "not decided here" must stay in the first sentence and the rejection reasons must stay beside it.

- **DevOps.** Q2. Vote: B. Reasoning: Five seats now hold B and the A voters moved for one reason: the table has an `Option` row, so a reader can take `Option[T]` as allowed. The spec sentence is what an implementer and a model read, and they never see the error text at the hole. One example marked "such as" closes that misreading and starts no list. I use the sys/plt/web words: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds." Concern: A reader may think `Option[T]` is the only container that counts, so "such as" must stay in the text.
  Q3. Vote: A2. Reasoning: The record should say the question was raised, give the one hard condition (exclude `Raw[Str]`), and keep the rejection reasons beside it. The A1 sentence "E0534 does not block" is the part min and aiml read as a promise, and A2 drops it with no loss: "neither adds it nor rules it out" says the same thing in neutral words. A2 keeps the line out of the spec and gives a later filer a clear answer when they search `decisions/`. My words: "Not decided here: a sealed `TemplateValue` bound. This decision neither adds it nor rules it out. Any such bound would have to exclude `Raw[Str]`. Rejected for now: it adds a trait, and `Raw[Str]` needs its own rule." Concern: A reader may still take the line as a plan, so "Not decided here" must stay the first words.

- **AI/ML.** Q2. Vote: B. Reasoning: A model reads the spec, not the error text. The table has an `Option` row, so without an example "contains" is easy to misread as "allowed". One example, marked "such as", shows nesting at a cost of about five tokens and starts no list. All six seats now accept B or can live with it, and C adds no new shape. Concern: A reader may take `Option[T]` as the only container that counts, so the words "is or contains a type parameter" must carry the rule and "such as" must stay.
  Q3. Vote: A2. Reasoning: The line records that the question was raised and states the one hard condition (exclude `Raw[Str]`), and it keeps the rejection reasons beside "not decided here". It leaves out "does not block it", which reads as a soft promise and gives a later reader a decision point ("do I wait for the bound?"). The line stays in `decisions/`, so a model reading the spec alone never sees it. Concern: A later proposer may read "would have to exclude `Raw[Str]`" as a design already chosen, so the line must keep "not decided here" first.

- **Minimalism.** Q2. Vote: B. Reasoning: One example adds no new rule. It blocks one misreading: the table has an `Option` row, so `Option[T]` can look allowed. A second example (C) adds no new shape and starts a list that goes stale. A (no example) leaves the one real trap open for a reader of the spec. Concern: A reader may take `Option[T]` as the only containing type that counts, so "such as" must stay in the sentence.
  Q3. Vote: C *(dissent)*. Reasoning: A line about a bound we do not have is text we maintain, and every A wording still states design for a feature nobody proposed: the `Raw[Str]` condition, or "does not block". A later bound needs its own proposal and vote, and nothing in this decision stops one. The rejection reasons already record that the question was raised. If C does not win, I rank B above A2 above A1. Concern: A later proposer may not see that this panel weighed the bound, though the recorded rejection reasons show it.

#### AI-First Review

**AI-First Review: 5/5 PASS**

| Criterion | Score | Notes |
|-----------|-------|-------|
| Learnability | PASS | A hole type is a table row or it is E0534. One sentence, one example. |
| Consistency | PASS | Same code and same "at the definition, never at mono" rule as `Raw[T]`. |
| Generability | PASS | `{x.display()}` with `T: Display`, or a concrete type. |
| Debuggability | PASS | One error at the hole, in the generic body, with two repairs. |
| Token Efficiency | PASS | No new trait, no new code. |

#### Final Spec

- A `t"..."` hole whose static type is or contains a type parameter is E0534 (TemplateHoleType). It fires at the hole, at typecheck, in the generic definition, whatever the bounds. An uncalled generic also errors.
- No error at the call that sets `T`. No fold at mono. `RawBypassesParam` fires only at a hole of concrete type `Raw[Str]`.
- 03b *Template Values* sentence: "A hole whose type is or contains a type parameter, such as `Option[T]`, is E0534, whatever the bounds."
- Repairs: `{x.display()}` with `T: Display`, or a concrete type.
- The ERROR_CATALOG E0534 row has the same words (Q4, 5-1).
- Q3 wording of record (A2): "Not decided here: a sealed `TemplateValue` bound. This decision neither adds it nor rules it out. Any such bound would have to exclude `Raw[Str]`. Rejected for now: it adds a trait, and `Raw[Str]` needs its own rule."

#### Dissents

- Minimalism, Q4 (B): the catalog row follows the spec when the work lands, with no decision requirement. The panel chose A, so the catalog row carries the same words.
- Minimalism, Q3 (C): record only the rejection reasons. The panel chose A2.
- Systems and PLT, Q3 (A1): they wanted the sentence that E0534 does not block a later bound. A2 says the same in neutral words ("neither adds it nor rules it out").

#### Moderator Notes and Reading Gaps

- No Phase A seat ran the probes. Five seats took the results from the brief. DevOps does not say.
- The probe in the original report uses a plain literal. Under the spec that is E0310. The spec form is `t"..."`. A plain literal is out of scope here.
- gen1 lags the spec: it does not parse `t"..."` and has no `values()`. The examples in the spec text cannot be checked with `blink check` yet.
- Minimalism's first reply wrote `x.to_str()` under `T: Display`. `Display` has `display()` and no `to_str`. Phase B stated this as a fact.
- Web read only part of the other five Phase A files in Phase B and in Phase C, and says so in its files.
- The first writes of web and devops in Phase B came out empty and were rewritten.
- Phase D ran on Q2 and Q3 only. D1 reused the Phase C seats. D2 used fresh seats.
- The owner's dashboard ruling and the panel files agree. No difference was found.
