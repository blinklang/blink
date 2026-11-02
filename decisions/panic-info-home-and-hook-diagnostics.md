[< All Decisions](../DECISIONS.md)

# Where PanicInfo Lives, and the Diagnostics of the Panic Hook — Design Rationale

**Question.** The panic hook (§2.20) left five points open. Where does `PanicInfo` live, and does code need an import to write the name? What does a user `type PanicInfo` do? Which E0565 label does each wrong use of `on_panic` get? What is `with on_panic(f) as x`? What does a user value named `on_panic` do? The first ruling ([panic-hook-and-dev-trace.md](panic-hook-and-dev-trace.md)) and the second ([panic-hook-and-dev-trace-open-points.md](panic-hook-and-dev-trace-open-points.md)) did not answer these. §2.20 said that `PanicInfo` is a built-in type, and §10.6 said that the set of compiler-known type names is closed and does not list it.

**Answer.** (1) `PanicInfo` is an ordinary type of the module `std.panic`. Code that writes the name imports it with `import std.panic.{PanicInfo}`. It is not added to the closed table of §10.6. A general rule line sits beside the §10.5 sentence "Bare names and qualifiers share one table": a qualifier is used only in `q.y`, and a bare call `q(...)` or a bare value `q` never resolves to a qualifier. (2) A site gets one E0565. When a site breaks both the form rule and the place rule, the form label is the one reported. (3) A closure or nested fn in `main` gets the label "`on_panic` outside `main`" and a note. (4) `with on_panic(f) as x` is E0565, with its primary span on `as x`. (5) A user value named `on_panic` hides the built-in by lexical scope, and the error at the item carries a note that names the hiding binding.

**Release note.** One change is visible to users: a program that writes the name `PanicInfo` needs `import std.panic.{PanicInfo}`. No compiler has `on_panic` yet, so no program breaks. The spec examples of §2.20 gain the import. A user `type PanicInfo` and a user value named `on_panic` stay legal and get no warning.

**Spec.** §2.20 (*Panic Hook: `on_panic`*: the import, the labels of E0565, the name bound with `as`, a user value named `on_panic`), §4.7, §8.15.7 (the `on_panic` note beside the `trace` note), §10.5 (*Imported Names*: the qualifier rule). §10.6 is not changed. ERROR_CATALOG.md rows E0565, E0839 and E0507. No new error code.

### Decision

| Q | Result | Tally | Dissent |
|---|---|---|---|
| Q1 | `PanicInfo` lives in `std.panic`. Code needs `import std.panic.{PanicInfo}` to write the name. One general rule line beside the §10.5 "one table" sentence: a module qualifier is used only in `q.y`; a bare call `q(...)` or a bare value `q` never resolves to a qualifier. `panic` is its example: `import std.panic.{PanicInfo}` binds the qualifier `panic`, and `panic("boom")` is still the built-in. | 6-0 after Phase D (Phase C 4-2; sys and plt had `std.runtime`) | none |
| Q2 | A site gets one E0565. When a site breaks both the form rule and the place rule, the form label wins: `fn serve() { let h = on_panic }` gets "`on_panic` is only a `with` item". | 5-1 | DevOps/Tooling: place first |
| Q3 | A closure or nested fn inside `main`: the label "`on_panic` outside `main`" and a note that says the use is in a closure or nested fn, whose body is not the body of `main`. | 6-0 | none |
| Q4 | `with on_panic(f) as x` is E0565, not E0839. The primary span is `as x`. The label is like "`on_panic` gives no value to bind". The help is ``remove `as x` `` and is machine-applicable. The site still counts as the one hook of `main`. The catalog row states the span of this case in its own clause. | 6-0 after Phase D (Phase C 4-2; sys and min had the span on `on_panic`) | none |
| Q5 | A user value named `on_panic` hides the built-in by lexical scope. The error at the item (E0300 or E0839) must carry a note that names the hiding binding and says that it hides the built-in hook. The words are free, as for `trace`. | 6-0 | none |

**Agreed by all six, not voted.** `with on_panic(f)` needs no import, and a closure hook with an inferred parameter needs no import. A bare `PanicInfo` with no import is E0507, and its help names the import line as a machine-applicable fix. A user `type PanicInfo` is a plain namesake and gets no W1010. A module that declares `type PanicInfo` and also imports it gets E1012. A type mismatch prints both types with their module. The name `on_panic` is not reserved, and a declaration with that name gets no warning.

**The note of Q5.** The note also fires when a selective import hides the hook. It never fires for a qualified `lib.on_panic(...)`, and never for an E0300 that has nothing to do with the hook. The spec text shares one shape between this note and the `trace` note (§8.15.7), and each refers to the other.

**Phase B moves.** Web/Scripting moved from the §10.6 table row (Phase A: `PanicInfo` as a compiler-known type with home `blink.core`, no import) to `std.panic`. DevOps/Tooling moved from `std.runtime` to `std.panic`, and from two labels for a closure and a nested fn to one label and a note. Plt and Systems moved from `std.panic` to `std.runtime`, because the import of `std.panic` binds the qualifier `panic`. AI/ML and Web/Scripting moved the primary span of Q4 to `as x`. Minimalism moved the note of Q5 from "optional" to "required".

**Phase C moves.** None on Q2, Q3 and Q5. Q1 and Q4 stayed split 4-2 and went to Phase D.

**Phase D moves.** Q1: Systems and PLT moved from `std.runtime` to `std.panic`, on the condition that the rule line is general and sits beside the §10.5 sentence. Q4: Systems and Minimalism moved from the span on `on_panic` to the span on `as x`. After the re-vote Q1 and Q4 are 6-0.

**Dissent.** The text below is the full text of the section of the ballot of the seat, copied without change.

*DevOps/Tooling on Q2 (place first).*

> Q2: Q2-place
> Reasoning: The place is wrong for each form, so "outside `main`" is the one statement that holds after any rewrite of the form. With the help that shows the whole repair (writer note), the user needs one edit, whichever label wins.
> Concern: If form first wins and the help shows only `with on_panic(f) { ... }`, the user rewrites in `serve` and gets a second E0565.

**Follow-ups, open.** This ruling does not decide them.

1. `with arena as x` has the same gap as `with on_panic(f) as x`. This ruling does not decide it.
2. Which label a site gets when it has `as x` and is also outside `main` is not ruled. Q2 rules the order of the form and the place for a use that is not a `with` item.
3. The `trace` note stays an example (the second ruling, Q1b, 5-1). The `on_panic` note is required (Q5, 6-0). The two notes share one shape and differ in whether the wording is required.

**Related.** [panic-hook-and-dev-trace-open-points.md](panic-hook-and-dev-trace-open-points.md) (the rule that a binding named `trace` hides the built-in, which Q5 extends to `on_panic`) and [builtin-type-name-shadowing.md](builtin-type-name-shadowing.md) (the closed set of compiler-known type names and the shadowing rules, which Q1 keeps unchanged).

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Each quote below is the full text of the reply of the seat, copied without change. The only edits: a session tag in the heading of a reply is removed, and a path to a scratch file is removed. The text of the moderator rounds is not quoted.

#### Phase A — Independent proposals

Each seat proposed alone, from the brief of the five points.

**Systems**

> # Systems seat (sys): proposals
>
> My question for each point: what does the compiler emit, and what is fixed in the runtime ABI? The hook costs one store of a fn pointer (and its env) into a process global at the `with` entry, one store at the exit, and one trampoline that builds a `PanicInfo` from the C values `(msg, file, line)` that `__blink_panic_dispatch` already has. No point below changes that cost. So I pick each rule by how few special paths the compiler gets.
>
> ## P1 + P2. `PanicInfo` lives in `std.panic`; a user `type PanicInfo` is a plain namesake
>
> **P1: option B, module `std.panic`.** `std.panic` holds one declaration, `pub type PanicInfo { message: Str  file: Str  line: Int? }`. A program names it through an import. `on_panic` itself stays built-in and needs no import. The §2.20 test example gains `import std.panic.{PanicInfo}`.
>
> ```blink
> import std.panic.{PanicInfo}
>
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) { panic("boom") }
> }
> ```
>
> stderr: `fatal: boom`. Exit code 70. Without the import, `report` is the normal unknown-type error at `PanicInfo`.
>
> Why B:
> - §10.6 says in plain words that a new built-in type "is never added to this table". Option A breaks a rule that the panel voted to close. B needs no change to §10.6.
> - B has a precedent of the exact shape: `time.read()` is a built-in op, it returns `Instant`, and `Instant` lives in `std.time` and needs an import to name. `on_panic` is a built-in item typed against a std type, the same thing.
> - B has a codegen precedent too: `std.process.ProcessResult` is a std type whose C struct the runtime header defines. The compiler finds the tid of `std.panic.PanicInfo` by its fixed path when it types `on_panic`. It loads `std.panic` only when a program uses `on_panic` or imports the module. Option A puts the type in scope of every module of every program; no run-time cost either way, but B keeps the surface paid for by use.
> - The hook author must name the type anyway (the param of `report`), so the import is one line in the one module that has `main`.
>
> Tradeoff: one import line that A does not need. I accept it to keep the closed set closed.
>
> **P2: a user `type PanicInfo` is an ordinary type with no diagnostic,** as `FfiScope` and a user `type Duration` are. It is not compiler-known, so W1010 does not apply. In a module that declares its own `PanicInfo` and also needs the std one, `import std.panic.{PanicInfo as Crash}` works with no special rule.
>
> A user type does not satisfy the hook:
>
> ```blink
> type PanicInfo { code: Int }
>
> fn report(p: PanicInfo) -> Never ! Env.Exit { env.exit(p.code) }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }   // error[TypeError] E0300
> }
> ```
>
> The error is the ordinary argument mismatch (E0300): expected `fn(std.panic.PanicInfo) -> Never`, got `fn(app.PanicInfo) -> Never`. Both names print with their module path because the short names are the same. No new code.
>
> Cross-language: Rust puts `PanicHookInfo` in `std::panic` and makes you name the path; Go's `recover()` gives an untyped `any`. Rust's shape is the one that keeps the prelude small.
>
> ## P3. E0565 labels: one closed list, one label per site
>
> E0565 keeps one code. The catalog row lists five labels:
>
> | Case | Label |
> |---|---|
> | a fn other than `main` | "`on_panic` outside `main`" |
> | a closure or nested fn in `main` | "`on_panic` outside `main`" |
> | a `test` block | "`on_panic` in a `test` block" |
> | any use that is not a `with` item | "`on_panic` is only a `with` item" |
> | `with on_panic(f) as x` (P4) | "`on_panic` gives no value to bind" |
> | a second hook in `main` | "a second `on_panic` in `main`", secondary span on the first: "first `on_panic` here" |
>
> A "use that is not a `with` item" is any place the name `on_panic` resolves to the built-in other than as the full expression of a `with` item: `let h = on_panic`, `on_panic(report)` as a statement, `run(on_panic(report))`, `with wrap(on_panic(report))`.
>
> ```blink
> fn main() ! IO, Env {
>     let h = on_panic            // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     on_panic(report)            // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
> }
> ```
>
> One site gets one E0565. When two cases hold, the place wins: test block, then outside `main`, then not a `with` item, then `as`, then second hook. Reason: the place error tells a library author that no form of the hook can work there; the other repairs come after the user moves the code. "Second" counts every hook in `main` in source order, in any branch and at any depth of `with` nesting; the check is static, so a hook in a branch that never runs still counts.
>
> Tradeoff: the closure case shares the "outside `main`" label. A closure in `main` is a separate fn in the emitted C, and can run after the `with` ends or on another thread, so "outside `main`" is true from the codegen view. A separate label buys nothing a note cannot.
>
> ## P4. `with on_panic(f) as x` is E0565
>
> Reject it. Label "`on_panic` gives no value to bind", help "remove `as x`".
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) as h { run() }   // error[PanicHookPlacement] E0565: `on_panic` gives no value to bind
> }
> ```
>
> Why: the hook gives no value, so a binding is a dead slot. A user who writes `as h` thinks `h` is something: a handle to uninstall the hook, or the `PanicInfo`. Neither exists. E0839 does not apply (§4.7 says so), and a new code for one shape is waste; E0565 already owns "misuse of `on_panic`". I do not take this as a rule for `arena`; `arena` is outside these tickets.
>
> ## P5. A user value named `on_panic` hides the built-in by lexical scope
>
> Same rule as `panic`, `todo`, `unreachable` and `trace`: the name is not reserved. A fn, `let`, param, or import alias named `on_panic` hides the built-in in its scope. `with on_panic(...)` then types as an ordinary `with` item on the user value (§4.7).
>
> The MVCE:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
>     // error[TypeError] E0300: expected `Int`, got `fn(PanicInfo) -> Never ! IO.Eprint, Env.Exit`
> }
> ```
>
> After a fix of the argument, the item has type `Int`: E0839. Each of these errors gets one note: "`on_panic` here is the fn at app.bl:1; it hides the built-in panic hook". No E0565 fires, because the name does not resolve to the built-in.
>
> Why:
> - One resolution path. The compiler looks `on_panic` up like any name and reaches the built-in only when nothing hides it. A keyword-in-one-position rule adds a second path to the `with` checker and a name that means two things in one scope.
> - The precedent is decided (`panic`, `trace`). A fourth rule for one name is what a user cannot guess.
> - The safety goal holds: only the built-in installs a hook, so a library fn named `on_panic` cannot take the crash report. Selective imports mean a library's `on_panic` hides the built-in only where the app imports that name by hand, and the app can alias it.
>
> No escape path to the built-in is needed: the hook lives only in the entry module's `main`, where the user owns every name and can rename.
>
> Cross-language: Rust's `std::panic::set_hook` is an ordinary path that a local `set_hook` hides; nobody has asked for it to be reserved.

**Web/Scripting**

> # Web seat, Phase A: panic hook, five points
>
> Lens: a JS/Python dev writes their first hook. They copy the §2.20 example. It must compile as written, and each mistake must give one error that names the fix.
>
> ## P1. `PanicInfo` is compiler-known: add it to the §10.6 table (option A)
>
> **Behavior.** `PanicInfo` is usable in every module with no import. Home `blink.core`, "shadows, W1010", specified in §2.20. `import blink.core.{PanicInfo}` is the inert marker, and `import blink.core.{PanicInfo as P}` reaches it from a module that shadows it. §2.20 and its test example stay as they are.
>
> Change the closure sentence of §10.6, do not drop it. The rule that holds for every row now: a type is compiler-known when **built-in syntax or a built-in item** names it (`..` gives `Range`, `handler` gives `Handler`, `.to[T]()` gives `ConversionError`). A type that only a std API names goes in a std module (`Duration`). `on_panic` is a built-in item with no import, so its parameter type is in the table. The set stays closed under that rule.
>
> ```blink
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> Compiles with no import. A panic in `run` prints `fatal: <message>` and exits 70.
>
> **Tradeoffs.** Option B gives the worst first five minutes: `on_panic` works with no import, but the one type you need to write the hook says "unknown type `PanicInfo`". Nobody guesses that the item is built in and its argument type lives in `std.panic`. That error makes Stack Overflow questions. B also adds an import line to every hook and every hook test, to save one row in a table. The only cost of A is one table row and one sentence that states the rule that already holds.
>
> **Cross-language.** In TS you write `window.onerror = (e: ErrorEvent) => ...` with no import of `ErrorEvent`. In Python `sys.excepthook` takes a `TracebackType` that you never import to use. The hook and its argument type come as one unit.
>
> ## P2. A user `type PanicInfo`: W1010, the same as every other shadows row
>
> **Behavior.** It compiles, it wins in its module, and it gets W1010 at the declaration with the usual help (`import blink.core.{PanicInfo as CorePanicInfo}`). The `on_panic` typing rule always uses the built-in `PanicInfo`. So in that module, `with on_panic(report)` where `report` takes the user `PanicInfo` is the normal argument type error (E0300). That error must spell the two types so that they differ: `expected fn(blink.core.PanicInfo) -> Never, got fn(PanicInfo) -> Never`, with a note that points at the user declaration.
>
> ```blink
> type PanicInfo { code: Int }      // warning[W1010]: shadows compiler-known type `PanicInfo` (blink.core)
>
> fn report(p: PanicInfo) -> Never ! Env.Exit { env.exit(p.code) }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }   // error[E0300]: expected fn(blink.core.PanicInfo) -> Never
> }
> ```
>
> **Tradeoffs.** A plain namesake with no warning (the `FfiScope` rule) fits only a name no program can write. Programs write `PanicInfo` in each hook, so a silent shadow leaves a confusing type error with no hint. W1010 says it at the cause. No new rule: this is the row the table already has.
>
> ## P3. E0565 labels: four, and the catalog row lists all four
>
> | Case | Label | Help |
> |---|---|---|
> | A use that is not a `with` item (`let h = on_panic`, `on_panic(report)` as a statement, `on_panic` as an argument) | "`on_panic` is only a `with` item" | `write it as with on_panic(f) { ... } in main` |
> | In a `test` block | "`on_panic` in a `test` block" | `a test checks the hook by calling it as a plain fn` |
> | A fn other than `main`, or a closure or nested fn in `main` | "`on_panic` outside `main`" | for a closure or nested fn, a note: `a closure or nested fn in main is not the body of main` |
> | A second hook in `main` | "a second `on_panic` in `main`" | secondary span on the first |
>
> One E0565 per site. When two cases match (`let h = on_panic` in `fn serve`), the label is the first row that matches, in table order. The "not a `with` item" fix comes first, because a dev fixes the form first and then the place.
>
> ```blink
> fn main() ! IO, Env {
>     on_panic(report)          // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     run()
> }
> ```
>
> **Tradeoffs.** The closure case is the one that gets the question "but it IS in main". The note answers it, so the label can stay short. Four labels, one code, one `blink explain` page.
>
> ## P4. `with on_panic(f) as x`: reject, E0565
>
> **Behavior.** Error E0565, primary span on `as x`, label "`on_panic` gives no value to bind", help "remove `as x`". Not E0839: §4.7 already says E0839 does not apply to `on_panic`, and the dev did not write a non-handler. They wrote a real hook with an extra `as`. Every misuse of `on_panic` under one code means one explain page covers all of them.
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) as h { run() }   // error[PanicHookPlacement] E0565: `on_panic` gives no value to bind
> }
> ```
>
> **Tradeoffs.** Allow-and-ignore (bind `()`) is the silent kind of "just works" that confuses later: someone writes `h.uninstall()` and gets a strange method error. A clear error now costs one deleted word. If the panel finds the name "Placement" too narrow for this case, I accept a new code. I do not accept silent acceptance.
>
> ## P5. A user `on_panic` hides the built-in by lexical scope
>
> **Behavior.** Same rule as `panic`/`todo`/`unreachable` and `trace` (already decided): `on_panic` is not reserved. A module fn, `let`, param, local or import alias named `on_panic` hides the built-in item in its scope. A user `on_panic` in one module does not hide the built-in in other modules. Then `with on_panic(x)` types the user value by the §4.7 item rules: a `Handler` installs, a scoped value runs `enter`/`exit`, anything else is E0839. E0565 never fires for the user name, in or out of `main`. A qualified `lib.on_panic(...)` hides nothing.
>
> The MVCE:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> ```
> error[E0300]: expected Int, got fn(PanicInfo) -> Never
>   --> app.bl:4:19
>   = note: `on_panic` here is the fn at app.bl:1, which hides the built-in panic hook
>   = help: rename the fn to use the built-in `with on_panic(f)`
> ```
>
> The note fires on any error at a `with` item whose callee is a user binding named `on_panic` (E0300 on the argument, or E0839 on the item). This is the same help-line pattern the panel gave `trace.log`. No escape to reach the built-in when hidden: rename, as with `trace`.
>
> **Tradeoffs.** A name reserved only inside a `with` item gives one name two meanings in one scope (`on_panic(3)` calls the user fn, `with on_panic(f)` is the built-in). That is the case the panel rejected for `trace`, for the same reason. `on_panic` is a common name in user code (event-emitter style callbacks: `on_click`, `on_error`, `on_panic`), so a reserved word would break real code to protect a once-per-program item. The note makes the hide visible at the one place it hurts.
>
> **Cross-language.** Python: `def print(...)` hides the built-in, and the error you get later never says why. JS: `let onerror = ...` in a module scope hides nothing global, which is the "own module only" rule. We take the JS scope rule and add the note Python lacks.

**PLT**

> # plt seat, Phase A
>
> One principle drives all five points: **the typing rule of a built-in names its types by a fixed path,
> and user names reach the built-in only through ordinary lexical scope.** That is the hygiene rule
> already in decisions/builtin-type-name-shadowing.md ("desugarings always target the builtin, never
> the name in scope"). With it, no new reserved name and no new table row is needed.
>
> ## P1 + P2. `PanicInfo` lives in `std.panic`; option (B); a user `type PanicInfo` is a plain namesake
>
> **Behavior.**
> - `PanicInfo` is an ordinary `pub type` in a new module `std.panic`. It is not compiler-known in the
>   §10.6 sense (no bare use without import). §10.6 stays closed; §2.20 and its examples gain
>   `import std.panic.{PanicInfo}`.
> - The typing rule of `on_panic(f)` checks `f : fn(std.panic.PanicInfo) -> Never` (row free). It
>   names the type by its path, not by what `PanicInfo` means in scope. So `with on_panic(report)`
>   needs no import when `report` is declared in another module; only a fn that *writes* the type
>   needs the import, exactly as with `Duration`.
> - A user `type PanicInfo` with no import of `std.panic.{PanicInfo}`: plain namesake, no diagnostic
>   (the `FfiScope` / `Duration` precedent: nothing is in scope to shadow). With the import too:
>   the existing import-vs-declaration rule of §10.5 applies; nothing new.
> - A hook typed with the user type is the ordinary argument mismatch, and the message prints the
>   paths, so the two types never read the same:
>
> ```blink
> type PanicInfo { code: Int }
>
> fn report(p: PanicInfo) -> Never ! Env.Exit { env.exit(p.code) }
>
> fn main() ! IO, Env {
>     with on_panic(report) { io.println("hi") }
>     // error: mismatched argument to `on_panic`
>     //   expected `fn(std.panic.PanicInfo) -> Never`
>     //   found    `fn(app.PanicInfo) -> Never`
> }
> ```
>
> ```blink
> import std.panic.{PanicInfo}
> import std.testing.{capture_print, mock_env}
>
> test "report writes the status line" {
>     let out: List[Str] = []
>     assert_panics(matching: "env.exit(101)") {
>         with capture_print(out), mock_env(Map.new()).as_handler() {
>             report(PanicInfo { message: "ice", file: "a.bl", line: Some(3) })
>         }
>     }
> }
> ```
>
> **Why not (A).** The §10.6 table is the set of names the compiler needs *in every module* because
> literal syntax or desugaring produces them (`Int`, `Option` for `T?`, `Range` for `a..b`). No
> syntax produces a `PanicInfo`; one fn in one program names it. Adding it breaks a sentence written
> precisely to stop this growth, and every future runtime record (a signal info, an exit info) would
> claim the same row. (B) is monotone: a later compiler adds fields or siblings in `std.panic` with no
> new global name. Why a new module, not `std.process`: that module is child-process control; a panic
> record there is a category error. `std.panic` is the natural home for any later panic API too.
>
> **Cross-language.** Rust: `std::panic::PanicHookInfo`, reached by path, never in the prelude.
> OCaml: `Printexc` is a module, not a pervasive.
>
> ## P3. E0565 labels: one label per case, chosen by a fixed order
>
> The catalog row lists every label. The checker tests in this order and emits one diagnostic for
> the first case that holds (a single error per site, deterministic):
>
> | Case | Label |
> |---|---|
> | `on_panic` that is not the callee of a `with` item (`let h = on_panic`, `on_panic(report)` as a statement, `wrap(on_panic(report))` inside a `with`) | "`on_panic` is only a `with` item" |
> | `with on_panic(f)` in a `test` block | "`on_panic` in a `test` block" |
> | any other place not in the body of `main` (other fn, closure or nested fn in `main`) | "`on_panic` outside `main`" |
> | a second hook in `main` | "a second `on_panic` in `main`"; secondary span "first hook here" |
>
> For a closure in `main`, a `note:` says "a closure body is not the body of `main`", because that
> case reads as "inside main" to a user.
>
> ```blink
> fn main() ! IO, Env {
>     on_panic(report)        // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     let h = on_panic        // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
> }
> ```
>
> The form check comes first because it is a syntactic class (no well-formed placement can repair
> `let h = on_panic`). `on_panic` has no type, so it must not fall into `UnresolvedName` or a type
> error: that would claim the name is unknown, which is false. All of this applies only to a
> reference that resolves to the built-in (P5).
>
> ## P4. `with on_panic(f) as x`: reject, E0565
>
> **Behavior.** Error E0565, primary span on `as x`, label "`on_panic` gives no value to bind".
> Help: "remove `as x`". Exit: no build.
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) as h {    // error[PanicHookPlacement] E0565: `on_panic` gives no value to bind
>         run()
>     }
> }
> ```
>
> **Why.** §4.7 gives `as` a meaning only per item kind: the handler, or the Context. The hook item
> has neither. Typing `x : ()` would be a binding no one can use, a rule invented for no program.
> Rejecting keeps "`as` never changes what an item does" true with no special case. E0839 is wrong:
> §4.7 already says E0839 does not apply to `on_panic`, and E0839's help ("add `?`", "write it as a
> statement") points the wrong way. E0565 is the code for "a malformed use of the hook", so the
> catalog row text widens from "placement" to "placement or form"; the name `PanicHookPlacement`
> can stay. Same-code-for-every-hook-misuse also makes the catalog greppable for a model.
>
> Side note for the writer, not a vote: `with arena as x` has the same hole in §5.2. It should get
> the same treatment, in its own ticket.
>
> ## P5. A user value named `on_panic` hides the built-in by lexical scope
>
> **Behavior.** `on_panic` is not reserved. A module-level `fn`/`let`, an import, a parameter or a
> local named `on_panic` hides the built-in item in its scope, exactly as §8.15.7 rules for `trace`.
> In that scope `with on_panic(...)` is an ordinary `with` item typed by §4.7: it takes the user
> value. E0565 never fires for it (any place, any count), and no hook is installed. A user
> `on_panic` in one module hides nothing in other modules.
>
> The MVCE:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> gives the ordinary argument mismatch at `report` (expected `Int`, found `fn(PanicInfo) -> Never`),
> with a `note:` "`on_panic` here is the fn at app.bl:1, which hides the built-in panic hook". If the
> call were well typed (`with on_panic(3)`), the item is an `Int`: E0839, with the same note. A user
> `on_panic` that returns a `Handler[E]` is legal and installs that handler: it is the user's name.
>
> **Why.** Every precedent the panel has set is lexical hiding: `panic`/`todo`/`unreachable` user fns,
> the `trace` binding, `io`/`env` outside their effect. A name that means the built-in in a `with`
> item and the user fn in every other position gives one name two meanings in one scope; that does
> not compose with refactoring (extract the item into a `let` and its meaning changes). The danger
> case, a hook silently not installed, cannot be silent: the user value must type as a `Handler` or
> a scoped value, or E0839 fires, and the note names the hiding binding. No escape path
> (`blink.core.on_panic`) is needed: the hook is legal only in `main`, so the fix is a rename in one
> module. YAGNI.
>
> **Cross-language.** Haskell and OCaml: every non-keyword name in the Prelude/Stdlib is hidden by a
> local binding, and no compiler warns. Koka: `handler` is syntax, an ordinary name is not.

**DevOps/Tooling**

> # Phase A, DevOps seat
>
> ## P1. Where `PanicInfo` lives: (B), in a new module `std.runtime`
>
> **Behavior.** §10.6 holds. `PanicInfo` is a `pub type` in `std.runtime`. Code that writes the name imports it: `import std.runtime.{PanicInfo}`. `on_panic` stays a built-in item with no import. Its argument type is `fn(std.runtime.PanicInfo) -> Never`, so a closure hook with an inferred parameter needs no import. A bare `PanicInfo` with no import is `UnknownType` (E0507). Its help names the import and gives a machine-applicable fix (the same fix that `Duration` gets for `std.time`). When the file already binds `runtime` to something else, the fix becomes help only, as the `std.random` rule (§4.4) does.
>
> ```blink
> import std.runtime.{PanicInfo}
>
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) { panic("boom") }
> }
> ```
>
> stderr `fatal: boom`, exit 70. If you remove the import:
>
> ```
> error[UnknownType]: unknown type `PanicInfo`
>  --> app.bl:1:15
>   |
> 1 | fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>   |              ^^^^^^^^^ not in scope
>   |
>   = help: import it: `import std.runtime.{PanicInfo}`
> ```
>
> An inline hook needs no import:
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(fn(p) {
>         io.eprintln(p.message)
>         env.exit(70)
>     }) {
>         panic("boom")
>     }
> }
> ```
>
> **Why this module, not one that already exists.** A selective import also binds its qualifier (§10.1). `main` holds every built-in effect, so `main` has every built-in handle in scope.
> - `std.process` and `std.io` give a qualifier (`process`, `io`) that a handle in `main` hides. That gives W0602/handle-hide noise in the one file that must import `PanicInfo`.
> - `std.panic` binds the qualifier `panic`, which hides the built-in `panic()` in that file. That is worse.
> - `std.testing` is the wrong home, because `main` needs the type.
> - `runtime` collides with no handle and no built-in.
>
> **Tradeoffs.** (A) costs nothing at the use site, but it reopens a closed table one vote after we closed it. Then every later built-in type ("an item of the language, so it goes in the table") repeats this fight. That costs more than (B). (B) costs one import line, once per program, in `main`'s file. The LSP adds the line on completion, as it does for `Duration`. The §2.20 examples and the test example gain the import.
>
> **Cross-language.** Rust: `std::panic::PanicHookInfo` needs a `use` or a full path, and `set_hook` does not. This is the same split.
>
> ## P2. A user `type PanicInfo`: plain namesake, no diagnostic
>
> This follows from P1. The name is not compiler-known, so W1010 does not apply. Treat it as `FfiScope` is treated. Two rules give the tooling cover:
>
> 1. A module that declares `type PanicInfo` and also imports `std.runtime.{PanicInfo}` gets the existing import/declaration name-clash error. This needs no new rule.
> 2. A type mismatch between two types with the same spelling **qualifies both by module**. Without that, the message reads "expected `PanicInfo`, found `PanicInfo`". The line from the shadowing decision ("expected `Handle` (main), found `Handle[Int]` (blink.core)") shows the shape.
>
> ```blink
> type PanicInfo { code: Int }
>
> fn report(p: PanicInfo) -> Never ! Env.Exit { env.exit(p.code) }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> ```
> error[TypeError]: mismatched types
>  --> app.bl:6:19
>   |
> 6 |     with on_panic(report) { run() }
>   |                   ^^^^^^ expected `fn(PanicInfo) -> Never` (std.runtime), found `fn(PanicInfo) -> Never` (app)
>   |
>   = note: `PanicInfo` at app.bl:1:6 is not `std.runtime.PanicInfo`
> ```
>
> ## P3. E0565 labels: one per case, and the catalog row lists each one
>
> The label must name what the user sees. "Outside `main`" is wrong for a closure that sits in `main`, because the user is reading `main` at that point. The labels:
>
> | Case | Primary label (span on `on_panic`) | Extra |
> |---|---|---|
> | A fn other than `main` | "`on_panic` outside `main`" | |
> | A closure in `main` | "`on_panic` in a closure" | |
> | A nested fn in `main` | "`on_panic` in a nested fn" | |
> | A `test` block | "`on_panic` in a `test` block" | note: tests check a hook by calling it (§2.20) |
> | Not a `with` item (`let h = on_panic`, `on_panic(report)` as a statement, an argument, a branch of an `if` item) | "`on_panic` is only a `with` item" | help: `with on_panic(report) { ... }` |
> | A second hook in `main` | "a second `on_panic` in `main`" | secondary span "first `on_panic` here" |
> | `with on_panic(f) as x` | see P4 | |
>
> **One diagnostic per site, checked in this order: place, then form, then count.** `let h = on_panic` in `fn serve` gets "`on_panic` outside `main`", because the place is wrong for each form. A second hook counts in source order and includes `if`/`else` branches. The rule is "at most one" in the text, and an LSP can check that without control flow. Under P5, E0565 fires only on a reference that resolves to the built-in.
>
> ```blink
> fn main() ! IO, Env {
>     let h = on_panic             // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     let g = fn() { with on_panic(report) { } }   // E0565: `on_panic` in a closure
> }
> ```
>
> ## P4. `with on_panic(f) as x`: reject, E0565, with a machine-applicable fix
>
> The hook gives no value. A user (or a model) who writes `as h` expects a handle, for example to remove the hook. A silent `()` binding hides that error, and then an unused-binding lint shows up later and is less clear. E0839 is the wrong code because §4.7 says E0839 does not apply. This is a misuse of the form of `on_panic`, and E0565 already covers form ("as anything other than a `with` item"). So:
>
> ```
> error[PanicHookPlacement]: `on_panic` gives no value
>  --> app.bl:2:27
>   |
> 2 |     with on_panic(report) as x {
>   |                           ^^^^ nothing to bind
>   |
>   = help: remove `as x`
> ```
>
> The span is on `as x`, and the fix removes it (machine-applicable). Adjacent gap, not ruled here: `with arena as x` has the same hole. File a ticket so the two match.
>
> ## P5. A user value named `on_panic`: it hides the built-in by lexical scope
>
> Use the same rule as `trace` (§8.15.7) and `panic`/`todo`/`unreachable`: the name is not reserved, and a fn, `let`, parameter, local or selective import named `on_panic` hides the built-in in its scope. A module-level one hides it only in its own module. `lib.on_panic` (qualified) never hides it. A reserved word breaks working code (the probe compiles today) to protect a one-line item. The cost is a confusing error, so give that error the `trace`-style help, once, on the first error at the item:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> ```
> error[TypeError]: mismatched types
>  --> app.bl:4:19
>   |
> 4 |     with on_panic(report) { run() }
>   |                   ^^^^^^ expected `Int`, found `fn(PanicInfo) -> Never`
>   |
>   = help: `on_panic` here is the fn at line 1, which hides the built-in panic hook; rename the fn to use it
> error[E0839]: a with-item must be a Handler[E] or a scoped value, got Int
> ```
>
> No W1010-style warning goes on the declaration. A user `fn on_panic` that nobody puts in a `with` is not a problem, and `trace` set the no-warning rule. No escape import (`blink.core.{on_panic as ...}`) either: the hook is one line in one file, and renaming is the fix (YAGNI).
>
> **Cross-language.** In Python, `print = 3` hides the built-in with no hint. The `trace` precedent showed that the hint is what makes hiding acceptable.

**AI/ML**

> # Phase A — aiml seat
>
> My test for each point: can a model that read the spec once write the right code the first time, and when it does not, does the diagnostic name the repair? Every rule below uses a rule that exists already. I add no new code and no new kind of name.
>
> ## P1 + P2. `PanicInfo` lives in a named std module and needs an import (option B)
>
> **Behavior.** `PanicInfo` is an ordinary `pub type` in a std module. I propose `std.panic` (fallback: `std.process`, see the risk below). A program that names it imports it. `on_panic` stays a built-in `with` item with no import. The 2.20 examples gain `import std.panic.{PanicInfo}`. The test example becomes `import std.panic.{PanicInfo}` plus `import std.testing.{capture_print, mock_env}`.
>
> A use with no import is the usual `UnknownType` (E0507), and its help names the import:
>
> ```blink
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {   // error[E0507]: unknown type `PanicInfo`
>     io.eprintln("fatal: {p.message}")                        //   help: import std.panic.{PanicInfo}
>     env.exit(70)
> }
> ```
>
> The repair:
>
> ```blink
> import std.panic.{PanicInfo}
>
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) { panic("boom") }
> }
> ```
>
> stderr `fatal: boom`, exit 70.
>
> **P2 follows with no new rule.** `PanicInfo` is not compiler-known, so a user `type PanicInfo` is an ordinary type with no diagnostic, as `Duration` and `FfiScope` are. A module that declares it and also imports `std.panic.{PanicInfo}` gets `DuplicateSymbol` (E1012). It reaches the std type with `import std.panic.{PanicInfo as Crash}`.
>
> ```blink
> type PanicInfo { code: Int }      // no diagnostic
>
> fn main() ! IO {
>     io.println("{PanicInfo { code: 1 }.code}")
> }
> ```
>
> stdout `1`, exit 0.
>
> **Tradeoffs.**
> - The value of §10.6 is one sentence a model can hold: "the table is complete, a new built-in type is reached by import." It holds for `Duration`, `Instant`, `FsError`, `ProcessError` today. The first exception makes the rule "complete, except some types in 2.20", and a model can no longer trust the table. Option A costs the rule; option B costs one line.
> - The line is cheap. A program has one hook, so it has one `import` for it. The miss is the most common model error, but E0507 with a help line is fixed in one step, without guessing.
> - A model that knows Rust expects an import: Rust has `std::panic::PanicHookInfo`, reached through `use std::panic`. `std.panic` matches that prior, so the guess is right.
> - Option A also gives a second decision (W1010 for a user `type PanicInfo`), which B does not need.
>
> **Risk to check (for the systems/PLT seats).** A qualified `import std.panic` binds the qualifier `panic`. I read §10.5 as: the qualifier lookup is syntactic and covers `a.f` only, so a bare call `panic("x")` still resolves to the built-in. If that reading is wrong, use `std.process` (it already holds the types for how a process ends: `ChildEnd`, the signal constants) and the rest of this proposal does not change.
>
> **Cross-language.** Rust: `std::panic::{set_hook, PanicHookInfo}`, both need a path. Go: `recover()` is built in, and the value has no type of its own. Neither puts the type in a global prelude.
>
> ## P3. E0565 labels: one label per case, and the catalog lists all of them
>
> | Case | Label |
> |---|---|
> | In a fn other than `main` | ``"`on_panic` outside `main`"`` |
> | In a closure or nested fn inside `main` | ``"`on_panic` outside `main`"`` + `note: a closure or nested fn in main is not the body of main` |
> | In a `test` block | ``"`on_panic` in a `test` block"`` |
> | Any use that is not a `with` item (`let h = on_panic`, `on_panic(report)` as a statement, `on_panic` passed as an argument) | ``"`on_panic` is only a `with` item"`` |
> | A second hook in `main` | ``"a second `on_panic` in `main`"``, with a secondary span ``"first `on_panic` here"`` |
>
> The help for the first four is the same: `help: put `with on_panic(f) { ... }` around the body of main`.
>
> When a use breaks two rules, one label is shown, in this fixed order: form (not a `with` item), then place, then count. If the form is wrong, moving the code into `main` does not fix it, so the form error comes first.
>
> ```blink
> fn main() ! IO, Env {
>     on_panic(report)          // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     run()
> }
> ```
>
> **Tradeoff.** A label that states the case lets a model fix the code in one step. The closure note matters most: a model sees `on_panic` written inside `main`, so "outside `main`" with no note reads as a compiler bug. Five fixed strings in the catalog give one source of truth for the tests and the docs.
>
> ## P4. `with on_panic(f) as x` is E0565
>
> **Behavior.** Rejected. The code is E0565, label ``"`on_panic` binds no name"``, help `remove `as x``. It is not E0839, because §4.7 says E0839 does not apply to `on_panic`. A new code would add one more entry for the same misuse. The E0565 row already covers "anything other than a `with` item" in the correct form, so this case belongs there: it is the right item in the wrong form.
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) as h {      // error[PanicHookPlacement] E0565: `on_panic` binds no name
>         run()                         //   help: remove `as h`
>     }
> }
> ```
>
> **Tradeoff.** Models copy `with mock_db(f) as h` and `with arena as a`, so they will write `as h`. A binding of type `()` that nothing can use is a silent dead end. A rejection with a one-step help teaches the shape.
>
> ## P5. A user value named `on_panic` hides the built-in, by lexical scope
>
> **Behavior.** The name is not reserved. This is the same rule as `trace`, `panic`, `todo` and `unreachable`: a module-level fn, an import, a parameter or a local named `on_panic` hides the built-in item where it is in scope. Then `with on_panic(...)` is ordinary item typing (§4.7), and E0565 does not apply, because the reference is not to the built-in.
>
> For the MVCE:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }   // error[E0300]: expected `Int`, got `fn(PanicInfo) -> Never`
> }                                     //   note: `on_panic` here is the fn at app.bl:1, not the built-in panic hook
> ```
>
> With an `Int` argument, the item has type `Int`, and the error is E0839. Both diagnostics carry the `note:` when the callee is a user binding named `on_panic`. To use the hook, rename the fn or use an import alias (`import util.{on_panic as on_crash}`). No escape such as `blink.core.on_panic` is needed (YAGNI).
>
> **Tradeoff.** A model learns one rule for every built-in value name: not reserved, hidden by scope. A special reserved case only for `on_panic` adds one more decision point. The cost of the hidden name is a confusing error, and the `note:` removes that cost.
>
> ## Summary of what I want
>
> - P1: B, `import std.panic.{PanicInfo}` (fallback `std.process`). §10.6 stays closed.
> - P2: plain namesake, no W1010. E1012 if it is also imported.
> - P3: five labels in the catalog row, fixed order form > place > count, note for closure or nested fn.
> - P4: E0565 ``"`on_panic` binds no name"``.
> - P5: not reserved, hidden by scope, a `note:` on the resulting E0300/E0839.

**Minimalism**

> # Phase A: min seat
>
> My lens: no new codes, no new reserved names, no new rules where an old rule already decides the case. Four of the five points need no new rule. Each one follows from a rule we already voted.
>
> ## P1. `PanicInfo` lives in `std.panic`, reached by import (option B)
>
> **Behavior.** `PanicInfo` is an ordinary `pub type` in a new module `std.panic`. It is not in the §10.6 table. A program that writes the name imports it. `on_panic` itself stays a built-in `with` item. The compiler checks the hook's type against `std.panic.PanicInfo` by identity, so `with on_panic(f)` needs no import. Only a written `PanicInfo` needs one.
>
> ```blink
> import std.panic.{PanicInfo}
>
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) { panic("boom") }
> }
> ```
>
> stderr `fatal: boom`, exit 70. Without the import: `error[UnknownType] E0507` at `PanicInfo` in `report`'s parameter. A help line `import std.panic.{PanicInfo}` is welcome but not required wording.
>
> A closure hook needs no import, since its parameter type comes from inference:
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(fn(p) {
>         io.eprintln(p.message)
>         env.exit(70)
>     }) {
>         run()
>     }
> }
> ```
>
> The 2.20 test example gains `import std.panic.{PanicInfo}`.
>
> **Why B.** The §10.6 freeze (X7 of builtin-type-name-shadowing) is a voted rule, and its reason fits this case. "A new built-in type goes in a named std module ... never added to this table." `Duration` and `Instant` show that a type the runtime fills in does not need an ambient name. Option A breaks the freeze the first time a new type tests it. After that, every new builtin can say "PanicInfo got in". It also makes a common domain word (`PanicInfo` in a crash-reporting library) a W1010 shadow for every user, and a future break for each name we add. B costs one import line, in roughly one file per program.
>
> **Why a new module, and why `std.panic`.** No current module fits. `std.process` is about child processes, `std.testing` is test-only, and `env` is a handle, not a module. Putting the type in a module where it does not belong saves one module name but costs a lookup every time a user or a model goes looking for it. `std.panic` is the name a user guesses, and it is the place for any later panic item, if one ever comes (YAGNI on adding anything else now).
>
> *Cross-language:* Rust puts `PanicHookInfo` in `std::panic` and needs a `use` (or a path) to name it. Go puts no panic type in the universe scope beyond `error` and `any`.
>
> ## P2. A user `type PanicInfo`: plain namesake, no diagnostic
>
> This follows from P1. A name outside the §10.6 table is not compiler-known. Like `Duration` or `FfiScope`, a user `type PanicInfo` is an ordinary type with no W1010. If a module both imports `std.panic.{PanicInfo}` and declares `PanicInfo`, it gets `DuplicateSymbol` E1012 (the rule we have now).
>
> If a user's own `PanicInfo` is passed as the hook's type, the result is the ordinary mismatch:
>
> ```blink
> type PanicInfo { code: Int }
>
> fn report(p: PanicInfo) -> Never ! Env.Exit { env.exit(p.code) }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }   // error[TypeError] E0300
> }
> ```
>
> E0300: expected `fn(std.panic.PanicInfo) -> Never`, found `fn(PanicInfo) -> Never`. The message gives the module path when two types share a short name. That rule (or practice) is general and not specific to the hook.
>
> ## P3. E0565 labels: four, with a fixed order
>
> One diagnostic per `on_panic` site. The first case that matches gives the label:
>
> | Order | Case | Label |
> |---|---|---|
> | 1 | Not a `with` item: `let h = on_panic`, `on_panic(report)` as a statement, `on_panic(f)` nested inside another item's expression | "`on_panic` is only a `with` item" |
> | 2 | A `with` item, in a `test` block | "`on_panic` in a `test` block" |
> | 3 | A `with` item, anywhere else outside `main`'s own body (another fn, a closure or nested fn in `main`) | "`on_panic` outside `main`" |
> | 4 | A second `with on_panic` in `main` (nested or after the first) | "a second `on_panic` in `main`", with a secondary span on the first |
>
> Form comes before place: a misused form is wrong in every place. I would merge "closure/nested fn in main" into "outside `main`", and not add a fifth label, because the fix is the same: move it to `main`'s own body. I keep the test-block label only because 2.20 already shows it and its help has a different fix: "call the hook as a plain fn in a test". P4 adds a fifth case (below), under the same code.
>
> ```blink
> fn main() ! IO, Env {
>     let h = on_panic          // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     on_panic(report)          // error[PanicHookPlacement] E0565: `on_panic` is only a `with` item
>     with on_panic(report) { run() }
> }
> ```
>
> The catalog row then lists every label.
>
> ## P4. `with on_panic(f) as x`: reject, E0565
>
> **Behavior.** `error[PanicHookPlacement] E0565` at `as x`, with the label "`on_panic` gives no value to bind". Help: remove `as x`. This sits between rows 1 and 2 of the P3 order. The site still counts as `main`'s one hook, so a later hook gets "a second `on_panic`" and does not get a cascade.
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) as h { run() }   // error[PanicHookPlacement] E0565: `on_panic` gives no value to bind
> }
> ```
>
> **Why reject, why not E0839, why not a new code.** If we allow it, we need a new `as` bullet in 4.7 that says what `h` is (`()`?). Then a binding that can only be unused sits there to confuse readers and models. Rejecting it takes one label. §4.7 already says E0839 does not apply to `on_panic`, and the E0565 row already covers form ("as anything other than a `with` item"), so the label fits there with no new code. `with arena as a` has the same gap. I flag it as a separate friction item and do not settle it here.
>
> ## P5. A user value named `on_panic` hides the built-in, by lexical scope
>
> **Behavior.** We already have this rule for `panic`, `todo`, `unreachable` and `trace`. The name is not reserved. A binding named `on_panic` (module-level fn or `let`, an import, a parameter, a local) hides the built-in item where it is in scope. `with on_panic(f)` is then an ordinary `with` item: the user call is typechecked, and the item's type decides what happens (§4.7). There is no new rule and no warning at the declaration.
>
> The ticket MVCE:
>
> ```blink
> fn on_panic(x: Int) -> Int { x }
>
> fn main() ! IO, Env {
>     with on_panic(report) { run() }
> }
> ```
>
> `error[TypeError] E0300` at `report`: expected `Int`, found `fn(PanicInfo) -> Never`. With an argument that typechecks, such as `with on_panic(3) { }`, the error is `E0839` (an item of type `Int`). E0565 does not fire, because that name is no longer the built-in. Both errors are loud, so the trap is not silent. The fix is to rename the user fn. We need no escape path back to the built-in: nobody needs both in one scope.
>
> Optional, not normative: a `note:` on that E0300/E0839 that says "`on_panic` here names the fn at app.bl:1, not the built-in panic hook". That is cheap and helps models, but it is a quality point, not a spec rule.
>
> **Why not reserve.** Reserving the name in a `with` item makes a third resolution mode ("a name that is ordinary except as a `with` head"). That costs more than one note line. It also breaks the rule we use for `panic`/`todo`/`trace`, so a model would have to learn an exception.
>
> ## Summary
>
> | Point | Ruling | New surface |
> |---|---|---|
> | P1 | `std.panic.PanicInfo`, import to name it | one module, one type |
> | P2 | plain namesake; E1012 / E0300 as usual | none |
> | P3 | four labels, fixed order (form, test, outside, second) | one label |
> | P4 | reject `as`, E0565 "gives no value to bind" | one label |
> | P5 | hides by lexical scope, like `trace` | none |

#### Phase B — Round 1

Each seat read the six Phase A replies and said where it stood. Q1: DevOps/Tooling moved to `std.panic`, Web/Scripting moved from its table row to `std.panic`, Plt and Systems moved to `std.runtime`. Q3: DevOps/Tooling moved to one label and a note. Q4: AI/ML and Web/Scripting moved the span to `as x`. Q5: Minimalism moved to a required note.

**Systems**

> # sys, Phase B round 1
>
> **Q1: B-runtime (changed from B-panic).** I probed the qualifier risk with a stand-in module `panic` (pkg with `src/panic.bl` holding `pub type PanicInfo`, and `src/main.bl` with `import panic.{PanicInfo}` then a bare `panic("boom")`). gen1 compiles it, the bare call reaches the built-in, and the program exits 101 with `panic: boom at src/main.bl:6`. So the compiler is lenient today. But §10.5 says bare names and qualifiers share one table, and the spec has no rule for a bare call when a qualifier of the same name is in scope. If `std.panic` is the home, the one file that must import `PanicInfo` (main's file) depends on an unwritten rule, or on one we would have to add. `std.runtime` binds `runtime`, which collides with no handle and no built-in, so the question never comes up. Same cost and codegen as before: one std declaration, loaded only on use. A user `type PanicInfo` stays a plain namesake with no W1010. I agree with the variations: a mismatch prints both types with their module, and declare + import in one module is E1012.
>
>
> Side point for the lead: a bare call with a same-named qualifier in scope is a spec gap in its own right (it affects any user module named `panic`, `todo` and so on). It is not part of this ballot, and it may be worth a friction ticket.
>
> **Q2: form first (changed from place first).** The form check looks only at the expression node: is this `on_panic` the full expression of a `with` item? It needs no scope walk, so the label for one expression never depends on where the code sits. Each order takes the user two steps, so place first gives no real gain. A simpler checker wins.
>
> **Q3: one label + note.** No change. A closure is a separate C fn and may run after the `with` or on another thread, so "outside `main`" is true. The note says which form it is.
>
> **P4 span:** primary on `on_panic`, as the catalog says, plus a secondary span on `as x` that carries the machine-applicable "remove `as x`" fix. The span stays consistent with every other E0565, and the fix still points at the right text.
>
> **P5 note:** required. It costs one note line, and it turns a puzzling E0300/E0839 into a rename.
>
> Stable, ready to vote.

**Web/Scripting**

> # web, Phase B round 1
>
> **Q1 (P1+P2): I change from A to B-panic.** Two points from the other seats remove my objection to B. (1) Under B a closure hook needs no import, because its parameter type comes from inference, so a first program can run with no import. (2) A missing import gets E0507 with an `import std.panic.{PanicInfo}` help, the same machine-applicable fix that `Duration` gets. My five-minute test asked for an error that names the fix, and that one does. Rust devs also expect `std::panic`. My condition: the E0507 help that names `import std.panic.{PanicInfo}` is required, not optional. P2 follows from this: a user `type PanicInfo` is a plain namesake with no diagnostic. A mismatch prints both types with their module, and a module that also imports the name gets E1012.
>
> **The devops/aiml risk with `std.panic` does not hold in the compiler today.** Probe (gen1): a package module `mylib/panic.bl`, then `import mylib.panic.{Info}`, then a bare `panic("boom")` in `main`. Result: `panic: boom at src/main.bl:6`, exit 101. The bare call reached the built-in, and `Info` resolved. A bound qualifier `panic` changes only `panic.x`, not `panic(...)`. The spec says nothing on this, so I ask the writer to add a line: a module qualifier applies only to `q.member`, and a bare call `panic(...)` still reaches the built-in. With that line I take `std.panic` over `std.runtime`, because `std.panic` is the name a user guesses.
>
> **Q2: form first (no change).** If the form is wrong, moving the code into `main` does not fix it.
>
> **Q3: one label plus a note (no change).** The fix is the same in each case: move the code into the body of `main`. The note answers "but it is in main".
>
> **P4 span: I change to devops/plt.** The primary span goes on `as x`, with a machine-applicable fix that removes it. The error is about the `as`, so the caret goes there. I agree with min that the site still counts as `main`'s one hook.
>
> **P5 note: required.** The catalog row for E0300/E0839 at a `with` item states it, as we did for `trace`. Hiding a name is acceptable only because the error says what hid it. Without the note we get the Python `print = 3` mystery.
>
> Stable, ready to vote.

**PLT**

> plt, B1.
>
> Q1: B, and I CHANGE the module from std.panic to std.runtime (devops's B-runtime). Why: §10.5 says bare names and qualifiers share one table, so `import std.panic.{PanicInfo}` binds `panic` as a qualifier in the file that most likely also calls `panic("...")`. One name with two meanings in one scope is the exact thing all six of us rejected in P5. I probed gen1 with a stand-in package module named `panic` (probe/plt/): `import panic.{Info}` plus a bare `panic("big")` compiles, and the call still reaches the built-in (it prints `panic: big at src/main.bl:4`). So the compiler tolerates the overlap today. But no spec line says it must, so std.panic would rest on behavior the spec does not cover. `std.runtime` binds a qualifier that collides with nothing. The rest is unchanged: the typing rule checks `f` against `std.runtime.PanicInfo` by path, `with on_panic(f)` needs no import, a user `type PanicInfo` is a plain namesake, the type-mismatch message qualifies both types, and E1012 applies when a module both imports and declares the name. Side point for the writer, not a vote: the spec should say how a bare call resolves when a qualifier of the same name is in scope. That is a separate friction ticket.
>
> Q2: form first, no change. A form error survives every move: if `let h = on_panic` in `fn serve` gets "outside `main`" and the user moves it into `main`, they get a second error. "`on_panic` is only a `with` item" names the one repair that every fix needs. Place-first makes the user fix the error twice.
>
> Q3: one label plus a note, no change. "`on_panic` outside `main`" holds for a closure and a nested fn, because each one has its own body, which is not the body of `main`. The note answers "but it is in main". Two more labels add catalog rows and no new fact.
>
> P4 span: on `as x`, with a machine-applicable fix that removes `as x`. That was already my Phase A text, and it matches devops and web. The span goes on the token that is wrong; `on_panic(f)` itself is correct. I agree with min: the site still counts as `main`'s one hook, so a later hook gets "a second `on_panic`".
>
> P5 note: required, as a catalog clause on E0300/E0839 when the callee of a `with` item is a user binding named `on_panic`. The `trace` ruling made its note normative. The note is what keeps "hide by scope" from leaving a hook that silently is not installed, so it is part of the rule, not polish.
>
> Stable, ready to vote.

**DevOps/Tooling**

> B1, devops
>
> **Q1: change to B-panic (`std.panic`).** I tested my own objection with gen1 and it does not hold. The probe used a package with a stand-in module `src/panic.bl`. `import panic.{Info}` and `import panic` both bind the qualifier `panic`, and a bare `panic("boom")` in the same file still reaches the built-in: `panic: boom at src/pp.bl:6`, exit 101. A call `panic(...)` and a qualified access `panic.X` have different syntax, so a user does not hit a clash. The name `std.panic` also matches what a user searches for (Rust `std::panic`). Condition: §10.5 says "bare names and qualifiers share one table", so the writer must add one line. A call or value use of bare `panic` resolves to the built-in fn, and `panic.X` resolves through the qualifier. The current behavior is then a rule, not an accident. Without that line, a later "fix" to the shared table breaks every hook file. The E0507 help for a bare `PanicInfo` names `import std.panic.{PanicInfo}` and gives a machine-applicable fix. Mismatches print both modules. A module that declares `type PanicInfo` and also imports it gets E1012. A user `type PanicInfo` gets no W1010.
>
> **Q2: place first. I can also accept form first.** Either order takes the user two edits if the help names only one rule. So I ask for this instead: when a site breaks both rules, the one diagnostic's help shows the full repair, "`with on_panic(f) { ... }` in the body of `main`". With that help, the label order matters little. I keep place first because the place is wrong for every form. I will not dissent on form first if the combined help is in the rule.
>
> **Q3: change to one label + note.** "`on_panic` outside `main`" with a `note:` that says the use is in a closure or nested fn, and that its body is not the body of `main`. The note carries what my own labels carried, and the catalog gets fewer labels.
>
> **P4 span: no strong view.** I can accept a primary span on `on_panic` if a secondary span marks `as x` and the "remove `as x`" fix is machine-applicable. The fix is the part I care about.
>
> **P5 note: required.** The note must be there, and its words are free (the same split as the `trace` help). With no note, "expected `Int`, found `fn(PanicInfo) -> Never`" from a hidden `on_panic` gives the user nothing to act on. The note is the whole reason hiding is acceptable.
>
> Stable, ready to vote.

**AI/ML**

> # B1 — aiml
>
> **Q1: B-panic (`std.panic`). Second choice: B-runtime.** I tested the qualifier risk myself with gen1, using a stand-in module `mylib.panic` in a package:
> - `import mylib.panic.{PanicInfo}`, then `panic("boom")` gives `panic: boom at src/main.bl:6`, exit 101. The bare call still reaches the built-in.
> - `todo()` in the same file still works.
> - `import mylib.panic`, then `panic.PanicInfo { ... }` and `panic("boom")` in one fn: both work, exit 101.
>
> So the compiler today does not let a qualifier hide the built-in call. A qualifier is used only before `.`, and `panic(...)` is a call, not `q.y`. The spec does not state this, though. §10.5 says "bare names and qualifiers share one table", and a reader can take that the other way. I want one sentence for the writer (a fact rule, not a new choice): "A module qualifier is used only in `q.y`. It does not hide a built-in fn of the same name in a call." The risk devops named is real for a reader, not for the compiler. With that sentence, `std.panic` is the module a model guesses first (the Rust prior `std::panic`), so the first try is right. If the panel will not add the sentence, I vote `std.runtime`. The E0507 help names the import in both cases.
>
> Against A: no change. Web's "first five minutes" cost is real, but the E0507 help fixes it in one step. The rule "the §10.6 table is complete" is the more valuable thing for a model to keep.
>
> **Q2: form first. No change.** `let h = on_panic` in `fn serve` is wrong in every place, so "is only a `with` item" is the label that leads to a repair. A model that moves the code into `main` because the place label came first still gets the form error. That is two rounds instead of one.
>
> **Q3: one label + note. No change.** The note answers "but it is in main". Two more labels add strings to learn and give no different fix.
>
> **P4 span: I accept devops/web/plt: primary span on `as x`, with a machine-applicable fix that removes it.** This is a change from my Phase A reply, where I left the span on `on_panic`. The span should mark the token to delete, and a model applies a machine fix with no thought. I also agree with min: the site still counts as `main`'s one hook, so a later hook gets "a second `on_panic`" and no cascade.
>
> **P5 note: required.** For a model, the note is the only signal that the name is hidden. Without it, "expected `Int`, got `fn(PanicInfo) -> Never`" on a line that matches the spec example invites a wrong repair, such as changing the argument. The `trace` precedent made the hint part of the rule.
>
> Stable, ready to vote.

**Minimalism**

> # B1: min
>
> **Q1: B-panic, with B-runtime as my second choice. A last.**
>
> I probed the risk that devops and aiml raised with gen1, using a stand-in package module `src/panic.bl` (`pub type Info`).
> - `import panic.{Info}`, then `Info { .. }` and a bare `panic("boom")` in one fn: prints `panic: boom at src/main.bl:6`, exit 101. The bare call reaches the built-in.
> - `import panic`, then `panic.Info { .. }` and `panic("boom2")`: the same. The qualifier and the built-in fn live side by side.
> - The same holds for a module `todo` with `todo()`.
>
> So the compiler does not hide the built-in today. This question also exists without us: any user package can have a `panic.bl` or `todo.bl` right now. Picking `std.runtime` hides the question but does not answer it. My condition for B-panic is that the ballot carries one fact, which matches gen1: "a module qualifier is not a value. A call `panic(...)` never resolves to a qualifier, so it reaches the built-in. `panic.y` reaches the module." The general rule for qualifiers against built-in fns then goes to a friction ticket. If the panel does not want to state that fact here, I take `std.runtime` instead, because it needs no new text. I reject a grab-bag reading of that name: it holds `PanicInfo` and nothing else until a later vote adds something.
>
> P2 stays as it was: a plain namesake, E1012 on a clash with the import, and both module paths in a mismatch.
>
> **Q2: form first, but weakly held.** A site with both faults needs two fixes in either order. The rule that matters is that the order is fixed and there is one diagnostic per site. If place-first wins, I have no objection.
>
> **Q3: one label + note.** Devops's two extra labels add two catalog entries, and the fix is the same as for "outside `main`": move the hook to `main`'s own body. A note that says "in a closure in `main`" gives the same information with no new label.
>
> **P4 span:** keep the primary span on `on_panic`, so every E0565 label has the same span rule. Devops's machine-applicable fix that removes `as x` is fine. A fix's edit span does not need to be the primary span. The site still counts as `main`'s one hook.
>
> **P5 note: change from Phase A.** I now accept the note as required content: the error names the binding that hides the built-in. The wording is free, the same as for the `trace` help line, which open-points marked "an example, not required wording". Five seats want it, it costs one line, and it is the one thing that makes the hide-by-scope rule safe for a model to learn.
>
> Stable, ready to vote.

#### Phase C — Silent ballot

Each seat voted alone on Q1 to Q5. The result was Q1 4-2 (`std.panic`: aiml, devops, min, web; `std.runtime`: plt, sys), Q2 5-1 (form first; devops: place first), Q3 6-0, Q4 4-2 (the span on `as x`: aiml, devops, plt, web; the span on `on_panic`: min, sys) and Q5 6-0.

**Systems**

> Q1: Q1-runtime
> Reasoning: Codegen and cost are the same for both modules: one std declaration that the compiler finds by its path and loads only on use. The difference is the name tables. Q1-panic needs a new resolution rule for one qualifier beside one built-in, and the general case is not ruled yet. Q1-runtime needs no new rule, so the resolver keeps one path with no special case.
> Concern: If Q1-panic wins, the pinned rule for `panic` is a one-off, and the friction ticket's general rule for qualifiers may later contradict it.
>
> Q2: Q2-form
> Reasoning: The form check looks only at the expression node (is this `on_panic` the full expression of a `with` item?) and needs no walk of the enclosing scopes. So the label for one expression does not depend on where the code sits. Either order takes the user two steps, so the simpler checker wins.
> Concern: A library author who writes `on_panic(f)` as a statement learns only on the second compile that no hook can work outside `main`.
>
> Q3: Q3-note
> Reasoning: A closure or nested fn in `main` becomes a separate C function, which can run after the `with` ends or on another thread. So "outside `main`" is literally true. The note names the form, and no new label is needed.
> Concern: A user may read "outside `main`" as false, because the closure is inside `main` in the source, unless the note is always there.
>
> Q4: Q4-onpanic
> Reasoning: Every E0565 site keeps its primary span on `on_panic`, so tools and goldens have one span rule for the code. The secondary span on `as x` carries the machine-applicable fix, which is what an editor applies.
> Concern: A terminal reader may look at the `on_panic` caret and miss the secondary `as x` mark if the label does not name `as`.
>
> Q5: Q5-req
> Reasoning: The note costs one line in one diagnostic, and the compiler already knows the binding it resolved. Without it, the user sees an E0300 or E0839 about an `Int` and does not know that the name was taken. A required note is one a golden can protect.
> Concern: The note may fire for a hiding binding that the user meant to use, and so add noise in that rare case.

**Web/Scripting**

> # web ballot, Phase C
>
> Q1: Q1-panic
> Reasoning: `std.panic` is the name a JS/Python/Rust dev guesses, and Rust's `std::panic` sets that guess. A gen1 probe shows a bare `panic("boom")` still reaches the built-in when the qualifier `panic` is bound. The rule line only writes down what the compiler already does. `std.runtime` is a name nobody would search for, and finding it would take a docs lookup.
> Concern: if the friction ticket later rules that qualifiers hide bare built-in calls in general, `std.panic` gets a special exception, so that ticket must not undo this line.
>
> Q2: Q2-form
> Reasoning: if the form is wrong, moving the code into `main` does not fix it. Place-first sends the user to move `let h = on_panic` into `main`, and then they get a second error for the same line. With form first, one fix ends the problem.
> Concern: a library author who writes the form wrong in a helper fn learns the place rule only on the next build.
>
> Q3: Q3-note
> Reasoning: the fix is the same in every case (move the code into the body of `main`), so a single label keeps the list short. The note answers the "but it IS in main" question at the place where it comes up.
> Concern: if the note is dropped in the implementation, the closure case reads as a compiler bug, so the catalog row must require the note.
>
> Q4: Q4-as
> Reasoning: the mistake is the `as x`, so the caret goes there. That is where an editor puts the squiggle, and it is the text the fix deletes. A primary span on `on_panic` tells the user the hook is wrong, when the hook is fine.
> Concern: it breaks the "every E0565 points at `on_panic`" pattern, so the catalog row must state this case's span on its own.
>
> Q5: Q5-req
> Reasoning: hiding a name is fine only when the error says what hid it. Without the note, "expected Int" on a well-written hook is the Python `print = 3` mystery and a Stack Overflow question. The `trace` ruling set this same rule, so making it required keeps the two consistent.
> Concern: wording drift between the `trace` note and the `on_panic` note; the writer should use one shape for both.

**PLT**

> Q1: Q1-runtime
> Reasoning: §10.5 puts bare names and qualifiers in one table, so `std.panic` makes `panic` mean two things in the file that is most likely to call `panic()`. Q1-panic fixes this with a special rule that pins today's gen1 behavior for one name, while the general question goes to a friction ticket. A special case decided before the general rule may conflict with that rule later. `std.runtime` needs no new rule, so the choice holds whatever that ticket decides.
> Concern: `std.runtime` may become a catch-all module for unrelated runtime items. Each later addition to it needs its own review.
>
> Q2: Q2-form
> Reasoning: Moving the use into `main` does not fix a form error. Only the form label names the repair that every fix needs. With place first, the user fixes the place, gets a second error, and fixes the code twice.
> Concern: The checker must classify the form before it resolves the place, so the implementation must fix that order and test it.
>
> Q3: Q3-note
> Reasoning: A closure or a nested fn has its own body, which is not the body of `main`, so "outside `main`" is true. The note answers "but it is in main". Separate labels add catalog rows and no new fact.
> Concern: If the note is dropped in implementation, the label alone confuses the user. The diagnostics golden must check for the note.
>
> Q4: Q4-as
> Reasoning: The primary span marks the part that is wrong. `on_panic(report)` is a correct hook, and only the `as x` binding has nothing to bind. The fix deletes the text under the span, so the span and the fix agree.
> Concern: The E0565 catalog row must then state that the primary span for this case is on `as x`, not on `on_panic`, or the implementation will follow the other cases.
>
> Q5: Q5-req
> Reasoning: Hiding by lexical scope is correct only if the user can see that the name is hidden. Without the note, a program can compile toward a state where the hook is not installed, and the error that remains does not say why. The `trace` ruling set this pattern, and the same name-resolution fact should get the same diagnostic.
> Concern: The note must fire only when the callee resolves to a user binding named `on_panic`, never on an ordinary E0300 at an unrelated `with` item.

**DevOps/Tooling**

> Phase C ballot, devops
>
> Q1: Q1-panic
> Reasoning: `std.panic` is the name a user or model looks for when they search for the hook's type (Rust `std::panic`), and LSP auto-import finds it by that name. My gen1 probe showed that a bare `panic(...)` still reaches the built-in when the qualifier `panic` is bound. The rule line turns that probe result into a rule.
> Concern: The rule line gets lost or written too narrowly, and a later change to the shared name table makes a bare `panic` in a hook file resolve to the qualifier.
>
> Q2: Q2-place
> Reasoning: The place is wrong for each form, so "outside `main`" is the one statement that holds after any rewrite of the form. With the help that shows the whole repair (writer note), the user needs one edit, whichever label wins.
> Concern: If form first wins and the help shows only `with on_panic(f) { ... }`, the user rewrites in `serve` and gets a second E0565.
>
> Q3: Q3-note
> Reasoning: One label keeps the catalog row and the LSP code-action list short. The note gives the detail that confuses users ("I am in `main`") at the place where they read the error.
> Concern: An implementation leaves out the note, and "outside `main`" then reads as a false claim to a user whose cursor is in `main`.
>
> Q4: Q4-as
> Reasoning: The error is `as x`, not `on_panic`, and the squiggle should be on the text the quick-fix deletes. An editor shows the code action at the span. With a primary span on `on_panic`, the fix shows up on a token that is correct.
> Concern: Q4-onpanic wins, and the editor shows "remove `as x`" when the cursor is on `on_panic`, a token the fix does not touch.
>
> Q5: Q5-req
> Reasoning: Without the note, a hidden `on_panic` gives "expected `Int`, found `fn(PanicInfo) -> Never`" at a call that looks like the built-in, and the user cannot act on that error. The `trace` ruling made hiding acceptable only because the error names the binding that hides the built-in. Free wording keeps the cost low.
> Concern: The note must also fire when a selective import does the hiding, and an implementation that checks only local fns misses that case.

**AI/ML**

> Q1: Q1-panic
> Reasoning: `std.panic` is the module a model guesses first, from the Rust prior `std::panic`. So the import is often right on the first try, and when it is not, the E0507 fix names the path. The rule line only pins what gen1 does today (I probed it: a qualifier `panic` and a bare `panic("boom")` work side by side), so it adds no new behavior to learn.
> Concern: a reader of §10.5 ("bare names and qualifiers share one table") may still expect the qualifier to hide `panic()`, unless the rule line sits next to that sentence and the friction ticket settles the general case.
>
> Q2: Q2-form
> Reasoning: a misused form is wrong in every place. Place-first sends a model to move the code into `main`, and then it gets the form error. That is two repair rounds where form-first takes one.
> Concern: if the panel picks place-first, a model fixes the place and is surprised by a second E0565 on the same token.
>
> Q3: Q3-note
> Reasoning: the fix is the same for a closure, a nested fn and another fn (put the hook in `main`'s own body), so one label is enough. The note answers the only confusion: "but it is in main". Fewer distinct strings in the catalog means fewer cases to learn.
> Concern: a tool that reads only the label, and not the note, loses the closure hint.
>
> Q4: Q4-as
> Reasoning: the primary span should mark the token to delete, and that matches the machine fix. A model or an LSP that acts on the primary span removes the right text. The `on_panic` token is correct here, and a span on it suggests the hook itself is wrong.
> Concern: Q4-as is the one E0565 label whose primary span is not on `on_panic`, so the catalog row must say this, or tests that assume a single span site will fail.
>
> Q5: Q5-req
> Reasoning: when a binding hides `on_panic`, the note is the only signal of it. Without the note, "expected `Int`" on a line that matches the spec example invites a wrong repair, such as changing the argument. The `trace` precedent made the hint part of the rule, and the same name-hiding case should give the same diagnostic shape.
> Concern: "required" means the compiler must keep track of which with-item callee resolved to a user binding named `on_panic`. If the rule is unclear about qualified `lib.on_panic(...)`, which hides nothing, the note can fire in the wrong place.

**Minimalism**

> Q1: Q1-panic
> Reasoning: The rule line adds no behavior. It records what gen1 does today, and it settles a question that any user package with a `panic.bl` or `todo.bl` already raises. `std.panic` is the name a user or a model guesses first, so nobody has to look it up. `std.runtime` costs nothing in text, but it hides the qualifier question instead of answering it, and its vague name invites later additions.
> Concern: The friction ticket for qualifiers beside every built-in fn could get lost, and the one-line rule would then stand alone as an exception for `panic` and not as a general rule.
>
> Q2: Q2-form
> Reasoning: A wrong form is wrong in every place, so form-first reports the fault that is true no matter where the code moves. Either order takes the same two fixes. What matters is one fixed order and one diagnostic per site.
> Concern: If place-first wins, a model that moves `let h = on_panic` into `main` gets a second E0565 right away, and that reads as churn.
>
> Q3: Q3-note
> Reasoning: The fix is the same as for "outside `main`": move the hook to `main`'s own body. Two more labels put two more catalog entries on the budget and teach nothing that a note does not.
> Concern: A user who reads only the label may think "but I am in `main`". The note must always be present for the closure and nested-fn cases, not left optional.
>
> Q4: Q4-onpanic
> Reasoning: One span rule for every E0565 label keeps the catalog row simple and the tooling uniform. The secondary span and the machine-applicable fix already point at `as x`, so Q4-as adds nothing except an exception to the span rule.
> Concern: An editor that shows only the primary span underlines `on_panic`, and the user must read the secondary span to see that `as x` is the fault.
>
> Q5: Q5-req
> Reasoning: Hide-by-scope is safe to learn only when the error says that the hide happened. One required note with free wording costs little and follows the `trace` precedent. Without it, E0839 on `with on_panic(3)` makes no sense to a model.
> Concern: The note must fire only when the name resolves to a user binding that the built-in would otherwise fill. If it also fires for unrelated E0300s, it is noise.

#### Phase D — Focused round on Q1 and Q4

Q1 and Q4 were 4-2 and got one focused round. Each seat answered the strongest point of the other side.

**Systems**

> # sys, Phase D
>
> **Q1: I move to Q1-panic, on one condition about how the rule is written.** The strongest point is min's: any user package with a `panic.bl` or `todo.bl` already raises the qualifier question, so `std.runtime` only avoids it here and leaves it open everywhere else. From the resolver's side, the answer is not a special case. A module is never callable, so a qualifier in call position can only ever give an error. "A qualifier is used only in `q.y`; a bare name never resolves to a qualifier" costs nothing, matches gen1 today, and removes a dead resolution path. My objection was to a one-off rule for `panic` alone. So I ask the writer to state the line in general form beside the §10.5 "one table" sentence, with `panic` as its example, and not as an exception for one name. If the line must stay `panic`-only, I stay on Q1-runtime.
>
> **Q4: I move to Q4-as.** The strongest point is devops's: editors put the code action at the primary span, so with Q4-onpanic the "remove `as x`" fix shows up on a token that is correct and that the fix does not touch. The primary span should mark the text that is wrong and that the fix deletes. One span rule for the code was my reason for Q4-onpanic, but that rule is weaker than "the span marks the fault". The catalog row must name this case's span on its own, as plt and aiml said.
>
> Stable, ready to re-vote.

**Web/Scripting**

> # web, Phase D
>
> **Q1: I stay on Q1-panic.** The strongest point against it is plt's: §10.5 puts bare names and qualifiers in one table, so the rule is a special case decided before the general one. My answer is that the case is not special to `panic`. A user package with `util/panic.bl`, `util/todo.bl` or `util/assert.bl` raises the same question today, so `std.runtime` does not remove the question. It only keeps std from being the first place it comes up. A module cannot be called, so `q(...)` can never mean the module. The rule line should be written in that general form: "a module qualifier is used only before `.`; a bare call never resolves to it". Written that way, it is the general rule, not an exception, and the friction ticket only confirms it. A name users can guess (`std.panic`) helps every hook author. A name chosen to avoid a resolver question helps nobody who writes Blink.
>
> **Q4: I stay on Q4-as.** The strongest point against it is min/sys: one span rule for every E0565 keeps tooling uniform. But E0565 already has more than one span shape (the second-hook label adds a secondary span), so the catalog states spans per label in any case. Both min's and sys's own concerns name the real cost: an editor that shows only the primary range underlines `on_panic`, which is correct code, and a user tries to fix the hook. The squiggle must be on the text that the fix deletes. Golden-test uniformity is the tool author's convenience. The user's view of the error comes first.

**PLT**

> plt, Phase D.
>
> Q1: I MOVE to Q1-panic. The strongest point is min's: user packages with a `panic.bl` or a `todo.bl` already raise the qualifier question, so `std.runtime` does not avoid it. It only keeps the standard library out of it. My objection was a special case made before the general rule. That objection goes away if the line states a fact that holds in general: a module qualifier is not a value, so only the `q.y` form looks it up, and a bare call `f(...)` never resolves to a qualifier. This is sound with no exceptions. Calling a module can never be well typed, so leaving qualifiers out of bare-call lookup rejects no program that could be valid. It also matches gen1. I ask the writer to put the line beside the §10.5 "one table" sentence and to word it for every qualifier, not for `panic` alone. That way the friction ticket can only confirm it. With that, the name a user guesses wins at no cost to soundness.
>
> Q4: I stay on Q4-as. The strongest point is min's and sys's: one span rule for every E0565 site. The uniform rule is "the primary span marks the faulty construct", and in every other E0565 case that construct is `on_panic`. Here `on_panic(report)` is a correct hook and `as x` is the fault. Putting the caret on `on_panic` keeps the spelling uniform but breaks the meaning: the caret then marks a correct token as wrong. The catalog row states the span for this case in one clause, which is a small price for that. An editor that shows only the primary span then underlines the text the fix deletes.

**DevOps/Tooling**

> D, devops: I stay at Q1-panic and Q4-as.
>
> Q1. plt/sys: "a special rule for one name, decided before the general rule, may conflict with it later." That holds only if the line is written as a special case for `panic`. Write it as the general fact instead: "a module qualifier is used only in `q.y`; a bare call or value use never resolves to a qualifier." That is not new behavior. Any user package with a `panic.bl` or `todo.bl` already depends on it today (min's point). The friction ticket then has a rule to confirm, and has no exception to reconcile. `std.runtime` does not avoid the question. It only moves the question to the first user who writes `src/todo.bl`. Its vague name also invites a catch-all module, which plt names as a concern.
>
> Q4. sys/min: "one span rule for every E0565 label keeps tools uniform." The uniform rule I want is "the primary span is on the text that is wrong". For each other E0565 case that text is `on_panic`, so the rule still holds for every case. In LSP the primary span is the diagnostic's `range`. Secondary spans go to `relatedInformation`, which many editors do not show. A code action is offered when the cursor overlaps the range. So with Q4-onpanic, the editor underlines a correct token and offers "remove `as x`" there, and not where the user is looking. min's own stated concern is this case. Goldens: one more span rule in the catalog row, as plt says, which is a small cost.

**AI/ML**

> # D — aiml
>
> **Q1: I stay on Q1-panic.** The strongest point against it (plt, sys) is that we would pin a special case for one name before the general rule exists, and the general rule might later contradict it. My answer: write the line as a general rule, not as a rule for `panic`: "a module qualifier is used only in `q.y`; it does not hide a built-in fn in a call." This is what gen1 does today for any qualifier (I probed it). It is also the only direction the friction ticket can take without breaking code that exists now: a user package with `panic.bl` or `todo.bl` already compiles today and calls `panic()` next to the qualifier. So the friction ticket would confirm the line, not contradict it. `std.runtime` does not avoid that question; it only leaves it unasked here. A model guesses `std.panic` first, and a vague `runtime` module invites unrelated items later (plt's own concern).
>
> **Q4: I stay on Q4-as, at low stakes.** The strongest point against it (min, sys) is that one span rule for all of E0565 keeps goldens and tools uniform. My answer: the uniform rule can be "the primary span marks the text at fault". In every other case that text is `on_panic`. Here it is `as x`, and the fix deletes exactly what the span marks. An editor or a model that shows or acts on the primary span alone then points at the right token. With Q4-onpanic, it underlines a correct hook. I accept Q4-onpanic if it wins, provided the label names `as`, so that a reader who sees only the primary caret still learns the fault.

**Minimalism**

> # D: min
>
> **Q1: I stay on Q1-panic.** plt and sys say the strongest thing: a special case that we decide before the general rule could conflict with that rule later. My answer is to write the rule line as a general rule, not one for `panic`. "A module qualifier is used only in `q.y`. A call `q(...)` never resolves to a qualifier." That is true for every name, it matches gen1 for both `panic` and `todo` (my probe), and §10.1 already reads this way: a qualifier is reached only through `.`. The general question exists with or without us, because any user package can ship a `panic.bl` or `todo.bl` today. `std.runtime` does not answer it. It only keeps the standard library out of the question. The friction ticket then checks that line against the rest of the name rules. It does not invent the rule from nothing. So we add no exception and no new concept, and users get the module name they guess first.
>
> **Q4: I move to Q4-as.** devops and web make the strongest point. An editor puts the squiggle and the code action at the primary span. On `on_panic` the fix shows up on a token that is correct and that the fix does not touch. My reason was one span rule for the code, but that only makes the catalog look the same. The catalog row already states each label on its own, so stating one span there costs one clause. A primary span on the text the fix deletes is the simpler rule for a user to learn.

#### Phase D — Silent re-vote on Q1 and Q4

The Phase D replies asked for the rule line in its general form, beside the §10.5 sentence, and the ballot used that form.

**Systems**

> Q1: Q1-panic
> Reasoning: The ballot writes the rule line in general form, which was my condition. A module cannot be called and is not a value, so leaving qualifiers out of bare-name lookup rejects no program that could be valid. It also removes a dead path from the resolver. It matches gen1 today, and a user package with a `panic.bl` or `todo.bl` already depends on it, so `std.runtime` would only have put the question off.
> Concern: The impl ticket must make the resolver skip qualifiers for every bare call and bare value use, not only for `panic`, or a later user `todo.bl` breaks a bare `todo()`.
>
> Q4: Q4-as
> Reasoning: In LSP the primary span is the diagnostic range, and the code action is offered there. So the span must mark the text that the fix deletes. `on_panic(report)` is a correct hook here, and `as x` is the fault.
> Concern: The catalog row must state this case's span in its own clause, or the implementation will copy the `on_panic` span of the other E0565 labels.

**Web/Scripting**

> Q1: Q1-panic
> Reasoning: `std.panic` is the module name a user or a model guesses first. The rule line is now in general form beside the §10.5 sentence: a qualifier is used only in `q.y`. That records what gen1 already does, and any user package with a `panic.bl` or a `todo.bl` depends on it today. A module is never callable, so the rule rejects no program that could be valid.
> Concern: if the writer words the line only for `panic` and not for every qualifier, it becomes the one-off exception that plt and sys objected to.
>
> Q4: Q4-as
> Reasoning: in LSP the primary span is the range that the editor underlines and the place where it offers the code action. So that span must be on `as x`, the text the fix deletes, and not on the correct `on_panic`. The rule that holds for every E0565 case is "the primary span marks the fault".
> Concern: the catalog row must state this case's span in its own clause, or an implementation will copy the `on_panic` span that the other labels use.

**PLT**

> Q1: Q1-panic
> Reasoning: The general rule ("a module qualifier is used only in `q.y`; a bare call or value use never resolves to a qualifier") answers my objection, because it is a rule and not an exception for `panic`. It is sound with no exceptions: a module is not a value, so leaving qualifiers out of bare lookup rejects no program that could be well typed. It also matches gen1 and every user package that has a `panic.bl` or `todo.bl` today. With that rule in place, users get the module name they would guess.
> Concern: The rule must also say that a local binding still hides a qualifier in `q.y` (the §10.1 rule). If it does not, the two lines read as if they conflict.
>
> Q4: Q4-as
> Reasoning: The primary span marks the part that is wrong, and here that is `as x`, not the correct hook `on_panic(report)`. The span and the machine-applicable fix then cover the same text, so an editor that shows only the primary range puts the squiggle and the code action on the right token.
> Concern: The E0565 catalog row must state this case's span in its own clause, or the implementation will copy the span of the other cases.

**DevOps/Tooling**

> Phase D re-vote, devops
>
> Q1: Q1-panic
> Reasoning: The rule line is now general and sits beside the §10.5 "one table" sentence, so it is not a one-off for `panic`. It matches gen1 today (several seats probed both `panic` and `todo`), and no valid program depends on the other reading, because a module cannot be called. Users and models guess `std.panic` first, and LSP auto-import finds it by that name.
> Concern: The resolver and the LSP (go-to-definition, hover) must apply the same rule, or hover on `panic(` in a hook file will jump to the `std.panic` module.
>
> Q4: Q4-as
> Reasoning: The primary span is the LSP diagnostic range, and the editor offers the code action there. On `as x`, the squiggle and the "remove `as x`" fix mark the same text. The catalog row states this case's span in one clause.
> Concern: An implementation copies the span rule of the other E0565 cases and puts the caret on `on_panic`, unless a golden test pins the `as x` span.

**AI/ML**

> Q1: Q1-panic
> Reasoning: `std.panic` is the module a model or a user guesses first, so the import is right on the first try more often. The rule line in its general form ("a module qualifier is used only in `q.y`; a bare call or value use never resolves to a qualifier") is one fact with no exception, it matches gen1 today, and a model can apply it to any name. A module is never callable, so the rule rejects no valid program.
> Concern: The writer must state the line for every qualifier beside the §10.5 "one table" sentence. If it is stated only for `panic`, models will learn it as a one-name exception.
>
> Q4: Q4-as
> Reasoning: The primary span marks the text that is wrong, and the machine fix deletes that same text. A model or an LSP that reads only the primary range then acts on `as x` and not on a correct hook. The uniform rule is "the primary span is on the fault", and it holds for every E0565 case.
> Concern: The catalog row must state this case's span in its own clause, or an implementation will copy the `on_panic` span from the other labels.

**Minimalism**

> Q1: Q1-panic
> Reasoning: Written in its general form, the rule line is not an exception. It states that a module qualifier is not a value, so it is looked up only in `q.y`. Calling a module can never be well typed, so the line rejects no program that could be valid, and it matches gen1 today for any qualifier. With that line, `std.panic` costs no new concept, and users get the name they guess first. `std.runtime` would leave the question open and is a vague module name that invites unrelated items later.
> Concern: The writer could place the line only in §2.20, or word it for `panic` alone, which brings back the one-off exception. It must sit beside the §10.5 "one table" sentence, in general form.
>
> Q4: Q4-as
> Reasoning: The primary span marks the text that is at fault and that the fix deletes. In LSP, that span is the range where the squiggle and the code action show, and many editors hide the secondary spans. The catalog row already states spans per label, so one more clause costs little. Every other E0565 case still has its span on `on_panic`, so "the span marks the fault" holds for the whole code.
> Concern: An implementation that copies the span code from the other E0565 labels puts the caret on `on_panic` anyway, so the golden test for this label must check the column of `as`.

