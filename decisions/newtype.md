[< All Decisions](../DECISIONS.md)

# Newtype: One-Field Struct — Design Rationale

**Gap:** The spec has no rule that names a type that wraps exactly one value of another type and is nominally distinct from it. It showed two forms and called both "the newtype": a single-variant payload enum named after itself (`type Errno { Errno(Int) }`, §3.4 and §7) and a one-field struct (`type UserId { value: Int }`, §3.6 and §3.8). No panel had voted on how to write such a type. The stdlib `Errno` used the enum form. Every other wrapper in lib/std (`Pid`, `Date`, `Duration`, `Instant`, `TcpSocket`, `Connection`) is a one-field struct.

**Result:**

- **Q1 (6-0, S):** the spec names the one-field struct as the newtype. `type Errno { code: Int }`. Build it with a struct literal, read it with `e.code`, take it apart with a struct pattern. Derives, JSON and generics follow the struct rules. `type X = Y` is an alias, not a newtype. There is no tuple struct, no `newtype` keyword and no implicit conversion in either direction. A single-variant enum is an ordinary enum.
- **Q2 (5-1, G):** the newtype text says: name the field for what it holds; use `value` when nothing better fits. Minimalism dissents for G0 (no field-name advice in the spec).
- **Q3 (6-0, T, after 4-2 in Phase C):** an opt-in `@json(transparent)` is filed as a separate, gated ticket. The spec does not describe it. JSON of a newtype follows the struct rules: `{"code":2}`.
- **Follow-up Q1 (6-0, X):** a variant with the name of its own enum (`type Token { Token(Str), End }`) is an error at the declaration, reported once, at the variant. All six seats changed their earlier "legal" vote.
- **Follow-up Q2 (6-0, R):** the error is E0518 `NameCollision`, widened to cover this case.

Points that all six seats accepted without a vote: no new syntax and no keyword; no lint on a single-variant enum; `lib/std` `Errno` becomes `pub type Errno { code: Int }`; `FsError.code` becomes `FsError.errno`, and the number reads as `err.errno.code`; the test copies that model std `Errno` migrate, the tests whose point is a single-variant enum stay (renamed off "Errno"), and no test is deleted; the diagnostics below; the `let Code(n) = c` and `let S { x, .. } = s` parse errors and the generic `Deserialize` internal error are implementation bugs, not spec questions.

The panel did not vote on the sha256 decision. See *Concerns* for the moderator's correction.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote and re-vote rounds. Each panelist's text below is a verbatim excerpt of the panelist's own reply. Ticket identifiers are removed from the excerpts.

#### Phase A — Independent proposals

Phase A proposed these forms: a one-field struct (Systems S1, Web W1, PLT P1, AI/ML A1, Minimalism M1; DevOps D2 as fallback), the self-named single-payload enum (DevOps D1; Systems S2, PLT P2 and AI/ML A2 as fallbacks), and "name neither form" (Minimalism M2, fallback).

- **Systems:**

> # Systems seat — Phase A
>
> ## Proposal S1 (my pick): the newtype is a one-field struct. One form, no new syntax.
>
> The spec names the case in one place (§3, near the struct section): "A newtype is a struct with exactly one field. It is nominally distinct from the field's type. Use it to make a value that cannot be mixed up with its inner type." No new keyword, no new kind of type. Every rule that already holds for structs holds for it.
>
> ```blink
> @derive(Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { code: Int }
>
> type Wrap[T] { value: T }
>
> fn open_fail(rc: Int) -> Result[Int, Errno] {
>     if rc < 0 { return Err(Errno { code: -rc }) }
>     Ok(rc)
> }
>
> fn main() ! IO {
>     let e = Errno { code: 2 }
>     io.println("{e.code}")                 // read: plain field access
>     match e {
>         Errno { code: 2 } => io.println("ENOENT")
>         Errno { code } => io.println("other {code}")
>     }
>     let w = Wrap { value: 3 }
>     io.println("{w.value}")
> }
> ```
>
> - Declare: `type T { name: U }`. Build: struct literal. Read: `.name`. Match: struct pattern (and `let T { name } = x` once the open `let`-struct-pattern parse gap is fixed; that gap is a bug against :3620 either way).
> - Derives, JSON, generics: exactly as for any struct. JSON is `{"code":2}`. No special transparent JSON form; YAGNI until someone asks with a real wire format.
> - Alias `type X = Y`: same type, no distinction. Unchanged. The spec says in one line: "an alias is not a newtype".
> - Payload enum: a single-variant payload enum stays legal (it is an enum with one variant), but the spec does not call it a newtype and the stdlib does not use it as one.
>
> Why, from what the hardware sees:
> - A field read is a load. The enum form makes the read a `match` over a one-arm sum type; the compiler must prove "one variant" to drop the tag. Today that proof is keyed on the literal name `std_errno.Errno`, breaks for non-Int payloads, and miscompiles as-patterns. The struct form has no tag to drop. Three open codegen bugs go away by construction, not by a cleverer shape check.
> - Predictable cost model: "a struct of one field costs what the field costs" is a rule a user can hold in their head. The spec does not state it (layout is not spec, DECISIONS.md:401); the implementation can and should do it, shape-based, for every one-field struct.
> - Monomorphization: `Wrap[T]` is a generic struct, instantiated per `T` like every other. The generic-enum Deserialize ICE is not on this path.
> - One form means one shape to optimize and test. Two "newtype idioms" means two lowerings to keep in sync.
> - It is what lib/std already does: Pid, Date, Duration, Instant, TcpSocket, Connection. Errno is the single outlier. The orphan-rule text (:4871) and the no-1-tuple text (:6471) already say "struct".
>
> Cost: construction is longer (`Errno { code: rc }` vs `Errno(rc)`). About 22 lib/std lines. I accept that; reads (`e.code`) get shorter and need no `match`.
>
> Cross-language: Go `type Errno struct{ code int }` and Zig `struct { code: i32 }` work this way with no special form. Rust `struct Errno(i32)` is a tuple struct, which Blink does not have and should not add for this. Haskell `newtype` is a distinct keyword because Haskell boxes `data`; Blink has no such cost gap to close.
>
> ## Migration
>
> - lib/std/errno.bl: `pub type Errno { code: Int }`. Rewrite ~22 build sites and 2 match sites in libc.bl, fs_ops.bl, io.bl, fs_error.bl. Breaking change to `std.errno`; pre-1.0, note it in the changelog.
> - Spec: rewrite 03_types.md:2366 and 07:1568 (and 04_effects.md:1038 wording) to the struct form; keep :4871 and :6471, now pointing at the new newtype paragraph. llms-full text follows.
> - decisions/sha256-std.md: amend the type line to `type Sha256Digest { bytes: Bytes }`. Nothing in tree to migrate.
> - Tests: copies that mirror the stdlib Errno migrate. Tests that test single-variant enums as enums (Code, Name, nested C/B/A) stay; they test enums, not newtypes.
>
> ## Diagnostics
>
> - `Errno(5)` on the struct: existing UndefinedFunction help, made specific: "`Errno` is a struct; build it with `Errno { code: 5 }`".
> - `e == 2` or passing `e` where `Int` is wanted: TypeError with help "read the inner value with `e.code`".
> - Expecting distinction from an alias (`type UserId = Int`, then mixing): no error is possible; the alias paragraph says so plainly.
>
> ## Open edge: a variant named like its own enum
>
> Legal, no warning. `type Token { Token(Str), End }` is an enum with a variant named like it; a bare `Token(...)` is the variant, because a type name is never a value ("values come first", worktree :2284). Under S1 this case no longer carries the newtype idiom, so the rule needs no newtype-specific clause.
>
> ## Proposal S2 (fallback, not preferred): name the self-named single-variant enum as the newtype
>
> If the panel wants terse `Errno(rc)` construction: the spec names `type T { T(U) }` as the newtype, fixes `let T(x) = v`, and states it has no tag operations. I oppose it: it makes the newtype a special case of sum types, so the implementation needs a shape rule to undo the sum, and a user's cost model has to include "unless it has one variant".

- **Web/Scripting:**

> # Web/Scripting seat — Phase A
>
> ## Proposal W1 (my pick): name the case, spell it as a one-field struct
>
> **Name it.** Yes. The spec teaches two forms today and calls both "the newtype". That is the worst outcome for a learner: two answers, no rule. Every "how do I make a UserId" question on Stack Overflow will get both answers. One sentence in §3 fixes it: *"A newtype is a struct with one field. Use it to make a type that holds one value of another type and is distinct from it."* No new syntax, no new keyword.
>
> ```blink
> @derive(Eq, Hash, Clone, Debug, Serialize, Deserialize)
> type UserId { value: Int }
>
> fn lookup(id: UserId) -> Str {
>     "user {id.value}"
> }
>
> fn main() ! IO {
>     let id = UserId { value: 42 }
>     io.println(lookup(id))
>     let UserId { value } = id      // spec 03_types.md:3620 says legal; parser bug today
>     match id {
>         UserId { value: 0 } => io.println("root")
>         UserId { value: n } => io.println("user {n}")
>     }
> }
> ```
>
> - **Build:** struct literal. **Read:** `.value`. **Match / destructure:** struct pattern (irrefutable in `let`).
> - **Derives / generics:** whatever structs do, no special case. `type Wrap[T] { value: T }` is a plain generic struct.
> - **JSON:** struct rules, `{"value": 42}`. (See W2 for the wire-format problem.)
> - **Convention:** name the field `value` unless a domain name reads better. Kotlin `value class UserId(val value: Int)` uses the same word, so JS/Kotlin devs read it at once.
>
> **Why struct, not the self-named enum** (DX view):
> 1. Reading the inner value is `.value`, like every language a web dev knows. The enum form needs `match e { Errno(n) => n }` to get one Int out. That is three lines of ceremony and the top SO question in waiting: "how do I get the Int out of Errno?"
> 2. One concept (struct) the dev already learned; no "enum with one case that is not really an enum" lesson.
> 3. No variant exists, so the open edge of the type-named-like-a-variant rule never touches a newtype.
> 4. Already the dominant form in lib/std (Pid, Date, Duration, Instant, TcpSocket, ...). The enum form exists in one stdlib type.
>
> **Cost I accept:** `UserId { value: 42 }` is longer than `UserId(42)`. A positional call for structs is a separate, larger question (tuple structs); I do not open it here. YAGNI.
>
> **Relation to other forms:**
> - `type X = Int` (and `@where` refinement aliases) stay the same type. Not a newtype; spec says so in one line.
> - `type Errno { Errno(Int) }` stays legal Blink. It is a payload enum with one variant, nothing more. The spec stops calling it a newtype.
>
> **Wrong-use diagnostics** (shape):
> - `UserId(42)` → existing E-UndefinedFunction help: "`UserId` is a struct; build it with `UserId { value: 42 }`".
> - `let n: Int = id` / passing `UserId` where `Int` is expected → TypeError, with help "`UserId` holds an `Int`; read it with `id.value`".
> - `id == 42` → TypeError, help "compare `id.value == 42`".
>
> **Open edge (variant named like its own enum):** legal, no warning. `type Token { Token(Str), End }` is a real enum; the variant lives in the type's own namespace, as the worktree text (F6 :2284, :2299) already says. The newtype question no longer depends on it.
>
> **Existing uses:**
> - lib/std `Errno` → `pub type Errno { value: Int }`; ~22 `Errno(rc)` sites become `Errno { value: rc }`; the 2 match sites become `.value`. `FsError.code.value` reads fine. Mechanical chore; FFI shape stays an impl detail (the open codegen tickets move to "one-field struct").
> - Spec 03_types.md:2366, 07:1568, llms text: rewrite to the struct form. :4871 and :6471 already agree.
> - ~40 test copies: keep the ones that test single-variant enums (still legal); migrate the ones whose point is Errno-as-newtype. No test deletion.
> - sha256 decision: `type Sha256Digest { bytes: Bytes }`. The decision voted "a newtype over Bytes, not hex Str"; the form follows this ruling, no re-vote.
>
> ## Proposal W2 (follow-up, separate ticket): transparent JSON opt-in
>
> Web devs will put `UserId` in an API struct and get `{"user": {"value": 42}}` when the wire wants `{"user": 42}`. Today the enum form is worse (`{"type":"Code","_0":5}`). Fix with an explicit opt-in, not magic by field count:
>
> ```blink
> @derive(Serialize, Deserialize)
> @json(transparent)
> type UserId { value: Int }   // to_json -> 42
> ```
>
> Serde `#[serde(transparent)]` is the precedent. Error when the struct has more than one field. Out of scope for this ticket; file it so W1 does not ship with a known papercut unnamed.
>
> ## Cross-language
> Kotlin `value class`, TS branded types, Python `typing.NewType` all read the inner value as a field or the value itself; none make you pattern-match. Rust/Haskell positional forms suit their users; ours come from JS/Python.

- **PLT:**

> # PLT seat — Phase A
>
> ## Framing
>
> A newtype is a nominal N with an isomorphism to T: one intro, one elim, nothing else. Blink already has two sound encodings: a product of arity one (one-field struct) and a sum of arity one (one-variant, one-payload enum). The defect is that the spec calls both "the newtype" with no rule, so readers learn two idioms for one concept.
>
> No `newtype` keyword. Haskell needs `newtype` apart from `data` only because of laziness (irrefutable match, no extra bottom). Blink is strict, so the keyword would carry no meaning. It would be a third form.
>
> ## P1 (preferred): the newtype is a one-field struct, and the spec names it
>
> New §3 subsection *Newtypes*: "A newtype is a struct with exactly one field. It is nominally distinct from its field type. No implicit conversion goes either way. It gets a trait of the field type only by derive or impl."
>
> ```blink
> @derive(Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { code: Int }
>
> type Wrap[T] { value: T }
>
> fn fail(rc: Int) -> Result[Int, Errno] {
>     Err(Errno { code: rc })
> }
>
> fn main() ! IO {
>     let e = Errno { code: 2 }
>     let n = e.code
>     match e {
>         Errno { code: 2 } => print("ENOENT")
>         _ => print("other {n}")
>     }
> }
> ```
>
> Why the product:
> - Elim is a total projection (`e.code`). The sum form eliminates only by case analysis, and its `let` form is a parse error today (P6).
> - Wire form `{"code":2}`, set by the field name. The enum gives `{"type":"Code","_0":5}`. A JSON special case for one-variant enums would make the encoding depend on variant count: adding a variant changes existing values on the wire. That does not compose; I reject it.
> - No value named like its type, so no contact with the shadow rule.
> - The spec says this twice already (03:4871, 03:6471); lib/std does it (Pid, Date, Duration). Errno is the outlier.
>
> Generics, derives, orphan rule: as any struct. Derives stay explicit per trait (no GeneralizedNewtypeDeriving), so coherence is untouched. Build and read are pure.
>
> Existing uses:
> - lib/std: `type Errno { code: Int }`; ~22 build sites become `Errno { code: rc }`, 2 match sites `Errno { code: c }`. FsError's `code` field may want a rename (`errno`) to avoid `err.code.code`.
> - Spec 03:2366 and 07:1568 move to the struct form. The 03:2382 `Code` example stays an enum (it is about payload enums). Drop "zero-cost/transparent" from spec text (layout is not spec, DECISIONS:401).
> - Tests: migrate the Errno copies; payload-enum tests keep their enums.
> - sha256: `type Sha256Digest { bytes: Bytes }`. Same meaning (distinct from Bytes/Str), so an editorial note on that decision.
>
> Diagnostics:
> ```
> type Errno(Int)
> // error[ParseError]: Blink has no tuple structs
> //   help: a newtype is a one-field struct: type Errno { code: Int }
> let e = Errno(2)
> // error[UndefinedFunction]: `Errno` has no constructor call
> //   help: build it with a struct literal: Errno { code: 2 }
> ```
> `type Errno = Int` gets no diagnostic: an alias is the same type by rule. *Newtypes* states the contrast in one line.
>
> The one-variant enum stays legal as a sum with one summand. It is not "the newtype" and gets no lint.
>
> ## Open edge: a variant named like its own enum
>
> Legal, no warning, under P1 or P2. In `type Token { Token(Str), End }` the bare `Token(...)` is the variant ("values come first"; a type name is never a bare value), so nothing is ambiguous. The owner rule is about a type that shadows a variant of some *other* enum; here the type in scope is the variant's own enum.
>
> ## P2 (fallback, for positional build)
>
> Name the one-variant one-payload enum as the newtype. Then the spec must also make `let Errno(n) = e` legal (03:3626 claims it; today a parse error), fix the tagged JSON form `{"type":"Errno","_0":n}` as the rule with no special case, and rewrite 03:4871 and 03:6471. Cost: elim only by pattern, a noisy wire form. Sound, but I vote against it.
>
> ## Cross-language
>
> Rust `struct E(i32)` and OCaml `E of int` are positional because each has a cheap positional elim (`.0`, irrefutable `let`). Blink has neither and no tuple structs (03:6471).
>
> Impl bugs either way: `c == 5` on a payload enum is accepted ; `let Code(n) = c` fails to parse against 03:3626.

- **DevOps/Tooling:**

> # DevOps/Tooling seat — Phase A
>
> My test: one written form per intent, so the LSP, the linter and the error text can name it. Two "newtype idioms" with no rule between them give two hover texts, two quick-fixes and a lint that cannot say which is right.
>
> ## Proposal D1 (preferred): name it; the self-named one-payload enum is the newtype
>
> **Rule.** A *newtype* is an enum with exactly one variant, which has the type's own name and exactly one positional payload. No new keyword, no new syntax.
>
> ```blink
> @derive(Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { Errno(Int) }
>
> type Wrap[T] { Wrap(T) }
>
> fn describe(e: Errno) -> Str {
>     let Errno(n) = e
>     "errno {n}"
> }
>
> fn is_again(e: Errno) -> Bool {
>     match e {
>         Errno(11) => true
>         Errno(_) => false
>     }
> }
>
> fn main() ! IO {
>     let e = Errno(11)
>     io.println(describe(e))
>     io.println("{is_again(e)}")
> }
> ```
>
> - **Build:** `Errno(rc)`. Same as today; the 26 lib/std lines and ~40 test copies stay as written.
> - **Read:** irrefutable `let Errno(n) = e` (03_types.md:3626 already promises this; the parse error is an impl bug), or `match`. No `.0`, no auto-unwrap, no implicit conversion either way.
> - **Derives:** all derives work on the payload. `Debug` prints `Errno(11)`.
> - **JSON:** a newtype is transparent: `Errno(11).to_json()` is `11`, and `11` deserializes to `Errno(11)`. Today's `{"type":"Code","_0":5}` is noise for a type whose only job is a name. Serde does the same for `struct E(i32)`. Other single-variant enums (variant not self-named, or more than one payload) keep the tagged form.
> - **Generics:** `Wrap[T]` is a newtype. The Deserialize ICE is an impl bug, not a spec question.
> - **Relation to other forms:** `type X = Y` is the same type (unchanged). A one-field struct is a struct: use it when the field name tells the reader something (`Duration { nanos }`, `Pid { handle }`); JSON is an object. A payload enum with two or more variants, or a variant not named like the type, is an ordinary enum.
>
> **Spec edits.** 03_types.md gets one short "Newtypes" subsection with the rule above. 6471 changes "use a named struct" to "use a newtype, `type UserId { UserId(Int) }`". 4871 orphan text changes to `type MyResponse { MyResponse(HttpResponse) }`. 2366 and 07:1568 already agree. sha256 decision already uses this form. lib/std one-field structs stay; no migration.
>
> **Open edge (variant named like its own enum).** Legal, no W1011. Bare `Errno` / `Errno(...)` resolves to the variant of the type of that name. The owner rule fires only when type `X` and variant `X` come from different declarations: with `std.errno.Errno` in scope and `type Os { Errno(Int) }`, bare `Errno(3)` is an error; write `Os.Errno(3)`.
>
> **Diagnostics** (each names the newtype and gives the fix):
>
> ```
> error[E0300]: expected `Int`, found `Errno`
>   let n: Int = e
>                ^ `Errno` is a newtype over `Int`
>   help: unwrap it: `let Errno(n) = e`
>
> error[E0300]: cannot compare `Errno` with `Int`
>   if e == 11 {
>   help: wrap the literal: `e == Errno(11)`
>
> error[NoSuchField]: `Errno` has no field `0`
>   help: newtypes have no fields; use `let Errno(n) = e`
>
> error[...]: `UserId` has no constructor call    (one-field struct)
>   help: build it with `UserId { value: 5 }`, or declare a newtype `type UserId { UserId(Int) }`
> ```
>
> **Tooling.** Hover: "newtype over `Int`". Rename of the type renames the variant too (one symbol in the LSP index, two sites). Completion after `Errno(` offers `Int` context. `blink fmt` keeps `type Errno { Errno(Int) }` on one line. Lint W-next (warn): a single-variant one-payload enum whose variant is *not* named like the type ("did you mean a newtype? rename the variant to `Errno`"), since that shape gets tagged JSON and readers will not expect it.
>
> **Tradeoffs.** Pro: zero churn, matches Haskell/OCaml, positional build is short, match works now. Con: name said twice; JSON form now depends on a naming rule (but the lint makes it visible); the struct form still exists, so the help text must teach when to pick which.
>
> ## Proposal D2 (fallback): name it; the one-field struct is the newtype
>
> `type Errno { code: Int }`, read via `e.code` (autocompletes well), JSON `{"code":11}`. Rewrite 2366, 07:1568, sha256, lib/std `Errno` (26 lines) and ~40 test copies to `Errno { code: rc }`. Self-named-variant edge then needs no special case. I rank this lower: more churn, longer build sites, and the irrefutable-pattern and `match Errno(11)` cases get worse, not better.
>
> ## Not recommended: leave it unnamed
>
> Two idioms, no rule: the LSP cannot offer one quick-fix, the 6471 and 2366 texts contradict, and the open edge of the type-named-like-a-variant rule stays open.

- **AI/ML:**

> # AI/ML seat — Phase A: newtype
>
> ## Main point
> Today the spec teaches two forms for one job (03:2366/07:1568 enum, 03:4871/6471 struct). For a model that learns from the spec, two forms with no rule to choose means a coin flip at each wrapper, and code from different models (or different prompts) disagrees. The language must name the case and give **one** form. I propose the form the spec and lib/std already use most: the one-field struct.
>
> ## Proposal A1 (preferred): "a newtype is a one-field struct"
> No new syntax. A short section in 03_types.md names the case and sends both existing passages (2366, 4871, 6471, 07:1568) to it.
>
> ```blink
> @derive(Eq, Ord, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { code: Int }
>
> type Wrap[T] { value: T }
>
> fn check(rc: Int) -> Result[Int, Errno] {
>     if rc < 0 { return Err(Errno { code: -rc }) }
>     Ok(rc)
> }
>
> fn main() ! IO {
>     match check(-2) {
>         Ok(n) => print("ok {n}")
>         Err(e) => print("errno {e.code}")
>     }
>     let Errno { code } = Errno { code: 5 }   // irrefutable, per 03:3620
> }
> ```
>
> - Declare: `type N { field: T }`. Spec guidance: name the field for what it holds; use `value` when nothing better fits (one default removes a decision).
> - Build: struct literal. Read: `e.code` — no match needed. Match/destructure: struct pattern.
> - Derives, JSON, generics: all struct rules, no special case. JSON is `{"code":3}`, which a reader (human or model) can read; the enum form gives `{"type":"Code","_0":5}`, and `_0` is a key no one would guess.
> - Alias: `type N = T` stays the same type; the new section says so in one line, because "alias = newtype" is a common model mistake (Go/TS training data).
> - A self-named single-variant enum stays legal — it is an enum like any other — but the spec stops calling it a newtype. No lint: it is not wrong, only not the named form.
>
> **Tradeoffs.** Build costs about 3 more tokens per site (`Errno { code: rc }` vs `Errno(rc)`). Read saves more: a field access is about 3 tokens; a match to unwrap is about 10 tokens and a block. Wrappers are read more than built. The real gain is zero decision points: one form, one JSON shape, one read path. Weakness: training data from Rust (`struct Errno(i32)`, `e.0`) and Haskell pushes models to write `Errno(rc)`. The diagnostic below must catch that at once.
>
> **Cross-language.** Go (`type X struct{ v int }`) and Kotlin (`value class X(val v: Int)`) also put a name on the field. Rust's tuple struct is the main reason models will try `X(v)`.
>
> ## Diagnostic shape
> `Errno(rc)` where `Errno` is a one-field struct already fails with UndefinedFunction + help. Make the help fill in the field name, so the fix is mechanical:
>
> ```
> error[E....]: `Errno` is a struct and has no constructor call
>   --> io.bl:12:16
>    |  Err(Errno(rc))
> help: build it with a struct literal: `Errno { code: rc }`
> ```
>
> Same for `e.0` (NoSuchField): `help: the field of Errno is `code`: write `e.code``.
>
> ## Existing uses
> - lib/std `Errno` → `type Errno { code: Int }`; ~22 build sites and 2 matches are mechanical. `FsError.code` field type is unchanged. Layout (the "transparent" C shape, open codegen tickets) is codegen work, out of the spec.
> - ~40 test copies → migrate with the stdlib; keep a few tests of a self-named enum, since that form stays legal.
> - DECISIONS.md:335: still holds (Errno exists, distinct from Int); only its spelling changes. llms-full.md lines 323/331/1323 update to the struct form.
> - sha256 decision: `type Sha256Digest { bytes: Bytes }`; its intent (distinct type over Bytes, not hex Str) is kept. Amend the text, no re-vote.
>
> ## Open edge: a variant named like its own enum
> Legal, no warning. `type Token { Token(Str), End }` has one declaration, so a bare `Token(s)` has one meaning; the owner rule targets a type and a variant from *two* declarations. With A1 this edge no longer carries newtypes, so it needs no special rule.
>
> ## Proposal A2 (fallback, if the panel wants short construction)
> Name the self-named single-variant enum as the form and drop the struct passages. Then the spec must also make `let Errno(n) = e` parse (03:3626 already says it is irrefutable) and fix the JSON to an untagged inner value, else reads stay costly and the JSON stays opaque. I rank A2 below A1: it keeps the fewest tokens at build but adds a special read path and a special JSON rule, which are two more things a model must learn.
>
> ## Separate defects (not this vote)
> `let S { x, .. } = ...` and `let Code(n) = c` are parse errors though the spec allows them; `c == 5` on a payload enum passes check . File or link as bugs.

- **Minimalism:**

> # Minimalism seat — Phase A
>
> ## Position
>
> We do not need a newtype feature. The language already has two general forms that give a nominally distinct wrapper, and both fall out of rules we already have. The real defect is that the spec calls two different things "the newtype" and picks neither. Fix that with one sentence and one convention, not with syntax.
>
> ## M1 (preferred): no new form; the one-field struct is the documented idiom
>
> - **Named?** Only in prose. A "newtype" is a one-field struct. The spec gets no grammar rule, no keyword, no special typing for it.
> - **Declare / build / read:**
>
> ```blink
> @derive(Eq, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { code: Int }
>
> fn last_error() -> Errno {
>     Errno { code: libc_errno() }
> }
>
> fn is_not_found(e: Errno) -> Bool {
>     e.code == ERR_NOENT
> }
>
> fn main() ! IO {
>     let e = Errno { code: 2 }
>     io.println("{e.code}")
> }
> ```
>
> - **Match:** `match e { Errno { code } => ... }` works the same as for any struct. Most code does not match at all: a field read does the job.
> - **Derives / JSON / generics:** what structs already do. JSON is `{"code":2}`, which is better than the enum form's `{"type":"Code","_0":2}`. `type Wrap[T] { value: T }` works. Generic Deserialize fails with the same ICE for structs and enums (I probed `Wrap[T] { value: T }`), so that bug is not a reason to pick either form.
> - **Relation to other forms:** an alias stays "same type". A one-field enum stays legal, but only as an enum with one variant. It has no newtype status and no special rules. Tag ops stay off it (DECISIONS:401).
> - **Why struct over enum:** structs already do all of this. The spec already uses them for this job at 03:4871 (orphan rule) and 03:6471 (no 1-tuples). lib/std already uses them about 11 times (Pid, Date, Duration, Instant, TcpSocket...), and Errno is the only enum case. Choosing the struct removes one idiom. Choosing the enum would rewrite the bigger set or leave two idioms. The field name also documents what the value is (`code`, `nanos`), and `_0` does not.
>
> **Existing uses:**
> - lib/std `Errno` becomes `type Errno { code: Int }`. That changes about 22 build sites and 2 matches (fs_error.bl:51, :69 become `e.code`). `FsError.code.code` reads badly, so either rename the FsError field to `errno` or name the inner field `value`. I prefer `FsError.errno` with `Errno.code`.
> - The ~40 test copies of `type Errno { Errno(Int) }` stay. They are valid single-variant-enum tests. Rename them to drop the word Errno where they claim to model std.
> - Spec: change 03:2366 and 07:1568 to the struct form. Keep 03:4871 and :6471, and add one line at 6471: "A newtype is a one-field struct; Blink has no other newtype form."
> - sha256: write `type Sha256Digest { bytes: Bytes }`. Only the spelling changes; the decision's intent ("a distinct type, not bare hex") holds.
> - DECISIONS:335 stands. It voted that Errno exists and is distinct from Int, not on the spelling. "Zero cost" is lowering, which is out of spec. The compiler may lower any one-field struct to its field; that work moves to the open codegen tickets.
>
> **Diagnostics:** the existing ones cover it. Extend the help text:
> - `Errno(5)` when Errno is a struct gives UndefinedFunction (today: "has no constructor call"). Help: ``build it with `Errno { code: 5 }` ``.
> - `let e: Errno = 5` gives TypeError. Help: ``wrap the value: `Errno { code: 5 }` ``.
>
> **Open edge (variant named like its own enum):** legal, with no warning. In `type Token { Token(Str), End }`, the bare `Token(...)` is the variant ("values come first"), and its own enum is the only type of that name, so nothing is ambiguous. The owner rule about another enum's variant does not apply. Under M1 this edge is rare and not tied to newtypes.
>
> ## M2 (fallback): spec names neither form
>
> Keep both forms. Fix only the contradiction: 2366, 07:1568, 4871 and 6471 each say "a single-variant enum or a one-field struct is nominally distinct", and Errno stays as it is. This costs nothing, but users and LLMs keep seeing two idioms. Choose M2 only if the panel will not touch lib/std.
>
> ## Rejected: new syntax
>
> `struct Errno(Int)`, `newtype Errno = Int`, Go's `type Errno Int`. Each adds a third form to save a few characters at build sites. Rust needs tuple structs because it has positional structs everywhere. Blink chose named fields and no 1-tuples (03:6471). Go's `type X Y` would also sit right next to the alias `type X = Y`, which differs by one `=`. That is a trap for humans and for LLMs.
>
> ## Separate bugs (not this ticket)
>
> `let Code(n) = c` and `let S { x, .. } = s` are parse errors, but the spec allows them (03:3620, :3626). File them as impl bugs. They affect both forms equally.
>
> **Vote intent:** M1 > M2 > any new syntax.

#### Phase B highlights

Phase B round 1: all six seats ended on the one-field struct (S). DevOps moved from the enum form (E) to S. The excerpts below are the replies to the strongest case for E, which was DevOps D1 ("zero churn, short build, transparent JSON").

- **DevOps (moves from E to S):**

> ## Position: I change from E to S
>
> plt's point decides it for me: "A JSON special case for one-variant enums would make the encoding depend on variant count: adding a variant changes existing values on the wire." My D1 transparent-JSON rule had exactly that problem, and my V4 lint was only there to make the hidden rule visible. A rule that needs a lint to be visible is a bad rule. Without the JSON special case, E gives `{"type":"Errno","_0":11}`, and nothing in E beats S. I merge into S (sys S1 / plt P1 / web W1 / aiml A1 / min M1).
>
> Tooling reason too: `e.` in the LSP completes `code`; hover on the field shows `Int`. The enum form gives completion nothing to offer and needs a `match` snippet to read the value.
>
> ```blink
> @derive(Eq, Hash, Clone, Debug, Serialize, Deserialize)
> pub type Errno { code: Int }
>
> fn fail(rc: Int) -> Result[Int, Errno] {
>     Err(Errno { code: rc })
> }
>
> fn main() ! IO {
>     match fail(2) {
>         Ok(n) => io.println("{n}")
>         Err(e) => io.println("errno {e.code}")
>     }
> }
> ```

- **PLT (answer to DevOps):**

> ## Answer to devops (D1), the strongest case against S
>
> devops: zero churn, short `Errno(rc)`, and "a newtype is transparent: `Errno(11).to_json()` is `11`".
>
> 1. **Transparent JSON under E does not compose.** The wire form would then depend on the variant's *name* and *count*. Rename the variant, or add `Unknown`, and every stored value changes encoding with no type error at the change site. A rule that turns on a spelling is not a typing rule. Under S the wire form follows from one rule (struct = object), and a later opt-in is per type and explicit.
> 2. **Churn is small.** 26 lib/std lines, mechanical. The language lives longer than this diff.
> 3. **Pattern power is equal.** devops's `Errno(11) => true` is `Errno { code: 11 } => true`. Irrefutable `let` is the same bug in both forms (03:3620 and :3626).
> 4. **E makes the newtype a special case of sums.** Exhaustiveness, JSON and lowering each need "unless it has one self-named variant". sys's three open codegen tickets are that special case leaking.

- **Minimalism (drops N, answers DevOps):**

> ## S vs E vs N
>
> **S.** I drop N (my M2). Five seats prefer S, and devops lists it as their fallback. N kept two idioms only to avoid touching lib/std, and nobody else wants that. So I merge into S.
>
> **Strongest point against me: devops D1 has zero churn, a short positional build, and one LSP symbol.** My answer:
> - The churn is small and runs one way. One lib/std type (26 lines) moves to S. Under E, the spec text at 4871/6471 changes and about 11 lib/std one-field structs are left as a second form, which D1 keeps on purpose ("use it when the field name tells the reader something"). That is two idioms again, with a taste rule between them, which is the defect this ticket exists to remove.
> - D1 also needs new machinery that S does not: a naming rule that decides the JSON shape, a new lint (V4), and a parse fix promoted to a newtype feature. Each is new surface. S adds one paragraph.
> - A shorter build costs a longer read. `e.code` is a projection. `let Errno(n) = e` is a pattern that does not parse today.

- **Systems (answer to DevOps):**

> **Against devops D1 ("zero churn, positional build is short").** The churn is about 26 lib/std lines, one time, mechanical. What E keeps is permanent: a read path that needs a pattern, a JSON rule that depends on the variant's name, and a lowering that must prove "one variant" to drop a tag. That proof is where three open codegen bugs live today. Under S those bugs are not fixed by a better shape check; the shape has no tag. A short build site does not pay for that. The devops tooling points (one hover text, one quick-fix, one lint target) hold for S just as well: "newtype: struct with one field" is one rule the LSP can name.

- **Web/Scripting (answer to DevOps, and the opt-in JSON ticket):**

> **Strongest point against me (devops D1):** "zero churn, positional build is short, match works now", plus transparent JSON.
> - Churn: about 24 lib/std lines and a chore. We pay that once. Users pay the reading cost on each use.
> - Short build: `Errno(rc)` is shorter to write, but you build a newtype in one place (the FFI edge) and read it in many. `e.code` beats `let Errno(n) = e` on each read, and it autocompletes, which devops's own tooling test values.
> - "Match works now": the read path that E needs (`let Errno(n) = e`) is the one that is a parse error today. The struct read (`e.code`) works today.
> - JSON: devops's transparent rule makes the wire format depend on whether a variant name matches the type name. A rename of one variant changes the API payload. A JS dev will never guess that. I side with plt here.
>
> **V1 JSON:** struct rules (`{"code":2}`) under S. I keep W2 as a separate opt-in ticket (`@json(transparent)`, error if the struct has more than one field). It is explicit, it does not depend on a naming rule, and serde users already know it. Not part of this vote.

- **AI/ML (answer to DevOps):**

> ## Answer to devops (strongest point: zero churn, short build, Haskell/OCaml/Rust data)
> - Churn is a one-time cost of about 24 lib/std lines. A second idiom costs each generated program.
> - Training data pushes models toward `Errno(rc)` and `e.0`. That is the case for a good diagnostic, not for the form. With the filled-in help (V5), a model fixes the error on its first retry.
> - D1's transparent JSON hangs on a naming rule: `type Errno { Errno(Int) }` gives `11`, `type Errno { E(Int) }` gives a tagged object. A model cannot see that difference in the output it expects. A hidden rule like this is the worst kind for AI accuracy, and it needs a lint (V4) to patch it.

#### Phase C — Silent vote

Q1 asked for the form: **S** (the one-field struct), **E** (the self-named single-payload enum) or **N** (the spec names neither). Q2 asked whether the newtype text gives field-name advice: **G** (yes) or **G0** (no). Q3 asked whether to file the opt-in `@json(transparent)` as a separate ticket: **T** (file it) or **T0** (do not file; wait for a real wire format).

##### Q1: The form

- **Systems:**

> **Vote:** S
>
> **Reasoning:** A field read is a load and needs no case analysis. The struct has no tag, so the compiler needs no "one variant" proof to remove one; the open codegen bugs on the enum shape (name-keyed shape check, non-Int payload Eq/Hash, as-pattern binder) do not apply to it. One named form gives one shape to lower and test, and lib/std already uses it in all but one place.
>
> **Concern:** If the codegen does not treat every one-field struct as its field (shape-based, not name-based), the Errno migration can regress the FFI paths in libc.bl and fs_ops.bl, which a self-host regen will not catch.

- **Web/Scripting:**

> **Vote:** S
>
> **Reasoning:** A JS/Python/Kotlin dev already knows "a struct with one field" and reads the inner value as `e.code` with no new lesson. One named form gives one answer to the "how do I make a UserId" question, where today the spec gives two. The enum form makes each read a `match` or a `let` pattern, and that read path is a parse error today.
>
> **Concern:** People may still copy the self-named enum form from old tests, blog posts or LLM output, and it compiles. So the docs and llms text must show only the struct form.

- **PLT:**

> **Vote:** S
>
> **Reasoning:** A newtype is a nominal type with one intro and one elim. The one-field struct gives both from rules that already exist: a literal to build and a total projection to read. The enum form eliminates only by case analysis and would need special rules (JSON, lowering, exhaustiveness) keyed on a one-variant self-named shape. S adds no typing rule and removes one of two names for one concept.
>
> **Concern:** Users from Rust/Haskell will keep writing `Errno(rc)`; if the UndefinedFunction help does not fill in the field name, the cost falls on every first-time user.

- **DevOps/Tooling:**

> **Vote:** S
>
> **Reasoning:** With one named form there is one hover text, one help line and one quick-fix (`Errno(5)` to `Errno { code: 5 }`). `e.` completes the field in the LSP; the enum form gives completion nothing and needs a `match` snippet to read the value. E needed a JSON special case and a lint to make that case visible. That is the wrong trade.
>
> **Concern:** Rust and Haskell habits make `Errno(5)` the first thing users and models type, so the UndefinedFunction help must name the field from the start or the struct form will feel hostile.

- **AI/ML:**

> 1. **Vote:** S
> 2. **Reasoning:** One form for one job removes a decision point at each wrapper, and the spec already uses the struct form most (lib/std, 4871, 6471). A field read (`e.code`) is shorter and easier to guess than a match, and `{"code":2}` is JSON a model can predict. The Rust/Haskell habit of writing `Errno(rc)` and `e.0` gets caught by the filled-in help lines on the first retry.
> 3. **Concern:** Training data will keep producing `Errno(rc)`, and since the self-named enum is still legal, a model that declares the enum form gets no error, so the two idioms may spread again in user code.

- **Minimalism:**

> **Vote:** S
>
> **Reasoning:** S adds no new grammar or typing rule. It names a pattern the language already has and that lib/std already uses about 11 times, so only one type moves. It removes one of the two idioms and keeps nothing that needs a shape rule, a naming rule or a lint. E would keep both forms, and N would keep the contradiction.
>
> **Concern:** People who liked the short `Errno(rc)` build may start declaring one-variant enums again by habit. With no lint, the two-idiom drift can slowly come back.

##### Q2: Field-name guidance

- **Systems:**

> **Vote:** G
>
> **Reasoning:** One default removes a decision at each wrapper and gives consistent code across authors and models. The guidance costs one sentence and has no runtime or codegen effect. "Name it for what it holds" comes first, so domain names (`code`, `nanos`) stay the norm.
>
> **Concern:** Writers can read `value` as the rule instead of the fallback, and stdlib types lose names that tell the reader what the field holds.

- **Web/Scripting:**

> **Vote:** G
>
> **Reasoning:** "What do I call the field?" is a decision with no right answer that slows a newcomer down. A default (`value`, same as Kotlin's `value class`) ends that question, and "name it for what it holds" keeps domain words like `code` and `nanos`. It costs one sentence.
>
> **Concern:** People may use `value` everywhere, even when a domain name reads better. Then the field name tells the reader nothing.

- **PLT:**

> **Vote:** G
>
> **Reasoning:** The guidance is a convention, not a typing rule, so it costs soundness nothing. One stated default removes a free choice that otherwise splits code into `value`/`inner`/`v`/`0`-style names. It also gives the diagnostics and docs one name to use in examples.
>
> **Concern:** Readers may take "use `value`" as a rule and pick it where a domain name (`nanos`, `code`) carries meaning.

- **DevOps/Tooling:**

> **Vote:** G
>
> **Reasoning:** A default gives authors one less choice, and scaffolds, snippets and code actions have one name to put in when they create a newtype. "Name it for what it holds" stays the main rule, so domain names (`nanos`, `code`) win where they read better.
>
> **Concern:** People may use `value` everywhere and lose the field name as documentation, so they get `x.value.value` chains in hover and completion.

- **AI/ML:**

> 1. **Vote:** G
> 2. **Reasoning:** A stated default removes one more open choice. With no default, models pick `inner`, `val`, `value`, `v` or `_0` at random, and code from different runs disagrees. "Name it for what it holds" keeps good names like `code` and `nanos`.
> 3. **Concern:** Models may apply `value` everywhere and skip the domain name, which makes nested reads like `x.value.value` that tell the reader nothing.

- **Minimalism:**

> **Vote:** G0
>
> **Reasoning:** A default field name is style advice, not a language rule, and the spec should state only what the compiler enforces or what a user can rely on. A worked example with a domain name (`code`, `nanos`) teaches the habit without making a rule. If the advice belongs anywhere, it belongs in the `blink llms` guide.
>
> **Concern:** If G wins, `value` turns into the field name everyone reaches for, LLMs most of all. We get `x.value.value` chains instead of names that say what the value is.

##### Q3: The opt-in `@json(transparent)`

- **Systems:**

> **Vote:** T
>
> **Reasoning:** The opt-in is explicit, per type, and costs nothing for code that does not use it, so the wire form never changes silently. Filing it now keeps a known gap visible rather than lost; the later panel can still close it as YAGNI. Filing is not building.
>
> **Concern:** The ticket can pull in scope (rename, skip, flatten attributes) and turn a one-rule opt-in into a general serde-style attribute system.

- **Web/Scripting:**

> **Vote:** T
>
> **Reasoning:** Web devs will put a newtype ID in an API struct on day one and get `{"user": {"value": 42}}` where the wire format wants `{"user": 42}`. That is a known papercut, and serde users know the fix. A filed ticket keeps it visible without adding it to this decision. Filing it adds nothing to the language until a later panel votes on it.
>
> **Concern:** The ticket may sit unread while users write `Serialize` impls by hand for each ID type. Those impls drift apart and become the de facto idiom.

- **PLT:**

> **Vote:** T
>
> **Reasoning:** The opt-in is sound: it is explicit, per type, and checked (error on more than one field), unlike a wire form that turns on variant count. Filing it now records the known gap between S and common wire formats, so the panel decides it on purpose and not under pressure later. Filing is not adopting; the later panel can still reject it.
>
> **Concern:** The ticket could pull in scope creep (transparent for enums, renames, flatten) and become a general serde-attribute design instead of one checked rule.

- **DevOps/Tooling:**

> **Vote:** T
>
> **Reasoning:** The `{"user": {"value": 42}}` papercut is predictable for anyone who puts a newtype in an API struct, and an open ticket gives the help text and docs a place to point. Filing it does not decide it; a later panel still judges the diagnostic surface (error on more than one field, interaction with Deserialize).
>
> **Concern:** An open ticket can push users to write hand-made `Serialize` impls as a stopgap, and those will be hard to move off once the attribute lands.

- **AI/ML:**

> 1. **Vote:** T0
> 2. **Reasoning:** Each attribute is one more thing a model must learn and one more choice at each wrapper. With no user need on record, a ticket sets the panel to design a feature with no real wire format to check it against. When a user brings one, a ticket with that case in it will make a better spec.
> 3. **Concern:** If the ticket is filed now, it may pass as a feature with no user, and give the JSON of a wrapper two forms that a model must choose between.

- **Minimalism:**

> **Vote:** T0
>
> **Reasoning:** No user and no lib/std type needs a bare-scalar wire form today. A ticket filed now puts the panel's time on an attribute that nobody has asked for. When a real wire format needs it, that case will define the feature better than a guess made today. YAGNI.
>
> **Concern:** If T wins, a filed ticket tends to get built, and the attribute surface grows without a real use case to test the design against.

Tally: Q1 S 6-0. Q2 G 5-1 (Minimalism for G0). Q3 T 4-2 (AI/ML and Minimalism for T0).

#### Phase D — Debate and re-vote (Q3)

Phase D covered Q3 only. Q1 and Q2 were decided. The debate replies:

- **Systems:**

> # Systems seat — Phase D (Q3)
>
> **Strongest point against T: aiml**, "a ticket sets the panel to design a feature with no real wire format to check it against." min makes the same point: "a filed ticket tends to get built."
>
> That is a fair risk, and it is about when the ticket is worked, not whether it exists. A design with no test case is a guess; I agree. But T0 has its own cost, which web and devops name: with no record, users write hand-made `Serialize` impls per ID type, and those become the idiom before any panel looks. A known gap with no record is lost; a record with no rule to wait is a guess. Both fail.
>
> **I keep T, with one condition merged from aiml and min:** the ticket is filed as deferred, and its text says "do not deliberate until a real wire format (a user program or a lib/std type) is attached." The `{"user": {"value": 42}}` shape goes in as the expected case, not as the spec. Then:
> - the gap stays visible, and help text or docs can point to it (devops);
> - no panel time is spent until a real case exists (min);
> - the design gets checked against that case (aiml);
> - scope stays one checked rule, since the ticket names only `@json(transparent)` on a one-field struct (my Phase C concern).
>
> From the systems view the opt-in has zero cost for code that does not use it, so the only real risk is process, and the deferral rule handles it.
>
> No change: T, deferred until a real wire format arrives.

- **Web/Scripting:**

> # Web/Scripting seat — Phase D (Q3)
>
> **Strongest point against T (aiml):** "a ticket sets the panel to design a feature with no real wire format to check it against. When a user brings one, a ticket with that case in it will make a better spec."
>
> **Answer:** The wire format is not a guess. `{"id": 42}` for an ID field is the default shape of nearly every REST and JSON API a web dev talks to: Stripe, GitHub, any ORM-backed service. We know today that S gives `{"id": {"code": 42}}`. What we do not have is a *Blink* user on record, and aiml and min are right that a panel with no real case tends to over-design. sys and plt raise the same risk as scope creep.
>
> **Change (merge):** I keep T, but narrow what the ticket is. File it as a friction/backlog record, not as panel work:
> - Title it as the gap: "newtype in a JSON API struct encodes as an object, not the bare value".
> - Do not put it in the /deliberate queue until it has a real wire format from a user or a lib/std type.
> - Scope it to one rule: an explicit per-type opt-in, an error when the struct has more than one field, and Deserialize symmetric. Rename, skip and flatten stay out.
>
> This answers min's "a filed ticket tends to get built": with a gate, it does not get built until someone brings the real case. The gap stays visible, so the docs and help text can point at it, and a user who hits it adds a note to the record instead of writing a `Serialize` impl by hand.
>
> If the panel reads T0 as "record the gap, take no panel action", my position equals T0 and I will not block either label.

- **PLT:**

> # PLT seat — Phase D (Q3)
>
> **Strongest point against T (aiml):** "a ticket sets the panel to design a feature with no real wire format to check it against." min adds that a filed ticket tends to get built.
>
> **Answer.** I accept the premise: a design with no concrete wire format to test it against is underdetermined, and I would not vote on one. The fault is in *when the panel deliberates*, not in *whether the gap is recorded*. Q1 chose S knowing that it gives `{"user": {"value": 42}}`. That consequence is part of this decision and should be on record where the next user who hits it will find it. Without a ticket, a user's report starts from zero, and in the meantime hand-written `Serialize` impls (devops, web) become the idiom with no pointer to a planned fix.
>
> **Change.** I keep T, with one condition written into the ticket: it states the gap and the sound shape (explicit, per type, error on more than one field), and it is not deliberated until a concrete wire format from a user or a lib/std type is attached. That answers aiml's and min's concern (no design against a guess, no drift into a built feature) and keeps sys/web/devops's point (the gap is visible). If the panel will not attach that condition, I would still vote T; the record matters more than the risk of a ticket that waits.

- **DevOps/Tooling:**

> # DevOps/Tooling seat — Phase D (Q3)
>
> **Strongest point against T (aiml):** "a ticket sets the panel to design a feature with no real wire format to check it against. When a user brings one, a ticket with that case in it will make a better spec." min adds: "a filed ticket tends to get built."
>
> **Answer.** aiml is right that the design needs a real case, and min is right that open tickets drift toward being built. Neither point argues against writing the gap down. It argues against deliberating on it now. Under T0 the gap exists only in this transcript. When a user later hits `{"user": {"value": 42}}`, nobody finds this panel's reasoning, and the user writes a hand-made `Serialize` impl. That impl is the drift web and I flagged, and it gives a model a third JSON form to learn, which is aiml's own concern.
>
> **Change: I keep T, with a gate that meets both T0 points.** File the ticket as blocked, with this text: "Not for deliberation until a concrete wire format (an external API or a lib/std type) is attached." It names the papercut, links this decision, and lists the scope limit sys and plt gave (one rule: transparent on a one-field struct, error otherwise; no rename, skip or flatten). Docs and the struct-JSON help text can point to it. Nothing gets designed or built without a user case, so min's YAGNI holds. If the panel thinks a blocked ticket is the same as T0, I accept that merged reading.

- **AI/ML:**

> # AI/ML seat — Phase D, Q3
>
> **Strongest point against T0: web.** "Web devs will put a newtype ID in an API struct on day one and get `{"user": {"value": 42}}` ... users write `Serialize` impls by hand for each ID type. Those impls drift apart and become the de facto idiom." (devops makes the same point.)
>
> This hits my own domain. My T0 case was "no user need on record, so do not add a choice a model must learn." But web names a need that S itself creates: Q1 makes a struct the one newtype form, so every wrapped ID in an API struct now serializes as an object. That is a known, near-certain case, not a guess. And the stopgap is worse for AI accuracy than the attribute: hand-written `impl Serialize for UserId` blocks, each slightly different, end up in public code and in training data. Models then copy ten shapes of boilerplate instead of learning one checked rule.
>
> sys and plt are also right that filing is not building. A ticket costs a model nothing; only a vote to adopt adds surface.
>
> **I change to T**, with two asks for the ticket text:
> - scope it to the one checked rule (explicit per type, error on more than one field); no rename/skip/flatten, so it cannot grow into a serde-style attribute set (the scope concern sys and plt raise);
> - name the `{"user": {"value": 42}}` case as its motive, so the later panel checks the design against a real wire shape.

- **Minimalism:**

> # Minimalism seat — Phase D (Q3)
>
> **The strongest point against T0 comes from web, backed by devops.** The papercut is foreseeable, not imagined. Under the Q1 result, every ID wrapper in an API struct serializes as `{"user": {"value": 42}}`, while almost every wire format wants `{"user": 42}`. Without a planned fix, users write `Serialize` and `Deserialize` impls by hand for each ID type, and those impls become the idiom.
>
> That argument wins, and it beats my YAGNI case. The hand-written impls are not zero surface: each one is a copy of the same rule, written in user code and in training data, and each copy can drift from the others. One checked attribute is less total surface than many hand-written impls. I also mixed up "file a ticket" with "build it". A ticket adds nothing to the language. A later panel can still close it as YAGNI.
>
> **I change to T, with one condition on how the ticket is written.** It covers exactly one rule: `@json(transparent)` on a struct with exactly one field, and an error on any other shape. It does not cover enums, renames, flatten, skip or any other serde-style attribute. The ticket text must say that a wider attribute system needs its own ticket. That condition answers the concern sys and plt raised about the scope growing, and it also answers my own Phase C concern.
>
> AI/ML's point still holds: a filed ticket can pass as a feature that no user asked for. The condition limits that risk, and the later panel can still reject the feature.
>
> Changed: T0 to T (with the scope condition above).

AI/ML and Minimalism moved to T on the point that Q1 itself makes `{"user": {"value": 42}}` a certain result, so users would otherwise write their own `Serialize` impls and those would become the idiom. The votes:

##### Q3: The opt-in `@json(transparent)`

- **Systems:**

> # Systems seat — Phase D vote (Q3)
>
> **Vote:** T
>
> **Reasoning:** Q1 makes every wrapped ID in an API struct encode as an object, so the gap is certain, and a record keeps users from writing their own `Serialize` impls before a panel looks. The opt-in has zero cost for code that does not use it. The ticket should carry the conditions the panel converged on: scope is one checked rule (`@json(transparent)` on a one-field struct, error on any other shape, Deserialize symmetric; no rename, skip, flatten or enums), and it is not deliberated until a real wire format is attached.
>
> **Concern:** If the ticket text drops the scope limit or the deferral gate when it is filed, the later panel can treat it as a mandate for a general serde-style attribute system.

- **Web/Scripting:**

> # Web/Scripting seat — Phase D vote (Q3)
>
> **Vote:** T
>
> **Reasoning:** Q1 itself creates the `{"user": {"value": 42}}` papercut, so the gap is real for any web dev who puts an ID in an API struct. A ticket keeps it visible, so docs and help text can point to it and users do not hand-write `Serialize` impls as the idiom. File it with the conditions the debate converged on: one checked rule (explicit per type, error on any struct that does not have exactly one field, symmetric Deserialize; no rename, skip, flatten or enums), the papercut named as its motive, and no deliberation until a real wire format from a user or a lib/std type is attached.
>
> **Concern:** The deferral gate may also keep the ticket out of sight of the users it is for, so the hand-written impls spread anyway.

- **PLT:**

> # PLT seat — Phase D vote (Q3)
>
> **Vote:** T
>
> **Reasoning:** The `{"user": {"value": 42}}` shape follows from Q1, so the gap is a known consequence of this decision and belongs on record. The opt-in is sound only in its narrow form: explicit per type, one-field struct, error on any other shape, Deserialize symmetric. The ticket must carry that scope and the gate "not deliberated until a concrete wire format is attached" (sys, devops, web, min), so the later panel checks a design against a real case.
>
> **Concern:** If the ticket loses its scope limit or its gate in the filing, it can grow into a general serde-attribute design that no concrete case has tested.

- **DevOps/Tooling:**

> # DevOps/Tooling seat — Phase D vote (Q3)
>
> **Vote:** T
>
> **Reasoning:** Q1 makes the struct the only newtype form, so `{"user": {"value": 42}}` is a known result of this decision. It needs a record that docs and help text can point to. File the ticket with three limits all seats now accept: one rule (`@json(transparent)` on a struct with exactly one field, an error on any other shape, Deserialize the same); no rename, skip, flatten or enum scope; and no deliberation until a concrete wire format from a user or a lib/std type is attached. That keeps the gap visible and meets min's YAGNI point and aiml's "design against a real case" point.
>
> **Concern:** The ticket text can drop the gate or the scope limit, and then the ticket reaches /deliberate early as a general serde-style attribute design.

- **AI/ML:**

> # AI/ML seat — Phase D vote, Q3
>
> **Vote:** T
>
> **Reasoning:** Q1 (S) makes `{"user": {"value": 42}}` a near-certain case for any wrapped ID in an API struct. If the gap has no record, users write their own `Serialize` impls, each a bit different, and models learn many shapes of boilerplate in place of one checked rule. A ticket adds nothing a model must learn; only a later vote to adopt would. I back the gate sys, plt and devops give (no deliberation until a real wire format is attached) and min's scope limit (one rule, one-field struct only, error otherwise).
>
> **Concern:** If the gate and scope limit are not written into the ticket text, a later panel may design a wider serde-style attribute set with no real case to check it against.

- **Minimalism:**

> # Minimalism seat — Phase D vote (Q3)
>
> **Vote:** T
>
> **Reasoning:** The Q1 result causes the `{"user": {"value": 42}}` case, so we know about it today and do not have to guess. If the panel does nothing, users write `Serialize` impls by hand for each ID type, and that is more total surface than one checked rule. Filing a ticket adds nothing to the language. I support the gate that sys, plt and devops proposed: the ticket is not deliberated until a real wire format is attached, and it covers only one rule, an opt-in on a struct with exactly one field that is an error on any other shape.
>
> **Concern:** If the ticket text leaves out the deliberation gate and the one-rule scope, a later panel could treat it as a request for a general serde-style attribute set.

Tally: Q3 T 6-0. The ticket carries these conditions: one checked rule, `@json(transparent)` on a struct with exactly one field; an error on any other shape; `Deserialize` mirrors `Serialize`; no rename, skip, flatten or enum scope; and no deliberation until a concrete wire format from a user or a lib/std type is attached.

#### Follow-up: a variant named like its own enum

The Phase C ballot listed, as agreed by all six without a vote: "A variant named like its own enum (`type Token { Token(Str), End }`) is legal, with no warning." The owner asked (verbatim):

> "how does that make sense in the new paradigm?"
>
> "What does it MEAN if 'legal', and whats the purpose?"

Each seat answered four points: what the form means under the owner ruling that a bare variant is an error when a type of that name is in scope; its purpose after Q1; a rule; and what happens to the existing uses. Every seat withdrew its earlier "legal" vote.

##### Phase A

- **Systems:**

> # Systems seat — a variant named like its own enum
>
> I withdraw my "legal, no warning" vote. It fit the old model, where `Errno(rc)` was the newtype. Q1 and the owner ruling remove that reason.
>
> ## 1. What "legal" means now
>
> For `type Token { Token(Str), End }`, the type `Token` is in scope at every site where the variant `Token` is. So under "every bare is illegal":
>
> | Site | Meaning |
> |---|---|
> | bare `Token` | error: type in scope |
> | `Token(s)` (expr) | error: type in scope |
> | pattern `Token(s)` | error: type in scope |
> | `Token.x` | type path: member `x` of the type |
> | `Token.Token(s)` | the only way to reach the variant |
> | annotation `Token` | the type |
>
> So "legal" means: you may declare a name you can use only as `Token.Token`. That is a trap.
>
> ## 2. Purpose
>
> None. The hardware sees no difference. `type Token { Token(Str), End }` and `type Token { Text(Str), End }` give the same tagged union, the same tag values, the same code. A one-variant `type C { C(Int) }` is worse than the Q1 newtype: as an enum, the reader must ask if it carries a tag. The one-field struct's layout is the field. The self-named form gives no cost, layout or API that another form lacks.
>
> ## 3. Rule
>
> A variant must not have the name of its own enum. Error at the variant declaration, so the user sees it once, not at each use.
>
> ```blink
> type Token { Token(Str), End }
> // error[<new code>]: variant `Token` has the name of its enum `Token`
> //   help: rename the variant, for example `Text(Str)`
> //   help: for a one-value wrapper, write a struct: `type Token { text: Str }`
>
> type Token { Text(Str), End }       // ok
>
> fn show(t: Token) -> Str {
>     match t {
>         Text(s) => s
>         End => "end"
>     }
> }
> ```
>
> One name compare per variant at declaration. No resolver rule, no W1011 exemption; worktree 03_types.md:2284 text and the `type Unit { Unit }` example at :2299 go away.
>
> ## 4. Existing uses
>
> - lib/std `Errno` and the ~36 `type Errno { Errno(Int) }` test copies: migrate to `type Errno { code: Int }` under Q1, in the same change.
> - 03:2366, :2382, 07:1568 (`Code { Code(Int) }`): Q1 already rewrites them as structs.
> - tests/test_nested_variant_payload_patterns_run.bl:72-74: rename the variants (`C { CI(Int) }`, `B { BC(C) }`, `A { AB(B) }`).; the test proves nested patterns, not self-naming.
> - `Code`/`Name` test shapes: struct form.
> - Add one rejection test for the new error.

- **Web/Scripting:**

> # Web seat — a variant named like its own enum
>
> ## 1. What "legal" means under the owner's ruling
>
> The owner ruled: when a type `X` is in scope, a bare `X` / `X(...)` is an error. In `type Token { Token(Str), End }` the type `Token` is always in scope where its variant is. So:
>
> - bare `Token`: error (type in scope, a type is never a value).
> - `Token(s)` call: error, by the same rule. Write `Token.Token(s)`.
> - `Token.x`: type path. `Token.Token` is the variant; `Token.len()` is not the variant's method.
> - pattern `Token(s)`: error by the same rule ("every bare is illegal"). Write `Token.Token(s)`.
> - annotation `: Token`: the type.
>
> So "legal" means: you can declare the variant, but you can never write its short name anywhere. Each use is `Token.Token`. That is legal only on paper. The 6-0 point was correct when the self-named form was the newtype. Q1 removed that job, and the ruling removed the short use.
>
> ## 2. Purpose now
>
> None. A JS/TS/Python dev who reads `Token.Token("a")` asks why the word is there two times. The one-field struct `type Token { text: Str }` gives the wrapper. A differently named variant (`Word(Str)`) gives the enum case. The self-named form gives nothing that these do not, and it adds a trap: the user writes `Token("a")`, which is the natural form, and gets an error at each site instead of one error at the cause.
>
> ## 3. Proposal: reject it at the declaration
>
> Make it an error, not a warning. Report it once, at the cause, with the fix.
>
> ```blink
> type Token { Token(Str), End }
> ```
>
> ```
> error[E1012]: variant `Token` has the same name as its enum
>   --> lex.bl:1:14
>    |
>  1 | type Token { Token(Str), End }
>    |              ^^^^^ every use would need `Token.Token`
>    = help: to wrap one value, use a struct: `type Token { text: Str }`
>    = help: for an enum case, give the variant its own name: `Word(Str)`
> ```
>
> This also covers `type Unit { Unit }`. The worktree text at 03:2284 and the "no W1011" line at :2299 go; W1011 keeps "a different enum" with no exemption to explain.
>
> ## 4. Existing uses
>
> - lib/std `Errno` and the ~36 `type Errno { Errno(Int) }` copies: migrate to `type Errno { code: Int }` under Q1.
> - `Code { Code(Int) }`, `Name { Name(Str) }`: one-field structs.
> - tests/test_nested_variant_payload_patterns_run.bl:72-74: rename the variants (`CVal(Int)`, `BVal(C)`, `AVal(B)`). The test proves nested payload patterns, not the self-name.
> - Spec 03:2366, :2382, 07:1568: Q1 rewrites them.
> - Add a typecheck test that the declaration gives E1012 (use a free code).

- **PLT:**

> # PLT seat — a variant named like its own enum
>
> I withdraw my earlier "legal, no warning" vote. It predates the owner's ruling and Q1; after both, the form means only stutter.
>
> ## 1. What "legal" means now
>
> For `type Token { Token(Str), End }` with the owner ruling on a type named like a variant:
>
> | Site | Refers to |
> |---|---|
> | bare `Token` | error: a type `Token` is in scope |
> | `Token(s)` (expr) | error, same reason |
> | `Token.x` | type path: member `x` of the type |
> | `Token.Token(s)` | the only way to build the variant |
> | pattern `Token(s)` | the variant, by the type-directed pattern rule (§3.5) |
> | annotation `: Token` | the type |
>
> So the variant is bare in a pattern but must be qualified in an expression. Construction and destruction of one injection use two spellings. No other variant has this asymmetry. The W1011 own-enum exemption exists only for this form.
>
> ## 2. Purpose
>
> None that remains. It came from Haskell `newtype T = T a`, where types and constructors live in separate namespaces. In Blink a type name now blocks a bare variant. Q1 gives the newtype its own form (`type Errno { code: Int }`). For a multi-variant enum, a variant called `Token` gives nothing that `Text` or `Word` does not, and it costs `Token.Token`.
>
> ## 3. Rule
>
> Extend E0518 (NameCollision). Its own principle already says: "a name is either a product type or a sum injection — never both." An enum named like one of its own variants is that same overlap, inside one declaration.
>
> ```blink
> type Token { Token(Str), End }
> // error[NameCollision]: variant `Token` has the name of its enum `Token`
> //   help: rename the variant, e.g. `type Token { Word(Str), End }`
> //   help: for a one-field wrapper, use a struct: `type Token { text: Str }`
> ```
>
> One error, at the variant in the declaration; no cascade at use sites. The check reads one declaration only, so scope and imports cannot change it. Drop the W1011 own-enum exemption; it has nothing to exempt.
>
> ## 4. Existing uses
>
> - lib/std `Errno` and the ~36 `type Errno { Errno(Int) }` copies: migrate to `type Errno { code: Int }` with Q1.
> - `Code { Code(Int) }`, `Name { Name(Str) }`, 03:2366/2382, 07:1568: same, struct form (Q1 already rewrites them).
> - tests/test_nested_variant_payload_patterns_run.bl:72-74: rename variants (`C { Cv(Int) }` etc.).
> - Worktree 03:2284 and the `type Unit { Unit }` example at :2299: delete; add one negative test for the new E0518 case.

- **DevOps/Tooling:**

> # DevOps/Tooling — a variant named like its own enum
>
> **Change of vote: I now say the form is illegal.** My earlier vote came before the owner ruling on a type named like a variant, which breaks it.
>
> ## 1. What "legal" means under the owner's ruling
>
> `type Token { Token(Str), End }` puts type `Token` in scope wherever variant `Token` is. So:
>
> - bare `Token`, `Token("x")`: error. The type is in scope; write `Token.Token("x")`.
> - pattern `Token(s)`: the same error; write `Token.Token(s)`.
> - `Token.x`: type path. `Token.Token` is the variant; `Token.Token.len()` reaches a member of the value.
> - annotation `Token`: the enum.
>
> "Legal" means the declaration compiles, and then each bare use of the variant fails. The user gets one error per use site, at a place far from the cause. The only spelling left is `Token.Token`, the stutter Go's `golint` flags.
>
> ## 2. Purpose
>
> None is left. Before Q1 it was the newtype shape. Q1 (6-0) moved the newtype to `type Errno { code: Int }`. A single-variant enum `X { X(T) }` adds nothing over the one-field struct.
>
> ## 3. Rule
>
> A variant with the name of its own enum is a declaration error. Report it once, at the variant, not at each use.
>
> ```blink
> type Token { Token(Str), End }
> // error[NameCollision]: variant `Token` has the name of its enum `Token`
> //   --> lex.bl:1:14
> //   help: rename the variant, as in `type Token { Word(Str), End }`
> //   help: for a wrapper type, use a one-field struct: `type Token { text: Str }`
>
> type Errno { code: Int }      // the newtype (Q1)
> type Token { Word(Str), End } // ok
> ```
>
> Use the same code as E0518. It enforces the same rule: one name in a package is a product name or a sum injection, never both. The second `help:` shows only for a one-variant enum with one payload. Neither help is machine-applicable, because the compiler cannot choose the new name. The LSP shows them as text, with no auto-edit.
>
> ## 4. Existing uses
>
> - lib/std `Errno`: Q1 migrates it to a one-field struct. Land that before the error.
> - The ~36 `type Errno { Errno(Int) }` test copies: rewrite them to the Q1 struct in the same slice.
> - `test_nested_variant_payload_patterns_run.bl` `C/B/A`: rename the variants (`CVal`, `BVal`, `AVal`).
> - `Code`/`Name` test shapes: one-field structs.
> - Spec: delete the "may have a variant with its own name" sentence and the `type Unit { Unit }` example at 03:2284/2299. Add one negative example to the E0518 text, and add the case to `blink explain E0518`.
> - Order: migration commit first, then the error.

- **AI/ML:**

> # AI/ML seat — a variant named like its own enum
>
> ## 1. What "legal" means under the owner's ruling
>
> Take `type Token { Token(Str), End }`. The type `Token` is always in scope where its variant is, so the ruling ("every bare is illegal") applies at every site:
>
> - bare `Token` / `Token("a")` in an expression: error; write `Token.Token("a")`.
> - pattern `Token(s)`: error; write `Token.Token(s)`.
> - `Token.x`: type path (member `x` of the type), never the variant value.
> - annotation `: Token`: the enum.
>
> So "legal" means only that the declaration compiles. Every use is `Token.Token(...)`: a stutter, nothing more.
>
> ## 2. Purpose now
>
> None. Before Q1 it was the newtype idiom. Q1 (6-0) made the one-field struct the newtype. The form has no use that a one-field struct or a renamed variant does not give, and both of those read better.
>
> From my domain: models trained on Rust, Haskell and Swift write `type Token { Token(Str) }` by habit (`struct Token(String)`, `data Token = Token String`). If the declaration compiles, the model then gets an error at each use site, far from the cause, and must work out the stutter itself. One error at the declaration, with a fix, is the cheapest path to correct code.
>
> ## 3. Proposal: make it an error at the declaration
>
> A variant must not have the name of its own enum.
>
> ```blink
> type Token { Token(Str), End }
> ```
>
> ```
> error[E10xx]: variant `Token` has the name of its enum `Token`
>   --> lex.bl:1:14
> help: for a newtype, write a one-field struct: `type Token { text: Str }`
> help: or rename the variant: `type Token { Word(Str), End }`
> ```
>
> Correct forms:
>
> ```blink
> type Token { text: Str }              // newtype
> type Tok { Word(Str), End }           // enum
> fn main() ! IO {
>     let t = Token { text: "a" }
>     let w = Tok.Word("b")
> }
> ```
>
> Remove the worktree sentence "An enum may have a variant with its own name" and the `type Unit { Unit }` example (:2284, :2299); the W1011 "own enum" exemption then has nothing to exempt and goes too.
>
> ## 4. Existing uses
>
> - lib/std `Errno` and the ~36 `type Errno { Errno(Int) }` copies: migrate to the one-field struct under Q1.
> - `Code { Code(Int) }`, `Name { Name(Str) }`: one-field structs.
> - test_nested_variant_payload_patterns_run.bl:72-74: keep the test and its purpose (nested payload patterns); rename the variants (`type C { CVal(Int) }` and so on). Do not convert to structs, or it stops testing variant payloads.
> - sections/03 :2366, :2382 and 07:1568: rewritten by Q1.

- **Minimalism:**

> # Minimalism — a variant named like its own enum
>
> ## 1. What "legal" means under the owner's ruling
>
> Take `type Token { Token(Str), End }`. The type `Token` is always in scope where its variant is, so the owner's ruling ("every bare is illegal") applies at every site:
>
> | Site | Meaning |
> |---|---|
> | `let t: Token` | the enum |
> | `Token.x` | type path: member `x` of the enum |
> | bare `Token` / `Token("a")` | error: write `Token.Token` |
> | pattern `Token(s)` | error: write `Token.Token(s)` |
> | `Token.Token.len()` | a method on the variant value |
>
> So "legal" means: you may declare it, but you can never write the variant by its short name. Every use is `Token.Token`. The only thing the form gives is a stutter, plus spec text to explain it (the W1011 exemption, the `Unit.Unit.x()` paragraph).
>
> ## 2. Purpose now
>
> None. The old purpose was the newtype; Q1 (6-0) moved that to `type Errno { code: Int }`. A multi-variant enum like `Token { Token(Str), End }` loses nothing if the variant gets a real name: `Word(Str)`. No user writes this form to get something they cannot get another way. The owner already asked "why would you?" — I find no answer.
>
> ## 3. Proposal: make it an error at the declaration
>
> One rule, at one place. It removes the W1011 exemption, the `Unit.Unit` example and the type-path-vs-variant edge case. Less spec, not more.
>
> ```blink
> type Token { Word(Str), End }
>
> fn show(t: Token) -> Str {
>     match t {
>         Word(s) -> s
>         End -> "<end>"
>     }
> }
> ```
>
> The wrong form:
>
> ```blink
> type Token { Token(Str), End }
> ```
>
> ```
> error[E____]: variant `Token` has the same name as its enum
>   --> lex.bl:1:14
>    |
>  1 | type Token { Token(Str), End }
>    |              ^^^^^ rename this variant
>    = help: for a one-value wrapper, use a one-field struct: `type Token { text: Str }`
> ```
>
> The help line points at the Q1 newtype, which is the most common reason a user writes this.
>
> ## 4. Existing uses
>
> - lib/std `Errno` and the ~36 `type Errno { Errno(Int) }` test copies: migrate to `type Errno { code: Int }` under Q1. No extra work from this rule.
> - `Code { Code(Int) }`, `Name { Name(Str) }`: same — one-field structs.
> - tests/test_nested_variant_payload_patterns_run.bl:72-74: rename the variants (`CInt(Int)`, `BC(C)`, `AB(B)`); the test is about nested payloads, not names.
> - Spec 03:2366, :2382, 07:1568: Q1 rewrites them; the worktree text at 03:2284 and :2299 drops the self-named sentences and the "own enum is exempt" clause.
>
> Order: migrate lib/std and tests first, then add the error. src has no uses, so no bootstrap dance.
>
> Vote: illegal, error at declaration.

##### Silent vote

Q1 asked: **X** (a variant with the name of its own enum is an error at the declaration) or **L** (keep it legal). Q2 asked: **R** (reuse E0518 `NameCollision`, widened) or **N** (a new code).

###### Q1: Error or legal

- **Systems:**

> Vote: X
> Reasoning: Under "every bare is illegal", the variant is reachable only as `Token.Token`, so the form gives the user nothing and costs a resolver exemption. The renamed variant compiles to the same tagged union, and the one-field struct is the zero-cost newtype. One name compare at the declaration is the cheapest, most predictable check.
> Concern: The migration of the ~36 `Errno` test copies must land before the error, or the gate breaks.

- **Web/Scripting:**

> Reasoning: Under the owner's "every bare is illegal" ruling, the self-named variant can never be written short, so each use is `Token.Token`. That gives no gain to the user, and it is a trap: `Token("a")` fails at every use. One error at the declaration, with the struct and rename help, tells the user the fix at the cause.
>
> Concern: The migration of the ~36 `Errno` copies must land before the error, or the gate breaks.

- **PLT:**

> **Vote:** X
> **Reasoning:** Under the owner's ruling, the variant can only be built as `Token.Token(...)`, but a type-directed pattern still matches it bare. So one injection gets two spellings. The form has no purpose that Q1's one-field struct does not serve better. An error at the declaration is local and does not depend on scope.
> **Concern:** The migration must land before the error, or the ~36 `Errno` test copies break the gate.

- **DevOps/Tooling:**

> **Reasoning:** Under the owner's ruling, each bare use of the variant is an error, so a legal declaration gives one error per use site, far from the cause. A single error at the variant names the cause and shows the fix. No user gains anything from the legal form after Q1.
> **Concern:** The migration commit must land first, or the gate goes red on ~36 test files and lib/std.

- **AI/ML:**

> Reasoning: Under the owner's "every bare is illegal" ruling, the form only compiles; each use must be `Token.Token(...)`, which gives no gain. Models from Rust/Haskell write this form by habit, and one error at the declaration with a fix is the shortest path to correct code. It also removes a spec sentence and a W1011 exemption, so there is less for a model to learn.
> Concern: The migration (lib/std `Errno` and ~36 test copies) must land before the error does, or the gate breaks.

- **Minimalism:**

> **Vote:** X
> **Reasoning:** Under the owner's ruling, the form can never be used by its short name, and Q1 gave the newtype to the one-field struct, so it has no purpose. An error at the declaration is one rule in one place. It also lets us delete the W1011 exemption and the `Unit.Unit` text, so the spec gets smaller.
> **Concern:** The migration of the ~36 `Errno` test copies must land before the error, or the corpus goes red.

###### Q2: Diagnostic code

- **Systems:**

> Vote: R
> Reasoning: E0518 already states the rule: a name is a product type or a sum injection, never both. A self-named variant breaks that same rule, so one code with one explanation is clearer for users and tools than two codes for one idea. Widen the E0518 catalog row and its explain text to name this case.
> Concern: The E0518 message text must change per case, so the user sees "variant `Token` has the name of its own enum", not the struct-vs-variant wording.

- **Web/Scripting:**

> Reasoning: It is the same rule: one name cannot be both a type and a variant. A user who searches the code finds one page with one rule, not two codes to learn. Fewer codes for one idea is easier for a JS/Python dev.
>
> Concern: Widen the E0518 catalog row and message text so they do not say only "a struct"; the self-named enum case must read as a normal part of the rule.

- **PLT:**

> **Vote:** R
> **Reasoning:** E0518 states the principle "a name is either a product type or a sum injection — never both". An enum named like its own variant breaks that same principle inside one declaration. One rule should have one code. The catalog row and the message must be widened, not forked.
> **Concern:** The ERROR_CATALOG.md:125 text names only struct-vs-variant, so the amendment must rewrite it, or E0518 will read as two unrelated checks.

- **DevOps/Tooling:**

> **Reasoning:** The user sees one rule, "a name in a package is a product name or a sum injection, never both". One code means one `blink explain` page, one ERROR_CATALOG row and one search term. A new code for each shape of the same collision splits the docs and gives no new fix.
> **Concern:** The E0518 explain text and catalog row must list both cases (struct vs variant, and enum vs its own variant) with their different fixes. If they do not, the explain page for the new case is wrong.

- **AI/ML:**

> Reasoning: E0518 already states the principle "a name is either a product type or a sum injection — never both", and this case breaks that same principle. One code for one rule means a model or user who has learned E0518 knows this case too, and `blink explain E0518` covers both. The message text can still name this case on its own ("variant `Token` has the name of its enum").
> Concern: The E0518 catalog row and explain text must be widened in the same change, or the code points to a description that does not match.

- **Minimalism:**

> **Vote:** R
> **Reasoning:** E0518 already states the principle: a name is a product type or a sum injection, never both. A self-named variant breaks the same principle, so a new code adds catalog surface for no new idea. Widen E0518's catalog row and keep one code that users and tools learn once.
> **Concern:** The widened E0518 message must name the case at hand ("variant has the name of its own enum") and not fall back on a vague general text.

Tally: Q1 X 6-0. Q2 R 6-0.

### Final Spec

A newtype is a struct with exactly one field.

```blink
type Errno { code: Int }

fn open_failed(rc: Int) -> Result[Int, Errno] {
    Err(Errno { code: rc })
}

fn main() {
    let e = Errno { code: 5 }
    let n: Int = e.code           // read the field
    let bad: Int = e              // error[TypeError]: declared type Int but got Errno
}
```

Locked points:

- A newtype is a one-field struct. It is a new type, distinct from the type of its field. Build it with a struct literal, read it with `e.code`, destructure it with a struct pattern. `@derive`, JSON and generics follow the struct rules. The JSON form of `Errno { code: 2 }` is `{"code":2}`.
- There is no implicit conversion between a newtype and its field type, in either direction. A newtype has no operators of its field type.
- `type X = Y` is an alias: the same type, not a newtype.
- There are no tuple structs and no `newtype` keyword. A single-variant enum is an ordinary enum, not a newtype, and gets no lint.
- The newtype text says: name the field for what it holds; use `value` when nothing better fits.
- Diagnostics: `Errno(5)` is `UndefinedFunction`, and the help fills in the field (`Errno { code: 5 }`; all fields with placeholders when there are several). `e == 2`, or an `Int` where an `Errno` is expected, is `TypeError`, and the help is `e.code`. `e.0` is `NoSuchField` and names the field. `type Errno(Int)` is `ParseError` ("Blink has no tuple structs"), and the help is `type Errno { code: Int }`. No help line offers an enum form.
- A variant with the name of its own enum is E0518 `NameCollision`, at the variant, once. The message is "variant `Token` has the name of its enum `Token`". The help is to rename the variant (`type Token { Word(Str), End }`); for an enum with one variant and one payload, a second help is to use a one-field struct (`type Token { text: Str }`). Neither help is machine-applicable. The principle of E0518 stays: a name is either a product type or a sum injection, never both.
- `lib/std` `Errno` is `pub type Errno { code: Int }`. `FsError.code` becomes `FsError.errno`; the number reads as `err.errno.code`. The migration of lib/std and of the test copies that model std `Errno` lands before the new error.
- An opt-in `@json(transparent)` is filed as a separate ticket with the conditions in Phase D. The spec does not describe it.
- Out of scope: positional (tuple-struct) construction, `GeneralizedNewtypeDeriving`, a rename, skip or flatten attribute set for JSON, and the layout of a one-field struct (an implementation matter).

### Concerns

- Moderator correction to the ticket text: the sha256 decision landed `pub opaque type Sha256`, not `Sha256Digest`. `Sha256Digest` appears only inside a quoted Phase A proposal in `decisions/sha256-std.md`. That decision gave no newtype form, so nothing in it needs amending.
- Minimalism dissents on Q2: field-name advice is style, not a language rule. The risk the other seats name for G is the same one: authors use `value` everywhere and get `x.value.value` chains.
- Rust and Haskell habits make `Errno(5)` and `e.0` the first thing users and models write. The `UndefinedFunction` help must fill in the field name from the start.
- The self-named enum form stops being a newtype, and under the follow-up it is now an error. Old tests, posts and model output may still contain it. The docs and `blink llms` text show only the struct form.
- A one-field struct must lower as its field for every one-field struct, by shape and not by name, or the `Errno` migration can regress the FFI paths in libc.bl and fs_ops.bl. A self-host regen does not catch this.
- The `@json(transparent)` ticket can lose its scope limit or its deliberation gate when it is filed. Then it can grow into a general serde-style attribute design.
- Hand-written `Serialize` impls for each ID type can spread before the ticket is worked.
