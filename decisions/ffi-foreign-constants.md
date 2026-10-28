[< All Decisions](../DECISIONS.md)

# Foreign Constants — Design Rationale

The signal numbers of `std.process` (`SIGBUS`, `SIGSEGV` and others) and the errno numbers of `std.libc` differ between hosts. `SIGBUS` is 7 on Linux and 10 on macOS. `ENOTSUP` is 95 on Linux and 45 on macOS. §4.4.8 names them as constants "because their numbers differ between hosts". No library could write a correct value. A module-level `let` initializer is static (§2.12.1): it cannot call a function or read another module `let`. A `const` cannot call (§2.21). The language has no conditional compilation, and `decisions/cpu-intrinsics.md` rejected it. So the spec had no way to say "the number that this target's C headers give".

The panel added one mechanism, the **foreign constant**: an `@ffi` annotation on a module-level `let` with no initializer. The C compiler of the build target sets its value. The front end sees only the type.

**Note on syntax.** The panel wrote keyword parameters with `--` (for example `fn stop(c: Child, -- sig: Int = SIGTERM)`). The marker in the spec is `*,` (§2.13), and `--` is a reserved token (§2.19). Every quote below keeps the panel's `--`, and it means the `*,` marker. The spec text uses `*,`.

**Result.**

| Question | Result | Ruling |
|----------|--------|--------|
| Accepted by all six, no vote | 6-0 | Foreign constants are user-visible, not std-only. The compiler checks, for each build target, that the C name is an integer constant expression that fits the declared type; a failure is a Blink diagnostic at the declaration, never a raw C error. No `@trusted`. Only `Int` or a sized integer type. `let mut` with the form is an error. A `const` initializer that names one is `NonConstExpr`. A range-pattern bound that names one is `RangeBoundNotConst` (E0323). A guard and any fn body are allowed. A lone name in a pattern stays a binder, as today. |
| Q1. Static or const | F, 6-0 | A foreign constant is static, not const. The C compiler sets the value. The front end sees only the type, so `blink check` gives the same result on every target. |
| Q2. Module-level `let` initializer | a, 6-0 | A bare leaf only: the name alone, or an element of a list, tuple, struct or variant literal. An operator over it is `NonInitExpr` (E1129). |
| Q3. Defaults | b, 4-2 in Phase C, 6-0 after Phase D | A keyword default may be a bare foreign constant. A struct field default may not. |
| Q4. Spelling | a, 6-0 | `@ffi(...)` on a bodyless `let`. Same arguments and native-dependency rules as `@ffi fn`. |
| Q5. `header:` | a, 5-1 | Required. Minimalism dissents. |

### Panel Deliberation

#### Phase A — Independent proposals

Each seat proposed a shape alone. F means a foreign constant: static, not const, with the value set by the C compiler. T means a real `const` with a value from a table per target.

**Systems** (sys):

> The source of truth for SIGBUS on a triple is `<signal.h>` for that triple. The front end does not have it; the C compiler does. So the language should not pretend the front end knows the value. Name the C macro, and let the C compiler fill it in.
>
> Recommendation: S1, user-visible, static and not const, with the emitted constant check so that a non-constant macro cannot slip through as a run-time read.


**PLT** (plt):

> **Type checking does not depend on the target.** A program that type-checks for one triple type-checks for every triple, with the same errors, warnings, exhaustiveness and overlap results. decisions/cpu-intrinsics.md ("no conditional compilation on the target") is a special case of this principle. If the front end knew a different value per target, the judgment Γ ⊢ e : T would become Γ ⊢_τ e : T, indexed by the triple. That is conditional compilation that goes in through the const evaluator.
>
> **Declaration.** An `@ffi` binding can name a C integer constant, as it names a C function today. The declaration has a type and no initializer. The writer chooses the exact spelling. My shape:


**DevOps/Tooling** (devops):

> Seat: DevOps/tooling. My lens is what the error, the hover and the cross build look like. Summary: the C headers of the target already hold the right numbers, and our pipeline already runs a C compiler for that target. Let the C compile set the value. Keep the front end target-blind, so `blink check`, the LSP and the diagnostics give one answer for every target.


**Minimalism** (min):

> Seat: Minimalism. Summary: the C compiler already has the right number for each target. The front end does not need it, so do not teach the front end. Add one small form to escape hatch 1: an `@ffi` value binding. Do not add a new kind of const, a target table or an exception to §2.12.1.


**Web/Scripting** (web):

> A JS or Python developer types `import std.process.{SIGBUS}` and expects one thing: a constant that holds the right number on the machine the program runs on. They do not want to learn a third kind of binding ("static but not const"). So my vote: make the 18 values real `const` items, with each target's number in a table that the compiler holds. The user sees `pub const SIGBUS: Int`, and the existing rules give the answers to Q2 and Q4 with no new rule. My first choice is P1. P2 is a fallback if the panel will not put a per-target table in the front end. I reject "do nothing" and the OCaml-style portable numbers (reasons at the end).


**AI/ML** (aiml):

> What matters for an AI is how the use site looks, not how std declares it. Models arrive with a strong prior from Rust `libc::SIGBUS`, Go `syscall.SIGBUS` and Python `signal.SIGBUS`: a signal number is a plain constant, legal anywhere a number literal is. Each place where `SIGTERM` works but a "target constant" does not is a decision point that the spec must teach, and that models will get wrong. So I want the use site to behave exactly like a `const`, with zero new rules for users.


#### Phase B — Debate highlights

The seats read all six proposals and replied once. The quotes below show the position shifts. **(dissent)** marks a position that the other seats did not take.

**PLT** (plt):

> **P withdrawn.** No seat supports it, and sys/web are right: it doubles the number space at every C crossing (raw errno from a user @ffi binding). Drop it from the ballot.


**Web/Scripting** (web):

> I proposed T because I wanted the use site to read like a plain const. plt and devops showed me that T has a higher DX cost than I said. Under T, `blink check` and the LSP give the answer for one target only:
>
> My one real objection to F was the keyword default `sig: Int = SIGTERM`, the line that every Python dev writes. devops's F-2 removes that objection, so I can vote F. With F-1 and F-2 allowed, F has a five-minute rule: **"The compiler does not know the number. Only places where the compiler must compute the number reject it: a `const` and a range bound."** Every other place works.


**AI/ML** (aiml):

> Two arguments from the other seats change my vote. Both are also AI/ML arguments.
>
> 1. Target-blind checking (plt, devops). An agent works in a loop: edit, `blink check`, read the errors, fix. Under T, `blink check` on a Linux dev box can be clean, and the macOS cross build in CI can then report an unreachable arm or E0546 on `1 / (SIGBUS - 7)`. The agent cannot reproduce that error where it runs. That is the Rust `cfg` pain that models handle worst. Also, under T, `const ON_MAC = SIGBUS == 10` is a working OS probe. Models WILL find it and copy it, because it is the shortest way to write "if macOS". F makes that line an error with a clear cause.
>
> 2. User-visible need (sys, min, plt, devops). T is std-only, so a model that writes an FFI wrapper for `O_NONBLOCK` or `AF_INET6` still has to pick a literal. That literal is right on Linux and wrong on macOS, and it goes into the training data. Under F, the same `@ffi` form that the model already knows from `@ffi fn` gives the right value. Std-only was my YAGNI call, and I was wrong: the demand exists today, in every libc wrapper.


**Systems** (sys):

> **plt's target-blind typing argument decides it for me.** Under T this program is clean on Linux and fails only in the macOS cross build:
>
> **F-2 (defaults): I move to allowing a keyword default as a bare leaf. A struct field default stays an error.**
>
> Why the split: the compiler fills a keyword default at each call site. The caller's TU emits `SIGTERM` as an immediate, at zero cost, and nothing is folded in the front end. A struct field default also feeds `const X = Opts {}` (§2.21 uses field defaults in const struct literals). Allowing it would put a foreign value into a `const` through a hidden path. If the panel wants one rule for both defaults, I accept "both are errors" over "both OK". I will not accept "both OK".


**PLT** (plt):

> **F-2 (keyword default, struct field default). I change from error to OK, for a bare leaf only.** The principle that decides it: *a foreign constant is allowed wherever the front end does not need its value.* A default is filled at each call site. A bare leaf has no evaluation that could panic, and it gives no effect and no order. So the default is sound, and typing stays target-independent. That leaves exactly two contexts that reject it, `const` and range bound, and both need the value at type check. That is one rule users can learn, not a list. It also fixes the line that aiml and web say models will write:
>
> **F-3 + F-4 should merge into one choice. They are the same decision.** If the C-side constant check (sys/devops: `enum { k = (SIGBUS) };` plus a fit `_Static_assert` for sized types) is mandatory, then no claim is left unchecked: the value is an integer constant expression, and it fits the type. `@trusted` is for an unchecked claim that soundness depends on, so it would be ceremony with nothing to audit. I change to: **mandatory check, no `@trusted`.** A failure maps to a new Blink diagnostic at the declaration span, as devops designed. I keep my objection to the other combination (no check and no trust). sys's `errno` example shows it: without the check, `@ffi("errno") let E: Int` silently becomes a run-time thread-local read in each function. That makes the "static" classification false, which breaks F-1 and F-2. So the check is load-bearing for soundness, not a nicety.


**Minimalism** (min) **(dissent)**:

> ## F-2, defaults: error (no change)
> I agree with sys and plt. A default is a const context (§2.13, §2.14). devops's "third class" adds a rule ("static, not const, but OK in defaults") for one convenience.


**Minimalism** (min):

> ## F-3 + F-4 are one choice. Merge them. I CHANGE to: an emitted C check, no `@trusted`.
> `@trusted` stands for a claim that the compiler cannot check. With the sys/devops C check (`enum { k = (SIGBUS) };` plus a fit check for a sized type), the compiler does check it. A missing name, a non-constant (`errno`, glibc `SIGRTMIN`) and a value that does not fit all fail the build. No unchecked claim is left. Then 18 audit strings would be ceremony. That is surface that buys nothing. So:


**AI/ML** (aiml) **(dissent on arithmetic)**:

> Min's E1129 here costs us the most common module-level use and buys nothing: an `@ffi` constant has no cell and no init, so no order issue exists. About arithmetic (`let NEXT = SIGTERM + 1`, `let WANT = POLL_EVT_IN | POLL_EVT_OUT`): I prefer to allow any operator that a const expression allows, over foreign leaves. C folds it at file scope, and the emitted check (F-4) turns an overflow into a Blink error at build time. Then the rule is "a foreign constant is static wherever a const is static". That is one rule, not "bare leaf only". I accept plt's bare-leaf v1 as a fallback, but only if E1129's help then names the cause ("arithmetic on a foreign constant; write it in a fn").


**DevOps/Tooling** (devops):

> ## F-5, spelling: I switch to sys and plt, `@ffi("SIGBUS", header: "signal.h") pub let SIGBUS: Int`, and drop `@ffi.const`.
> One annotation name means the LSP, `blink doc` and `blink audit` handle one `@ffi` family. The user form for a library is sys's two-argument form (`@ffi("curl", "CURLE_OPERATION_TIMEDOUT", header: "curl/curl.h")`) with the existing E0820 rule. One addition, against min's form with no header: `header:` is required on a foreign constant. A macro has no linkage, so without its header the C compile cannot see it. A missing `header:` is a new error at the declaration, not a cc error later.


#### Phase C — Final vote

Each seat voted alone. Each block below is the full text of that seat's answer to that question.

##### Q1. Static or const (F or T)

Result: F 6-0.

**Systems** (sys):

> **Q1. Vote: F.**
> Reasoning: under T and under F the code that runs is the same: one compare against an immediate. T still needs the target headers in every user TU (aiml's `_Static_assert`) and also keeps a per-triple table. So T is F's work plus a second source of truth. F is right on every triple that the C toolchain has headers for, including the ones nobody tests, such as Linux MIPS SIGBUS 10. It keeps the front end target-blind.
> Concern: a misspelled C name shows up only at `blink build`, not at `blink check` or in the LSP, so an edit-check loop stays green until the first build.


**Web/Scripting** (web):

> **Q1. Vote: F**
> Reasoning: Under F, `blink check` gives one result on every machine. Under T, a user sees a green check on a Linux laptop and an unreachable-arm or E0546 error in the macOS CI, and cannot reproduce it. A "works on my machine" puzzle costs more DX than the two contexts F rejects (`const` and range bound). Those two get a local error that names the cause. F also serves users who write FFI wrappers (`O_NONBLOCK`, `AF_INET6`). T leaves them with literals that are wrong on one OS.
> Concern: users will write `assert_eq(SIGBUS, 7)` or `const X = SIGBUS` and not know why it fails. So the NonConstExpr / E0323 help and the hover must say "foreign constant: the target's C headers set its value".


**PLT** (plt):

> **Q1. Vote: F.**
> Reasoning: type checking must give the same result on every target. Under T it does not: `1..=SIGBUS` overlap, E0546 on `SIGSEGV - SIGBUS - 1`, and `const ON_MAC = SIGBUS == 10` all change with the triple. Under F, the type checker gets only a type, never a number, so its result does not depend on the target. The C headers are the only source of the number, so no table can drift.
> Concern: users may read "foreign constant" as "constant" and keep writing `const X = SIGBUS`. The NonConstExpr and E0323 help must name the cause in one sentence.


**DevOps/Tooling** (devops):

> ## Q1. Main choice
> **Vote:** F
> **Reasoning:** With F, `blink check`, the LSP and every front-end diagnostic give one result for every target. A user can reproduce on their own machine any error the cross CI shows. T makes reachability, E0546 and E0318 depend on the triple, so the LSP needs a target setting and a clean check on Linux can fail on macOS. The C compiler that already runs is the only source of the number, so no table can drift.
> **Concern:** A misspelled macro shows up only at `blink build` or at the per-triple archive build, not at `blink check` or in the LSP. That is a slower edit loop for that one class of error.


**AI/ML** (aiml):

> ## Q1. Main choice
> Vote: F
> Reasoning: An agent's loop is edit, `blink check`, fix. Under T, that loop gives a green result on Linux and a red one in the macOS CI, and the agent cannot reproduce the CI result. Under F, both lines models write most (`let FATAL = [SIGSEGV, SIGBUS]` and `-- sig: Int = SIGTERM`) still compile, given Q2 and Q3. F also gives user FFI wrappers the right `O_NONBLOCK`, where T sends them back to literals that are wrong on one host. Those literals become training data.
> Concern: a misspelled C name surfaces only at `blink build`, not at `blink check`. So a check-only agent loop can pass with a declaration that never builds.


**Minimalism** (min):

> ## Q1. Main choice
> Vote: F
> Reasoning: The C compiler already holds the right number for every triple, so a table in the front end is a second copy that can only be wrong. T makes the result of `blink check` depend on the target (`const ON_MAC = SIGBUS == 10` would act as an OS probe), and it is std-only, so it gives std a privilege that users cannot get. F adds no table, no new kind of `const` and no target knowledge to the front end.
> Concern: if the help text for the NonConstExpr and E0323 errors does not name the foreign constant and say why, users will hit a rule they cannot explain.


##### Q2. Module-level `let` initializer

Result: a 6-0.

**Systems** (sys):

> **Q2. Vote: a (bare leaf only).**
> Reasoning: the hardware cost of a leaf is zero. The init stores an immediate, or a C file-scope initializer holds the constant, and no Blink rule needs the value. Arithmetic would fold in C too, but then a C compiler enforces Blink's overflow and division rules (E0546), and those are front-end rules. The leaf keeps that line clean, and widening it later is backward compatible.
> Concern: `let WANT = POLL_EVT_IN | POLL_EVT_OUT` is a real poll-mask pattern, and its E1129 help must say "a foreign constant is static only as a bare name; compute it in a fn" or users will loop on it.


**Web/Scripting** (web):

> **Q2. Vote: a (bare leaf only)**
> Reasoning: `let FATAL = [SIGSEGV, SIGBUS]` is the line people write, and a leaf allows it. Arithmetic in a module initializer on a signal or errno number is rare, and "compute it in a fn" is an easy fix. Widening later breaks nobody. Narrowing later would break code.
> Concern: `let WANT = POLL_EVT_IN | POLL_EVT_OUT` is a plausible line for a poll user, so the E1129 help must name the cause ("arithmetic on a foreign constant; write it in a fn"). The generic "make it a `const`" help would be wrong here, and users could not follow it.


**PLT** (plt):

> **Q2. Vote: a (bare leaf only).**
> Reasoning: §2.12.1 bans a read of a module `let` so that initializers cannot see each other: no order, no cycle. A foreign leaf has no Blink initializer, so adding it keeps that guarantee exactly. Arithmetic over an opaque leaf raises Blink overflow and `/0` questions that the front end cannot decide. Option b moves those checks into the C compiler, which then enforces a Blink rule (E0546) with C's semantics. A strict leaf keeps the grammar a plain extension, and the panel can widen it later without breaking code.
> Concern: `let WANT = POLL_EVT_IN | POLL_EVT_OUT` will be a common E1129. The help must say "compute it in a fn".


**DevOps/Tooling** (devops):

> ## Q2. Module-level `let` initializer
> **Vote:** a (bare leaf only)
> **Reasoning:** A bare leaf needs no evaluation, so no overflow or `/0` question can come up before `main`, and the C compiler never enforces a Blink rule. The E1129 help for `SIGTERM + 1` can name the exact cause ("arithmetic on a foreign constant; compute it in a fn"). The rule can widen later without breaking code.
> **Concern:** `let WANT = POLL_EVT_IN | POLL_EVT_OUT` is a real poll-mask pattern, and it fails. The E1129 help must give that fix, or users will see the error as arbitrary.


**AI/ML** (aiml) *(position change: changed from b in Phase B)*:

> ## Q2. Module-level `let` initializer
> Vote: a (bare leaf only). I drop my Phase B "b".
> Reasoning: With Q3 = c, "a foreign constant is OK only as a bare name" is one rule in every static context. That is fewer decision points than "operators in initializers, but bare names only in defaults". Plt is right that overflow is a front-end rule, and C must not enforce it. Adding operators later is backward compatible.
> Concern: `let WANT = POLL_EVT_IN | POLL_EVT_OUT` gets E1129. The help must name the cause ("arithmetic on a foreign constant: compute it in a fn"), or models will loop on the error.


**Minimalism** (min):

> ## Q2. Module-level `let` initializer
> Vote: a (bare leaf)
> Reasoning: §2.12.1 bans the read because of init order and cycles. A foreign constant has neither, so one leaf is the smallest rule that keeps the guarantee. Option b brings Blink's overflow and `/0` rules onto an operand that the front end cannot see, and so a C compiler would enforce a Blink rule. If a real need appears, we can add arithmetic later and break nothing.
> Concern: `let WANT = POLL_EVT_IN | POLL_EVT_OUT` will be the first E1129 that people hit, so its help must say "compute it in a fn".


##### Q3. Keyword default and struct field default

Result: b 4, c 2 (sent to Phase D).

**Systems** (sys):

> **Q3. Vote: b (keyword default OK as a bare leaf; struct field default an error).**
> Reasoning: a keyword default is filled in the caller's TU, which emits the macro as an immediate, and nothing reads that default back as a const. A struct field default is different, because §2.21 fills omitted fields from their defaults inside a `const` struct literal. Under c, `type Opts { sig: Int = SIGTERM }` followed by `const D = Opts {}` puts a foreign value into a `const` through a path the user cannot see. Then either that const line needs its own new error, or the const evaluator meets an opaque value. No round 1 reply under c addressed this case.
> Concern (c is likely to win): the writer must then state what `const D = Opts {}` gives when a field default is a foreign constant. I would make it NonConstExpr at the `const`, with the help naming the field, so the hole does not ship unstated.


**Web/Scripting** (web):

> **Q3. Vote: c (both OK as a bare leaf)**
> Reasoning: `fn stop(c: Child, -- sig: Int = SIGTERM)` is what every Python/JS developer writes, and a split between keyword defaults and field defaults is one more rule with no reason a user can see. With c, the whole user rule is one sentence: "only `const` and range bounds reject a foreign constant, because only there must the compiler compute the number". Hover and `blink doc` show `sig: Int = SIGTERM`, the name, which reads best.
> Concern: sys's hidden path. `const D = Opts {}`, which omits a field whose default is a foreign constant, must be NonConstExpr with a help that points at the field default. If not, the foreign value leaks into a `const`.


**PLT** (plt) *(position change: changed from c)*:

> **Q3. Vote: b (keyword default OK as a bare leaf; struct field default is an error).** I change from c.
> Reasoning: sys's point is correct, and c is unsound as it stands. §2.21 fills omitted fields of a const struct literal from the field defaults. So `type Opts { sig: Int = SIGTERM }` followed by `const O = Opts {}` would put an opaque value into a `const`, a value the front end must evaluate. A keyword default cannot reach a const context, because a call is never const. So b admits exactly the case that is sound. c would need a non-local rule ("a struct literal that omits a field with a foreign default is not const") to repair it.
> Concern: users will ask why `fn stop(-- sig: Int = SIGTERM)` works and `type Opts { sig: Int = SIGTERM }` does not. The field-default error help must give the const-struct-literal reason.


**DevOps/Tooling** (devops) *(position change: changed from c)*:

> ## Q3. Defaults
> **Vote:** b (keyword default OK as a bare leaf, struct field default an error). I change from c.
> **Reasoning:** sys showed a hidden path that I missed. §2.21 fills omitted fields from the field defaults in a const struct literal. Under c, `const X = Opts {}` would fail far from its cause, on a line that names no foreign constant. That needs a diagnostic chain from the const to the field default, and users will read it as a confusing error. Nothing reads a keyword default from a const context: it is filled at each call site. So b allows the line people write (`sig: Int = SIGTERM`) and has no hidden path.
> **Concern:** Users will ask why `sig: Int = SIGTERM` works in a fn but not in a type. The NonConstExpr help on the field default must name the const-struct-literal reason in one line.


**AI/ML** (aiml):

> ## Q3. Keyword default and struct field default
> Vote: c (both OK as a bare leaf)
> Reasoning: `fn stop(c: Child, -- sig: Int = SIGTERM)` is the line I measured, and gen1 rejects it today. Models copy it from Python and from every signal API. Splitting keyword defaults from field defaults (b) adds a decision point that no model will guess. Sys's concern about `const X = Opts {}` takes a rule: a const struct literal that would fill a field default which names a foreign constant is NonConstExpr, with the same help. That rule is consistent with "a const needs the value".
> Concern: the `const X = Opts {}` case above must be specified and tested. If it is not, a foreign value reaches a `const` through the field default and breaks the target-blind front end.


**Minimalism** (min) *(position change: changed from a)*:

> ## Q3. Keyword default, struct field default
> Vote: b (keyword default OK as a bare leaf; field default is an error)
> Reasoning: I move from a to b. plt's principle, "allowed where the front end does not need the value", explains the split. A keyword default never feeds a const context. A struct field default does: `const X = Opts {}` fills it (§2.21), so c lets a foreign value into a `const` by a hidden path, or it needs one more rule at that site. b gives the common line (`-- sig: Int = SIGTERM`) and keeps the const contexts closed with no new interaction.
> Concern: if c wins, the spec must still decide what `const X = Opts {}` does when `Opts` has a foreign-constant default. I expect NonConstExpr at the const, which is one more rule to state and test.


##### Q4. Spelling

Result: a 6-0.

**Systems** (sys) *(position change: changed from b)*:

> **Q4. Vote: a (`@ffi` on a bodyless `let`). I change from b.**
> Reasoning: min, plt and web are right that `.const` names the binding after the one thing it is not, and the reader then writes `const X = SIGBUS` or a range bound. My concern was that `@ffi("NAME")` reads as a linked symbol. The item kind settles that, because a `let` cannot be a function symbol. So `blink audit` and the emitter can tell the two forms apart with no new attribute name.
> Concern: `blink audit` and the symbol and link tooling must branch on the item kind. If one tool treats an `@ffi let` name as a link symbol, it reports a missing symbol for every macro.


**Web/Scripting** (web):

> **Q4. Vote: a (`@ffi` on a bodyless `let`)**
> Reasoning: One annotation family to learn. A developer who has bound a C function with `@ffi("cos", header: "math.h")` already knows how to bind a C constant. `@ffi.const` puts the word "const" on a thing that is not a const, and that makes people write `const X = SIGBUS` and hit NonConstExpr.
> Concern: a bodyless `let` with no `@ffi` must get a clear "missing initializer" error, not a parse error that confuses people.


**PLT** (plt):

> **Q4. Vote: a (`@ffi` on a bodyless `let`).**
> Reasoning: it is the value-shaped twin of `@ffi fn`, with the same arguments and the same native-dependency gate, so it adds no new attribute name. `@ffi.const` names the binding after the one thing it is not (a `const`), and that invites the Q1 confusion.
> Concern: `blink audit` and the linker model treat `@ffi` names as linked symbols (sys). Tooling must not list a foreign constant as a symbol that needs linking.


**DevOps/Tooling** (devops):

> ## Q4. Spelling
> **Vote:** a (`@ffi("SIGBUS", header: "signal.h") pub let SIGBUS: Int`)
> **Reasoning:** Tooling (LSP, `blink doc`, `blink audit`) then handles one `@ffi` family, and the item kind tells the tool which binding it is. `@ffi.const` on a `let` puts the word "const" on a thing that a `const` cannot use, which invites the NonConstExpr loop that web and aiml describe. sys's "a macro is not a linked symbol" point is real, but `blink audit` can show the kind ("constant") from the item.
> **Concern:** Tools that treat each `@ffi` name as a link symbol (audit output, any symbol check) must branch on the item kind, or they will report a macro as a missing symbol.


**AI/ML** (aiml):

> ## Q4. Spelling
> Vote: a (`@ffi("SIGBUS", header: "signal.h") pub let SIGBUS: Int`)
> Reasoning: It copies the `@ffi fn` form exactly, including the two-argument native-dep form, so a model that can bind `cos` can bind `SIGBUS` with no new attribute name. `@ffi.const` puts the word "const" on a binding that is not a `const`, and models will then use it in a `const` or a range bound.
> Concern: `blink audit` and the docs must say that an `@ffi let` names a value from a header, not a linked symbol. Sys's point is that `@ffi` otherwise reads as "link symbol".


**Minimalism** (min):

> ## Q4. Spelling
> Vote: a (`@ffi` on a `let` with no body)
> Reasoning: It is one attribute family, the same argument shape as `@ffi fn`, and the item kind tells the two apart. `@ffi.const` adds a name and puts the word "const" on a thing that is not a `const`.
> Concern: `blink audit` and any tool that treats every `@ffi` name as a symbol to link must learn that an `@ffi let` names a macro that has no address.


##### Q5. `header:` required

Result: a 5, b 1 (min dissents).

**Systems** (sys):

> **Q5. Vote: a (required).**
> Reasoning: an `@ffi fn` can omit `header:` because the compiler emits its own prototype and the linker resolves the symbol. A macro has no linkage and no prototype, so nothing can stand in for the header. The value exists only after the preprocessor has seen the header, in every TU that reads the constant. With `header:` optional, a missing header shows up as a raw "undeclared identifier" in generated C, or the TU works by accident through some other include. The second case is worse, because it breaks when an unrelated include changes or on another libc.
> Concern: if b wins, the "header rule supplies the header" must be a specified rule that the compiler checks, not "some include happens to define it", or the result depends on the include order of other modules.


**Web/Scripting** (web):

> **Q5. Vote: a (header required)**
> Reasoning: A macro has no linkage, so without its header the C compile cannot see it. The user would then get a late cc error from generated C, which is the error every seat agreed to prevent. When `header:` is required, a missing one is a front-end error at the declaration in `blink check`, which needs no C toolchain. "Optional where the header rule supplies it" is the kind of rule that gets Stack Overflow questions: "why does `@ffi("SIGBUS")` work here and not there?" A required argument is one more word in each declaration, and it is never a puzzle.
> Concern: users who copy an `@ffi fn` declaration without `header:` will hit the new error. Its help must give the fix directly (`add header: "signal.h"` style), not only say that the argument is missing.


**PLT** (plt):

> **Q5. Vote: a (header required).**
> Reasoning: a macro has no linkage. An `@ffi fn` with no header can still work through an emitted prototype, but a constant has no such fallback. A front-end error at the declaration comes earlier and is the same on every target. The alternative is a C-side check failure that depends on what the default includes pull in on that triple, so the result can depend on the target.
> Concern: one more required argument than `@ffi fn` has, which users who copy the fn form will hit once.


**DevOps/Tooling** (devops):

> ## Q5. `header:` required?
> **Vote:** a (required)
> **Reasoning:** On an `@ffi fn`, `header:` is optional because the compiler can emit its own prototype and the linker resolves the symbol. A macro has no linkage and no prototype the compiler can write, so without its header the name can never exist in the TU, and "the header rule supplies it" never applies. Optional only moves the error from a clear "a foreign constant needs `header:`" at the declaration to a later "not defined on <triple>" that blames the target.
> **Concern:** If b wins, the F-4 diagnostic for a declaration with no `header:` must say "no header given", not "not defined on <triple>". Otherwise users chase a target problem that does not exist.


**AI/ML** (aiml) *(position change: changed from b)*:

> ## Q5. `header:` required?
> Vote: a (required). I change from b.
> Reasoning: A macro has no linkage, so the header is the only way the C compile can see it. Where `@ffi fn` can fall back to a prototype that the compiler writes, a constant has no such fallback. If `header:` is optional, a declaration works on the host only because some runtime header happens to include `<signal.h>`, and it fails elsewhere. Models write that silent host-only pass more than any other error. A required `header:` gives a local error at the declaration on every target, for the cost of one argument that every example will show anyway.
> Concern: models trained on `@ffi fn` examples with no `header:` will leave it off. The error must say "a foreign constant needs `header:`" and give a fix with the header name in it.


**Minimalism** (min) **(dissent)**:

> ## Q5. `header:` required?
> Vote: b (optional, as for an `@ffi fn`)
> Reasoning: One header rule for the whole `@ffi` family is smaller than two. The check that every seat accepts already turns a name that the C compiler cannot see into a Blink error at the declaration, so a "header required" rule would report a failure that the check reports anyway. For std, the runtime headers already supply `signal.h`, `errno.h` and `poll.h`.
> Concern: the "not defined for target" diagnostic must suggest adding `header:` when the declaration has none, or a user who left it out will think the macro does not exist.


#### Phase D — Round 2

Q3 got 4-2 in Phase C. A result closer than 5-1 gets one focused round, so the panel debated Q3 only. Q1, Q2, Q4 and Q5 stayed closed. Each seat replied once (D1), then voted alone (D2). The ballot was: (b) keyword default OK as a bare leaf, struct field default an error; (c) both OK as a bare leaf. After D1, web and aiml changed from c to b. The D2 vote was 6-0 for b.

**Minimalism** (min), D1 reply (excerpt):

> Q3: I hold b.
>
> The strongest point for c is web's one-sentence rule: "only `const` and range bounds reject a foreign constant." Under c that sentence is false. Both web and aiml concede that c needs a third case:
> ```blink
> type Opts { sig: Int = SIGTERM }    // c: OK
> const D = Opts {}                   // c: error[NonConstExpr], on a line that names no foreign constant
> ```
> So the honest rule under c has three cases, and the third is non-local. The error fires at `const D`, and its cause is in a type that can be in another module. If `Opts` lives in a library, the library author can break a downstream user's `const` just by adding a defaulted field. That makes a field default part of a type's const-compatibility, which is new API surface that nobody has asked for.


**Minimalism** (min), D2 vote:

> Vote: b
> Reasoning: Under b, each error is on the line that names the foreign constant, so the rule stays local. Under c, a library that changes a field default to `SIGTERM` silently breaks a downstream `const X = Opts {}`, which makes a field default part of the type's const API. b already accepts the case that has real demand, `-- sig: Int = SIGTERM`, and widening b to c later breaks no program.
> Concern: the field-default error must give the reason and a fix in one line (a keyword default on a constructor fn, or an `Option[Int]` field), or users will read the split as arbitrary.


**PLT** (plt), D1 reply (excerpt):

> **Position: b. No change.**
>
> **The strongest point for c** (web, aiml): one user rule, "only `const` and range bounds reject it", plus a repair for the hidden path: `const X = Opts {}` is NonConstExpr when it would fill a foreign field default. I accept that the repair is sound, so c is no longer unsound. My objection is now about composition, not soundness.
>
> **Why c's repair does not compose.** Under c, whether a struct literal is const depends on the defaults of the fields it omits. That is a property of another module's type body, and the use site does not show it.
>
> ```blink
> // lib a, v1
> pub type Opts { sig: Int = 15 }
>
> // lib a, v2: a fix, so the number is right on macOS
> pub type Opts { sig: Int = SIGTERM }
>
> // user module, which compiles against v1
> const DEFAULT_OPTS = Opts {}      // under c with v2: NonConstExpr. The line names no foreign constant and did not change.
> ```
>
> - **A silent break across modules.** A library author changes one default to the correct form, and downstream `const` items stop compiling. Nothing in the library's public signature changed to warn either side. Under b, the library author meets the error in their own module, at the line they wrote.
> - **c is not one rule.** The real rule is "only `const` and range bounds reject it, and also any const struct literal that omits a field whose default names one". That is the same decision point web and aiml want to avoid. It sits at a site that is harder to explain, because the error points away from the line the user wrote.


**PLT** (plt), D2 vote:

> Vote: b
> Reasoning: A foreign leaf is allowed only where no `const` context can reach it. A keyword default is filled only at a call, and a call is never const, so it qualifies. A field default can fill a const struct literal (§2.21), so it does not. c is sound only with a repair at the `const` site. That repair makes a type's const-compatibility depend on its field defaults, a non-local property, so changing a default in a library silently breaks downstream `const` items. b keeps every error local to the line that names the foreign constant, and widening b to c later breaks no program.
> Concern: the field-default NonConstExpr help must state the const-struct-literal reason and a fix (a keyword default on a constructor fn, or an `Option[Int]` field). Without that help, the split reads as arbitrary.


**Web/Scripting** (web), D1 reply (excerpt):

> **Q3: I change from c to b.**
>
> The strongest point on the b side is devops's: under c, the error lands on a line that names no foreign constant. I accepted that in my own Phase C concern, but I under-rated what it costs a user. The worst case is across packages:
>
> ```blink
> // lib v1.2 (a library)
> pub type KillOpts { sig: Int = 15 }
>
> // lib v1.3: the author changes it to the correct, portable value
> pub type KillOpts { sig: Int = SIGTERM }     // under c: OK, and the library's own tests pass
>
> // user code, unchanged since v1.2
> const QUIET = KillOpts {}                    // under c: NonConstExpr after an upgrade, in a file the user did not touch
> ```
>
> A minor upgrade breaks downstream code, and the error points at the user's line, not at the change that caused it. That is a "my build broke and I changed nothing" question, and it is worse DX than any one-line rule. Under b, the library author gets the error at the field default, in their own file, when they make the change. A local error is better than a distant one.


**Web/Scripting** (web), D2 vote:

> Vote: b
> Reasoning: The line Python/JS developers write, `fn stop(c: Child, -- sig: Int = SIGTERM)`, compiles under b, and that was the case I cared about. Under c, a library author who changes a field default to `SIGTERM` breaks each downstream `const X = Opts {}`, with an error on a line that names no foreign constant. That is a "my build broke and I changed nothing" question. Under b the author gets the error on the line they just wrote. A local error beats a distant one, and widening b to c later is backward compatible.
> Concern: users will still ask why `sig: Int = SIGTERM` works in a fn and not in a type. So the field-default help must give the reason and a fix (a keyword default on a constructor fn, or an `Option[Int]` field) in one line, and a test must pin both lines.


*Position change: from c to b.*

**DevOps/Tooling** (devops), D1 reply (excerpt):

> Q3 only. My position stays b.
>
> **The strongest point for c (web, aiml)** is a one-sentence user rule: "only `const` and range bounds reject a foreign constant." I agree it reads better. But both c voters concede that c needs a second rule to close sys's hidden path: `const D = Opts {}` is NonConstExpr when an omitted field has a foreign default. With that rule added, c is not one sentence either. It is the same sentence plus an error at a distance. And that error is worse than the one b gives.
>
> **Why the c fix is a bad diagnostic, and a library hazard.** Under c the error lands on a line that names no foreign constant. Often that line is in another package:
>
> ```blink
> // lib v1.0 (package "proc_opts")
> pub type Opts {
>     sig: Int = 15
> }
>
> // lib v1.1: the author fixes the literal, as this panel says they should
> pub type Opts {
>     sig: Int = SIGTERM            // c: OK, no error here
> }
>
> // user crate, unchanged; it compiled against v1.0
> const DEFAULTS = proc_opts.Opts {}  // c: NonConstExpr after upgrading to v1.1
> ```
>
> - **For the library author:** they make a correct-looking fix and their own build stays green. They cannot see that they broke a downstream `const`. Under c, a field default becomes part of a type's semver surface in a way no tool flags.
> - **For the user:** the error points at a line they did not change. The cause is in a dependency, so the LSP must chain the help through the type to a field in another package to explain it.


**DevOps/Tooling** (devops), D2 vote:

> **Vote:** b
> **Reasoning:** Under b, every error lands on the line that names the foreign constant, in the build of whoever wrote it. The span is local and the help can fix it in place. Under c, a library author's correct fix to a field default breaks downstream `const` items in other packages. The error then points at a line the user never changed, and no tool warns the author. b still accepts the line people write, `fn stop(c: Child, -- sig: Int = SIGTERM)`, and widening b to c later breaks no code.
> **Concern:** If the field-default NonConstExpr help does not give the reason and a fix in one line, users will read the keyword/field split as arbitrary. The help must say "a `const` struct literal can fill it" and offer a keyword default on a constructor fn or `Option[Int] = None`.


**AI/ML** (aiml), D1 reply (excerpt):

> Q3: I change from c to b.
>
> The strongest point for b is the one devops made: under c, the error lands far from its cause. On debuggability, that decides it for me. An agent fixes the line that the error names. Under c, the error is on `const X = Opts {}`, and that line has no foreign constant in it. The real cause is in a type definition, perhaps in another module. Models handle a non-local error like that badly: they edit the `const` line, and then loop. Under b, the error is on the line the model just wrote, `type Opts { sig: Int = SIGTERM }`, and a one-line help can fix it there.
>
> Second point, which no seat has raised yet: c makes a field default part of a library's const contract. Under c, a library author changes `type Opts { sig: Int = 15 }` to `sig: Int = SIGTERM` (the "correct" fix, the one this ticket asks for). Every downstream `const D = Opts {}` in other packages then breaks, with no change in their code. Under b that edit is a local error for the author, so nothing breaks downstream.


**AI/ML** (aiml), D2 vote:

> Vote: b
> Reasoning: Under b, the error lands on the line that names the foreign constant. An agent can fix that line where it stands. Under c, the error lands on a `const` that has no foreign constant in it, and often that `const` is in another package. Models loop on that kind of error. b still accepts the line models write most, `fn stop(c: Child, -- sig: Int = SIGTERM)`. Widening b to c later breaks no code.
> Concern: users and models will try `type Opts { sig: Int = SIGTERM }` first. So the field-default help must give the reason and a fix in one line ("a field default can fill a `const` struct literal; use a keyword default on a constructor fn, or an `Option[Int]` field"), and a test must pin it. Without both, the split looks arbitrary.


*Position change: from c to b.*

**Systems** (sys), D1 reply (excerpt):

> Q3 only. I hold b.
>
> **The strongest point for c** (web, aiml): one user rule, "only `const` and range bounds reject a foreign constant". The `const X = Opts {}` hole closes with one more NonConstExpr at the const, which points at the field default. That fix is sound, and I accept that c can be made correct. But the fix moves the error from the place where the cause is to the places where the effect is, and that has a cost c's side has not priced: a library's field default becomes part of its const API.
>
> ```blink
> // lib v1
> pub type Opts { sig: Int = 15 }
>
> // lib v2: author fixes the macOS bug the right way
> pub type Opts { sig: Int = SIGTERM }    // c: OK here, no error in the library
>
> // user code, unchanged, compiled against v2
> const DEFAULT_OPTS = Opts {}            // c: NonConstExpr, here, in the user's module
> ```
>
> Under c, a change to a default value, which a library author reads as an implementation detail, breaks every downstream `const` that omits that field. The author's own build and tests stay green, because only a consumer's const sees it. That is a silent breaking change across a package boundary. Under b the error is at the field declaration, in the author's build. The author then picks on purpose between `sig: Int = SIGTERM` as a keyword arg on the constructor fn, `sig: Option[Int] = None` resolved in a fn, or a literal. None of those leaks.


**Systems** (sys), D2 vote:

> Vote: b
> Reasoning: both options emit the same immediate in C, so the choice is only about where the error lands. Under b it lands on the line that names the foreign constant, in the author's own build. A keyword default is filled only at a call, and a call is never const, so no const context can reach it. A field default can fill a `const` struct literal (§2.21), so it must stay a const. b admits the line people write (`-- sig: Int = SIGTERM`), keeps a field default out of a library's const API, and can widen to c later without breaking code.
> Concern: the writer must pin both lines in a test, and the field-default NonConstExpr help must give the const-struct-literal reason and a fix (a keyword default on a constructor fn, or an `Option[Int]` field), or users will read the split as arbitrary.


### Final Spec

```blink
@ffi("SIGBUS", header: "signal.h")
pub let SIGBUS: Int                          // the C headers of the build target set the value

@ffi("curl", "CURLE_OPERATION_TIMEDOUT", header: "curl/curl.h")
pub let CURLE_OPERATION_TIMEDOUT: Int

let FATAL = [SIGSEGV, SIGBUS]                // OK: bare leaves
let NEXT = SIGTERM + 1                       // error[E1129]
const BAD_SIG = SIGBUS                       // error[NonConstExpr]

fn stop(c: Child, *, sig: Int = SIGTERM) -> Result[(), ProcessError] ! Process {   // OK
    process.signal(c, sig)
}
type Opts { sig: Int = SIGTERM }             // error[NonConstExpr]
```

- A foreign constant is an `@ffi(...)` annotation on a module-level `let` with no initializer. Its type is `Int` or a sized integer type. `let mut` is an error. `header:` is required.
- It is static, not const. The front end sees the type only, so `blink check` gives the same result on every target.
- A module-level `let` may name one only as a bare leaf. An operator over it is E1129.
- A keyword default may be a bare foreign constant. A struct field default may not, because a field default can fill a `const` struct literal.
- A `const` initializer that names one is NonConstExpr. A range-pattern bound that names one is E0323. A guard and any fn body are allowed. A lone name in a pattern stays a binder or an error, as today.
- No `@trusted` is needed. The build checks, for the build target, that the C name is an integer constant expression that fits the declared type. A failure is a Blink diagnostic at the declaration. A misspelled C name shows at `blink build`, not at `blink check`.
- `blink audit` and link tooling treat the form as a value from a header, not as a linked symbol. Hover and `blink doc` may show the target value for display only.
- A bodyless `let` without `@ffi` is the new error MissingInitializer (E1140).
- New error codes: ForeignConstForm (E0853), ForeignConstNoHeader (E0854), ForeignConstInvalid (E0855), MissingInitializer (E1140).

### Implementation notes

- **Parser and typecheck.** Accept a bodyless `@ffi let`. The type must be an integer type. `let mut` is an error. A missing `header:` is an error with the fix `add header: "signal.h"`. Apply the foreign-leaf rules in `const`, range bounds, module `let`, keyword default and field default. The help texts name the cause: NonConstExpr, E0323 and E1129 say that the name is a foreign constant and that the target's C headers set its value. E1129 says "compute it in a fn". The field-default error gives the const-struct-literal reason and one fix.
- **Build.** The per-target integer-constant check, reported as the new Blink diagnostic at the declaration (ForeignConstInvalid).
- **Tooling.** `blink audit` lists the form as a header value, not as a link symbol. Hover and `blink doc` display the value.
- **std migration.** All 18 host-defined lets (`SIG*`, `ERR_*`, `POLL_EVT_*`) move to the form, including private `ERR_NOENT`. The build-fs code replaces its two not-empty errno literals (39 and 66) with one `ERR_NOTEMPTY`. The earlier C shims go away. Renaming `ERR_*` to `E*` is a separate chore.
- **Tests.** One test pins `fn stop(c: Child, *, sig: Int = SIGTERM)` OK and `type Opts { sig: Int = SIGTERM }` NonConstExpr.
- **Open points.** A bodyless local `let` without an initializer keeps its present diagnostic. The NonConstExpr code number differs between the table in `sections/02_syntax.md` and `ERROR_CATALOG.md`; this change does not settle it.
