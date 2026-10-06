[< All Decisions](../DECISIONS.md)

# Opaque Types and Type-Scoped Declarations — Design Rationale

Resolves the spec gap "private fields / opaque stdlib types — make MsgFlags and Instant opacity a stated rule". Before this decision, `MsgFlags` and `Instant` were opaque only by compiler knowledge. The spec had no rule for fields, and no way to declare a type-scoped constant such as `MsgFlags.NONE`. The stdlib made `Duration.ms(…)` work with free functions named `Duration_ms`, a convention that was not in the spec and did not work for user code.

Facts given to the panel (measured on gen1):
- A user `pub type T { x: Int }` in module `a` can be built, matched and read from module `main` with no error. Fields are fully public.
- `impl T { pub fn make() -> T }` is rejected (no inherent impls).
- A user `pub fn T_make()` called as `T.make()` gives "method `make` resolves to nothing".
- A user `pub const T_ZERO` used as `T.ZERO` gives an internal compiler error.

## Result

| Question | Result | Vote |
|----------|--------|------|
| Q1 How a type hides its representation | `opaque` modifier on the type; the whole body is hidden outside the declaring module | **6-0** |
| Q2 Type-scoped constants | Top-level `pub const T.NAME = <const expr>`, only in the module that declares `T`; a const reference in §2.21 | **6-0** |
| Q3 Type-scoped functions | Decided now: `pub fn T.name(...)` with no receiver, same ownership rule, an explicit amendment to §3c No Inherent Methods | **6-0** |
| V1 Patterns outside the module | No pattern at all, `T { .. }` included | **6-0** |
| V2 Opaque enums | An opaque enum hides all of its variants | **6-0** |
| V3 Spelling | Contextual word: `pub opaque type` | **6-0** |
| V4 Error text | Names the type and the owning module, never the hidden field (E1003) | **6-0** |
| V5 Derived Debug | Informative note only: a derived `Debug` prints hidden fields; write it by hand to hide them | 3-3 (C) → 4-2 STATE (D; Web, PLT for NORULE). All six accept the note as non-normative |
| V6 Annotation on `const T.NAME` | Same rule as a plain `const` | **6-0** |
| V7 Name clash in `T.` | One `T.` namespace: E1016, checked across the package; a trait impl from another package is E0522 at the use site | **6-0** (sub-point **6-0**) |
| V8 Constants on generic types | Not for now | **6-0** |
| V9 Owner of builtin-type constants | The prelude | **6-0** |
| V10 Combined flags | Out of scope, no follow-up ticket; a combined default is its own constant | **6-0** |
| V10 sub-point | §2.21 states in present tense that an operator on a user type is a trait call and is not admitted; no "never" | 4-2 for "never" (C) → D labels 2 YES (DevOps, Min) / 4 NO (Sys, Web, PLT, AI/ML); **all six** back present-tense text with no "never" |
| C1a Value semantics | Semantic text only: `opaque` changes visibility, not value semantics, and is not `@ffi.opaque`; C layout goes to codegen notes | 3-3 on C layout text (C) → **6-0** SEMANTIC-ONLY (D) |
| C1b Check site | Against the source module, not the mono site | **6-0** |
| C1c Aliases | An alias does not open the type | **6-0** |
| C1d Const compare | `==` / `<` on an opaque type in a const expression outside its module is an error | **6-0** |

The user signed off on the tally, including the V5 reading (an informative note).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Text below is verbatim from each panelist. Only heading levels were changed.

#### Phase A — Independent proposals

##### Systems

Frame: privacy and type-scoped constants are compile-time rules. Each must cost zero at run time, keep the full struct layout visible to C, and fold to a literal. The C side must never see a difference.

---

**P1 (privacy). Per-field `pub`. Fields are private by default.**

```blink
// std.time
pub type Instant {
    nanos: Int              // private to std.time
}

pub type Point {
    pub x: Int
    pub y: Int
}
```

Rules (checked against the module of the source text, not the module where mono instantiates it):
- Read or write `v.f` outside the module: `f` must be `pub`.
- Struct literal `T { ... }` outside the module: every field must be `pub`. A spread `T { x: 1, ..base }` follows the same rule, because it copies the hidden fields.
- Struct pattern outside the module: it can name only `pub` fields. If the type has a hidden field, the pattern must end in `..`.
- A type with no `pub` field and no `pub` constructor fn is opaque. `Instant` and `MsgFlags` drop out of the compiler's special-case list. They become plain types.
- Enum variants and their payloads take the visibility of the type. To hide a representation, use a struct with a private field. That gives one way to do it.

What the hardware sees: nothing changes. The C struct stays complete in the header, so `Instant` passes by value in registers and lives on the stack. This is the main win over the C/pimpl idiom, where an opaque type must be an incomplete type behind a heap pointer. Inlining and `-O2` still see the field. Generic code that touches a private field is checked once, at its own definition, before mono. So instantiating it from another module is legal and costs nothing.

Tradeoffs: this is consistent with §2.12 (items are private by default), and it is what the B1 voters asked for. The cost is migration. Every stdlib and test type whose fields callers use today needs `pub` on each field. That takes the 3-step dance: (1) parse and ignore field `pub`, (2) mark fields, (3) enforce. It also adds tokens to plain data types.

Cross-language: Rust works this way (private by default, struct update rejected when fields are hidden). Go uses case per field. Zig has no field privacy, and its users ask for it.

---

**P2 (privacy, opt-in fallback). An `opaque` modifier on the type.**

```blink
pub opaque type MsgFlags {
    bits: Int
}
```

All fields are hidden outside the module, with no literal and no pattern. Fields of a type without `opaque` stay public, as they are today. There is no migration and no per-field noise. The cost: it is all or nothing, and it adds a second visibility word next to `pub`. Codegen is the same as P1.

---

**P3 (constants). Type-qualified `const` in the type's own module.**

```blink
// std.libc
pub type MsgFlags {
    bits: Int
}

pub const MsgFlags.NONE: MsgFlags = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK: MsgFlags = MsgFlags { bits: 1 }

pub fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO {
    // ...
}

// std (built in)
pub const Float.INF: Float = 1.0 / 0.0
```

Rules:
- Only the module that declares `T` may declare `const T.NAME`. Builtin types (`Float`, `Int`) get theirs in the stdlib module that owns them.
- The RHS is a §2.21 const expression. It may use private fields, because it is in the defining module.
- §2.21's "reference to a const by name" also covers `T.NAME`, so it is legal as a keyword default, a field default, and a range bound.
- `T.NAME` lives in the type's value namespace. A clash with a static trait fn of the same name on `T` is E1016.
- These are not inherent methods. A constant has no dispatch, takes no `self`, and cannot shadow a trait method. The 4-1 "no inherent methods" reason does not apply.

What the hardware sees: no calls are allowed in a const, so there is no init order and no lazy-init guard. The C printer emits the folded literal at each use (`(blink_MsgFlags){1}`), or a `static const` for large values. A keyword default costs one immediate move. A per-call constructor function (`MsgFlags.none()`) would be a call unless inlined, and it is never const, so it cannot be a keyword default. That rules out the "methods only" route for this job.

Cross-language: Rust `impl T { const X }` (inherent), Zig `pub const X` inside the struct namespace, Go package-level `const` with a type.

---

**P4 (constants, rejected for now). Trait associated constants** (`trait Bounded { const MAX: Self }`). These monomorphize to a literal at zero cost and are useful for generic `T.MAX`. But `MsgFlags.PEEK` is not a trait property, and requiring a one-off trait per constant set is ceremony. YAGNI. This option stays open later, and it does not conflict with P3.

---

**Preference: P1 + P3.**

P1 because it matches §2.12's private-by-default rule, gives per-field control with no run-time cost, and keeps opaque types by value. That beats every heap-handle opaque scheme. The migration is a one-time cost. A rule that leaks fields by default is a latent bug in every library. If the panel judges the migration too heavy, P2 is my second choice. It is codegen-identical, and P1 could replace it later.

P3 because a keyword default needs a const, a const cannot be a call, and the hidden field forces the constant to live next to the type. One more point: the brief shows `T.ZERO` gives an ICE today and `T_make` naming is a hidden stdlib convention. Whatever we pick must replace the `Type_name` free-fn mangling hack with a spec rule. It must not add a second hidden convention.

##### Web/Scripting

###### Proposal 1 (preferred for privacy): an `opaque` modifier on the type

A struct is fully public, as it is today, unless the author marks the whole type `opaque`. Outside its defining module, an opaque type:

- has no struct literal (`T { .. }` construction): error;
- has no spread (`..t`): error;
- has no field read or write (`t.x`): error;
- has no destructuring pattern. Only a binding (`let x = t`) or a wildcard is allowed.

Inside the defining module, all of these work. Derived and impl'd traits (Eq, Ord, Hash, Display, Clone, Debug) still work everywhere.

```blink
// lib/std/time.bl
pub opaque type Instant {
    nanos: Int
}

// user module
fn main() {
    let a = Instant.from_epoch_secs(0)   // ok
    let b = Instant { nanos: 5 }         // error: Instant is opaque; use a constructor
    print(a.nanos)                       // error: Instant is opaque; it has no public fields
}
```

**Tradeoffs (DX):**
- The 90% case stays the same. Most Blink structs are plain data: configs, DTOs, JSON shapes, AST nodes. They should stay readable and buildable from anywhere with no extra `pub` on each field. Python, TS, Kotlin data classes, and Go-style records all work this way, so a JS or Python dev expects it.
- The spec already uses this word for Instant, MsgFlags, Template, TestError, and `@ffi.opaque`. One word gives all these special cases a single stated rule, and the error message can say exactly that word.
- One knob, two states. There is no question like "which fields did I mark?". This is easy for an AI model to generate and easy for a human to review.
- Cost: you cannot have a struct with some public and some private fields. I say YAGNI. Kotlin's `private val` is the only common case, and a getter in a trait impl covers it.
- Spelling: a contextual keyword (`pub opaque type`) or an annotation (`@opaque pub type`). I lean toward the keyword because it changes what the type means, not only how the compiler treats it. I accept either.

###### Proposal 2 (fallback): per-field `pub`, private by default (the Rust model)

```blink
pub type User {
    pub name: Str
    pub email: Str
    password_hash: Str     // private: blocks literal, pattern, read outside module
}
```

The rule: if any field is private, then outside the module you cannot use a literal, a spread, or a full pattern on the type.

**Tradeoffs:**
- Pro: it matches §2.12, "nothing leaves a module without `pub`". That is one rule for items and fields.
- Con: it changes every `pub type` with fields in the corpus. A codemod can do the change, but users get pub noise on every data struct.
- Con: it is the top Rust beginner complaint ("field is private" on a struct you just made pub). It will produce many Stack Overflow questions.
- Con: a type with three private fields and one `pub` field is a half-open thing that most users do not need.

I would accept this before any Dart/Python-style `_name` rule. Two privacy mechanisms (`pub` for items, `_` for fields) are worse than either one alone.

###### Proposal 3 (preferred for constants): `const` inside the type body

```blink
pub opaque type MsgFlags {
    bits: Int

    pub const NONE = MsgFlags { bits: 0 }
    pub const PEEK = MsgFlags { bits: 1 }
}

fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO
```

Rules:
- The right-hand side must be a §2.21 const expression. It can be a struct literal of its own type even when the type is opaque, because the body is in the defining module.
- The constant is reached only as `Type.NAME`, also inside the module. That gives one way to write it.
- `pub` follows the item rule, so you can write a private helper constant.
- Builtins use the same form in the prelude, for example `Float.INF` and `Int.MAX`.

**Tradeoffs:**
- Every web-adjacent language has this shape: TS `static readonly`, Kotlin `companion object { const val }`, Swift `static let`, Python class attributes. A JS dev reads `MsgFlags.NONE` and the declaration with no help.
- The constant sits next to the fields it depends on, and the "same module" rule needs no extra check.
- It does not break the No Inherent Methods rule. That rule exists to stop silent priority over trait *methods*. A const is not callable and traits have no associated consts today, so no conflict exists. If associated consts in traits come later, the panel needs a rule for that, and I would make a name clash with a trait const an error.
- Cost: the parser must tell `const` items from fields in a type body. The keyword makes this simple.

###### Proposal 4 (fallback for constants): dotted top-level name

```blink
pub type MsgFlags { bits: Int }
pub const MsgFlags.NONE = MsgFlags { bits: 0 }
```

This is easy to search with grep and keeps type bodies to fields only. But it looks like the `Duration_ms` mangling hack moved into the spec. People will then ask for `pub fn Duration.ms(...)`, which is an inherent method under a different name. I rank it second.

###### Sub-questions the panel should flag, not solve here

1. **Constructors for user types.** `Duration.ms(…)` and `Instant.from_epoch_secs(…)` work only through a stdlib-only `Type_name` mangling. A user who makes an opaque type has no way to give it a `T.make()` constructor. Opacity without this is half a feature: users can hide fields but cannot offer a named way in. This needs its own ticket. It may be the most-asked question after this lands.
2. **Combined flag constants.** `MsgFlags.PEEK | MsgFlags.WAITALL` is an operator call through a trait, so §2.21 does not allow it as a keyword default. A later flag will need either `|` added to const expressions for a named set of types, or a declared combined constant.
3. **Debug output of opaque types.** Should `@derive(Debug)` print the hidden fields? For DX I say yes. Debug is for humans, and hiding `nanos` from a log line only slows people down.

###### My preference

I prefer **Proposal 1 plus Proposal 3**. Data structs keep working with no change, the spec gets one stated rule for the word "opaque" that it already uses, and constants look the way every JS, TS, Kotlin, or Python dev already writes them. A new user learns both in under five minutes, and the compiler can give exact, fixable errors ("Instant is opaque; use a constructor").

##### PLT

I propose two rules plus one optional third. Rules 1 and 2 cover the two parts of the ticket. Rule 3 is a follow-up, and I would put it in a separate ticket.

###### Proposal 1 (preferred for sub-question 1): field-level `pub`, fields private by default

**Rule.** A struct field is private to the module that declares the type, unless the field has `pub`. This is §2.12 applied one level down: items are private by default, and now fields are too. Enum variants keep the visibility of their type (see the note below).

```blink
// std/time.bl
pub type Instant {
    nanos: Int
}

pub type Span {
    pub start: Int
    pub end: Int
}

// user module
let s = Span { start: 0, end: 4 }       // ok: every field is pub
let t = Instant { nanos: 5 }            // error: field `nanos` of `Instant` is private
let n = t.nanos                         // error: private field
match t {
    Instant { nanos: n } => n           // error: private field in pattern
    Instant { .. } => 0                 // ok: names no private field
}
let u = Span { start: 1, ..s }          // ok: Span has no private field
```

**Typing rules.** Let M be the current module and `vis(f)` the set of modules that can see field f.
1. **Literal:** `T { f1: e1, ... }` in M is legal only if *every* field of T, including fields that use a default, is visible in M. Defaults are part of the representation too. Also, if this rule were weaker, adding a private field later would break callers in an uneven way.
2. **Spread `..base`:** the same "every field" condition. Spread copies private fields and so can break a relation between fields (an invariant).
3. **Read and write `e.f`:** f must be visible in M.
4. **Pattern:** each field the pattern names must be visible in M. If T has a private field, the pattern must use `..`.
5. Shorthand construction (§2.15) is a literal and follows rule 1.

**Why this is sound.** It is the abstract-type rule from ML signatures and Reynolds' abstraction theorem. Code outside M can neither make nor look at the representation, so M can keep any invariant on it and can change the representation freely. Code outside M uses Eq, Ord, Hash and Debug only through impls, and derived impls are generated in M. So they need no exception.

**Enum variants stay public with their type.** A sum type is its constructors. If one variant were hidden, a `match` outside the module could never be complete, and exhaustiveness checking would not compose. To make an opaque sum, wrap it in a struct that has a private field. Thus the newtype `type Errno { Errno(Int) }` stays transparent. That is correct, because the spec chose it to be transparent.

**Tradeoffs.**
- This breaks existing code: every `pub type` that today has its fields used from outside needs `pub` on those fields. That needs a codemod (`blink fix`), plus the 3-step bootstrap dance for src/ and lib/std.
- Records with many fields that are only data (DTOs) get more tokens. Rust has the same cost.
- The privacy boundary is the module, not the package, which matches §2.12. std modules that share a representation must go through functions. I would not add `pub(package)` now (YAGNI).

**Alternative 1b (not preferred): fields stay public by default; `priv` hides one.** This needs no migration. But it is a second default that goes against §2.12's "private by default", and it brings a new keyword. I reject it on consistency grounds.

**Cross-language.** Rust: per-field `pub`, and functional record update is blocked when there are private fields, which is the same as my rule 2. OCaml: abstract `type t` in a signature. OCaml also has `private` types, which let outside code read and match but not construct; my rule 4 with `..` gives the matching half. Haskell: export the type without its constructors.

###### Proposal 2 (sub-question 2): type-qualified `const` declarations

**Rule.** The module that declares a type may declare constants in that type's namespace:

```blink
pub type MsgFlags {
    bits: Int
}

pub const MsgFlags.NONE: MsgFlags = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK: MsgFlags = MsgFlags { bits: 2 }

fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO {
    ...
}
```

**Rules.**
- The declaration must be in the module that owns `T`. The prelude counts as the owner of builtin types, so `pub const Float.INF: Float = 1.0 / 0.0` goes there.
- The right side is a §2.21 const expression evaluated in the owner's scope, so it may use private fields.
- §2.21 grows by one clause: "a reference to a const binding, bare or type-qualified (`T.NAME`)". A const has no free variables or effects, and it is a closed value that cannot be forged, so a private representation is safe to use from outside. It works as a keyword default, which closes the MsgFlags gap.
- Each type gets a value namespace for its qualified constants. If a name in it is the same as a trait's static function name on `T`, that is a compile error, never a priority. That keeps the reason behind the "No Inherent Methods" vote (no silent priority) intact.
- For now, no constants on generic types (`Box[T].EMPTY`). A polymorphic const raises value-restriction questions that nobody needs answered yet.

**Why not trait associated consts?** Rust's `trait Flags { const NONE: Self }` needs a separate trait for each type just to hold a name, and nothing abstracts over that trait. It is ceremony with no polymorphism.

**Tradeoff.** This is new declaration syntax, but it is small, and it is the only sound way to make `T.NAME` a const expression.

###### Proposal 3 (optional, separate ticket): type-qualified static functions

Opaque user types need smart constructors. Today `Duration.ms` works only through a `Duration_ms` naming trick that the spec does not describe and user code cannot use (measured). The same declaration form would fix it:

```blink
pub fn Instant.from_epoch_secs(s: Int) -> Instant {
    Instant { nanos: s * 1000000000 }
}
```

There is no receiver, so there is no method dispatch to shadow, and the same collision-is-an-error rule applies. This touches the 4-1 "No Inherent Methods" vote, so it needs its own deliberation. Without it, Proposal 1 still works: users write free `pub fn make_instant()`.

###### Preference

**I prefer 1 + 2 together.** Proposal 1 gives one principled typing rule. Instant, MsgFlags, TestError and `Handle[T]` all fall out of it, and none of them needs to be compiler-known any more. Proposal 2 is the smallest addition that makes `MsgFlags.NONE` a real const expression, and it does so without bringing back inherent impls. The B1 voters' concern is met: under rule 1, `MsgFlags { bits: 0x40 }` outside std is a compile error by a general rule, not by a special case.

##### DevOps/Tooling

The test I apply to each option: what does the error say, what can the LSP list after `T.`, and what does `blink fmt` do.

###### Proposal D1: `opaque` type modifier (preferred)

Add one modifier to the type declaration: `pub opaque type T { ... }`. Outside the module that declares `T`, code can name the type, pass it, and call its trait methods. Outside code cannot:

- write a struct literal or a variant constructor of `T`;
- use a struct or variant pattern on `T`, even with `..`;
- read or write a field, or use `..t` spread.

Inside the module, every one of these is legal. The rule applies the same way to structs and enums, so one rule covers Instant, MsgFlags and an opaque enum.

```blink
// lib/std/time.bl
pub opaque type Instant {
    nanos: Int
}

pub fn instant_from_epoch_secs(s: Int) -> Instant {
    Instant { nanos: s * 1000000000 }
}

// user main.bl
fn f(i: Instant) -> Int {
    i.nanos
}
```

```
error[E10xx]: `Instant` is opaque outside module `std.time`
 --> src/main.bl:2:7
  |
2 |     i.nanos
  |       ^^^^^ field `nanos` is not visible here
  |
  = note: `std.time` declares `pub opaque type Instant`
  = help: use a method, e.g. `i.since(other)`
```

A struct literal and a pattern give the same code, each with its own label ("cannot construct", "cannot match"). The error names the type, not the field. This is better than "private field `bits`" because it does not tell the user the hidden field's name, and the hidden field can change later.

**Tradeoffs**
- No break: every existing `pub type` stays fully public. With per-field privacy (D2), every type changes.
- The LSP hover shows `pub opaque type Instant` and nothing more. Field completion after `i.` is empty outside the module, so the LSP shows no hidden fields.
- `blink doc` prints the type with no body.
- `blink fmt` puts the modifier in one fixed place: `pub opaque type`.
- The spec already uses the word "opaque" for Instant, Template, TestError and `@ffi.opaque`. Those become one stated rule plus a few compiler-known types.
- It cannot express "some fields public, some private". I say YAGNI: no case in the ticket needs a mixed type.

**Cross-language:** OCaml abstract types and Haskell modules that do not export constructors work this way. Swift and Rust do privacy per field.

###### Proposal D2: per-field `pub`, fields private by default

```blink
pub type Point {
    pub x: Int
    pub y: Int
}
```

If a type has a non-`pub` field, outside code cannot construct it, and cannot pattern-match on that field. This matches the §2.12 default-private rule.

**Tradeoffs**
- It breaks every existing `pub type` that outside code builds or reads, which is most of them. A `blink fix` tool can add `pub` to the fields, but the diff is large and the stdlib churns.
- For enum variants it is not clear what the rule is (per variant? per payload?), so it needs a second rule.
- Every struct body has more noise, so more tokens for an AI to write and to read.

**Cross-language:** Rust and Swift. In Rust, the private-field error E0451 is a common beginner error.

###### Proposal D3: type-namespaced constants, `const T.NAME`

You declare these with a qualified name, and only in the module that declares `T`:

```blink
pub opaque type MsgFlags {
    bits: Int
}

pub const MsgFlags.NONE = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK = MsgFlags { bits: 2 }

pub fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.PEEK) -> Result[Bytes, Errno] ! IO {
    ...
}
```

Rules:
- The right-hand side must be a §2.21 const expression. It can use the opaque struct literal because it is inside the type's module.
- §2.21 grows one case: a reference to `T.NAME` is a const reference. This makes `MsgFlags.NONE` legal as a keyword default in any module.
- `Float.INF` is a `pub const Float.INF` in the module that owns Float.
- A const and a trait static function with the same name in `T`'s namespace collide, and E1016 reports it.

The diagnostics:

```
error[E10xx]: cannot declare `Int.MAX` outside the module that declares `Int`
 --> src/main.bl:1:11
  |
1 | pub const Int.MAX = 9
  |           ^^^^^^^ `Int` is declared in `std.prelude`
```

```
error[E10xx]: `MsgFlags` has no constant `PEK`
  = help: did you mean `MsgFlags.PEEK`?
```

**Tooling:**
- After `MsgFlags.`, the LSP lists the constants and the trait static functions together. The data comes from one place: declarations in one module.
- Go-to-definition jumps to the `const` line.
- `rg 'const MsgFlags\.'` finds all the constants, which is good for grep and for AI agents.
- This also fixes today's internal compiler error (NodeCarriesNoType) on `T.ZERO`. It gives a stated rule in place of a crash.

**Cross-language:** Rust `impl T { const X }` and Swift `static let` do the same thing, but they need an inherent block, and §3c rejects inherent blocks. A qualified name gives the same result without one.

###### Open sub-question (I flag it, I do not propose it): `fn T.name`

The stdlib maps `Duration_ms` to `Duration.ms(...)` by a naming convention that is not in the spec. User code cannot use it: the measured error is "method `make` resolves to nothing", which does not help.

An opaque type needs a public constructor. Without one, users write `pub fn make_t()` and the stdlib writes `Instant.from_epoch_secs`, so there are two styles.

The same qualified form (`pub fn Duration.ms(n: Int) -> Duration`) would fix this. It has no `self`, so it cannot get priority over a trait method on a value, which was the §3c concern. A collision would be E1016. The panel must still rule on this, because it touches the "No inherent methods" vote.

At a minimum, the hidden `Type_name` convention must become a stated rule or be removed. Today it is a trap: the stdlib can do something user code cannot.

###### Preference

**D1 + D3.** My reasons:

1. **One error per idea.** An `opaque` error names the type and its module, and does not expose field names.
2. **No break.** D2 makes every `pub type` change and creates a large `blink fix` migration for no current gain.
3. **One completion source.** With D3 the LSP and `blink doc` can list `T.` members from one module. Nothing depends on name conventions.
4. **No special cases.** MsgFlags and Instant become ordinary stdlib code under stated rules. Only Template, TestError, Iterator and Handle stay compiler-known, because they have no Blink body.

I reject D2 on churn and token cost. If the panel wants mixed-field privacy later, it can add `pub` on fields of an `opaque` type, and nothing in D1 blocks that.

##### AI/ML

My test for each option: can a model learn the rule from one spec paragraph, how many choices does it add per declaration, and does the error point at the fix?

###### Proposal 1 (preferred): `opaque` modifier on the type

```blink
// lib/std/libc.bl
pub opaque type MsgFlags { bits: Int }

pub const MsgFlags.NONE: MsgFlags = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK: MsgFlags = MsgFlags { bits: 1 }

// lib/std/time.bl
pub opaque type Instant { nanos: Int }

// user module
let f = MsgFlags.PEEK                 // ok
let g = MsgFlags { bits: 64 }         // error: MsgFlags is opaque outside std.libc
match f { MsgFlags { bits } => bits } // error: same
f.bits                                // error: same
```

**The rule.** `opaque` goes on a `type` declaration. In the declaring module, the type works as it does today. In all other modules, the type name is visible, but these are compile errors:
- struct literals, spread and shorthand construction
- patterns that name fields or variants
- field reads and field writes
- for an enum: building or matching a variant

Trait methods, derived traits, `==`, and passing the value to functions all still work. A plain `pub type` keeps all fields public, which is today's behavior, so no code has to migrate.

**Tradeoffs.**
- **One choice per type, not one per field.** A model makes the choice once, at the declaration, which is where it thinks about the type's purpose.
- **Easy to find.** `rg "opaque type"` lists every sealed type. A model that reads a `pub` signature sees `opaque` on the same line.
- **Errors point at the fix.** "MsgFlags is opaque outside std.libc; use MsgFlags.NONE or a function from std.libc" tells the caller what to do. Under per-field `pub`, the error appears in the caller's module, but the fix (add `pub`) is in another file, which may be a stdlib file the user cannot edit.
- **No mixed structs.** You cannot make a struct with some public fields and some private fields. I think that is correct for Blink: a mixed struct cannot be built outside its module anyway, so you get opacity plus partial reads, which adds a second concept for little gain.
- **Getters need a trait or a module function.** Because Blink has no inherent methods, an opaque type exposes reads through a trait or a module function such as `time.nanos(i)`. This is more text than `i.nanos`, but it is the same model the no-inherent-methods decision already uses.
- **It removes the special cases.** One rule replaces the compiler knowledge for `Instant`, `MsgFlags` and `TestError`. Fewer special cases means less spec for a model to learn.

**Other languages.** OCaml and Haskell abstract types hide the whole representation, the same as this. Rust and Swift use per-field `pub`, and Go uses per-field capitals. In Rust, models often forget `pub` on fields and get E0451 far from the declaration.

###### Proposal 2 (rejected): per-field `pub`, Rust style

```blink
pub type Instant {
    nanos: Int          // private
}
pub type Point {
    pub x: Int
    pub y: Int
}
```

**Tradeoffs.**
- **It breaks almost every existing struct.** Fields become private by default, so every public data struct must add `pub` to each field.
- **It costs tokens.** That is one `pub` per field, on the most common type shape.
- **It doubles the choices.** A model must decide public or private for each field, and the common case (a public data record) is the noisy one.
- **It invites a wrong guess.** Many models are trained mostly on Rust, so they expect this design, and the Blink default would then differ from what they guess.
- **Its one gain** is mixed structs, which I rated as low value above.

I do not support this proposal.

###### Proposal 3: type-qualified `const` declarations

```blink
pub const MsgFlags.NONE: MsgFlags = MsgFlags { bits: 0 }
pub const Float.INF: Float = 1.0 / 0.0

fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO
```

**The rule.**
- `const T.NAME: T = <const expr>` declares a constant in the namespace of type `T`.
- Only the module that declares `T` may write one. This uses the same ownership idea as trait coherence and stops third parties from adding `Float.MY_PI`.
- The right side follows §2.21, and it may use `T`'s private fields because it is in the same module.
- The constant is a const expression, so it is legal as a keyword default, a field default or a range-pattern bound.
- `pub` follows §2.12.
- `T.NAME` resolves only in the type's constant table. It never collides with a module value, so §2.12.1 needs no change.

**Tradeoffs.**
- **It reuses `const` syntax.** The only new part is the dotted name, so there is no new block form.
- **Declaration matches use.** The text at the definition (`MsgFlags.NONE`) is the same as at the call site, so a model can find the definition with one grep.
- **It is not an inherent method.** It cannot shadow `x.method()`, because constants are reached only through the type name. The reason behind the no-inherent-methods vote (silent priority over trait methods) therefore does not apply.
- **It costs few tokens.** `MsgFlags.NONE` is short and does not repeat the module name.
- **It fixes a measured bug.** Today `T.ZERO` from user code is an internal compiler error. This gives that case a defined meaning.

**Other languages.** Rust associated consts need an `impl` block. Swift and Kotlin use `static let` and `companion` blocks. The Blink form has neither block.

###### Note for a later ticket: `Type.name()` functions for user code

The stdlib maps `Duration_ms` to `Duration.ms`, but user code cannot do this, and the spec does not describe it. Opaque types make the gap worse: a user `Email` type needs a public way to build it (`Email.parse(s)`). The fix that matches Proposal 3 is `pub fn Email.parse(s: Str) -> Result[Email, ParseError]`, with the same "declaring module only" rule. I do not ask this panel to decide it now. I do ask the panel to record the gap, because without it user opaque types fall back to module-level functions (`email.parse(s)`). That works, but it is a second way to do the same thing.

###### My preference

Take Proposal 1 together with Proposal 3. The combination adds:
- one keyword (`opaque`) with one choice per type
- one declaration form (`const T.NAME`) that has the same shape as its use

The rule fits in one spec paragraph and needs no training-data prior. It removes compiler knowledge for four types. Current code keeps working, and every error names the type and the module that owns it.

##### Minimalism

###### Framing

This gap has two parts. First, the compiler already treats five types as opaque by special case: `Instant`, `MsgFlags`, `TestError`, `Template[C]` and `@ffi.opaque`. Second, stdlib uses a hidden `T_name` naming convention to make `Duration.ms(…)` work, and that convention fails for user code. The best fix replaces those special cases with one rule. A fix that adds a rule and keeps the special cases fails. The burden of proof is on each new feature, but here the special cases already exist, so the real choice is between one stated rule and six unstated ones.

###### M1 (preferred): whole-body opacity plus type-scoped items

**Part 1: the `opaque` type modifier.** The type's name is public. Its body (fields or variants) belongs to its module.

```blink
// lib/std/time.bl
pub opaque type Instant { nanos: Int }

// lib/std/libc.bl
pub opaque type MsgFlags { bits: Int }
```

Outside the declaring module, it is a compile error to:
- write a literal `Instant { nanos: 5 }`, or spread one with `..i`
- read a field: `i.nanos`
- write a struct pattern `Instant { .. }`, or name a variant of an opaque enum

Inside the module, all of these are legal. Outside the module, code can still hold, pass, store and compare values, and it can call trait methods. `derive` and `impl` in the owning module work as usual. The error is the existing pub-enforcement error (§2.12) with a field or variant as the subject. No new error code is needed.

**Part 2: type-scoped `const` and `fn`.** Only the module that declares `T` may declare them.

```blink
pub const MsgFlags.NONE = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK = MsgFlags { bits: 1 }

pub fn Duration.ms(n: Int) -> Duration {
    Duration { nanos: n * 1000000 }
}

fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO
```

- `MsgFlags.NONE` is a reference to a const, not a struct literal. It is therefore legal outside the module, and it is a const expression. §2.21 changes in one place: "references to other `const` bindings by name" becomes "by name or by `Type.NAME`".
- A type-scoped `fn` has no receiver. You cannot call it with method syntax (`d.ms(5)`), so it never takes part in method resolution. The reason for "No Inherent Methods" was silent priority over trait methods, and that reason does not apply here. If a type-scoped item and a trait static of one type have the same name, it is an E1016 duplicate.
- `|` on `MsgFlags` comes from an ordinary operator trait impl in `std.libc`. It needs no new feature.
- `Float.INF` uses the same rule. The prelude declares it.

**What M1 removes:** the compiler-known opacity of `Instant` and `MsgFlags`, the hidden `T_name` convention, and the ICE on `T.ZERO`. `TestError` and `Template[C]` become `pub opaque type` declarations. `@ffi.opaque` becomes a bodiless opaque type plus its C mapping. That is one rule for six cases.

**Cost:** one contextual word, valid only before `type`, and one form of declared name (`T.name`). The new interactions are with patterns, spread, field access and const expressions, and each one has a yes-or-no answer. There is no partial visibility and no per-field matrix.

**Cross-language:** OCaml abstract types and Haskell's "export the type, hide the constructors" use the same whole-type cut, and in practice it is enough. Go and Rust cut per field.

###### M2: per-field `pub` (Rust/Go style), which I reject

```blink
pub type Point { pub x: Int, pub y: Int }
```

- Fields are public today. Default-private fields would break every `pub type` in stdlib and in user code, and add tokens to every data struct.
- Default-public fields with a `priv` marker give a mixed-visibility matrix: can you construct a struct when one field is hidden? Can you match it with `..`? Rust needs `#[non_exhaustive]` on top for this reason.
- None of the six real cases needs mixed visibility. YAGNI.

###### M3: do nothing; use convention and module constants

```blink
let head = libc.recv_bytes(fd, 16, flags: libc.MSG_PEEK)?
```

- This adds no syntax. Zig does the same: it has no private fields and relies on documentation.
- I reject it. The B1 vote said that if `MsgFlags { bits: 0x40 }` compiles outside `std.libc`, B1 falls back to B2. A convention gives no guarantee. M3 also keeps the five special cases and the hidden naming convention, so it adds unstated rules and subtracts none. It also reverses the decided spelling `MsgFlags.NONE`.

###### Possible cut

If the panel wants to scope this down, drop type-scoped `fn` and keep only `const`. User opaque types then build values through module functions (`counter.new_counter()`). Stdlib would still need its hidden convention for `Duration.ms`, so it keeps one unstated rule. I would accept that as a second choice, but I would not prefer it: "methods only" for stdlib and "free functions only" for users are two ways to do one thing.

###### Preference

**M1.** It adds one modifier and one form of declared name. In exchange it removes five compiler special cases and a hidden naming convention, and it fixes an ICE. M1 replaces existing complexity, so it is the kind of addition I vote for. Part 1 decides question (1) and Part 2 decides question (2), with no extra rules.

#### Phase B — Debate, round 1 (all six ended STABLE; Phase B closed after one round)

##### Systems

**1. Positions**

**Q1: I move from Q1-B to Q1-A (`opaque` modifier).** My case for Q1-B was consistency with §2.12 and mixed-field control. Neither one is a hardware argument. Both options compile to the same C: a complete struct, passed by value, with layout unchanged. Since my domain sees no difference, the churn decides it. Q1-B makes every `pub type` in lib/std, src and tests change through a 3-step bootstrap, and no case in the ticket needs mixed fields. If a real need for mixed fields shows up later, `pub` on fields of an `opaque` type can be added without a break (DevOps made this point).

One condition I hold firm on: **`opaque` hides the representation from code. It does not change the representation.** An opaque struct keeps its full C layout in the header, stays on the stack, and keeps its derived impls inlinable. It must never turn into a pointer or a heap handle.

**Q2: Q2-A (top-level `pub const T.NAME`).** I am unchanged. Against Q2-B: Web's in-body `pub const` mixes declarations into the field list, and the parser and every tool that walks fields must then tell them apart. Q2-A keeps the type body equal to the layout. The C printer can read the body as the struct, with no filter.

**Q3: decide it here, on its own ballot line, using Min's rule.** `pub fn T.name(...)` takes no receiver, so it is a direct static call. It has no dispatch, no vtable and no method lookup, so it cannot shadow a trait method. The compiler already emits exactly this for `Duration_ms`; the spec just never states it. If the panel judges that it reopens the 4-1 vote, then record a blocking follow-up ticket and have the spec name the `Type_name` convention as stdlib-only debt. It must not stay hidden.

**2. Variations**

- **V1:** no pattern outside the module, including `T { .. }`. The type is static, so that pattern tells the reader nothing that a binding does not.
- **V2:** an opaque enum hides all of its variants. PLT's exhaustiveness concern applies to hiding *some* variants. When outside code cannot match at all, there is nothing for an outside match to be incomplete about. The tag and payload layout do not change.
- **V3:** a keyword, `pub opaque type`. It changes what is legal to type-check. Blink's `@` annotations carry compiler or FFI metadata.
- **V4:** name the type, not the field (DevOps). The field can change later without changing the error text.
- **V5:** yes, Debug prints hidden fields. The derive runs in the owning module.
- **V6:** use the same annotation rule as a plain `const`. Do not add a second rule.
- **V7:** a clash is E1016. AI/ML's separate table makes `T.foo` ambiguous as a value (a const, or a fn reference?). A single namespace gives a single resolution.
- **V8:** no constants on generic types for now. Mono could handle them, but nothing needs them (YAGNI).
- **V9:** I move to "the prelude" for builtins. It is the module that owns `Float`, so this is the same rule I stated.
- **V10:** this is a non-problem; keep §2.21 closed. Only *defaults* must be const, and the default stays `MsgFlags.NONE`. `MsgFlags.PEEK | MsgFlags.WAITALL` at a call site is an ordinary argument, which gcc folds to an immediate anyway. A combined *default* can be its own declared constant.

**3. Rebuttals**

- **Min:** "`@ffi.opaque` becomes a bodiless opaque type plus its C mapping." I agree with the name, and I disagree that it is the same thing. An `@ffi.opaque` value is a `T *` to an incomplete C type, so its ABI is a pointer. A `pub opaque type` is a complete struct passed by value. The spec must keep these as two shapes, or a later implementer will "unify" them into a pointer and add an indirection to every `Instant`.
- **AI/ML:** "Getters need a trait or a module function... more text than `i.nanos`." Cost is the same at run time: a module fn on a by-value struct inlines to a field load. Nobody should argue for a field-level escape hatch on performance grounds.
- **Web:** "dotted top-level name... looks like the `Duration_ms` mangling hack moved into the spec." Putting it in the spec is the point. A stated rule that the compiler checks replaces a hidden one it does not check.

STABLE: ready to vote

##### Web/Scripting

###### 1. Positions

**Q1: Q1-A (`opaque` modifier). I keep my Phase A vote.** Five of six proposals put it first or second.

**Q2: I move to Q2-A (`pub const T.NAME`).** The case for it is stronger than my in-body form:
- AI/ML: "Declaration matches use." A user who sees `MsgFlags.NONE` can grep for `const MsgFlags.NONE` and find it. That is better DX than Kotlin's companion block.
- A type body then holds only fields or variants. No reader has to ask "is this line a field or an item?".
- It adds no new block form and reuses `const`.

**Q3: decide `pub fn T.name(...)` now, with the same rule as Q2-A (Min M1 Part 2).** If the moderator rules it out of scope, then record it as a required follow-up, not an optional one. My reason: §2.12 already says the stdlib surface is `Duration.ms(100)` and `Instant.from_epoch_secs(0)`. The spec promises the call shape but never says how a type declares it. Today the stdlib can do something that user code cannot. A user who copies the stdlib pattern gets "method `make` resolves to nothing". That gap will produce many "how do I write a constructor?" questions, and opaque types make it worse, because a user opaque type with no named constructor is half a feature. The function has no receiver, so it cannot get priority over a trait method. The reason behind the 4-1 vote does not apply.

###### 2. Variations

- **V1:** no `T { .. }` pattern outside the module. One rule: "no body syntax outside the module". `T { .. }` tells you nothing that a type annotation does not.
- **V2:** an opaque enum hides its variants. PLT's exhaustiveness concern does not apply, because outside code cannot match the type at all. A transparent newtype such as `Errno` stays non-opaque, so it does not change.
- **V3:** a contextual keyword, `pub opaque type`. It changes what the type means, so it belongs in the declaration line, not in an annotation.
- **V4:** name the type and the owning module (DevOps), and add a help line that lists the way in: "use `MsgFlags.NONE` or a function in std.libc". An error that says "field `bits` is private" invites the user to ask how to make it public, and they cannot.
- **V5:** `@derive(Debug)` prints hidden fields. Debug output is for logs, not API. DevOps's "do not leak the field name" applies to the compile-time error, not to a log line. JS, Python and Kotlin all print private state in debug output.
- **V6:** no special rule. The type annotation on `const T.NAME` is optional or required by the same rule as a plain `const`. One rule for both.
- **V7:** a clash is E1016. AI/ML's separate constant table means `MsgFlags.X` and `MsgFlags.X()` can name two different things. That is a puzzle for a reader and a bug magnet for a model.
- **V8:** no constants on generic types for now (PLT). YAGNI.
- **V9:** the prelude owns builtin-type constants such as `Float.INF`. A user must find these in one place.
- **V10:** I disagree with Min's "`|` ... needs no new feature." An operator trait call is not a §2.21 const expression, so `flags: MsgFlags = MsgFlags.PEEK | MsgFlags.WAITALL` fails as a keyword default. No current flag needs this, so record it as a follow-up and do not decide it here.

###### 3. Rebuttals

- **To Sys:** "A rule that leaks fields by default is a latent bug in every library." Most structs are data: request bodies, configs, rows, AST nodes. For a data struct, public fields are the correct result, not a leak. A type with an invariant is the case where the author already knows to protect it. One word at that place is enough. Per-field `pub` puts the cost on the 90% case to help the 10% case.
- **To Sys P1:** "A type with no `pub` field and no `pub` constructor fn is opaque." Here opacity comes from things that are absent. A JS dev cannot see that by reading the declaration. `opaque` states it on the declaration line.
- **To PLT:** you can get the soundness of an abstract type with a whole-type cut. OCaml's abstract types and Haskell's hidden constructors are the same theorem. Per-field control is not needed to get it.

STABLE: ready to vote (with Q3 voted as its own question)

##### PLT

###### 1. Positions

**Q1: I move from Q1-B to Q1-A (`opaque`).** Both options are sound. Each one is an abstract-type rule. So the choice comes down to cost, and Q1-A costs less: no migration, and one choice per type. Q1-A also has a principled reading. `pub type T { ... }` exports the name and the structure. `pub opaque type T { ... }` exports only the name. That is OCaml's split between `type t = { ... }` and `type t` in a signature. It does not contradict §2.12's "private by default", because the fields belong to the type's exported structure. DevOps is right that per-field `pub` can be added later inside an opaque type, and nothing in Q1-A blocks it.

My conditions for Q1-A (the typing rules must say these):
- **Source module.** Access is checked against the module of the source text, not the module where mono instantiates it (as Sys says). Generic code in the owner may touch the body; generic code elsewhere may not.
- **Aliases.** An alias does not open the type. `type A = Instant` in another module is still opaque there.
- **Const-expression comparison.** In a const expression, `==` and `<` on an opaque type outside its module are errors. Otherwise const evaluation compares the hidden representation directly, without the Eq impl, and that leaks it.

**Q2: Q2-A (`pub const T.NAME`).** No change from Phase A.

**Q3: decide it now, together with Q2-A**, but only as an explicit amendment to the §3c "No Inherent Methods" text, recorded as such. Minimalism's argument holds: the hidden `Type_name` convention is a stated-nowhere rule, and Q2-A gives the exact declaration form to replace it. A type-scoped fn has no receiver, so `x.f()` can never resolve to it, and the reason behind the 4-1 vote does not apply. If the panel does not want to amend §3c in this ticket, I accept a follow-up ticket.

###### 2. Variations

- **V1:** no struct pattern at all outside the module, `T { .. }` included. That gives one rule. `T { .. }` gains nothing over a binding.
- **V2:** I withdraw my Phase A objection. I argued that hiding *some* variants breaks exhaustiveness. Under whole-body opacity, outside code cannot match the type at all, so exhaustiveness never comes up. An opaque enum hiding all of its variants is sound.
- **V3:** `pub opaque type` as a keyword. Opacity changes the static meaning of the type, so it is not an annotation.
- **V4:** name the type, not the field (DevOps). The field name is part of the hidden representation.
- **V5:** Debug may print hidden fields. The derived impl lives in the owning module, so the owner chooses what it shows. The output is a string, so nobody can use it to forge a value.
- **V6:** the annotation is optional, the same as a bare `const` in §2.21. The type is inferred from the right side.
- **V7:** it must be an error, not a separate table. Reply to AI/ML ("`T.NAME` resolves only in the type's constant table. It never collides"): with Q3, `T.x` would name either a const or a static fn, and a reader or a model cannot tell which. One name gives one meaning.

  A caveat for Sys, Min and DevOps: E1016 is module-scoped, but trait impls can live anywhere in the owning package. So the clash check has to be package-wide. When a trait impl comes from another package, report it as an ambiguity at the use site (fixed with `Trait.name(...)`), not at the declaration. Otherwise, adding a const upstream would silently break code downstream.
- **V8:** no constants on generic types for now.
- **V9:** "the module that declares `T`". For builtins, the spec names that module (the prelude). Sys's wording and mine agree.
- **V10:** I agree with Web, and I add a hard line: §2.21 must not admit trait operator calls. A user impl of `|` can be arbitrary code, and const evaluation must stay total and free of effects. A combined flag gets its own declared constant with literal bits.

###### 3. Rebuttals

- **Web P3 (`const` inside the type body):** under `opaque`, the body is exactly what is hidden. A `pub const` inside it puts public items inside the private part, and that confuses the rule. It also means a type body holds two kinds of item, so the parser and the reader must tell them apart. With Q2-A, the type body holds only the representation.
- **Web P4 ("looks like the mangling hack moved into the spec"):** this is the reverse of the truth. The hack is a name trick that nobody stated. `T.NAME` is a scoping rule that the spec states, the declaration looks the same as its use, and the compiler checks ownership.

STABLE: ready to vote

##### DevOps/Tooling

###### 1. Positions

**Q1: Q1-A, the `opaque` modifier. No move.** Sys and PLT are right that Q1-B follows §2.12 more strictly, and that the codegen is the same either way. My objections to Q1-B are about the diagnostics:

- Under Q1-B, the error shows up in the caller's file, but the fix (add `pub` to a field) is in the declaring file. That file is often a stdlib or dependency file that the user cannot edit. AI/ML made this point and I agree. Rust's E0451 is the proof.
- Every `pub type` in the corpus needs a codemod. That is a large `blink fix` diff with no current gain.

**Q2: Q2-A, `pub const T.NAME`. No move.**

**Q3: I support `pub fn T.name` and I move toward Min.** My vote is to decide it in this panel, as a separate vote item that is not bundled with Q1 or Q2. My reason is about the tooling. Today `T.make()` fails with "method `make` resolves to nothing", and the stdlib uses a naming trick that the spec does not describe. If we ship `opaque` without Q3, the LSP must list `Instant.from_epoch_secs` and must also tell users "you cannot do this". That is a worse state than today. If the panel rules that the 4-1 "No Inherent Methods" vote stops this decision, then the follow-up ticket must be a blocker for marking f64d9c done.

###### 2. Variations

- **V1: no `T { .. }` pattern outside the module.** It matches the same values as `_`, so it adds nothing. It also leaks the shape: it tells the caller that `T` is a struct. If the author later changes `T` to an enum, that pattern breaks. Opacity exists so that the author can make this change. The error text should be: "`Instant` is opaque outside `std.time`; use `_` or a binding".
- **V2: an opaque enum hides its variants.** PLT says "hiding a variant breaks exhaustiveness". That is true for hiding *one* variant. Under Q1-A, outside code cannot match on any variant, so no outside match exists to be incomplete. The problem does not arise.
- **V3: the keyword `pub opaque type`.** Annotations (`@derive`, `@trusted`) control tooling and code generation. `opaque` changes which code is legal. `blink fmt` gets one fixed order: `pub opaque type`.
- **V4: name the type in the main error line, and do not show the hidden field name as a suggestion.** I accept Min's point: reuse the existing pub-enforcement code with a new subject, and add no new code. One code means one `blink explain` page.
- **V5: Debug prints hidden fields.** I agree with Web. The derive runs in the owning module, and log output is for people who debug.
- **V6: the type annotation follows whatever rule the spec has for a plain `const`.** Do not make a second rule for qualified consts.
- **V7: a name clash is E1016 at the declaration.** AI/ML wants a separate table that never clashes. With that table, `MsgFlags.NONE` at a use site could name a const or a static fn. Go-to-definition and hover then need a tie-break rule, and that is the silent priority that the 4-1 vote removed. An error at the declaration is better than a surprise at the use site.
- **V8: no constants on generic types for now.** I agree with PLT.
- **V9: the prelude declares the builtin constants.** That is where the types are declared, so the "declaring module only" rule holds with no exception.
- **V10: out of scope.** Declare a combined constant when one is needed.

###### 3. Rebuttals

**To Web, on Q2-B (`const` inside the type body):** "Builtins use the same form in the prelude, for example `Float.INF`". `Float` has no Blink body to put a const in, so Q2-B needs a second form for builtin types. Also, a body that mixes fields and items makes `blink fmt` and the LSP outline sort two kinds of entry. Q2-A keeps a type body to fields only. The text at the declaration (`MsgFlags.NONE`) is the same as at the use site, so `rg 'MsgFlags.NONE'` finds both.

**To Web, "it looks like the `Duration_ms` mangling hack moved into the spec":** It is the reverse. The hack is a convention that the spec does not describe, that user code cannot use, and that gives a bad error. A declared form is visible, the spec states it, and the LSP can index it.

**To Sys, "A type with no `pub` field and no `pub` constructor fn is opaque":** Here opacity follows from what is missing, so neither hover nor `blink doc` can show that the author meant it. Then one `pub` field added later changes the type's whole surface in silence. A keyword states intent in one place where a person or a tool can see it.

STABLE: ready to vote

##### AI/ML

###### 1. Positions

**Q1: Q1-A (`opaque` on the type). No move.** Five of six panelists named it first or second. My reason stays: one choice per type, written at the declaration, and the error names one word. Per-field `pub` adds one choice per field on the most common shape (data records) and breaks every `pub type` in the corpus.

**Q2: Q2-A (`pub const T.NAME = ...` at top level). No move.** The declaration text matches the use text, so `rg "const MsgFlags\."` finds every definition. Six of six support it as first or fallback.

**Q3: I move from "flag it" to "decide now, same form as Q2-A".** Reason: the 4-1 "stdlib API surface: methods only" vote already makes `Duration.ms(100)` and `Instant.from_epoch_secs(0)` the spec surface. Q3 does not add a feature. It states how that decided surface is declared, and it removes a hidden `Type_name` convention. A model that reads the stdlib today sees `Duration.ms(...)`, writes `T.make(...)` for its own type, and gets "method `make` resolves to nothing". That is the worst kind of error for an AI: the spec and the stdlib both show a pattern, and the compiler rejects it. Min's argument holds: a type-scoped `fn` has no receiver, so it is not method resolution, and the reason for the No Inherent Methods vote does not apply. If the panel will not decide Q3 here, I accept the cut, but then the spec must state the `Type_name` rule or remove it. It must not stay hidden.

###### 2. Variations

- **V1:** No pattern on an opaque type outside its module, including `T { .. }`. The type is static, so `T { .. }` tests nothing. One rule ("no pattern") is easier to learn than "no pattern except `..`". I change my Phase A text to say this.
- **V2:** An opaque enum hides its variants. PLT's exhaustiveness concern does not arise: outside code cannot match at all, so no outside match can be incomplete. This lets `TestError` be `pub opaque type`.
- **V3:** A contextual keyword (`pub opaque type`). An annotation reads as metadata, but this changes what the type means. The keyword also sits in the signature line that a model scans.
- **V4:** Name the type and its module, not the field (DevOps). The help line should name the public way in (`MsgFlags.NONE`, `Duration.ms`).
- **V5:** Yes, a derived `Debug` prints the hidden fields. The derive runs in the owning module. Debug output is for people who are fixing problems.
- **V6:** The annotation is optional, the same as a plain `const` (§2.21 examples: `const MAX_RETRIES = 5`). Two rules for two `const` forms would be one decision point too many.
- **V7:** I move to E1016 on a clash (Sys, PLT, DevOps, Min). One `T.` namespace gives one completion list and one meaning for `T.x`. My Phase A "separate table" would let `T.make` mean two things.
- **V8:** No constants on generic types for now (PLT).
- **V9:** The prelude owns `Float.INF`. That is one owner rule: "the module that declares the type".
- **V10:** Not in this ticket. When a combined flag ships, declare a named constant (`MsgFlags.PEEK_WAITALL`) or add `|` to §2.21 for one named trait. Record it as a follow-up.

###### 3. Rebuttals

- **Sys:** "A type with no `pub` field and no `pub` constructor fn is opaque." Under this rule, opacity is a result you compute from what is absent. A model must scan every field and every function to know whether `T { ... }` compiles. `opaque` states it in one token.
- **PLT:** "It is the abstract-type rule from ML signatures." I agree, and whole-body `opaque` is that rule in its exact form: an ML abstract type hides the whole representation, not some fields. The soundness argument supports Q1-A as well as it supports Q1-B.
- **Sys/PLT, the consistency with §2.12:** §2.12 governs items. A field is not an item, so extending the rule to fields is a new choice, not a consequence. The cost of that choice is one `pub` on every field of every public record.
- **Web, Q2-B:** "The constant sits next to the fields." But then the body of a type mixes two kinds of member, and the declaration (`pub const NONE`) does not match the use (`MsgFlags.NONE`). Web's case against Q2-A ("people will then ask for `pub fn Duration.ms(...)`") is my case for it: one form answers both questions.

STABLE: ready to vote

##### Minimalism

###### 1. Positions

**Q1: Q1-A (`opaque` modifier). No move.** It covers all six real cases. It breaks no code and adds one choice per type. Q1-B adds one choice per field and migrates every `pub type`, only to make mixed structs possible, and no listed case needs a mixed struct.

**Q2: Q2-A (`pub const T.NAME`). No move.**

**Q3: I move.** In Phase A I asked to decide `fn T.name` now. Four panelists want a separate ticket, because it touches the 4-1 No Inherent Methods vote. That process point is fair. I accept a follow-up, on two conditions that the decision record must state:
- (a) The `T.name` declared-name form is reserved, so that a later `fn T.name` uses the same shape as `const T.NAME`.
- (b) The hidden stdlib `Type_name` convention is a known gap, and it has its own ticket. Sys says it well: "It must not add a second hidden convention."

###### 2. Variations

- **V1: no pattern at all on an opaque type outside its module, including `T { .. }`.** For a struct, `T { .. }` tests only the type, and the type checker already knows the type. For an enum, it would leak which variant is present. One rule ("no pattern") is shorter than "no pattern unless it names nothing".
- **V2: an opaque enum hides its variants.** `TestError` needs this. PLT's objection was: "If one variant were hidden, a `match` outside the module could never be complete." That is true for hiding *per variant*, but Q1-A never hides one variant. It hides the whole body, so outside code cannot `match` at all, and exhaustiveness never comes up. Sys and PLT's "wrap it in a struct with a private field" is a second way to make an opaque sum.
- **V3:** contextual keyword `pub opaque type`. This is a weak preference. It changes what the type means, and the spec text already uses the word.
- **V4:** name the type and its module, not the field (DevOps). Do not show a name the owner may change.
- **V5: no rule.** Debug is an impl in the owning module. `derive` prints the fields, and an owner who wants to hide them writes the impl by hand. Adding a special case here is exactly what this ticket removes.
- **V6:** follow whatever a plain `const` requires. Do not add a separate rule for `T.NAME`.
- **V7: E1016.** AI/ML's separate table means `T.x` could name both a const and a trait static fn. The reader then needs a priority rule, and silent priority is what §3c banned.
- **V8:** no consts on generic types for now (PLT). YAGNI.
- **V9:** this is not a separate decision. The rule is "the module that declares `T`", and the spec already says where `Float` is declared.
- **V10:** `|` stays a trait call, not a const expression. If a combined default is ever needed, declare it as a named constant, such as `pub const MsgFlags.PEEK_WAIT`. Do not grow §2.21 now.

###### 3. Rebuttals

- **Sys and PLT: "This is §2.12 applied one level down."** §2.12 governs *items*, and a field is not an item. Fields have been public for the whole life of the language, and the corpus depends on that. Q1-B is not "consistency". It is a new default plus a migration through the 3-step bootstrap.
- **Sys: "A rule that leaks fields by default is a latent bug in every library."** Under Q1-A, an author who needs an invariant writes one word, and the type cannot leak. A plain data struct with public fields is not a bug. It is most Blink types (Web's DTO point). Sys also grants that "codegen is the same as P1".
- **Web on Q2-B: a const in the type body.** Under `opaque`, the body is the hidden part. A `pub const` inside a hidden body mixes representation with API, and it makes the rule "the body is hidden, except `pub const` lines". Q2-A keeps the body equal to the representation.
- **Web: Q2-A "looks like the `Duration_ms` mangling hack moved into the spec."** That is the point. It turns a hidden, stdlib-only hack into a stated rule that users get too.

###### 4. Status

STABLE: ready to vote

#### Phase C — Silent vote

##### Systems

**Q1 — Q1-A**
Reasoning: Both options compile to the same C: a complete struct, by value, with layout unchanged. The tie-break is churn. Q1-B changes every `pub type` across lib/std, src and tests through a 3-step bootstrap, and no ticket case needs mixed fields.
Concern: an implementer may read "opaque" as "pointer to an incomplete type" and add an indirection to every `Instant` (C1a guards against this).

**Q2 — Q2-A**
Reasoning: The type body stays equal to the C layout, so the printer and every field walker read it with no filter. The constant folds to a literal at each use, with no init order and no guard.
Concern: users will copy the dotted form for other items before Q3 is in the spec. Q3-NOW removes that gap.

**Q3 — Q3-NOW**
Reasoning: `pub fn T.name(...)` has no receiver, so it is a direct static call with no dispatch and no lookup, and it cannot shadow a trait method. The compiler already emits this for `Duration_ms`. Writing it down replaces a hidden convention with a checked rule.
Concern: the amendment to §3c must say clearly that it covers receiver-less fns only, or it reopens inherent methods by the back door.

**V1 — V1-NONE.** `T { .. }` on a statically known type tells the reader nothing that a binding does not. One rule: no patterns.
**V2 — V2-HIDE.** With no outside match there is no exhaustiveness to break. Tag and payload layout do not change.
**V3 — V3-KW.** It changes typing, not metadata. `@` annotations are for compiler/FFI metadata.
**V4 — V4-TYPE.** The hidden field can change without changing the diagnostic.
**V5 — V5-NORULE.** A normal derive runs in the owning module and prints every field, so this gives the same result with no extra spec text.
**V6 — V6-SAME.** One annotation rule for all consts.
**V7 — V7-E1016.** One `T.` namespace gives one resolution for `T.foo` as a value. Sub-point: **yes.** Coherence allows impls in another package, so the declaration site cannot see every clash. An ambiguity error at the use site, with the `Trait.name(...)` fix, is the correct place.
**V8 — V8-NO.** YAGNI. Mono could handle it later at no cost.
**V9 — V9-PRELUDE.** The prelude is the module that declares `Float`, so this is my own rule.
**V10 — V10-CLOSED.** Only defaults need const. A combined flag at a call site is an ordinary argument, and gcc folds it. Sub-point: **no.** §2.21 already excludes calls, and a user operator is a trait call, so it is excluded today. A normative "never" would rule out a future const-eval design without a panel. That is a separate decision.

**C1 — conditions**
- **C1a: yes.** This is the guard against the pointer-indirection mistake above.
- **C1b: yes.** Check once at the definition, before mono. Instantiation from another module is then legal and free.
- **C1c: yes.** An alias is a name, not a new module boundary. Otherwise any module could open any opaque type with one line.
- **C1d: yes.** An opaque type's `Eq`/`Ord` may be hand-written. If the const evaluator folds `==` structurally through hidden fields, it can give a different answer from the run-time impl. That would be a silent miscompile.

##### Web/Scripting

###### Q1 — Q1-A
**Reasoning:** Most structs are plain data, and their fields should stay public with no extra tokens. That matches JS, Python, TS and Kotlin data classes. One word on the declaration line marks the rare type that has an invariant, and a reader sees it at once. It needs no migration.
**Concern:** People will ask for "one private field in a public struct", and someone will try to add per-field `pub` on top of `opaque`, which gives two systems.

###### Q2 — Q2-A
**Reasoning:** The declaration has the same text as the use, so a grep for `const MsgFlags.NONE` finds the declaration. Type bodies keep only fields or variants. It reuses `const` and adds no new block form.
**Concern:** Constants can be spread across a long file away from the type. The style guide should say to put them directly below the type.

###### Q3 — Q3-NOW
**Reasoning:** The spec already promises `Duration.ms(100)` as the call shape but never says how to declare it. User code that copies the stdlib fails with "resolves to nothing". An opaque user type with no named constructor is half a feature. A fn with no receiver cannot get priority over a trait method.
**Concern:** Users may read `fn T.name` as permission for `fn T.name(self)`. The spec and the error must reject a receiver in plain words.

###### V1 — V1-NONE
**Reasoning:** One rule: no body syntax outside the module. `T { .. }` adds nothing that a type annotation does not say.
**Concern:** Generated code that writes `T { .. }` for every type will fail on opaque types. A clear error fixes that.

###### V2 — V2-HIDE
**Reasoning:** Outside code cannot match the enum at all, so exhaustiveness is not a problem. A transparent newtype such as `Errno` stays non-opaque.
**Concern:** Users may mark a public enum `opaque` by mistake and then find they cannot match it.

###### V3 — V3-KW
**Reasoning:** It changes what the type means, so it belongs in the declaration, next to `pub`.
**Concern:** It adds one more contextual word to the language.

###### V4 — V4-TYPE
**Reasoning:** Name the type and the owning module, and add a help line that lists the ways in (constants, functions). "Private field `bits`" invites a question with no answer.
**Concern:** The help line must stay accurate. If it suggests wrong names, it is worse than no help.

###### V5 — V5-STATE
**Reasoning:** Debug is for logs. A JS, Python or Kotlin dev expects private state in debug output. One spec sentence stops the question before anyone asks it.
**Concern:** A type that holds a secret leaks it to logs. The spec sentence should say that such an owner must write Debug by hand.

###### V6 — V6-SAME
**Reasoning:** One rule for every `const`.
**Concern:** None that matters.

###### V7 — V7-E1016
**Reasoning:** One `T.` namespace. `MsgFlags.X` and `MsgFlags.X()` must not name two different things.
**Sub-point (package-wide check, ambiguity at the use site, fix `Trait.name(...)`):** YES, provided the error shows the fix.
**Concern:** An ambiguity error at a use site, caused by another package's impl, will confuse users unless the error names both sources.

###### V8 — V8-NO
**Reasoning:** YAGNI. No case in the ticket needs it.
**Concern:** None now.

###### V9 — V9-PRELUDE
**Reasoning:** Builtin-type constants should live in one place, next to the declaration of the type.
**Concern:** None.

###### V10 — V10-CLOSED (I move from FOLLOWUP)
**Reasoning:** A declared combined constant covers the real need today. A ticket with no user who needs it is noise.
**Sub-point (spec says §2.21 *never* admits trait operator calls):** NO. Say "not admitted", and do not write "never". Do not close a door in normative text when no one needs it closed.
**Concern:** A user who writes `A | B` as a default gets an error. The error must say "declare a combined constant".

###### C1 — conditions
- **C1a: NO as written.** The semantic point is correct: `opaque` changes visibility, not value semantics. But C struct layout is a codegen detail and does not belong in sections/. Put the C text in codegen docs.
- **C1b: YES.** Generic code must not break because of where mono instantiates it.
- **C1c: YES.** An alias must not be a back door around `opaque`.
- **C1d: YES.** A structural compare in a const expression reads the hidden representation.

##### PLT

###### Q1: Q1-A
Both options are sound abstract-type rules, so the choice comes down to cost and clarity. `pub type` exports name plus structure, and `pub opaque type` exports the name only. That is OCaml's split between `type t = {...}` and `type t`, with no migration. Per-field `pub` can be added later inside an opaque type without a conflict.
Concern: without conditions C1b-C1d, opacity can leak through mono, aliases or const evaluation.

###### Q2: Q2-A
The type body stays pure representation, and the declaration has the same shape as its use. The ownership check is the same as for trait coherence. §2.21 gains one clause and stays closed.
Concern: constant names and trait static fn names share `T.`, so the clash rule (V7) must be exact.

###### Q3: Q3-NOW
A receiver-free `T.name` fn can never take part in `x.f()` resolution, so the reason behind the 4-1 vote does not apply. Recording it as an explicit amendment keeps the decision trail honest. It turns a hidden name trick into a stated scoping rule.
Concern: the §3c amendment may be read as a door to inherent methods with `self`. The text must say "no receiver, never method-call syntax".

###### V1: V1-NONE
`T { .. }` gains nothing over a binding. One rule (no pattern outside the module) is simpler to state and to check.
Concern: none of note.

###### V2: V2-HIDE
When the whole body is hidden, outside code cannot match at all, so exhaustiveness never comes up. One rule covers structs and enums.
Concern: users may expect to match an opaque enum and must use a trait or predicate fn instead.

###### V3: V3-KW
Opacity changes the static meaning of the type, not a compiler hint, so it belongs in the grammar.
Concern: a contextual keyword must not break existing identifiers named `opaque`.

###### V4: V4-TYPE
The field name is part of the hidden representation. An error must not expose it or depend on it.
Concern: an error inside a long expression must still point at the right span.

###### V5: V5-NORULE
The derived impl lives in the owning module and is ordinary owner code, so the existing derive rule already settles it. The output is a string, so nobody can forge a value from it. A special rule adds nothing.
Concern: users may be surprised to see hidden fields in a log line.

###### V6: V6-SAME
A const's type comes from its right side under §2.21. A second rule for qualified names is not needed.
Concern: none of note.

###### V7: V7-E1016
`T.x` must have one meaning for a reader and a model. Sub-point: **yes**. The check is package-wide, and a clash with a trait impl from another package is a use-site ambiguity (fix: `Trait.name(...)`), so an upstream addition never breaks a downstream declaration.
Concern: the E1016 text must be widened beyond "module scope", or the code will be misleading.

###### V8: V8-NO
Polymorphic constants raise value-restriction and mono questions that no case needs answered yet.
Concern: none of note.

###### V9: V9-PRELUDE
The rule is "the module that declares `T`", and for builtins that is the prelude. The two labels mean the same thing if the spec names the declaring module.
Concern: none of note.

###### V10: V10-CLOSED
A combined default is its own declared constant with literal bits. Sub-point: **yes**. The spec must state that §2.21 never admits trait operator calls, because a user impl is arbitrary code and const evaluation must stay total and free of effects.
Concern: the list of declared combined constants may grow when many flags exist.

###### C1
- C1a: **yes**. It hides the representation and keeps it the same, which is sound and keeps by-value layout.
- C1b: **yes**. Otherwise mono instantiation leaks the representation.
- C1c: **yes**. Otherwise an alias opens the type, and opacity means nothing.
- C1d: **yes**. Otherwise const evaluation compares the hidden representation without the Eq impl.

##### DevOps/Tooling

###### Q1 — Vote: Q1-A
**Reasoning:** One keyword on one line gives the LSP hover, `blink doc` and `rg "opaque type"` a single place to show intent. With Q1-B the error shows up in the caller's file, but the fix is in the declaring file, often one the user cannot edit. Q1-A needs no corpus-wide codemod.
**Concern:** Users will want one public field on an opaque type, and they will ask for a mixed form before the spec has a rule for it.

###### Q2 — Vote: Q2-A
**Reasoning:** The text at the declaration is the same as at the use site, so one grep and go-to-definition find both. Type bodies stay fields only, so `blink fmt` and the LSP outline have one kind of entry. Builtins such as `Float.INF` use the same form, and Q2-B cannot do this.
**Concern:** The parser must accept a dotted name in `const` position, and it must give a clear error when `T` is from another module.

###### Q3 — Vote: Q3-NOW
**Reasoning:** If we ship opacity with no way to declare a constructor, the LSP must list `Instant.from_epoch_secs` and must also tell users that they cannot write the same thing. Today's "method `make` resolves to nothing" error is a trap that the stdlib does not hit. A declared form with no receiver makes the hidden convention a stated rule.
**Concern:** The amendment to the §3c text must say that `T.name` is never reached by method syntax, or the "no silent priority" reason comes back.

###### V1 — Vote: V1-NONE
**Reasoning:** `T { .. }` matches the same values as `_`, and it tells the caller that `T` is a struct. If the author changes the type to an enum, that caller breaks. The error can say "use `_` or a binding".
**Concern:** Users will try `T { .. }` from Rust habit, and the help text must point them to the fix.

###### V2 — Vote: V2-HIDE
**Reasoning:** When all variants are hidden, outside code cannot match on any variant, so no outside match exists to be incomplete. One rule then covers structs and enums.
**Concern:** None in my domain.

###### V3 — Vote: V3-KW
**Reasoning:** `opaque` changes which code is legal, so it belongs in the declaration syntax with `pub`, not in an annotation. `blink fmt` gets one fixed order.
**Concern:** A new contextual keyword can collide with existing identifiers named `opaque`, so the parser must accept it only before `type`.

###### V4 — Vote: V4-TYPE
**Reasoning:** The error names the type and its owning module, and it reuses the pub-enforcement code. It does not suggest hidden field names, so the author can change those fields later.
**Concern:** The error is less useful inside the owning package, where a field name would help. A secondary note can add it there.

###### V5 — Vote: V5-STATE
**Reasoning:** Debug output is for people who debug. If the spec states the rule, nobody has to guess whether `{:?}` will leak data or hide it.
**Concern:** Authors who store secrets in an opaque type must know that they need to hand-write Debug.

###### V6 — Vote: V6-SAME
**Reasoning:** One rule for every `const`. A second rule for qualified consts is a second thing to learn and to lint.
**Concern:** None.

###### V7 — Vote: V7-E1016. PLT sub-point: yes
**Reasoning:** One `T.` namespace means hover and go-to-definition never need a tie-break. When the clash cannot be seen at the declaration (a trait impl in another package), a use-site ambiguity error with the fix `Trait.name(...)` is the correct diagnostic.
**Concern:** A use-site ambiguity can appear in a downstream package after an upstream upgrade, so the error must name both sources.

###### V8 — Vote: V8-NO
**Reasoning:** YAGNI. No current case needs it, and the inference errors for a polymorphic const are hard to make readable.
**Concern:** None.

###### V9 — Vote: V9-PRELUDE
**Reasoning:** The prelude declares the builtin types, so the "declaring module only" rule holds with no exception.
**Concern:** None.

###### V10 — Vote: V10-CLOSED. PLT sub-point: yes
**Reasoning:** §2.21 stays small. Each combined default is its own named constant, which is easy to find and to document. Stating it normatively stops the question from coming back.
**Concern:** A type with many flags gets a long list of combined constants.

###### C1
- **C1a: yes.** Without it, readers will confuse the two meanings of "opaque" (by-value struct and C handle).
- **C1b: yes.** A generic body is checked once at its definition, so errors point at source the user wrote.
- **C1c: yes.** An alias must not be a way around opacity.
- **C1d: yes.** Outside the module, `==` would read the hidden fields. Also, trait operator calls are not const.

##### AI/ML

###### Q1 — Q1-A
**Reasoning:** One choice per type, made at the declaration, and `opaque` is in the signature line that a model reads. Per-field `pub` adds one choice per field on the most common shape and puts a `pub` on every field of every public record. The error under Q1-A names one word and one module, so the fix is easy to find.
**Concern:** Users who come from Rust may write `pub` on a field by habit; the parser must reject it with a help line that points to `opaque`, not accept it in silence.

###### Q2 — Q2-A
**Reasoning:** The declaration text (`const MsgFlags.NONE`) is the same as the use text, so one grep finds the definition. It reuses `const` syntax and changes nothing in the type body. The same form also answers Q3.
**Concern:** A model may try `const T.NAME` in a module that does not own `T`; that error must name the owning module.

###### Q3 — Q3-NOW
**Reasoning:** The methods-only vote already made `Duration.ms(...)` the stdlib surface, so models will write `T.make(...)` for their own types. Today that fails with an unhelpful error. One form for `const T.NAME` and `fn T.name` is one rule to learn, and it removes a hidden convention.
**Concern:** The §3c amendment must say clearly that a `T.name` fn has no receiver and is never reached by method syntax, or models will think inherent methods are back.

###### V1 — V1-NONE
`T { .. }` tests nothing on a static type. "No pattern" is one rule with no exception.

###### V2 — V2-HIDE
Outside code cannot match, so no outside match can be incomplete. One rule for structs and enums.

###### V3 — V3-KW
`opaque` changes what the type means, and a keyword stays on the signature line.

###### V4 — V4-TYPE
The hidden field name is not part of the API. The help line names the public way in.

###### V5 — V5-STATE
One sentence in the spec gives a model the answer, so it does not have to guess whether Debug leaks fields. The behavior is the same as V5-NORULE; only the explicit statement differs.

###### V6 — V6-SAME
Two rules for two `const` forms add a decision point for no gain.

###### V7 — V7-E1016
One `T.` namespace gives one meaning for `T.x` and one completion list. Sub-point (package-wide check; a foreign trait impl is reported as an ambiguity at the use site, fix `Trait.name(...)`): **yes**.

###### V8 — V8-NO
No need today. YAGNI.

###### V9 — V9-PRELUDE
One owner rule: the module that declares the type.

###### V10 — V10-CLOSED
I move from my round 1 position. A combined flag passed as an argument works at run time through the `|` impl. Only a keyword default needs a const, and a declared named constant covers that. A follow-up ticket would track a need that nobody has yet. Sub-point (§2.21 never admits trait operator calls): **yes**. It tells a model that `|`, `==` or `+` on a user type is a call, so it cannot be in a const expression.

###### C1
- **C1a: yes**, but write it as a semantic rule: `opaque` hides the representation and does not change how values are passed; it is not `@ffi.opaque`. Keep C layout words out of sections/ and put them in the codegen notes.
- **C1b: yes.** Without it, generic code would compile or fail depending on where it is used.
- **C1c: yes.** Otherwise an alias would be a way around the rule.
- **C1d: yes.** It follows from C1b and the V10 sub-point; stating it removes a guess.

##### Minimalism

###### Q1: Q1-A
**Reasoning:** One choice per type covers all six real cases, and it needs no migration. Q1-B adds a choice on every field and a migration through the 3-step bootstrap, and its only gain is mixed structs, which no case needs.
**Concern:** Users may ask for mixed structs later, and someone may try to add per-field `pub` on top of `opaque`. That would give two privacy mechanisms.

###### Q2: Q2-A
**Reasoning:** The type body stays equal to the representation, so the opaque rule has no exceptions. The declaration text matches the use text, which makes the definition easy to find with one search.
**Concern:** Without a written rule, the declared-name form `T.NAME` could later spread to other kinds of item.

###### Q3: Q3-NOW
**Reasoning:** I move back to my Phase A position. In round 1, I asked for a follow-up only because of process: the 4-1 No Inherent Methods vote. All five other panelists now accept recording this as an explicit amendment to §3c, and that answers my concern. Deciding now removes the hidden `Type_name` convention in the same change, so it subtracts a rule instead of postponing one.
**Concern:** Readers may see `fn T.name` as inherent methods returning. The amendment must state clearly that it has no receiver, takes no part in method syntax, and that a clash is E1016.

###### V1: V1-NONE
**Reasoning:** "No pattern" is a shorter rule than "no pattern unless it names nothing". `T { .. }` has no use on a struct, and on an enum it leaks the variant.
**Concern:** It may confuse users who expect a wildcard-style pattern to work.

###### V2: V2-HIDE
**Reasoning:** `TestError` needs it. Code outside the module cannot `match` at all, so the exhaustiveness question never comes up. Hiding the variants also avoids a second idiom: wrapping the enum in a struct with a private field.
**Concern:** None that is serious.

###### V3: V3-KW
**Reasoning:** `opaque` changes what the type means, so it is a modifier and not an annotation. The spec already uses the word.
**Concern:** Users may confuse it with `@ffi.opaque`. C1a's distinction (in spec wording) covers that.

###### V4: V4-TYPE
**Reasoning:** Do not show a field name that the owner is free to change.
**Concern:** The message is slightly less precise when you debug inside the owning package.

###### V5: V5-NORULE
**Reasoning:** Debug is an ordinary impl in the owning module. A special rule here would be a new special case, and this ticket exists to remove special cases.
**Concern:** Derived Debug prints the hidden fields, and some authors will not expect that.

###### V6: V6-SAME
**Reasoning:** One rule for every `const`.
**Concern:** None.

###### V7: V7-E1016
**Reasoning:** One `T.` namespace means no priority rule is needed.
**PLT sub-point: yes.** A cross-package clash is an ambiguity at the use site, and `Trait.name(...)` resolves it. It is never a priority.
**Concern:** A new trait impl in another package can turn existing use sites into errors.

###### V8: V8-NO
**Reasoning:** YAGNI.

###### V9: V9-PRELUDE
**Reasoning:** This falls out of "the module that declares `T`". It is not a separate rule.

###### V10: V10-CLOSED
**Reasoning:** YAGNI. A combined default can be its own named constant.
**PLT sub-point: yes.** §2.21 already bans calls, and an operator through a trait is a call. One clarifying sentence costs nothing.
**Concern:** The first real combined flag may cause pressure to change this.

###### C1: conditions
- **C1a: no as worded.** Yes to "opaque hides the representation; it does not change its value semantics, and it differs from `@ffi.opaque`". No to the C-layout sentence. Layout is a codegen matter, not spec text.
- **C1b: yes.** Without it, generic code breaks depending on where mono instantiates it.
- **C1c: yes.** An alias is a name, not a new type.
- **C1d: yes.** Structural comparison in a const context goes around the owner's impl and leaks the representation.

#### Phase D — Focused round on V5, the V10 sub-point and C1a

##### Systems

**D1: I move to V5-STATE.** AI/ML has it right: "The behavior is the same as V5-NORULE; only the explicit statement differs." If one sentence derives from the existing rule and warns about secrets in logs, it is not a special case, so Min's objection does not apply. Write it as a consequence of the derive rule: derived Debug prints every field, so an owner that holds a secret writes Debug by hand.

**D2: I hold NO, on the word only.** I agree with Min that "One clarifying sentence costs nothing." My objection is to "never". PLT's reason, "const evaluation must stay total and free of effects", is the argument a future const-eval panel should weigh. This panel should not settle it in advance. Use Web's wording: "An operator on a non-builtin type is a trait call, so §2.21 does not admit it." That gives models and users the same answer today and closes nothing that nobody asked to close.

**D3: I move to SEMANTIC-ONLY.** The user rule from 2026-10-02 decides this: C representation is a codegen detail, not spec text. My concern is still met if the sections/ text says that `opaque` does not change value semantics and is not `@ffi.opaque`, and if the by-value C struct sentence goes in the codegen notes. An implementer who turns `Instant` into a handle would break value semantics (copy and identity), and the spec text forbids that.

**Final votes**
- **D1: V5-STATE.** It has the same behavior as NORULE. One derived sentence answers the leak question before anyone asks.
- **D2: NO.** State "not admitted" today, and leave "never" to a future const-eval panel.
- **D3: SEMANTIC-ONLY.** It follows the no-impl-details rule. The C by-value sentence goes in the codegen notes.

##### Web/Scripting

**D1.** I move to V5-NORULE. AI/ML wrote "The behavior is the same as V5-NORULE; only the explicit statement differs", and Min is correct that a normative rule here is a new special case. My DX need is that a user can find the answer, and an informative note does that without adding a rule. Put a one-line note, with an example, under the derive section: "Derived Debug on an opaque type prints all fields; write Debug by hand to hide a secret." That is a note, not a rule.

**D2.** I hold NO on "never", and I agree with Min's "one clarifying sentence". Write: "A trait operator call is a call, so §2.21 does not admit it." That answers AI/ML's need ("tells a model that `|` ... is a call") and DevOps's need. Sys is correct that a normative "never" decides a future const-eval design with no panel. PLT's totality argument holds for today's §2.21, and today's text already gives it.

**D3.** SEMANTIC-ONLY. The user ruled on 2026-10-02: "Memory layout, tag words, C representation and lowering choices are codegen decisions." DevOps's concern (two meanings of "opaque") is a semantic concern, and the semantic sentence answers it: "`opaque` hides the representation and does not change value semantics; it is not `@ffi.opaque`." Sys's guard against pointer indirection belongs in codegen notes, where the people who could make that mistake read.

###### Final votes
- **D1: V5-NORULE.** The behavior is the same either way. Use an informative note, not a new normative special case.
- **D2: NO.** Add a clarifying "not admitted" sentence. Do not write a normative "never" that decides future const-eval with no panel.
- **D3: SEMANTIC-ONLY.** The user's 2026-10-02 ruling keeps C layout out of sections/.

##### PLT

**D1.** I hold V5-NORULE. AI/ML says it exactly: "The behavior is the same as V5-NORULE; only the explicit statement differs." A normative sentence about one trait on one kind of type is a special case that the general derive rule already covers. Web's real concern, secrets in logs, belongs in a non-normative note: "derived Debug prints every field; hand-write Debug to hide one." I support that note, not a rule.

**D2.** I move to NO on the word "never". Sys is right: "A normative 'never' would rule out a future const-eval design without a panel." §2.21 itself names `const fn` as a possible v2, and a sound const-trait design (pure, total, checked impls) could admit some operators later. My real need is met by a clarifying sentence that is true today: "An operator on a user type resolves to a trait method call, so it is not a const expression." That keeps const evaluation total now and leaves the door to a future panel, as Web asks.

**D3.** I move to SEMANTIC-ONLY. The user's rule of 2026-10-02 settles it: C representation is a codegen matter. The meaning still guards against Sys's mistake: "`opaque` changes visibility only, not value semantics, and it differs from `@ffi.opaque`." The by-value C struct sentence goes to the codegen notes.

###### Final votes
- **D1: V5-NORULE.** The general derive rule already decides it; I add a non-normative note on secrets.
- **D2: NO.** Clarify that a user operator is a call (so it is excluded today), without a "never" that pre-empts a future const-eval panel.
- **D3: SEMANTIC-ONLY.** Per the user's no-implementation-details rule; the C layout text goes to the codegen notes.

##### DevOps/Tooling

**D1.** Min says a stated rule "would be a new special case". It would not be one. The sentence says the normal derive rule applies, and it adds no new behavior. A non-normative note is enough: "Derived Debug runs in the owning module, so it prints hidden fields. Write Debug by hand to hide them." The note is there because users will ask this question, and the answer needs one place in the spec to live. I stay with STATE, and I accept that the note can be informative only.

**D2.** Sys and Web are right about the word "never". Any spec text can change by a later panel, so "never" adds nothing. It only reads as a ban on future const-eval work. The part that has value is the clarifying sentence in present tense: "An operator on a user type is a trait call, so it is not a const expression." With that sentence, the error for `MsgFlags.PEEK | MsgFlags.WAITALL` as a default can cite §2.21 directly. I vote YES on that wording, not on "never".

**D3. I move to SEMANTIC-ONLY.** The user's rule from 2026-10-02 settles this: C representation does not go in sections/. The confusion I raised is about meaning, and a semantic sentence fixes it: "`opaque` hides the representation; it does not change value semantics, and it is not `@ffi.opaque`." The by-value C struct text goes in the codegen notes.

###### Final votes
- **D1: V5-STATE.** A short note gives `blink explain`, the docs and models one answer, and it adds no new behavior.
- **D2: YES.** The present-tense clarifying sentence ("an operator on a user type is a trait call, so it is not a const expression") lets the diagnostic cite the rule. Drop the word "never".
- **D3: SEMANTIC-ONLY.** The project rule keeps C layout out of sections/. The semantic sentence alone stops the two meanings of "opaque" from being confused.

##### AI/ML

**D1.** Min: "A special rule here would be a new special case." I agree that the spec must not add a rule. But a sentence that states what the existing rule gives is not a new rule. Write it as a non-normative note under `opaque`: "A derive runs in the owning module, so a derived `Debug` prints hidden fields. To hide them, write `Debug` by hand." That answers the question a model will ask, and it meets the concern that Web, PLT and Min all raised (secrets in logs). No new rule, no special case.

**D2. I move.** Sys: "A normative 'never' would rule out a future const-eval design without a panel." That is correct. A model needs the rule as it is today, not a promise for all time. A present-tense sentence gives the model all it needs: "A trait operator on a user type (`|`, `==`, `+`) is a call, so §2.21 does not admit it." This matches Web's "not admitted". I vote NO on "never" and YES on that present-tense sentence.

**D3.** The user ruled on 2026-10-02 that C representation does not go in sections/. Sys's guard against pointer indirection still holds if the semantic text says "values of an opaque type are passed and stored the same as values of any other type; it is not `@ffi.opaque`". That is a rule about meaning, and a model can check it. The C struct sentence goes in the codegen notes.

###### Final votes
- **D1: V5-STATE**, as a non-normative note that states what the derive rule gives, plus the advice to hand-write Debug for secrets.
- **D2: NO**. Do not write "never". State the present-tense rule ("is a call, so §2.21 does not admit it") in its place.
- **D3: SEMANTIC-ONLY**. The user ruled that C layout stays out of sections/, and the semantic text already covers the pointer-indirection guard.

##### Minimalism

**D1: I move to V5-STATE.** I voted NORULE because I did not want a special case. AI/ML has it right: "The behavior is the same as V5-NORULE; only the explicit statement differs." A sentence that restates what the derive rule already does is not a new rule. Web's concern about secrets in logs is real, and the sentence answers it at no cost. My condition: write it as a consequence, not a new rule. For example: "`derive` on an opaque type works as on any type, and its output shows the hidden fields. To hide them, write the impl by hand."

**D2: yes on the substance, with Web's wording.** Sys says "a normative 'never' would rule out a future const-eval design without a panel." That is fair. A later panel can change any sentence, but "never" invites the reading that it needs extra justification. The sentence should state the fact: "an operator on a user type is a trait call, so it is not a const expression (§2.21)." That also gives PLT and AI/ML what they asked for.

**D3: SEMANTIC-ONLY.** The user ruled on 2026-10-02 that C representation does not go in sections/. Sys's worry about pointer indirection is a codegen worry, so the guard belongs in the codegen notes. The semantic sentence covers DevOps' worry about confusing it with `@ffi.opaque`.

###### Final votes
- **D1: V5-STATE.** It restates existing behavior and costs one sentence. Write it as a consequence, not a rule.
- **D2: YES.** Use Web's wording ("not admitted, because a trait operator is a call"), not "never".
- **D3: SEMANTIC-ONLY.** The project rule keeps C layout out of sections/.

### Final Spec

```blink
@module("clock")

pub opaque type Stamp {
    nanos: Int
}

pub const Stamp.ZERO = Stamp { nanos: 0 }

pub fn Stamp.from_secs(s: Int) -> Stamp {
    Stamp { nanos: s * 1000000000 }
}

// another module
let a = Stamp.from_secs(5)          // ok
let z = Stamp.ZERO                  // ok
let b = Stamp { nanos: 5 }          // error[E1003]: `Stamp` is opaque outside module `clock`
let n = a.nanos                     // error[E1003]
```

- `pub opaque type T` hides the whole body outside the declaring module: no literal, spread, variant, field access, or pattern (`T { .. }` included). An opaque enum hides all of its variants.
- `opaque` is a contextual word between `pub` and `type`. It is not a keyword. There is no per-field `pub`.
- A violation is E1003. The message names the type and the module, never the field.
- The check runs against the module of the source text, not where mono instantiates it. An alias does not open the type. `==` and `<` on an opaque type in a const expression outside its module are errors.
- `opaque` changes visibility, not value semantics, and it is not `@ffi.opaque`. A derived `Debug` prints hidden fields (informative note).
- `pub const T.NAME = <const expr>` and `pub fn T.name(...)` are declared only in the module that declares `T` (the prelude for builtin types). A type-scoped constant is a const reference (§2.21), so it is legal as a keyword default. It follows the annotation rule of a plain `const`. Not allowed on generic types for now.
- `fn T.name` has no receiver. A `self` parameter is an error, and method syntax never reaches it. It is an explicit amendment to §3c No Inherent Methods, and it replaces the hidden stdlib `Type_name` convention.
- Variants, type-scoped constants and functions, and trait associated fns share one `T.` namespace. A clash is E1016, checked across the package. A clash with a trait impl from another package is E0522 at the use site, fixed with `(Trait for T).name()`.
- An operator on a user type is a trait call, so §2.21 does not admit it. `MsgFlags.PEEK | MsgFlags.WAITALL` cannot be a default. Declare the combination as its own constant.
