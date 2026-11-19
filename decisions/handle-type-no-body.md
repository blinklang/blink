[< All Decisions](../DECISIONS.md)

# A Handle Type Has No Body — Design Rationale

**Gap:** §9.1.4 said an `@ffi.opaque` type has "no body: no fields, no variants (a body is rejected)". It did not say what `type T {}` is. The compiler and tests accept `@ffi.opaque(...) type Oh {}`. Elsewhere `type Html {}` is a struct with no fields, and `Html {}` builds one. §4 says "an empty body is no body" for effects only. The spec examples write the bodiless form for `@runtime`, and the E1110 row said "`@runtime` on anything but a fn or a bodiless type".

```blink
@ffi.opaque(header: "stdio.h", name: "FILE")
type A {}

@runtime("blink_x")
pub type B {}
```

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q0 | Must the spec say anything about `type T {}` under `@ffi.opaque` or `@runtime` | Yes | 6-0 (round 1) |
| Q1 | Under `@ffi.opaque` and `@runtime`, what is `type T {}` | `B`: `{}` is a body, and any body is `UnexpectedAnnotation` (E1110): empty `{}`, `{}` that holds only a comment, fields, variants | 5-1 (PLT dissented for `N`) |
| Q2 | Must `@ffi.opaque` match `@runtime` | Yes: one rule for both annotations | 6-0 (round 1) |
| Q3 | The help, and `blink fmt` | The help names the exact fix (`type A`). `blink fmt` does not rewrite the braces. `blink fix` and the language server apply the help: they remove the braces, and they move a comment above the annotation and keep its text | 6-0 (round 1) |

Writer notes:

- The help names the exact fix (`type A`). The primary span is on the `{`. A body that holds only a comment gets the comment moved above the annotation (DevOps, AI/ML, Web/Scripting, Systems).
- A field body gets help that points to `@ffi.struct` for a known C layout (Systems).
- PLT's concern: the spec states as a rule that a handle type has no literal, so `A {}` is refused, and does not rest on today's compiler behavior. The spec shows `A {}` refused.
- A plain `type M {}` is a struct with no fields and does not change. The spec does not decide what a plain bodiless `type T` means.
- Notes for the implementation only (not for the spec): E1110 for an `@ffi.opaque` body, which the compiler accepts today; the machine fix in `blink fix` and the language server from the first day; three test lines in the identity test for `@ffi.opaque` move to the bodiless form.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path in the copy is replaced by `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

- **Systems:**

> # [ticket] — Systems seat (sys), Phase A
>
> ## What the compiler does today (probed with build/blink check, gen of this tree)
>
> | Source | Today |
> |---|---|
> | `@ffi.opaque(...) type A {}` | accepted |
> | `@ffi.opaque(...) type A` | accepted |
> | `@ffi.opaque(...) type A { x: Int }` | **accepted, no error** (spec: "a body is rejected") |
> | `@ffi.opaque(...) type A {}` then `A {}` in `main` | TypeError "cannot construct handle `A` outside the FFI boundary" (good) |
> | `@runtime("blink_x") pub type B {}` | E1110 UnexpectedAnnotation |
> | `@runtime("blink_x") pub type B { x: Int }` | E1110 |
>
> So the two annotations disagree on `{}` today, and `@ffi.opaque` silently takes a field body. The
> field-body case is the real hazard: the author writes `x: Int`, the C side gets `FILE *`, and the
> declared shape is a lie about memory. Whatever the panel picks for `{}`, the field body must error.
>
> ## Q0: Yes
>
> Both annotations lower to one thing: a C pointer `name *` / `blink_x *`, no Blink-side layout.
> Without the annotation, `type T {}` is a zero-field value struct that `T {}` builds. The spelling
> `{}` reads as "has a layout, size zero, constructible"; that is the opposite of a handle. The spec
> must say which reading wins under the two annotations, or two compilers will lower it two ways.
>
> ## Proposal S1 (recommended): an empty body is no body, for both annotations
>
> Reuse the §4 effect rule verbatim in spirit. One rule, one codegen path.
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                                // OK: same type as `type A`; fmt rewrites to `type A`
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                                   // OK: canonical
>
> @runtime("blink_tcp_handle")
> pub type B {}                            // OK: same as `pub type B`; fmt rewrites to `pub type B`
>
> @runtime("blink_tcp_handle")
> pub type B                               // OK: canonical
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     // the C FILE stream; never read from Blink
> }                                        // OK: no body; fmt keeps braces + comment (as §4)
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     fd: Int,                             // ERROR E1110
> }
>
> @runtime("blink_tcp_handle")
> pub type B {
>     fd: Int,                             // ERROR E1110 (today's code, today's position)
> }
> ```
>
> Field body diagnostic (both annotations, primary span on the first field):
>
> ```
> error[E1110]: a handle type has no fields
>   = help: remove the fields; `@ffi.opaque` maps to a C pointer whose layout Blink never sees.
>           For a C record with a known layout, use `@ffi.struct` (§9.1.3)
> ```
>
> (`@runtime` help: "remove the fields; `@runtime` on a type declares a pointer to a runtime C type".)
>
> - Q1: bodiless handle. Q2: bodiless handle; **yes, must match Q1** — same lowering, same
>   inert/flow/construction rules; two answers would mean two code paths in typecheck and layout for
>   one C shape, and the drift we already have between them is the proof.
> - Q3: `{}` is not refused; fmt removes it, so lib/std and tests converge on the bare form with no
>   migration error.
>
> Cost: zero runtime cost either way; the decision is purely front-end. Codegen sees one node kind
> ("handle, no fields"), so layout.bl keeps one branch.
>
> ## Proposal S2 (acceptable): refuse `{}` under both annotations
>
> `type A {}` and `pub type B {}` under either annotation are E1110 with
> `help: write \`type A\` with no braces; a handle has no body`, and `blink fmt` rewrites `{}` to the
> bare form (so fmt alone clears the error). Braces holding only a comment: also E1110, help says move
> the comment above the declaration; fmt does that move.
>
> Tradeoff vs S1: one spelling in the source forever (good for grep, for training data, for an AI
> writer). But it is an error for a purely cosmetic choice, and it breaks the §4 precedent that two
> neighbouring declaration kinds handle `{}` the same way. I rank S1 above S2 because fmt already
> gives the single spelling in practice, and an error that fmt fixes adds a failure mode with no
> semantic content.
>
> ## Not acceptable
>
> Any split answer (`{}` OK under one annotation, error under the other), and any reading where `{}`
> under `@ffi.opaque` makes a zero-field struct (size 0 value) instead of a pointer handle.
>
> ## Cross-language
>
> - C: `struct sqlite3;` (incomplete, pointer-only) vs `struct s {}` (GNU extension, size 0, a value).
>   The brace is the line between "handle" and "value" — exactly the confusion to avoid.
> - Rust: the old `#[repr(C)] struct Foo { _p: [u8; 0] }` idiom needed a private field because an
>   empty struct is constructible; `extern { type Foo; }` exists to drop the braces.
> - Zig: `const FILE = opaque {};` — braces mean opaque, but under a distinct keyword, so no clash.
>   Blink's annotation plays the role of Zig's keyword, which supports S1: the annotation, not the
>   braces, decides the shape.
>
> ## Side finding for the moderator
>
> `@ffi.opaque(...) type A { x: Int }` passes `blink check` today. That is a bug against current spec
> text ("a body is rejected"), independent of this vote; it should be a type:bug ticket.

- **Web/Scripting:**

> # [ticket] — Web/Scripting seat, Phase A
>
> ## What I measured (build/blink, probe dir probe/web/)
>
> | Source | `blink check` today |
> |---|---|
> | `@ffi.opaque(header: "stdio.h", name: "FILE") type A {}` | accepted |
> | `@ffi.opaque(...) type A` | accepted |
> | `@ffi.opaque(...) type A { x: Int, }` | **accepted** (spec says a body is rejected; no error fires) |
> | `@runtime("blink_x") pub type B {}` | E1110 "only allowed on ... a type with no body" |
> | `@runtime("blink_x") pub type B` | accepted past E1110 (E0849 only because probe is not lib/std) |
> | `@runtime("blink_x") pub type B { x: Int, }` | E1110 |
> | plain `type C` (no braces) | a zero-field struct; `C {}` builds it |
> | `blink fmt` on `type A {}` | rewrites to `type A` — for plain types AND `@ffi.opaque` types already |
>
> So the tool already treats `{}` as "no body" in fmt and for plain types, the two annotations disagree with each other, and `@ffi.opaque` with real fields slips through. Three answers for one spelling.
>
> ## Proposal W1 (my pick): "An empty body is no body" for every type declaration
>
> Q0: yes, the spec must say it. Q1/Q2: `{}` is no body, under both annotations, same answer. Q3: `{}` is not refused; fmt removes it.
>
> ```blink
> @ffi.opaque(header: "sqlite3.h", name: "sqlite3")
> pub type A {}                 // OK: same as `type A`. fmt rewrites to `pub type A`
>
> @ffi.opaque(header: "sqlite3.h", name: "sqlite3")
> pub type A                    // OK: canonical
>
> @runtime("blink_x")
> pub type B {}                 // OK in lib/std: same as `pub type B`. fmt rewrites it
>
> @runtime("blink_x")
> pub type B                    // OK in lib/std: canonical
>
> @ffi.opaque(header: "sqlite3.h", name: "sqlite3")
> pub type A2 {
>     db: Int,                  // ERROR E1110: an @ffi.opaque type has no fields
> }
>
> @runtime("blink_y")
> pub type B2 {
>     fd: Int,                  // ERROR E1110: a @runtime type has no fields
> }
>
> @ffi.opaque(header: "sqlite3.h", name: "sqlite3")
> pub type A3 {
>     // the C struct is incomplete; we never read it
> }                             // OK: no body. fmt keeps braces + comment (as for effects)
> ```
>
> Error for a real body (both annotations, one code, E1110, primary span on the first field or variant):
>
> ```
> error[E1110]: `@ffi.opaque` type `A2` cannot have fields
>   = help: a handle has no fields. Remove the body: `pub type A2`
> ```
>
> (`@runtime` says the same with its own name.) No machine fix that deletes fields; a human must decide where the data goes.
>
> Why this is the 90% answer:
> - **One rule, three places.** Effects already have it (§4 rule 4). Plain types already behave that way (`type C` and `type C {}` both give a zero-field struct). fmt already does it. W1 writes down what the tool does and closes the `@runtime` exception. A dev learns "braces with nothing in them mean nothing" once.
> - **Nobody hits a wall over two characters.** A TS/Kotlin dev writes `class Foo {}` / `interface Foo {}` by reflex. Rust devs write `struct Foo {}` and `struct Foo;` both. An error that says "remove `{}`" for something that means the same thing is pure friction and a Stack Overflow question ("why is `{}` an error here but fine on the next line?"). fmt fixing it silently is the Prettier/gofmt contract users already trust.
> - **Matches the code on disk.** lib/std and tests already write `@ffi.opaque(...) type X {}`. Under W1 they stay legal and fmt cleans them up.
> - **It fixes the real bug.** Today a field body under `@ffi.opaque` compiles. W1 makes it E1110 for both annotations, which is what §9.1.4 already promised.
>
> Cost: `@runtime type B {}` turns from error into OK. That relaxes an error, so no migration.
>
> Risk I accept: a reader may see `@ffi.opaque type A {}` and expect `A {}` to build one, as for a plain zero-field type. The existing construction diagnostic catches that. I ask the writer that its help names the source ("get an `A` from an `@ffi` fn that returns it"), but that is not a new rule.
>
> ## Proposal W2 (fallback): refuse `{}` under both annotations
>
> If the panel wants one spelling enforced by `check`, not only by fmt:
>
> ```blink
> @ffi.opaque(header: "sqlite3.h", name: "sqlite3")
> pub type A {}                 // ERROR E1110, machine fix removes `{}`
> ```
>
> ```
> error[E1110]: `@ffi.opaque` type `A` has no body; remove `{}`
>   = help: write `pub type A`
> ```
>
> Comment-only `{ // ... }`: same error, fix moves the comment above the declaration. fmt applies the fix (rewrite to `type A`), so `blink fmt` users never see it.
>
> Tradeoff: stricter, and it keeps "`type T {}` = zero-field struct" true everywhere (no context-dependent meaning). But it breaks the effect parallel, punishes a reflex, and costs a migration of existing `{}` sites. I vote W1 over W2; either is better than today's split.
>
> **Hard requirement for both: Q2 matches Q1.** `@runtime` handles were defined as "flows and is inert as an `@ffi.opaque` handle is". Two handle kinds that disagree on braces is the worst outcome.
>
> ## Cross-language note
>
> TS/JS: `{}` = empty, never an error. Kotlin: `class Foo` and `class Foo {}` are the same; IntelliJ greys the braces as redundant (exactly W1 + fmt). Rust: `struct Foo;` vs `struct Foo {}` are distinct (unit vs braced), a known paper cut Blink should not copy. Go: `struct{}` has one spelling, gofmt does not care.
>
> ## Side finding (not this ticket)
>
> `blink fmt` rewrites the literal `A {}` to `A {  }` (two spaces). Looks like a formatter bug; worth a ticket.

- **PLT:**

> # [ticket] — PLT seat, Phase A
>
> ## What gen1 (build/blink) does today (probes in probe/plt/)
>
> | Source | Today |
> |---|---|
> | `@ffi.opaque(...) type A {}` then `A {}` in `main` | **compiles**. The literal builds a handle. |
> | `@ffi.opaque(...) type A2` then `A2 {}` | `cannot construct handle A2 outside the FFI boundary` |
> | `@ffi.opaque(...) type A3 { x: Int }` | **compiles**. The spec says "a body is rejected". |
> | `@runtime("blink_x") pub type B {}` | E1110 |
> | `@runtime("blink_y") pub type B2 { x: Int }` | E1110 |
> | unannotated `type T`, then `T {}` | compiles (a zero-field struct) |
>
> So the question is not only about spelling. Today `{}` under `@ffi.opaque` turns the handle into a
> zero-field struct, and that struct has an introduction form, `A {}`. That breaks *Construction —
> sealed to the FFI boundary*: ordinary code can mint a `FILE*` handle. This is a soundness hole,
> whatever the panel decides. The two annotations also disagree on the same text.
>
> ## Proposal PLT-1 (recommended): `{}` is a body. A handle type has none. One rule for both annotations.
>
> Typing view. A handle type is an abstract type: a name with no introduction form in Blink code
> (its values come only from the boundary) and no elimination form (inert). `type T {}` everywhere
> else in Blink is the zero-field product, whose introduction form is `T {}`. These are two different
> types. If `{}` meant "abstract" under an annotation and "product" otherwise, the meaning of the
> body would depend on the annotation. The annotation would then not apply to a declaration; it
> would rewrite it. A declaration's meaning should compose: annotation applied to the meaning of the
> declaration as written. So the parser decides body/no body (it already does), and each handle
> annotation requires "no body".
>
> Behavior:
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                          // OK: a handle
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // error E1110
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     // a C FILE handle
> }                               // error E1110 (a comment does not remove the body)
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A { fd: Int }              // error E1110
>
> @runtime("blink_x")
> pub type B                      // OK: a handle
>
> @runtime("blink_x")
> pub type B {}                   // error E1110 (as today)
>
> @runtime("blink_x")
> pub type B { fd: Int }          // error E1110 (as today)
> ```
>
> - Code: E1110 `UnexpectedAnnotation` for both. Its catalog row grows: "`@ffi.opaque` or `@runtime`
>   on a type with a body, an empty body `{}` included". No new code. The current text of §9.1.4
>   ("a body is rejected") gets its code.
> - Primary span: the `{`. Help: "a handle type has no body; remove the braces: write `type A`".
>   When the braces hold a comment, the help says to move the comment above the annotation.
> - `blink fix` applies the help (removes `{}`, moves a comment out). `blink fmt` does **not**
>   rewrite: fmt keeps meaning, and here `{}` has a meaning (a body) that the rule refuses. The
>   §4 effect rewrite is different, because for effects `{}` and no braces mean the same thing.
> - Q2 = Q1 by design. §9.1.4 already says the `@runtime` handle "flows and is inert as an
>   `@ffi.opaque` handle is" and has the same construction rule. Two annotations that make the same
>   type-theoretic object must take the same declaration form. Different body rules for them would
>   be an accident of history (E1110 came first for `@runtime`).
> - Migration: lib/std and tests that write `@ffi.opaque(...) type X {}` drop the braces (pre-1.0,
>   CHANGELOG line). The test at test_typecheck_ffi_opaque_identity_is_the_declaration_not_the_spelling.bl
>   changes its fixtures.
> - Independent of the vote: `A {}` must not build an `@ffi.opaque` handle, and a field body under
>   `@ffi.opaque` must be an error. Both are bugs against today's §9.1.4.
>
> ## Proposal PLT-2 (second choice): "an empty body is no body" for handle types
>
> Under `@ffi.opaque` and `@runtime`, `{}` (or `{}` with only a comment) means no body. A field in the
> braces is E1110. `blink fmt` rewrites `type A {}` to `type A` under these annotations, and keeps
> braces that hold a comment, as §4 does. Same answer under both annotations.
>
> Tradeoff: it is the friendlier rule and matches §4 in shape. But in §4 the two spellings mean the
> same thing everywhere; for types they do not (`type Meters {}` builds with `Meters {}`). PLT-2 makes
> the denotation of `{}` depend on the annotation above it, and fmt must read the annotation to
> format the body. It also keeps the exact shape that produced today's hole. If the panel picks
> PLT-2, the spec must state that the annotation removes the introduction form, and a test must prove
> `A {}` is refused.
>
> ## Q0
>
> Yes. The spec says "no body" and the compiler reads `{}` as a body in one place and not in the
> other. Silence is how the hole got in.
>
> ## Follow-up (not for this vote)
>
> Unannotated `type T` (no braces) compiles today as a zero-field struct. Under PLT-1, a bare `type T`
> is the abstract form, so with no handle annotation it has no meaning. The spec does not say what it
> is. That needs its own ticket (error, or same as `type T {}`).
>
> ## Cross-language
>
> - OCaml: `type t` is abstract; a record needs at least one field. The two forms never mix.
> - Haskell: `data T` (no constructors, EmptyDataDecls) is a different type from `data T = T`.
> - Rust: `extern { type T; }` (extern types) uses the bodiless form; `struct T {}` is a unit-like
>   struct that you can build. Rust never takes `{}` to mean "foreign, opaque".
> All three keep "no body" and "empty body" apart. PLT-1 does the same.

- **DevOps:**

> # [ticket] — devops seat, Phase A
>
> ## What the tools do today (probed with build/blink 0.60.0-dev+20261119010138)
>
> | Input | `blink check` today |
> |---|---|
> | `@ffi.opaque(...) type A {}` | ok |
> | `@ffi.opaque(...) type A` | ok |
> | `@ffi.opaque(...) type A { x: Int }` + `a.x` | **ok** (spec says a body is rejected; the field is even readable) |
> | `@runtime("blink_x") pub type B {}` | E1110 "only allowed on ... a type with no body" |
> | `@runtime("blink_x") pub type B { x: Int }` | E1110 |
>
> `blink fmt` today, on plain types (no annotation):
> - `type M {}` becomes `type M`. The program `type M {}` + `let _m = M {}` runs; after fmt it ICEs (`unwrap called on None`, src/parser.bl:1424). **fmt changes meaning and breaks a working program.**
> - `type N {\n    // c\n}` becomes `type N`. **fmt deletes the comment.**
>
> So the two annotations answer Q1/Q2 in opposite ways now, and fmt already applies the §4 effect rule to types, where it is wrong. Whatever the panel picks, these three are bugs to file.
>
> ## Proposal A (my pick): an empty body is no body, for a handle type only
>
> Q0: yes. Q1: bodiless. Q2: bodiless; it must match Q1.
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // ok: same as `type A`; fmt rewrites to `type A`
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                          // ok, canonical form
>
> @runtime("blink_x")
> pub type B {}                   // ok: same as `pub type B`; fmt rewrites to `pub type B`
>
> @runtime("blink_x")
> pub type B                      // ok, canonical form
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A3 {                       // ERROR E1110
>     x: Int,
> }
>
> @runtime("blink_x")
> pub type B3 {                   // ERROR E1110 (as today)
>     x: Int,
> }
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A4 {
>     // the stream handle of libc
> }                               // ok: bodiless; fmt keeps braces + comment
>
> type M {}                       // unchanged: zero-field struct; `M {}` builds one; fmt keeps the braces
> ```
>
> Field body error (one code for both annotations, primary span on the first field, secondary on the annotation):
>
> ```
> error[E1110]: `@ffi.opaque` is only allowed on a type with no body
>  --> app/io.bl:6:5
>   |
> 5 | @ffi.opaque(header: "stdio.h", name: "FILE")
>   | -------------------------------------------- the handle type is declared here
> 6 |     x: Int,
>   |     ^^^^^^ a handle type has no fields
>   |
>   = help: remove the body; to keep data next to the handle, declare
>           `type Stream { file: A, x: Int }`
> ```
>
> The `@runtime` message keeps its text, gains the field span and the same help.
>
> Q3: `{}` is not refused, so no help applies. `blink fmt` rewrites an empty `{}` away only on a type that carries `@ffi.opaque` or `@runtime`, and keeps braces that hold a comment — the same rule as §4 effects. It never rewrites `type M {}` without one of those annotations, and never deletes a comment.
>
> Tradeoffs (tooling view):
> - **No new code, no error users can hit by habit.** A user who writes `{}` from the struct habit gets a working program and fmt makes it canonical. Go's gofmt works this way: the tool, not the compiler, picks the one spelling.
> - **fmt rewrite is safe only because the meaning is the same.** Under the annotation there is no literal, so `{}` and no braces cannot differ. Without the annotation they differ (`M {}` is a literal), so the rule must be keyed on the annotation. The LSP "format document" and fmt share this one check.
> - **Existing code compiles.** tests and lib/std that write `type X {}` under `@ffi.opaque` keep passing; fmt migrates them.
> - **Cost:** two spellings in unformatted source; a reader of raw source sees `type A {}` and may think "zero-field struct". fmt removes that in one pass, and `blink fmt --check` in CI stops it landing.
> - Matching Q1 and Q2 is not optional: a rule keyed on which handle annotation is present gives the LSP two code paths and gives users a surprise when lib/std code moves from one to the other.
>
> ## Proposal B (alternative): refuse `{}` under both, with a fix
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // ERROR E1110
> @runtime("blink_x")
> pub type B {}                   // ERROR E1110 (as today)
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A4 { /* comment */ }       // ERROR E1110: a comment is not a fix for braces
> ```
>
> ```
> error[E1110]: `@ffi.opaque` is only allowed on a type with no body
>   |
> 6 | type A {}
>   |        ^^ remove the braces
>   = help: write `type A`; a handle type has no body
> ```
>
> The LSP offers "remove the braces" as a machine-applicable fix (`blink fix` applies it; a comment inside moves above the `type` line). `blink fmt` does not rewrite it: fmt formats valid code; it does not fix errors.
>
> Tradeoffs: one spelling in all source, and raw source never looks like a zero-field struct. Cost: a new error users hit by habit, with a different answer from §4 effects for the same `{}` shape. Two rules for "empty braces" in one language is a thing users and LLMs must learn.
>
> ## Cross-language
>
> - Go: gofmt picks the canonical spelling; the compiler accepts both.
> - Rust: `struct A;` and `struct A {}` both compile and mean different things; rustfmt never rewrites one to the other. This is the trap fmt falls into today on plain `type M {}`.
> - Swift / Kotlin: `class A {}` and `class A` are the same; no tool error.
>
> ## Recommendation
>
> Proposal A. It reuses the §4 rule, adds no code, and fixes the real hazard here, which is fmt today, not the compiler. File three bugs regardless of outcome: fmt rewrites `type M {}` to `type M` (meaning change + ICE), fmt deletes a comment in empty type braces, and `@ffi.opaque` accepts a field body.

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase A
>
> ## What the compiler does today (probed with build/blink check)
>
> | Source | Today |
> |---|---|
> | `@ffi.opaque(...) type A {}` | ok |
> | `@ffi.opaque(...) type A { x: Int, }` | **ok** (spec says a body is rejected: a latent bug) |
> | `@ffi.opaque(...) type A { // handle }` | ok |
> | `@runtime("blink_x") pub type B {}` | E1110 "a type with no body" |
> | `@runtime("blink_x") pub type B { x: Int, }` | E1110 |
>
> So today the two annotations give opposite answers for `{}`, and `@ffi.opaque` accepts real fields. lib/std writes the bare form everywhere; only tests write `{}`. Probes: [scratch path].
>
> ## Q0: yes
>
> The spec must say it. The model reads "no body" and must guess whether `{}` is a body. Today two handle annotations answer that guess in opposite ways. A generator learns from examples, and the corpus (tests) has `type Oh {}` under `@ffi.opaque`. That is a trap that a model will copy to `@runtime` and hit E1110.
>
> ## Proposal P1 (recommended): an empty body is no body, the same under both annotations
>
> The §4 effect rule, extended to a handle type. One rule, two places, no new decision point.
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // ok: the same as `type A`; fmt rewrites to `type A`
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                          // ok: canonical form
>
> @runtime("blink_x")
> pub type B {}                   // ok (lib/std only): the same as `pub type B`; fmt rewrites
>
> @runtime("blink_x")
> pub type B                      // ok: canonical form
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     // a FILE* from libc
> }                               // ok: no body; fmt keeps the braces and the comment
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     fd: Int,                    // ERROR E1110
> }
>
> @runtime("blink_x")
> pub type B {
>     fd: Int,                    // ERROR E1110
> }
> ```
>
> - A field or a variant in the braces is `UnexpectedAnnotation` (E1110) under **both** annotations, with one help text for both:
>   `help: a handle type has no fields; write `type A` with no braces, or remove @ffi.opaque to declare a struct`
>   (for `@runtime`, the same with the annotation name changed). Primary span on the first field. Same code for both, so a model learns one fix.
> - `A {}` as a literal stays a construction error under both, as today (the annotation, not the braces, seals construction).
> - `blink fmt` rewrites `{}` (empty, or whitespace only) to no braces on an annotated handle type, and keeps braces that hold a comment, exactly as for an effect.
> - Q2: the answer must match Q1. Two handle kinds that differ only in who owns the C type must not differ in syntax.
>
> ### Tradeoffs (generation, learning, tokens)
>
> - **Fewer red builds.** Models from Rust (`struct A {}`), Go (`type A struct{}`) and Swift write empty braces by habit. P1 accepts that habit, and fmt turns it into one canonical form, so the corpus and future training data converge on `type A`.
> - **One rule to learn.** "Empty braces are no body" already holds for effects. P1 makes it hold for every declaration where a body is not allowed. A model that knows the effect rule gets this one free.
> - **Cost:** `{}` means a zero-field struct on a plain `type`, and no body on an annotated one. That is a real context switch. I accept it: under both readings the type has zero fields, and the literal `A {}` is refused only because the annotation seals construction. A model cannot write a program whose behaviour changes with the reading.
> - **Fixes the latent bug:** a field under `@ffi.opaque` becomes an error, which today it is not.
>
> ## Proposal P2 (alternative): `{}` is a body, refused under both
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // ERROR E1110
> @runtime("blink_x")
> pub type B {}                   // ERROR E1110
> ```
>
> Help: `write `type A` with no braces: a handle type has no body`. A comment-only `{}` is also E1110. `blink fmt` does not rewrite it (fmt does not fix errors).
>
> - For: exactly one spelling, and the zero-field-struct meaning of `{}` stays true everywhere.
> - Against: each generator that writes `{}` pays one red build and one repair turn. It also makes handles disagree with the effect rule, so a model must learn two rules for "empty braces". More decision points, not fewer.
>
> ## Rejected: do nothing
>
> Today the two annotations disagree and `@ffi.opaque` accepts fields. Silence keeps both.
>
> ## Cross-language
>
> Rust: `struct A;` and `struct A {}` are both legal and mean the same (unit vs empty braced struct differ only in construction syntax). Swift/Kotlin accept `{}` on any class body. Go needs `struct{}`. No mainstream language refuses empty braces where "no members" is the meaning; P1 matches what models already expect.

- **Minimalism:**

> # [ticket] — Minimalism seat (min), Phase A
>
> ## Probe facts (build/blink, today)
>
> | Source | Result today |
> |---|---|
> | `@ffi.opaque(...) type A {}` | ok (handle; `A {}` gets "cannot construct handle") |
> | `@ffi.opaque(...) type A` | ok |
> | `@ffi.opaque(...) type A { x: Int }` | **ok — spec says "a body is rejected"; bug** |
> | `@runtime("blink_x") pub type B {}` | E1110 |
> | `@runtime("blink_y") pub type B { x: Int }` | E1110 |
> | `type T` (no annotation) | ok, silently (out of scope; noted) |
>
> So today the two annotations disagree on `{}`, and `@ffi.opaque` does not enforce its own "no body" rule. lib/std writes every handle without braces already; only 3 test lines use `{}`.
>
> ## Proposal M1 (recommended): `{}` is a body. A handle has none. One rule, both annotations.
>
> Q0: yes, but only one clause: "a handle type is written with no braces; empty braces are a body." No new concept, no new code.
> Q1: body → E1110 (as today).
> Q2: body → E1110 (same code, same help). Must match Q1: the spec already says the two flow, mint and stay inert by the same rules. Two spellings of one concept is surface we pay for twice.
> Q3: help says remove the braces. `blink fmt` does nothing: fmt never turns an error into valid code. The diagnostic carries a machine fix (LSP quick-fix / `blink fix`).
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                                  // ok
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                               // ERROR E1110
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A { fd: Int }                      // ERROR E1110 (today: wrongly accepted)
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     // a C FILE*
> }                                       // ERROR E1110; the comment is not special
>
> @runtime("blink_x")
> pub type B                              // ok
>
> @runtime("blink_x")
> pub type B {}                           // ERROR E1110 (unchanged)
>
> @runtime("blink_x")
> pub type B { n: Int }                   // ERROR E1110 (unchanged)
>
> @runtime("blink_x")
> pub type B {
>     // owned by the runtime
> }                                       // ERROR E1110
> ```
>
> ```
> error[E1110]: `@ffi.opaque` is only allowed on a type with no body
>  --> app/io.bl:2:8
>   |
> 2 | type A {}
>   |        ^^ a handle type has no body, not even an empty one
>   |
>   = help: remove the braces: `type A`
> ```
>
> Same text with `@runtime` in place of `@ffi.opaque`. A comment in the braces moves above the declaration.
>
> Why this is the minimal answer:
> - **Zero new meaning.** `type T {}` already means "struct with zero fields" in §3 and §3b, and `T {}` builds one. Reading the same braces as "no body" only under two annotations makes `{}` context-dependent: a reader must check the annotation to know whether `A {}` is a literal or an error. M1 keeps one reading of the token pair everywhere in type declarations.
> - **The annotation changes no syntax.** It only restricts. That is easier to teach and to state in the grammar than "annotation X changes what `{}` parses as".
> - **No fmt rule.** The effect rule ("empty body is no body", 04:5140) exists because for an effect `{}` has no other meaning. For a type it has one. Copying the effect rule here would import a rule whose reason does not hold.
> - **Cost is tiny:** 3 test lines change; lib/std already conforms.
>
> Tradeoff: a user who writes `type A {}` out of habit gets an error, not silent acceptance. The help and the quick-fix make that a one-keystroke repair. An error that teaches the one form beats two accepted forms that every reader, LLM and formatter must know are equal (AI/LLM codegen copies whatever forms exist; one form gives one pattern).
>
> ## Proposal M2 (fallback): equate `{}` with no body for handles, as effects do
>
> `type A {}` and `type A` mean the same under both annotations; `blink fmt` removes the braces (keeps them when they hold a comment). A field body is E1110 under both.
>
> I vote against M2: it adds a fmt rewrite, a comment exception, and a second reading of `{}` — three rules to save one keystroke. Its one merit is symmetry with effects; that symmetry is shallow, because effect `{}` is not overloaded.
>
> ## Rejected: do nothing
>
> Not possible here: the two annotations disagree today, and `@ffi.opaque` accepts a field body against the spec. Something must change; M1 changes the least.
>
> ## Bugs for the lead (not panel questions)
>
> 1. `@ffi.opaque(...) type A { x: Int }` passes `blink check`; §9.1.4 says a body is rejected. A conformance bug whatever the panel picks.
> 2. Bare `type T` with no annotation passes silently. What a bodiless unannotated type means is not stated in §3 that I found; a friction ticket, not this panel.
>
> ## Cross-language
>
> - Rust `extern { type Foo; }` (and `struct Foo;` vs `struct Foo {}`): the semicolon form is the opaque/unit form; Rust does not let annotations re-read braces.
> - Zig `opaque {}` is its own keyword, not a struct with an attribute.
> - C: `struct sqlite3;` (incomplete) vs `struct s {}` (a GNU extension, complete, size 0) are different things. Blink's `type A` vs `type A {}` mirrors C exactly under M1.

### Phase B — Debate (round 1)

All six seats ended round 1 stable. Systems, Web/Scripting, DevOps and AI/ML moved from `N` to `B`; PLT moved from `B` to `N`. All six stated that Q0 is yes, that Q2 matches Q1, that a field or variant body is E1110 under both annotations, and that under `B` `blink fmt` does not rewrite `{}`.

- **Systems:**

> # [ticket] — sys, Phase B round 1
>
> ## Position: B first, N second. I changed my first choice from N (S1) to B.
>
> What changed my mind: the facts the moderator surfaced, and my own Phase A cross-language note.
>
> - Fact 2: plain `type M {}` and `type M` already lower differently. `M {}` runs on the first and
>   hits an ICE on the second. So in Blink today, braces carry a code-generation meaning: `{}` is a
>   value struct with a layout and an introduction form. Under N, the annotation must turn that
>   off. The C shape of `{}` then depends on an annotation one line up. Under B, the parser's body
>   or no-body flag alone says "value" or "pointer", and the annotation only restricts. That is the
>   more predictable path from source to C, and layout.bl keeps one test, not two.
> - My own Phase A note said it: in C, `struct sqlite3;` vs `struct s {}` is the line between
>   handle and value. Rust (`extern type` vs `struct T {}`) and OCaml (abstract `type t`) keep
>   the two apart too. min and plt ran that argument to its end, and I agree with them.
> - Fact 3: fmt already applies the effect rule to plain types and breaks programs. An
>   annotation-keyed fmt rewrite under N is safe, but it is one more context check in fmt and the
>   LSP. The bug that exists today came from exactly that shape.
>
> The cost of B is one error that people hit out of habit. Handle types are rare: FFI authors write
> them, and only lib/std writes `@runtime`. lib/std already uses the bare form, and only about 3 test
> lines change. A machine fix makes the repair one keystroke. I accept that cost.
>
> ## Variation under B: does `blink fmt` rewrite `{}`?
>
> **No**, I withdraw that part of S2. fmt formats valid code and keeps its meaning. `{}` under these
> annotations is an E1110, and only the annotation makes it one, so a syntax-only formatter would
> need semantic context to know. The fix belongs to `blink fix` and the LSP quick fix: remove `{}`, and
> move a comment that sits inside the braces above the annotation. A comment-only `{}` is also E1110
> (min, plt).
>
> ## Variation under N (if N wins)
>
> The fmt rewrite applies only to a type that carries `@ffi.opaque` or `@runtime` (devops). web's
> "for every type declaration" rests on "plain `type C` and `type C {}` are the same", and Fact 2
> refutes that. A blanket rule would make the fmt bug in Fact 3 permanent.
>
> ## Other points
>
> - Fact 1: plt's "`A {}` compiles" was wrong. The construction seal holds today under both
>   readings. So the case for B is about clarity and lowering, not a soundness hole.
> - Independent of the vote: a field body under `@ffi.opaque` must be E1110 (all seats agree), and
>   the bugs in Facts 2 and 3 need tickets.
> - Q2 = Q1: unchanged, required.
>
> STABLE

- **Web/Scripting:**

> # [ticket] — Web seat, Phase B round 1
>
> ## Position: I change from N to B
>
> B: `{}` is a body; under `@ffi.opaque` and `@runtime` it is E1110. A comment inside the braces does not change that. On B's fmt question: **fmt does not rewrite**. The fix goes through `blink fix` and the LSP quick-fix (plt, min, devops, aiml).
>
> On N's fmt-scope question, if N wins: the rewrite covers the two annotations only. I withdraw my "every type declaration" scope (see fact 2).
>
> ## Why I changed
>
> 1. **Fact 2 removes my main argument.** I said plain `type C` and `type C {}` are already the same thing. They are not: `type M {}` then `M {}` runs, but `type M` then `M {}` ICEs at build. So no general rule that "empty braces mean nothing" exists for types. The only precedent is effects, and min is right that effect `{}` has no other meaning. Type `{}` does: it means a zero-field struct that `T {}` builds. N would give the same two characters two meanings, and the annotation above them would decide which. That causes Stack Overflow questions ("why does `A {}` build `Meters` but not `A`?"), not the B error.
>
> 2. **The audience is small and expert.** Only lib/std writes `@runtime`. Only an FFI binding author writes `@ffi.opaque`. Neither is the 90% case. A one-line error with a quick-fix costs this reader five seconds and teaches the one form. My "two characters cause friction" argument is for beginners, and beginners do not write these declarations.
>
> 3. **One form helps tools and LLMs** (aiml/min). lib/std already writes the bare form, and only 3 test lines change.
>
> ## On fmt under B
>
> I said in W2 that fmt applies the fix. I drop that. Prettier and gofmt do not turn code that fails to compile into code that compiles, and users do not expect them to. `blink fix` / the LSP quick-fix is where users look for that repair. The help text must name the fix: "remove the braces: `type A`". When the braces hold a comment, the fix moves the comment above the annotation.
>
> ## On the other facts
>
> - Fact 1: plt's "soundness hole" did not reproduce (`A {}` gets "cannot construct handle"). So B is not needed for soundness. I take it on clarity alone.
> - My fmt finding (`A {}` → `A {  }`), devops's fmt comment deletion and the ICE on plain `type M` → separate bug tickets. They are not votes.
> - Writer note kept: the construction error's help names where a value comes from ("get an `A` from an `@ffi` fn that returns it").
>
> STABLE

- **PLT:**

> # [ticket] — PLT seat, Phase B round 1
>
> ## Position: I change to N
>
> Moderator fact 1 is right and my Phase A table was wrong. I re-ran probe/plt/a.bl:
> `A {}` on `@ffi.opaque(...) type A {}` gives `cannot construct handle A outside the FFI boundary`.
> I read truncated output (`head -30` cut the error). There is no soundness hole. My main argument for
> B rested on it, so I withdraw that argument.
>
> What is left of my B case is "`{}` must mean the same thing everywhere". aiml's point answers it, and
> the compiler already works that way. A typing reading of N that composes:
>
> - The annotation is a seal on a declaration with zero fields. It (1) requires that the field set is
>   empty, and (2) removes the introduction form (no literal) and keeps no elimination form (inert).
> - `type A` and `type A {}` both declare the empty field set. The annotation applies to that
>   meaning, and the result is one abstract type. The meaning of `{}` does not depend on the
>   annotation; the annotation acts after it.
> - A plain `type M {}` is the same empty field set without the seal, so `M {}` builds one.
>
> That is the OCaml shape too: `type t = private ...` or a signature seal acts on a declared type and
> removes construction; the declaration is not read in a new way. So N is sound and compositional,
> and it keeps the §4 parallel. B costs a new error for two characters that, under the seal, cannot
> change any program. That is not worth it.
>
> ## Variations
>
> - N, scope of the fmt rewrite: **annotated handle types only** (devops, sys, aiml). Not web's
>   "every type declaration". For a plain type, `type M` and `type M {}` differ today (fact 2: the
>   bare form ICEs at build), and the spec says nothing about a plain bodiless `type M` (fact 4). The
>   fmt rewrite is safe only where the two spellings are proven equal, and that is under the seal.
>   The plain-type question goes to its own ticket.
> - N, braces that hold only a comment: fmt keeps them, as §4 does.
> - B, does fmt rewrite: no (moot for me now, but fmt must not turn an error into valid code).
>
> ## Conditions I attach to N (writer notes, not new options)
>
> 1. The spec states that the annotation removes the introduction form for both spellings, so the
>    rule does not rest on today's compiler behavior.
> 2. A test proves `A {}` is refused for `type A {}` and for `type A`, under both annotations
>    (for `@runtime`, the `B {}` refusal is in a lib/std-scoped test).
> 3. A field or variant body under either annotation is E1110 (common ground).
>
> STABLE

- **DevOps:**

> # [ticket] — devops seat, Phase B round 1
>
> ## Position: I change from N to B. fmt does not rewrite.
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A                          // ok
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {}                       // ERROR E1110, span on `{}`; quick-fix "remove the braces"
>
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type A {
>     // a C FILE*
> }                               // ERROR E1110; the quick-fix moves the comment above the annotation
>
> @runtime("blink_x")
> pub type B {}                   // ERROR E1110 (as today)
>
> type M {}                       // zero-field struct; fmt leaves it alone
> ```
>
> ## Why I changed
>
> My Phase A argument was "fmt may rewrite `{}` away because under the annotation it means the same". PLT's point breaks that. For a type, `{}` already has a meaning: the zero-field struct, which `M {}` builds. So N needs the annotation to change what the braces mean. For tooling, that means:
>
> - **fmt must read annotations to format a body.** Today fmt is syntactic. N adds the first fmt rule that looks at an annotation's name, and every new handle annotation must be added to that list. B adds no fmt rule.
> - **My own probe is the case against N.** Today's fmt already applies the effect rule to types. It turns a working `type M {}` + `M {}` program into an ICE, and deletes a comment. That is the bug class N invites: a formatter that drops braces when it decides they are empty. Under B, the rule for fmt is simple: never remove type braces.
> - **PLT's fact 1 hole** (`A {}` under `@ffi.opaque` built a handle in plt's run; the moderator re-run says it is refused now) came from the `{}` shape. Under B, the shape cannot reach typecheck.
> - **The error costs one keystroke.** A machine-applicable fix in the LSP and `blink fix` repairs it. An LLM or a user sees one form in all source.
>
> ## Flagged variations
>
> - **Under B, does fmt rewrite?** No (with plt, min, aiml). fmt formats valid code; it does not fix errors (gofmt, rustfmt do the same). sys S2 and web W2 want fmt to clear the error. That puts annotation knowledge into fmt again, the cost I now reject. `blink fix` is the right tool for this.
> - **Under N, the scope of the rewrite** (if N wins): annotated handle types only. web W1's "for every type declaration" is refuted by moderator fact 2: plain `type M` and `type M {}` differ at build today. A fmt rewrite there changes behavior. I would vote against N-with-W1-scope in any case.
>
> ## To the facts
>
> - Fact 3 (fmt rewrites plain `type M {}`, deletes a comment, `A {}` to `A {  }`): bugs, whatever the vote.
> - Fact 4 (meaning of plain bodiless `type T`): agree it is a separate ticket. Under B it becomes more pressing, because `type T` then reads as "abstract" by its form.
>
> ## Writer note
>
> E1110 help when the braces hold a comment: "remove the braces; move the comment above the annotation". The fix must keep the comment text.
>
> STABLE

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase B round 1
>
> ## Position: B (changed from N)
>
> `{}` is a body. Under `@ffi.opaque` and under `@runtime`, any body (`{}`, comment-only `{}`, fields) is E1110, with one help text: "a handle type has no body; remove the braces: `type A`". A comment-only body: the help (and the fix) moves the comment above the annotation.
>
> **B variation (fmt):** fmt does **not** rewrite. The machine fix lives in `blink fix` / the LSP quick-fix. Agree with plt, min, devops.
>
> **N variation (if N wins):** fmt rewrites `{}` only on a type with `@ffi.opaque` or `@runtime`, never on a plain `type M {}` (devops' scope). Fact 2 settles this: plain `type M {}` and `type M` differ at build today, so web's "plain types already behave that way" is wrong.
>
> ## Why I changed
>
> My Phase A case for N was "fewer red builds when a model writes `{}` by habit". I now count decision points instead of first-try failures, and B wins:
>
> - **N adds three rules for a model to carry:** (1) the annotation changes what `{}` means; (2) fmt removes `{}` only under two annotations; (3) a comment keeps the braces. Each is a fact a model must get from the spec, and each varies by context. B adds one: "a handle type has no braces".
> - **min's point on corpora is my domain:** a model copies whatever forms exist in the training text. Under N, unformatted code keeps two spellings in the wild forever; fmt is not run on every snippet that reaches a corpus. Under B, every program that compiles has one spelling. lib/std already writes the bare form everywhere; only test fixtures use `{}`.
> - **The cost of B is one cheap repair.** The error names the exact fix, and `blink fix` applies it. One repair turn with an exact help text is the best kind of error for a generator: deterministic, local, no reasoning needed.
> - **plt's composition argument helps learnability too.** "The annotation restricts, it never re-reads syntax" is a rule a model can apply to any future annotation without a new spec lookup. N sets a precedent that an annotation can change parsing meaning.
> - **Effect parallel is shallow** (min): effect `{}` has no second meaning; type `{}` has one (`Meters {}` builds a struct). So "same rule as effects" was the wrong analogy in my P1.
>
> ## On the facts
>
> - Fact 1 (plt's "A {} compiles" is wrong): noted; it removes plt's soundness-hole argument, but not the composition argument, which I rely on.
> - Fact 3 (fmt today rewrites plain `type M {}` and drops comments): under B those are plain fmt bugs with a clear fix (fmt must not touch type braces). Under N, fmt would need an annotation-aware rule there, which is the kind of context switch I now want to avoid.
> - All seats agree a field body under `@ffi.opaque` is E1110 and Q2 = Q1. So do I.
>
> STABLE

- **Minimalism:**

> # [ticket] — min, Phase B round 1
>
> ## Position
>
> **B, unchanged.** `{}` is a body; under both annotations it is E1110.
> - B variation (fmt rewrites `{}` away?): **No.** The fix ships as a machine fix (`blink fix` / LSP), as plt, devops B and aiml P2 say. fmt keeps meaning; it does not repair errors.
> - If N wins, N variation (scope of the rewrite): **annotated handle types only** (devops, sys, aiml). I oppose web's "every type declaration" scope; see fact 2 below.
>
> ## Responses
>
> **aiml ("under both readings the type has zero fields, so no program changes behaviour").** Accepted, and it is the strongest argument for N. It weakens my "context-dependent `{}`" point: no well-typed program reads differently under N. My objection is now on rule count, not on meaning. N needs: the equivalence, an fmt rewrite keyed on the annotation, and the comment exception. B needs one clause and reuses E1110. Same behaviour for correct code; B has fewer moving parts.
>
> **web ("plain types already behave that way; fmt already does it").** Fact 2 refutes this. `type M` + `M {}` ICEs at build; `type M {}` + `M {}` runs. They differ. fmt rewriting `type M {}` to `type M` breaks a working program and deletes comments (fact 3). So "fmt already does it" is a bug, not a precedent, and it shows the hazard of an fmt rule that must read context to stay safe. That is why, under N, the rewrite must be keyed on the annotation, and why I prefer B, which needs no fmt rule.
>
> **sys S2 / web W2 ("fmt applies the fix").** Then fmt would change an erroring program into a passing one. That makes `blink fmt` part of the type rules. Under B, `blink fix` is the tool for that; fmt stays a pure layout tool.
>
> **devops ("gofmt picks the spelling, not the compiler").** gofmt only rewrites forms that already mean the same thing. That supports N-with-fmt or B-without-fmt, not a mix. Both are coherent; B is smaller.
>
> **"Friction for habit"** (web, aiml). The cost is one error with a one-key fix, at handle declarations only. Users cannot write `@runtime`, and `@ffi.opaque` is rare FFI code. The habit cost lands on few lines.
>
> **Fact 1** (plt's table): noted. The construction error fires for `A {}` today, so my Phase A table row stays correct.
>
> ## Ranking
>
> 1. B, no fmt rewrite. 2. N, rewrite on annotated handles only. Last: N with the rewrite on every type (it breaks programs today).
>
> Both B and N close the real defect, which is that the two annotations disagree and `@ffi.opaque` accepts fields. I will not block N if the majority wants it.
>
> STABLE

### Phase C — Vote

Options on the ballot: `N`, an empty body is no body (§4 effect rule), so `type A {}` means `type A` and `blink fmt` rewrites it; `B`, `{}` is a body and is E1110 under both annotations. Result: `B` 5-1 (Systems, Web/Scripting, DevOps, AI/ML, Minimalism; PLT for `N`). Phase D did not run. The owner approved the tally on 2026-11-19.

- **Systems:**

> # [ticket] — sys, Phase C vote
>
> 1. **Vote:** B
>
> 2. **Reasoning:** In Blink, `{}` on a type already has a code-generation meaning: a value struct
> with a layout and a literal `T {}`. Plain `type M {}` and `type M` already lower differently
> (Fact 2). Under B, the parser's body or no-body flag alone decides value or C pointer, and the
> annotation only restricts. So the path from source to C stays predictable, and layout and fmt need
> no annotation context. C (`struct s;` vs `struct s {}`), Rust (`extern type`) and OCaml (abstract
> `type t`) keep these two forms apart for the same reason.
>
> 3. **Concern:** If B wins, the E1110 help and the `blink fix` quick fix must exist on day one.
> Without them, the users and models who write `{}` out of habit hit a dead end. If N wins, the
> annotation-keyed fmt rule can leak to plain types, as the fmt bug does today.

- **Web/Scripting:**

> # [ticket] — Web seat, Phase C vote
>
> 1. **Vote:** B
>
> 2. **Reasoning:** In a type declaration, `{}` already means "a zero-field struct that `T {}` builds". Under N, the annotation above the braces would decide what they mean, and that generates confused questions ("why does `Meters {}` build but `A {}` not?"). Only FFI binding authors and lib/std write these declarations. For them, a one-line E1110 with "remove the braces: `type A`" and a quick-fix costs seconds and teaches the one form that tools and LLMs then copy.
>
> 3. **Concern:** If the E1110 help is vague, or `blink fix` and the LSP do not apply it, users get an error that fmt will not clear. Then the strict rule feels like a trap, not a lesson.

- **PLT:**

> # [ticket] — PLT seat, Phase C vote
>
> 1. **Vote:** N
>
> 2. **Reasoning:** `type A` and `type A {}` both declare an empty set of fields. The handle annotation then seals that declaration: it removes the introduction form (no literal) and gives no elimination form (inert). The annotation acts on the declaration's meaning and does not change how `{}` is read, so the rule composes, and it is the same shape as an OCaml signature seal or `private` type. Under the seal no program can tell the two spellings apart, so an error over them (B) would refuse code without a semantic reason.
>
> 3. **Concern:** If the spec rests the "no literal" rule on today's compiler and not on the seal, a later change could make `type A {}` under an annotation build `A {}` again. So the spec must state the seal, and a test must refuse `A {}` for both spellings under both annotations.

- **DevOps:**

> # [ticket] — devops, Phase C
>
> 1. **Vote:** B
>
> 2. **Reasoning:** For a type, `{}` already means a zero-field struct, so under N `blink fmt` must read the annotation's name to decide whether braces may go. That would be its first rule that depends on what an annotation means, and each new handle annotation would have to be added to it. Today's `blink fmt` bug, which drops `{}` on a plain `type M {}` and turns a working program into an ICE, is the mistake N would build into the tool. Under B the fmt rule is simple (never remove type braces), and E1110 with a machine-applicable fix in the LSP and `blink fix` makes the repair one keystroke.
>
> 3. **Concern:** If the E1110 fix deletes the braces without moving a comment inside them above the annotation, it loses text, which is the same comment-loss bug `blink fmt` has today.

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase C vote
>
> 1. **Vote:** B
>
> 2. **Reasoning:** B adds one rule a model can learn from the spec alone ("a handle type has no braces"). N adds three rules that change with context: the annotation changes what `{}` means, fmt rewrites only under two annotations, and a comment keeps the braces. Under B every program that compiles has one spelling, so training text converges on one pattern. The cost is one repair turn with an exact help and a machine fix, which is the cheapest kind of error for a generator.
>
> 3. **Concern:** Models that carry the Rust/Go habit will write `type A {}` often at first, so the E1110 help must name the exact fix (`type A`), and `blink fix` must apply it, or each slip costs a reasoning turn instead of a mechanical one.

- **Minimalism:**

> # [ticket] — min, Phase C vote
>
> 1. **Vote: B**
>
> 2. **Reasoning:** Both options give the same behavior for correct code, so the choice comes down to how many rules each adds. B adds one clause and reuses E1110. N adds an equivalence, an fmt rewrite that must read the annotation, and a comment exception. That fmt rewrite reads context to stay safe, and today's fmt shows the hazard: it breaks programs by rewriting plain `type M {}`. One spelling that `check` enforces is the smallest surface, and it is the only form an LLM corpus will learn.
>
> 3. **Concern:** If N wins, the annotation-keyed fmt rule may drift from the plain-type case. Today's fmt bug shows this can happen, so the fmt goldens must prove that plain `type M {}` keeps its braces.

### Final Spec

```blink
@ffi.opaque(header: "stdio.h", name: "FILE")
type A                                  // OK

@ffi.opaque(header: "stdio.h", name: "FILE")
type B {}                               // ERROR E1110: empty braces are a body

@ffi.opaque(header: "stdio.h", name: "FILE")
type C {
    // the stream handle of libc
}                                       // ERROR E1110; `blink fix` moves the comment above the annotation

@runtime("blink_x")
pub type E {}                           // ERROR E1110: the same rule for `@runtime`

type M {}                               // OK: plain type; a struct with no fields

fn make() -> A {
    A {}                                // ERROR: a handle type has no literal
}
```

- Under `@ffi.opaque` and `@runtime`, any body is E1110: empty braces, braces that hold only a comment, fields, variants.
- The help names the exact fix (`type B`); the primary span is the `{`.
- `blink fmt` does not rewrite the braces. `blink fix` and the language server apply the help.
- A handle type has no literal. This is a rule of the language and not a note on one compiler.
- A plain `type T {}` does not change.
