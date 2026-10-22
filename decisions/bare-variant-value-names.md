[< All Decisions](../DECISIONS.md)

# Bare Variant and Value Names — Design Rationale

§2.12.1 gave module scope a value namespace (`let`, `let mut`, `const`, `fn`) but did not say whether
a variant that a program can write bare (`Red`, `Leaf(1)`) binds a value name. On the current
compiler (gen1), measured before the panel met:

| Program (module scope + use in `main`) | Result |
|---|---|
| `type Color { Red, Green }` + `fn Red() -> Int { 1 }`; `let x = Red()` then `"{x}"` | typecheck types `x` as `Color` (error: Color has no Display): the variant wins at typecheck |
| same, but `fn Red() -> Int { 7 }` and `x.to_int()` | runs and prints `7`: codegen called the `fn`. Typecheck and codegen pick different winners |
| `type Color { Red, Green }` + `fn Red()`; `let c = Red` | typecheck: `Color`; codegen emits a function value, and the C compiler fails (`_cg_fn_value1` undeclared) |
| `type Color { Red, Green }` + module `let Red = 5`; `"{Red}"` | prints `5`: the module `let` wins |
| `type Color { Red, Green }` + `const Red = 5`; `let c: Color = Red` | error: declared type Color but got Int: the `const` wins even against a `Color` hint |
| `type Wrap { Leaf(Int), Empty }` + `fn Leaf(n: Int) -> Int`; `let i: Int = Leaf(2)` | error: declared Int but got Wrap: the variant wins even against an `Int` hint; the `fn` is unreachable |
| `type Color { Red, Green }`; inside `main`: `let Red = 5`; `"{Red}"` | prints `5`: a local `let` hides the variant |

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Does a variant bind a name in the value namespace? | No. A variant lives in `T.`; the declaration error is a collision check, not namespace membership | 6-0 |
| Q2 | Code for the declaration-time collision | E1016 `DuplicateModuleBinding` | 6-0 |
| Q3 | Reach of the check (module-scope `let`/`let mut`/`const`/`fn` vs a variant) | Every enum in the same package | 6-0 (Systems, Web, Minimalism moved from module reach) |
| Q4 | Bare use where a module value and a variant outside the Q3 reach both exist | Scope order: local, then module value or import, then §3.4 (hint, then global-unique); the first step that finds the name decides; a hint never moves resolution past a binding; a type error at a hinted site gets help naming `T.V` | 6-0 |
| Q4w | Warning at a module-scope value that hides a variant outside the Q3 reach | W1011 `ShadowedVariant`, only when the module imports the variant's type | 5-1 (Minimalism: no warning) |
| Q5a | Module-scope value named like a prelude variant | E1016; the variants of a prelude enum count as declared in every module | 6-0 |
| Q5b | Local binding named like a prelude variant | Same rule as Q6 | 6-0 |
| Q5c | Which prelude names | Every variant of every prelude enum, stated by kind | 6-0 |
| Q6 | Local binding named like a variant | Legal, W1011; reach: same-package, prelude, and imported-type variants; a pattern binder warns only when the scrutinee type has no variant of that name | 6-0 in Phase D, after 3-3 in Phase C (Systems, PLT, Minimalism moved) |
| Q7 | Patterns | A bare name in a pattern is a variant only when the scrutinee type has that variant; otherwise a new binding; the global-unique search never runs in a pattern; no value binding changes a pattern | 6-0 (PLT, Systems, DevOps, Web moved from the §3.4-resolution wording) |
| Q8 | "One resolution" invariant | One sentence in §2/§3, with no list of phases; a §6 sentence for `blink query` and the language server | 5-1 (Minimalism: implementation note) |

The user approved the tally. The moderator stated, and the user accepted, two readings of the votes:
an import of the whole module (`import pal`) does not count as importing the type for W1011, only an
import entry that names the type; and `@allow(ShadowedVariant)` goes on the enclosing `fn`, as for
other warnings.

Out of scope, filed as separate tickets: the typecheck/codegen split and the `_cg_fn_value1` C error;
narrowing the program-wide reach of struct-vs-variant `NameCollision`; a sum `type Red` and a variant
`Red` of another type; a misspelled variant in a pattern (`Gren =>`) that becomes a catch-all binding.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The text below is each panelist's own, in full.
Headings inside a panelist's text are shown in bold, and each text's title line is left out.

#### Phase A — Independent proposals

##### Systems

**What the hardware sees today**

The table in the brief shows a miscompile, not only a spec gap. For `type Color { Red }` + `fn Red() -> Int { 7 }`, typecheck types `Red()` as `Color` and codegen emits a call to the `fn`. The program runs and prints `7` through a value that the type system calls `Color`. For `let c = Red`, codegen emits a function value that does not exist, and the C compile fails. Two stages that resolve one name two ways is the worst result for a systems language: the type that the checker proves is not the type that the machine gets.

So my first requirement is for every proposal: **a bare name resolves once, statically, to one entity, and every later stage uses that entity.** Whatever rule we pick, a bare variant use must emit the same code as the qualified form (§3.4 already says this). No runtime lookup, no runtime tag check, no new indirection.

Two more facts I measured (gen1, main at 1ea8e0ca):

- In pattern position, a bare `Red` with a `Color` scrutinee is the variant, even when `fn Red` or a local `let Red = 5` exists. Pattern resolution already goes through the scrutinee type. That part is correct and I keep it.
- `let x = Red` then `let Red = 5` in one function: `x` is `Color.Red`, later `Red` is `5`. Local shadowing works in sequence.

---

**Proposal A (preferred): variants bind no module value name; a clash is an error at the earliest point that can see both**

**Rule (spec-ready text, for §2.12.1 and §3.4)**

> **Enum variants and the value namespace.** An enum variant does not bind a name in the value namespace of any module. The bare name of a variant resolves only by the rules of §3.4 *Variant Construction* (hint-directed, then global-unique) and, in a pattern, through the type of the scrutinee (§3.5).
>
> **Declaration-time clash.** In the module that declares a type `T`, a `let`, `let mut`, `const` or `fn` whose name is equal to the name of a variant of `T` is `DuplicateModuleBinding` (E1016). The primary span is on the value declaration. A label marks the variant. The prelude variants `Ok`, `Err`, `Some` and `None` count as declared in every module, so a module-scope value declaration of one of these names is E1016 in every module.
>
> **Use-site clash.** In an expression, a bare name `V` that names a module-scope value (a declaration or an import entry of the current module) and that also resolves to a variant by any rule of §3.4 is `AmbiguousBareName` (new code). The hint does not break the tie. The fix is to qualify the variant (`T.V`) or to rename the value or its import (`import m.{V as v2}`). This rule applies only at a site; the declarations stay legal.
>
> **Local bindings.** A function-local binding (a `let`, a parameter, a pattern binding) with the name of a variant hides the variant in expressions in its scope, by the nested-scope rule (§2.2, §10.6). It does not change a pattern: in a pattern, a bare variant name whose scrutinee type has that variant is always the variant.

**Example**

```blink
type Color { Red, Green }

fn Red() -> Int { 1 }      // error[E1016]

fn main() {
    let c = Red
}
```

```
error[E1016]: `Red` is declared twice in module `main`
 --> src/main.bl:3:4
  |
1 | type Color { Red, Green }
  |              --- variant `Color.Red` declared here
2 |
3 | fn Red() -> Int { 1 }
  |    ^^^ value declared here with the same name
  |
  = help: rename the function, or rename the variant
```

Cross-module case, where the declaration site cannot see the clash:

```blink
@module("paint")
pub type Color { Red, Green }
```

```blink
@module("main")
import paint.{Color}

const Red = 5

fn main() {
    let a: Color = Red           // error[AmbiguousBareName]
    let b: Color = Color.Red     // OK
    let n = Red                  // error[AmbiguousBareName]
}
```

```
error[AmbiguousBareName]: `Red` names both the constant `main.Red` and the variant `paint.Color.Red`
 --> src/main.bl:7:20
  |
4 | const Red = 5
  |       --- constant declared here
...
7 |     let a: Color = Red
  |                    ^^^ ambiguous bare name
  |
  = help: write `Color.Red` for the variant, or rename the constant
```

Local shadowing stays legal:

```blink
type Color { Red, Green }

fn main() {
    let x = Red          // Color.Red
    let Red = 5          // local hides the variant in expressions below
    let y = Red + 1      // Int
    let s = match x {
        Red => "red"     // still the variant: the scrutinee is Color
        Green => "green"
    }
}
```

**Tradeoffs (systems view)**

- **Codegen cost: zero.** Resolution is static. A bare variant, after resolution, is the same tag constant or the same constructor call as `T.V`. Nothing reaches the runtime.
- **Compile cost: small and bounded.** The declaration check is one set test per value declaration against the variant names of types in the same module. The use-site check is one extra lookup for each bare name that already hits the program-wide variant table, which §3.4 global-unique resolution needs anyway.
- **Kills the miscompile at the root.** No pair of entities can both be live under one bare name at a site, so no later stage can pick a different one. The typecheck/codegen split in the brief cannot happen.
- **Locality.** The declaration rule fires where both names are in one file. The use-site rule fires only where the reader sees the bare name. A new variant in a distant module can turn a working bare use into an error, but never into a different meaning. That matches the §3.4 principle: "No path ever silently picks a winner."
- **Cost to users.** `fn Some()`, `const None` and similar become errors. I accept this. A value named like a prelude variant is a trap for every reader and every model that writes Blink.
- **The hint does not break the tie on purpose.** If the hint broke the tie, `let a: Color = Red` would compile and `let n = Red` would not, and adding an annotation would change which entity a name means. That is a silent change of meaning by a type annotation. I prefer one rule: a bare name that has two candidates in two kinds is an error.

**Cross-language note**

- Rust: unit and tuple variants live in the value namespace only after `use Color::*`. Then `fn Red` and the glob import conflict (E0255 for an explicit import; a glob is shadowed by a local item, which is a known source of bugs, for example a match arm `Red =>` that becomes a catch-all binding). Blink must not copy that silent case.
- OCaml and Haskell: constructors have their own namespace, and the lexer splits them by case. Blink has no case rule (PascalCase is a convention only, §2 naming table), so Blink needs a diagnostic in place of a lexical rule.
- Swift: `.red` with a leading dot is always hint-directed, so no clash exists. Blink chose bare names, so Blink must pay with a clash rule.

---

**Proposal B (alternative): a variant binds a value name in its declaring module**

**Rule**

> A variant `V` of a type `T` declared in module `M` binds `V` in the value namespace of `M`. A `let`, `let mut`, `const` or `fn` named `V` in `M` is E1016 (two declarations in one namespace). An import of `T` does not bind its variants; in other modules the bare variant resolves only by §3.4.

**Example**

```blink
type Color { Red, Green }
fn Red() -> Int { 1 }    // error[E1016]: `Red` is declared twice in module `main`
```

**Tradeoffs**

- It reuses E1016 and the §2.12.1 text with no new code. Simple to implement: add variants to the module value map.
- But it is not the whole answer. The variant is still global-unique program-wide by §3.4, so a `const Red` in another module that imports `Color` still has two candidates for a bare `Red`. B needs the use-site rule of A anyway, or it leaves that case with a silent winner.
- It also states that a variant is a module value in one module and not in others. That is two models for one entity. Proposal A has one model: a variant is never a module value; only a clash is an error.

---

**Proposal C (rejected): fixed priority, value beats variant**

> A module-scope value always wins over a variant for a bare name. Write `T.V` to get the variant.

This is today's behavior for `let` and `const`. It is deterministic and costs nothing at runtime. I reject it because it is a silent winner: `const Red = 5` in a module makes `let c: Color = Red` a type error with a confusing message, and a new `fn` can change the meaning of an existing bare use. It violates the §3.4 rule that no path silently picks a winner.

---

**Notes for the panel**

- Whatever wins, the conformance tests must include the `fn` case with a payload (`fn Leaf(n: Int)` + `Leaf(2)`) and the function-value case (`let c = Red`). These two expose the typecheck/codegen split today.
- Interaction with tzrpfj: Proposal A does not depend on how that audit ends. It treats bare and qualified variant spellings as equal, as §3.4 already does.
- Code number: I propose a new code for `AmbiguousBareName`; the moderator can map it to the catalog. If the panel prefers, it can be a second form of `AmbiguousConstruction`, but the message must name both kinds (value and variant), because the fix differs.

**Preference: Proposal A.**

##### Web/Scripting

**My lens**

A JS, TS, Python or Kotlin developer never writes a bare enum member. TS `Color.Red`, Python `Color.RED`, Kotlin `Color.RED` — always qualified. So bare `Red` is already the surprising part of Blink for my users. When bare `Red` also silently means a function in one layer and a variant in another (measured: typecheck picks the variant, codegen calls the `fn`), that is the worst result: the program compiles and does the wrong thing. Anything is better than that. My rule of thumb: the 90% case is "one file, one enum, one helper fn that I named like a variant by mistake". That case must be a clear error at the declaration, and the message must teach `Color.Red`.

**Extra facts I measured (gen1 at 1ea8e0ca)**

| Program | Result |
|---|---|
| package `x`; module `colors` has `pub type Color { Red, Green }`; module `x` has only `import colors`; `let c = Red` | runs, prints `0` — bare `Red` reaches a variant of a type the module never imported by name. Global-unique really is program-wide |
| same, but module `x` has `import colors.{Color}`, `fn Red() -> Int { 7 }`, `let c: Color = Red` | C compile error (`_cg_fn_value1` undeclared) — the cross-module case has the same typecheck/codegen split |
| `fn Some() -> Int { 3 }`; `let x = Some()` | `x` typed `Option[?]` — the prelude variant beats the user `fn`; the `fn` is unreachable |
| `fn Less() -> Int { 4 }`; `let x: Int = Less()` | error: declared Int but got Ordering — prelude variant beats the user `fn` even against an `Int` hint |
| `type Wrap { Leaf(Int), Empty }`; `let f = Leaf`; `f(2)` | error: `f` has type Wrap, which is not a function |

**Proposal 1 (preferred): error in the declaring module, scope order everywhere else**

**Rule (spec-ready text, for §2.12.1 after the namespace paragraph)**

> **Variant names and value names.** A variant name of an enum that module M declares must differ from the name of every `let`, `let mut`, `const` and `fn` that M declares. A clash is `DuplicateModuleBinding` (E1016), with the same shape as any other E1016: the primary span is on the later of the two in source order, and a label marks the first. When the variant is the first, the label is on the variant name inside the `type` body. Two variants of one name in two enums do not clash: §3.4 *Variant Construction* resolves them. An import entry that binds a value name equal to a variant name of M is `DuplicateSymbol` (E1012), as for any import against a declaration.
>
> This check does not make a variant a member of the value namespace. A variant is reached only through §3.4 resolution (qualified, hint, global-unique), never through the module's name table.

> **Bare names in other modules.** In a module that does not declare the enum, a bare name resolves by nested scope (§2.2, §10.6), inner first:
> 1. a function-local binding;
> 2. a module-scope value binding of this module: a `let`, `let mut`, `const` or `fn` that it declares, or a name that it imports;
> 3. §3.4 variant resolution: hint, then global-unique.
>
> The first step that finds the name decides. So a variant that another module declares can never change what a bare name means in a module that declares or imports a value of that name. If step 2 decides and the site has a hint that names an enum with a variant of that name, the type error carries a help line that names the qualified variant.

> **Patterns.** A bare variant pattern (`Red =>`, `NotFound { msg } =>`) resolves through the scrutinee type only. It never looks in the value namespace, so this rule does not change any pattern.

> **Function-local shadowing.** A function-local `let Red = 5` hides the variant `Red` for the rest of its scope. This is legal shadowing between nested scopes (§2.2). Write `Color.Red` to reach the variant.

**Example — same module (the 90% case)**

```blink
type Color {
    Red
    Green
}

fn Red() -> Int { 1 }

fn main() {
    let x = Red()
}
```

```
error[E1016]: `Red` is declared twice in module `main`
 --> src/main.bl:6:4
  |
2 |     Red
  |     --- first declared here, as a variant of `Color`
...
6 | fn Red() -> Int { 1 }
  |    ^^^ declared again here
  |
  = help: rename the function, or rename the variant. A bare `Red` must name one thing in this module
```

Same for `const Red = 5` and module `let Red = 5`. All four of the measured same-module rows (`fn`, `let`, `const`, `fn` with payload variant) become this one error. No winner, no split between typecheck and codegen.

**Example — another module**

```blink
// src/colors.bl
@module("colors")
pub type Color {
    Red
    Green
}

// src/x.bl
@module("x")
import colors.{Color}

fn Red() -> Int { 7 }

fn main() {
    let n = Red()             // OK: step 2, calls x.Red
    let c: Color = Color.Red  // OK: qualified
    let d: Color = Red        // error: step 2 decides, then the type does not match
}
```

```
error[TypeError]: variable `d`: declared type Color but got fn() -> Int
 --> src/x.bl:10:20
   |
10 |     let d: Color = Red
   |                    ^^^ `Red` is the function `x.Red` declared in this module
   |
   = help: to build the variant, write `Color.Red`
```

**Tradeoffs (my domain)**

- The common mistake gets a clear error at the line the developer just wrote. One code (E1016) they already know from `fn f` + `fn f`.
- The cross-module rule is the one every JS/Python dev already has in their head: "my own names win over names from somewhere else". It also keeps the §3.4 promise: a distant enum can never change what a site means. A dependency that adds a variant `Red` does not break or change a module that has its own `fn Red`.
- Cost: a cross-module hint site (`let d: Color = Red`) gives a type error, not the variant. I accept that. The alternative (hint beats your own function) means one bare name reads two ways in one file depending on the left side. That generates Stack Overflow questions. The help line makes the fix one edit.
- Cost: step 2 is a winner by scope. It is not a winner between peers, so "no path silently picks a winner" still holds in the sense §3.4 meant: peers in one scope always error.
- Scope of the declaration check is the declaring module only. That matches §2.12.1 (module scope). I do not want it program-wide (Proposal 2) because then a dependency release breaks a downstream build.

**Cross-language notes**

TS, Python, Kotlin: enum members always need the type qualifier, so the clash cannot occur. Haskell: constructors and functions live in different namespaces by case (capital vs lower), so no clash either; Blink has no such case rule, so it needs this one. Rust: a unit or tuple variant brought in with `use Color::*` and a local `fn Red` in one module is a "defined multiple times" error, I believe; local items winning over glob imports is also Rust behavior (verify both before the record quotes them).

**Proposal 2: program-wide declaration error (the struct-vs-variant model)**

**Rule**

> A `let`, `let mut`, `const` or `fn` with the name of any enum variant anywhere in the program is `NameCollision`, reported at declaration time, as for a struct named like a variant (§3.4).

**Example**

```blink
// in a dependency
pub type Ordering2 { Before, After }

// in your module
fn Before() -> Int { 1 }   // error[NameCollision]: `Before` is a variant of `Ordering2` (in package `dep`)
```

**Tradeoffs**

Simple to explain: "a value can never have a variant's name". But it is fragile: a dependency adds a variant in a minor release and your build breaks on a function you wrote two years ago. It also bans helper names like `fn Empty()` program-wide if any enum anywhere has `Empty`. Too much blast radius for the 10% case. I do not prefer it.

**Proposal 3 (rejected, listed for completeness): variants are never values; the module binding always wins**

This is the PLT Phase A remark from the earlier panel taken to its end. In-module `type Color { Red }` + `fn Red()` compiles, and bare `Red` always means the `fn`. It fixes the typecheck/codegen split. But the one-file case reads two ways with no warning: the developer sees `Red` in the `type` body three lines up and gets a function. That is the silent winner §3.4 forbids. Reject.

**Sub-question: prelude variants (`Ok`, `Err`, `Some`, `None`, `Less`, `Equal`, `Greater`)**

Measured: a module `fn Some()` or `fn Less()` is accepted, and the prelude variant wins every use, even against an `Int` hint. The `fn` is unreachable and nothing says so. Under plain nested scope (prelude under module) the user `fn Some` would instead hide `Some` in the whole module and break every `Option` build. Both are bad. I propose: a module-scope `let`, `let mut`, `const` or `fn` named like a prelude variant is an error (`NameCollision`, "`Some` is a prelude variant of `Option`; a value cannot use its name"). These names carry the §3.4 hint machinery, so they must mean one thing everywhere. A function-local `let Some = 1` stays a legal shadow. I flag this for a vote; it is not part of Proposal 1's core.

**Out of scope (note for the moderator)**

A bare variant is not a function value today: `let f = Leaf` gives "`f` has type Wrap, which is not a function", and `let c: Color = Red` with a `fn Red` in scope gives the C error `_cg_fn_value1`. Proposal 1 does not make a variant a function value. The C error is a separate codegen bug and should get its own ticket.

*Later note:* the ruling *Payload variants as fn values* ([variant-fn-value.md](variant-fn-value.md)) closes this item. A variant with a positional payload, named with no argument list, is now a function value.

**Preference**

Proposal 1. Then the prelude sub-question as error.

##### PLT

**Framing**

The ticket asks "does a variant bind a module-scope value name?" The answer must be no. Two decided rules forbid it:

- Decision 2: `Pending` in `JobState` and `Pending` in `NetState` is legal, also in one module. If a variant bound a value name, those two would be E1016.
- Decision 4: the home of a variant is the `T.` namespace (§2.12.3), not the module value map.

So the real question is different. A bare variant spelling and a value-namespace name are two *resolution systems* for one token. Value names resolve lexically (scope chain). Bare variants resolve by type and by a program-wide search (§3.4). When both systems give an answer for one token, the language must say what happens. Today it says nothing, and the compiler disagrees with itself (typecheck picks the variant, codegen calls the `fn`). That is a soundness defect: the static type of `Red()` is `Color`, the run-time value is an `Int`.

Two facts I measured on gen1 (in addition to the brief):

1. Pattern kind is not lexical. `type Color { red, green }` with arm `red =>` matches the variant. Arm `Zed =>` on an `Int` binds a new name. The grammar words `TYPE_NAME` and `IDENT` in §3.5 are not a casing rule; the compiler decides by resolution. So the OCaml/Haskell answer (constructors and variables are disjoint by case) is not available to Blink.
2. A local `let Red = 5` does not change `Red =>` in a pattern: the arm still matches `Color.Red`. Expression `Red` reads the local.

Existing codes: `NameCollision` is E0518 (struct vs variant). `AmbiguousConstruction` is E0519.

**The principle I build on**

Decision 5 says: shadowing happens only between nested scopes; two module-scope meanings of one name are a duplicate, never a shadow. A bare variant is ambient at module level: no scope contains it, and no import is needed to spell it. So a module-scope value `Red` and a bare variant `Red` are at the same level. They cannot shadow each other. They can only collide. A function-local `Red` is in a nested scope, so it shadows. Everything below follows from this one rule.

---

**Proposal P1 (PREFERRED) — collide at the declaration in one module, ambiguity at the use across modules**

**Rule (spec-ready text, for §2.12.1 and §3.4)**

> **Variants and the value namespace.** An enum variant does not bind a name in the value namespace of its module. Its home is the `T.` namespace of its type (§2.12.3). The bare spelling of a variant (`Red`, `Leaf(1)`, `NotFound { msg: "x" }`) is a short form of the qualified spelling, resolved by §3.4.
>
> A module-scope value declaration (`let`, `let mut`, `const`, `fn`) must not have the same name as a variant of an enum that the same module declares. The compiler reports `DuplicateModuleBinding` (E1016) with the shape of §2.12.1: the primary span is on the later of the two in source order, a label marks the first, the fix is a suggestion only. An import entry that binds such a name in that module is `DuplicateSymbol` (E1012).
>
> In a module that does not declare the enum, a bare name in expression position can have two meanings: a module-scope value binding (declared or imported) and a variant, of an enum in the same package, that §3.4 finds. When both exist, the use is `AmbiguousConstruction` (E0519). The expected type does not choose between a value and a variant. The fix is to qualify the variant (`Color.Red`), or to rename the value or reach it through a module qualifier. This rule does not change the §3.4 candidate set: a variant is a candidate whether or not the module imports its type.
>
> **Scopes under the module.** The prelude and dependency packages are scopes under module scope (§10.6). A variant from the prelude (`Ok`, `Err`, `Some`, `None`) or from a dependency package is in such a scope. A module-scope value of the same name shadows it in that module, with no error. For a prelude variant the compiler reports `W1010`, as for a type that shadows a builtin type. Every diagnostic whose subject is the shadowing name adds a `note:` that names the hidden variant and its qualified spelling (§10.6 item 2).
>
> A function-local binding (a `let`, a parameter, a pattern binding) is in a nested scope. It hides a bare variant in the expression positions of its scope, as it hides a module-scope name (§2.2). It has no effect on patterns.
>
> **Patterns never read the value namespace.** A bare name in a pattern is a variant when §3.4 resolves it (the scrutinee type is the hint), else a new binding. A `let`, `const` or `fn` of that name, at any scope, does not change the meaning of the pattern.

**Example: same module (the ticket MVCE)**

```blink
type Color { Red, Green }

fn Red() -> Int { 1 }      // error[E1016]

fn main() {
    let _ = Red()
}
```

```
error[E1016]: `Red` is declared twice in module `main`
 --> src/main.bl:3:4
  |
1 | type Color { Red, Green }
  |              --- first declared here, as a variant of `Color`
2 |
3 | fn Red() -> Int { 1 }
  |    ^^^ declared again here, as a function
  |
  = help: rename the function, or rename the variant
```

The fact-table row `const Red = 5` + `let c: Color = Red` is E1016 at the `const`. The use site is never reached, so the question "does the `Color` hint win?" does not come up. The same holds for `type Wrap { Leaf(Int), Empty }` + `fn Leaf`, and for `fn Red` + `let c = Red` (today a C compile error).

**Example: across modules**

```blink
// file: paint.bl
@module("paint")
pub type Color { Red, Green }
```

```blink
// file: main.bl
import paint.{Color}

const Red = 5

fn main() {
    let a = Red                 // error[E0519]
    let b: Color = Red          // error[E0519]: the hint does not choose
    let c = Color.Red           // OK
    let Red = "local"
    io.println(Red)             // OK: the local hides both
}
```

```
error[E0519]: `Red` has two meanings here
 --> src/main.bl:7:13
  |
4 | const Red = 5
  |       --- a constant in module `main`
  |
7 |     let a = Red
  |             ^^^ used here
  |
  = note: `Red` is also a variant of `Color` (module `paint`)
  = help: for the variant, write `Color.Red`
  = help: for the constant, rename it
```

**Local shadowing — defined, no warning**

`let Red = 5` in a function body is legal. In that scope, expression `Red` reads the local. Pattern `Red =>` still matches the variant. This is not an inconsistency. The dual pair in §3.4 is *construction and pattern*, not *expression and pattern*. A local value is never a pattern, because Blink patterns do not compare against values (only range bounds read consts, through their own syntax). So a pattern has only one candidate.

I recommend no warning for a local that hides a bare variant. The local is next to its uses. Decision 5 gives no warning for any other function-local shadow. A lint can add one later if friction shows a need.

**Tradeoffs (PLT)**

- **Sound.** Each bare token gets one meaning or one error. The static type and the run-time value always agree. No path picks a winner silently.
- **Compositional at the declaration.** The declaration check needs the text of one module. A new variant in another module of the same package never makes a *declaration* ill-formed. It can make an existing bare *use* an E0519 error. This is the same cost the panel already accepted for variant vs variant (adding `Pending` to `NetState` breaks unhinted `Pending` sites). Errors may appear from a distant change; silent rebinding never does. Across a package boundary the cost is zero: the local value shadows the dependency variant (see Interactions).
- **Why the module boundary, when E0518 is program-wide.** Struct names and variant names are both type-like and both reachable bare across the program, so a program-wide check is cheap and local in meaning. Value names are module-local: another module reaches them only through an import. A program-wide value-vs-variant check would make `fn Red` in module A ill-formed because module Z, which A never imports, declares `Red`. That breaks separate reasoning. So the declaration check stops at the module, and the use-site check covers the rest.
- **Why the hint does not choose between a value and a variant.** §3.4 uses the hint to choose among *constructors*. Letting it choose between a *value reference* and a constructor makes the meaning of a plain name depend on the expected type. With HM metavariables (gen1 has them), the expected type can be an unsolved metavariable at the site and be solved later. Resolution would then depend on the order of constraint solving. That is not a property a name lookup should have. Keep name lookup a function of the scope, and keep type direction inside the constructor set.
- **Cost.** One more case in the E0519 message, and a cross-namespace check in the module collision pass. No new code numbers.

**Cross-language note**

- OCaml and Haskell never meet this case: constructors are capitalized, values are not, so the lexer splits the namespaces. OCaml's type-directed disambiguation (4.01, warnings 40–42) works only among constructors. Blink has no casing rule (measured above), so it needs an explicit rule.
- Rust: `use Color::*;` plus `fn Red()` is E0255, a declaration-time clash in one module. P1 matches that for the declaring module. Rust's glob-import pattern trap (a misspelled variant binds a variable) is the hazard behind "patterns never read the value namespace".
- Swift avoids the clash by syntax: an implicit member needs a leading dot (`.red`).
- Koka puts constructors in the value namespace and resolves overloads by type. That is the model the hint rule above rejects for plain names.

---

**Proposal P2 — use-site only, no declaration rule**

**Rule**

> No declaration-time check. At each bare use where a module-scope value binding and a §3.4 variant both exist, the use is E0519, in the declaring module too.

**Example**

```blink
type Color { Red, Green }
fn Red() -> Int { 1 }          // OK under P2

fn main() {
    let a = Red()              // error[E0519]: `Red` has two meanings here
    let b = Color.Red          // OK
}
```

**Tradeoffs**

Simpler: one rule, one place. But in the declaring module the `fn Red` can never be called bare, and the bare variant can never be used. A declaration that no bare use can reach is a defect, and the author learns of it only at a use. Decision 1 already chose declaration-time errors for this shape of mistake in one module. P2 is a fallback if the panel rejects any new collision pair in §2.12.1.

---

**Proposal P3 — value binding hides the variant (REJECT, on record)**

**Rule**

> A module-scope value binding hides a bare variant of the same name. This is today's behavior for `let` and `const`.

**Why reject**

- It is a silent winner. §3.4 says "No path ever silently picks a winner." `const Red = 5` + `let c: Color = Red` gives "declared Color but got Int", with no pointer to the cause.
- It treats two module-level meanings as a shadow. Decision 5 says module-level pairs are a duplicate, never a shadow.
- The measured `fn` case shows the cost of an unwritten precedence: typecheck and codegen already chose different winners and produced a program whose static type is wrong.

**Proposal P4 — a variant binds a value name in its module (REJECT, on record)**

The Rust-like model: each variant enters the value namespace of its declaring module.

Reject: two enums in one module that share `Pending` would then be E1016, which contradicts decision 2. It also contradicts decision 4, which puts the variant in `T.`. P1 gets the useful part of this model (the in-module collision) without making the variant a value binding.

---

**Interactions**

- **§2.12.3 `T.` namespace.** `pub fn Color.Red()` against variant `Color.Red` is already E1016 (decision 4). P1 does not touch it.
- **Opaque enums.** Outside the declaring module, the variants of an opaque enum are hidden. A hidden variant is not a §3.4 candidate there, so it cannot make a use ambiguous. A value `Red` in another module is then the only meaning.
- **Prelude and dependency variants are the exception that fits the principle.** The principle is "a bare variant has no enclosing scope, so a module-level pair collides". A prelude variant and a dependency variant *do* have a scope, and decision 5 puts both under the module. So a module-scope `fn Some` shadows the prelude `Some` with W1010 (decision 6 already does this for types), and a module-scope `const Red` shadows a dependency's `Red`. E0519 applies only inside one package. Result: a new `pub` variant in a dependency can never break a downstream program. It can only change nothing (the local value already wins) or add a note to an error.
- **Why E1016 and not E0518 for the in-module pair.** Decision 4 already uses E1016 for a clash in the `T.` namespace, so E1016 already covers a clash across namespaces in one module. Decision 2 scopes E0518 to struct vs variant only; widening it would reopen that decision.
- **tzrpfj** (bare vs qualified audit): P1 keeps both spellings and adds a reason to prefer the qualified spelling when a value of the same name exists. It does not resolve tzrpfj.
- **Implementation note (not spec text).** The front end must record one resolution per bare-name site, and codegen must use that record. Today's typecheck/codegen split is a symptom of two separate lookups.

**Preference**

**P1.** It follows from decision 5 with no new idea: module-level meanings collide, nested meanings shadow. It keeps name lookup independent of types, it reuses E1016, E1012, E0519 and W1010, and it closes the soundness hole the measured `fn` case shows.

##### DevOps

**What I measured in addition to the brief**

All runs use gen1 from main at 1ea8e0ca. Scratch files are in `gt/devops/`.

| Program | Result |
|---|---|
| package; `src/pal.bl` has `pub type Color { Red, Green }`; `tests/main.bl` does `import pal` (whole module, no `Color` import) and `let c = Red` | runs, prints `0`. A bare variant reaches across modules with no import of its type. |
| same package; `main.bl` also declares `fn Red() -> Int { 7 }`; `let c = Red()` | prints `7`. The `fn` wins over a variant from another module, with no diagnostic. |
| `fn Some(n: Int) -> Int`, `let None = 3` at module scope; `Some(1)`, `"{None}"` | both resolve to the prelude variants (`Option[Int]`). The user `fn`/`let` is dead code, with no diagnostic. This is the opposite winner from user variants, where `let` wins. |
| `type Color { Red, Green }`; in `main`: `let Red = 5`, then `match Color.Green { Red => ..., _ => ... }` | prints `other`. In a pattern, `Red` is the variant even though a local `Red` is in scope. In an expression, `Red` is the local. |

So today one bare name can have four different meanings, and the winner changes with the kind of declaration, with the module, with prelude vs user, and with the compiler phase. For tooling, the worst fact is the phase split: the LSP reads typecheck results, so hover and go-to-definition on `Red()` point at the variant while the binary calls the `fn`. A tool that lies about what a name means is worse than a missing diagnostic.

**My test for every option**

1. Does one bare name at one site have exactly one meaning, which the LSP can show without running full type inference?
2. Does the error appear once, at the declaration, in a file the user owns, with both declarations shown?
3. Can a change in a dependency break a build that did not change? (Semver test.)
4. Does `blink fmt` stay out of name resolution?

---

**DV-1 (preferred): a variant is a value name. Same package = E1016. Other package = an outer scope with a warning.**

**Rule (spec-ready text, for §2.12.1, with a cross-reference from §3.4 *Variant Construction*)**

> **Variants in the value namespace.** A variant of an enum that a package declares binds its bare name in the value namespace of every module of that package. Thus a `let`, `let mut`, `const` or `fn` with the name of such a variant is `DuplicateModuleBinding` (E1016). The check covers the whole package, because a bare variant resolves across modules (§3.4, *Global-unique*). It uses the same diagnostic shape as other E1016 pairs: the primary span is on the value declaration, a label marks the variant, the fix is a suggestion only, and the program does not compile. A variant that is not visible outside its module (the type is not `pub`, or it is `pub opaque`) binds its name only in its own module.
>
> Two variants of one name in different enums do not collide. §3.4 resolves them by the hint, or reports `AmbiguousConstruction` (E0519).
>
> **Variants of another package.** A `pub` variant from another package is in an outer scope, under module scope. A module-scope value declaration of the same name hides it in that module, and the compiler emits `ShadowedVariant` (W1011) once, at the declaration. The qualified form `Color.Red` still names the variant. A dependency that adds a variant never stops a dependent package from compiling.
>
> **Prelude variants.** `Ok`, `Err`, `Some` and `None` are reserved in the value namespace. A module-scope or local value binding of one of these names is `ReservedValueName` (E1017).
>
> **Local bindings.** A local binding (`let`, a parameter, a closure parameter, or a pattern binding) may hide a variant. This is a shadow between nested scopes (§2.2), so it is legal. The compiler emits W1011 at the binding.
>
> **Patterns.** In a pattern, a bare name that names a visible variant always means the variant, also when a value binding of that name is in scope. A pattern never reads a value binding.
>
> **Value position.** In an expression, a bare name resolves in this order: (1) local bindings, inner to outer; (2) module-scope value bindings, including imports; (3) variants, by the §3.4 rules (hint-directed, then global-unique). The first step that finds the name gives the meaning. The type hint does not move a name past a binding that it finds in an earlier step.
>
> **One resolution.** Every compiler phase and every tool (typecheck, code generation, `blink query`, the LSP) uses one result for a bare name at a site.

**Example**

```blink
type Color { Red, Green }

fn Red() -> Int { 1 }      // error[E1016]

fn main() {
    let _ = Red()
}
```

```
error[E1016]: `Red` is declared twice in module `main`
 --> src/main.bl:3:4
  |
1 | type Color { Red, Green }
  |              --- `Red` is a variant of `Color`; a variant binds its name as a value
  |
3 | fn Red() -> Int { 1 }
  |    ^^^ declared again here, as a function
  |
  = help: rename the function, or rename the variant
```

Across modules in one package (the variant is in `src/pal.bl`, the function in `src/main.bl`), the message names the module of the variant:

```
error[E1016]: `Red` is both a variant of `pal.Color` and a function in module `main`
 --> src/main.bl:3:4
  |
3 | fn Red() -> Int { 1 }
  |    ^^^ function declared here
  |
 ::: src/pal.bl:2:20
  |
2 | pub type Color { Red, Green }
  |                  --- variant declared here
  |
  = note: a bare `Red` resolves to a variant in every module of the package
  = help: rename the function, or rename the variant
```

Another package (`pkg.palette` declares `pub type Color { Red, Green }`):

```blink
import pkg.palette.{Color}

let Red = 5                  // warning[W1011]

fn main() {
    let c: Color = Red       // error[TypeError], with a note
}
```

```
warning[W1011]: `Red` hides variant `Color.Red` from package `palette`
 --> src/main.bl:3:5
  |
3 | let Red = 5
  |     ^^^ a bare `Red` in this module now means this binding
  |
  = help: rename the binding, or write `Color.Red` where you mean the variant

error[TypeError]: declared type Color but got Int
 --> src/main.bl:6:20
  |
6 |     let c: Color = Red
  |                    ^^^ `Red` is the `let` at line 3
  |
  = note: the `let` hides variant `Color.Red`
  = help: write `Color.Red`
```

Local hiding and patterns:

```blink
type Color { Red, Green }

fn main() {
    let Red = 5              // warning[W1011]: `Red` hides variant `Color.Red`
    match Color.Green {
        Red => io.println("red")     // the variant, not the local
        _ => io.println("other")
    }
}
```

Prelude:

```blink
fn Some(n: Int) -> Int { n }   // error[E1017]: `Some` is a reserved value name (prelude variant of `Option`)
```

**Tradeoffs (tooling)**

- **One answer for the LSP.** Steps (1)-(3) are a lexical walk. Hover and go-to-definition on a bare name do not need the inferred type, except inside step (3), where §3.4 already needs it. Today the LSP and codegen disagree. "One resolution" makes that a spec violation that a test can catch: a corpus test with `fn Red` + variant `Red` must be E1016, not a run.
- **The error lands where the fix is.** In one package the author owns both declarations, so E1016 at declaration time is right, and it follows §2.12.3, where the `T.` namespace check is also package-wide. It follows E0518 (struct vs variant), which is a declaration-time error too.
- **Semver stays safe.** If E1016 were program-wide, a dependency that adds a variant in a minor release would break a downstream `fn` of that name. That error would point into a file the user does not own. W1011 keeps the build green and still tells the user. This is the same split as §2.12.3 (package-wide E1016, cross-package E0522) and as W1000 (dependency under local module).
- **No silent winner.** Every hidden variant gets W1011 at the hiding binding. A type error at a hidden site gets a note that names the hidden variant. Nothing changes meaning without a diagnostic.
- **Hint does not override a binding.** If the hint could move past a binding, hover would need type inference to know what `Red` is, and adding an annotation would change which declaration a name means. That is the same "a distant edit changes meaning" problem that §3.4 rejected.
- **Prelude variants reserved.** Today `fn Some` is silently dead. `Some`/`None`/`Ok`/`Err` carry `?`, `??`, and the carrier hint of §3.4. If a module could shadow them, every carrier example in the spec would need a "unless shadowed" note. An error costs nothing real: no one needs a function named `Some`.
- **Local W1011.** The pattern-vs-expression split (`Red` is the local in `x == Red` and the variant in `Red =>`) is a known trap. Rust has `bindings_with_variant_name` (deny by default) for the other side of it. A warning at the local binding is cheap and fires once. `@allow(ShadowedVariant)` on the `fn` suppresses it.
- **Cost.** One new warning code (W1011) and one new error code (E1017). E1016 gets one more pair kind. The package-wide check reuses the variant table that E0518 already reads program-wide.
- **`blink fmt`:** no change. It never rewrites `Red` to `Color.Red` or back (as §3.4 already says). The help lines above are suggestions only (§8.6), because they change which declaration a name means.
- **LSP completion:** at a bare value position, when a binding hides a variant, completion offers the binding as `Red` and the variant as `Color.Red`. It never inserts a bare name that means something other than the item the user picked.

**Cross-language note**

- Rust: unit and tuple variants are values only when you `use` them into scope; `use Color::*` plus `fn Red` is E0255 (name defined twice). With a unit variant `Red` in scope, `let Red = 5` reads `Red` as a pattern, not a new binding, so it is an error. A match arm that binds a name equal to a variant is the `bindings_with_variant_name` lint. DV-1 is close to Rust inside a package.
- Haskell: constructors live in their own namespace (uppercase), so `fn Red` cannot exist. Blink has no case rule, so it needs an explicit rule.
- Swift: `.red` needs a leading dot unless the type is known; it avoids the clash by syntax. Blink chose bare names (§3.4), so it must pay with a namespace rule.

---

**DV-2 (alternative): program-wide E1016, mirroring E0518 exactly**

**Rule**

> A visible variant binds its bare name in the value namespace of every module of the program. A module-scope value declaration with the name of any visible variant anywhere in the program is E1016. Local bindings may hide a variant (W1011). Prelude variants are reserved (E1017).

**Example**

```blink
import pkg.palette.{Color}

fn Red() -> Int { 1 }   // error[E1016]: `Red` is both a variant of `palette.Color` and a function in module `main`
```

**Tradeoffs**

- Simplest rule: one tier, the same scope as E0518.
- Fails my semver test. A dependency that adds a `pub` variant breaks every dependent package with a `fn` or `let` of that name. The primary span is in the user's file, but the cause is in a dependency, and the user cannot fix it there. The only fix is to rename their own function.
- E0518 already has this problem for struct vs variant. If the panel picks DV-2, consistency is a fair reason. If it picks DV-1, a follow-up ticket should ask whether E0518 needs the same package split.

---

**DV-3 (rejected, listed so the panel can see why): use-site ambiguity error**

> A bare name that matches both a value binding and a variant, with no hint, is an error at the use site.

- A module `fn Red` has no other spelling (there is no `self.Red`), so a bare use of it is always an error. The function becomes unreachable, so the real fix is still to rename it. The error just comes later and many times.
- N uses give N diagnostics, at the use sites, not at the declaration that caused them.
- The LSP cannot show what `Red` means until full inference runs.

---

**Preference**

**DV-1.** It gives one meaning per site that a lexical walk can find, puts the error at the declaration in the package that owns both names, follows the §2.12.3 package/cross-package split and the W1000/W1010 "inner scope wins with a warning" pattern, and does not let a dependency's new variant break a build. DV-2 is my second choice if the panel puts consistency with E0518 first.

**Interactions to note (not resolved here)**

- **tzrpfj** (bare vs qualified audit): DV-1 does not change which spellings are legal. It only fixes what a bare name means when a value binding has the same name.
- **E0518 scope:** if DV-1 wins, E0518 (struct vs variant, program-wide) has the same semver exposure that DV-1 avoids for values. That question belongs in a separate ticket.
- **Implementation:** the "one resolution" rule needs typecheck and codegen to read one resolved-name table. Today codegen re-resolves `Red()` on its own, which is how the `fn` wins at run time. This is the bug that the corpus tests for this ticket must catch.

##### AI/ML

**Two extra measurements (gen1 from main at 1ea8e0ca)**

The brief measures only expression sites. The pattern side matters to me, because a pattern is where one token can change meaning with no visible sign.

| Program | Result |
|---|---|
| `type Color { Red, Green }`; in `main`: `let Red = 5`, then `match c { Red => 1  Green => 2 }` and `"{Red}"` | prints `2 5`. In the pattern, `Red` is the variant. In the expression `{Red}`, `Red` is the local `5`. One token, two meanings in one function. |
| `type Color { Red, Green }` + module `fn Red() -> Int`; same `match` | prints `2`. The pattern `Red` is the variant; the `fn` is not seen. |
| `type Color { Red, Green }`; `match c { red => 1  Green => 2 }` | `red` binds the value (catch-all). Only spelling separates a variant from a binding. |

So patterns already resolve a bare name against the scrutinee's variants first. Expressions do not. The two sites disagree today.

**What the model must learn, and why I care**

An AI writes `Red` or `Red()` and must know what it means from the spec text alone. Today the answer depends on the kind of the other declaration (`let`/`const` win, `fn` loses at typecheck, `fn` wins at codegen), on the site (pattern or expression), and on nothing the model can see at the site. That is three hidden decision points for one identifier. No training data can teach it, because no other language has this table.

OCaml and Haskell have zero decision points here: case is lexical. A capitalized name is a constructor, a lowercase name is a value. Blink has no casing rule for values (§2.2 states PascalCase only for types). So Blink must get the same result by rule instead of by lexeme: **a bare name is a variant or a value, never both.** Decision 2 already says this for structs ("a name is either a product type or a sum injection — never both"). I want to widen that sentence, not add a new idea.

---

**Proposal 1 (preferred): widen NameCollision (E0518) to value declarations**

**Rule (spec-ready, for §3.4 *Variant Construction*, "Name collisions")**

> **A variant does not bind a module-scope value name.** The home of a variant is `T.Variant` (§2.12.3). A bare spelling (`Red`, `Leaf(1)`, `NotFound { ... }`) is a short way to write it, and §3.4 resolves it. It is never an entry in the value namespace of §2.12.1.
>
> **A bare name is either a variant or a value, never both.** A module-level `fn`, `let`, `let mut` or `const` whose name is equal to the name of an enum variant is a compile error at the declaration, `NameCollision` (E0518). The scope of the check is the same as for a struct name equal to a variant name: the whole program. The prelude variants `Ok`, `Err`, `Some` and `None` are included.
>
> **A bare use resolves by §3.4, unchanged.** Because no module-level value can share a variant's name, a bare name in an expression has only one candidate kind. If a function-local binding of that name is in scope, the local is used (§2.2 shadowing). Otherwise §3.4 applies: qualified, then hint, then global-unique.
>
> **Patterns.** In a pattern, a bare name that is a variant of the scrutinee type matches that variant. A local binding never changes this.
>
> **Local bindings named like a variant.** A function-local `let`, parameter, or `for` binding whose name is equal to a variant name of a type in scope is legal (§2.2), but it gets warning `LocalHidesVariant` (W-code new). After that binding, `Red` in an expression means the local, and `Red` in a pattern still means the variant.

Pairs covered, one code for all four: `fn`+variant, `let`+variant, `let mut`+variant, `const`+variant. `type`+variant stays E0518 (struct) or legal (a sum type named like a variant of another sum? see open question 3).

**Example**

```blink
type Color { Red, Green }

fn Red() -> Int { 1 }        // error[E0518]
const Green = 5              // error[E0518]

fn main() {
    let c: Color = Red       // the variant; no other candidate exists
}
```

```
error[E0518]: `Red` is both a function and a variant of `Color`
 --> src/main.bl:3:4
  |
1 | type Color { Red, Green }
  |              --- variant declared here
2 |
3 | fn Red() -> Int { 1 }
  |    ^^^ function declared here
  |
  = note: a bare `Red` in an expression must have one meaning
  = help: rename the function, or rename the variant
```

Primary span on the value declaration, label on the variant, as in §2.12.1. The fix is a suggestion only: the compiler cannot know which one to rename. Recovery: bare uses resolve to the variant, so the rest of the module checks against §3.4 alone.

Local hiding:

```blink
type Color { Red, Green }

fn score(c: Color) -> Int {
    let Red = 5              // warning[LocalHidesVariant]
    match c {
        Red => Red           // pattern: the variant; arm body: the local 5
        Green => 0
    }
}
```

```
warning[LocalHidesVariant]: local `Red` hides the variant `Color.Red` in expressions
 --> src/main.bl:4:9
  |
4 |     let Red = 5
  |         ^^^ `Red` in an expression now means this local
  |
  = note: `Red` in a pattern still means `Color.Red`
  = help: rename the local, such as `red`
```

**Tradeoffs (AI/ML)**

- **Zero cost for normal code.** Values in real Blink are snake_case and variants are PascalCase. The rule fires only on code that is already confusing. No new syntax, no new token in the common case.
- **One sentence to learn.** "A bare name is a variant or a value, never both" is the rule E0518 already teaches for structs. The model learns one rule with a wider subject, not a second mechanism.
- **The error is at the declaration, where the fix is.** A use-site error would say "qualify it". But the `fn` side has no qualified spelling in its own module, so that fix does not close for the value side. A declaration error tells the model the only working fix: rename.
- **Cost: the scope is the whole program.** A `pub` variant added in a dependency can break a `fn` of the same name in my package. This pulls against the §3.4 sentence "a distant enum declaration can never retroactively change which variant a site resolves to". My reading: §3.4 forbids a *silent* change of meaning; a declaration error is loud and names both sites, so it does not violate that sentence. E0518 accepted this cost already. One scope for both E0518 cases is simpler for a model than two scopes. If the panel wants a narrower scope, I accept "the package" (the variants of dependencies excluded) as second choice, but the struct rule should then narrow too, so the two stay one rule.
- **The warning fixes the split meaning in p1.** Today `Red` means two things in one function with no sign. A warning keeps §2.2 shadowing legal and still tells the model.

---

**Proposal 2: module-scope value wins lexically; variant search runs only if no value binding**

**Rule**

> A bare name in an expression resolves in this order: (1) function-local binding; (2) module-scope value binding (declared or imported); (3) §3.4 variant resolution. A same-module `fn`/`let`/`const` and a variant of a type that the same module declares is E1016. A value binding in one module and a variant in another do not collide; the value wins. When a type hint names an enum that has a variant of that name and the value's type does not fit, the type error gets a note: "`Red` here is the function `main.Red`; write `Color.Red` for the variant."

```blink
import palette.{Color}       // Color has variant Red

fn Red() -> Int { 1 }        // legal: Red the variant lives in another module

fn main() {
    let c: Color = Red       // error[E0300]: declared type Color but got fn() -> Int
                             // note: `Red` here is the function `main.Red`
                             // help: write `Color.Red` for the variant
}
```

**Tradeoffs (AI/ML)**

- Local: resolution depends only on the module's own bindings. A distant variant cannot break a build.
- But a model must now learn an ordered lookup with three steps, plus a fourth case (same-module E1016 vs cross-module legal). That is two rules where Proposal 1 has one.
- The silent case remains: `Red()` calls the `fn` and the model may have meant the variant. The type error catches it only when the types differ. With `Leaf(n: Int) -> Wrap` style helpers (a `fn` that returns the same enum), no error ever fires.
- Pattern and expression still disagree for the same token at module scope (pattern = variant, expression = fn). I count that as a defect for code generation.

**Rejected: hint-directed tie-break between `fn` and variant**

`let i: Int = Red()` → the fn, `let c: Color = Red()` → the variant. This is type-directed overloading under a new name. Blink has no overloading (§2.12.1). It adds a decision point that depends on inference, and row 6 of the brief shows the compiler cannot even do it consistently today. No.

**Cross-language note**

- OCaml/Haskell: case separates constructors and values; no rule needed. Blink lacks the lexical signal, so Proposal 1 states it as a rule.
- Rust: unit variants imported with `use Color::*` live in the value namespace and collide with a `fn` or `const` of that name (E0255). A local `let` that is named like an in-scope unit variant is a pattern, not a binding (E0005 refutable pattern), which is the known footgun. Proposal 1 keeps Rust's collision and avoids its footgun: a pattern always prefers the variant, and a local `let` named like a variant gets a warning.
- Swift: `.red` needs a leading dot when bare, so no clash exists. Blink chose bare spelling (decision 2), so it must pay with a collision rule.

**Open questions for the panel**

1. The exact W-code for `LocalHidesVariant`, or fold it into an existing shadow warning.
2. Whether `@allow(LocalHidesVariant)` is enough, or the warning is error-level in `--strict`.
3. Out of scope, noted only: a sum `type Red` plus a variant `Red` of another type. E0518 today covers struct names only. If Proposal 1 passes, the panel may want the same sentence for every type name; I would file it as a follow-up, not decide it here.
4. tzrpfj interaction: none. Proposal 1 keeps bare and qualified spellings both legal in construction and patterns.

**I prefer Proposal 1.**

##### Minimalism

**My frame**

Today the compiler has no rule, and typecheck and codegen pick different winners for the same name. That is a miscompile, so "do nothing" is not an option. The question for my seat is: which rule adds the fewest new concepts, codes and lookup steps?

The answer must reuse what is decided: §2.12.1 (two namespaces, E1016, no winner), §2.2/§10.6 (shadowing only between nested scopes), §3.4 (hint, then global-unique). I count new concepts for each proposal.

---

**Proposal M1 (PREFERRED) — A variant is a value name in its declaring module**

**Rule (spec-ready, for §2.12.1)**

> **Variants are values.** Each variant of a `type` (opaque or not) binds its name in the value namespace of the module that declares the type. A `let`, `let mut`, `const` or `fn` with the same name as a variant of a type in the same module is `DuplicateModuleBinding` (E1016). Two types in one module that have a variant of the same name do not collide: §3.4 *Variant Construction* resolves them. A variant does not collide with a type of the same name in the type namespace (`type Leaf { Leaf(Int) }` is valid).
>
> **Bare use.** A bare name in value position resolves through the ordinary scopes first: function-local bindings, then module-scope `let`/`let mut`/`const`/`fn` and imported values, then the prelude. The variant search of §3.4 (hint, then global-unique) runs only when the ordinary scopes do not bind the name. A variant declared in the same module never reaches this step through a value of the same name, because E1016 rejects that pair.
>
> **Local shadowing.** A function-local binding can hide a variant name, as it hides any module value (§2.2). This is a shadow between nested scopes, so it is legal. The qualified form `Type.Variant` always reaches the variant.

**Example**

```blink
type Color { Red, Green }

fn Red() -> Int { 1 }       // error[E1016]: `Red` is declared twice in module `main`

fn main() {
    let _ = Red()
}
```

```
error[E1016]: `Red` is declared twice in module `main`
 --> src/main.bl:3:4
  |
1 | type Color { Red, Green }
  |              --- first declared here (variant of `Color`)
...
3 | fn Red() -> Int { 1 }
  |    ^^^ declared again here
  |
  = help: rename one of the two declarations
```

The order rule of §2.12.1 holds unchanged: the primary span is on the later declaration in source order. If the `fn` comes first, the span is on the variant and the label is on the `fn`.

Same rule for every value kind and every variant shape:

```blink
type Wrap { Leaf(Int), Empty }
const Empty = 0               // error[E1016]: `Empty` is declared twice in module `main`
let Leaf = 5                  // error[E1016]: `Leaf` is declared twice in module `main`
```

Local shadowing stays legal; the qualified form still works:

```blink
type Color { Red, Green }

fn main() {
    let Red = 5
    io.println("{Red}")              // 5
    let c: Color = Color.Red         // OK: qualified always reaches the variant
}
```

Cross-module: a value in scope comes before the variant search.

```blink
// module paint
pub type Color { Red, Green }

// module main
import paint.{Color}
fn Red() -> Int { 1 }

fn main() {
    let n = Red()            // the fn: ordinary scope binds `Red`
    let c: Color = Color.Red // the variant: qualified
    let d: Color = Red       // error[TypeError]: declared type Color but got fn() -> Int
                             //   note: `Red` is also a variant of `Color`; write `Color.Red`
}
```

**Tradeoffs (minimalism)**

- **New concepts: zero.** No new namespace, no new code, no new lookup layer. The variant joins the value namespace that §2.12.1 already defines, and E1016 already has the diagnostic shape, the order rule and the recovery rule. The spec gains one paragraph.
- **One lookup order for every bare name.** Scopes first, then the §3.4 variant search. This keeps §3.4 locality: a distant declaration never changes a site, because the ordinary scopes are all local to the file (locals, own declarations, own imports, the fixed prelude).
- **It closes the miscompile at the source.** The only pair that typecheck and codegen disagree on today is a same-module pair. M1 rejects that pair, so no site needs a "which one wins" rule in codegen.
- **Cost:** a module cannot have `fn Red` next to a variant `Red`. Naming convention (variants PascalCase, values snake_case) means real code almost never wants this. When it does, the fix is a rename, which the author controls inside one module.
- **Cost:** in the cross-module case, the value wins over a type hint (`let d: Color = Red` above). I accept this. A hint that overrides a name in scope is a second, competing resolution rule; the note on the type error points to `Color.Red`. The author of `main` wrote both `fn Red` and the use, so the cause is in view.
- **Not a new rule for `let` patterns.** It does not touch how `match` reads `Red =>`. (See interaction 2 below.)

**Cross-language note**

- Haskell, OCaml, Elm: constructors are module-level names, and a duplicate constructor in one module is a declaration error. They never clash with functions because the grammar forces constructors to be uppercase and values lowercase. Blink has no such case rule, so it needs the E1016 rule instead.
- Rust: variants are scoped to the enum. `use Color::*` brings them in bare, and a module `fn Red` then silently shadows the glob. That silent winner is the outcome Blink's §3.4 forbids ("no path ever silently picks a winner"), so Rust is the warning here, not the model.
- Swift: cases are scoped to the type (`.red`, `Color.red`); bare use needs the leading dot. Blink chose bare use, so it must pay for it with a namespace rule.
- Go: no sum types; every `const`/`func` sits in one flat package namespace and duplicates are errors. M1 is the Go answer applied to variants.

---

**Proposal M2 (ALTERNATIVE) — Variants live outside module scope; a two-way match at a bare use is an error**

**Rule**

> Variants do not bind names in module scope. A bare name in value position first looks through the ordinary scopes. Then, if the name also matches a variant through §3.4 (hint or global-unique), and the ordinary scopes also bind it at module scope, the site is `error[AmbiguousName]`. Function-local bindings still hide variants without error.

**Example**

```blink
type Color { Red, Green }
fn Red() -> Int { 1 }       // OK at declaration

fn main() {
    let _ = Red()           // error[AmbiguousName]: `Red` is both fn `Red` and variant `Color.Red`
                            //   help: write `Color.Red` for the variant
}
```

**Tradeoffs**

- **New concepts: one new code and one new step.** It also leaves no way to name the `fn` at all: a module cannot qualify its own `fn`. So the `fn` is dead, and the "use-site error" is a declaration error that fires late and once per use. That is strictly worse than M1.
- It does reproduce §3.4's use-site style for variant-vs-variant. But variant-vs-variant has a qualified escape for both sides; fn-vs-variant does not. The analogy does not hold.

I list M2 so the panel sees why the use-site model fails here, not because I support it.

---

**Proposal M0 (REJECTED by me) — Convention only**

A lint that forbids PascalCase `fn`/`let`/`const` names would make the collision rare. It does not remove it (`const` names are often written in caps, and FFI wrappers can need PascalCase), and the language still needs a rule for the case that remains. A lint does not replace a rule. Reject.

---

**Interactions for the moderator (not resolved here)**

1. **Prelude variants `Some`, `None`, `Ok`, `Err`.** Under M1 they are prelude values. A module `fn Some` is then a shadow between nested scopes (prelude under module), like a user `type Option` (W1010). I recommend that M1 says nothing new here and lets the existing prelude rule apply; if the panel wants a warning for value-shadowing of a prelude constructor, that is a separate question.
2. **`let` with a bare capitalised name.** §3.5 makes a single-variant enum pattern irrefutable. So `let Only = x`, where `Only` is the one variant of a type in scope, could read as a pattern or as a new binding. The facts table shows the compiler makes a new binding today. M1 does not depend on the answer. It is a pattern question, so I suggest a separate friction ticket rather than folding it in here.
3. **tzrpfj (bare vs qualified audit).** M1 adds no new spelling and keeps "qualified always works", so it does not change that audit.
4. **Opaque types.** An opaque type still binds its variant names in its own module (they are used there). Outside the module they are hidden (§2.12.2), so they bind nothing there and cannot collide there.

**Preference**

**M1.** It adds no code, no namespace and no lookup layer. It moves the variant into the value namespace that already exists and lets E1016 do the rest.

#### Phase B — Debate, round 1

All six signalled "stable, ready to vote" after one round.

##### Systems

I read all five other Phase A texts. I amend my Proposal A on Q4: I move from use-site ambiguity to scope order, with one warning at the declaration. Reasons are under Q4.

**Q1 — Model: Q1-N (a variant binds no value name)**

Position unchanged. Against Q1-Y-mod (min M1): plt P4 is right. If a variant is a member of the module value namespace, two enums in one module that share `Pending` are two members of one name, which is E1016 by §2.12.1. min M1 adds an exception sentence for that case. A namespace with an exception for its own members is not the namespace of §2.12.1; it is Q1-N with different words. Against Q1-Y-pkg (devops DV-1): it makes one entity a member of the value namespace of N modules at once. That is a new concept, not a reuse of §2.12.1. Q1-N gives the same declaration error (A1) with one honest sentence: "this is a collision check, not namespace membership."

**Q2 — Code: E1016**

Against E0518 (aiml): decision 4 already reports a clash between a variant and a `T.` function as E1016, so E1016 already covers a variant on one side. E0518 carries a program-wide scope (see Q3), and decision 2 scoped it to struct vs variant.

**Q3 — Reach: Q3-module**

This is my strongest point from the systems seat. The module-level check reads the text of one module. Its result depends on nothing outside that module. That matters for incremental and daemon checks: when module A adds a variant, only A needs a recheck for this rule. With Q3-package (devops DV-1), a new variant in A invalidates the declaration check of every module in the package. With Q3-program (aiml 1), a dependency release invalidates and can break every downstream module, which web and devops both reject on semver. Under the Q4 rule below, Q3-package buys nothing that the warning does not already give.

**Q4 — Bare use with a module value and a variant from another module: amend to Q4-scope**

I withdraw the use-site error (`AmbiguousBareName`) from my Proposal A. min M2 and devops DV-3 showed the defect: a module cannot qualify its own `fn Red`. Under a use-site error, every bare use of it is an error, so the `fn` is dead, and the user gets N errors at use sites for a cause at one declaration. The variant side always has an escape (`Color.Red`); the value side has none. So scope order is the only rule where both entities stay reachable.

My position is now: local → module value (declared or imported) → §3.4 (hint, then global-unique). The first step that finds the name decides. The hint never moves a name past a binding (A2; plt's point that the hint can be an unsolved metavariable is a strong reason, because resolution would then depend on solve order).

Systems cost: step 2 is a hash lookup in tables that already exist. When it hits, the program-wide variant search does not run. One static result per site, so the typecheck/codegen split cannot happen.

I add one amendment, from devops DV-1: warning `ShadowedVariant` (W1011) at a module-scope value declaration whose name is equal to a variant visible to that module but declared in another module (same package or dependency). It fires once, at the declaration, not at each use. It never breaks a build. A type error at a hinted site also gets the note "write `Color.Red`" (web 1, min M1). With the warning, no hidden variant goes without a diagnostic, which keeps the §3.4 sentence "no path silently picks a winner".

Against plt P1 (E0519 inside one package): same objection as above. The `fn` in the using module becomes unreachable bare.

**Q5 — Prelude variants: Q5-err-module (E1016)**

Position unchanged. `Some`, `None`, `Ok`, `Err` feed `?`, `??` and the carrier hints of §3.4. Under Q5-shadow (plt, min), the spec must say whether the desugaring of `?` reads the user's `Some` or the prelude one. If it reads the prelude one, then `Some` in source and `Some` in the desugaring differ. If it reads the user one, the program breaks. An error removes the question at zero runtime cost. Against Q5-reserved for locals (devops): a local is next to its uses, and Q6 treats locals as legal shadows. One rule for all locals is simpler. I accept web's addition of `Less`, `Equal`, `Greater` only if those are prelude variants in the spec; I have not checked, and the moderator should check before they go on the ballot.

**Q6 — Function-local binding: Q6-legal-silent**

Unchanged. The local is next to its uses. §2.2 gives no warning for any other local shadow. I do not object hard to a warning (aiml, devops), but I do not want it to fire per local in generated code. If it goes on the ballot, I vote silent.

**Q7 — Patterns**

Agree with plt's text: "A bare name in a pattern is a variant when §3.4 resolves it (the scrutinee type is the hint), else a new binding. A value binding of that name, at any scope, does not change the pattern." min's `let Only = x` question: a separate friction ticket.

**Q8 — "One resolution"**

I support one semantic sentence in the spec: "A bare name at a site has one meaning, given by these rules." I do not want devops's list of phases and tools in sections/, because that is implementation detail. The current split (typecheck picks the variant, codegen calls the `fn`; the `_cg_fn_value1` C error) is a codegen bug and needs its own `type:bug` ticket now, with the brief's rows 2 and 3 and web's cross-module row as the test cases (web). It must not wait for the spec edit.

**Other items**

- E0518 scope (program-wide) has the same semver and invalidation cost I raise in Q3. A follow-up ticket, not this ballot.
- aiml open Q3 (`type Red` plus a variant `Red` of another type): a follow-up ticket.

Stable, ready to vote.

##### Web/Scripting

I confirm A1, A2, A3.

**Q1 — Model: **Q1-N****

The behavior is the same as Q1-Y-mod. The difference is the text a reader learns. Q1-Y-mod needs a carve-out ("two variants of one name in one module do not collide") against the sentence §2.12.1 just made ("at most one declaration per namespace"). plt P4 is right: without the carve-out, decision 2 breaks. A rule with a built-in exception produces Stack Overflow questions. Q1-N says one thing: a variant lives in `T.`, and the module has a collision check. Against devops Q1-Y-pkg: "a variant is a value in every module of its package but not in other packages" is a third model to learn.

**Q2 — Code: **Q2-E1016****

The developer already knows E1016 from `fn f` + `fn f`. Against aiml E0518: decision 2 scoped E0518 to struct vs variant on purpose, and plt notes that decision 4 already uses E1016 for the `T.` clash.

**Q3 — Reach: **Q3-module**. Second choice: **Q3-package**. Not Q3-program.**

- Against Q3-program (aiml): a dependency adds a `pub` variant in a minor release, and my `fn` breaks. That is the npm "patch release broke my build" pain. aiml reads §3.4 as "only silent changes are banned". But a loud error in a file I own, caused by code I do not own, is still bad DX. If the panel wants program-wide reach, E0518 has the same cost, and that belongs in the follow-up ticket.
- Q3-package (devops) is defensible: in one package the author owns both names, and §2.12.3 is package-wide. I keep module first because plt's point holds: `fn Active` in `views.bl` would fail because `models.bl`, which `views.bl` never imports, declares `Active`. With the Q4 warning below, the in-package case is not silent anyway. I can live with either.

**Q4 — Bare use, value and variant from another module: **Q4-scope**, amended with devops's W1011**

- Against Q4-ambig (sys, plt): the module's own `fn Red` has no qualified spelling, so a use-site ambiguity makes the `fn` unreachable. The only fix is a rename, but the error comes N times, at the uses, not once at the declaration (devops DV-3, min M2 make the same point). sys's version also lets a dependency's new variant break a downstream build at every use. plt limits it to one package, which helps, but it still errors at N sites for a declaration-level problem.
- aiml P2 raises a fair point against plain Q4-scope: `fn Leaf(n: Int) -> Wrap` in module B silently wins over variant `Wrap.Leaf`, and no type error fires. I accept that hole is real. **Amendment:** I adopt devops's `ShadowedVariant` (W1011): one warning, at the module-scope value declaration, when its name equals a variant that §3.4 can reach from that module. A warning fires once, in the file the author owns, and it never breaks a build. So nothing is silent. The type-error help line ("write `Color.Red`") stays.
- I apply W1011 to all such variants (same package and other packages), because I hold Q3-module. If Q3-package wins, W1011 covers only other-package variants, as devops wrote.

**Q5 — Prelude variants: **error.** I move to **Q5-reserved** (devops E1017 `ReservedValueName`), module scope and local.**

- One rule that a JS developer understands in five seconds: "`Ok`, `Err`, `Some`, `None` are reserved words for values." Same as `undefined`-style names people already avoid.
- Against Q5-shadow (plt, min): today a module `fn Some` is silently dead (measured), and under shadowing it would silently take over every `Some(x)` in the module. W1010 is a warning for *types*; a hidden `Some` breaks far more code than a hidden `Option` type name. Nobody needs a value named `Some`.
- E1017 over E1016: "`Some` is declared twice in module `main`" points at nothing the user wrote twice. A dedicated message is clearer.
- `Less`/`Equal`/`Greater`: include them if the panel treats them as prelude variants (they are, per the §10 prelude table). I do not insist.

**Q6 — Local binding named like a variant: I move to **Q6-legal-warn**, same code W1011**

aiml's measured case convinced me: `Red => Red` with a local `let Red = 5` reads as the variant in the pattern and the local in the body. That is a trap that no TS/Python developer expects. One warning code for Q4 and Q6 is one concept, not two. It fires only when a local has the name of a variant, so normal snake_case code never sees it. `@allow(ShadowedVariant)` silences it.

**Q7 — Patterns: **agree** (sys, plt, devops, aiml wording)**

A bare name in a pattern that names a variant of the scrutinee type is that variant. No value binding at any scope changes a pattern. Agree with min that `let Only = x` belongs in a separate friction ticket.

**Q8 — One resolution: **support as normative****

The measured typecheck/codegen split is the bug users will hit. I support devops's sentence. I would phrase the spec part as a language guarantee: "A bare name at a site has exactly one meaning, and every compiler phase and tool uses that meaning." The list of tools can be an example, not the rule.

**Other items**

- Codegen `_cg_fn_value1` / split: separate bug ticket, with sys's two conformance tests (`fn Leaf(n: Int)` + `Leaf(2)`, and `let c = Red`).
- E0518 reach (devops/aiml): yes, follow-up ticket.
- aiml open Q3 (`type Red` + variant `Red` of another sum): follow-up ticket.
- min `let Only = x`: friction ticket.

Stable, ready to vote.

##### PLT

I read all five other texts. I amend P1 in two places (Q3, Q5) and withdraw my use-site E0519 for the in-package case (Q4).

**A1–A3:** confirmed.

**Q1 — Model: **Q1-N****

A variant lives in `T.`; the declaration error is a collision check, not namespace membership. Against Q1-Y-mod (min M1) and Q1-Y-pkg (devops DV-1): both need the extra sentence "two variants of one name in one module/package do not collide". A namespace that holds two entries of one name is not a namespace in the §2.12.1 sense ("each bare name has at most one declaration in each namespace"). So Y-mod is not "zero new concepts". It redefines the value namespace with an exception, and it contradicts decision 4 (variant home = `T.`). Q1-N gives the same diagnostics with no exception. I ask that the spec text use Q1-N wording whatever the reach.

**Q2 — Code: **E1016****

Against aiml (widen E0518): decision 2 says E0518 is "narrowly scoped to the struct-vs-variant case only". Widening it reopens decision 2. Decision 4 already uses E1016 for a clash across namespaces (variant vs type-scoped `fn`), so E1016 already covers this shape.

**Q3 — Reach: **amend to Q3-package** (was Q3-module)**

devops DV-1 convinced me. Within one package, §3.4 global-unique already makes every variant of the package ambient in every module (web and devops measured it: `let c = Red` works with no import of `Color`). So a `fn Red` in module A and a variant `Red` in module Z of one package are two peers at one level, and the author owns both. This matches the decided §2.12.3 split exactly: E1016 package-wide, a different rule across packages. My Phase A concern ("A never imports Z") does not apply, because the bare variant reaches A without an import anyway.

Against Q3-program (aiml): the error points into a file the user owns, but the cause is a dependency release. The struct rule E0518 has the same defect. That calls for a follow-up ticket to narrow E0518, not for copying the defect. aiml reads §3.4 "never retroactively change" as "never silently". I agree with that reading. But a change in a dependency that breaks downstream compilation still fails compositionality: a well-typed program must stay well-typed when a dependency adds a declaration that the program does not name.

Against Q3-module: it leaves the in-package cross-module case to a use-site rule. min M2 and devops DV-3 are right that the use site gives the value no escape (no qualified spelling of one's own `fn`). So the error belongs at the declaration.

**Q4 — Cross-package use: **Q4-scope, withdraw my E0519 rule****

With Q3-package, my in-package use-site case cannot arise. The case that remains is a dependency variant against a module-scope value. Decision 5 puts a dependency under the local module, so this is a shadow between nested scopes: the value wins, by lexical order. The hint does not move a name past a binding that an earlier scope finds (A2). A type error at a hinted site carries a note that names `T.V`.

Against sys Q4-ambig: it gives N use-site errors for a value that has no other spelling (min M2). Across packages it also lets a dependency release break a downstream build, which I reject under Q3.

Warning: I accept devops W1011 `ShadowedVariant` at the module-scope value. It is the analog of W1000 (dependency under local module), and the warning cannot break a build. Amendment for the vote: fire W1011 only when the module imports the variant's type. Without that limit, any dependency that has a variant `Empty` warns on every `fn Empty` downstream, with no relation to the user's code.

**Q5 — Prelude: **amend to Q5-err-module** (was Q5-shadow)**

web and devops changed my view. The prelude variants carry the §3.4 carrier hint (`Err(NotFound { .. })`). A module-scope `fn Some` that shadowed the prelude would change every carrier site in the module, and every spec example would need an "unless shadowed" note. Decision 6 W1010 is about type names, where a shadow changes one name. Here it changes a resolution mechanism. So: the prelude variants count as declared in every module (sys wording), and a module-scope value of one of these names is E1016.

Against devops Q5-reserved (E1017, also for locals): a local `let None = 3` is a shadow between nested scopes, which decision 5 makes legal. Patterns are not affected (Q7). An error for locals is a new reserved-word class without need.

**Q6 — Locals: **Q6-legal-silent****

The split (expression `Red` = local, pattern `Red` = variant) is well-defined: patterns never read values, so only one candidate exists in each position. Decision 5 gives no warning for any function-local shadow. Against aiml/devops: a warning is a lint question. It does not change the semantics. I would not block a lint, but I vote against putting it in this decision.

**Q7 — Patterns: as stated**

A bare name in a pattern is a variant when §3.4 resolves it (the scrutinee type is the hint), else a new binding. No value binding, at any scope, changes a pattern. This is consistent with all measurements (aiml's `red =>` binds because no variant `red` exists). min's `let Only = x`: agree it is a separate friction ticket.

**Q8 — One resolution: **normative, language-level wording****

Accept as spec text, with this wording: "A bare name at a site denotes exactly one entity, and the compiler determines it statically." Do not list compiler phases in §2/§3 (implementation detail). The LSP and `blink query` sentence can go in §6 tooling. Every stage that disagrees then violates the language rule, so a test can catch the typecheck/codegen split.

**Other items**

- Narrow E0518 to the same package split: support a follow-up ticket.
- aiml open Q3 (sum `type Red` + variant `Red`): follow-up ticket.
- web: `_cg_fn_value1` C error is a codegen bug ticket. Agree.

stable, ready to vote

##### DevOps

I read sys, web, plt, aiml and min.

**A1-A3:** confirmed.

**Q1: model. I move to Q1-N.**

I withdraw the "binds a name in the value namespace" wording in DV-1. plt P4 is right. If a variant were a value binding, two enums in one module that both have `Pending` would be E1016, and that is against decision 2. min M1 avoids this only with a special case ("two types ... do not collide"). That special case shows the variant is not a value binding. It is a collision check between two resolution systems. Diagnostics and the LSP do not need the membership claim. They need "one meaning or one error". I keep the DV-1 check itself and restate it in Q1-N terms (sys A, plt P1).

**Q2: E1016.**

aiml wants E0518, but that would widen decision 2's "narrowly scoped" rule. Users already know E1016 from `fn f` + `fn f`. The message can say "a variant of `Color`" in its label (as all drafts do).

**Q3: reach. I still prefer package reach. My non-negotiable rule: no silent winner inside one package.**

The pair inside one module is agreed. The open case is two modules of one package, where module A has `fn Red` and module B has variant `Red`:
- min M1 and web 1 let the `fn` win by scope order. The only diagnostic is a type-error note. aiml showed the hole in this: if `fn Leaf(n: Int) -> Wrap` returns the same enum, no type error ever fires, so the `fn` wins in silence. Inside a package the author owns both names, so silence is not acceptable.
- plt P1 gives a use-site E0519 inside the package. This is also loud, and I accept it. The cost is N diagnostics at the uses, not one at the cause. Also the `fn` can never be used bare in its own module (DV-3, min M2). An exported `fn` that is used only as `a.Red()` gets no error, and plt's rule is more exact there.

My order: Q3-package (E1016 at the declaration) first, then plt P1 (module E1016 plus package E0519). Against Q3-program (aiml 1): a `pub` variant added in a dependency's minor release breaks a downstream build. The span is in the user's file, but the cause is in a file the user cannot edit. web 2 and plt agree.

**Q4: bare use where a module value and a variant from another module both exist.**

- **Same package:** an error, either Q3-package or plt's E0519 (see Q3). Q4-scope must not apply here.
- **Other package:** Q4-scope. The value wins. A type error at a hinted site gets the note and help that name `Color.Red` (web, min, aiml P2, plt).
- **Against sys A (`AmbiguousBareName` for every §3.4 variant, dependencies included):** this fails the semver test. A new dependency variant turns a working bare use into an error. sys says "an error, never a different meaning". But a downstream build that breaks on a dependency's minor release is the problem itself, also when the error is loud. plt's dependency-scope rule fixes this.
- **I withdraw the module-scope W1011 for the other-package case.** `--strict` and `[lints]` can promote warnings to errors (W1001 is promotable). Then a new dependency variant could break a strict build again, which brings back the semver problem. The type-error note is enough.

**Q5: prelude variants. I move to Q5-err-module (sys, web, aiml).**

A module-scope `let`, `let mut`, `const` or `fn` named like a prelude variant is E1016 in every module. Treat the prelude variants as declared in each module (sys wording). The set must include `Less`, `Equal` and `Greater` (web measured `fn Less` dead against an `Int` hint). The rule must cover every variant of every prelude enum, not a list of four.

Against Q5-shadow (plt, min): under scope order, a module `fn Some` hides `Some` for every `Option` construction in that module. W1010 is a warning that people suppress, and after it each `Some(x)` in the file means something else. For types, W1010 is acceptable because `type Handler` is a deliberate choice. A value named `Some` is almost always a mistake. Today such a `fn` is silently dead (my measurement and web's).

I withdraw the local part of my E1017 (`ReservedValueName`). Locals go under Q6.

**Q6: local bindings. Q6-legal-warn (with aiml). I merge my code into aiml's name: `LocalHidesVariant`, one new W-code.**

My reason: measured by me, aiml and sys, `Red` in `x == Red` is the local and `Red =>` is the variant, in one function. plt says the dual pair is construction and pattern. That is true for the spec, but the reader sees one token with two meanings a few lines apart. The warning fires once, at the binding, and its note says "`Red` in a pattern still means `Color.Red`". `@allow(LocalHidesVariant)` records a deliberate choice. To be consistent with my Q4 withdrawal, the warning covers only variants of the same package plus the prelude variants. A dependency variant can then never add this warning to a downstream build, so a `--strict` build has no semver cost. If the panel votes it down, I want it filed as a lint ticket, not dropped.

**Q7: patterns. I adopt plt's text.**

"A bare name in a pattern is a variant when §3.4 resolves it (the scrutinee type is the hint), else a new binding. A value binding of that name, at any scope, does not change the pattern." min interaction 2 (`let Only = x`) should be a separate friction ticket.

**Q8: "one resolution" should be normative spec text. sys agrees.**

plt calls it an implementation note. But the failure is visible to users: hover and go-to-definition (typecheck) show the variant while the binary calls the `fn`. Tools are part of the language surface (§6). One sentence in §3.4 or §2.12.1 gives conformance tests a rule to cite: "A bare name at a site has one meaning; every compiler phase and tool uses it." If the panel wants it outside the core text, a §6 tooling sentence is fine.

**Other items**

- I want the E0518 narrowing follow-up ticket (aiml and me). It is not on this ballot.
- web: the `_cg_fn_value1` C error needs its own codegen bug ticket. Agreed.

Stable, ready to vote.

##### AI/ML

I read all five other texts. I **withdraw my Proposal 1 as written** (program-wide, E0518). The semver argument from web 2, devops DV-2 and plt is right: a model that writes `fn Red` in its own package cannot know every variant in every dependency, and an error it cannot fix at the cause is a bad teaching signal. I now support **devops DV-1's reach and diagnostics, with the Q1-N model wording of sys/plt**. Reasons per question below.

**Q1 — Model: **Q1-N****

A variant lives in `T.`; the declaration error is a collision check, not namespace membership. plt P4 is right that Q1-Y-mod makes two enums of one module that share `Pending` E1016, against decision 2. min M1 patches this with an exception sentence ("two types ... do not collide"). An exception is a second rule the model must learn. Q1-N gives DV-1's result with no exception. To devops: I read DV-1's "binds its bare name" as a way to state the reach; I ask that the text say "collides with" instead.

**Q2 — Code: **E1016** (I withdraw E0518)**

With package reach, E1016 has a direct precedent: §2.12.3 already reports a `T.` clash as E1016 over the whole package. plt is right that widening E0518 reopens decision 2.

**Q3 — Reach: **Q3-package****

This is the question that matters most for code generation. Compare the same-package, cross-module case (variant `Leaf` in `tree.bl`, `fn Leaf(n: Int) -> Wrap` in `main.bl`):

- Q3-module + Q4-scope (web 1, min M1): `Leaf(2)` calls the `fn` and type-checks, because the helper returns `Wrap`. **Silent.** No error, no warning, no note. A model that meant the variant gets wrong code that compiles. The "note on the type error" fallback only fires when the types differ.
- Q3-module + Q4-ambig (sys A, plt P1): loud, but the `fn` has no qualified spelling in its own module, so every bare call is an error. The fix is still to rename. devops DV-3 and min M2 make this point. It gives N use-site errors for one cause.
- Q3-package (DV-1): one error, at the declaration, in a package the author owns, with both sites shown. Same reach as the §2.12.3 `T.` check.

plt says module reach keeps separate reasoning. But §3.4 global-unique already makes a bare variant reach across modules (web and devops measured it with only `import pal`). The variant is package-visible already. The collision check should cover the same reach as the resolution.

**Q4 — Cross-module bare use: **scope order** (local → module value/import → §3.4), as in DV-1 step order**

Under Q3-package this applies only to variants of *other packages*, which is where scope order is correct (decision 5: dependency under local module). I support it with devops's **W1011 `ShadowedVariant` at the hiding declaration**. Against web 1/min M1 (no warning): a cross-package hide is otherwise silent in the same way as the `fn Leaf -> Wrap` case above. One warning, at the declaration, is cheap, and a dependency release cannot break the build. Against sys A `AmbiguousBareName` across packages: a dependency that adds a `pub` variant then breaks downstream use sites. It fails the semver test.

**Q5 — Prelude: **Q5-reserved** (devops), module and local**

`Some`, `None`, `Ok` and `Err` are among the most frequent tokens in Blink code. If a module can shadow them (plt, min), then every `Some(x)` the model writes in that module can mean a user function, and the model must check each module for a shadow before using `?`/`??` carriers. That cost falls on every file. A ban costs nothing: no one needs a value named `Some`. Amendment: state the rule by kind, not by list: "a value binding may not have the name of a variant of a prelude type." Then `Less`/`Equal`/`Greater` (web) are covered, and a model has no list to memorize. Second choice: Q5-err-module (sys, web).

**Q6 — Local binding named like a variant: **Q6-legal-warn**, one code with Q4**

I merge my `LocalHidesVariant` into devops's W1011 `ShadowedVariant`: one warning for "a binding hides a variant", at module or local scope. Against plt ("the local is next to its uses"): my probe shows `Red => Red` in one arm, which means the variant on the left of `=>` and the local `5` on the right. Closeness does not help when one token has two meanings in one line. Rust has `bindings_with_variant_name` as deny-by-default for this reason. A warning, not an error, keeps decision 5 intact.

**Q7 — Patterns: agree with sys/plt/web/devops**

A bare name in a pattern that names a variant of the scrutinee type is that variant. No value binding changes it. Note only: plt's "else a new binding" keeps the case where a misspelled variant (`Gren =>`) is a catch-all. That is today's rule and out of scope, but I support a friction ticket with min's `let Only = x` case.

**Q8 — One resolution: **normative, as a language property****

State it as semantics, not as a fact about compiler phases: "A bare name at a site has exactly one meaning. Every tool that reports on the name (the compiler, `blink query`, the language server) reports that meaning." A model reads hover and `blink query` output as ground truth. Today that output disagrees with the binary. That is a spec-level promise, not an implementation note (against plt).

**Other items**

- Yes, file the codegen bug (`_cg_fn_value1`, typecheck/codegen split) separately (web).
- Yes, follow-up ticket: should E0518 narrow to package reach to match (devops, aiml).
- Keep my open Q3 (sum `type Red` + variant `Red`) as a follow-up, not on this ballot.

Stable, ready to vote.

##### Minimalism

I read all five other Phase A texts.

**Q1 — Model: I AMEND M1 to Q1-N.**

plt P4 is correct about my text. My M1 said "a variant binds a value name", then had to add an exception ("two types in one module with one variant name do not collide"). Under §2.12.1, two entries of one name in one namespace collide by definition, so that exception is a second rule hidden in the first. The behavior I want is a collision check. It is not namespace membership. So I withdraw the "variants are values" wording and support **Q1-N** (sys A, plt P1, web 1): a variant lives in `T.` (§2.12.3), §3.4 resolves its bare spelling, and the declaring module has a collision check. My behavior does not change, but the spec text gets shorter: it needs no exception clause.

Against **Q1-Y-pkg** (devops DV-1): it has the same exception problem, and it needs a third tier (an "outer scope" for dependency variants) with a new warning.

**Q2 — Code: **E1016.****

Against E0518 (aiml 1): decision 2 scoped E0518 "narrowly ... to the struct-vs-variant case only". If we widen it, we reopen a 6-0 decision. Decision 4 already uses E1016 for a clash across kinds in one module, so E1016 needs no new meaning.

**Q3 — Reach: **Q3-module.****

- Against Q3-program (aiml 1): if a dependency adds a variant, a `fn` that I wrote and own stops compiling. That is the largest possible reach for the smallest gain.
- Against Q3-package (devops DV-1): `fn Red` in module X becomes an error because module Y, which X never imports, declares a variant. §2.12.1 is a module-scope rule. Q4 handles the cross-module case, so the declaration check does not need to reach it.

**Q4 — Cross-module bare use: **Q4-scope** (web 1, aiml P2, devops for other packages). Second choice: plt's version of Q4-ambig.**

- Q4-scope adds no code and no step. Name lookup is the existing scope walk, with §3.4 at the end. A variant declared in another module never changes or breaks a site in this module, so the §3.4 locality promise holds in full.
- aiml objects that a helper `fn Leaf(n: Int) -> Wrap` gets called and no error fires. My reply: that `fn` is declared or imported in the same file as the use. That is not a distant silent winner. It is the name the author put in scope.
- sys A (any §3.4 variant, new code `AmbiguousBareName`): this adds a code, and a variant added anywhere in the program can break a working use. I oppose it.
- plt P1 (E0519, same package only; dependency variants shadowed, W1010 for prelude): this reuses an existing code and its reasoning is sound ("module-level meanings collide"). But it has two tiers (same package = error, dependency = shadow). Q4-scope has one tier. If the panel wants no scope winner, I vote for plt P1 over sys A.
- I oppose devops W1011 at a module-scope value that hides a dependency variant. The type-error note already names `T.V` at the only site where it matters.

**Q5 — Prelude variants: I CHANGE my position to **Q5-err-module, using E1016** (sys A).**

web and devops measured this: today a `fn Some` is silently dead. Under plain prelude shadowing it would hide `Some` in the whole module and break `?`, `??` and the §3.4 carrier hint. My "the existing rule applies" was wrong, because those names are tied to language machinery. sys's version adds the least: "the variants of a prelude enum count as declared in every module". This needs no new code (against devops E1017) and no list to maintain. It covers `Ordering` (`Less`/`Equal`/`Greater`, from web) automatically. I would keep local `let None = 3` legal (Q6). If a local `let None` is ever a real problem, it can be a lint.

**Q6 — Local binding: **Q6-legal-silent** (sys, plt, web).**

Against the warnings (devops W1011, aiml LocalHidesVariant): each one is a new code for a shadow that decision 5 already allows with no warning for every other local. The local is next to its uses. If friction appears, add a lint later.

**Q7 — Patterns: agree, with one amendment to plt's text, and I withdraw my interaction 2.**

plt: "a variant when §3.4 resolves it (the scrutinee type is the hint), else a new binding." I propose this instead: "a variant **of the scrutinee type**". If the global-unique step also applied in patterns, `let Red = 5` (scrutinee `Int`) would find `Color.Red` and fail, where today it binds. sys and web already use the scrutinee-only wording. With this text, my `let Only = x` question is answered: if `x` has the single-variant type, `Only` is that variant (irrefutable); otherwise `Only` is a new binding. No friction ticket is needed.

**Q8 — "One resolution" text: **implementation note, not spec text** (plt).**

§3.4 already says "Resolution is static", and Q1 to Q7 give each site one meaning. A sentence that names typecheck, codegen, `blink query` and the LSP describes compiler internals. The spec says what a name means; the conformance tests (sys: the `fn Leaf(n: Int)` case and the `let c = Red` case) enforce one result. Put the requirement in the implementation ticket.

**Other items**

- I agree with web: the `_cg_fn_value1` C error gets its own bug ticket.
- E0518 narrowing (devops/aiml) and a sum `type Red` against a variant `Red` (aiml): both are follow-up tickets, off this ballot.

Stable, ready to vote.

#### Phase C — Final vote

Tally: Q1 6-0, Q2 6-0, Q3 6-0, Q4 6-0, Q4w 5-1 (Minimalism dissent: no warning), Q5a/Q5b/Q5c 6-0, Q6 3-3 (Systems, PLT, Minimalism: silent; Web, DevOps, AI/ML: warn), Q7 6-0, Q8 5-1 (Minimalism dissent: implementation note).

##### Systems

**Q1 — Q1-N**
Reasoning: A variant lives in `T.`. The declaration error is a collision check between two resolution systems, not membership in the value namespace. All six seats now hold this, and it needs no exception clause for two enums that share `Pending`.
Concern: The spec text could still say "binds" by habit somewhere; the edit must use "collides with" throughout.

**Q2 — Q2-E1016**
Reasoning: Decision 4 already reports a variant-vs-`T.`-function clash as E1016, so E1016 already has a variant on one side. E0518 stays narrow, as decision 2 said.
Concern: "declared twice" reads oddly when one side is a variant; the label must say "a variant of `Color`".

**Q3 — Q3-package (changed from Q3-module)**
Reasoning: I drop my incremental-check argument. §3.4 global-unique resolution already makes every bare use depend on the variant table of the whole program, so a package-wide declaration check adds no new dependency edge for a recheck. aiml's case (`fn Leaf(n: Int) -> Wrap` in one module, variant `Leaf` in another) is silent under Q3-module, and inside one package the author owns both names. Package reach matches the §2.12.3 `T.` check, so one reach covers both E1016 cases.
Concern: A large package gets an error in module X for a variant in module Y that X never names; the diagnostic must show the variant's file with a secondary span.

**Q4 — Q4-scope**
Reasoning: Scope order gives one static result per site from a lookup in tables that already exist. The hint never moves a name past a binding, so resolution does not depend on the order of constraint solving. Under Q3-package it applies only to dependency variants, where decision 5 already puts the dependency under the module.
Concern: A dependency helper that returns the same enum can still be shadowed silently if Q4w-none wins.

**Q4w — Q4w-imported**
Reasoning: Under Q3-package, only dependency variants remain. A warning for every reachable dependency variant brings back the semver cost in `--strict` builds (devops). Limiting it to variants whose type the module imports ties the warning to a name the user wrote in this file, and it costs one lookup in the import table at the declaration.
Concern: A dependency variant that reaches the module through global-unique search with no import gets no warning, so that hide stays silent.

**Q5a — Q5a-E1016**
Reasoning: "The variants of a prelude enum count as declared in every module" needs no new code and no new concept. It removes the question of which `Some` the `?`/`??` desugaring reads, at zero runtime cost.
Concern: The "declared twice" headline points at nothing the user wrote twice; the label must name the prelude enum.

**Q5b — Q5b-local-as-Q6**
Reasoning: A local is a shadow between nested scopes (decision 5) and is next to its uses. Patterns do not change (Q7). One rule for all locals.
Concern: A local `let None = 3` reads badly; a lint can cover it later if friction shows.

**Q5c — Q5c-kind**
Reasoning: State it by kind ("every variant of every prelude type"), so `Less`/`Equal`/`Greater` are covered and a new prelude enum needs no spec edit.
Concern: A future prelude enum with a common variant name (e.g. `Empty`) would take that name from every module; the panel that adds such an enum must check this.

**Q6 — Q6-silent**
Reasoning: Decision 5 gives no warning for any other local shadow. The expression/pattern split has one candidate in each position (Q7). A lint can come later.
Concern: `Red => Red` with a local `Red` reads as one token with two meanings in one arm, and a reader can miss it.

**Q7 — Q7-scrutinee**
Reasoning: In a pattern, look only at the variants of the scrutinee type. That is a local lookup with a fixed result, and the program-wide search never runs in a pattern. It also keeps `let Red = 5` on an `Int` a plain binding, where plt's wording could make a distant `Color.Red` turn it into a pattern error.
Concern: A misspelled variant (`Gren =>`) is still a catch-all binding; that needs its own friction ticket.

**Q8 — Q8-lang**
Reasoning: One semantic sentence ("A bare name at a site has one meaning, given by these rules") gives conformance tests a rule to cite. The list of phases and tools is implementation detail and does not belong in §2/§3; a §6 tooling sentence is fine.
Concern: The rule does nothing until the typecheck/codegen split bug is filed and fixed; that ticket must be filed now.

##### Web/Scripting

**Q1**
- **Vote:** Q1-N
- **Reasoning:** One sentence a user learns: a variant lives in `T.`, and the compiler checks that no value shares its name. Every "Yes" wording needs an exception for two enums that share `Pending`, and exceptions generate questions.
- **Concern:** Docs may still say "variants are values" loosely; the spec and `blink llms` text must use the collision wording.

**Q2**
- **Vote:** Q2-E1016
- **Reasoning:** Users already know E1016 from `fn f` + `fn f`, and §2.12.3 uses it for the `T.` clash. Widening E0518 would reopen decision 2.
- **Concern:** "declared twice in module `main`" reads wrong when the variant is in another module of the package; the message must name the variant's type and module.

**Q3**
- **Vote:** Q3-package
- **Reasoning:** I move to my second choice. plt's point removes my objection: a bare variant already reaches every module of the package with no import (measured), so `fn Active` in `views.bl` really does compete with `Status.Active` in `models.bl`. One error at the declaration, in a package the author owns, beats a silent `fn Leaf -> Wrap` win (aiml) or N use-site errors.
- **Concern:** A new variant in one file can make a declaration in another file fail. The message must show both sites so the user does not hunt for the cause.

**Q4**
- **Vote:** Q4-scope
- **Reasoning:** Under Q3-package this covers only dependency variants. "My own names win over names from a dependency" is what every JS/Python developer expects. A dependency release can never break or change my code.
- **Concern:** A hinted site such as `let c: Color = Red` gives a type error. It must carry the "write `Color.Red`" help, or users will not see the cause.

**Q4w**
- **Vote:** Q4w-imported
- **Reasoning:** If I import `Color`, I use it, so a warning that my `fn Red` hides `Color.Red` is useful. If I never import it, a warning about some dependency's `Empty` variant is noise that people learn to ignore. plt's limit keeps the warning tied to code the user wrote.
- **Concern:** Under `--strict`, a dependency that adds a variant to a type I import can turn this warning into a build error. That is opt-in, but the docs should say so.

**Q5a**
- **Vote:** Q5a-E1016
- **Reasoning:** I drop E1017. "Prelude variants count as declared in every module" gives the same error with no new code, and it follows from the Q3 rule. My only issue was the message text, which a label can fix.
- **Concern:** The message must say "`Some` is a variant of the prelude type `Option`", not only "declared twice", or users will look for a second declaration that does not exist.

**Q5b**
- **Vote:** Q5b-local-as-Q6
- **Reasoning:** If prelude variants count as module declarations, a local that hides them is an ordinary nested shadow. One rule for all locals is easier to learn than a reserved-word class just for locals. With Q6-warn, the user still gets a warning.
- **Concern:** If Q6 is silent, a local `let None = 3` will produce confusing `x == None` code with no signal.

**Q5c**
- **Vote:** Q5c-kind
- **Reasoning:** "Every variant of a prelude type" covers `Less`/`Equal`/`Greater`. There is no list to memorize, and none to update when the prelude grows.
- **Concern:** A future prelude enum with a common variant name (such as `Empty`) would reserve that name in every module, so prelude additions need this rule in mind.

**Q6**
- **Vote:** Q6-warn, sub-choice Q6-warn-W1011
- **Reasoning:** `let Red = 5` and then `Red => Red` in one arm reads the variant on the left and the local on the right. No TS or Python developer expects that. One warning code for "a binding hides a variant" is one concept. It fires only on locals named like a variant, which normal snake_case code never has.
- **Concern:** If the warning covers dependency variants, a `--strict` build gains a semver exposure; I accept devops's limit (same-package and prelude variants only) if the panel prefers it.

**Q7**
- **Vote:** Q7-scrutinee
- **Reasoning:** min's case decides it. `let Red = 5` is a pattern with an `Int` scrutinee. Under the global-unique wording it would find `Color.Red` and fail, so the local shadowing that every other answer depends on would break. "A variant of the scrutinee type, else a new binding" is also the rule a user can predict from the line they read.
- **Concern:** A misspelled variant (`Gren =>`) stays a catch-all binding; that needs its own friction ticket.

**Q8**
- **Vote:** Q8-lang
- **Reasoning:** I move from Q8-tools. A semantic sentence ("a bare name at a site denotes exactly one entity, determined statically") is enough for a conformance test to catch the typecheck/codegen split. A §6 tooling sentence can cover the language server and `blink query`.
- **Concern:** Without the §6 sentence, hover and the binary can still disagree in practice, so the §6 sentence should land with this change.

##### PLT

**Q1 — Q1-N**
Reasoning: A variant lives in `T.` (decision 4). §2.12.1 defines a namespace as "at most one declaration per name". A variant-as-value model needs an exception for two enums that share `Pending` (decision 2), so it is not that namespace. Q1-N gives the same diagnostics with no exception.
Concern: Readers may still think of a bare variant as a module value. The spec text must say "collision check, not namespace membership" in plain words.

**Q2 — Q2-E1016**
Reasoning: Decision 4 already reports a clash between a variant and a `T.` function as E1016, so E1016 already covers a clash across namespaces. Decision 2 limits E0518 to struct vs variant.
Concern: The text "declared twice" fits a prelude variant poorly. The message must label the variant as a variant of `T` (or "a prelude variant of `Option`").

**Q3 — Q3-package**
Reasoning: §3.4 global-unique already makes every variant in a package reachable bare from every module, with no import. So a value and a variant in one package are peers at one level, and peers collide (decision 5). The reach of the check then equals the reach of the resolution, and it copies the §2.12.3 split (E1016 across the package, a different rule across packages). With Q3-module, a cross-module helper `fn Leaf(n: Int) -> Wrap` in one package wins silently, because no type error fires.
Concern: If Q3-module wins, that silent in-package case stays open. sys's invalidation cost under Q3-package is real but bounded: one package-wide set of variant names.

**Q4 — Q4-scope**
Reasoning: Outside the Q3 reach, the variant is in a scope under the module (decision 5), so this is a shadow, resolved by lexical order. A hint must not move a name past a binding. The hint can be an unsolved metavariable, and resolution would then depend on the order in which constraints are solved. Q4-ambig leaves the value with no spelling that works.
Concern: A dependency helper and a downstream value of the same name and same result type resolve silently to the value. The Q4w warning or the type-error help must carry that case.

**Q4w — Q4w-imported**
Reasoning: The hazard exists only when the module can mean the variant, in practice when it imports the type. Warning on every variant of every dependency is noise with no link to the user's code. W1000 already warns for the analogous dependency-under-module shadow.
Concern: devops is right that a `--strict` build promotes the warning. A dependency that adds a variant to a type that the module imports can then fail a strict build. That is the cost of an opt-in mode, not of the language.

**Q5a — Q5a-E1016**
Reasoning: The prelude variants carry the carrier hint and the `?`/`??` machinery. A shadow would change a resolution mechanism across the whole module, not one name. Treating them as declared in every module reuses the Q3 rule with no new code.
Concern: The E1016 message must not say "declared twice" with a span that points at nothing. It needs a "prelude variant of `Option`" label.

**Q5b — Q5b-local-as-Q6**
Reasoning: Decision 5 makes a local shadow legal, and patterns are not affected (Q7). One rule for all locals.
Concern: A local `let None = 3` reads as odd in code. A lint can cover it if friction appears.

**Q5c — Q5c-kind**
Reasoning: State the rule by kind: every variant of every prelude enum. The facts note confirms that `Less`, `Equal` and `Greater` are prelude constructors. A list needs maintenance; a rule by kind does not.
Concern: A future prelude enum with common variant names (`Empty`, say) widens the ban with no new vote. Prelude additions should be checked against it.

**Q6 — Q6-silent**
Reasoning: The split is well-defined. Patterns never read values, so each position has one candidate. Decision 5 gives no warning for any other local shadow. A warning is a lint question and does not change the semantics.
Concern: aiml's `Red => Red` arm is a real reading trap. If silent wins, the lint ticket that devops asked for must be filed.

**Q7 — Q7-scrutinee**
Reasoning: min is right, and this is more exact than my own text. In a pattern the expected type (the scrutinee) is always present, so global-unique adds no information. Global-unique could only turn a binder on an unrelated type (`Red` on an `Int`) into a type error. Resolving only against the scrutinee type keeps pattern meaning local, and it settles `let Only = x` with no extra rule.
Concern: A misspelled variant (`Gren =>`) still binds as a catch-all. That needs a separate friction ticket (aiml).

**Q8 — Q8-lang**
Reasoning: "A bare name at a site denotes exactly one entity, and the compiler determines it statically" is a semantic property. A conformance test can cite it, and it rules out the typecheck/codegen split. The names of phases and tools are implementation detail and do not belong in sections/ §2/§3. A §6 sentence for the LSP and `blink query` is fine.
Concern: Without a test that runs the `fn Leaf(n: Int)` and `let c = Red` cases end to end, the sentence will not catch the codegen bug. The codegen ticket must carry those tests.

##### DevOps

**Q1: Q1-N**
**Reasoning:** The LSP and the diagnostics need "one meaning or one error" at each site. They do not need the claim that a variant is a member of the value namespace. Y-mod and Y-pkg each need an exception sentence for `Pending` in two enums, and every hover text and error message would have to explain that exception.
**Concern:** The spec text might keep the word "binds" from DV-1 or M1 by accident. The text must say "collides with".

**Q2: Q2-E1016**
**Reasoning:** Users already know E1016 from `fn f` + `fn f`, and §2.12.3 already uses E1016 for a variant against a `T.` function. A label "a variant of `Color`" tells the user which kind of pair collided.
**Concern:** The headline "`Red` is declared twice" can read wrong when one side is a variant, so the message must name the variant in its label or headline.

**Q3: Q3-package**
**Reasoning:** Inside a package, §3.4 global-unique already reaches every variant from every module, so the check must cover the same reach as the resolution. One diagnostic appears at the declaration, in code the author owns. Without it, `fn Leaf(n: Int) -> Wrap` wins in silence. This copies the decided §2.12.3 split.
**Concern:** sys's invalidation cost is real: a new variant in module A makes the daemon and the LSP recheck the declaration checks of every module in the package. The daemon dependency graph must record this edge, or warm and cold checks will disagree.

**Q4: Q4-scope**
**Reasoning:** Under Q3-package, this rule applies only to dependency variants. Decision 5 already places a dependency under the local module. The lookup is a lexical walk, so hover does not need the solved type. The type-error help that names `T.V` gives the fix in one edit.
**Concern:** The help line must fire only when the hint names an enum that has that variant. Otherwise it suggests `Color.Red` at unrelated type errors.

**Q4w: Q4w-imported**
**Reasoning:** I withdrew the general W1011 because `--strict` can promote it, and then a new dependency variant could break a build. plt's limit removes that risk. When a module imports `Color`, a new variant in `Color` already breaks downstream exhaustive matches, so a warning on the same change adds no new semver cost. It also warns only where the user can see both names.
**Concern:** Users may read an import of the type through a whole-module import (`import pal`) differently, so the spec must say whether a qualifier import counts.

**Q5a: Q5a-E1016**
**Reasoning:** "The variants of a prelude enum count as declared in every module" adds no new code and no list to maintain. Its error recovery and suggestion-only fix are the same as for every other E1016.
**Concern:** The message must say "`Some` is a prelude variant of `Option`", not "declared twice in module `main`" (web's point). Otherwise the diagnostic points at nothing the user wrote twice.

**Q5b: Q5b-local-as-Q6**
**Reasoning:** One rule for all locals. If Q6-warn wins, a local `let None` gets the warning. Decision 5 keeps local shadowing legal.
**Concern:** If Q6-silent wins, a local `let None = 3` hides `None` with no diagnostic at all.

**Q5c: Q5c-kind**
**Reasoning:** A rule stated by kind covers `Less`, `Equal` and `Greater` (§10.6 lists them as prelude constructors) and any future prelude enum. A list would drift away from the prelude table.
**Concern:** None that matters.

**Q6: Q6-warn, sub-choice Q6-warn-local**
**Reasoning:** In `Red => Red`, the left side is the variant and the right side is the local (aiml measured this). One warning at the binding, with the note "`Red` in a pattern still means `Color.Red`", prevents that trap for the cost of one code. I limit it to same-package variants, prelude variants and variants of imported types, the same reach as Q4w, so a dependency release cannot add it to a strict build. I accept Q6-warn-W1011 if it has that same reach.
**Concern:** If silent wins, file it as a lint ticket so the trap gets a diagnostic later.

**Q7: Q7-scrutinee (I change from Q7-plt)**
**Reasoning:** min found a real defect in plt's text. With global-unique in patterns, `let Red = 5` (scrutinee `Int`) would find `Color.Red` and fail, which contradicts the local shadowing we keep in Q6. With scrutinee-only, the LSP can classify a pattern name from the scrutinee type alone, and a far-away variant can never change a pattern.
**Concern:** A misspelled variant (`Gren =>`) is still a catch-all binding. It needs a follow-up lint, for example an unused or unreachable-arm warning that names the near match.

**Q8: Q8-lang, with plt's §6 tooling sentence (I change from Q8-tools)**
**Reasoning:** The language sentence ("a bare name at a site denotes exactly one entity, determined statically") makes the typecheck/codegen split a spec violation that a test can catch. The §6 sentence then binds `blink query` and the LSP to the same answer. This gives the guarantee I asked for without a list of compiler phases in §2 or §3.
**Concern:** If the §6 sentence is dropped, nothing in the spec says hover and query must agree with the binary.

##### AI/ML

**Q1 — Q1-N**
Reasoning: A model learns one sentence: a variant lives in `T.`, and module values have a collision check against it. The Y options need an exception clause for two enums that share a variant name, and every exception is a decision point that the spec alone teaches badly.
Concern: Spec text could still say "binds" somewhere by habit; the edit must use "collides with" in every place.

**Q2 — Q2-E1016**
Reasoning: E1016 is the code a model already sees for `fn f` + `fn f`, and §2.12.3 already uses it package-wide for a `T.` clash. One code for "two things own one bare name" is the cheapest to learn.
Concern: The message "declared twice in module `main`" is wrong when the variant is in another module; the label must name the variant's module and type.

**Q3 — Q3-package**
Reasoning: §3.4 global-unique already makes every variant of the package reachable bare in every module, so the collision check must cover the same reach. Under Q3-module, `fn Leaf(n: Int) -> Wrap` in one module and variant `Leaf` in another give no error and no type error: wrong code that compiles, the worst case for generated code. Package reach puts one error at the declaration the author owns.
Concern: If Q3-module wins, the in-package silent case stays open unless Q4w covers same-package variants (Q4w-any).

**Q4 — Q4-scope**
Reasoning: Under Q3-package, this applies only to dependency variants, where decision 5 already puts the dependency under the module. A lexical walk gives one meaning without type inference, so hover, `blink query` and the model agree. The hint never moves a name past a binding, which keeps resolution free of solve order (plt).
Concern: The type-error help ("write `Color.Red`") is the only signal at the use site, so it must always fire when the hint names an enum that has that variant.

**Q4w — Q4w-imported**
Reasoning: When the module imports the variant's type, a bare `Leaf(2)` is a likely attempt to build the variant, and a helper that returns the same enum gives no type error. The warning closes that silent case where it matters, and the import limit stops noise from unrelated dependency variants (plt). If Q3-module wins, I take Q4w-any instead, so the in-package case is not silent.
Concern: Under `--strict`, a dependency that adds a variant to a type the module imports can turn this warning into a build break (devops).

**Q5a — Q5a-E1016**
Reasoning: I move from E1017 to E1016. "The variants of a prelude enum count as declared in every module" (sys) needs no new code and no list, and it makes the model's rule the same as for user variants. What matters for AI is that `Some(x)` can never mean a user function; both error options give that.
Concern: The message must say "a variant of the prelude type `Option`", not "declared twice", or a model will search the file for a second `Some`.

**Q5b — Q5b-local-as-Q6**
Reasoning: I move from local-error. One rule for every local is easier to learn than a special local rule for seven names. With my Q6 vote, a local `let None = 3` gets the warning, which is enough because the hide stays inside one function.
Concern: If Q6-silent wins, `let None = 3` silently changes every later `None` in that function, including in `??` operands.

**Q5c — Q5c-kind**
Reasoning: "Every variant of every prelude type" has no list to memorize and stays correct if the prelude grows. §10.6 lists `Less`, `Equal` and `Greater` as prelude constructors, and web measured `fn Less` as dead code today.
Concern: None material; the spec must point to the §10.6 prelude table as the single source.

**Q6 — Q6-warn, sub-choice Q6-warn-W1011**
Reasoning: `Red => Red` with a local `let Red = 5` means the variant on the left of `=>` and `5` on the right, in one line. A model that reads or writes that line has no cue. One warning code for "a binding hides a variant", at module or local scope, is one concept.
Concern: If Q6-silent wins, the pattern-vs-expression split stays unflagged; then file it as a lint ticket (devops), not drop it.

**Q7 — Q7-scrutinee**
Reasoning: In a pattern, the scrutinee type is always known, so the variant set is exactly the variants of that type. No program-wide search means a variant added in a distant module can never turn a working binding pattern into an error. It also answers `let Only = x` with no extra rule (min).
Concern: A misspelled variant (`Gren =>`) still becomes a catch-all binding; that trap needs its own friction ticket.

**Q8 — Q8-lang**
Reasoning: I move from Q8-tools. "A bare name at a site denotes exactly one entity, and the compiler determines it statically" (plt) is a language rule that a conformance test can cite, and plt's §6 sentence can carry the tool promise. Naming compiler phases in §2/§3 is an implementation detail.
Concern: If the §6 tooling sentence is not written, hover and `blink query` can still disagree with the binary with no spec text to cite.

##### Minimalism

**Q1 — Q1-N**
Reasoning: A variant lives in `T.`, and the declaration error is a collision check. This needs no exception clause in §2.12.1, so it is the shortest correct text. My M1 wording needed a carve-out for two enums that share a variant name, which is a hidden second rule.
Concern: Spec writers may drift back to "binds a value name" wording in examples or diagnostics labels; the labels should say "a variant of `Color`", not "declared twice".

**Q2 — Q2-E1016**
Reasoning: Decision 4 already uses E1016 for a variant against a `T.` function, so E1016 needs no new meaning. E0518 is scoped to struct vs variant by a 6-0 decision.
Concern: The headline "`Red` is declared twice in module `main`" reads oddly when the two sites are a variant and a `fn`, or are in two modules; the message text must name both kinds.

**Q3 — Q3-package (I change from Q3-module)**
Reasoning: aiml's `fn Leaf(n: Int) -> Wrap` case is a silent winner inside one package, and under module reach the only fix for it is a new warning (Q4w-any). Package reach closes that hole with no new code, and it copies a precedent that already exists: the §2.12.3 `T.` check is E1016 package-wide. Fewer concepts in total: one error, one reach that the spec already uses, no warning.
Concern: sys's point holds: a new variant in one module now changes the declaration check of every module in the package, which costs incremental/daemon recheck work and can break a `fn` in a file that never imports the variant's type.

**Q4 — Q4-scope**
Reasoning: Under Q3-package this applies only to variants of other packages, and decision 5 already makes a dependency a scope under the local module. So no new rule is needed: the existing scope walk decides, and a dependency release can never break or change a downstream site. The type-error help naming `T.V` covers the site where it matters.
Concern: A downstream helper whose type matches the hidden dependency variant (the `fn Leaf -> Wrap` shape across packages) stays silent.

**Q4w — Q4w-none**
Reasoning: devops's own reason: `--strict` and `[lints]` can promote a warning to an error, so a warning on dependency variants brings back the semver break that Q3-package avoids. The cross-package hide is a decided nested-scope shadow (decision 5), and §2.2 gives no warning for other shadows. One more code is surface that this case does not need.
Concern: If the panel picks module reach for Q3, Q4w-none leaves the in-package silent hole open; my Q4w vote assumes Q3-package.

**Q5a — Q5a-E1016**
Reasoning: "The variants of a prelude enum count as declared in every module" uses the existing code and the existing rule. A dedicated E1017 adds a code and a new class of reserved names for a case that E1016 already describes.
Concern: The E1016 message must not say "declared twice in module `main`" with no first site in the user's file; it needs a label or note that names the prelude type.

**Q5b — Q5b-local-as-Q6**
Reasoning: A local is next to its uses, and decision 5 makes every function-local shadow legal. A second local rule just for these names is a new reserved-word class without need. Patterns are not affected (Q7), so `match` on `Option` stays correct.
Concern: A local `let None = 3` followed by `x == None` in that scope reads oddly. That case is rare, and a lint can cover it if friction shows.

**Q5c — Q5c-kind**
Reasoning: A rule stated by kind has no list to maintain and no list to learn. It covers `Less`/`Equal`/`Greater` automatically, and any future prelude enum with no spec edit.
Concern: The closed compiler-known table in §10.6 must stay the single source for "prelude type", so the rule cannot drift.

**Q6 — Q6-silent**
Reasoning: The local is next to its uses, and decision 5 gives no warning for any other function-local shadow. A warning is a lint question, not a semantic one; it can be added later from a friction ticket without a spec change. Two new W-code proposals (W1011 and LocalHidesVariant) show the surface cost.
Concern: aiml's `Red => Red` case (variant on the left, local on the right) will confuse some readers, and silence gives them no pointer.

**Q7 — Q7-scrutinee**
Reasoning: plt's text says "a variant when §3.4 resolves it", and §3.4 includes the program-wide global-unique step when the hint names no matching enum. Then `let Red = 5` (scrutinee `Int`, no hint match) would find `Color.Red` and fail, where today it binds. "A variant of the scrutinee type" is the rule sys, web and aiml already state in words, it has one step, and it answers `let Only = x` with no friction ticket.
Concern: If Q7-plt wins as written, the spec text may imply global-unique lookup in patterns, which would turn ordinary `let` bindings of capitalised names into errors.

**Q8 — Q8-note (second choice: Q8-lang)**
Reasoning: §3.4 already says "Resolution is static", and Q1–Q7 give each site one meaning, so the spec already implies one result. A sentence that names compiler phases or tools is implementation detail in sections/. If the panel wants a sentence, plt's single semantic line with no tool list is acceptable.
Concern: Q8-tools would put a list of internal phases and tools into the language spec, and that list will go stale.

#### Phase D — Round 2 on Q6, debate

Q6 tied 3-3 in Phase C, so the panel debated Q6 alone for one round.

##### Systems

I move from Q6-silent to Q6-warn, code W1011, with the same reach as Q4w.

Why I move. My Phase C reasons for silence were the cost of a new code and noise in generated code. The Q4w result removed the first reason: W1011 `ShadowedVariant` now exists for module-scope values. A local use of it adds no new code and no new concept. It is the same warning at a nested scope ("a binding hides a variant"). That answers min's surface-cost point: the cost is already paid. For generated code, `@allow(ShadowedVariant)` is enough.

The check costs one hash probe per local binding into the package variant table, which Q3-package already builds. It is compile-time only, with zero runtime cost and no change to the generated code.

plt and min both say the trap is real (`Red => Red`: variant on the left, local on the right). plt says it is "a lint question". In Blink, a warning code that the spec names is the lint. If we defer it to a ticket, we file the same W1011 later and the trap stays unflagged in the meantime.

Code: W1011 `ShadowedVariant`, one code for module and local scope (web, aiml).

Reach: the same as Q4w, as devops asks: variants of enums in the same package, prelude variants (Q5b sends locals named `Some`/`None`/... here), and variants of types that the module imports. A dependency variant that reaches the module only by the global-unique search adds no warning. So a dependency release cannot add a warning to a `--strict` build. This is devops's semver point, and it makes devops's Q6-warn-local and W1011 the same option.

Note text: "`Red` in a pattern still means `Color.Red`" (devops).

##### Web/Scripting

**Vote: Q6-warn, code W1011 `ShadowedVariant`, with devops's reach:** variants of the same package, prelude variants, and variants of imported types. This is the same reach as Q4w, so a dependency release can never add the warning to a `--strict` build.

**To sys, plt, min ("decision 5 gives no warning for any other local shadow"):** this shadow is not like the others. An ordinary shadow such as `let x = x + 1` replaces the meaning of `x` everywhere below it. A local `Red` replaces it only in expressions, while `Red` in a pattern keeps the variant (Q7-scrutinee). So one token has two meanings in one scope, split by position. No other shadow in Blink does that, so decision 5's silence does not cover it. All three silent ballots name `Red => Red` as a real trap in their own Concern field. I agree with that, and it is the case the warning exists for.

**To min ("surface cost: two new W-codes"):** Q4w-imported already decided that W1011 exists, at the module-scope declaration. Q6-warn-W1011 adds no code. It applies the same message ("a binding hides variant `Color.Red`") at one more scope. Under devops's reach, Q6 and Q4w cover the same variants, so the user learns one rule: a binding that hides a variant gets W1011, at any scope.

**To plt ("a lint question, not semantics"):** this is true, but a warning is still something users see. In my experience, "a lint ticket later" usually means a beginner hits the trap first and asks on a forum. The note "`Red` in a pattern still means `Color.Red`" answers that question at the line where it starts. It costs nothing in snake_case code, and `@allow(ShadowedVariant)` records a deliberate choice.

If silent wins, I join devops and aiml: file the lint ticket, do not drop it.

##### PLT

I change my vote to **Q6-warn, code W1011 `ShadowedVariant`, with the same reach as Q4w**.

Two facts changed after Phase C.

1. **Q4w-imported won, so W1011 now exists.** min's cost argument ("two new W-codes") no longer applies. A local warning that uses W1011 adds no code and no concept. It is the same diagnostic ("a binding hides a variant") at an inner scope.

2. **This shadow is partial, and no other shadow is.** I argued in Phase C that decision 5 has no warning for other local shadows. But every other local shadow hides a name in *all* positions of its scope. With Q7-scrutinee, a local `Red` hides the variant in expressions and not in patterns. So in its own scope, one name has two meanings that depend on position. aiml's `Red => Red` arm is the minimal case. The semantics are still well-defined (I hold that). But decision 5's "no warning for a local shadow" covered total shadows only. A partial shadow is a new case, so the precedent does not settle it. Reply to sys and min: your Phase C concerns name exactly this trap.

**Reach** (devops's limit, equal to Q4w): variants of enums in the same package, variants of prelude enums, and variants of types that the module imports. A variant of a dependency type that the module does not import never triggers it. So a dependency release cannot add W1011 to a `--strict` build of a module that does not use that type.

**Shape:** one warning at the binding (a `let`, a parameter, a closure parameter, a pattern binder). The note says "`Red` in a pattern still means `Color.Red`". The help says to rename the local or write `Color.Red`. `@allow(ShadowedVariant)` on the `fn` suppresses it. A pattern binder warns only when the scrutinee type does not have that variant, because under Q7 a pattern `Red` with a scrutinee that has it is the variant, not a binder.

##### DevOps

**Vote: Q6-warn, code W1011 `ShadowedVariant`, the same code as Q4w.** I drop my separate `LocalHidesVariant`, so web, aiml and I now agree on the sub-choice.

**Reach:** a local binding (`let`, a parameter, a closure parameter or a pattern binder) whose name is equal to one of these:
1. a variant of an enum in the same package;
2. a variant of a prelude enum (Q5b sends `let None` here);
3. a variant of a type that the module imports, the same reach as Q4w.

It never covers a dependency variant that the module does not import. So a dependency release cannot add this warning to a `--strict` build.

**To min ("surface cost: two new W-codes"):** that cost is gone. Q4w-imported already passed, so W1011 exists. Q6-warn adds a second place where W1011 fires, not a new code. The rule stays one sentence: "a binding that hides a variant gets W1011."

**To sys, plt, min ("decision 5 gives no warning for any other local shadow"):** decision 5 makes a shadow legal. It does not make it silent. W1000 and W1010 are warnings on legal shadows. The question is whether this shadow is a trap, and all three of your Concern lines say it is (`Red => Red`: the variant on the left, the local on the right).

**To plt ("a warning is a lint question"):** in Blink, a lint is a W-code in the spec. W0734 `SealedMethodNameCollision` is a precedent: a spec-defined warning that does not change semantics. "File a lint later" means this panel or a later one writes the same rule, after users have already written the trap into code that becomes training data.

**Prelude locals:** under Q5b, Q6-silent means `let None = 3` changes every later `None` in the function, including `??` operands, with no diagnostic (aiml). Of the outcomes still open in this round, this one is the worst for a reader.

**Tooling cost:** the warning fires once, at the binding, with the note "`Red` in a pattern still means `Color.Red`". `@allow(ShadowedVariant)` on the `fn` turns it off. The help (rename the local) is a suggestion only, never machine-applicable.

##### AI/ML

**Vote: Q6-warn. Code: W1011 `ShadowedVariant`, the same code as Q4w. Reach: the same as Q4w and devops's limit. It covers variants of the same package, prelude variants, and variants of types that the module imports. A dependency release can never add it to a `--strict` build.**

1. **All three silent voters name the trap in their own Concern.** sys: "a reader can miss it". plt: "a real reading trap". min: "silence gives them no pointer". No silent vote argues that the trap is not real. They argue only that it can wait.

2. **Q5b now depends on Q6.** Q5b-local-as-Q6 won, so this vote also decides `let None = 3` in a function. Under Q6-silent, every later `None` in that function, including `??` operands, silently means `3`. The panel made a module-scope `fn Some` an error because prelude variants carry language machinery. A silent local hide of the same names is the same hazard in a smaller scope.

3. **To sys, plt and min ("decision 5 gives no warning for any other local shadow"):** Other local shadows do not split meaning by position. A local `x` that hides a module `x` means the local in every position. A local `Red` means the local in an expression and the variant in a pattern (Q7), sometimes in one arm. No other shadow in Blink has this property, so decision 5 is not a precedent here.

4. **To plt ("a lint question, does not change the semantics"):** W1010 and W1000 do not change semantics either, and the spec states both. In Blink, a lint *is* a W-code. "Later" means that the same code ships later, after models have already learned the trap from code that compiles without a diagnostic.

5. **To min ("two new W-code proposals show the surface cost"):** That cost is gone. I merged LocalHidesVariant into W1011, and devops accepts W1011. Q4w-imported already creates W1011, so Q6 adds no code. It adds one more place where the existing code fires.

##### Minimalism

I change my vote to Q6-warn, sub-choice W1011, with the same reach as Q4w.

My Phase C vote for silent rested on one cost: a new W-code for a shadow that decision 5 allows. Phase C removed that cost. Q4w-imported won, so W1011 `ShadowedVariant` now exists for a module-scope value that hides a variant. The question is no longer "add a code?" but "does the one existing code apply at one scope or at two?"

Under silent, the rule a reader must learn is: "a module-scope binding that hides a variant warns, a local binding that hides the same variant does not." That is an asymmetry with no reason behind it, and the local case is the worse one, because aiml's `Red => Red` puts both meanings in one arm. One sentence for both scopes is shorter than two: "A binding that hides a variant in reach gets W1011."

Code: W1011, one code for module and local. No separate `LocalHidesVariant` (against devops's sub-choice only on the name; I agree with its reach).

Reach: the same variants that Q3/Q4w already name, and no others:
- variants of enums in the same package,
- prelude variants (Q5b sends locals here),
- variants of types the module imports.

A variant of a dependency type that the module does not import never adds the warning, so a dependency release cannot fail a `--strict` build through a local (devops's semver point).

To sys and plt: I agree the semantics are well-defined and that each position has one candidate. The warning does not change semantics; it costs no new concept now that W1011 exists, and both of you named `Red => Red` as a real trap in your own concerns. To devops: same reach as yours, one code instead of two.

#### Phase D — Round 2 on Q6, vote

Result: Q6-warn-W1011, 6-0.

##### Systems

**Vote:** Q6-warn-W1011

**Reasoning:** W1011 already exists for module-scope values (Q4w), so the local case adds no new code and no new concept. The check is one hash probe per local binding into the package variant table that Q3-package builds, with zero runtime cost and no change to generated code. The reach (same-package variants, prelude variants, variants of imported types) means a dependency release cannot add the warning to a `--strict` build.

**Concern:** Code generators and macros that emit locals named like variants will need `@allow(ShadowedVariant)`, and the spec must say where that attribute may appear for a local binding.

##### Web/Scripting

**Vote:** Q6-warn-W1011. Reach: variants of enums in the same package, prelude variants, and variants of types the module imports, the same as Q4w.

**Reasoning:** A local that hides a variant changes the name only in expressions, never in patterns, so `Red => Red` reads two ways in one arm. W1011 already exists from Q4w, so the user learns one sentence: "a binding that hides a variant gets W1011", at any scope. Under Q5b, this also flags `let None = 3`, which would otherwise change every later `None` in the function with no diagnostic. I support plt's shape detail: a pattern binder warns only when the scrutinee type does not have that variant.

**Concern:** Code generators that emit PascalCase locals will need `@allow(ShadowedVariant)`, and the warning text must say why, with the note "`Red` in a pattern still means `Color.Red`", or users will just silence it.

##### PLT

**Vote:** Q6-warn-W1011

**Reasoning:** Under Q7-scrutinee, a local named like a variant shadows it only in expressions, not in patterns. This partial shadow is a new case, and decision 5's precedent for no warning covered only shadows that hide a name in all positions. W1011 already exists from Q4w, so the warning adds no code and no concept. Its reach equals Q4w (variants of enums in the same package, prelude variants, variants of types the module imports), so a dependency release cannot add it to a strict build of a module that does not use that type.

**Concern:** The spec text must state that a pattern binder warns only when the scrutinee type does not have that variant. Otherwise implementers may warn on a pattern that is the variant itself.

##### DevOps

**Vote:** Q6-warn-W1011

**Reasoning:** W1011 already exists from Q4w, so the rule is one sentence at both scopes: "a binding that hides a variant in reach gets W1011". Its reach is the same as Q4w: variants of enums in the same package, prelude variants and variants of imported types. So a dependency release cannot add it to a `--strict` build. This is a partial shadow (expressions only, not patterns), and decision 5's silence does not cover it (web, plt). The note "`Red` in a pattern still means `Color.Red`" explains the `Red => Red` trap at the line where it starts.

**Concern:** The spec text must keep plt's detail. A pattern binder warns only when the scrutinee type lacks that variant, because when it has the variant, Q7 makes the name the variant, not a binder. Without this detail the warning fires on correct `match` arms.

##### AI/ML

**Vote:** Q6-warn-W1011. Reach: variants of enums in the same package, prelude variants, and variants of types that the module imports (the same reach as Q4w). No warning for a dependency variant that the module does not import.

**Reasoning:** A local `Red` is a partial shadow (plt). It means the local in an expression and the variant in a pattern, so `Red => Red` has two meanings in one arm and no cue for a reader or a model. Q4w already created W1011, so a model learns one sentence for both scopes: "a binding that hides a variant gets W1011". Under Q5b, the warning also covers `let None = 3`, which would otherwise silently change every later `None`, including `??` operands.

**Concern:** For a pattern binder, the warning must fire only when the scrutinee type has no variant of that name (plt). Otherwise a correct variant pattern gets a false warning, and a false warning teaches a model to ignore W1011.

##### Minimalism

**Vote:** Q6-warn-W1011 (reach: variants of enums in the same package, prelude variants, variants of types the module imports).

**Reasoning:** Q4w-imported already created W1011, so a local warning adds no code and no concept. It extends one existing rule to one more scope: "a binding that hides a variant in reach gets W1011". plt and web showed that decision 5 does not settle this case: every other local shadow is total, but under Q7-scrutinee this one hides the variant in expressions and not in patterns. The same reach as Q4w keeps dependency releases out of `--strict` builds.

**Concern:** The pattern-binder case must follow plt's limit (warn only when the scrutinee type does not have that variant), or the spec text will warn on bindings that are in fact variant patterns.

#### AI-first review

| Criterion | Result | Note |
|---|---|---|
| Learnability | pass | One rule per site: values before variants in expressions, the scrutinee type in patterns |
| Consistency | pass | E1016 already covers module-scope collisions; W1011 follows the W1000/W1010 shadow pattern |
| Generability | pass | Generated code that names a value like a variant fails loudly in its own package |
| Debuggability | pass | Depends on the E1016 labels naming the variant's type and module, and on the `T.V` help |
| Token efficiency | pass | No new syntax; bare variants stay bare |

0 of 5 failed.

### Final Spec

```blink
// package app; package pal declares `pub type Tone { Warm, Cool }`
import pal.{Tone}

type Color { Red, Green }

fn Red() -> Int { 1 }        // error[E1016]: `Red` collides with variant `Color.Red`
let Ok = 5                   // error[E1016]: `Ok` collides with variant `Result.Ok` (prelude)
const Warm = 1               // warning[W1011]: hides variant `Tone.Warm`

fn name(c: Color) -> Str {
    let Green = 2            // warning[W1011]: hides variant `Color.Green`
    match c {
        Red => "red"         // the variant: the scrutinee is a Color
        Green => "green"     // the variant, not the local
    }
}
```

- A variant is not in the value namespace. A module-scope `let`, `let mut`, `const` or `fn` collides
  (E1016) with a variant of any enum in the same package and with any prelude variant (§2.12.1).
- A bare use looks for a local, then a module-scope value or import, then a variant by §3.4. The first
  step that finds the name decides (§3.4 *Values come first*).
- In a pattern, a bare name is a variant only when the scrutinee type has that variant (§3.5).
- W1011 `ShadowedVariant` marks a binding that hides a variant of the same package, of the prelude, or
  of a type the module imports through an import entry (§10.6 *Shadowing Rules*).
- A bare name at a site denotes exactly one entity, and the compiler determines it statically (§3.4);
  `blink query` and the language server report that entity (§8.2).
- Governing text: §2.12.1, §3.4 *Variant Construction*, §3.5 *Pattern Forms*, §10.5 *Import Errors*,
  §10.6 *Prelude Types* and *Shadowing Rules*, §8.2.
