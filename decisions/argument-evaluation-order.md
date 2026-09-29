[< All Decisions](../DECISIONS.md)

# Argument Evaluation Order — Design Rationale

**Gap:** the spec did not say in what order a call evaluates its arguments, or in what order binary operands, interpolation holes, literal elements and assignment targets evaluate. Codegen passed arguments as C call arguments, and C leaves their order unspecified. Measured with gen1 on 2026-09-27: `f(b: tick(2), a: tick(1))` bound in parameter order, `"{g2()} {g2()}"` printed "202 101", and `bump() + n * 100` read `n` before `bump()` ran. §2.13 also said "The formatter enforces declaration order at call sites for consistency", which the formatter never did, and §2.19 defined `x += rhs` as a purely syntactic rewrite, which evaluates `xs[next()]` twice.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Each panelist's text below is quoted in full, as written.

#### Phase A — Independent proposals

- **Systems:**

> # Systems (Sys) panel proposal: evaluation order
>
> ## P1: Strict written order, left to right, everywhere (recommended)
>
> **Rule (spec text).** Every expression evaluates its direct sub-expressions exactly once, in the order they are written in the source, left to right. Each sub-expression finishes, side effects and any panic included, before the next one starts. This covers:
>
> - **Calls.** The callee expression goes first, then the receiver for a method call, then the arguments in written order. Keyword arguments follow the same rule: `f(b: x(), a: y())` runs `x()` before `y()`. Defaults for omitted keyword parameters are const expressions, so when they are filled in cannot be observed.
> - **Operators.** For binary operators, the left operand is evaluated before the right. The desugared `Add.add(x, y)` keeps this order. `&&`, `||` and `??` keep their conditional right side.
> - **Variable reads.** A read of a variable is an evaluation, and it happens at its written position. In `bump() + n * 100`, `n` is read after `bump()` returns.
> - **Interpolation.** Hole *i* is evaluated and pushed into the builder before the expression for hole *i+1* starts. In a `Template[C]` context the values list is built in the same order.
> - **Struct and list literals.** Fields and elements evaluate in written order. List spreads already work this way (§2.16).
> - **Assignment `place = rhs`.** The sub-expressions of the place (base, then index) go first, then `rhs`. The store happens last, and so does its bounds check. For `a[i()] += f()`, the rewrite to `x = x + rhs` must evaluate the place's sub-expressions once, not twice.
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
>
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1
>     let _ = tick(3) + tick(4)            // prints 3, then 4
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     io.println("{bump() + n * 100}")     // 101: n is read after bump()
>     io.println("{bump()} {bump()}")      // "2 3"
> }
> ```
>
> **What the hardware sees.** Nothing new. The IR lowering puts each argument into a temp, in written order. That is SSA-style lowering, and the IR is being built this way now. gcc and clang at -O2 remove the temps (SROA and register allocation) and reorder pure computations under the as-if rule anyway. Sequencing costs one extra mov at most, and usually nothing. We give up only the freedom to reorder calls that have side effects, and no competent backend uses that freedom for speed.
>
> **C printer rule.** An argument can stay inline as a C call argument only when it is an atom (a literal, an immutable local, or a parameter), or when it is the single non-atom in the call. Everything else goes into a temp. The effect row gives a second way out: an argument with an empty effect row that reads no mutable cell captured by a closure can stay inline. This keeps the C output small without making the order depend on the C compiler.
>
> A read of a `let mut` local can be clobbered by a call only if a closure captured it by shared reference (§2.8). The compiler knows this statically, so ordinary loop counters never get an extra temp.
>
> **Cross-language.** Java and C# fix full left-to-right order, and the JIT does not pay for it. Rust does the same for operands and arguments. Go fixes the order of calls but *not* of variable reads, so `a[i] + f()` with `f` changing `i` is unspecified. The ticket note's `bump() + n * 100` is exactly that hole, so do not copy Go's half rule. C and OCaml leave the order unspecified, and that is a well-known source of bugs that gives no measurable speedup. C++17 had to add order guarantees after the fact.
>
> ## P2: Formatter clause (required by P1)
>
> Under P1, moving keyword arguments to declaration order changes when their side effects happen. The §2.13 line "The formatter enforces declaration order at call sites" would make `blink fmt` change program behavior. Strike it. The formatter does not do this today. If the panel wants the reorder anyway, allow it only when every moved argument is an atom, so the reorder cannot be observed. Stripping side effects out of formatter output is a correctness bug.
>
> ## P3: Unspecified order, stated as such (rejected)
>
> I list this only to reject it. "Unspecified" makes the C backend a hidden part of the semantics: gcc evaluates arguments right to left on x86-64 in many cases, and clang often goes left to right. So the same Blink program gives different output from each C compiler, and the cross-compile path through zig cc could get a third order. That is under-determined behavior with no diagnostic, which the E0301 stance forbids. It also breaks the §3c promise that "evaluation order equal[s] source order."
>
> An effect-based conflict error ("two arguments both carry `! IO`") is too coarse. Nearly every IO call would trip it, and it misses the mutable-read case entirely. It gains no speed over P1.
>
> **Vote position: P1 + P2.**

- **Web/Scripting:**

> # Web/Scripting panelist: Phase A proposal
>
> I checked the premise against `02_syntax.md` §2.13 (lines 718-760) and `03c_protocols.md:32`. The brief is accurate. §2.13 also conflicts with itself: see P2.
>
> ## P1: Everything runs in written order, left to right
>
> **Rule (spec text).** An expression evaluates its subexpressions exactly once, in the order they appear in the source, left to right. This holds for:
> - **Calls:** the callee, then the receiver (for `recv.m(...)`), then each argument in written order. All of this finishes before the callee body runs.
> - **Binary operators:** the left operand runs completely before the right operand. This holds after the desugaring in §2.19, so `Add.add(x, y)` inherits the call rule. `&&`, `||` and `??` keep their short-circuit rules: when the right side runs, it runs after the left side.
> - **Interpolation:** holes run left to right, and each hole runs before the text after it is appended.
> - **Literals:** list elements (spreads included, as §2.16 already says), struct-literal fields, tuple elements and variant payloads run in written order. Written order applies, not declaration order.
> - **Assignment:** the subexpressions of the target place (receiver, index) run first, left to right. Then the right-hand side runs, then the store.
>
> Codegen may reorder only when no program can observe the difference. For example, it may skip a temp for an argument that has no effects and reads no `let mut` cell that another argument writes.
>
> ```blink
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
>
> fn g(a: Int, b: Int) -> Int { a + b }
>
> fn main() {
>     let _ = g(tick(1), tick(2))           // prints 1, then 2
>     let _ = tick(1) + tick(2) * tick(3)   // prints 1, 2, 3
>     io.println("{tick(4)} {tick(5)}")     // prints 4, 5, then "4 5"
>     let xs = [tick(6), tick(7)]           // prints 6, then 7
> }
> ```
>
> The ticket note's closure case:
>
> ```blink
> fn main() {
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     let r = bump() + n * 100   // bump() runs first: r = 1 + 100 = 101
>     io.println("{r}")
> }
> ```
>
> **Tradeoffs (DX).**
> - A JS/TS, Python, Kotlin or Java developer already assumes this rule. Nobody reads a spec to learn it. They find out only when it breaks, which means a Stack Overflow question and a lost afternoon. The `"202 101"` interpolation result in the ticket note is that bug report.
> - "Unspecified" is the C/C++ answer. It is the reason `i = i++ + ++i` is a famous interview question, and I want none of that in Blink. It also conflicts with §3.4/E0301: we refuse to guess in the type system, so we should not let the backend guess at runtime.
> - LLM-written code (see the AI panelist's ground) assumes left to right in every case. A rule the training data already expects costs nothing to teach.
> - Cost: codegen must hoist effectful arguments into temps, because C argument order is open. That is backend work, done once, and the C compiler removes the temps it does not need. Call lowering is being built in the IR now, so this is the cheapest time to add it.
>
> **Cross-language.** JS, Java, C#, Kotlin and Python all use left to right for calls and operators. Python is the outlier for assignment: it runs the right-hand side before the target. JS, Java and C# run the target first, and I follow them. Only C and C++ leave call order unspecified.
>
> ## P2: Keyword arguments run in written order, and the formatter rule goes
>
> **Rule.** Keyword arguments run in the order the caller writes them, not in declaration order. The callee then receives them in declaration order. Defaults are const expressions (§2.13), so where they are filled in does not matter.
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
>
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1
> }
> ```
>
> **Remove** this line from §2.13: *"The formatter enforces declaration order at call sites for consistency."* Under P1, reordering labels changes what the program does. A formatter must never change behavior, and the current formatter already keeps written order. If the panel wants declaration order, the only safe form is a lint (a warning with no auto-fix), never a rewrite. My recommendation: no lint. "Order-independent at call site" is the feature we advertise, and it is how Python and Kotlin work.
>
> **Cross-language.** In Python, C# and Kotlin, named arguments run in written order. Swift requires labels in declaration order, which removes the question, but Blink already chose to let callers reorder.
>
> ## P3: Compound assignment reads its target place once (a finding, not a new axis)
>
> §2.19 rewrites `x += rhs` to `x = x + rhs` as syntax. That is safe for a plain name. It is not safe for `xs[next()] += 1`, because the rewrite calls `next()` twice.
>
> **Rule.** For `place op= rhs`, the subexpressions of the place run once, left to right. Then `rhs` runs, then the operator, then the store.
>
> ```blink
> fn main() {
>     let mut i = 0
>     let next = fn() -> Int {
>         i = i + 1
>         i
>     }
>     let mut xs = [0, 0, 0]
>     xs[next()] += 10   // next() runs once: xs = [0, 10, 0]
>     io.println("{xs}")
> }
> ```
>
> A JS or Python developer would call two calls a bug on sight. In JS, Python and Kotlin, `a[f()] += 1` calls `f()` once. If the panel sees this as out of scope, it should get its own ticket.
>
> **Vote intent:** P1 and P2 together. P3 is a separate ticket if it is out of scope.

- **PLT:**

> # PLT panelist: Phase A proposal
>
> **Position:** evaluation order belongs in the dynamic semantics. Leaving it unspecified would make the meaning of a program depend on the backend, and that is exactly the under-determined behaviour §3.4/E0301 exists to forbid. I propose one rule (P1), two corrections it forces (P2, P3), and one option I reject (P4).
>
> ## P1: Strict left-to-right, call-by-value, everywhere (the rule)
>
> **Spec text (new §2.x "Evaluation Order"):**
>
> > Every compound expression evaluates its immediate sub-expressions exactly once, from left to right in *written* order, to values, before it performs its own action. The only exceptions are the control forms that are defined to be conditional: `&&`, `||`, `??`, `if`, `match`, loops. Concretely:
> > - **Calls:** first the callee, then the receiver (for a method call it is argument 0), then the arguments in written order. Keyword arguments are evaluated in written order and *then* bound to parameter positions. Omitted defaults are const (§2.21), so their placement cannot be observed.
> > - **Operators:** `a op b` evaluates `a`, then `b`, then calls the trait method. The desugaring `Add.add(a, b)` inherits the call rule, so this holds by construction.
> > - **Literals:** list elements, including spreads, tuple elements, and struct fields go in written order, not declaration order.
> > - **Interpolation:** holes are evaluated left to right. With `Template[C]`, the values list is built in the same order.
> > - **Assignment `place = rhs`:** the sub-expressions of `place` (receiver, index) are evaluated left to right, then `rhs`, then the store happens.
> > - **Early exit:** a `?` or a panic in sub-expression *i* means that sub-expressions *i+1..n* never run.
> > - An implementation may reorder only when the difference cannot be observed (the as-if rule).
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2 then 1
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     let g = bump() + n * 100            // 1 + 100 = 101
>     io.println("{bump()} {bump()}")     // "2 3"
> }
> ```
>
> **Typing and soundness:** the typing rules do not change. This fixes the big-step semantics, so each program gets exactly one meaning.
>
> It also composes. Every desugaring the spec already has (operators to trait calls, `??` to match, `with a, b` nesting, list spreads) keeps the order once it is stated for calls, because each one is defined as a call or as a sequence. The existing decisions (§2.16 spreads, §4.6.3 `with` items, §3c "eager keeps evaluation order equal to source order") become special cases of P1 and stop being ad hoc.
>
> **Why the effect system cannot stand in for this.** Effect rows do not track two things that make order observable:
> 1. writes to captured `let mut` cells (§2.8). `bump` above is effect-free by its row.
> 2. divergence. Overflow panics (§3), and which argument panics first is observable.
>
> So "pure arguments may evaluate in any order" is not a sound rule in Blink. Only an as-if proof that also covers state and divergence can justify a reordering.
>
> **Cost:** codegen binds arguments that are not trivial to temps in written order. The C compiler removes these temps for free, so this is not a performance argument.
>
> **Cross-language:** Java, C#, Kotlin, Swift, Python, JS and Koka use left to right. Rust uses left to right for calls. OCaml and Scheme leave the order unspecified, and OCaml evaluates right to left in practice. That is a known trap in ML code and a lesson for Blink, not a precedent.
>
> ## P2: Delete "The formatter enforces declaration order at call sites" (§2.13)
>
> Under P1, moving keyword arguments to declaration order changes the meaning of the program. A formatter must preserve semantics. The current formatter prints written order, so the sentence is already false today. Replace it with: "The formatter preserves written argument order."
>
> I also reject a narrower rule that reorders only literal or variable arguments. It adds a special case for a cosmetic gain.
>
> ## P3: Compound assignment evaluates the place once
>
> The purely syntactic rewrite `x += rhs` → `x = x + rhs` is unsound when the place has effects. `xs[next()] += 1` would call `next()` twice.
>
> **Amend §2.19:** the rewrite applies to a place whose sub-expressions have first been bound to fresh temps in written order, so `xs[next()] += 1` means `let i = next()` then `xs[i] = xs[i] + 1`. When the place is a bare variable, this is the same as today's rewrite.
>
> (Rust and Python both evaluate the place once. C# does too.)
>
> ## P4 (rejected): "unspecified, stated as such"
>
> Stating the order as unspecified turns a determinism bug into a documented one. It is also inconsistent with three decisions already taken (§2.16, §4.6.3, §3c:32) and with the E0301 stance.
>
> A variant that flags interfering sibling arguments at compile time is also rejected. It cannot be sound without an effect or region system that tracks captured-cell writes and divergence, and Blink does not have one.
>
> **Vote intent:** P1 + P2 + P3 as one package.

- **DevOps/Tooling:**

> # DevOps/Tooling proposals: argument evaluation order (bwmxbg)
>
> My test for every option: can `blink fmt`, the LSP and the diagnostics stay correct under it? The formatter cannot change what a program does, and a user must be able to read the order things run from the source text.
>
> ## P1: Written order, left to right, for every call (positional and keyword)
>
> **Rule:** A call evaluates its callee, then its receiver (for method calls), then each argument in the order written in the source, left to right. It evaluates each one fully before it starts the next. After that it binds the values to parameters by position or label, then calls. Keyword labels control only where a value binds. They do not control when the value is evaluated. Default values are const expressions (§2.21), so they have no order.
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1
>     let _ = f(tick(1), tick(2))         // positional: prints 1, then 2
> }
> ```
>
> **Spec change this requires:** remove "The formatter enforces declaration order at call sites" from §2.13. Under written order, a formatter that reorders keyword arguments changes program output. That breaks the formatter's semantic-preservation invariant, which `test-fmt` already checks. The current formatter (src/formatter.bl, NamedArg case) keeps written order, so the code already follows the corrected spec.
>
> **What replaces it:** a lint, `KeywordArgOrder` (warning, off by default or `@allow`-able). Its autofix is offered only when every argument it moves is a literal, a local name or a field read. Otherwise it shows the warning with no fix and explains why:
>
> ```
> warning[KeywordArgOrder]: keyword arguments differ from declaration order
>   --> main.bl:7:13
>    |
>  7 |     let _ = f(b: tick(2), a: tick(1))
>    |               ^^^^^^^^^^^^^^^^^^^^^^ declared order is `a`, `b`
>    = note: arguments run in written order; reordering would run tick(1) first
>    = help: bind to `let` first if the order matters
> ```
>
> **Tradeoffs:**
> - The formatter stays semantics-preserving, with no purity analysis.
> - A debugger stepping through a call, `--trace` NDJSON output, and the order of panics (overflow is checked, §3) all follow the text.
> - LSP inlay hints and "go to parameter" do not have to show a second, hidden order.
> - Cost: codegen must hoist arguments into temps when C's unspecified order could show. The IR rewrite is building call lowering now, so this is the cheapest time to add it.
>
> **Cross-language:** Java, C#, Kotlin, Swift and Python all use written order, including for named arguments. Kotlin had to add temps for named arguments to do this. Its IDE issues a "named arguments out of order" hint, but its formatter never reorders.
>
> ## P2: One rule, "written order", for every compound expression
>
> **Rule:** Unless a construct is short-circuiting (`&&`, `||`, `??`, `if`, `match`), it evaluates its operands left to right in source order:
> - Binary operators: left operand, then right. `x + y` is `Add.add(x, y)`, so P1 already covers it.
> - Interpolation: holes in text order, left to right, including `fmt(sb)` pushes and `Template[C]` value lists.
> - Struct literals: fields in written order, not declaration order. The formatter does not reorder them, for the same reason as P1.
> - List literals: elements left to right. This makes the §2.16 spread rule a case of this one rule.
> - Assignment `p = rhs`: first the place's subexpressions (base, then index or field path), then `rhs`, then the store.
>
> ```blink
> fn main() {
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     let g = fn() -> Int { bump() + n * 100 }
>     io.println("{g()}")                 // prints 101
>     io.println("{bump()} {bump()}")     // prints "2 3"
> }
> ```
>
> **Tradeoffs:** users learn one sentence instead of eight rules. The same sentence covers LSP hover text, docs (`blink llms --topic`) and error explanations. Today's measured "202 101" and `g() == 1` become bugs with MVCEs, and the ticket-note test row that sequences the call with a `let` can drop that workaround later.
>
> **Cross-language:** Java (JLS 15.7) and C# do this for all of the above. Python does too, except that it evaluates the assignment RHS first. Rust evaluates a simple assignment's RHS first too, so we should choose on purpose here. I pick place first because it matches reading order.
>
> **Flagged sub-issue:** §2.19 rewrites `x += rhs` to `x = x + rhs`. With `a[next()] += 1`, `next()` runs twice. The spec must say that the place is evaluated once, or reject side-effecting places in compound assignment with a named diagnostic. Otherwise P2's assignment rule and the rewrite contradict each other. This needs a separate ticket if the panel does not want it in scope.
>
> ## Rejected: "unspecified, stated as such"
>
> Tooling cannot support this. No lint can soundly find two interfering arguments, because closures mutate captured `let mut` (§2.8) with no effect annotation. `blink fmt`, the debugger and the trace would each be free to disagree with the compiler. That also goes against the E0301 stance that under-determined behavior is an error, not a silent guess.

- **AI/ML:**

> # AI/ML panelist: Phase A proposal
>
> ## P1: One rule: source order, left to right, everywhere (recommended)
>
> **Rule (spec text):**
>
> > **Evaluation order.** An expression evaluates its operand sub-expressions exactly once, left to right, in the order they appear in the source text. It then performs its own operation. Only these constructs do not evaluate every operand unconditionally: `&&`, `||`, `??`, `if`/`match` arms, and closure bodies. For those, the right operand, arm, or body runs only as §2.19, §3.5, and §2.8 say. The rule covers:
> > - **Calls:** the callee expression, then the receiver (for a method call), then the arguments in written order. Keyword arguments also use written order, and bind to parameters only after all arguments are evaluated. Default values are const expressions (§2.21), so they have no order.
> > - **Operators:** these desugar to trait calls (§2.19), so `x + y` evaluates `x`, then `y`, then calls `Add.add`.
> > - **Literals:** list elements, struct-literal fields, variant payloads, and tuple elements go in written order.
> > - **Interpolation:** holes go left to right. A hole's value is appended before the next hole is evaluated.
> > - **Assignment:** `a[i] = v` and `s.f = v` evaluate the target's sub-expressions (`a`, then `i`) first, then `v`, then store. `x += rhs` rewrites to `x = x + rhs`, so `x` is read before `rhs`.
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
>
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1 (written order)
>     let _ = tick(1) + tick(2)           // prints 1, then 2
>
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     let g = fn() -> Int { bump() + n * 100 }
>     io.println("{g()}")                 // 101: bump() runs before n is read
>     io.println("{bump()} {bump()}")     // "2 3"
> }
> ```
>
> **Tradeoffs (AI/ML view):**
> - **Learnability:** it is one sentence with a closed list of exceptions, and the exceptions are the short-circuit and branch forms every model already knows. It adds no decision points, because the model never has to ask "is this safe to write inline?"
> - **Prior match:** LLMs learned from Python, JS, Java, Kotlin, C# and Swift. All of them evaluate call arguments and binary operands left to right. Models already write `f(next(), next())` and `"{pop()} {pop()}"` and expect written order. Under "unspecified", every such line that works on the model's prior is a latent bug. No diagnostic finds it, and it can flip when the C compiler or optimisation level changes. That is the "silent wrong program with a green build" that §3c.32 and E0301 already reject.
> - **Token cost:** it is zero. The other option makes the model (and users) sequence effects with `let` temps, which costs about 3 to 10 extra tokens for each affected call. The ticket note shows the repo already paying this in `test_arena_closure_tail_outlives_reused_arena`.
> - **Debuggability:** `--trace` output and `io.println` order match the text the model reads. Explaining a trace means no reasoning about the C level.
> - **Cost:** the codegen hoists effectful arguments into temps in written order. The call lowering in the IR is being built now, so this is the cheapest time to do it. Pure arguments and plain variable reads need no temp, and the C compiler can still reorder them freely.
>
> **Cross-language:** Java (JLS §15.7), C#, Kotlin, JS and Python use left to right for arguments and operands. C# and Kotlin keep written order for named args, which is the same choice as here. Go is the warning case: it fixes order only for calls and channel ops, and leaves other operand order open, which is a known FAQ trap. Rust and Python evaluate the right side of an assignment first. P1 chooses pure text order so that the rule has no special case.
>
> ## P2: The formatter must not reorder keyword arguments
>
> Delete "The formatter enforces declaration order at call sites" from §2.13 and replace it with:
>
> > The formatter keeps keyword arguments in written order. A reorder would change evaluation order (P1), and a formatter must not change program meaning.
>
> The current formatter already behaves this way (measured fact), so this change only brings the spec in line with the code.
>
> **Tradeoff:** AI-generated code often goes through `blink fmt` automatically. If a semantic-changing formatter step sits in that pipeline, a model cannot find the bug by reading its own output. We lose uniform declaration-order call sites. If we want that, a style lint (a warning with no autofix) can offer it later.
>
> ## P3 (considered, rejected): "Unspecified" stated in the spec, with or without a diagnostic
>
> - **Unspecified, no diagnostic:** this leaves an under-determined behaviour with no error, which breaks the E0301 stance. From the spec alone, a model cannot tell which of its programs are wrong.
> - **Unspecified plus an error when two operands have interfering effects:** closures mutate captured `let mut` bindings with no effect row (§2.8, as `bump` above does), so the check needs alias analysis. False positives would add a new decision point and a repair pattern to every call site that has two calls in it. That costs more tokens and more mistakes than P1 costs the codegen.
>
> **Vote intent:** P1 + P2.

- **Minimalism:**

> # Minimalism (Min) — Phase A proposal
>
> I push for one rule that covers every case, with nothing special per construct. Most of this ticket's options would add surface. The right answer here removes some.
>
> ## P1: One rule for every expression, left to right (recommended)
>
> **Rule (for a new §2.x, "Evaluation Order"):**
>
> > An expression evaluates its operand subexpressions exactly once, one at a time, in the order they appear in the source text, left to right. It finishes each one before it starts the next. Then it does its own operation. The only exceptions are forms the spec defines as conditional: `&&`, `||`, `??`, `if`, `match`, and guards. Their skipped operands are not evaluated.
>
> What "operands in source order" covers, as consequences of the rule, not as extra rules:
> - **Calls:** callee, then arguments as written. For keyword args that means **written order**, not declaration order.
> - **Method calls:** receiver, then arguments.
> - **Binary operators:** left, then right. `x + y` is `Add.add(x, y)`, a call, so this follows from the call rule anyway.
> - **Interpolation:** holes left to right. Each hole's `fmt(sb)` push happens in order.
> - **Literals:** struct fields as written, and list elements and spreads left to right. §2.16's spread sentence becomes one example of this rule.
> - **Assignment:** the target's subexpressions (index, receiver), then the right-hand side, then the store.
>
> ```blink
> fn f(-- a: Int, b: Int) -> Int { a + b }
> fn tick(n: Int) -> Int {
>     io.println("{n}")
>     n
> }
>
> fn main() {
>     let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1
>     let _ = tick(1) + tick(2)           // prints 1, then 2
>     io.println("{tick(1)} {tick(2)}")   // prints 1, 2, then "1 2"
>
>     let mut n = 0
>     let bump = fn() -> Int {
>         n = n + 1
>         n
>     }
>     let g = fn() -> Int { bump() + n * 100 }
>     io.println("{g()}")                 // 101: bump() runs before n is read
> }
> ```
>
> **Tradeoffs (subtraction lens):**
> - **One sentence replaces many.** The spec already sets order piece by piece: spreads in §2.16, `with` items in §4.6.3, and eager adapters "equal to source order" in §3c. A general rule makes all three special cases of one statement. Without it, each new construct needs its own vote. C++17 is the warning here: P0145 added separate order rules for `<<`, `=`, `.`, `[]` and still left function arguments unsequenced.
> - **"Unspecified" is not the smaller choice.** It brings in a new concept the language does not have: behavior the program cannot observe the same way twice. It also goes against the E0301 stance that under-determined behavior is an error, not a guess. §2.8 lets closures mutate captured `let mut` without an effect in the row, so the compiler cannot detect the hazard. So "unspecified" means silent bugs that change with the platform. The only way out is a lint or diagnostic, and that is more surface than the rule.
> - **Implementation cost is one lowering rule.** The IR under construction already names intermediate values. When an argument can have side effects, the lowering binds it to a temporary in source order. The C compiler removes the temporaries for pure arguments, so runtime cost is close to zero.
> - **Keyword args in written order** keeps "labels are call-site sugar" true: the reader sees the order that runs. Declaration order would be a second rule, one the reader can only check by opening the callee. Defaults are const expressions (§2.21), so the order of filled-in defaults is not observable and needs no rule.
>
> **Cross-language:** Java, C#, JavaScript, Python, Kotlin and Swift use left to right as the one general rule. Go specifies left to right only for calls, method calls and channel operations, and leaves the rest open. That gap is a well-known Go pitfall, and this proposal is the full version of Go's rule. OCaml leaves order unspecified and in practice goes right to left, which surprises users all the time.
>
> ## P2: A cleanup that comes with P1 (delete a sentence)
>
> **Rule:** Strike "The formatter enforces declaration order at call sites for consistency" from §2.13. Add: *"The formatter never reorders arguments. Under §2.x, the order of arguments is the order of evaluation."*
>
> Under P1, a formatter that reorders keyword args would change what a program does. The sentence was never implemented either: src/formatter.bl prints keyword args in written order. So deleting it makes the spec match the code and removes a trap.
>
> If someone wants declaration order as a *style*, it should be an opt-in lint that fires only when every keyword argument is side-effect free. I recommend we don't build that lint until someone asks for it (YAGNI).
>
> ## P3: A defect to flag (not a new rule)
>
> §2.19 defines `x += rhs` as a purely syntactic rewrite to `x = x + rhs`. For `xs[next()] += 1`, that runs `next()` twice. P1's "exactly once" wording needs the rewrite to bind the target's subexpressions to temporaries first. I propose amending the §2.19 wording in the same change: "evaluates the target's subexpressions once". This does not reopen the 5-0 decision; it states what the rewrite always meant.
>
> ## Rejected on purpose
>
> - **(b), unspecified:** see P1's tradeoffs.
> - **Declaration order for keyword args:** a second rule that the reader cannot see at the call.
> - **An error when two arguments both have side effects:** the compiler cannot detect this, because closure mutation of a captured `let mut` is not in the effect row. It would also add a diagnostic code to guard a hazard that P1 removes outright.
>
> **Min's vote:** P1 + P2 + P3. This is the rare case where the spec gets smaller by adding a rule.

#### Phase A.5 — Mechanical dedupe (moderator)

> # Phase A.5 — Mechanical dedupe (panel-facing)
>
> Full Phase A texts of all six panelists, verbatim, are in the scratchpad:
> phaseA_sys.md, phaseA_web.md, phaseA_plt.md, phaseA_devops.md, phaseA_aiml.md, phaseA_min.md
> (directory /tmp/claude-1000/-home-nhumrich-blinklang-blink/8b07a50f-fa99-4b48-ba28-ada79838422d/scratchpad/).
> Read all six before replying.
>
> ## Core rule — one option, proposed by all six
>
> **W: written order, left to right, for every expression.** Proposed by Sys (P1), Web (P1+P2),
> PLT (P1), DevOps (P1+P2), AI/ML (P1), Min (P1). All six state: calls = callee, then receiver,
> then arguments in written order; keyword arguments in written order, bound to parameters after;
> binary operands left then right; interpolation holes left to right; struct/list/tuple literal
> elements in written order; assignment = place sub-expressions, then rhs, then store; the
> conditional forms keep their conditional operands.
>
> Nobody proposed the ticket's "(b) unspecified". Sys (P3), PLT (P4), DevOps, AI/ML (P3), Min,
> and Web rejected it, some with an "unspecified + interference diagnostic" variant also rejected.
>
> Variations within W (wording differences, listed so the panel can confirm or collapse them):
> - W-v1 exception list: PLT lists `&&, ||, ??, if, match, loops`; Min lists `&&, ||, ??, if, match, guards`;
>   AI/ML lists `&&, ||, ??, if/match arms, closure bodies`; Sys and Web list `&&, ||, ??`; DevOps lists
>   `&&, ||, ??, if, match`.
> - W-v2 explicit as-if clause ("an implementation may reorder only when the difference cannot be
>   observed"): stated by PLT and Web; not stated by the others.
> - W-v3 explicit early-exit clause ("a `?` or a panic in sub-expression i means i+1..n never run"):
>   stated by PLT; Sys states "side effects and any panic included, before the next one starts".
> - W-v4 "a variable read is an evaluation at its written position" stated explicitly by Sys.
>
> ## Sub-question S1 — compound assignment `place op= rhs` (flagged: different proposals)
>
> - S1-a: amend §2.19 so the place's sub-expressions are evaluated once (bound to temps in written
>   order), then rhs, then op, then store. Proposed by Web (P3), PLT (P3), Min (P3), Sys (in P1).
> - S1-b: DevOps offered as an alternative: "or reject side-effecting places in compound assignment
>   with a named diagnostic".
> - S1-c: treat as out of scope and file a separate ticket. Offered as a fallback by Web and DevOps.
> - AI/ML's text says "`x += rhs` rewrites to `x = x + rhs`, so `x` is read before `rhs`" and does
>   not address a place with side effects.
>
> ## Sub-question S2 — what replaces the §2.13 formatter sentence (flagged: different proposals)
>
> All six strike "The formatter enforces declaration order at call sites for consistency".
> What goes in its place differs:
> - S2-a: formatter preserves written order; no lint. Web ("My recommendation: no lint"), PLT
>   ("I also reject a narrower rule that reorders only literal or variable arguments"), Min (lint
>   only if someone asks, YAGNI).
> - S2-b: DevOps: a `KeywordArgOrder` lint (warning, off by default or @allow-able), autofix only
>   when every moved argument is a literal, local name or field read.
> - S2-c: Sys: "If the panel wants the reorder anyway, allow it only when every moved argument is an
>   atom, so the reorder cannot be observed."
> - S2-d: AI/ML: "If we want that, a style lint (a warning with no autofix) can offer it later."

#### Phase B — Debate (round 1)

Five panelists signalled "STABLE, ready to vote" after round 1. DevOps signalled "NOT STABLE" on two points, the old-value read in compound assignment and the closed exception list; both went onto the ballot as options. Position shifts in this round: DevOps withdrew S1-b (a diagnostic for side-effecting places) and the `KeywordArgOrder` lint; Sys withdrew S2-c (an atoms-only formatter reorder) and its empty-effect-row inline rule; AI/ML withdrew its Phase A compound-assignment wording and S2-d; Web withdrew S1-c. Sys raised a new question, what evaluating an assignment place produces, which became Q5.

- **Systems:**

> # Systems (Sys): Phase B round 1
>
> ## W: yes. Collapse W-v1..v4 into one text
>
> All six of us agree on the rule. The variations are gaps in the wording, not rival designs. I propose we fold all four into one text and vote on it as a single item.
>
> **W-v1 (exception list): use one closed list that is the union of ours.**
> "`&&`, `||`, `??`, `if`, `match` (arms and guards), loop bodies and conditions, and closure bodies."
>
> Closure bodies must be on the list. A closure literal used as an argument is *created* in its written position, but its body does not run there. A list that leaves this out reads as if `f(fn() { tick(1) }, tick(2))` runs `tick(1)` first. The scrutinee of `if`/`match` and the left operand of a short-circuit form still follow W. Only the branches are conditional.
>
> **W-v2 (as-if clause): include it, with "observable" defined.**
> The definition: output and other effects, the state of captured `let mut` cells, and *which* panic or `?` fires first.
>
> I withdraw part of my Phase A proposal. I said an argument with an empty effect row could stay inline in C. PLT is right that this is unsound: a captured-cell write (§2.8) and an overflow panic (§3) are both invisible to the effect row. So the C printer may leave an argument inline only in two cases:
> - it is an atom (a literal, an immutable local, or a parameter),
> - it is the only non-atom in the call.
>
> Everything else goes into a temp. gcc and clang remove these temps at -O2, so the runtime cost is still zero.
>
> **W-v3 (early exit): include PLT's sentence as written.**
> "A `?`, a panic, or other early exit in operand *i* means operands *i+1..n* never run."
>
> My Phase A text implied this but did not say it.
>
> **W-v4 (a variable read is an evaluation): include it explicitly.**
> This is the one clause that separates W from Go's partial rule. The ticket note measured `bump() + n * 100` giving 1, and without this clause a reader could still argue for that result. One sentence closes it: "Reading a variable is an evaluation, and it happens at its written position."
>
> ## Assignment: one detail the backend needs in the text
>
> Everyone chose place first, then rhs, then store. The spec must also say *what* evaluating the place produces:
> - the base value (the list or map handle, or the struct receiver),
> - the index or key value,
> - *not* an element address.
>
> The element address and the bounds check happen at the store, after rhs. Otherwise `xs[0] = grow(xs)`, where `grow` appends and reallocates the buffer, would let the C printer compute `&xs->data[0]` before the call and then write through a dangling pointer. This costs nothing at runtime. It forbids an unsafe hoist, which is a memory-safety bug in waiting.
>
> ## S1 (compound assignment): S1-a. Reject S1-b and S1-c
>
> The full order for `place op= rhs` is:
> 1. evaluate the place's sub-expressions once, in written order, into temps;
> 2. load the old value;
> 3. evaluate rhs;
> 4. apply op;
> 5. store, with the bounds check at this step.
>
> Step 2 before step 3 is what `x = x + rhs` already means under W. So `n += bump()` reads the old `n` before `bump()` runs, and that must be written out. Java does the same (JLS 15.26.2); Rust's order for primitive types differs, and we should not copy it.
>
> - **S1-b** adds a diagnostic for a hazard that S1-a removes outright, at no cost. More surface, no gain.
> - **S1-c** fails because W says "exactly once" and today's syntactic rewrite runs the place twice. Shipping W without S1 puts two contradicting sentences in the spec. They go in together.
>
> ## S2 (formatter sentence): S2-a. I withdraw my S2-c
>
> Replace the sentence with: "The formatter preserves written argument order."
>
> PLT and Min are right that an atoms-only reorder is a special case bought for a cosmetic gain, and the formatter would then need a purity test. As for a lint (S2-b and S2-d): it is not spec text. DevOps can file a feature ticket if users ask for one. YAGNI.
>
> ## Summary position
>
> W (with v1 through v4 merged as above, plus the assignment clause) + S1-a + S2-a, as one package.
>
> STABLE, ready to vote

- **Web/Scripting:**

> # Web/Scripting: Phase B round 1
>
> I have read all six Phase A texts. All six of us proposed the same rule, and no one defends "unspecified". What remains is wording, plus S1 and S2.
>
> ## W: yes
>
> I support W. A JS, Python or Kotlin developer already assumes it, so it costs them nothing to learn.
>
> ## W-v1 to W-v4: take all four, because they do not conflict
>
> The four variations add to each other. None of them competes with another, so I propose we merge them into one text and vote on that.
>
> **W-v1 (exception list).** Use Min's general clause and give the concrete list after it, so a reader does not have to work it out:
>
> > The only exceptions are the forms the spec defines as conditional: `&&`, `||`, `??`, `if`, `match` (arms and guards), and loops. Their operands run only as those forms define.
>
> A closure literal is not an exception, so I would leave "closure bodies" out of the list. `fn() { ... }` evaluates to a closure value, and nothing inside the body runs until the closure is called. A note can say this, but the exception list is not the place for it. If we put it there, readers will ask what else is on the list.
>
> **W-v2 (as-if).** Include it. The rule tells codegen it may skip the temps. Users never see the clause, and without it an implementer could read W as "hoist every argument into a temp".
>
> **W-v3 (early exit).** Include it. "A `?` or a panic in sub-expression i means i+1..n never run" is what every developer expects from `f(parse(a)?, save(b))`. Sys's "side effects and any panic included" is the same idea. Use PLT's wording, because it names `?` explicitly.
>
> **W-v4 (a variable read happens at its written position).** Include it. This is the ticket-note bug: `bump() + n * 100` gave 1. Without this sentence someone will implement Go's half rule, where calls are ordered but reads are not. Sys and AI/ML both point to Go's version of this as a known FAQ trap. We should say it in the spec text and not leave it to an example.
>
> **Assignment, for the record.** AI/ML's line "`x += rhs` ... so `x` is read before `rhs`" agrees with S1-a. S1-a adds that the place's sub-expressions run once. The old value is still read before `rhs`, as in JS and Python, where `a[i] += f()` reads `a[i]` before it calls `f()`. The spec should state that order: place sub-expressions, then the read of the old value, then `rhs`, then the op, then the store.
>
> ## S1: S1-a
>
> Four of us proposed S1-a outright, and PLT's §2.19 wording is ready to paste. Now that the fix is small and agreed, the fallback (S1-c) is not needed, so I withdraw it.
>
> I am against S1-b (reject side-effecting places with a diagnostic):
> - `counts[key_of(item)] += 1` is ordinary code in JS, Python and Kotlin. An error there makes people ask why Blink rejects code that works everywhere else, which is the Stack Overflow question I want to avoid.
> - To detect a side-effecting place, the compiler needs the effect and alias analysis that PLT, DevOps and Min have already shown is not sound here (§2.8 captured `let mut`).
> - S1-a is smaller than S1-b and correct.
>
> ## S2: S2-a, with wording that also covers struct literals
>
> Replacement text:
>
> > The formatter preserves the written order of call arguments and struct-literal fields. Under §2.x that order is the evaluation order.
>
> Struct-literal fields need the same guarantee. DevOps flagged this in P2, and under W a formatter that sorts fields would change behavior in the same way.
>
> - **Against S2-b (off-by-default lint with a partial autofix):** users would see one lint that auto-fixes some call sites and not others, and ask why. It also adds lint surface that nobody has asked for.
> - **S2-c and S2-d** are both "if the panel wants it later". No one is asking for it now. I propose we fold them into one note: a declaration-order style lint is out of scope and needs its own ticket if users ask for one.
>
> ## Summary of my position
>
> - W, with v1 (Min's clause plus the concrete list, no closure bodies), v2, v3 (PLT wording) and v4.
> - S1-a, with the order of the old-value read stated.
> - S2-a, extended to struct-literal fields.
>
> STABLE, ready to vote

- **PLT:**

> # PLT: Phase B round 1
>
> All six panelists proposed the same rule, W. The four wording variants W-v1 to W-v4 do not compete with each other. Each one fixes a separate hole, so I propose merging all four into one text (below). Two sub-questions stay open: S1, where I favour S1-a, and S2, where I favour S2-a and show that S2-b is unsound as written.
>
> ## W: yes. Merge W-v1..v4 into one text
>
> **W-v1 (the exception list).** Do not simply list constructs. Define the category and then name its closed membership, so that a construct added later has to state which side it is on.
>
> - The exceptions are the forms whose semantics decide *which* sub-expressions run: `&&`, `||`, `??`, `if`, `match` (arms and guards), and loops.
> - A closure body (AI/ML) is **not** an exception to W. It is not an operand at all. A closure literal evaluates to a value, and the body runs when the closure is called, under W at that call. Calling it an exception suggests that closure construction is partly lazy, which is wrong.
> - Guards (Min) and loops (PLT) come under `match` and the loop forms, so list them as members rather than as extra rules.
>
> **W-v2 (the as-if clause): keep, and define "observable".** Without this clause, W forbids the temp-elision Sys relies on in the C printer. With a vague version of it, W allows reordering anything that is "pure". §2.8 (captured `let mut` writes have no effect row) and §3 (overflow panics) make a vague clause unsound.
>
> Proposed text: *"An implementation may evaluate in another order only when no program can observe the difference. Observable means output, the value of any binding, which panic occurs, and whether evaluation terminates."*
>
> **W-v3 (early exit): keep.** It follows from "finish each one before starting the next", but divergence is exactly where optimisers hoist code wrongly. For example, evaluating `b()` before `a()?` has returned its `Err` is wrong. State it.
>
> **W-v4 (variable reads are evaluations at their written position): keep.** This is the ticket-note MVCE (`bump() + n * 100`), and it is Go's hole. Without W-v4, "sub-expressions" could be read as meaning calls only.
>
> **Merged text:**
>
> > An expression evaluates its operand sub-expressions exactly once, one at a time, left to right in written order. A read of a variable is an evaluation at its written position. Each operand finishes, side effects and panics included, before the next starts. If one exits early through `?` or a panic, the operands after it are not evaluated. Then the expression performs its own operation. The forms whose semantics decide which sub-expressions run (`&&`, `||`, `??`, `if`, `match` arms and guards, loops) evaluate only the parts their sections select, and in the same relative order. A closure literal is a value; its body runs at each call. An implementation may evaluate in another order only when no program can observe the difference (output, the value of any binding, which panic occurs, termination).
>
> The per-construct bullets (calls, keyword arguments, operators, literals, interpolation, assignment) then become non-normative consequences, the form Min proposed.
>
> ## S1: S1-a, and in this change, not in a separate ticket
>
> - **Reject S1-c (a separate ticket).** W says "exactly once". The §2.19 rewrite evaluates the place's sub-expressions twice. If both went into the spec, the spec would contradict itself. The amendment must land together with W.
> - **Reject S1-b (a diagnostic).** It adds a code in order to forbid `xs[next()] += 1`, a legal program with one obvious meaning. W already gives it that meaning.
> - **One extra detail for S1-a: when the old value is read.** Order is:
>   1. the place's sub-expressions,
>   2. **the read of the place's current value**,
>   3. `rhs`,
>   4. the operator,
>   5. the store.
>
>   This is what `x = x + rhs` means under W, because the read of `x` is written to the left of `rhs`. Java does the same. Rust reads after `rhs` for primitives, and we should not copy that. It is observable when `rhs` writes the place through a captured cell:
>
> ```blink
> fn main() {
>     let mut n = 1
>     let bump = fn() -> Int {
>         n = n + 10
>         0
>     }
>     n += bump()
>     io.println("{n}")   // 1: n is read (1) before bump() runs; the store then writes 1 + 0
> }
> ```
>
>   AI/ML's sentence ("`x` is read before `rhs`") agrees with this for a bare variable. S1-a extends it to places.
>
> ## S2: S2-a
>
> - **S2-b is unsound as written.** DevOps offers the autofix when every moved argument is "a literal, a local name or a field read". By W-v4, a read of a `let mut` local is order-sensitive whenever a sibling argument can write that local through a closure:
>
>   ```blink
>   let r = f(b: bump(), a: n)   // written order reads n after bump()
>   ```
>
>   Moving `a: n` first changes `r`.
> - **Sys's S2-c atom definition is sound:** a literal, an immutable binding or a parameter. But a sound reorder is still more surface than this ticket needs.
> - **Adopt S2-a.** Min's wording is the right one: *"The formatter never reorders arguments; argument order is evaluation order (§2.x)."*
> - **A lint can come later under its own ticket (AI/ML's S2-d).** If it offers an autofix, the fix must use the immutable-atom criterion, not "local name".
>
> STABLE, ready to vote

- **DevOps/Tooling:**

> # DevOps/Tooling: Phase B round 1
>
> ## W (core rule): support
>
> All six of us agree. I have nothing to add to the substance. My remaining interest is wording, because diagnostics, `blink llms` topics and the LSP hover text will quote this rule directly.
>
> ### W-v1 (exception list): use one closed list, stated by construct
>
> I propose this text:
>
> > The exceptions are the forms the spec defines as conditional or repeated: `&&`, `||`, `??`, `if`, `match` (arms and guards), and loop conditions and bodies (`while`, `loop`, `for`). A closure literal evaluates to a closure value and does not run its body.
>
> Reasons:
> - **Guards (Min) and loops (PLT) belong in the list.** Without them a reader can argue that a guard is an "operand".
> - **Closure bodies (AI/ML) are not an exception.** A closure body is not a sub-expression that the literal evaluates. Listing it as an exception suggests that other operands run bodies. I keep AI/ML's point as the separate sentence at the end instead.
> - **A closed list is better than "forms the spec defines as conditional" alone.** `blink explain` and hover text can print a closed list word for word. An open phrase makes every new construct raise the same question again.
>
> ### W-v2 (as-if clause): include it
>
> Sys's C printer rule keeps atoms and effect-free arguments inline. That is only legal if the spec says an implementation may reorder when nobody can see the difference. Without the clause, the spec as written forbids gcc's own optimisations. PLT's wording is fine. Tooling consequence: at `-O2` a debugger can show temps merged or moved. That is normal, and `--debug` (`-O0`) keeps the written order visible.
>
> ### W-v3 (early exit): include PLT's explicit sentence
>
> "A `?` or a panic in sub-expression *i* means *i+1..n* never run." Sys's "before the next one starts" implies this, but diagnostics need it stated outright. The panic users see is the first one in written order, and `--trace` shows no call after it. `?` also interacts with `with` cleanup (§4.6.3), so the rule should not have to be inferred.
>
> ### W-v4 (variable reads): include it
>
> The ticket note's own bug is `bump() + n * 100` reading `n` early. If the spec does not say that a read is an evaluation at its written position, we have copied Go's gap. Sys's sentence is short, so keep it.
>
> **My request for W:** the final text should include v2, v3 and v4 as written, plus my v1 list above.
>
> ## S1 (compound assignment): S1-a. I withdraw S1-b
>
> I withdraw my S1-b ("reject side-effecting places with a diagnostic"). It needs the same check I rejected for "unspecified": closure writes to `let mut` cells are not in the effect row, so the diagnostic could not be sound. It would add an error code to guard against a hazard that S1-a removes.
>
> S1-c (a separate ticket) also goes. W's "exactly once" cannot be true while §2.19 evaluates the place twice, so S1 is in scope.
>
> **One wording gap is still open in S1-a.** It does not say when the place's **current value** is read. Given `xs[i] += f()`, where `f` writes `xs[i]`, it matters whether the old value is read before or after `f()` runs. The existing rewrite `x = x + rhs` evaluates the left operand of `+` first, so the old value is read before `rhs`. That also matches AI/ML's sentence and Java (JLS 15.26.2). Proposed §2.19 text:
>
> > `place op= rhs` evaluates the place's sub-expressions once, left to right. Then it reads the place's current value, evaluates `rhs`, applies `op`, and stores the result to the same place. For a bare variable this is the same as `x = x op rhs`.
>
> ```blink
> fn main() {
>     let mut i = 0
>     let next = fn() -> Int {
>         i = i + 1
>         i
>     }
>     let mut xs = [0, 0, 0]
>     xs[next()] += 10          // next() runs once: xs == [0, 10, 0]
>     io.println("{xs}")
> }
> ```
>
> ## S2 (formatter sentence): S2-a. I withdraw the lint
>
> Five panelists want no lint now, and I accept YAGNI. A lint with a conditional autofix is also something users would have to learn, for a style point nobody has asked for. I merge S2-b and S2-d into this: "no lint now; a declaration-order lint needs its own proposal."
>
> **I reject S2-c (Sys: the formatter may reorder when every argument is an atom).** A formatter that rewrites a call only sometimes, depending on what kind of argument it holds, gives unpredictable output. For example, change one argument from `x` to `x.len()` and the whole call is reordered back. That creates diff churn in review and makes `fmt --check` failures hard to explain. `gofmt` and `rustfmt` never make a rewrite depend on expression purity.
>
> Proposed §2.13 replacement, which widens Min's wording to struct literals because W covers them too:
>
> > The formatter never reorders arguments, struct-literal fields or list elements. Their written order is their evaluation order (§2.x).
>
> NOT STABLE: S1-a must state that the place's current value is read before `rhs` (proposed text above). W-v1 needs the closed exception list agreed.

- **AI/ML:**

> # AI/ML: Phase B round 1
>
> ## Core rule W: support
>
> All six panelists wrote the same rule. That agreement is itself a learnability signal: six domain lenses, starting from the same spec, all expected left to right. A model reading the spec will expect the same. I support W as the one rule and see nothing left to argue on its substance.
>
> ## W-v1, exception list: collapse into one closed list
>
> A model learns a closed, explicit list better than a category such as "control forms". A category makes it guess the edges ("is a guard a control form? a loop body?"). I propose this list, the union of all five with the overlap removed:
>
> > The only exceptions are forms the spec defines as conditional or deferred: `&&`, `||`, `??`, `if`, `match` (arms and guards), loops, and closure literals. A closure literal's body runs when the closure is called, not where it is written.
>
> Why I keep "closure literals": `let g = fn() -> Int { bump() }` does not run `bump()` at the `let`. Every model knows this, but "every sub-expression, exactly once" read literally would say otherwise. One clause removes the ambiguity. PLT's "loops" and Min's "guards" belong in the list for the same reason. The Sys/Web list (`&&`, `||`, `??` only) is too short to read literally.
>
> ## W-v2, as-if clause: include
>
> It costs one sentence. It tells implementers (and models writing codegen for this repo) that the rule is about observable behaviour, not about emitting a temp for every argument. Without it, a literal reader could think `f(1, x)` must go through temps. It also closes off the wrong conclusion "pure arguments may reorder": PLT showed that effect rows do not track captured-cell writes or panics, so as-if is the only correct escape hatch.
>
> ## W-v3, early exit: include, using PLT's wording
>
> `f(a()?, b()?)` and `parse(x)? + parse(y)?` are very common shapes in generated code. The rule has to say that `b()` never runs when `a()?` exits early, and that the panic from an overflow in argument 1 hides argument 2. Sys's "finishes before the next one starts" implies this, but a model learns best from the explicit form: "a `?`, `return`, or panic in sub-expression *i* means *i+1..n* never run".
>
> ## W-v4, a variable read is an evaluation at its written position: include, with the ticket-note example
>
> This is the one clause models get wrong, because Go (a common training source) leaves it open. The measured bug (`bump() + n * 100` giving 1) is exactly this case. Put that example in the spec text, since an example teaches better than a sentence. My Phase A example already showed 101. I endorse Sys's explicit sentence.
>
> ## S1, compound assignment: S1-a
>
> I withdraw my Phase A wording ("rewrites to `x = x + rhs`, so `x` is read before `rhs`"). It is correct only for a bare name, and S1-a covers it as a special case.
>
> - **S1-a (support).** `counts[key()] += 1` and `xs[i()] += v` are common generated shapes. Every source language a model learned from (JS, Python, Kotlin, C#, Rust) evaluates the place once. A double call would be a silent wrong result that nothing detects.
> - **S1-b (reject).** A new diagnostic on side-effecting places adds a decision point and a repair pattern ("hoist into a `let`") for code that is correct in every language the model knows. We would pay tokens and error rounds to guard against a hazard S1-a removes.
> - **S1-c (reject as scope-splitting).** It is one sentence in §2.19, and W's "exactly once" wording already needs it. Leaving it out would ship a spec that contradicts itself.
>
> ## S2, formatter sentence: S2-a
>
> I withdraw my S2-d aside ("a lint can offer it later"). No one needs it now (YAGNI), and Min says the same.
>
> - **S2-a (support).** Proposed wording: "The formatter never reorders arguments; argument order is evaluation order (§2.x)."
> - **S2-b (reject).** An autofix that applies to some calls and not others teaches two behaviours. A model cannot predict from source whether `blink fmt` will change its call, so formatted output stops being a stable target. A lint that is off by default is also dead weight in the spec.
> - **S2-c (reject).** This is the same objection in formatter form: a rule where atoms may move and calls may not. PLT's "special case for a cosmetic gain" is right.
>
> ## Summary of my position
>
> W with v1 (closed union list, above) + v2 + v3 + v4; S1-a; S2-a.
>
> STABLE, ready to vote

- **Minimalism:**

> # Minimalism (Min) — Phase B round 1
>
> I read all six Phase A texts. We agree on W. The four wording variations are not rival designs: each one answers a question the others leave open. I propose we fold all four into one rule text and vote on that single text. My merged wording is at the end.
>
> ## W-v1: exception list
>
> Five lists, and they disagree because they mix two kinds of thing:
> - **Conditional operands:** `&&`, `||`, `??`, and the arms and guards of `if` and `match`. These are real exceptions. The operand is part of the expression, but it may not run.
> - **Bodies:** closure bodies (AI/ML) and loop bodies (PLT). These are not exceptions. A closure literal evaluates to a closure value, and its body is not an operand. A loop is a statement with its own §2 rules. Putting them in the list suggests they are exceptions to W, which invites the question "which other bodies are too?"
>
> Proposal: a **closed** list, `&&`, `||`, `??`, and the branches and guards of `if` and `match`. Add one sentence: "A body (closure, loop, block) is not an operand of the expression that contains it; its own rules say when it runs." The `if` condition and the `match` scrutinee still go first under W. Only the branches are conditional.
>
> A closed list matters. An open list ("forms the spec defines as conditional") means every new construct reopens this rule. That is the C++ piecemeal pattern we all rejected.
>
> ## W-v2: as-if clause (include)
>
> I support it, with PLT's scope made explicit: "observable" includes output, writes to captured `let mut` cells, and which panic fires first. Without this clause, a reader could take W as a ban on the temp-elision that Sys's C-printer rule depends on. With it, "effect row empty" alone is visibly not enough to reorder, which is PLT's soundness point. It costs one sentence and removes a whole class of implementer questions.
>
> ## W-v3: early exit (include, merged with Sys's wording)
>
> This already follows from "finishes each operand before the next starts". But `?` is a Blink-specific control transfer, and a reader will ask. State it once: "If operand *i* panics or exits through `?`, operands *i+1..n* do not run and the operation is not performed." This absorbs Sys's "side effects and any panic included".
>
> ## W-v4: a variable read is an evaluation at its written position (include)
>
> This is the exact bug in the ticket note (`bump() + n * 100` gives 1), and it is the hole that makes Go's rule half a rule. Without it, a reader can claim that `n` is not a "sub-expression with effects" and so falls outside W. Keep the clause.
>
> ## S1: compound assignment (S1-a)
>
> **S1-a.** The place's sub-expressions are evaluated once, in written order. Then the place's current value is read, then `rhs` is evaluated, then the operator runs, then the store. For a bare variable this is exactly today's rewrite. AI/ML's "x is read before rhs" is consistent with this, so AI/ML's text needs no retraction, only the "once" clause.
>
> - **Against S1-b (reject side-effecting places):** it adds a diagnostic code and makes `xs[next()] += 1` illegal, when JS, Python, C#, Rust and Kotlin all accept it with a single evaluation. It is more surface than S1-a, not less.
> - **Against S1-c (separate ticket):** W's "exactly once" and the literal §2.19 rewrite contradict each other. If we adopt W without S1-a, the spec contradicts itself on the day we vote. The fix is one clause. Deferring it costs more process than doing it now.
>
> ## S2: formatter sentence (S2-a, generalized)
>
> **S2-a**, with the replacement generalized so it also covers struct literals (DevOps's P2 point):
>
> > "The formatter never reorders arguments, fields or elements. Under §2.x their written order is their evaluation order."
>
> - **S2-d collapses into S2-a.** "A lint can offer it later" is S2-a plus a sentence of intent, and specs do not record intent.
> - **Against S2-b (`KeywordArgOrder` lint with a conditional autofix):** it adds a new warning code, an off-by-default config switch, and a purity classifier inside the formatter. That is three pieces of surface to enforce a style that §2.13 itself calls "order-independent". It is a fine idea to file as a tooling ticket if users ask for it, but it does not belong in this spec change.
> - **Against S2-c (reorder when every moved argument is an atom):** a formatter whose output depends on a purity check behaves one way for `f(b: x, a: y)` and another for `f(b: x.len(), a: y)`. PLT is right: a special case for a cosmetic gain.
>
> ## Merged rule text (for the vote)
>
> > **Evaluation order.** An expression evaluates its operands exactly once, left to right, in the order they are written. Each operand finishes, side effects and any panic included, before the next one starts. Then the expression performs its own operation. A read of a variable is an evaluation at its written position. If operand *i* panics or exits through `?`, later operands do not run and the operation is not performed.
> >
> > The only exceptions are the conditional operands of `&&`, `||` and `??`, and the branches and guards of `if` and `match`. The `if` condition and the `match` scrutinee still run first. A body (closure, loop or block) is not an operand of the expression that contains it.
> >
> > Operands, in order:
> > - **Call:** the callee, then the receiver, then the arguments as written. Keyword arguments are bound to parameters only after all of them are evaluated.
> > - **Operator:** left operand, then right operand.
> > - **Literal:** fields, elements and payloads as written.
> > - **Interpolation:** holes left to right. Each hole's value is appended before the next hole starts.
> > - **Assignment:** the place's sub-expressions, then the right-hand side, then the store. For compound assignment `place op= rhs`: the place's sub-expressions once, then the place's current value, then `rhs`, then the operator, then the store.
> >
> > An implementation may reorder evaluation only where no program can observe the difference, counting output, writes to captured `let mut` cells, and which panic fires.
>
> Plus S2-a (generalized) in §2.13, and §2.16's spread sentence kept as a cross-reference to this rule.
>
> STABLE, ready to vote

#### Phase C — Final vote

The ballot, as sent to the panel:

> # Phase C — silent ballot
>
> Phase B closed after round 1: 5 of 6 panelists signalled "STABLE, ready to vote". DevOps signalled
> "NOT STABLE: S1-a must state that the place's current value is read before `rhs` (proposed text
> above). W-v1 needs the closed exception list agreed." The round-1 texts are in the scratchpad as
> phaseB1_*.md; read them all before voting (you have not yet seen the other five).
>
> Vote silently. Do not message other panelists. For EACH question give:
> 1. **Vote**: option label.
> 2. **Reasoning**: 2–4 sentences, anchored in your domain.
> 3. **Concern**: one sentence on what could go wrong with the option that wins (or the one you voted for).
>
> ## Q1 — Core rule
> - **Q1-W**: written order, left to right, for every expression, as merged in round 1 (see PLT's and
>   Min's merged texts in phaseB1_plt.md / phaseB1_min.md): operands evaluated exactly once, one at a
>   time, in written order; keyword arguments in written order, bound after; a variable read is an
>   evaluation at its written position (W-v4); if operand i exits through `?` or panics, later operands
>   do not run (W-v3); as-if clause, where observable includes output, the value of any binding
>   (including captured `let mut` cells), which panic occurs, and termination (W-v2).
> - **Q1-U**: the ticket's option (b): order unspecified, stated as such.
>
> ## Q2 — Exception list and the status of bodies (W-v1)
> - **Q2-A** (PLT, DevOps, Web in round 1): closed list `&&`, `||`, `??`, `if`, `match` (arms and
>   guards), and loops; a closure literal is a value whose body runs at each call — stated in a
>   separate sentence, not in the exception list.
> - **Q2-B** (Min in round 1): closed list `&&`, `||`, `??`, and the branches and guards of `if` and
>   `match`; plus "A body (closure, loop or block) is not an operand of the expression that contains
>   it." Loops are not in the list.
> - **Q2-C** (Sys, AI/ML in round 1): closed list that includes loops AND closure bodies/literals as
>   members, e.g. AI/ML: "`&&`, `||`, `??`, `if`, `match` (arms and guards), loops, and closure literals.
>   A closure literal's body runs when the closure is called, not where it is written."
>
> ## Q3 — Compound assignment `place op= rhs` (S1)
> - **Q3-a** (S1-a): amend §2.19: the place's sub-expressions are evaluated once, in written order;
>   then the place's current value is read; then `rhs`; then the operator; then the store. For a bare
>   variable this equals today's `x = x op rhs`.
> - **Q3-b** (S1-b, withdrawn by its proposer): reject side-effecting places with a named diagnostic.
> - **Q3-c** (S1-c, withdrawn by its proposers): out of scope; separate ticket.
>
> ## Q4 — Replacement for the §2.13 formatter sentence (S2)
> - **Q4-a** (S2-a): strike the sentence; the formatter never reorders call arguments, struct-literal
>   fields or list elements, because written order is evaluation order. No lint now; a
>   declaration-order style lint needs its own proposal.
> - **Q4-b** (S2-b, withdrawn by its proposer): `KeywordArgOrder` lint, off by default, autofix when every
>   moved argument is a literal, local name or field read.
> - **Q4-c** (S2-c, withdrawn by its proposer): formatter may reorder only when every moved argument is an
>   atom (literal, immutable binding, parameter).
>
> ## Q5 — What evaluating an assignment place produces (raised by Sys in round 1)
> - **Q5-Y**: state in the spec that evaluating a place `base[index]` / `base.field` produces the base
>   value and the index/key value, not an element address; the element address and bounds check happen
>   at the store, after `rhs` (Sys's example: `xs[0] = grow(xs)`).
> - **Q5-N**: do not state it in the spec (leave it to the as-if clause / implementation).
>
> Write your ballot in full to scratchpad/phaseC_<yourname>.md and reply "voted".

**Tally:** Q1 W 6-0; Q2 A 6-0 (Min moved B → A, Sys and AI/ML moved C → A); Q3 a 6-0; Q4 a 6-0; Q5 Y 6-0. No question was closer than 5-1, so Phase D did not run.

- **Systems:**

> # Phase C ballot: Systems (Sys)
>
> ## Q1: Core rule
>
> **Vote: Q1-W**
>
> **Reasoning.** Sequencing costs nothing on real hardware. The IR puts each argument in a temp in written order, and gcc and clang at -O2 remove the temps and reorder pure work under the as-if rule anyway. Q1-U buys no speed. It only hands the meaning of a program to whichever C compiler runs: gcc and clang differ on x86-64, and zig cc for cross targets could differ again. The W-v2 definition of "observable" (binding values, which panic fires, termination) is the right fence for the C printer.
>
> **Concern.** An engineer working on the C printer may "optimise" by keeping a non-atom argument inline because its effect row is empty. That breaks W silently for captured-cell writes and for overflow panics. The inline rule (atoms only, or a single non-atom) needs a test in the rewrite suite.
>
> ## Q2: Exception list and the status of bodies
>
> **Vote: Q2-A**
>
> **Reasoning.** I withdraw Q2-C. PLT, Min and DevOps are right: a closure literal is a value, its construction is not partly lazy, and calling it an exception misleads anyone who writes the lowering.
>
> I prefer A to B for one concrete reason. B's sentence "A body (closure, loop or block) is not an operand" is wrong for block expressions. In `f({ tick(1) }, tick(2))`, the block *is* an operand, and it must run first, in its written position. A closed list plus a separate closure sentence has no such hole.
>
> **Concern.** A must also say that a loop condition is evaluated again each iteration, under W each time. Otherwise "loops" in the exception list reads as "the loop condition has no order rule".
>
> ## Q3: Compound assignment
>
> **Vote: Q3-a**
>
> **Reasoning.** The order is:
> 1. the place's sub-expressions once, into temps,
> 2. read the old value,
> 3. `rhs`,
> 4. the operator,
> 5. the store.
>
> This is what `x = x + rhs` already means under W, and it costs no more than one temp. The syntactic rewrite does not merely waste work on `xs[next()] += 1`: it is wrong, and W's "exactly once" contradicts it. Deferring the fix would put a contradiction in the spec.
>
> **Concern.** Lowering `m[k] += 1` on a Map needs two hash lookups: read the old value, then store. A later "fuse to one lookup" optimisation must still keep the old-value read before `rhs`.
>
> ## Q4: Formatter sentence
>
> **Vote: Q4-a**
>
> **Reasoning.** I withdraw my S2-c. DevOps's point about diff churn when `x` becomes `x.len()` settles it: formatter output must not depend on a purity test. The rule "written order is evaluation order, so the formatter never reorders" is one sentence, with no classifier to keep correct.
>
> **Concern.** A future style lint may bring back an autofix with a loose purity test ("local name"). PLT already showed that test is unsound under W-v4. Any such lint must use the immutable-atom test.
>
> ## Q5: What evaluating an assignment place produces
>
> **Vote: Q5-Y**
>
> **Reasoning.** This is semantics, not an implementation detail, so the as-if clause cannot settle it. Take `xs[10] = f()` on a 3-element list, where `f` prints. If evaluating the place includes the bounds check, the panic fires and nothing prints. If the check happens at the store, `f` prints first and then the panic fires. Output and "which panic occurs" are both observable under W-v2, so the spec must pick one. Picking "base and index values, bounds check and element address at the store" also rules out the hoisted `&xs->data[i]` that `xs[0] = grow(xs)` would turn into a write through a dangling pointer after a realloc. Java checks at the store too (JLS 15.26.1).
>
> **Concern.** The text must cover nested places (`a[i].f[j] = v`). Each intermediate element read is a value read in written order during place evaluation. Only the final location, with its bounds check, is deferred to the store. The wording has to say so, or the nested case stays ambiguous.

- **Web/Scripting:**

> # Phase C ballot: Web/Scripting
>
> ## Q1: Core rule
> **Vote:** Q1-W
>
> **Reasoning:** Every language a JS, TS, Python or Kotlin developer knows runs calls and operators left to right, so W needs no teaching. Users only discover an "unspecified" order when output comes out in a different order, as in the "202 101" interpolation result in the ticket note. That leads to a Stack Overflow question, and the answer would be "C does it". All six panelists reached the same answer on their own, which is a good sign that users will expect it too.
>
> **Concern:** The as-if clause is the one place an implementer could quietly break W. The codegen needs a test that runs the ticket-note programs (keyword args out of order, `bump() + n * 100`, two calls in one interpolation) at every optimisation level.
>
> ## Q2: Exception list and the status of bodies
> **Vote:** Q2-A
>
> **Reasoning:** A developer reads the list as written. The short list `&&`, `||`, `??`, `if`, `match` (arms and guards), loops matches the short-circuit and branch forms they already know. The closure sentence answers the obvious question ("does `fn() { tick(1) }` run here?") without making a closure look like an exception to W. Q2-C puts closures on the list, which tells readers that closure construction is partly lazy. Q2-B drops loops from the list and relies on the reader to see a loop condition as a "body", which is a subtler idea than most readers will bring.
>
> **Concern:** "Loops" is less precise than DevOps's "loop conditions and bodies". The final text should name `while`, `loop` and `for` so a reader does not have to guess.
>
> ## Q3: Compound assignment
> **Vote:** Q3-a
>
> **Reasoning:** `counts[key_of(item)] += 1` is ordinary code in JS, Python and Kotlin, and all three evaluate the place once and read the old value before `rhs`. Q3-a gives Blink the same meaning with one sentence and no new error code. Q3-b would reject code that works in every language our users come from, and Q3-c would leave the spec contradicting itself on the day W lands.
>
> **Concern:** `n += bump()`, where `bump` writes `n` through a closure, keeps the old read (PLT's example prints 1). Some users will be surprised by that, so the spec should show the example and not just the rule.
>
> ## Q4: Formatter sentence
> **Vote:** Q4-a
>
> **Reasoning:** A formatter that changes what a program prints is a trust-breaker: people stop running it on save. The current formatter already keeps written order, so Q4-a only brings the spec in line with the code. Q4-b and Q4-c would make `blink fmt` reorder some calls and not others depending on the argument kinds, which is exactly the "why did fmt do that?" confusion we want to avoid.
>
> **Concern:** Some users will want the declaration-order style that §2.13 used to promise. If they ask, that goes to a separate lint proposal that uses PLT's immutable-atom rule, never "local name".
>
> ## Q5: What evaluating an assignment place produces
> **Vote:** Q5-Y
>
> **Reasoning:** The difference is observable. In `xs[9] = parse(s)?` on a short list, the user can see whether the `?` exit or the bounds panic comes first, and JS and Python both evaluate the right-hand side before they do the store. Writing the rule down gives the user one answer ("`rhs` first, then the store and its check") and blocks the dangling-pointer hoist Sys described. That is a memory-safety bug we should not leave to "implementation detail".
>
> **Concern:** The wording must stay at the level of values and panics, not "addresses". The spec is for Blink users, and a sentence about element addresses will read as C jargon to them.

- **PLT:**

> # PLT: Phase C ballot
>
> ## Q1: Core rule
>
> **Vote: Q1-W**
>
> **Reasoning.** W gives every program one big-step meaning, and every existing desugaring keeps that meaning without extra rules: operators become trait calls, `??` becomes a match, and `with a, b` nests. U cannot be made sound as a hazard rule, because effect rows do not track writes to captured `let mut` cells (§2.8) or panics (§3). A program would then have a meaning that depends on the backend, which is exactly what E0301 forbids.
>
> **Concern.** An implementer could read the as-if clause as "pure by effect row may reorder" and bring back the ticket-note bug. The spec example for the clause must be `bump() + n * 100`.
>
> ## Q2: Exception list and the status of bodies
>
> **Vote: Q2-A**
>
> **Reasoning.** A loop condition is an operand that runs zero or more times, not "exactly once". So loops are a real exception to W's counting clause and belong in the closed list. Q2-B leaves `while cond` out, because it treats the condition as neither an operand nor a body. A closure literal is not an exception: it evaluates to a value, and its body is not a sub-term that construction evaluates. Q2-C puts closures in the list, which makes closure construction look partly lazy. That is the wrong model, and it invites the question "what other values hide unevaluated operands?"
>
> **Concern.** Any future construct that runs a sub-term zero or more times, for example a comprehension, must be added to this closed list by name, or W's "exactly once" becomes false for it.
>
> ## Q3: Compound assignment
>
> **Vote: Q3-a**
>
> **Reasoning.** W says "exactly once", and today's syntactic rewrite evaluates the place twice. Without Q3-a the spec contradicts itself. Reading the current value before `rhs` is what `x = x op rhs` already means under W, because the read of `x` is written to the left of `rhs`. So Q3-a is the unique extension of the rewrite that agrees with W, not a new choice.
>
> **Concern.** §2.19 calls the rewrite "purely syntactic, before type checking". The amended text must say that the rewrite binds the place's sub-expressions to fresh temps first. Otherwise the typecheck and lowering stages will keep duplicating the place.
>
> ## Q4: Formatter sentence
>
> **Vote: Q4-a**
>
> **Reasoning.** Under W, reordering changes the meaning of the program, and a formatter must preserve it. A reorder allowed only for atoms is sound only when "atom" is restricted to immutable bindings, since a read of a `let mut` local is order-sensitive. That is a special case bought for a cosmetic gain. Covering struct fields and list elements is correct, because W orders them too.
>
> **Concern.** A later style-lint proposal may reuse the unsound "local name or field read" criterion for its autofix. It must require immutable bindings.
>
> ## Q5: What evaluating an assignment place produces
>
> **Vote: Q5-Y**
>
> **Reasoning.** Q5-Y is semantics, not only a codegen detail. Whether the bounds check sees the length before or after `rhs` decides which panic occurs, and the as-if clause names that as observable. Leaving it out (Q5-N) would leave an under-determined point in exactly the rule that closes them. It also forbids the dangling-address hoist that Sys identified.
>
> **Concern.** The words "produces the base value" are wrong under value semantics. They could be read as a copy of the base taken before `rhs`, so a store into it would lose an `rhs` write to the same binding through a captured cell. The text must say: evaluating a place produces its root binding plus the evaluated index/key values along the path; the root is read, and the store and bounds check happen, after `rhs`.

- **DevOps/Tooling:**

> # DevOps/Tooling: Phase C ballot
>
> ## Q1: Core rule
> **Vote:** Q1-W
>
> **Reasoning:** Tooling needs one order that the source text shows. `--trace` NDJSON, debugger stepping at `--debug`, and which panic a user sees must all agree with what the reader sees. Under Q1-U, `blink fmt`, the trace and gcc/clang/zig cc would each be free to disagree. No lint can find the cases where that matters, because closures write captured `let mut` cells with no effect row.
>
> **Concern:** At `-O2` the as-if clause lets temps merge or move, so a debugger on an optimised build may show a different order. The docs must say to use `--debug` when the order matters.
>
> ## Q2: Exception list and bodies
> **Vote:** Q2-A
>
> **Reasoning:** `blink explain`, hover text and `blink llms` can quote a closed list word for word. Loops belong in the list so that no reader argues a loop body is an operand. Closure bodies do not belong in the list, since a closure literal evaluates to a value and does not run its body, but saying that in its own sentence ends the question AI/ML and Sys raised. Q2-B's "a body is not an operand" is correct too, but it takes loops out of the list the tooling quotes.
>
> **Concern:** If the list is closed, every new control form (for example a future `select` or `try` block) must amend it explicitly, and a spec author could forget.
>
> ## Q3: Compound assignment
> **Vote:** Q3-a
>
> **Reasoning:** This version states that the old value is read before `rhs`, which was my one open point, so I am satisfied. It makes `xs[next()] += 1` call `next()` once and adds no diagnostic code. A diagnostic could not be sound anyway, because closure writes to captured cells are not in the effect row. I withdrew Q3-b for that reason.
>
> **Concern:** The codegen must lower `+=` as a place read, then `rhs`, then a store. If it keeps the purely syntactic rewrite, it will still call `next()` twice, so the change needs a corpus test with a side-effecting index.
>
> ## Q4: Formatter sentence
> **Vote:** Q4-a
>
> **Reasoning:** A formatter must never change what a program does, and `test-fmt` already checks that. The current formatter keeps written order, so this makes the spec match the code. PLT showed that my Q4-b autofix criterion was unsound: moving a `let mut` local changes the result when a sibling argument writes it through a closure. So I withdraw Q4-b, and a declaration-order lint, if ever wanted, needs its own ticket and the immutable-atom criterion.
>
> **Concern:** Users who read "order-independent at call site" may expect `blink fmt` to normalise keyword order. The §2.13 text should say plainly that written order is kept and why.
>
> ## Q5: What evaluating a place produces
> **Vote:** Q5-Y
>
> **Reasoning:** The user sees this: in `xs[9] = f()`, `f()`'s output appears before the index-out-of-bounds panic, and the panic's span and trace must follow that order. Stating that the bounds check and element address happen at the store fixes which diagnostic comes first. It also blocks Sys's dangling-pointer hoist in `xs[0] = grow(xs)`. Leaving it to the as-if clause gives implementers room to get a memory-safety bug wrong.
>
> **Concern:** The wording must also cover map keys and nested places (`a.b[i].c = v`), or a reader will ask whether the intermediate places resolve before `rhs` too.

- **AI/ML:**

> # AI/ML: Phase C ballot
>
> ## Q1: Core rule
> **Vote: Q1-W**
>
> **Reasoning:** Every language a model learned from (Python, JS, Java, Kotlin, C#, Swift) evaluates in written order. Q1-W therefore costs nothing to learn and adds no decision points. Q1-U would make every `f(next(), next())` and `"{pop()} {pop()}"` a model writes a silent, backend-dependent bug that no diagnostic can catch. Including W-v4 (a variable read happens at its written position) also closes the Go gap, the one place where model priors are mixed.
>
> **Concern:** the as-if clause is where the IR/C printer could quietly break the rule. For example, it could inline a `let mut` read next to a call that writes it through a closure. Conformance tests need to cover the captured-cell and panic-order cases, not only `io.println` order.
>
> ## Q2: Exception list and the status of bodies
> **Vote: Q2-A**
>
> **Reasoning:** In round 1, what I needed was for the spec to state that a closure body does not run where the closure is written. Q2-A says this in its own sentence, so my point holds without calling closures an "exception". PLT and Web are right that listing closures as an exception suggests closure construction is partly lazy. Q2-A keeps loops in the closed list, and a closed list is easier for a model to learn than Q2-B's general "a body is not an operand" rule, which makes the reader classify each construct.
>
> **Concern:** a new construct added later (for example an async block or a new loop form) could fall outside both the closed list and the closure sentence. Every future spec section that adds a conditional or deferred form needs to state which side it is on.
>
> ## Q3: Compound assignment
> **Vote: Q3-a**
>
> **Reasoning:** `counts[key()] += 1` is a very common shape in generated code, and every language models learned from evaluates the place once. Q3-a also states that the old value is read before `rhs`, which matches Java, JS and Python, and matches what `x = x op rhs` already means under W. Q3-b would add an error code and a repair pattern for code that is correct everywhere else, which costs tokens and error rounds.
>
> **Concern:** models that learned Rust may expect the old value to be read after `rhs` for primitives. The spec should include the `n += bump()` example so the difference is taught, not only stated.
>
> ## Q4: Formatter sentence
> **Vote: Q4-a**
>
> **Reasoning:** Formatted output has to be a stable, predictable target for generated code. A formatter that changes evaluation order, or does so only for some kinds of argument, cannot be predicted from the source. Q4-a also covers struct-literal fields and list elements, so there is one rule in place of three. YAGNI rules out the lint.
>
> **Concern:** users who read "order-independent at call site" may still expect `blink fmt` to normalise keyword order, and file bugs when it does not. §2.13's example comment should say that written order is evaluation order.
>
> ## Q5: What evaluating an assignment place produces
> **Vote: Q5-Y**
>
> **Reasoning:** This repo's codegen is written largely by models, and a model writing a C printer will hoist `&xs->data[0]` before the call unless the spec forbids it. Q5-Y states the rule where codegen authors (human or model) will read it. It also fixes the meaning of `xs[0] = grow(xs)` for users, and costs one sentence with no runtime cost. Leaving this to the as-if clause asks the reader to work out a memory-safety consequence alone.
>
> **Concern:** the wording must stay in terms of values the user can see (base value, index value, check at the store). If C terms such as "element address" leak into the user-facing text, they will confuse readers who never see C.

- **Minimalism:**

> # Minimalism (Min) — Phase C ballot
>
> ## Q1 — Core rule
>
> **Vote: Q1-W**
>
> **Reasoning:** One general rule makes three existing rules (§2.16 spreads, §4.6.3 `with` items, the §3c "equal to source order" promise) special cases of it. It also stops every future construct from needing its own order vote. Q1-U is not the smaller option: it adds a new idea, behavior the program cannot observe the same way twice, and nothing can diagnose it (§2.8 captured-cell writes have no effect row). A rule nobody can check is surface, not its absence.
>
> **Concern:** The as-if clause is where this rule can quietly erode. A later "pure arguments may reorder" optimisation could drift past what the effect row can prove, so the clause's observable list (output, binding values, which panic fires, termination) must stay in the text word for word.
>
> ## Q2 — Exception list and the status of bodies
>
> **Vote: Q2-A**
>
> **Reasoning:** Q2-A and my own Q2-B mean the same thing. Both list closed, conditional forms, and both put the closure literal in a separate sentence as a value whose body is not an operand. The only difference is whether loops sit in the list. Listing loops costs one word and gives DevOps a list that `blink explain` can print word for word, so I move to the majority text rather than keep a wording fork. I vote against Q2-C: putting closure literals *in* the exception list suggests that closure construction is partly lazy, and it invites "what other bodies are exceptions?"
>
> **Concern:** "Loops" in the list may be read as saying a loop's operands are unordered. The §2 loop sections must keep saying that each iteration's condition and body follow W.
>
> ## Q3 — Compound assignment `place op= rhs`
>
> **Vote: Q3-a**
>
> **Reasoning:** W says "exactly once", and today's literal rewrite evaluates the place twice. Q3-a is the one clause that removes that contradiction, and for a bare variable it changes nothing. Its order (place sub-expressions, old value, `rhs`, op, store) is not new: it is what `x = x op rhs` already means under W, because the left operand is read first. Q3-b would add a diagnostic to forbid legal code that has one meaning, and Q3-c would ship a spec that contradicts itself.
>
> **Concern:** Implementers may keep the §2.19 "purely syntactic rewrite" wording in their heads and duplicate the place in lowering. The amended §2.19 text must drop "purely syntactic" for places that are not bare variables.
>
> ## Q4 — Replacement for the §2.13 formatter sentence
>
> **Vote: Q4-a**
>
> **Reasoning:** Under W, reordering changes behavior, so the only correct formatter rule is "never reorder". It is also what src/formatter.bl already does, so the spec change removes a false sentence and adds no work. A lint (Q4-b) or a purity-gated reorder (Q4-c) builds tooling surface to enforce a style that §2.13 itself calls order-independent. PLT also showed Q4-b's "local name" criterion is unsound.
>
> **Concern:** Someone will later ask for declaration-order call sites as a style rule. That request must come as its own proposal, not as a quiet formatter change.
>
> ## Q5 — What evaluating an assignment place produces
>
> **Vote: Q5-Y**
>
> **Reasoning:** W already says "the place's sub-expressions, then rhs, then store", and the sub-expressions are the base and the index, which are values. Q5-Y states outright what W implies. That matters here because the wrong reading (hoist the element address before `rhs`) is a memory-safety bug, not a style difference, and the as-if clause cannot rule it out, because a dangling write is not an "observable difference" the clause lists. It costs one sentence: "Evaluating a place `base[index]` or `base.field` produces the base and the index or key; the element is located, and bounds-checked, at the store."
>
> **Concern:** If the sentence grows past one line into a place-evaluation model (lvalues, addresses, projections), it becomes more spec than the problem needs. Keep it to one sentence.

#### Moderator notes on the spec text

- **Nested places.** Sys's Q5 concern read intermediate element reads in a nested place (`a[i].f[j] = v`) as happening during place evaluation, before `rhs`. PLT's Q5 concern said the root binding is read, and the store and bounds check happen, after `rhs`, so that an `rhs` write to the same binding through a captured cell is not lost. The two readings differ for a nested place. §2.22 follows PLT's reading: place evaluation computes the index and key values along the path; the store reads the root, follows the path, checks bounds at each step and writes. This also meets Sys's request that the nested case be stated.
- **Loops.** Web asked that `while`, `loop` and `for` be named; Sys and Min asked that the text say a loop condition runs again under the rule each iteration. §2.22 does both.
- **Examples.** Web, AI/ML and PLT asked for the `n += bump()` example (prints 1) and the `bump() + n * 100` example (101). §2.22 includes both.

### AI-First Review

| Criterion | Result | Note |
|-----------|--------|------|
| Learnability | pass | One rule and a closed list of five forms; matches Python, JS, Java, Kotlin, C# and Swift |
| Consistency | pass | §2.16 spreads, §4.7 `with` items and §3c eager adapters become cases of the one rule |
| Generability | pass | No new syntax; code a model writes from its priors now means what it expects |
| Debuggability | pass | Output, `--trace` and the panic that fires follow the source text; no C-compiler-dependent result |
| Token Efficiency | pass | No `let` temporaries needed to fix an order |

### Final Spec

```blink
fn f(-- a: Int, b: Int) -> Int { a + b }

fn tick(n: Int) -> Int {
    io.println("{n}")
    n
}

fn main() {
    let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1: written order
    io.println("{tick(5)} {tick(6)}")   // prints 5, 6, then "5 6"

    let mut n = 0
    let bump = fn() -> Int {
        n = n + 1
        n
    }
    io.println("{bump() + n * 100}")    // 101: n is read after bump() returns

    let mut i = 0
    let next = fn() -> Int {
        i = i + 1
        i
    }
    let mut xs = [0, 0, 0]
    xs[next()] += 10                    // next() runs once: xs == [0, 10, 0]
}
```

- Every expression evaluates its operands exactly once, left to right in written order; a variable read is an evaluation at its written position; `?` or a panic stops the later operands (§2.22).
- Keyword arguments evaluate in written order and bind afterwards (§2.13).
- Closed list of forms that select which parts run: `&&`, `||`, `??`, `if`, `match` (arms and guards), `while`, `loop`, `for`. A closure literal is a value; its body runs at each call.
- As-if clause: reorder only when no program can observe it (output, any binding's value, which panic, termination). An empty effect row is not enough.
- `place op= rhs`: place sub-expressions once, then the current value, then `rhs`, then `op`, then the store (§2.19).
- Assignment places: index and key values first; root read, element lookup and bounds check at the store, after `rhs`.
- The formatter never reorders arguments, struct-literal fields or list elements; no lint now.
- Rejected: order unspecified.
