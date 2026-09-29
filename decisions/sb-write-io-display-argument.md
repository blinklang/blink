[< All Decisions](../DECISIONS.md)

# `sb.write` and `io.*` Argument Types — Design Rationale

**Gap:** the ticket asked "argument-type dispatch for `sb.write` / `println` / format strings (overloading vs Display-like trait)". The headline question was already closed: the Display trait shape decision ([display-trait-shape.md](display-trait-shape.md)) routes `sb.write(x)` through `x.fmt(sb)`, and Blink has no function overloading. What remained was a contradiction and a hole:

- §3.2 *StringBuilder* gave `write` as `fn(self, s: Str)` and said the interpolation optimization leaves "the method signature unchanged", but §3.6 *Display Trait Shape* lowers `sb.write(x)` to `x.fmt(sb)` for any `T: Display`, and its `Point` example writes `Int` fields with `sb.write(self.x)`.
- §4.4 never stated the argument type of `io.print`, `io.println`, `io.log`, `io.eprint`, `io.eprintln` or the `_raw` variants. `effect IO { effect Print  effect Log }` declares no operation signatures; the stdlib handlers take `msg: Str`.
- The compiler accepts `sb.write(P{x: 1})` and `io.println(P{x: 1})` for a `P` with no `Display` impl, while `"{P{x: 1}}"` reports `MissingDisplayImpl`.

**Moderator facts surfaced during debate.** §4.4's `_raw` text, verbatim, and the fact that the compiler maps `print_raw` to the same C function as the no-newline default print (`io_default_print_no_nl`); existing `print_raw` uses in `src/cli.bl` pass `Str` literals and interpolated strings. Full text in the Phase C ballot notice below.

**Already decided (given to the panel as constraints):** the Display trait shape; strict interpolation (`T: Display`, no fallback); no function overloading; one `StringBuilder.write()` with a transparent interpolation optimization; `StringBuildOps` is prelude and sealed; `Display.fmt` has an empty effect row; effect handle operations resolve through the effect system, not traits.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six proposed and preferred the same core: a `Display` bound on `sb.write` and on the non-raw `io` functions, with handler operations kept on `Str`. Full texts:

**Systems:**

> Decision 1 already says `sb.write(x)` lowers to `x.fmt(sb)`. So `write` must accept any `T: Display`. The open questions are how stdlib types that rule and what `io.*` and the handlers take.
>
> **Proposal A: `write` is a generic Display sink (monomorphized)**
>
> Rule: `StringBuildOps.write[T: Display](self, x: T)`. The compiler monomorphizes per `T`, and the call becomes a direct `T.fmt(sb)` call. `Str`, `Int`, `Float`, `Bool` and `Char` get prelude `Display` impls whose `fmt` is a codegen intrinsic (typed append). `write_char` stays as it is. The "signature unchanged" text in 03_types.md is corrected to "`write` is generic over Display; interpolation lowering is transparent".
>
> ```blink
> impl Display for Point {
>     fn fmt(self, sb: StringBuilder) {
>         sb.write("(")
>         sb.write(self.x)   // Int.fmt, typed append
>         sb.write(", ")
>         sb.write(self.y)
>         sb.write(")")
>     }
> }
> ```
>
> - **Cost:** No boxing, no vtable, no intermediate `Str`.
>   - Every call site resolves statically to one C call or an inlined append.
>   - `sb.write("{x}: {y}")` lowers to `write(x)`, `write(": ")`, `write(y)`, which is the same code as the manual calls. The existing optimization becomes ordinary monomorphization instead of a codegen special case.
> - **Stdlib chore:** This unblocks moving `write` into lib/std. The special case reduces to the primitive impls' intrinsic bodies, which is one small, auditable set.
> - **Mono cost:** Code size grows by one instance per distinct `T`. That is bounded, and instances are tiny.
> - **Diagnostic:** A non-Display argument reports E0523 MissingDisplayImpl at the call, the same as interpolation. This also closes the bug that `sb.write(P{x:1})` passes today.
> - **Cross-language:** This is Rust `fmt::Write` plus `Display`, but with static dispatch. Zig's `writer.print` with `{}` is comptime-dispatched in the same way.
>
> **Proposal B: io ops take `T: Display`, handler ops stay `Str`**
>
> Rule: `io.print`, `println`, `log`, `eprint`, `eprintln` have surface signature `[T: Display](x: T)`. The `_raw` variants stay `Str`, since they are byte-level. The handler op signatures stay `print(msg: Str)`, as in testing.bl.
> - The effect layer converts before dispatch. A `Str` argument passes through with no copy.
> - Any other `T` is rendered once into a `Str` via `display()`, then handed to the handler.
>
> ```blink
> io.println(42)            // renders "42" once, calls handler print(msg: Str)
> io.println("plain")       // no copy, no alloc
> handler IO.Print {
>     fn print(msg: Str) { ... }
>     fn print_no_nl(msg: Str) { ... }
> }
> ```
>
> - **Cost:** At most one allocation, and only for non-`Str` arguments. It is the same cost as `io.println("{x}")` today, so the cost is visible in the model.
> - **Handlers:** Interceptable handlers keep one monomorphic ABI (`Str`). A generic handler op would force a per-`T` handler vtable or a boxed Display object, which I reject.
> - **Effect decision (7):** The op resolves through the effect system. Only the argument check uses the Display bound, so this does not route dispatch through a trait.
>
> **Proposal B2 (alternative): io ops accept `Str` only**
>
> Rule: `io.println(x: Str)`. Users write `io.println("{x}")`. There is no hidden conversion and no new bound.
> - **Cost:** One allocation for the interpolated `Str`, the same as B.
> - **Tradeoff:** Ergonomics are worse. `io.println(42)` is an error, and this is inconsistent with A's `write(42)`. That inconsistency is a teaching cost. The compiler could still lower `println("{x}")` directly to typed writes on a stack builder.
>
> **Proposal C (rejected): `write(s: Str)` only, with Display users interpolating**
>
> Users would write `sb.write("{self.x}")`. Interpolation lowering keeps this zero-cost. But it contradicts decision 1 (`sb.write(x)` is a call shape), so I list it only to show it is not viable.
>
> **Preference: A plus B.**
> - A is forced by decision 1. It is zero-overhead through monomorphization and it reduces the stdlib chore to a small set of intrinsic impls.
> - B gives the ergonomic `io.println(42)`. It costs one alloc only when the argument is not already a `Str`, and the handler ABI stays a single `Str`.
> - B2 is the fallback if the panel wants no implicit rendering at the effect boundary.
> - Both use E0523 for a missing Display impl.

**Web/Scripting:**

> ## Proposal 1: "Display bound on every text sink" (preferred)
>
> **Rule.** `sb.write`, `io.print`, `io.println`, `io.log`, `io.eprint`, `io.eprintln`, `io.print_raw` and `io.eprint_raw` take `x: T` where `T: Display`. `Str`, `Int`, `Float`, `Bool` and `Char` already implement `Display`, so `println("hi")` and `println(42)` both work. A type without `Display` gets E0523 MissingDisplayImpl. This is the same diagnostic that `"{p}"` produces today. The compiler no longer accepts `sb.write(P{x:1})`, and the pending bug ticket closes.
>
> The handler ops stay `msg: Str`. The call site formats `x.display()` first, and the handler sees only the final string. Formatting therefore stays outside the effect system (decided items 6 and 7). Handlers such as testing capture never see a generic argument.
>
> This is a bounded generic, not overloading (decided item 3). The spec text becomes `write | fn[T: Display](self, x: T)`. Decision 4 (one `write()`) still holds, and the interpolation optimization stays transparent.
>
> ```blink
> fn fmt(self, sb: StringBuilder) {
>     sb.write("(")
>     sb.write(self.x)        // Int: Display
>     sb.write(", ")
>     sb.write(self.y)
>     sb.write(")")
> }
>
> fn main() {
>     io.println(42)          // ok
>     io.println(Point { x: 1, y: 2 })   // ok if Point: Display
>     io.println(NoDisplay {})           // E0523
> }
> ```
>
> **Stdlib expression.** In `lib/std/traits.bl`, `StringBuildOps` declares `fn write[T: Display](self, x: T)`. The body is `x.fmt(self)`, and `Str` is the base case. `impl Display for Str` calls one private, non-user-visible append intrinsic, so there is no `fmt` to `write` recursion. Monomorphization gives each `T` its own copy. The chore that moves `write` out of codegen can then delete the interpolated-string special case, because interpolation lowers to `write(part)` per part.
>
> **Tradeoffs (DX).**
> - A JS or Python developer writes `println(x)` and it works. This is the "just works" path and covers 90% of uses.
> - One error message covers interpolation, `write` and `println`. That is one Stack Overflow answer for all three.
> - The cost is that `Display.fmt` calls `write`, which calls `fmt`. That cycle is the only clever part, and users never see it. Signature hover shows `T: Display`, which reads like a TypeScript generic.
>
> **Cross-language.** This matches Rust's `println!("{}", x)` bound, Kotlin's `print(Any?)` (which is looser), and Python's `print(x)` calling `str()`. It is stricter than Python and JS, which accept any object.
>
> ## Proposal 2: "Str-only sinks, explicit conversion"
>
> **Rule.** `write` and `io.*` take `Str` only. Callers write `sb.write(x.display())` and `io.println(n.display())`. Use `{}` interpolation for everything else.
>
> ```blink
> io.println("{n}")            // fine
> io.println(n)                // error: expected Str, found Int
> sb.write(self.x.display())
> ```
>
> **Tradeoffs.**
> - The types stay simple and there are no generics on the hot path.
> - It breaks the ticket's own Display example, which passes `Int` to `write` directly, and it contradicts decided item 1: `sb.write(x)` must lower to `x.fmt(sb)`.
> - `display()` allocates a `Str` for every `sb.write(int)`, which defeats the purpose of a builder.
> - Newcomers hit "expected Str, found Int" on the first `println(42)`, and that is a guaranteed Stack Overflow question.
>
> I reject this one. It reopens decided item 1.
>
> ## Proposal 3: "Display on `write`, Str-or-Display on `io`" (split)
>
> **Rule.** `sb.write` is generic over `Display`. The `io.*` functions accept `T: Display` too, but `io.log` takes a structured message and `io.println` takes any `Display`.
>
> **Tradeoffs.** Splitting the rules per sink adds a mental table. It does not improve on Proposal 1, so I do not recommend it.
>
> ## Preference
>
> I prefer **Proposal 1**. Use one rule (`T: Display`), one diagnostic (E0523) and one mental model for every text sink. Keep handler ops `Str` so the effect system stays simple.
>
> **Open question for the panel.** Should `io.print_raw` and `io.eprint_raw` also take `Display`? I say yes, for consistency, because a special case would just generate more questions.

**PLT:**

> ## Proposal P1: `write` and the `io` front-ends are bounded-polymorphic, and effect ops stay monomorphic on `Str`
>
> **Rule.** The gap comes from writing one signature for two different things. Resolve it in the type system:
>
> - `write` is one method with a Display bound: `fn write[T: Display](self, x: T)`. It is parametric with a bound, which is not overloading, so decision 3 holds.
> - `Str`, `Int`, `Float`, `Bool` and `Char` have prelude `Display` impls. The `Str` impl appends its text and is the base case.
> - `sb.write(x)` has the typing rule Γ ⊢ x : T, T : Display ⊢ sb.write(x) : Void, with an empty effect row (decision 6). It elaborates to `x.fmt(sb)`.
> - `write("{x}: {y}")` is the case T = Str. The interpolation lowering is then a semantics-preserving rewrite, because `"a{b}"` is `a.fmt(sb); b.fmt(sb)`. This keeps the spec's claim that the optimization is transparent.
> - The `io.print`, `io.println`, `io.log`, `io.eprint*` and `io.print_raw` front-ends are stdlib wrappers of the form `fn println[T: Display](x: T) with IO.Print`. The wrapper computes `x.display()` first, then performs the effect op.
> - Effect ops stay first-order and take `Str`, as `lib/std/testing.bl` handlers do today: `handler IO.Print { fn print(msg: Str) {...} }`.
> - A handler therefore never sees `T`. Conversion happens before the perform and is pure, so handler interception has no type-level effect.
>
> ```blink
> trait Display { fn fmt(self, sb: StringBuilder) ... }
>
> impl StringBuildOps for StringBuilder {
>     fn write[T: Display](self, x: T) { x.fmt(self) }   // sealed; single method
> }
>
> fn println[T: Display](x: T) with IO.Print {
>     io.print(x.display() + "\n")   // op is monomorphic: print(msg: Str)
> }
> ```
>
> **Diagnostic.** A missing bound at `write` or `io.*` reuses E0523 MissingDisplayImpl, so all three call shapes give one error. The generic call-site bound error (E0306) would give a different code for the same mistake. Special-case it, or map it, so the code is E0523.
>
> **Tradeoffs (PLT).**
> - **Sound and compositional.** The bound is checked at the call site, and monomorphization has one instance per T. The current acceptance of `sb.write(P{x:1})` is exactly the missing bound check, and this proposal closes it.
> - **Chore unblocked.** `StringBuildOps.write` becomes expressible in lib/std with no codegen special case beyond the interpolation rewrite.
> - **Circularity.** The `Str`/`Int` Display impls cannot be written in Blink itself. `Str.fmt` needs a primitive append, so those primitive impls must stay compiler-intrinsic. Name that seam explicitly. It is the only place that is not expressible in the stdlib.
> - **No polymorphic ops.** A handler for `print[T]` would need higher-rank or per-T handler machinery, which is a type-theoretic cost with no benefit. Keeping ops first-order avoids it.
>
> **Cross-language.** This matches Rust's `impl Display`/`write!` and Haskell's `Show a =>` on `print`. In Koka, `println` is `show`-overloaded, and the effect op `print(s: string)` takes a string. That is the same split as here.
>
> ## Proposal P2: `write` takes only `Str`, and `io.*` takes only `Str`
>
> **Rule.** The signature stays `write(self, s: Str)`, and `io.*` takes `Str`. Users must write `sb.write(x.display())` and `io.println(x.display())`.
>
> **Tradeoffs.**
> - The typing rule is trivial and no polymorphism is needed.
> - It contradicts decided constraint 1, which says `sb.write(x)` lowers to `x.fmt(sb)`. It also makes `display()` allocate an intermediate `Str`, which defeats the push-based design.
> - It is included only as the baseline. It reopens a decided point, so I reject it.
>
> ## Proposal P3: `write` special-cased in the checker, with an implicit Display bound
>
> **Rule.** The signature is still `write(self, s: Str)` in docs. The checker treats `write` and `io.*` as built-in forms with a hidden Display check.
>
> **Tradeoffs.**
> - This is what the compiler nearly does today. It is not expressible in the type system, so users cannot write their own `write`-like wrapper (for example `log_to(sb, x)`) without hitting the same hole.
> - It does not compose, and it blocks the stdlib migration. I reject it.
>
> ## Preference
>
> I prefer **P1**. It is the only option that meets all of these:
> - decided constraints 1 to 7;
> - a checkable typing rule;
> - an unchanged handler ABI (`Str` ops);
> - the stdlib migration.
>
> Its one cost is the intrinsic primitive `Display` impls. Say so in the spec and do not hide it.

**DevOps:**

> ## Proposal 1: One generic bound, one diagnostic (preferred)
>
> **Rule.** Every text sink takes `T: Display`. `StringBuildOps.write` is `fn write[T: Display](self, x: T)`. `io.print`, `io.println`, `io.log`, `io.eprint` and `io.eprintln` also take `x: T` with `T: Display`. `Str`, `Int`, `Float`, `Bool` and `Char` have prelude `Display` impls. `write_char(self, c: Char)` stays as is. The `io.*_raw` ops take `Str`, because "raw" means no formatting.
>
> Handler op signatures stay `Str`. The call site runs `x.display()` before it dispatches to the handler. `fmt` has an empty effect row, so this is safe. Handlers never see the `T`, and `lib/std/testing.bl` needs no change.
>
> The interpolation optimization stays a lowering of `sb.write("{x}")`. The `Str` argument is a `Display` value, and the type system does not see the lowering. The spec text "signature unchanged" becomes true: the signature is the generic one above.
>
> ```blink
> trait StringBuildOps {
>     fn write[T: Display](self, x: T)
>     fn write_char(self, c: Char)
> }
>
> impl Display for Point {
>     fn fmt(self, sb: StringBuilder) {
>         sb.write("(")
>         sb.write(self.x)      // Int: Display
>         sb.write(", ")
>         sb.write(self.y)
>         sb.write(")")
>     }
> }
>
> fn main() {
>     io.println(Point { x: 1, y: 2 })   // Display, so accepted
>     io.println(NoDisplay { x: 1 })     // E0523
> }
> ```
>
> **Diagnostics and LSP.**
> - Interpolation, `sb.write`, and `io.println` all report `E0523 MissingDisplayImpl`. Users learn one error code.
> - The message names the sink: `` `io.println` requires `Display`; `P` does not implement it ``.
> - The span is the argument, not the call.
> - Hover and signature help show the true signature, `write[T: Display](self, x: T)`.
> - Completion for `impl Display for` works the same at every sink.
> - `blink fmt` sees an ordinary generic call and needs no special case.
> - The fix to the current acceptance bug is now one rule in one place: the bound check on generic calls.
>
> **Tradeoffs.**
> - Cost: a monomorphized generic on the hottest path. Mono per `T` is bounded and `Display` is sealed-shape. Codegen may still fast-path `Str` and `Int` as an optimization.
> - Benefit: the chore that moves `write` into `lib/std` becomes plain stdlib code. No typecheck special case is left.
>
> **Cross-language.** Rust's `println!` and `write!` require `Display`, and rustc's `E0277` message names the missing trait. Go's `fmt.Println(any)` accepts anything and prints garbage, so it has no diagnostic to give.
>
> ## Proposal 2: Layered. Bound on `write`, `Str`-only on `io.*`
>
> **Rule.** `sb.write[T: Display]` as in Proposal 1. `io.print` and the other `io.*` ops take `Str` only. The user writes `io.println("{p}")`.
>
> **Tradeoffs.**
> - Benefit: the handler signature matches the call signature exactly.
> - Cost: `io.println(42)` fails, and it is the first line a new user writes. The error would need a special hint, "wrap in interpolation". That is a diagnostic patch over a design gap.
> - Cost: the spec has two rules for two sinks.
> - Cost: the string built at the call site allocates for nothing.
>
> I reject this. The gain is small and the diagnostic cost is real.
>
> ## Proposal 3: Signature says `Str`, checker special-cases (status quo, formalized)
>
> **Rule.** The docs keep `write(self, s: Str)`. The typechecker also accepts any `T: Display`.
>
> **Tradeoffs.**
> - The signature the LSP shows is wrong, and hover output lies.
> - The stdlib cannot express the rule in the trait, so the chore stays blocked or needs a permanent compiler special case.
> - A user cannot write a wrapper `fn log_to(sb, x)` with the same acceptance, unless they discover the hidden rule.
>
> I reject this. It breaks "diagnostic surface = truth".
>
> ## Rejected without a full write-up
>
> - **Overloading `write`.** This breaks constraint 3.
> - **Auto-fallback to a debug-style dump.** This breaks constraint 2, and it hides the very error users need to see.
>
> ## Preference
>
> Proposal 1. It has one trait, one error code, one true signature, and the handler ABI stays `Str`.
>
> One check for the moderator. The `Display` prelude impls for primitives must be listed in the spec. Without them, `sb.write(self.x)` in the decided Point example has no justification.

**AI/ML:**

> ## Proposal A: Display-only writes, one rule for every text sink (preferred)
>
> **Rule.** `StringBuilder.write` is `fn write[T: Display](self, x: T)`. It lowers to `x.fmt(sb)`. `Str` implements `Display` and appends itself. `Int`, `Float`, `Bool` and `Char` implement `Display` in lib/std. The prelude trait `StringBuildOps` keeps its one `write` method, so the 3-1-1 vote still holds. The interpolation optimization stays transparent, because `sb.write("{x}: {y}")` is just `write` with a `Str` argument.
>
> `io.print`, `io.println`, `io.log`, `io.eprintln` and `io.eprint` each take `T: Display`. They render to `Str` and then reach the handler op. Handler ops stay `Str`-typed, so the `lib/std/testing.bl` handlers do not change. `print_raw` and `eprint_raw` are the same. Their argument type also becomes `T: Display`, and only the newline differs.
>
> The diagnostic is E0523 MissingDisplayImpl at every sink. It names the sink, for example "`sb.write` argument type P does not implement Display".
>
> ```blink
> struct P { x: Int }
>
> impl Display for P {
>     fn fmt(self, sb: StringBuilder) {
>         sb.write("P(")
>         sb.write(self.x)
>         sb.write(")")
>     }
> }
>
> fn demo(io: IO) {
>     let mut sb = StringBuilder.new()
>     sb.write(P { x: 1 })   // OK: T: Display
>     sb.write_char('!')
>     io.println(P { x: 1 }) // OK
>     io.println(sb)         // error E0523: StringBuilder is not Display (if not implemented)
> }
> ```
>
> **Tradeoffs (AI/ML).**
> - **Decision points: one.** An LLM learns "anything that prints must be `Display`". It does not need to pick between `write`, `write_int`, `.display()` and interpolation. This is the same rule as `"{x}"`, so one lesson covers all four text sinks.
> - **Tokens: minimal.** `io.println(x)` and `sb.write(x)` need no `.display()` or `.to_string()` wrapper. The common pattern is the shortest one.
> - **Debuggability: high.** One error code at every sink, so a model can repair it from the message alone. Today `sb.write(P{x:1})` passes `check` and fails later, or silently. That is the worst outcome for an LLM.
> - **Cost.** The generic signature is more complex than `write(s: Str)`. The spec table must say "`T: Display`". The `Display` impl for `Str` needs care: `Str.fmt` must not recurse into `write`.
> - **Chore unblocked.** Moving `write` into lib/std is direct: it is one generic fn plus per-type `Display` impls. The codegen special case for interpolated arguments can go.
>
> **Cross-language.** This matches Rust `write!`/`println!` (which need `Display`) and Swift `print` (needs `CustomStringConvertible`). It differs from Python's `print(obj)`, which accepts anything, and from Go `fmt.Println(any)`. Rust is the closest match, and models already know it.
>
> ## Proposal B: `write` takes `Str` only, and `Display` is spelled `.display()`
>
> **Rule.** `sb.write(s: Str)` and `io.println(s: Str)` take `Str` only. `Display` reaches them through `x.display()` or interpolation `"{x}"`. Call shape 3 of the Display trait shape (`sb.write(x)`) is removed. This reopens decided item 1 (three call shapes), so it needs a panel vote to override.
>
> ```blink
> sb.write(p.display())
> io.println("{p}")
> ```
>
> **Tradeoffs.**
> - Good: signatures are simple, with no generics on the hot path. Handler ops and sink signatures match exactly.
> - Bad: every `Int` needs `"{n}"` or `.display()`. This adds tokens to the most common pattern, and LLMs from Rust and Python will write `sb.write(n)` and `println(n)` by reflex. That produces a frequent error class.
> - Bad: it drops a decided shape, and the spec Point example already uses `sb.write(self.x)`.
>
> ## Proposal C: `Str`-only write plus a separate `write_display`
>
> **Rule.** `write(Str)` stays. A new `sb.write_display(x: T)` handles `Display`. `io.println` takes `Str`.
>
> **Tradeoffs.** This adds a second method and a decision point at every call (which one?). It also conflicts with the decided "one `write()` method". I reject it. I list it only for completeness, so the panel can see the cost of avoiding generics.
>
> ## Recommendation
>
> I prefer **Proposal A**. It has the fewest decision points, it is consistent with the decided rules 1, 2, 4 and 5, and one diagnostic covers every text sink. It also matches Rust, which models already know.
>
> Two spec details should be fixed in A:
> 1. State that `Display` for `Str` appends the value directly and is not lowered through `write`, so the impl does not recurse.
> 2. State that the `io.*` sinks are generic wrappers over `Str`-typed handler ops. Effect handlers remain the interception point (decided rule 7), and `Display.fmt` keeps its empty effect row (rule 6).

**Minimalism:**

> Decided item 1 already says `sb.write(x)` lowers to `x.fmt(sb)`. So the gap is not open-ended. The spec has two sentences that contradict each other, and I must remove one. I also must choose the rule for `io.*`.
>
> ## Proposal A: One generic `write`, `Str` is just a `Display` type (core)
>
> **Rule.** `StringBuildOps.write` becomes `fn write[T: Display](self, x: T)`. This is a bound, not an overload, so decision 3 holds. `Str`, `Int`, `Float`, `Bool` and `Char` get ordinary `Display` impls in lib/std. Only the primitive `fmt` bodies use an intrinsic. The `write` body is `x.fmt(self)`. `write_char` stays as it is. The spec sentence "write takes Str, signature unchanged" is replaced by "the `Str` impl of `fmt` appends raw, so the interpolation lowering is transparent". Codegen loses its special case for interpolated arguments. The per-part typed writes become plain `fmt` calls on primitives.
>
> ```blink
> trait StringBuildOps {
>     fn write[T: Display](self, x: T)
>     fn write_char(self, c: Char)
> }
>
> impl Display for Point {
>     fn fmt(self, sb: StringBuilder) {
>         sb.write("(")
>         sb.write(self.x)
>         sb.write(", ")
>         sb.write(self.y)
>         sb.write(")")
>     }
> }
> ```
>
> **Diagnostic.** Reuse E0523 `MissingDisplayImpl` at the `write` call site. Add no new code. This also closes the bug where `sb.write(P{x:1})` is accepted for a non-Display struct.
>
> **Tradeoffs.**
> - **Rules:** this is a subtraction. Codegen loses one special case, the spec loses one contradiction, and there is one rule instead of two.
> - **Cost:** the bound is a generic function, so mono runs per `T`. That cost was already there, because decided item 1 already needs `x.fmt(sb)` per type.
> - **Rejected alternative:** keep `write(Str)` and forbid `sb.write(x)`. This is the smallest surface, but it breaks decided items 1 and 4. Not eligible.
>
> **Cross-language.** Rust `write!` calls `fmt::Display` per argument. Go's `fmt.Fprint(w, x)` takes `any`. Zig's `writer.print` takes a format and args. A bound is the strictest of these and needs no reflection.
>
> ## Proposal B: `io.*` takes `T: Display`; handler ops stay `Str`
>
> **Rule.** `io.print`, `io.println`, `io.log`, `io.eprintln` and `io.eprint` take `T: Display`. The call site converts with `x.display()`. The effect op receives a `Str`. The `IO.Print` and `IO.Log` handler signatures stay `msg: Str`, as in lib/std/testing.bl, so no handler changes. `io.print_raw` and `io.eprint_raw` take `Str` only, because raw output should not go through formatting.
>
> ```blink
> io.println(42)
> io.println(p)
> io.println("{p}")
> ```
>
> **Tradeoffs.**
> - **Rules to teach:** with A alone, `write` is generic and `println` is `Str`-only. That is two rules and an inconsistency. B gives one rule: anything `Display` can be output.
> - **Interception:** the `display()` call happens before effect dispatch. This keeps decision 7 intact, because the op still resolves through the effect system. I flag this for the panel: a strict reading of decision 7 may object to a trait bound on the op argument.
> - **Fallback if it fails:** B0 (`io.*` takes `Str` only) is the pure subtraction. `io.println("{x}")` already works. Diagnostic: E0523 also fires when `x` is not `Display`.
> - **Cost of B:** it adds one implicit `display()` call per `io` call and keeps the interception contract as it is.
>
> ## Not proposed
>
> - **Any auto-`Display` fallback.** Decision 2 forbids it.
> - **A new `Write` trait or format-arg macro.** That is new surface with no gap it closes.
> - **Docs-only.** Not enough here. The code accepts what the spec should reject, so the fix must touch the typechecker.
>
> ## Preference
>
> I prefer A plus B. It leaves one rule (`Display` is the only conversion to text) and it removes codegen special cases. If the panel reads decision 7 strictly, I vote A plus B0. I would not accept B0 without A.

#### Phase A.5 — Mechanical dedupe

The moderator's deduped option space and flagged variations, as sent to the panel:

> Full Phase A texts, verbatim, are in this directory: phaseA_sys.md, phaseA_web.md, phaseA_plt.md, phaseA_devops.md, phaseA_aiml.md, phaseA_min.md. Read all six.
>
> ## Deduped option space
>
> **Q1 — what `sb.write` accepts.**
> - Option W-D: `fn write[T: Display](self, x: T)`, lowers to `x.fmt(sb)`; `Str`, `Int`, `Float`, `Bool`, `Char` have prelude `Display` impls whose `fmt` bodies are compiler intrinsics; `write_char` unchanged. Proposed and preferred by all six (Sys A, Web 1, PLT P1, DevOps 1, AI/ML A, Min A).
> - Proposed and rejected by their own authors: `write(Str)` only (Web 2, PLT P2, AI/ML B, Sys C, Min "rejected alternative"); `write(Str)` + `write_display` (AI/ML C); docs say `Str`, checker hides a Display check (DevOps 3, PLT P3).
>
> **Q2 — what `io.print`, `io.println`, `io.log`, `io.eprint`, `io.eprintln` accept.**
> - Option IO-D: `T: Display`; the call site renders with `x.display()` before the effect op; handler op signatures stay `msg: Str`. Preferred by all six (Sys B, Web 1, PLT P1, DevOps 1, AI/ML A, Min B).
> - Option IO-S: `Str` only; user writes `io.println("{x}")`. Listed as fallback/alternative by Min (B0, "if the panel reads decision 7 strictly") and Sys (B2); proposed and rejected by DevOps (2) and Web (3, split variant).
>
> ## Flagged variations (need debate)
>
> - **V1 — `io.print_raw` / `io.eprint_raw` argument type.** `T: Display`: AI/ML, Web ("for consistency"), PLT (listed in P1 front-ends). `Str` only: Sys ("byte-level"), DevOps ("raw means no formatting"), Min ("raw output should not go through formatting").
> - **V2 — diagnostic code.** All six name E0523 MissingDisplayImpl at every sink. PLT notes the generic call-site bound error (E0306) would otherwise fire for the same mistake and must be special-cased or mapped to E0523. DevOps: message names the sink; span is the argument.
> - **V3 — Min's decision-7 flag.** Min: "a strict reading of decision 7 may object to a trait bound on the op argument." Sys and PLT state the bound sits on the front-end wrapper, not on the effect op.
> - **V4 — spec text details raised.** Str's `fmt` appends directly and does not recurse through `write` (AI/ML, Web, Min, PLT); primitive `Display` impls must be listed in the spec (DevOps, PLT: "say so in the spec and do not hide it"); `io.*` described as generic wrappers over `Str`-typed handler ops (AI/ML, PLT).
>
> ## Your reply (this round)
>
> Keep it under ~300 words. Respond to V1–V4 and to anything in another panelist's text you disagree with. You may revise your position or propose a variation. End with either "STABLE — ready to vote" or "NOT STABLE — <what remains open>". Do not edit files.

#### Phase B — Debate (one round)

Five of six sent "STABLE — ready to vote" after round 1; DevOps held V1 (`_raw`) open, which the ballot put to a vote as Q3. Round 1 replies, verbatim:

**Systems:**

> **Q1 and Q2:** No disagreement. W-D and IO-D stand.
>
> **V1 (`_raw` argument type):** For cost, `T: Display` and `Str` are equal. `Str.fmt` passes through with no copy, so I no longer defend "byte-level" as a cost argument. The question is what `_raw` means in the spec. If `_raw` means "no trailing newline", it duplicates `print_no_nl` and there is no reason to give it a different bound than `print`. In that case I vote `T: Display`, for one rule across all sinks. If `_raw` means "bypass any formatting or escaping", then `Str` stays. I have not checked 04_effects.md for which meaning it uses. The panel should read it before voting. I lean `T: Display` only if the spec text allows it.
>
> **V2 (diagnostic):** I agree with PLT. The bound-check failure at these call sites must report E0523, not E0306. Say so in the spec. The message should name the sink and put the span on the argument (DevOps).
>
> **V3 (decision 7):** Min's worry is answered. The bound sits on the front-end wrapper. The effect op (`print(msg: Str)`) is unchanged and is still what handlers intercept. Decision 7 is about how ops resolve, not about argument checks.
>
> **V4 (spec text):**
> - **PLT's wrapper body:** `io.print(x.display() + "\n")` is a cost bug. It builds one `Str` for `display()` and a second for the concat. The spec should say the wrapper calls the newline op (`print` versus `print_no_nl`) and does not concatenate. The spec should also say a `Str` argument is passed through with no copy. That is the `io.println("plain")` fast path, and it is what keeps IO-D free of any cost for existing code.
> - **Non-`Str` arguments:** Render into a single `Str` (one alloc) and call the op once.
> - **Intrinsic seam:** Agree. List the primitive `Display` impls and mark them as the only compiler-intrinsic `fmt` bodies. Agree that `Str.fmt` appends directly and never goes through `write`, so there is no recursion. The `Display` impl for `Str` is the one that must not go through the generic path. Otherwise the base case is unreachable.
> - **Codegen fast paths:** DevOps says codegen may fast-path `Str` and `Int`. That is fine as an optimization, but it must not change semantics. The spec should say the generic path is the definition.
>
> I reject IO-S (B2) as the default. It stays my fallback only if the panel reads decision 7 strictly.
>
> **STABLE — ready to vote**, provided the panel settles V1 by what `_raw` means in the spec.

**Web/Scripting:**

> **V1 (`_raw` argument type).** I change my position. `sections/04_effects.md:196-199` says `_raw` bypasses the handler system and the trace, and is an escape hatch for direct C output. It says nothing about skipping formatting. So `_raw` should not run the Display machinery: I now say `Str` only. The failure mode is small. `io.print_raw(42)` gives "expected Str, found Int", and the message can suggest `"{x}"`. `_raw` is low-level tooling, not application code, so few users will hit it. I withdraw my "consistency" argument.
>
> There is one cost. The spec must state that `print`, `println`, `log`, `eprint` and `eprintln` take `Display`, while the `_raw` variants take `Str`. The rule is short: `_raw` means no formatting and no handlers. The `eprint` and `eprintln` case needs an explicit spec line, because they also bypass handlers but are not `_raw`. I say they take `Display`. They are the ordinary stderr path, and forcing `eprintln("{e}")` would be surprising.
>
> **V2 (diagnostic).** I agree with E0523 at every sink. PLT is right that E0306 must not surface here. The E0523 message should name the sink and put the span on the argument, as DevOps said. It should also suggest "implement Display for T". That hint is the fix a newcomer needs.
>
> **V3 (decision 7).** I agree with Sys and PLT. The bound sits on the front-end wrapper, and the op stays `print(msg: Str)`. Min's fallback (`io.*` takes `Str` only) would give bad DX. `io.println(42)` failing is the first thing a JS or Python developer types. I would oppose IO-S.
>
> **V4 (spec text).** I support all four points, and I want one addition. The spec should include one example showing `println(42)` and `sb.write(self.x)` side by side, so the surface reads as one rule.
>
> **Disagreement with another panelist.** Sys says `Str` passes through with no copy, and that is right. However, `println` on non-`Str` types allocates. The spec should say so once, and it does not need a separate section.
>
> STABLE — ready to vote

**PLT:**

> **V1 (`print_raw` / `eprint_raw`).** I change my position and choose `Str` only. Spec line 196 says these are "raw stdout, no newline" and column 3 (handler-interceptable) is "No". They bypass the effect system. Nothing is rendered for a handler, so the wrapper argument for `print`/`println` does not apply. `raw` here means "unintercepted, unformatted". The rule is also cheap to state: the interceptable sinks take `T: Display`, and the bypass sinks take `Str`. This corrects my Phase A, which listed `print_raw` in P1 for consistency alone. Web and AI/ML argue only consistency. That argument is weaker than a boundary that follows the effect system. I accept the `Str` cost: one extra `"{x}"` at a rare call site.
>
> **V2 (E0523 vs E0306).** I agree on E0523 at every sink. Decide the mechanism now, or the spec will not be implementable. Do not special-case `write` and `io.*` by name. That is P3 again. Instead, let a `Display` bound failure at any generic call site report E0523, and keep E0306 for other traits. The rule is uniform and needs no per-sink code.
>
> **V3 (decision 7).** Min's concern does not apply. Decision 7 says handle ops "resolve through the effect system, not through traits". The bound sits on the wrapper. The op that is performed takes `Str` and is resolved through the effect system. State this sentence in the spec so it does not read as a conflict. B0 is not needed.
>
> **V4 (spec text).**
> - I agree with all of it.
> - Name the intrinsic seam exactly once in the spec: "the `Display` impls of `Str`, `Int`, `Float`, `Bool` and `Char` have compiler-provided `fmt`; every other impl is ordinary Blink". Do not describe it as "written in lib/std", as Web and Min imply. The `Str` base case cannot be written there without recursion.
> - Add one line to the spec: `write_char` stays outside the `Display` path. It takes `Char` and is not generic.
>
> **Disagreement.** Sys says `io.println(str)` costs "no copy". This depends on `display()` on `Str` returning its receiver. The spec should say `Str.display()` is identity, or the "no alloc" claim is unfounded.
>
> **Disagreement.** DevOps says hover shows `write[T: Display]`. That is true only if the sealed `StringBuildOps` declaration carries the generic. Keep the trait method itself generic.
>
> STABLE — ready to vote

**DevOps:**

> **V1 (`*_raw` type): I move to `Display`.**
> - I said "raw means no formatting". The spec does not support that. Per the digest, `print_raw` only drops the newline, and Sys and Min call it "byte-level". That is inference. Check what `print_raw` does in `sections/04_effects.md` before the vote.
> - If `_raw` takes `Str` while `println` takes `Display`, hover and the docs show two rules on one family. `io.print_raw(42)` would then get a bare type-mismatch error, not E0523. I would need a special hint to fix that. That is the same diagnostic patch I rejected in my Proposal 2.
> - If `_raw` writes bytes, it should take `Bytes`, not `Str`. That is a different question.
> - Position: `T: Display` for all `io` text sinks, unless the spec shows `_raw` is not text.
>
> **V2 (diagnostic code): E0523 everywhere, with these requirements.**
> - The E0306 to E0523 mapping must apply to the argument span.
> - The message names the sink: `` `io.println` requires `Display`; `P` does not implement it ``.
> - Interpolation, `write`, and `io.*` must not show three different wordings for one mistake.
> - I need a test per sink that asserts both the code and the span.
>
> **V3 (decision 7): I side with Sys and PLT.**
> - The bound sits on the front-end wrapper. The op stays `print(msg: Str)`.
> - Decision 7 says ops resolve through the effect system, not traits. That still holds.
> - I do not want B0 (`Str` only) as a fallback. It is a worse error surface, as in my Proposal 2.
> - Min should say what the strict reading of decision 7 actually forbids. As far as I can tell, it forbids nothing here.
>
> **V4 (spec text): required, and I add two points.**
> - The spec lists the primitive `Display` impls and marks their `fmt` as intrinsic.
> - `Str.fmt` appends directly and does not recurse through `write`.
> - The spec table shows `write[T: Display]`, so hover matches the docs.
> - The `io.*` front-ends are documented as generic wrappers over `Str`-typed ops.
>
> **New point, from PLT's example.**
> - The `println` wrapper `io.print(x.display() + "\n")` shows an extra concatenation. It also shows that `display()` builds a `Str` before the op.
> - Sys says a `Str` argument passes through with no copy. The spec should state one rule, so tools and docs agree.
> - Handler-visible output must be identical either way. A test double for `IO.Print` must see the same `msg` for `println(42)` and `println("42")`.
>
> **Status:** NOT STABLE. V1 is open: the spec must say what `print_raw` does. Everything else matches my position.

**AI/ML:**

> **V1 (`print_raw` / `eprint_raw`).** I keep `T: Display`. `sections/04_effects.md:196-197` shows both ops are not handler-interceptable. So the handler ABI argument for `Str` does not apply here. "Raw" in the spec means "no newline". It does not mean "no formatting". A model that has learned "anything `Display` prints" will write `io.print_raw(42)`. A `Str`-only rule adds a special case that is not in the spec text. The cost is low either way, so I will accept `Str`-only if the majority wants it. In that case the spec must state the exception in the table row, and the diagnostic must hint: "wrap with `"{x}"`".
>
> **V2 (diagnostic code).** I agree with PLT. E0523 must fire at every sink, and E0306 must not fire for the same mistake. This is the main learnability point: one error code means one repair pattern. The message names the sink, and the span is the argument (DevOps).
>
> **V3 (Min's decision-7 flag).** I side with Sys and PLT. The bound sits on the front-end wrapper, and the effect op stays `Str`-typed. Decision 7 says ops resolve through the effect system, and that still holds. Only argument rendering happens before the op. I support the spec sentence "`io.*` are generic wrappers over `Str`-typed handler ops". Min's fallback B0 hurts ergonomics: `io.println(42)` is the first line new users write.
>
> **V4 (spec text).**
> - Add the primitive `Display` impls to the spec, as DevOps and PLT ask. Without them the decided Point example has no basis.
> - State that `Str.fmt` appends directly and does not go through `write`.
> - Name the intrinsic seam once, in one place. Do not repeat it in each table.
>
> **Disagreement.** Sys says a `Str` argument to `io.println` passes with no copy, and only other types allocate. That is a fine implementation note, but it must not appear as a semantic rule in the spec. The spec should say only "renders via `display()`".
>
> **Additional point (hover text).** The tooling-visible signature must be the true generic one (DevOps). Models read hover text and signatures, so a hidden check (DevOps 3, PLT P3) would reintroduce the mismatch this ticket exists to close.
>
> STABLE — ready to vote

**Minimalism:**

> **V1: `print_raw` / `eprint_raw`.** I revise my position. My Phase A reason was "raw means no formatting". AI/ML says that only the newline differs, and Sys says raw is byte-level. Those are two different meanings, and I have not seen the spec define it. A `Str`-only exception adds a rule, and that costs more than one uniform bound. I now favor `T: Display` for every text sink, on one condition. The spec must state what "raw" means, and if it means "not a text render", the exception stays. I will check `sections/04_effects.md` before the vote. If raw means only "no newline", I vote uniform `Display`.
>
> **V2: diagnostic code.** I agree with PLT. One code, E0523, at every sink. The generic bound error E0306 must not surface for `write` or `io.*`. Otherwise one mistake gets two error codes. The message names the sink, and the span is the argument (DevOps).
>
> **V3: my decision 7 flag.** I withdraw it, with a condition. Sys and PLT are right: the bound sits on the wrapper, and the effect op stays first-order on `Str`. The spec must say that `io.*` are stdlib wrappers of the form `fn println[T: Display](x: T) with IO.Print`. It must also say that the handler op takes `Str`. Without those two sentences, someone will read decision 7 strictly later. I drop B0 as a fallback and keep it only as a rejected option.
>
> **V4: spec text.** I agree with all of it. I add two points.
> - The intrinsic seam is a closed list: the `Display` impls for `Str`, `Int`, `Float`, `Bool` and `Char`. The spec must name them. No other type may use an intrinsic `fmt`.
> - The spec must state that `Str.fmt` appends directly and does not call `write`. This removes the `fmt` to `write` to `fmt` cycle that Web flagged.
>
> **Other panelists.**
> - DevOps says the codegen fast path for `Str` and `Int` is allowed. I agree, only as an optimization with the same observable behavior. It must not become a new special case in the type rules.
> - AI/ML's Proposal C (`write_display`) is rejected by its author. I agree.
>
> **STABLE — ready to vote**, on the condition that the spec defines "raw" (V1) and adds the two decision 7 sentences (V3).

#### Phase C — Final vote

The ballot, as sent:

> Phase B round 1 closed with 5 of 6 "STABLE — ready to vote" (Sys, Web, PLT, AI/ML, Min; DevOps: "NOT STABLE. V1 is open: the spec must say what `print_raw` does").
>
> ## Fact (moderator-supplied, several panelists asked for it)
> sections/04_effects.md, verbatim:
> - Table rows: `io.print_raw(x) | raw stdout, no newline | Vtable-dispatched: No | Handler-interceptable: No | Trace: No` and `io.eprint_raw(x) | raw stderr, no newline | No | No | No`.
> - `io.eprintln(x)` and `io.eprint(x)`: Vtable-dispatched No, Handler-interceptable No, Trace Yes.
> - Prose: "The `_raw` variants are escape hatches for cases where direct C output is needed (e.g., streaming JSON fragments, progress indicators). They bypass the effect handler system entirely and emit no trace effects. Prefer `io.print`/`io.println` for application code; reserve `_raw` for low-level tooling."
> - The spec does not define "raw" further. Current compiler maps `print_raw` to the same C function as the no-newline default print (`io_default_print_no_nl`). Existing uses in src/cli.bl pass Str literals and interpolated strings.
>
> ## Ballot — vote privately. Do not edit files. For EACH question give:
> 1. Vote (option label)
> 2. Reasoning (2–4 sentences, your domain)
> 3. Concern (one sentence: what could go wrong with the option that wins, from your POV)
>
> **Q1 — `sb.write` signature.**
> - W-D: `fn write[T: Display](self, x: T)` on sealed `StringBuildOps`, lowers to `x.fmt(sb)`; prelude `Display` impls for `Str`, `Int`, `Float`, `Bool`, `Char` with compiler-provided `fmt` (the closed intrinsic seam; `Str.fmt` appends directly, never via `write`); `write_char(self, c: Char)` unchanged.
> - W-S: `write(self, s: Str)` only.
>
> **Q2 — `io.print`, `io.println`, `io.log`, `io.eprint`, `io.eprintln` argument.**
> - IO-D: `T: Display`; stdlib wrapper renders via `display()` before the effect op; handler op signatures stay `msg: Str`.
> - IO-S: `Str` only; user writes `io.println("{x}")`.
>
> **Q3 — `io.print_raw` / `io.eprint_raw` argument.**
> - RAW-D: `T: Display`, same as the other io sinks.
> - RAW-S: `Str` only.
>
> **Q4 — how the E0523 code is produced at these sinks** (all six agreed E0523, sink named in the message, span on the argument).
> - DX-G (PLT): a `Display` bound failure at ANY generic call site reports E0523; E0306 stays for other traits.
> - DX-N: `write` and `io.*` report E0523 by name; other generic call sites keep E0306 for a `Display` bound failure.
>
> **Q5 — spec text on `Str` pass-through in `io.*`.**
> - PT-S (Sys; Web: "The spec should say so once"): the spec states a `Str` argument passes through with no copy, and a non-`Str` argument is rendered into one `Str` (one alloc) and the op is called once.
> - PT-N (AI/ML): the spec says only "renders via `display()`"; no-copy for `Str` is an implementation note, not a semantic rule.

Tally:

- **Q1 — `sb.write` signature:** W-D, 6-0.
- **Q2 — `io.print`/`println`/`log`/`eprint`/`eprintln` argument:** IO-D, 6-0.
- **Q3 — `io.print_raw`/`eprint_raw` argument:** RAW-S, 6-0.
- **Q4 — how E0523 is produced:** DX-G, 6-0.
- **Q5 — pass-through wording:** PT-N, 4-2 (Systems and Web/Scripting dissent, for PT-S).

Ballots, verbatim:

**Systems:**

> **Q1: W-D** — Reasoning: Decision 1 forces `sb.write(x)` to lower to `x.fmt(sb)`. Monomorphizing a bounded generic gives a direct call per type, with no boxing, no vtable and no intermediate `Str`. The closed intrinsic seam is the only compiler-provided `fmt`. It is small and auditable. It also lets the interpolation special case in codegen go. Concern: Each distinct `T` adds an instance, and a careless `Str.fmt` that routes through `write` would make the base case unreachable.
>
> **Q2: IO-D** — Reasoning: The handler ABI stays one monomorphic `Str`, so there is no per-`T` handler machinery. Non-`Str` arguments cost one allocation. That is the same cost as `io.println("{x}")` today, so nothing is hidden. `Str` arguments pay nothing extra. Concern: A wrapper written as `x.display() + "\n"` would add a second allocation, so the spec must require the newline-op form.
>
> **Q3: RAW-S** — Reasoning: The spec says `_raw` bypasses the handler system, the vtable and the trace. It is an escape hatch for low-level output. It should skip all rendering machinery too, and a `Str`-only signature makes that visible in the type. The rule follows an existing boundary: `print` and `println` are the interceptable sinks, and `_raw` is not. I move here from my Phase B lean because the fact confirms the bypass meaning. The cost is a `"{x}"` at rare call sites. Concern: `eprint` and `eprintln` also skip handlers but stay `Display`. The spec must say the split is by `_raw` and not by handler interception, or the boundary will look inconsistent.
>
> **Q4: DX-G** — Reasoning: One rule for every generic call site needs no per-sink code in the checker. It is predictable and cheap to implement. A by-name rule adds special cases for `write` and `io.*`, and those cases would grow. Concern: Existing tests or docs that expect E0306 for a `Display` bound at other call sites will change.
>
> **Q5: PT-S** — Reasoning: Cost is part of the contract in a systems language. Stating "a `Str` argument passes through with no copy, and a non-`Str` argument is rendered once into one `Str`" gives users a predictable model. It also stops a wrapper from adding allocations later. It needs `Str.display()` to be the identity, and the spec should say that. Concern: It pins a rule that later constrains alternative implementations, such as a builder-backed print path that skips the intermediate `Str`.

**Web/Scripting:**

> **Q1: W-D**
> Decision 1 requires `sb.write(x)` to lower to `x.fmt(sb)`, so `write` has to take a `Display` bound. The generic signature also matches the hover text and the docs. A bound is not overloading, so decision 3 is unaffected.
> Concern: users who see a generic signature on the simplest method may worry about compile time or code size.
>
> **Q2: IO-D**
> `io.println(42)` is the first thing a JS or Python developer types. Failing it would create a Stack Overflow question on day one. The handler ABI stays `Str`, so effects are unaffected.
> Concern: a non-`Str` `println` allocates silently, and users may not expect that.
>
> **Q3: RAW-S**
> The spec says `_raw` is an unintercepted, untraced escape hatch for low-level output. The `Str`-only rule follows the effect boundary, which is easy to teach. Few users will write `_raw` in application code. I only weakly prefer RAW-S over RAW-D.
> Concern: `io.print_raw(42)` fails while `io.print(42)` works, so the error message must hint at `"{x}"`.
>
> **Q4: DX-G**
> One rule ("a `Display` bound failure reports E0523") is easier to learn than a per-sink list. It also holds for user-written generic wrappers such as `log_to(sb, x)`. Under DX-N, the same mistake in a user wrapper would give a different code.
> Concern: E0306 no longer signals a `Display` failure, so tooling or docs that key on E0306 may need updates.
>
> **Q5: PT-S**
> The no-copy path for `Str` is behavior that users observe, and the spec should say it once. Whether it is a semantic rule or a note is a minor question. What matters is that the spec is honest about the allocation for non-`Str` arguments.
> Concern: if the spec makes no-copy a rule, later implementations are locked into it.

**PLT:**

> **Q1: W-D** — Reasoning: A bounded-generic `write` has a checkable typing rule, `T: Display ⊢ sb.write(x) : Void`. It is not overloading, so decision 3 holds. It fixes the missing bound check that lets `sb.write(P{x:1})` pass today. It also makes the stdlib migration possible. W-S contradicts decision 1. Concern: The primitive `Display` impls are compiler-provided and cannot be written in Blink, so the spec must state that closed list exactly.
>
> **Q2: IO-D** — Reasoning: Conversion is pure and happens before the perform, so `T` never reaches the handler. Handler ops stay first-order on `Str`. The bound sits on the wrapper, so decision 7 holds. IO-S adds nothing type-theoretic and worsens the error surface. Concern: If the wrapper concatenates a newline (`display() + "\n"`), it costs an extra allocation. Implement it with the newline op (`print` versus `print_no_nl`).
>
> **Q3: RAW-S** — Reasoning: The spec shows `_raw` is not handler-interceptable and has no trace. It bypasses the effect system, so the wrapper argument for `Display` does not apply. The boundary "interceptable means `Display`, bypass means `Str`" follows the effect system and is easy to state. The `eprint` and `eprintln` sinks are also not interceptable, but the spec keeps them in the ordinary print family and they emit traces. `Display` is the right rule for them, so the boundary is `_raw`, not "interceptable". Concern: `io.print_raw(42)` gives a bare type mismatch unless the diagnostic hints `"{x}"`.
>
> **Q4: DX-G** — Reasoning: A rule keyed on the trait applies at every generic call site with no per-sink code. DX-N is the checker special case I rejected as P3 in Phase A. Users cannot reproduce it in their own wrappers, and it does not compose. Concern: Changing the generic-bound mapping for `Display` alters E0306 output at existing call sites, so tests that assert E0306 need a sweep.
>
> **Q5: PT-N** — Reasoning: Whether `Str` is copied is a cost model, not a typing or semantic rule. The spec should promise only the observable behavior: a handler sees the same `msg` for `println(42)` and `println("42")`. Requiring no-copy in the spec would restrict future implementations for no semantic gain. Concern: Without a stated cost, users may assume `io.println(str)` allocates, but the implementation note can cover that.

**DevOps:**

> **Q1: W-D** — Reasoning: The hover and signature help show the true generic signature, and the LSP and docs agree. Completion for `impl Display for` works the same at every sink. The rule sits in the trait, so the stdlib chore has no permanent compiler special case. W-S contradicts decided item 1. Concern: The intrinsic seam is closed at five types, so a user-defined primitive-like type cannot get a fast `fmt`, and hover on `Str.fmt` shows no body.
>
> **Q2: IO-D** — Reasoning: `io.println(42)` is the first line users write. IO-S would need a special "wrap in interpolation" hint, which is a diagnostic patch over a design gap. IO-D also gives one error code and one message shape across interpolation, `write` and `io.*`. Concern: The wrapper renders before the op, so a handler cannot tell `println(42)` from `println("42")`. Tests must pin that the handler-visible `msg` is identical.
>
> **Q3: RAW-S** — Reasoning: I withdraw my round-1 move to Display. The moderator fact settles it: `_raw` is a spec-defined escape hatch that bypasses the handler system and trace, so the boundary follows the effect system. `eprint` and `eprintln` are traced and stay on `Display`. The rule is short: interceptable and traced sinks take `Display`, bypass sinks take `Str`. That is a spec line, not a hidden hole. Concern: `io.print_raw(42)` gets a plain type mismatch, not E0523. Add a tested help line, "wrap with `"{x}"`", and put the exception in the spec table row.
>
> **Q4: DX-G** — Reasoning: Naming `write` and `io.*` in the checker is a per-sink special case (PLT's P3 again). It does not extend to user wrappers such as `log_to(sb, x)`. A `Display` bound failure at any generic call gives one code with no hidden list. A user wrapper `fn log_to[T: Display](sb, x: T)` then reports E0523 too. Concern: E0306 behavior for `Display` changes for existing generic code. Sweep the tests and the diagnostic explain text (`diag_explain`) for it, and check the new message still names the callee.
>
> **Q5: PT-N** — Reasoning: Tools and docs need one semantic rule: "renders via `display()`". Whether `Str` passes through with no copy affects cost, not typing or the handler-visible `msg`. I do not want the observable contract to depend on an allocation detail. The spec can state `Str.display()` is identity as a normal method fact. Then no-copy follows without a special rule. Concern: Without a stated cost model, a later implementation may allocate on every `println("plain")` without breaking any spec rule.

**AI/ML:**

> **Q1: W-D** — Reasoning: `sb.write(x)` is already decided as a call shape, and one generic bound is a single rule to learn. It matches what models know from Rust. The signature that hover text and the spec show is the true one, and the intrinsic seam is a closed list of five impls. Concern: `Str.fmt` could still leak through `write` and recurse, so the spec and a test must pin the direct append.
>
> **Q2: IO-D** — Reasoning: `io.println(42)` is the most common first line, and `Str`-only makes it fail. One rule for all text sinks gives one lesson and one repair pattern. Handler ops stay `msg: Str`, so effect handlers do not change. Concern: a reader may take the wrapper's render step as a change to the handler contract, so the spec must state that handlers still see only `Str`.
>
> **Q3: RAW-S** (revision from round-1 RAW-D) — Reasoning: The moderator's fact shows the spec calls `_raw` an escape hatch that bypasses the effect system, for low-level tooling only. Existing uses already pass `Str`. Models will rarely write `_raw` by reflex, so the extra rule costs little. A boundary tied to "bypasses handlers" is teachable. Concern: `eprint` and `eprintln` are also non-interceptable but take `Display`, so the boundary is really "`_raw` means raw" and not "non-interceptable". The spec must name the `_raw` variants explicitly and the diagnostic must hint `"{x}"`.
>
> **Q4: DX-G** — Reasoning: A uniform rule (a `Display` bound failure gives E0523 everywhere) means no per-sink special case. User-written wrappers such as `fn log_to[T: Display](sb, x)` get the same code as the stdlib sinks. Models then see one code for one mistake, whichever generic function they call. Concern: E0306 messages that other tools or docs quote for `Display` failures will change, so tests must be updated.
>
> **Q5: PT-N** — Reasoning: The spec should define what a program can observe. Handlers see the same `msg` for `println(42)` and `println("42")`, so no-copy is not observable. A copy-count rule in the spec would freeze an optimization and add text that models must read for no benefit. Concern: Without a semantic rule, someone may later add a copy on the `Str` path and cause a performance regression that no test catches.

**Minimalism:**

> **Q1: W-D** — Reasoning: decided item 1 already makes `sb.write(x)` a call shape, so W-S is not eligible. W-D removes the spec contradiction and the codegen special case. The five primitive `Display` impls are a closed, named seam. Concern: the intrinsic list must stay closed at these five types, or the seam grows into a second dispatch mechanism.
>
> **Q2: IO-D** — Reasoning: one rule ("`Display` is the only conversion to text") is a smaller surface than a per-sink table. The bound sits on the stdlib wrapper. The op stays first-order on `Str`, so decision 7 holds. Concern: a stderr sink (`eprint`) takes `Display` but bypasses handlers. A reader may assume "interceptable" and "`Display`" always go together, and the spec must say they do not.
>
> **Q3: RAW-S** — Reasoning: I read 04_effects.md before voting. It calls `_raw` an "escape hatch", "low-level tooling", and says it bypasses the effect system entirely. That gives a boundary that follows the effect system, and it adds no new rule, only a spec line. This reverses my round-1 lean toward uniform `Display`. That lean was conditional on `_raw` meaning only "no newline", and the spec text does not say that. A `Str`-only bypass path is also the smaller surface. Concern: `print_raw(42)` gets a plain type error, so the spec row needs a note that `_raw` takes `Str`, or users will file it as a bug.
>
> **Q4: DX-G** — Reasoning: a name-keyed rule for `write` and `io.*` is a checker special case. It is P3 again. A `Display` bound failure reporting E0523 everywhere is one rule, and user-written wrappers such as `log_to(sb, x)` get the same code for free. Concern: E0306 may have existing tests or docs for `Display` bound failures, and the change must update them in the same commit.
>
> **Q5: PT-N** — Reasoning: the spec should promise only "renders via `display()`". A no-copy rule for `Str` becomes a semantic guarantee that every future implementation must keep. It is an optimization, and optimizations belong in implementation notes. This matches what I said about the codegen fast path: it must not become a rule. Concern: without a spec line, a handler test double could see different behavior for `println(42)` and `println("42")` if an implementation drifts. Add a one-line test that both paths give the same `msg`, as DevOps asked, and it needs no spec text.

#### Phase D — not run

Q5 finished 4-2, which would trigger Phase D. The moderator reported it to the user as soft consensus instead: every majority ballot's Concern names the dissent's risk (an unstated cost, or a later copy on the `Str` path that no test catches), and the majority ballots name the repair: DevOps asks the spec to state `Str.display()` as the identity, and Minimalism asks for a test that a handler sees the same `msg` for `println(42)` and `println("42")`. **The user accepted the ruling** with that rider. The dissent is recorded above; the rider went into the spec as a method fact plus an implementation note, not as a cost rule.

### Final Spec

```blink
trait StringBuildOps {
    fn write[T: Display](self, x: T)     // x.fmt(self)
    fn write_char(self, c: Char)         // unchanged, not a Display path
    // to_str, len, capacity, clear unchanged
}

// io functions: stdlib wrappers over Str-typed handler operations
// io.print(x)      io.println(x)      io.log(x)   -- T: Display, interceptable
// io.eprint(x)     io.eprintln(x)                 -- T: Display, not interceptable
// io.print_raw(s)  io.eprint_raw(s)               -- Str only

// handler operations
handler IO.Print {
    fn print(msg: Str)          // called by io.println
    fn print_no_nl(msg: Str)    // called by io.print
}
handler IO.Log {
    fn log(msg: Str)
}
```

- **`sb.write` is generic over `Display` (Q1).** This is a bound, not an overload. `sb.write(x)` lowers to `x.fmt(sb)`; a `Str` argument is one `Display` type among five. The §3.2 "signature is unchanged" sentence now reads as a `T = Str` instance of the generic signature; the 4-1 interpolation-optimization vote stands.
- **The intrinsic seam is closed and named once (Q1).** `Int`, `Float`, `Bool`, `Str` and `Char` have prelude `Display` impls with compiler-provided `fmt` bodies. `Str.fmt` appends directly and never calls `write`. No other `fmt` body is intrinsic. §3.6 *Display Format Protocol*.
- **`io` functions take `T: Display` (Q2).** Each renders via `x.display()`, then calls the handler operation. The wrapper picks `print` or `print_no_nl`; it does not append a newline to `msg`. Handler operations take `msg: Str`, and §4.4 now states them.
- **`_raw` takes `Str` (Q3).** The split follows the `_raw` name, not interceptability: `io.eprint` is not interceptable and still takes `Display`. A non-`Str` argument is `error[TypeError]` with a help line that suggests `"{x}"`.
- **A failed `Display` bound is E0523 everywhere (Q4).** At `"{x}"`, `sb.write`, the `io` functions and any user generic with a `Display` bound. E0306 remains the code for every other trait. The message names the sink; the span covers the argument. A `Raw[T]` argument still reports `RawOutsideTemplate`.
- **Pass-through (Q5).** The spec says "renders via `display()`". `Str.display()` returns a `Str` equal to the receiver; not copying it is an implementation note. A handler sees the same `msg` for `io.println(42)` and `io.println("42")`.
