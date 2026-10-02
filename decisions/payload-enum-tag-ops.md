[< All Decisions](../DECISIONS.md)

# Payload Enum Tag Operations and Newtype Layout — Design Rationale

## The question

The spec ticket asked: should a user single-`Int`-payload newtype lower transparently, like the stdlib `Errno`? Today a table keyed on the declaration `std.errno.Errno` marks only that type as transparent, so a user `type Code { Code(Int) }` keeps a tagged layout.

A probe on 2026-10-02 found a semantic split under the layout question:

```blink
import std.errno
type Code { Code(Int) }

fn main() {
    let e = Errno(5)
    let c = Code(5)
    io.println("{e == 5}")         // true: compares the payload, but §3 said enum == Int compares the tag (0)
    io.println("{c == 5}")         // typechecks, then the emitted C does not compile
    io.println("{e.to_int()}")     // 0, the tag
}
```

## Outcome

- **Q1 (6-0):** comparison of an enum with `Int`, `Enum.to_int()` and `Enum.from_int()` are defined only on fieldless enums. On an enum with a payload variant, each is a compile-time `TypeError` with a `match` help line. Written into §3 *Enums Are Nominally Distinct from `Int`*.
- **Q1b (5-1, web dissent):** `Errno.code()` (promised in §07, not in `lib/std/errno.bl`) is a separate follow-up, not part of this change.
- **Q2–Q4 (G passed 5-1, min dissent) — overruled by the user.** The panel voted to write a size guarantee for single-field newtypes into the spec (G), for any payload type after monomorphization (Q3 A) and for single-field structs (Q4 A). The user ruled: **"implementation details dont go in spec"**. The spec says nothing about the layout of any enum or newtype. Dropping a tag that no program can observe is a codegen choice. The implementation still removes the declaration-keyed table and lowers by shape, as codegen work. The existing layout wording in §07 (`Errno` "no boxing, no tag, monomorphizes to a bare int"; `MsgFlags` "C representation is one `int64_t`") was removed under the same ruling.
- **Q5 (Phase D 3-2-1, no majority) — user chose B2.** The layout of single-variant enums with more than one field is not specified; the compiler may omit the tag. The user ruled that this is an implementation detail and not a spec question. It goes to a codegen chore.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

The relay cut each Phase A message at about 4,000 characters. Each entry is the received text, verbatim.

<details><summary><b>Systems</b> (excerpt)</summary>

> ## Systems proposals for xq8y7y: transparent newtypes
>
> **Position.** Make transparency a property of the type's shape, and make it guaranteed rather than an optimization. Also fix the `==`/`to_int` semantics, which are broken now whichever way the transparency question goes.
>
> ### Proposal S1 (preferred): a single-variant enum has no tag
>
> Rule for the spec (§3): *"An enum with exactly one variant has no runtime tag. If that variant has exactly one payload field, the enum has the size and C representation of that field. Otherwise it has the representation of a struct of its fields."*
>
> ```blink
> type Code { Code(Int) }           // lowers to int64_t
> type Port { Port(U16) }           // lowers to uint16_t
> type Wrap[T] { Wrap(T) }          // Wrap[Float] lowers to double, after mono
> type Pair { Pair(Int, Int) }      // a struct of 2 x int64_t, no tag word
>
> fn main() {
>     let r: Result[Int, Code] = Err(Code(5))
>     match r {
>         Ok(n) => io.println("{n}")
>         Err(Code(c)) => io.println("code {c}")
>     }
> }
> ```
>
> - **Hardware view.** A tag that can hold only one value carries zero bits of information. Emitting it costs memory and speed for nothing: `List[Code]` becomes 16 B per element instead of 8, and `Result[_, Code]` grows. Rust has dropped the discriminant from single-variant enums for years, and its users never ask for it back.
> - **Why shape, not declaration.** The old bug, where code keyed on the *name* `Errno` miscompiled user types, came from keying on spelling. Keying on shape fixes it at the root, because the rule reads only the declaration's structure, so the name has no effect. The `std_errno` table row goes away. Errno, a user `Code`, and `Raw[T]` all fall out of one rule with no list to keep in sync.
> - **The "ABI change" worry is void.** Constraint 6 says enums never cross FFI. Blink has no stable ABI between compilers, and the std archive is built by the same compiler as the user code. Changing this layout breaks nothing that anyone outside the compiler can see.
> - **Predictability.** Users can reason about the cost: "one variant, one field, so it is the field." I want this as a spec guarantee, not a "may", so that people who write performance-critical code can rely on it.
>
> ### Proposal S2 (required with S1 or without it): `==`/`<`/`to_int`/`from_int` against `Int` apply to fieldless enums only
>
> Today the meaning of `Errno(5) == 5` depends on how the type is laid out: the spec says it is `false` (the tag is 0), but the compiler prints `true`. For a user `Code(5) == 5`, the emitted C does not compile. Both are latent bugs. The root cause is that "compare the tag" has no useful meaning when a payload exists, and `from_int(n)` *cannot construct* a payload variant at all. So these operations only make sense for fieldless enums.
>
> ```blink
> let e = Errno(5)
> if e == 5 { }                 // error[TypeError]: Int comparison needs a fieldless enum; Errno has a payload
> match e {
>     Errno(rc) => if rc == 5 { }   // OK: compare the payload explicitly
> }
> let s = State.Running
> if s.to_int() == 1 { }        // OK: State is fieldless
> ```
>
> - The check happens at typecheck time, so the program fails before the C compiler sees it.
> - With this rule, no Blink operation can tell whether a tag exists. That makes S1 a pure layout choice with zero semantic surface. The compiler is then free to lay out any enum as it likes.
> - If the Errno ergonomics are a concern, a `.code() -> Int` method in std.errno, which §07 already says it has, is the explicit way out.
>
> ### Single-field structs: no rule needed
>
> `type UserId { value: Int }` is already one `int64_t` inside a C struct. On SysV x86-64 and AAPCS64, a struct holding one integer is passed and returned in a register, the same as a bare int. It has no tag and no box. The C printer may emit either form, and the spec should promise only "same size, no indirection." MsgFlags is covered by this as it stands. It stays opaque by compiler knowledge, as already decided, and needs no transparency fact
> [result truncated — ask the agent for the rest via SendMessage]

</details>

<details><summary><b>Web/Scripting</b> (excerpt)</summary>

> # Web/Scripting: Phase A proposal
>
> ## Where I start
>
> A JS, Python or Kotlin dev who copies the stdlib pattern expects the same behavior. Today they don't get it:
>
> - `Errno(5) == 5` is `true`, but the spec says it compares the tag, which is 0.
> - `Code(5) == 5` passes the type checker and then fails in the C compiler.
> - `c.to_int()` returns 0 on every value.
>
> These results are the real bug. The question "who gets the transparent lowering" matters less. Once the rules for `==` and `to_int` are fixed, the lowering can't be seen, and the question becomes "which types get the fast path".
>
> ## W1 (preferred): fix the semantics, key transparency on shape, guarantee zero cost
>
> **Rule 1: semantics.** An enum whose variants carry payloads is not C-like. These are compile errors on it:
> - Comparing it with `Int` (`==`, `<`, and the rest).
> - `.to_int()` and `.from_int()`.
>
> They stay legal on fieldless enums, so the 03_types section on enum comparison still holds there. The error points the user to the payload.
>
> ```blink
> import std.errno
>
> type Code { Code(Int) }
>
> fn main() {
>     let c = Code(5)
>     if c == 5 { }           // error[TypeError]: cannot compare Code with Int
>                             //   help: compare with Code(5), or match on Code(n)
>     if c == Code(5) { }     // OK: compares the payload
>     match c {
>         Code(n) => io.println("code {n}")
>     }
>     let e = Errno(5)
>     io.println("{e.code()}")  // Errno's named projection (§9.1.3.3)
> }
> ```
>
> **Rule 2: lowering.** A type gets the zero-cost lowering (bare scalar, no tag, no box) when it is either:
> - an enum with exactly one variant whose one positional field is a scalar (`Int`, sized ints, `Float`, `Bool`, `Char`), or
> - a struct with exactly one scalar field (`type UserId { value: Int }`, the idiom §3 "No 1-Tuples" tells users to write).
>
> The spec states this as a guarantee, in the same words it uses for Errno. Errno, MsgFlags and `Raw[T]` then match the general rule. None of them needs its own row in a table.
>
> **Tradeoffs**
> - (+) No stdlib-only magic. "Why is my `Code` slower than `Errno`?" never becomes a Stack Overflow question. The pattern the docs teach is the pattern that is fast.
> - (+) Kotlin `value class` and Rust newtypes work this way: the shape gives zero cost, and no annotation is needed.
> - (+) The rule is easy to teach: "one variant or field, one scalar, zero cost."
> - (-) It is a breaking change: code that does `errno == 5` must change to `e.code() == 5` or `e == Errno(5)`. The surface is small and the change is mechanical.
> - (-) The old name-keyed gate miscompiled. The risk was in the gate. Shape is easier to check than name, and the gate must check shape anyway. The test matrix must cover Option, Result, List and struct fields, plus user types named Errno with a different shape.
>
> **Cross-language.** Kotlin rejects `Code(5) == 5` at compile time ("Operator '==' cannot be applied"). Python's `Enum` returns `False` for `Color.RED == 1`, and only `IntEnum` returns `True`. Users widely see that split as a footgun. TS branded types compare as numbers, which is what makes them leaky. Kotlin is the closest model and the best one to follow.
>
> ## W2 (fallback): the spec promises semantics only, and lowering is the compiler's choice
>
> Keep Rule 1. Change the spec to say: "A newtype's representation is not observable. The compiler may lower any single-scalar newtype to a bare scalar." Errno keeps its zero-cost guarantee by name. The implementation can stay keyed on the declaration for now and widen later without a spec vote.
>
> - (+) Smallest spec change, and it fixes the bugs users see.
> - (-) A user can't rely on zero cost for their own type. People who care about performance will ask, and "it depends on the compiler" is a poor answer.
>
> ## Rejected: an opt-in `@transparent` annotation
>
> I argued for this before and dropped it in the enum-nominal vote. It makes users learn an annotation to get behavior they already expect by default. It also creates a second kind of newtype th
> [result truncated — ask the agent for the rest via SendMessage]

</details>

<details><summary><b>PLT</b> (excerpt)</summary>

> **PLT panelist: Phase A proposals (spec ticket xq8y7y)**
>
> **Diagnosis first.** The ticket asks the wrong question. Choosing between "declaration-keyed" and "shape-keyed" only matters if the lowering is observable. A correct lowering is a pure refinement of the program: no well-typed program can tell the two layouts apart. The probe shows Blink breaks this today. `Errno(5) == 5` gives `true` because the transparent layout compares the payload. The spec rule (§3, "Comparison is unaffected") compares the tag, which is 0. So one source program has two meanings depending on a codegen table. That is unsound, whichever key we pick. The user-side `Code(5) == 5`, which typechecks and then fails in the C compiler, is the same defect showing up as a crash.
>
> The cause is a typing rule that is too wide. "Enum compares with Int by tag" and `to_int()` make sense for **fieldless** enums only, where the tag *is* the value. For a single-variant enum the tag is the constant 0, so `Errno.to_int()` is a total function that ignores its argument. No one wants that function.
>
> ---
>
> **P0 (needed before either keying choice): tag operations only on fieldless enums**
>
> Typing rule: `e ⋈ n` for `⋈ ∈ {==,!=,<,<=,>,>=}` with `e : E` and `n : Int` typechecks only if every variant of `E` has zero fields. The same holds for `E.to_int()` and `E.from_int`. Otherwise it is a TypeError.
>
> ```blink
> import std.errno
>
> type Code { Code(Int) }
> type State { Idle, Running }
>
> fn main() {
>     let e = Errno(5)
>     let s = State.Running
>     io.println("{s == 1}")          // OK: fieldless enum, compares the tag
>     io.println("{e.code() == 5}")   // OK: explicit projection
>     io.println("{e == 5}")          // error[TypeError]: Errno has payload fields; compare e.code()
>     io.println("{Code(5).to_int()}") // error[TypeError]: to_int needs a fieldless enum
> }
> ```
>
> After P0, a newtype gives the user no operation that sees the tag. Only `match`/destructure and declared methods remain, and both commute with erasing the wrapper. Breakage: the current results are already wrong (`true`, `0`, a C error), so code that relies on them already has a bug.
>
> ---
>
> **P1 (recommended): shape-keyed transparency, defined as an isomorphism and not by name**
>
> Rule: a monomorphic instance of a type `N` lowers to its payload type `P` when all of these hold:
> - `N` is an enum with exactly one variant that has exactly one field, or a struct with exactly one field;
> - `P` does not mention `N`, directly or through another transparent type (otherwise there is no fixed point);
> - P0 holds, so `N ≅ P` with no observable difference.
>
> The spec says this lowering is **unobservable**. It is a zero-cost guarantee and not part of semantics, so no user can write code that tests for it. It composes: transparency is decided after monomorphization, so `W[A] { W(A) }`, nested newtypes (`Code(Errno)` → `int64_t`) and `Raw[T]` collapse step by step. MsgFlags stays opaque. Opacity is a *visibility* property and transparency is a *representation* property. They are orthogonal, and that is the point. The single-field struct `UserId { value: Int }` (§3 "No 1-Tuples") gets the same zero cost, so the spec's two newtype idioms cost the same.
>
> ```blink
> type UserId { value: Int }
> type Meters { Meters(Float) }
> type Wrap[A] { Wrap(A) }
>
> fn total(xs: List[Meters]) -> Float {
>     let mut t = 0.0
>     for m in xs {
>         match m {
>             Meters(v) => t = t + v
>         }
>     }
>     t
> }
> // List[Meters], Result[Int, UserId], Wrap[Wrap[Int]]: all bare scalars in C
> ```
>
> Tradeoffs:
> - (+) One rule for stdlib and user code. The stdlib-privilege table goes away, and so does the class of bugs where a name collides with a table entry.
> - (+) The Errno, Raw[T] and MsgFlags spec text becomes a *consequence* of the rule, not a set of special cases.
> - (−) It changes the internal ABI for user types and for the stdlib archive. §07 forbids enums at FFI, so the change is not visible outside Blink. The stdlib archive and user code must agree on the sh
> [result truncated — ask the agent for the rest via SendMessage]

</details>

<details><summary><b>DevOps/Tooling</b> (excerpt)</summary>

> # DevOps/Tooling: Phase A proposal (ticket xq8y7y)
>
> ## What the user sees today
>
> From my side the probe shows two failures, and both are worse than any layout question:
>
> 1. `Code(5) == 5` passes the type checker, then the C compiler rejects the output. The user gets a cc error about generated C they never wrote. No LSP squiggle, no `blink check` hit, no fix-it. This is the worst diagnostic a toolchain can produce.
> 2. `Errno(5) == 5` is `true` and `Code(5) == 5` would compare the tag. So whether a declaration happens to be in the transparency table changes what `==` returns. Hover in the LSP can't explain that, and neither can `blink llms` or a code reviewer.
>
> My rule: **the lowering must never change the result of a program.** Fix that first. After that, whether transparency is keyed on the declaration or on the shape is only a performance question.
>
> ## Proposal A (I recommend this): shape-keyed lowering, with semantics that don't depend on it
>
> **A1. Comparison and `to_int` belong to fieldless enums only.** An enum that has any payload variant has no useful "tag as Int". For a single-variant enum the tag is always 0. Make enum-vs-`Int` comparison and `to_int`/`from_int` a type error on any enum that has a payload variant, and give the error a fix-it:
>
> ```blink
> import std.errno
>
> type Code { Code(Int) }
>
> fn main() {
>     let c = Code(5)
>     if c == 5 { }            // error[TypeError]: `Code` has payload variants; it has no Int tag to compare
>                              //   help: match on the payload: `match c { Code(n) => n == 5 }`
>     let n = c.to_int()       // error[TypeError]: `to_int` is defined only for fieldless enums
>     let e = Errno(5)
>     if e.code() == 5 { }     // OK: the domain projection §07 already gives Errno
>     match e {
>         Errno(n) => io.println("errno {n}")
>     }
> }
> ```
>
> Every failing line now gets a squiggle in the editor and a fix-it the LSP can apply. Nothing reaches cc. Errno already has `.code()`, so stdlib loses nothing.
>
> **A2. Lowering is keyed on shape.** Rule: an enum with exactly one variant, where that variant has exactly one positional payload of type `T`, lowers to bare `T`. The rule doesn't care about the module or the name. That covers Errno, user `Code`, and `Raw[T]` (Systems already said it "lowers to bare T exactly as Errno(Int) does"). After A1 the lowering can't be observed except through size and speed, so it is an optimization and not an ABI promise. Enums can't cross FFI (constraint 6), so no C caller depends on it.
>
> The declaration-keyed table exists because a *name* gate miscompiled user types called `Errno`. A shape rule has no name in it, so that bug class can't come back. The table is the special case that needs explaining, and every user who asks "why is my newtype slower than Errno?" has to be told about it.
>
> Tooling cost: none for `blink fmt`. LSP hover can add one line, "lowered as `Int` (single-payload newtype)", from the same predicate codegen uses. One function, one source of truth.
>
> **A3. A single-field struct (`type UserId { value: Int }`) keeps its lowering.** A one-member C struct already costs nothing. Changing it buys nothing and widens the ABI surface.
>
> **A4. MsgFlags stays opaque by compiler knowledge**, as decided. Its representation is already one `int64_t`. No new rule is needed.
>
> ## Proposal B (alternative): opt-in `@transparent`
>
> ```blink
> @transparent
> type Code { Code(Int) }
> ```
>
> The compiler checks the shape at the declaration. A wrong shape gets an error that points at the annotation. This gives a diagnostic surface at the declaration and makes the intent clear when someone reads the code. I rank it below A: it adds an annotation that users must learn and that AI authors will forget, all for an optimization the compiler can find by itself. B still needs A1, because without A1 the annotation would change what `==` does, and that is the same bug.
>
> ## What I reject
>
> - **Keep the table and leave semantics alone.** That keeps the C-compile failure and the `=
> [result truncated — ask the agent for the rest via SendMessage]

</details>

<details><summary><b>AI/ML</b> (excerpt)</summary>

> **AI/ML panelist: Phase A proposals (ticket xq8y7y)**
>
> The real gap is not where the tag elision applies. The gap is that the elision is visible in program results. `Errno(5) == 5` is `true`, but the same comparison on a user `Code(5)` fails in the C compiler. Under the spec text, both should compare the tag, which is 0. An LLM cannot learn a rule that lives in a private table in `src/layout.bl` and changes what `==` returns. Rule number one for learnability: **representation is never observable.** If it isn't observable, "declaration-keyed vs shape-keyed" stops being a language question and becomes an optimizer detail.
>
> ---
>
> ### Proposal 1 (recommended): Payload enums lose tag-as-Int operations; transparency becomes an unspecified optimization
>
> **Rule A (spec change, user-visible).** Enum-vs-`Int` comparison and `Enum.to_int()` / `Enum.from_int()` are defined only for enums whose variants all carry no payload. For an enum with any payload variant, they are a compile error. The tag of `Code(5)` is meaningless to a user, and "compare the tag" on a payload enum is a silent trap: `c == 5` reads as "payload is 5".
>
> ```blink
> import std.errno
>
> type State { Idle, Running, Done }
> type Code { Code(Int) }
>
> fn main() {
>     let s = State.Running
>     io.println("{s == State.Running} {s.to_int()}")   // OK: fieldless enum
>
>     let c = Code(5)
>     // c == 5        // error[TypeError]: Code has payload variants; compare with match or a projection
>     // c.to_int()    // error: to_int is defined only for fieldless enums
>     let n = match c {
>         Code(v) => v
>     }
>     io.println("{n == 5}")
>
>     let e = Errno(5)
>     io.println("{e.code() == 5}")   // Errno keeps its named projection
> }
> ```
>
> **Rule B (spec text).** "The run-time layout of a type is not part of its meaning. A single-variant enum and a single-field struct behave the same whether or not the compiler removes the tag or wrapper." The compiler is then free to lower **every** single-variant enum and every single-field struct to its payload, by shape. Errno, MsgFlags, Raw[T], `type UserId { value: Int }` and a user `Code(Int)` all get the same lowering, and no table is needed. The Errno spec sentence ("no tag, monomorphizes to a bare int") stays true as a stdlib guarantee, and it becomes an instance of the general rule.
>
> **Why this is best for AI codegen:**
> - **No new decision points.** Users and models write the obvious newtype and get zero cost. There is no annotation to remember and no "is this type special?" check.
> - **One rule replaces three exceptions.** Errno, MsgFlags and Raw stop being "compiler-known". Today the spec names each one separately, and each named exception is something a model must memorize instead of derive.
> - **It removes a trap that training data will plant.** Go (`type Code int; c == 5` compiles) and C enums teach that newtype == literal works. Under Rule A this fails loudly at compile time instead of returning the tag.
> - **Token cost:** `e.code() == 5` costs about 2 tokens more than `e == 5`. That is cheap for an unambiguous result.
>
> **Cost:** It breaks existing `Errno == Int` code. That code is small and stdlib-local, and it relies on behavior that already contradicts the spec. The migration is mechanical (`.code()`).
>
> **Cross-language:** Rust optimizes single-variant enum layout automatically and promises nothing unless you write `#[repr(transparent)]`. That promise exists only for FFI. Blink enums cannot cross FFI (constraint 6), so Blink needs no promise and no annotation. Haskell `newtype` erases the wrapper, but it does not have `==` with the inner type either. That is the model to copy.
>
> ---
>
> ### Proposal 2 (fallback): Keep the table, fix the semantics
>
> Keep transparency declaration-keyed (Errno only, then MsgFlags and Raw added as rows), and still adopt Rule A so `Errno(5) == 5` stops diverging from `Code(5) == 5`.
>
> - **For AI:** It works, but the spec must keep listing "compiler-known" types. A model reading the spec still asks "will my `Code(Int)
> [result truncated — ask the agent for the rest via SendMessage]

</details>

<details><summary><b>Minimalism</b> (excerpt)</summary>

> ## Minimalism, Phase A
>
> **My view:** the ticket asks the wrong question. Declaration-keyed or shape-keyed only matters because users can see the lowering, through `==` and `.to_int()`. If we remove that, the spec does not need to say anything about transparency. It becomes a compiler optimization, and the spec stays silent about optimizations, as it does for register allocation.
>
> ### M1 (primary): make representation unobservable, then let the compiler choose
>
> **Rule 1.** Enum-to-`Int` comparison, `.to_int()` and `.from_int()` exist only for payload-free enums, where every variant has no fields. On an enum that has a payload variant, they are a type error.
>
> ```blink
> import std.errno
>
> type State { Idle, Running }
> type Code { Code(Int) }
>
> fn main() {
>     let s = State.Running
>     io.println("{s == 1}")          // OK: payload-free enum, compares the tag
>     let c = Code(5)
>     io.println("{c == 5}")          // error[TypeError]: Code has a payload variant; no Int comparison
>     let e = Errno(5)
>     let n = match e {
>         Errno(rc) => rc             // the one way to read the payload
>     }
>     io.println("{n == 5}")          // true
> }
> ```
>
> This subtracts surface. Comparing a payload enum's tag with an `Int` means nothing: `Code(5) == 0` is "true" because the tag is 0. Today that expression gives one of three results:
>
> - `true` (the Errno payload)
> - `false` (the tag)
> - a C compiler error, for a user `Code`
>
> All three disagree with each other, and the spec's own rationale ("cannot be confused with a plain `Int`") argues against the comparison. lib/std/errno.bl already says "No methods in v1, extract the code by matching `Errno(rc)`", so the stdlib loses nothing.
>
> **Rule 2.** The spec says the lowering of user types is unspecified. The compiler may lower any single-variant, single-scalar-payload enum, or single-field struct, as a bare scalar. Errno keeps its §07 promise of "transparent, zero-cost" as a guaranteed property of that one stdlib type. Users cannot observe the difference, so it is not an ABI promise: enums cannot cross FFI (constraint 6). The "ABI change for other enums" worry from the original deferral does not apply.
>
> After this, `lo_decl_fact_table` can become a shape rule or stay a one-row table, and that is an implementation choice that needs no panel vote. I would let it become shape-keyed. Then the table goes away, and so does a class of name and module bugs.
>
> **Tradeoffs**
> - (+) Net removal: three operators, two methods, and one compiler-known table stop applying to payload enums.
> - (+) One question gets one answer for every type: "does a tag exist?" is never visible, so nothing depends on it.
> - (−) A breaking change for any code that does `payloadEnum == n`. That code is already wrong or does not compile, so I count this as a small cost.
> - (−) Rule 2 leaves size and speed unspecified for user types. Users who need a guaranteed bare `Int` use `Int` or a sized integer. YAGNI on a guarantee nobody has asked for.
>
> ### M2 (fallback): declaration-keyed, plus Rule 1 only
>
> If the panel wants size guarantees in the spec, then keep the one-row table and add only Rule 1. I would not add a user-facing annotation such as `@transparent`. It is new syntax for a property users cannot observe once Rule 1 is in, and new syntax is the worst trade on offer here.
>
> ### What I reject
> - **A spec'd shape rule ("any `T { T(Int) }` is transparent"):** this puts a lowering detail in the spec. Every later shape question then needs its own ruling: `F32`, `Bool`, `Ptr`, generic payloads, single-field structs. That is the C++ committee path.
> - **Folding MsgFlags and Raw[T] into this decision:** they are already opaque or marker types by compiler knowledge. Under M1 their lowering is free anyway. One rule should not grow three special cases.
>
> ### Cross-language notes
> - **Rust:** `#[repr(transparent)]` exists only because Rust exposes layout at FFI. Blink does not, so it does not need the attribute.
> - **Go:** `type Code int` gives a distinct t
> [result truncated — ask the agent for the rest via SendMessage]

</details>


#### Phase A.5 — Mechanical dedupe

All six proposed the same Q1 rule. Q2 had options U (layout unspecified; min, aiml, web fallback), G (shape rule as a guarantee; sys, plt, web, devops), D (keep the declaration table; min and aiml fallback) and T (opt-in `@transparent`; devops, later withdrawn). Variations flagged for debate: payload kind, single-field structs, multi-field single-variant enums, self-reference, MsgFlags/Raw.

#### Phase B — Debate, round 1

<details><summary><b>Systems</b></summary>

> ## Systems: Phase B round 1
>
> **Q1: yes, as written.** All six panelists agree on it. On the help line: `.code()` does not exist (fact 1), so the help line must not point users at it. Use the devops wording: "help: match on the payload: `match c { Code(n) => n == 5 }`". Drop web's "compare with Code(5)" too, because enum-vs-enum `==` on a data enum is still an open ticket (fact 2). Adding `Errno.code()` is a cheap stdlib follow-up that §07 already promises, so file it as a chore, not as part of this vote. Fact 3 tells me Q1 breaks no existing code.
>
> **Q2: Option G.** I accept plt's wording: lowering cannot change what a program means, but the cost is guaranteed. Those two claims do not conflict. One is about what a program means and the other is about what it costs.
>
> Against U: "unspecified" plus "Errno guaranteed by name" sets up two tiers, a stdlib privilege and a user guess. A user who follows the §3 newtype idiom has to know whether `List[Code]` is 8 or 16 bytes per element. The spec is the place that answers that. If it says "may", the honest answer becomes "read the C output". U also leaves the name-keyed path in the compiler, which is the path that already miscompiled once.
>
> Against D: same objection, and it keeps a table that users can never join.
>
> Against T: an attribute exists to make an ABI promise across FFI. Constraint 6 means Blink has no such ABI, so the annotation would mean nothing, and users would forget to write it.
>
> On the flagged variations:
> 1. **Payload kind:** any `T` after mono. Dropping a tag that holds one constant saves the same bytes whether the payload is `Int` or `List[Int]`. A scalars-only limit adds a special case and buys nothing in return.
> 2. **Single-field structs:** include them. Either C form costs the same, so the guarantee is free, and one rule for both newtype idioms is simpler to teach than two.
> 3. **Multi-field single-variant enums:** I still think the tag should drop, but they are not newtypes. I withdraw this from the vote and will file it as a separate follow-up, so this decision stays narrow.
> 4. **Self-reference (plt):** accept. `type T { T(T) }` has no finite layout, so the condition costs nothing.
> 5. **MsgFlags / Raw[T]:** they follow from the rule. Opacity is a separate axis: MsgFlags stays opaque by compiler knowledge, exactly as decided. I would not add special text for either type.
>
> **Stable, ready to vote:** Q1 with the match-on-payload help line, and Q2 Option G with any `T` after mono, single-field structs included, plt's self-reference condition, and multi-field enums dropped from this vote.

</details>

<details><summary><b>Web/Scripting</b></summary>

> **Q1: yes, unchanged.** All six of us agree, so I only have notes on the help line.
>
> - Drop "compare with Code(5)" from my help text. Payload-enum `==` belongs to the separate open Eq ticket, and our diagnostic should not promise an answer to it. Use `help: match on the payload: match c { Code(n) => n == 5 }`. Devops and min have this right.
> - `Errno.code()` must ship in the same change as Q1. §07 already promises it. Without it, the Errno repair is a four-line `match` for something Python or Kotlin users write as `e.code == 5`. That is the Stack Overflow question we would create. Moderator fact 1 means this is spec debt, not a new feature, and it should land first. Fact 3 says the Q1 break hits almost nothing.
>
> **Q2: Option G (guarantee); U is my second choice; I reject T. D only if G and U both fail.**
>
> On the flagged variations:
>
> 1. **Payload kind.** I move to sys and plt: any `T` after monomorphization. The user rule gets shorter: "a one-field newtype costs the same as its field". Nobody needs a list of which types count as scalar. Nested newtypes then follow from the rule and need no special case.
> 2. **Single-field structs.** Include them. §3 tells users to write `type UserId { value: Int }`, so the guarantee must cover the idiom we teach. Sys's point is fair: a one-member C struct already costs nothing. So I accept sys's wording: "same size as its field, no tag, no box, no indirection". The spec then promises what users can measure, and the compiler picks the C form.
> 3. **Multi-field single-variant enums.** Out of scope. No user sees a tag on `Pair(Int, Int)` except through memory size. Decide it when someone asks.
> 4. **Self-reference.** Yes, plt's condition is required. A recursive type can't lower to its own payload. If we omit the condition, the spec contradicts itself.
> 5. **MsgFlags and Raw[T].** They follow from the rule. Whether a type is opaque has nothing to do with how it lowers. Min's caution is about procedure, and I accept it: don't rewrite their §07 text here, just check it stays consistent.
>
> **Responses**
>
> - **To aiml and min, on U ("layout is not part of meaning").** That is true for semantics, but users still see it in `List[T]` memory size and speed. A "may" makes the fast pattern depend on the compiler version. Errno would get a promise by name and `UserId` would not, which is the stdlib-only privilege this ticket is about removing.
> - **To devops ("not an ABI promise").** Agreed, and it costs nothing to say: enums can't cross FFI, so this is a promise about size and cost, not about ABI. Please confirm that A2 is a guarantee and not a "may". If it is, we have four votes for G.
>
> **Status:** stable, ready to vote.

</details>

<details><summary><b>PLT</b></summary>

> **PLT, Phase B round 1**
>
> **(1) Q1: adopt it.** Q1 is my P0, and the panel agrees on it 6-0. The rule it makes sound: no well-typed program can observe the tag of an enum whose variants carry payloads.
> - **Help line:** use devops/min's `match c { Code(n) => n == 5 }`.
>   - Reject `e.code()`: fact 1 shows it does not exist, so a help line that names it sends users to an error.
>   - Reject web's "compare with Code(5)": fact 2 shows enum-vs-enum `==` on data enums is still an open question.
>   - The help line must point only at a form the language already defines. That is `match`.
> - **Scope:** also state the dual. An `Int` scrutinee matched against payload-variant patterns is ill-typed. §3 already says this for enums in general, so this is no new rule.
>
> **(2) Q2: G, worded as a cost guarantee and not as a C layout.** Once Q1 lands, U and G have the **same semantics**: the layout cannot be observed in either. They differ only in the **cost model**. A cost model belongs in a spec when users depend on it, as they already do for "Errno is zero-cost" and "sized ints map to C". I adopt sys's form of words: "same size as its payload, no tag word, no indirection." It promises cost and does not fix the C spelling, so a one-member C struct satisfies it. That also settles variation 2: single-field structs are included at no extra cost.
>
> The flagged variations:
> 1. **Payload kind:** any `T` after monomorphization. A scalars-only rule does not compose. `Code(Errno)`, `Wrap[UserId]` and `Raw[T]` would each lose the guarantee one level down. A rule that does not hold up under substitution is not a type-level rule.
> 2. **Structs:** include them, with the cost wording above.
> 3. **Multi-field single-variant enums:** sound under Q1, because the tag is the constant 0 and Q1 makes it unobservable. I accept dropping the tag. It follows from the rule and is no extra feature.
> 4. **Self-reference:** required, stated precisely: P must not contain N **by value**. `type L { L(List[L]) }` is fine. `type T { T(T) }` has no finite layout and is excluded.
> 5. **MsgFlags and Raw[T]:** both follow from the rule with no row in any table. Opacity is visibility and transparency is representation, and the two are orthogonal. I agree with min that their §07 text needs no edit. The text simply becomes true by the rule.
>
> **Fallbacks:** U is acceptable, because it is sound and differs from G only in cost. D is acceptable only with Q1. I reject T. Under Q1 the annotation has no meaning that a program can observe, so it is ceremony. Rust's `repr(transparent)` is opt-in only because it fixes a C ABI, and Blink exposes no such ABI for enums.
>
> **(3) A response to the facts:** fact 1 is a separate gap. §07 promises `.code()` and the stdlib does not ship it. File it as a bug against `lib/std/errno.bl` and keep it out of this decision.
>
> **Ready to vote: yes.** My order is Q1, then G (any T, structs included, by-value self-reference excluded), then U, then D.

</details>

<details><summary><b>DevOps/Tooling</b></summary>

> **DevOps/Tooling, Phase B round 1**
>
> **(1) Positions**
>
> **Q1: yes.** I agree with the other five, so this is settled.
>
> Help line: I change mine because of fact 1. `Errno.code()` doesn't exist, so a fix-it that suggests it gives the user a second error. Fact 2 rules out web's "compare with `Code(5)`": it would point users at behavior another open ticket may still forbid. The only repair that works today on every payload enum is `match`:
>
> ```
> error[TypeError]: `Code` has a payload variant; it has no Int tag to compare
>   help: match on the payload: `match c { Code(n) => n == 5 }`
> ```
>
> Errno gets the same help line until `.code()` ships. The missing `.code()` is a separate gap between §07 and lib/std/errno.bl and should get its own ticket. This decision must not depend on it.
>
> **Q2: Option G, stated as a guarantee.** In answer to the procedural question: my A2 means a guarantee. The spec says "has the size and representation of `T`; no tag, no indirection". It does not say "may". It does not promise a C ABI, since enums can't cross FFI.
>
> Why a guarantee, from the tooling side:
> - A guarantee can be tested. We can put a size assertion in tests/ and gate it. A "may" can't be gated, so it fades away the first time someone refactors.
> - LSP hover and `blink query` can say "lowered as `Int`" without lying. Under U they would need "maybe".
> - Users who size a `List[Code]` get one answer. Under U the answer depends on the compiler version.
>
> Variations:
> 1. **Payload kind:** any `T` after monomorphization. A scalar-only rule leaves `Raw[T]` and nested newtypes out, and that recreates the special case we are removing.
> 2. **Single-field structs:** include them, worded as sys proposes: "same size, no indirection". That costs nothing to promise and keeps the two newtype idioms from §3 in step. I drop A3.
> 3. **Multi-field single-variant enums:** this is outside the ticket. Don't vote it in here; log a follow-up.
> 4. **Self-reference (P must not mention N):** accept. The compiler needs a defined result there, and plt's condition gives one.
> 5. **MsgFlags / Raw[T]:** they follow from the rule. MsgFlags opacity is a separate axis and stays decided as it is.
>
> **(2) Responses**
>
> - **I withdraw my Option T (`@transparent`).** With Q1 settled, the lowering can't change what a program returns, so an annotation only adds something to learn. Three panelists rejected it, and I agree now.
> - **To min and aiml (Option U):** "unspecified" is acceptable only because Q1 removes every way to observe the layout. I still rank it below G, for the testability reasons above. Fallback order: G, then U, then D.
> - **D (keep the table):** if we pass Q1, D keeps a table whose only effect is that user newtypes are slower. No diagnostic can explain that, so D is my last choice.
>
> **(3) Stable, ready to vote.** Q1 yes, with the `match` help line. Q2 is G as a guarantee: any `T`, structs included, the self-reference condition, and the multi-field case deferred.

</details>

<details><summary><b>AI/ML</b></summary>

> **AI/ML: Phase B round 1**
>
> **(1) Positions**
>
> **Q1:** Yes, as all six proposed.
> - **Help line.** Fact 1 kills my `e.code() == 5` repair, because `.code()` does not exist. Fact 2 kills web's "compare with `Code(5)`", because enum-vs-enum `==` on data enums is undecided. A help line must never suggest code that fails to compile, since models copy help lines word for word. I back devops's text: `help: match on the payload: match c { Code(n) => n == 5 }`. It works today and it works for every payload enum.
> - **Follow-up.** §07 promises `.code()` but lib/std/errno.bl does not ship it. That is a separate stdlib bug and should not hold up this vote. Once `.code()` exists, the Errno diagnostic may suggest it.
>
> **Q2:** I move from U to **G**, in sys's shortest form:
>
> > "An enum with exactly one variant has no run-time tag. If that variant has exactly one field, the enum has the representation of that field. The lowering is not observable."
>
> Why I moved: under U a model asked "is `type UserId { UserId(Int) }` zero-cost?" can only answer "maybe". G lets the spec answer "yes" in one sentence. Q1 makes the layout unobservable either way, so G only adds a cost model, and a cost model is something a model can reason from. U's only advantage was compiler freedom, and nobody named a case where that freedom matters.
>
> **Variations:**
> 1. **Payload kind:** any T after monomorphization. Scalars only means a list to memorize (`Char`? `F32`? `Str`?) and an odd cliff at `Wrap[Str]`. One rule with no list is easier to learn.
> 2. **Single-field structs:** leave them out of the rule. A one-member C struct is already the same size with no indirection, so a rule adds spec words and saves nothing.
> 3. **Multi-field single-variant enums:** include them. "One variant means no tag" is the simpler sentence. Putting the cut at "one field" adds a condition to learn.
> 4. **Self-reference:** accept plt's condition, but word it as a compiler constraint. A recursive one-variant enum must box anyway, and users never write that shape as a newtype.
> 5. **MsgFlags / Raw[T]:** they follow from the rule. Opacity is a visibility question and has no effect on representation. Each type the spec stops calling "compiler-known" is one less exception to memorize. If the panel prefers min's caution, I accept a note saying they follow from the rule without spending a separate vote.
>
> **Reject D and T.** D keeps a private table that no reader can extend. T adds an annotation decision to every newtype, and it guards nothing a user can observe.
>
> **(2) Response**
>
> devops's A3 argument ("a one-member C struct already costs nothing") is correct, and it is why I drop structs from the rule. Rule A from Phase A included them, so that is a change in my position.
>
> **(3) Status**
>
> Stable, ready to vote: Q1 with the devops help line, Q2 = G in sys's one-sentence form, Variations 1 = any T, 2 = no, 3 = yes, 4 = yes, 5 = follow.

</details>

<details><summary><b>Minimalism</b></summary>

> Minimalism, round 1: Q1 yes. Q2 Option U. Stable, ready to vote.
>
> **Q1:** Yes, the single option. On the help line, the diagnostic must name only a repair that exists. `match c { Code(n) => n == 5 }` works today, so the help line should give that. `e.code()` does not exist yet (fact 1). §07 already promises it, so adding `.code()` to std.errno adds no new surface, and I support that. But the help line must not depend on it shipping. Web's "compare with Code(5)" depends on the open Eq ticket (fact 2), so leave it out of the help text until that ticket closes.
>
> **Q2:** Option U. My ranking: U > D > G (web, scalar only) > G (broad) > T.
>
> My case against G: after Q1, layout cannot be observed except through size and speed. A guarantee users cannot test is ABI wording, and Blink has no ABI here, because enums cannot cross FFI. The digest shows the cost. G already has five variations under debate (payload kind, structs, multi-field tag drop, self-reference, MsgFlags/Raw), and each one becomes spec text we must keep forever. Under U all five are compiler decisions that need no vote. PLT's self-reference rule (variation 4) is the clearest example: a layout guarantee pulls recursion rules into the spec.
>
> Variations:
> 1. **Payload kind:** under U, the compiler decides. If G wins, scalars only. Generic `Wrap[T]` and nested newtypes multiply the cases.
> 2. **Single-field structs:** under U, the compiler is free. Under G, leave them out. Sys is right that a one-member C struct already costs nothing, so a rule adds words and no zero-cost gain.
> 3. **Multi-field tag drop:** no. This decision should not specify layout for every single-variant enum.
> 4. **Self-reference:** under U, an implementation detail. Under G, it is needed, and that is the argument against G.
> 5. **MsgFlags and Raw[T]:** under U, they follow with no new text, so the other panelists and I agree in substance. My objection is only to spec text that enumerates them.
>
> **To sys:** "a guarantee, not a 'may'" protects a property that no program can observe once Q1 lands. If the concern is that Errno must stay a bare int on the syscall path, U keeps that guarantee by name, as §07 does today.
>
> **To devops:** if your A2 means "may", it is U in all but name, and I would count it as U.
>
> **Facts:** fact 3 (no `Errno ==` hits) means Q1 costs almost no migration, which strengthens it.

</details>


#### Phase C — Final vote

Ballot: Q1 A/B; Q1b A (same change) / B (follow-up); Q2 G/U/D; Q3 A (any `T` after mono) / B (scalars); Q4 A (single-field structs included) / B; Q5 A (no tag for any single-variant enum) / B (follow-up).

- **Q1:** A, 6-0
- **Q1b:** B, 5-1 (**Web/Scripting** dissent: A)
- **Q2:** G, 5-1 (**Minimalism** dissent: U)
- **Q3:** A, 5-1 (**Minimalism** dissent: B)
- **Q4:** A, 5-1 (**Minimalism** dissent: B)
- **Q5:** B, 4-2 (**PLT** and **AI/ML** dissent: A) → Phase D

<details><summary><b>Systems</b></summary>

> ## Systems ballot
>
> **Q1: A**
> Reasoning: "Compare the tag" means nothing when the tag holds one constant, and `from_int` cannot build a payload variant at all. Today the same expression gives `true` for Errno and fails to compile in C for a user type. A typecheck error is the only answer that is the same for every layout, and it frees the compiler to lay out enums any way it likes.
> Concern: if someone has written `e == 5` on an Errno and relied on its accidental payload comparison, that code breaks without warning; a text search found none, but a search cannot see comparisons made through a variable.
>
> **Q1b: B**
> Reasoning: The agreed help line uses `match` and does not name `.code()`, so Q1 does not depend on it. Tying a stdlib method to a typecheck rule makes the change bigger and adds no safety. File it as a chore, because §07 already promises it.
> Concern: the follow-up may sit unfixed, leaving §07 promising a method the stdlib does not have.
>
> **Q2: G**
> Reasoning: Cost is something users rely on. Whether `List[Code]` takes 8 or 16 bytes per element should be in the spec, not left to reading the emitted C. G applies one rule to stdlib and user types alike and removes the name-keyed path that miscompiled before. The rule only drops a tag that carries zero bits, so it costs the compiler nothing to keep.
> Concern: every codegen seam (Result/Option arms, struct fields, list elements, generic mono) must honor the shape rule, and one seam that misses it is a silent layout mismatch; each one needs a pin test.
>
> **Q3: A**
> Reasoning: The bytes saved by dropping a constant tag are the same for any payload type. A scalars-only limit adds a special case and buys nothing. Mono already settles `T`, so the decision is local and the compiler always knows the answer.
> Concern: nested newtypes such as `Code(Errno)` and generic `Wrap[T]` exercise the seams most, so the test matrix must cover them, not only `Int`.
>
> **Q4: A**
> Reasoning: A one-field struct already costs nothing in C (it is passed in a register under SysV and AAPCS64), so this guarantee is free. With it, both newtype idioms that §3 names get the same promise, and that is simpler to teach. The wording promises cost, not a C spelling, so the printer keeps its freedom.
> Concern: a later field-privacy or reflection feature could add hidden per-struct metadata and quietly break the guarantee.
>
> **Q5: B**
> Reasoning: I still think a tag that holds one value should never be stored, but `Pair(Int, Int)` is not a newtype and this ticket is about newtypes. A narrow decision with pin tests is better than a wide one with seams left untested.
> Concern: the follow-up gets dropped and multi-field single-variant enums keep a dead tag word with no one tracking it.

</details>

<details><summary><b>Web/Scripting</b></summary>

> **Q1: A**
> - **Reasoning:** `Code(5) == 5` gives `false` today, or it fails in the C compiler. A JS or Python dev would not guess either result. Kotlin rejects the comparison at compile time, and that is the behavior people expect. A compile error with a `match` help line costs one Stack Overflow answer, and a silent `false` costs a hundred.
> - **Concern:** Some user code compares an Errno held in a variable with an `Int`. The text search can't find those, so the break could be larger than fact 3 shows.
>
> **Q1b: A**
> - **Reasoning:** After Q1, an Errno user can read the code only with a four-line `match`, even though §07 already promises `.code()`. Shipping the error before the accessor gives users a "use match" help line in exactly the case the spec says has a one-word method. The method is a few lines, so tying it to Q1 costs almost nothing.
> - **Concern:** If B wins, the follow-up ticket stays open for months and every Errno user writes the `match` form until it lands.
>
> **Q2: G**
> - **Reasoning:** The stdlib example should be the fast way to write a newtype. A guarantee given by name to Errno and only a "may" for `UserId` is stdlib-only privilege, and "why is my type slower than Errno?" becomes a common question. Kotlin `value class` and Rust newtypes promise zero cost by shape, and users already trust that model.
> - **Concern:** The old name-keyed gate miscompiled. The shape gate needs a test matrix across Option, Result, List, struct fields and generic instances before anyone can call it done.
>
> **Q3: A**
> - **Reasoning:** "A one-field newtype costs the same as its field" is one sentence, and a user never needs a list of which types count as scalar. Nested newtypes and `Wrap[T]` then work with no special case, and that is the "just works" result we want.
> - **Concern:** Payloads that are generic or not scalar widen the set of layouts to test, and a miscompile there would be silent.
>
> **Q4: A**
> - **Reasoning:** §3 tells users to write `type UserId { value: Int }`. If the guarantee skips that idiom, the spec teaches the slower of its two newtype forms. Wording the guarantee as cost means the compiler keeps its choice of C form.
> - **Concern:** Users may read "no indirection" as permission to hand the struct to C as an `int64_t`, so the "not an ABI promise" text needs to be clear.
>
> **Q5: B**
> - **Reasoning:** Users see a tag on `Pair(Int, Int)` only through memory size, and nobody has asked for this. YAGNI: decide it when a real need appears, not as a rider on this ticket.
> - **Concern:** Implementers may drop the tag anyway while they work on the one-field gate, and that would decide the question with no vote.

</details>

<details><summary><b>PLT</b></summary>

> **PLT: Phase C ballot**
>
> **Q1: A**
> - **Reasoning:** This restores soundness. Today `Errno(5) == 5` means one thing under one layout and another under the other, and a well-typed program must have exactly one meaning. For a single-variant enum the tag is the constant 0, so tag comparison and `to_int` are degenerate functions that no one writes on purpose. With A in place, no program can observe a payload enum's tag, and that is the precondition for every layout option in Q2.
> - **Concern:** the dual case must not get lost. An `Int` scrutinee matched against payload-variant patterns must also be rejected, or a back door stays open.
>
> **Q1b: B**
> - **Reasoning:** Q1's soundness does not depend on `.code()`. The help line names `match`, which already exists and already works for `Errno(n)`. Bundling a stdlib API addition into a typing-rule fix couples two changes that should land, and if needed revert, separately.
> - **Concern:** the follow-up may stall and leave §07 promising a method that does not exist, so give it a real ticket with an owner.
>
> **Q2: G**
> - **Reasoning:** Once Q1 lands, G and U are the same semantically: the layout cannot be observed in either. They differ only in the cost model. Blink already makes cost-model promises users rely on (Errno is zero-cost, sized ints map to C), and a promise keyed on shape is principled where one keyed on a declaration is ad hoc. It also removes the stdlib-privilege table, which caused the name-collision miscompile.
> - **Concern:** the guarantee must stay worded as size, no tag, no box and no indirection, not as a C spelling, or it will harden into an ABI promise that no one voted for.
>
> **Q3: A**
> - **Reasoning:** The rule must hold up under substitution. If `Code(Int)` is guaranteed but `Code(Errno)` and `Wrap[T]` are not, the guarantee breaks one level of abstraction down, and `Raw[T]` needs exactly the generic case. Deciding after monomorphization is the standard compositional answer (Koka, GHC newtype erasure).
> - **Concern:** the implementation must apply the rule to each instance after substitution, with the by-value self-reference check, or it will either miss nested cases or loop.
>
> **Q4: A**
> - **Reasoning:** §3 names the single-field struct as the canonical newtype idiom. A spec that guarantees zero cost for one idiom and stays silent on the other gives users a cost incentive to pick one over the other for no semantic reason. The cost wording costs the implementation nothing, because a one-member C struct already meets it.
> - **Concern:** this relies on structs having value semantics. If a later feature gives a struct identity or aliasing through `mut`, the isomorphism breaks and this guarantee must be revisited.
>
> **Q5: A**
> - **Reasoning:** With Q1 in place, a single variant's tag is the constant 0 and cannot be observed, so storing it has no semantic content. Leaving the tag word in for multi-field single-variant enums while removing it for single-field ones would split one principle into two special cases. The same argument covers both, so decide it once.
> - **Concern:** this is the one point that goes past the ticket's literal scope. If the panel splits on it, B costs nothing in soundness, only uniformity.

</details>

<details><summary><b>DevOps/Tooling</b></summary>

> **DevOps/Tooling, Phase C ballot**
>
> **Q1: A**
> - **Reasoning:** Today `Code(5) == 5` passes the type checker and then fails in cc. That is the worst diagnostic a toolchain can give, and A moves it to a TypeError that `blink check` and the LSP report at the call site. The `match` help line is a fix-it that compiles on every payload enum today. It also takes away the only ways the layout could change what a program computes.
> - **Concern:** The bad comparison may also hide in generic code (`T == Int` after monomorphization), so the check must run where it can still point at the user's line, not in codegen.
>
> **Q1b: B**
> - **Reasoning:** The help line we agreed on does not name `.code()`, so Q1 compiles and diagnoses correctly without it. If one change carries both, a stdlib API addition gates a type-rule fix. Track the gap between §07 and lib/std/errno.bl as its own ticket.
> - **Concern:** Until it ships, `blink llms` and §07 still tell users and AI authors to call a method that does not exist, so the follow-up needs a priority, not a parking spot.
>
> **Q2: G**
> - **Reasoning:** A guarantee can be tested. We can gate a size assertion in tests/, and hover / `blink query` can say "same size as `Int`" without hedging. Under U the tooling must either say "maybe" or say nothing, and the promise fades the first time someone refactors. The declaration-keyed table is the special case users would hit as "why is my newtype slower than Errno?", and no diagnostic can explain that.
> - **Concern:** The excluded self-containing case (`type T { T(T) }`) needs a defined diagnostic or a defined fallback lowering. It must not fall silently into some third behavior.
>
> **Q3: A**
> - **Reasoning:** A scalar-only rule leaves `Raw[T]`, `Wrap[T]` and `Code(Errno)` out. That brings back a "which newtypes count" list that users must learn and hover must explain. "Any T, decided after monomorphization" is one predicate, and codegen and the LSP can share it.
> - **Concern:** A generic newtype's size now depends on its instance, so hover on `Wrap[T]` before monomorphization must say "same size as `T`" and not show a fixed number.
>
> **Q4: A**
> - **Reasoning:** §3 names two newtype idioms, and a guarantee that covers only one of them reads like an accident in the docs. Worded as cost (same size, no box, no indirection), it promises nothing a one-member C struct does not already deliver, so the rule costs nothing to keep.
> - **Concern:** Someone may later read "same size as its field" as permission to make the struct assignable to its field, so the spec text must repeat that nominal typing does not change.
>
> **Q5: B**
> - **Reasoning:** No panelist asked for it, the probe did not test it, and nobody has looked at the diagnostic surface or the tests for multi-field single-variant enums. Deciding it here widens a decision about newtypes without the evidence.
> - **Concern:** The follow-up ticket may stall, and `Pair(Int, Int)` keeps a tag word nobody needs, but that only costs speed and is never wrong.

</details>

<details><summary><b>AI/ML</b></summary>

> **AI/ML: Phase C ballot**
>
> **Q1: A**
> - **Reasoning:** Under the current rule, `Code(5) == 5` compares a hidden tag. That is a silent trap, and models trained on Go and C enums will walk into it. A compile-time error, with a help line that compiles as written, turns a wrong-result bug into a one-step fix. It also makes the lowering unobservable, which Q2 depends on.
> - **Concern:** Existing Errno-vs-Int comparisons through a variable can't be found by text search, so the new error may surprise users at upgrade time.
>
> **Q1b: B**
> - **Reasoning:** The agreed help line uses `match` and does not mention `.code()`, so Q1 does not need it to be correct. Bundling the two ties a type-system change to a stdlib addition. The missing `.code()` is already a spec-vs-stdlib bug on its own and should get its own ticket.
> - **Concern:** The follow-up may stall, and §07 keeps promising a method that models will generate and that fails to compile.
>
> **Q2: G**
> - **Reasoning:** A shape rule lets the spec answer "is my newtype zero-cost?" with "yes" in one sentence. Under U, the honest answer for user types is "maybe", and D answers it with a private list nobody can extend. G also turns Errno, MsgFlags and Raw from named exceptions into instances of one rule, so there are fewer special cases to memorize.
> - **Concern:** If the implementation lags the guarantee, the spec will promise a cost that the compiler does not deliver for some generic instances.
>
> **Q3: A**
> - **Reasoning:** A scalars-only list is one more thing to memorize, and it creates an odd cliff: `Code(Int)` is free but `Name(Str)` and `Code(Errno)` are not. "Any T after monomorphization" is the shorter rule and the more predictable one.
> - **Concern:** A generic instance where T is itself a newtype must collapse layer by layer, and a bug there would break the promise without any error.
>
> **Q4: A**
> - **Reasoning:** This is a change from my round-1 position. Q2 is now worded as a cost guarantee, not a C spelling, so including structs costs one clause, and both newtype idioms that §3 names get the same promise. A model asked "should I use `UserId { value: Int }` or `UserId(Int)` for performance?" can then answer "it makes no difference". Without that clause, the spec leaves a question with no basis to answer it, and that pushes users toward the enum form.
> - **Concern:** It adds spec words for a case the C compiler already handles, and someone may read it as a promise about the C spelling.
>
> **Q5: A**
> - **Reasoning:** "A one-variant enum has no tag" is the simplest form of the rule. Putting the cut at "exactly one field" adds a condition to learn and gains nothing. A follow-up ticket would leave `Pair(Int, Int)` unspecified for no reason.
> - **Concern:** It widens this decision past the ticket's scope, so its wording needs care to stay a statement about cost and not about the C layout.

</details>

<details><summary><b>Minimalism</b></summary>

> Minimalism ballot: Q1 A, Q1b B, Q2 U, Q3 B, Q4 B, Q5 B.
>
> **Q1: A.**
> Reasoning: This removes surface. Six operations stop applying to payload enums, and they gave one of three results that disagree with each other: payload, tag, or a C compile error. With this rule, a program cannot observe whether a tag exists, and that is what makes Q2 a small question. Migration cost is close to zero, because the search found no `Errno ==` hits.
> Concern: Somebody may use the rule as a reason to add `@derive(Eq)` or payload `==` shortcuts in the same change. Keep the scope to the rule only.
>
> **Q1b: B.**
> Reasoning: §07 already promises `.code()`, so it adds no new surface, but Q1 does not need it. The help line uses `match`, and `match` works today. Coupling the two changes makes a gate depend on an unrelated stdlib method.
> Concern: The follow-up may sit unbuilt, and the §07 promise stays false longer.
>
> **Q2: U.**
> Reasoning: After Q1, no program can observe layout except through size and speed. A shape guarantee is ABI wording for a language with no enum ABI. G needs Q3, Q4, Q5 and the self-reference exclusion as permanent spec text, and every new payload kind will reopen it. U settles all of these as compiler choices, and Errno keeps its §07 promise by name.
> Concern: If G wins, every later type feature (generic payloads, refinements, `Option` niches) gets a new "does the guarantee still hold" spec question.
>
> **Q3 (if G wins): B.**
> Reasoning: If the spec makes the guarantee, keep it to the smallest set that we can prove holds. Scalars have no interaction with generics, recursion, or monomorphization order. Option A promises a cost result for every `T` after monomorphization, which makes a cost claim depend on how the compiler lowers each instance.
> Concern: Under A, a nested or generic case that cannot lower to a bare payload becomes a spec violation instead of a missed optimization.
>
> **Q4 (if G wins): B.**
> Reasoning: A one-member C struct already has the size of its field and no tag, box or indirection. Writing that down adds words and no zero-cost gain. The §3 idiom works as it is.
> Concern: Under A, the struct rule may later grow field-visibility or opacity text, which this decision does not need.
>
> **Q5: B.**
> Reasoning: This is out of scope for the ticket, and nobody raised a need for it. Specifying layout for multi-field enums is more of the same ABI wording, with no user-observable payoff.
> Concern: If someone decides it now, it sets a precedent that every layout question goes to the panel.

</details>


#### Phase D — Q5 debate

<details><summary><b>Systems</b></summary>

> ## Systems: Phase D, Q5
>
> I am moving to **A**. In Phase C I voted B to keep the decision narrow, but plt's point holds. Once Q1 is in place, a single variant's tag is the constant 0 and no program can read it. Q2 already writes that principle into the spec for one field. Stopping at "exactly one field" leaves one principle split into two cases, and the line falls in a place the hardware does not care about.
>
> My own Phase C reason was the risk of untested seams. Looking at it again, that reason is weaker than I made it sound. Lowering `Pair(Int, Int)` with no tag gives the same shape as `type Pair { a: Int, b: Int }`, and that struct path is the most exercised layout in the compiler. The new seam is the same single-variant detection that Q2 already needs. So A adds almost no new codegen surface beyond what G requires. It just stops that check from also testing `fields == 1`.
>
> To the other ballots:
> - **web (YAGNI):** Your own concern argues for A. Implementers working on the G gate will hit this exact branch, the one-variant check, and either drop the tag or keep it on purpose. Either way someone makes the choice, so the panel should make it, not a patch with no vote behind it.
> - **devops (no evidence):** Fair. I would make A conditional on pin tests in the same change: `List[Pair]` element size, `Result[_, Pair]` and `Option[Pair]` arms, and match binding both fields. That gives the evidence at merge time instead of in a ticket that may stall, which is the risk both you and I named.
> - **min (ABI wording, precedent):** This is not ABI wording. Enums cannot cross FFI, and the Q2 text already says "cost, not a C spelling". A extends that same sentence. It opens no new kind of layout question. Precedent cuts the other way: if we leave this open, the next panel has to decide a sub-case of a rule we already passed.
>
> Proposed wording, kept as a cost statement in aiml's spirit: "An enum with exactly one variant stores no tag word. Its size is that of its fields: with one field, the size of that field (Q2); with more, the size of a struct of those fields. No box, no indirection. This is a cost guarantee, not a C ABI promise."
>
> If the panel stays at B, that costs nothing in soundness, as plt and devops said. The one condition is that the follow-up gets wired as a `br` dependency of the G implementation ticket so it cannot be dropped.
>
> stable, ready to vote

</details>

<details><summary><b>Web/Scripting</b></summary>

> Web on Q5: I stay on B, with one wording change that settles my own Phase C concern.
>
> To plt (one principle, two special cases): with Q1 in place a single variant's tag can't be observed, and I agree. But that is why B costs nothing. The tag on `Pair(Int, Int)` affects only memory size, and nobody has asked for that. The two cases split along a line users already know. Q2/G promises "a newtype costs the same as its field", and Q4 says the same about one-field structs. `Pair` is a record, not a newtype. A Kotlin `value class` must have exactly one property, and Kotlin users don't see the missing multi-field case as an inconsistency.
>
> To aiml (an extra condition to learn): users don't learn layout rules. They learn "wrapping a value is free". The guarantee they rely on is the newtype guarantee, which is what Q2 gives them. "A one-variant enum has no tag" is a fact for the people who build the compiler, not something a JS or Python dev uses. And B doesn't leave `Pair` unspecified in a way anyone can see: Q1 already makes the tag invisible, so leaving it out only changes size.
>
> My Phase C concern was that implementers might drop the tag without a vote. I withdraw that concern, with this wording for B: "Layout of multi-field single-variant enums is not specified. The compiler may omit the tag. Whether the spec guarantees that is a follow-up ticket." The compiler can then do what plt and aiml want, and the spec makes no new promise without evidence. This also answers sys's and devops's worry that the follow-up stalls: if it stalls, nothing is lost.
>
> Min's precedent point is the strongest one here. A wide layout guarantee added as a rider on a newtype ticket invites every layout question to come to the panel.
>
> stable, ready to vote

</details>

<details><summary><b>PLT</b></summary>

> PLT Phase D, Q5: I move from A to B, with one condition on the follow-up's wording.
>
> Why I move: Q1 already settles the semantics of the open question. With Q1 in place, the tag of any single-variant enum is the constant 0, and no well-typed program can observe it. The Q2 text also says layout is a cost matter, not a matter of meaning. So whether `Pair(Int, Int)` stores its tag word is now a pure cost question, and no soundness or compositionality argument remains that makes it urgent. My Phase C argument was about uniformity. That is a real gain, but it is aesthetic, and sys's point outweighs it: a newtype decision with pin tests beats a wider decision whose seams no one has probed. devops is right that nobody tested the multi-field case.
>
> On aiml's "the cut at exactly one field adds a condition to learn": the condition is not arbitrary. With exactly one field, the newtype is isomorphic to its payload (N ≅ P). With n > 1 fields, it is isomorphic only to a product, which still needs a record layout. That is a different statement, and the Q4/Q5 boundary falls where the isomorphism changes shape. The guarantee is principled at "one field", so the cut costs no soundness.
>
> On web's concern (implementers might drop the tag on their own and so decide the question with no vote): under Q1 dropping it is already legal, because the representation is unobservable. That is not a decision about the spec. What stays unvoted is only a *guarantee* of the smaller size. So the condition I ask for:
>
> - The follow-up ticket records that, under Q1, a single-variant enum's tag cannot be observed. The compiler may omit it today, and the open question is only whether the spec *promises* omission.
>
> With that wording, B leaves nothing unspecified in meaning (aiml's worry) and nothing silently decided (web's worry).
>
> stable, ready to vote

</details>

<details><summary><b>DevOps/Tooling</b></summary>

> DevOps Q5 debate: I hold B, and I add one guard to the follow-up ticket.
>
> To plt and aiml: I accept the point about meaning. With Q1 in place, a one-variant tag is the constant 0, it has no semantic content, and A is the more uniform rule. My objection is about evidence, not principle. Under Q2/G every guaranteed case gets a size assertion in tests/ and a hover line ("same size as T"). For A we have none of that: no probe of Pair(Int, Int) on the current compiler, no pin test, no check of how match, Option[Pair] or a nested Pair(Code, Int) lower without the tag. A guarantee with no test is the "may" I argued against in Q2. If we decide it here, we decide it on argument alone.
>
> On aiml's "a condition to learn": users don't learn this cut. Since Q1 makes the layout unobservable, the "exactly one field" boundary shows up only as memory size. Hover can state the rule either way, so the predicate costs tooling nothing.
>
> To web's concern (implementers drop the tag anyway): that is the real risk under B, and the fix is to state it. The record should say: "Until the follow-up decides it, a multi-field single-variant enum keeps its current tagged layout; the one-field gate must not change it." That stops a vote-free decision, and sys's pin-test idea enforces it.
>
> To sys's concern (follow-up dropped): file it with the MVCE (type Pair { Pair(Int, Int) }, a size check, a match, an Option[Pair]) and the argument plt already wrote. Then whoever picks it up gets a short ticket, not one that starts from nothing.
>
> I would move to A only if someone shows the size, match and Option tests already pass for Pair with the tag removed. No one has, so B.
>
> stable, ready to vote

</details>

<details><summary><b>AI/ML</b></summary>

> AI/ML Phase D, Q5: I am moving from A to B, on the condition that the follow-up ticket gets filed.
>
> Why I moved:
> - My argument for A was about learnability: "one variant, no tag" is a shorter rule than "one variant, one field, no tag". I checked that against how people and models actually pick a type for several values. They reach for a struct, not `Pair(Int, Int)`. §3 names a struct as the idiom, and nobody picks a multi-field single-variant enum for speed. So the extra condition in the rule never reaches a real decision. It stays an edge case a model will not hit, and the learnability cost I claimed is close to zero.
> - Q1 already makes the tag unobservable, as plt says. That keeps B sound: leaving `Pair(Int, Int)` with a tag word costs only memory, never a wrong result. devops makes the same point.
> - sys's point decides it for me: a guarantee with no pin tests behind it is a promise the compiler may silently break. For a model, a spec claim that the compiler breaks is worse than a spec that says nothing, because the model will rely on the claim. The one-field case has a probe and tests. The multi-field case has neither.
>
> On web's concern (implementers might drop the tag anyway while they work on the one-field gate): the follow-up ticket should say in its body that the multi-field case stays tagged until a vote, so the implementation does not decide it with no vote.
>
> On min's precedent concern: I do not share it. The follow-up is a layout optimization, and it may never need the panel if it stays unobservable. But that is a question for the follow-up ticket, not this one.
>
> On plt's uniformity argument: it is correct in principle. B costs uniformity and no soundness, and I now judge that cost too small to widen this decision.
>
> stable, ready to vote

</details>

<details><summary><b>Minimalism</b></summary>

> Minimalism, Q5 debate: I stay on B.
>
> **To plt and aiml (uniformity):** I take the point seriously. "A one-variant enum stores no tag" is a shorter rule than "one variant and one field", and minimalism prefers shorter rules. But the comparison is wrong. B adds no rule for multi-field enums, so it is not the longer rule. It is silence. The choice is between one guarantee covering N types and one guarantee covering N+M types. The extra M is new spec surface that nobody asked for, the probe did not test, and no user can observe except through memory size. A shorter sentence that promises more is not subtraction.
>
> **On the "split principle":** this argument only works if we treat layout as a principle the spec owes users. I don't. After Q1, a single variant's tag cannot be observed, as plt says. That is exactly why the compiler may drop it with no vote. A dead tag word in `Pair(Int, Int)` is a missed optimization, not a semantic error, and devops is right that it "costs speed and is never wrong." The implementer can drop it tomorrow under the Q1 unobservability argument, with pin tests, and no spec text is needed for that.
>
> **To web's concern (implementers decide it with no vote):** that is fine by me, and I count it as the intended result. If the tag cannot be observed, removing it is a codegen choice, the same as register allocation. A vote would only be needed if the spec made a promise. Under B it makes none.
>
> **To sys's concern (the follow-up gets dropped):** then make the follow-up a codegen chore, not a type:spec ticket. That keeps it tracked without returning it to the panel. It also answers my own Phase C concern about precedent: not every layout question belongs to the panel.
>
> **Net:** A widens a newtype ticket into a general enum-layout promise, on no evidence, to buy a uniformity that only shows in a rule we don't need to write. B costs nothing in soundness, as plt concedes.
>
> stable, ready to vote

</details>


#### Phase D — Q5 re-vote

Options: **A** (sys wording, pin tests in the same change), **B1** (devops wording: multi-field single-variant enums keep their tag until the follow-up decides), **B2** (web wording with plt's condition: layout not specified, the compiler may omit the tag, the follow-up decides only whether the spec promises it).

Result: **B2 3 (web, plt, min), A 2 (sys, devops), B1 1 (aiml)** — no majority after the one allowed Phase D round.

<details><summary><b>Systems</b></summary>

> Systems final vote on Q5: A.
>
> 1. Vote: A.
>
> 2. Reasoning: Under Q1 no program can read a single variant's tag, and Q2 already promises in the spec that the tag goes away for one field. Stopping at "exactly one field" splits one principle into two cases. That line means nothing to the hardware. Lowering `Pair(Int, Int)` with no tag gives the same shape as a two-field struct, the layout path the compiler exercises most, so A adds almost no codegen surface beyond the single-variant check G already needs. If the vote goes B, I prefer B2 to B1: B1 would make the one-field gate test `fields == 1` on purpose just to keep a tag word nobody can read.
>
> 3. Concern: if A wins without its pin tests (`List[Pair]` element size, `Result[_, Pair]` and `Option[Pair]` arms, match binding both fields) in the same change, a missed seam can silently disagree about the layout, so those tests are a condition of my vote, not an extra.

</details>

<details><summary><b>Web/Scripting</b></summary>

> Web, Q5 final vote: B2.
>
> Reasoning: Under Q1 a single variant's tag can't be observed, so whether `Pair(Int, Int)` stores it is a cost question, not a meaning question. B2 lets the compiler omit the tag today without adding a spec promise that nobody has asked for or tested. B1 locks in a dead tag word as a rule, which is stricter than the facts call for. A adds a layout guarantee for records to a ticket about newtypes. From a user's view, B2 changes nothing they can see, and it leaves the door open.
>
> Concern: under B2 an implementer may omit the tag with no pin tests, so a silent layout bug in `Option[Pair]` or `Result[_, Pair]` could ship. Any change that omits the tag should carry sys's pin tests even before the follow-up decides the guarantee.

</details>

<details><summary><b>PLT</b></summary>

> PLT, Q5 re-vote: B2.
>
> Reasoning: Under Q1, no well-typed program can observe the tag of a single-variant enum, so whether it is stored is a question of cost and not of meaning. B2 records exactly that: omitting the tag is legal today, and the only open question is whether the spec promises omission. B1 is unprincipled in a different way. It freezes "keeps its current tagged layout", which states a requirement about a layout no program can observe, and that contradicts the Q2 ruling that layout is cost and not meaning. A goes beyond the newtype question this ticket asks, and nobody has probed the multi-field case.
>
> Concern: the follow-up may never get an owner, so the cost guarantee for `Pair(Int, Int)` stays unstated with nothing tracking it. Wire it as a br dependency (sys) and attach the MVCE (devops).

</details>

<details><summary><b>DevOps/Tooling</b></summary>

> DevOps Q5 vote: A (sys wording, with sys's pin-test condition).
>
> Reasoning: My B rested on one objection: a layout guarantee with no test behind it. sys's condition removes that. The change can't land without gated tests for List[Pair] element size, the Result and Option arms, and a match binding both fields, so the guarantee and its tests ship together. That is the standard I asked for in Q2. With that condition met, A gives one rule ("one variant, no tag") that codegen, hover and `blink query` can share. B2 is a "may", and I rejected that in Q2. B1 locks a dead tag word in place only to wait for a ticket that would reach the same answer.
>
> Concern: The multi-field part could hold up the one-field G work, which is what fixes the user bug. If the pin tests for Pair turn up a seam, land the one-field gate first and do not ship the Pair half without its tests.

</details>

<details><summary><b>AI/ML</b></summary>

> AI/ML Q5 re-vote: B1
>
> Reasoning: B1 is what I asked for in the debate: the multi-field case keeps its tag until a vote, and the one-field gate must not change it. That gives a model asking "what does Pair(Int, Int) cost?" a definite answer. B2's "may omit" gives "maybe", which is the same weakness that made me leave U in Q2. B1 also ensures the one-field implementation does not decide this question with no vote, which was web's own concern.
>
> Concern: If the follow-up is not wired as a br dependency of the G implementation ticket (sys's point), the dead tag word stays forever with no one tracking it.

</details>

<details><summary><b>Minimalism</b></summary>

> Minimalism, Q5 final vote: B2.
>
> **Reasoning:** B2 says what my debate text said: under Q1 the tag cannot be observed, so the compiler may omit it today, and the spec promises nothing. B1 goes the wrong way. It writes the current tagged layout into the record as a rule, and that is layout text for a property no program can observe, which is the opposite of subtraction. A turns a newtype ticket into a general enum-layout promise with no evidence that anyone needs it.
>
> **Concern:** If A wins, sys's pin tests will lock in a layout promise. Every later enum feature, such as niches or generic payloads, must then keep that promise or come back to the panel.

</details>


#### User rulings (BDFL)

- **Q5:** "sounds a lot like an implementation detail, not a language spec issue." → B2, filed as a codegen chore.
- **Q2–Q4:** "implementation details dont go in spec." Asked whether the rule also covers the voted G guarantee, the user chose: Q1 only in the spec, and strip the layout wording from §07.

## AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: one rule ("tag operations need a fieldless enum") with an example |
| Consistency | Pass: removes the case where `Errno` and a user type of the same shape gave different results |
| Generability | Pass |
| Debuggability | Pass: the error carries a `match` line to paste |
| Token efficiency | Soft fail until `Errno.code()` ships: `match` where §07 promises one method call |

## Final Spec

```blink
type State { Idle, Running, Done }
type Code { Code(Int) }

let s = State.Running
let a = s == 1           // OK: State is fieldless; compares the tag
let n = s.to_int()       // OK

let c = Code(5)
let b = c == 5           // error[TypeError]
                         //   help: match on the payload: match c { Code(n) => n == 5 }
let m = c.to_int()       // error[TypeError]
let ok = match c {
    Code(v) => v == 5
}
```

- Comparison with `Int`, `to_int()` and `from_int()` exist only on fieldless enums. This includes `Errno`.
- The spec states no layout for any enum or newtype. Codegen may lower a single-variant enum without its tag, because no program can observe the tag.
- `Errno.code()` remains promised by §07 and is tracked as a follow-up.
