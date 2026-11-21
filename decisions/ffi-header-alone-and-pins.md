[< All Decisions](../DECISIONS.md)

# A Header That Does Not Compile Alone, and a C Compiler That Ignores the Pins — Design Rationale

**Gap:** §9.1 said that the prototype test and the unit compile pass `-Werror=incompatible-pointer-types -Werror=int-conversion`, and that a build with `tcc` is outside the promise. It did not say what a build does when a header that an `@ffi` names has a fault of its own under those pins. Such a header makes every probe that includes it fail. The layout test then gave a false `ForeignStructMismatch` (E0862), or the unit compile gave `GeneratedCDidNotCompile` (I0017) with exit `101`, which says "compiler bug" for a fault in the header of the user. The spec also did not say what a build tells the user when the C compiler ignores the pins.

```blink
@ffi("mylib", "mylib_get", header: "mylib.h")
@trusted(audit: "MYLIB-GET")
fn c_get() -> I32 ! ()
```

```c
// mylib.h
static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
int mylib_get(int x);
```

Before this decision, `blink build` stopped with I0017 and exit `101`. After it, `blink build` stops with `ForeignHeaderDidNotCompile` (E0863) at the `@ffi` line, exit `1`, and copies the first 10 lines of the C compiler output into a note. A C compiler that accepts a pointer type mismatch under the pins gets one note per build, and the exit stays `0`.

This decision relates to [A `Ptr` at an `@ffi` Call](ffi-pointer-prototype.md), [The Header Governs the Prototype](ffi-header-governs-prototype.md), [A Struct Mirror That Does Not Match Its C Struct](ffi-struct-layout-mismatch.md) and [What E0861 Prints and When It Gives Help](ffi-prototype-message.md). The first gave the pins and the prototype test. The second made the test cover every `@ffi` wrapper of the unit, which Phase D of this decision used as a fact.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A header that an `@ffi` names does not compile alone | `H`: the build stops with a new error, E0863, exit `1`; no E0861 or E0862 shows for a declaration that names that header | 6-0 |
| Q2 | A C compiler that accepts a pointer type mismatch under the pins | `TN`: a canary probe, cached by compiler and flags; if it passes, one note per build; the note is not a warning, exit `0`, no check of the compiler name | 5-1 (Minimalism dissents for `T0`) |
| Q3 | When the note shows | `AF`: when the program has any `@ffi` fn, with or without `header:` | 6-0 in Phase D (4-2 in Phase C; Web/Scripting and Minimalism moved) |

The owner approved the tally on 2026-11-21 and ruled on one point that the panel did not vote: the `@ffi` fns of the standard library count toward `AF`. Systems, PLT, DevOps and AI/ML gave reasons for that reading in their Phase D files. Minimalism's Phase D file asks for the program's own only.

### Dissent

**Minimalism, Q2** voted `T0`. The vote, verbatim:

> ## Q2: T0
> **Reasoning:** The spec already says tcc is outside the E0861 promise, and the I0017 note names tcc. A canary adds a probe, a cache key and a message whose only fix is "use another compiler". Users and models learn to ignore a note like that. A flag that turns a pin off is a cflag problem: `probe_unsafe_cflag` (and pins placed last) covers it with no canary.
> **Concern:** A tcc user who has not read §9.1 ships a wrong pointer type with no sign at build time, and finds it as UB at run time.
>

The panel chose `TN` (5-1). The tally records the dissent as: "Q2 TN 5-1 (min dissent: T0; tcc outside the promise; pin-off flags belong in probe_unsafe_cflag)."

Minimalism's Phase A and Phase B text on the same question is in the deliberation below.

### Position changes

Each change is quoted from the panelist's own file.

**Web/Scripting, Q3, from `HD` to `AF`.** The Phase C vote for `HD`, verbatim:

> ## Q3
> **Vote:** HD
> **Reasoning:** With no `header:`, the declaration is the C prototype, so the test has nothing to compare it against and cannot miss a mismatch. A note there would be noise, and noise teaches users to skip notes.
> **Concern:** If a test of a binding with no `header:` can in fact find a mismatch (devops's claim), HD hides the note in a case where it matters.

The Phase D reply, verbatim:

> # [ticket] Phase D, Q3 — Web seat
>
> Rebuttal: none. My Phase C concern came true. The landed §9.1 text (:166) puts a binding with no `header:` in the test, and the `pipe` example shows it can give E0861. My HD reason was wrong.
>
> **Vote:** AF
> **Reasoning:** A headerless binding that a unit header declares (`pipe` through `unistd.h`) is checked on gcc and clang, and unchecked on tcc. HD would hide that gap. One rule, "the program has an `@ffi` fn", is easy to predict, and a user does not need to know which header governs which binding to understand it.
> **Concern:** The stdlib has `@ffi` fns, so the note shows on nearly every tcc build. To keep users reading it, the note must be one line and print once per build (wording, writer notes).

**Minimalism, Q3, from `HD` to `AF`.** The Phase C vote for `HD`, verbatim:

> ## Q3: HD
> **Reasoning:** If the note ships at all, it should show only where it says something true and useful. A program with no `header:` checks almost nothing against a real prototype, so a note on every such build is noise. The narrower scope is the smaller surface.
> **Concern:** A binding with no `header:` that a runtime-prologue header happens to declare (for example `pipe` through `unistd.h`) goes unchecked on tcc with no note.

The Phase D reply, verbatim:

> # [ticket] — Min, Phase D (Q3)
>
> **Rebuttal (and a change):** The spec text at :166 settles the fact that my Phase C concern raised.
> A binding with no `header:` is in the test, and a unit header can govern it (the `pipe` example). So
> HD hides the note in a case where the test can find a real fault. web's premise ("nothing to compare
> it against") is false when any unit header declares the symbol. One open point on sys's concern:
> "the program has an `@ffi` fn" should count the program's own declarations, as the I0017 note
> already does ("the program's own `@ffi` declarations"), not the stdlib's. Otherwise the note shows
> on every tcc build. I think that scope is a writer point, but the panel should confirm it.
>
> **Vote:** AF
>
> **Reasoning:** HD rests on a premise the landed spec contradicts. With HD the note is false by
> omission for a headerless binding that a unit header governs. AF is one rule ("the program has an
> `@ffi` fn"), and it is easier to state and to predict than one that depends on which bindings name a
> header. The smaller rule is the better minimal choice here.
>
> **Concern:** If "the program" includes stdlib `@ffi` fns, the note shows on nearly every tcc build,
> and users learn to ignore it.

### The ruling of the owner on the standard library

The tally left one point open: "Open sub-point (not voted): does "any @ffi fn" count stdlib bindings? min-D: only the program's own (as the I0017 note does). aiml-D, devops-D, plt-D, sys-D reasoning: stdlib bindings count too, since they also go unchecked on tcc. Put to the user in sign-off." The lead relayed that the owner signed off on 2026-11-21 and ruled that the `@ffi` fns of the standard library count. The spec says so, and says that the note then shows on nearly every build with `tcc` and is true there.

### Writer notes

Notes from the Phase C votes, and where the spec meets them:

- The pins apply to the whole compile, header code included. A header fault that is only a plain warning changes nothing and prints nothing. §9.1 *A header that does not compile alone*, with an example.
- The new error is E0863 (AI/ML, DevOps). It copies the first 10 lines of the output of the C compiler into a note and reads only the exit status (DevOps). `blink check` shows nothing. §9.1 *A header that does not compile alone*.
- The decision table uses pass and fail only. The spec names the tests by their codes and not by "guard" or "types control", which are not terms of the spec. §9.1, after *What the prototype test covers*.
- The help never offers "remove `header:`" without saying that the call is then unchecked (Web/Scripting, DevOps, PLT, AI/ML). The second help points `header:` at a header of the user that declares only the symbols that the user binds (Web/Scripting, DevOps, PLT). The extra help line with the command of the probe (Systems) is not in the spec: the output holds the output of the C compiler, which shows the fault.
- The span split: Systems, Web/Scripting, DevOps and PLT leaned to the `header:` argument; AI/ML and Minimalism leaned to the first `@ffi` line that names the header, with a note that lists the others. The spec takes the second: the rules of E0859, E0861 and E0862 all put the primary span on the `@ffi` line, so one rule holds for the four codes. A secondary label marks the `header:` argument, so the first group gets a place on the line that names the header.
- The note says "pointer type mismatch" and not "cannot fail", because `tcc` refuses a wrong count of arguments (Web/Scripting, PLT, Minimalism).
- The pins come last on the command line (Systems measured that `-Wno-incompatible-pointer-types` after the pins turns them off on gcc 16 and clang 23, and that `-fpermissive` does not). The spec does not name `probe_unsafe_cflag`.
- The note is one line and prints once per build (Web/Scripting).

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote and one focused re-vote round. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path that the reply contains shows as `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

The brief of the moderator, verbatim:

> # Blink spec panel — ticket [ticket], Phase A (independent proposals)
>
> Repo: /home/nhumrich/blinklang/blink (read only; do not edit any repo file, do not run gates).
> You may run `build/gen1/bin/blink check|build <file>` (and `build --emit c`) on probe projects under
> [scratch path]/probe/<your-seat>/ (create it). Run each probe in a capped scope:
> `systemd-run --user --scope -q -p MemoryMax=4G <cmd>`. Set `BLINK_CACHE_DIR=<your probe dir>/cache` for a build.
> You may run gcc, clang and `zig cc` on small C files in your probe dir. Use `zig cc -c -o x.o`, never
> `-fsyntax-only` (zig 0.17.1 reports a false FileNotFound there). A working project layout is in
> [scratch path]/probe/mod/ (blink.toml, blink.lock, src/main.bl); copy it.
>
> ## The ticket (verbatim)
>
> Title: Must an FFI prototype test that gives no verdict be visible, and must the -Werror pins apply to header code?
>
> Facts (spec text):
> - sections/07_trust_modules_metadata.md §9.1 (The prototype test): "The test and the unit compile both pass -Werror=incompatible-pointer-types -Werror=int-conversion, so one source gives one verdict on every host." tcc ignores these two flags, and the spec says E0861 then does not fire. §9.1 says the I0017 note covers "a wrong prototype that the test did not find".
> - No spec text says what happens when the prototype test cannot give a verdict for a declaration (it gives neither pass nor fail).
>
> Facts (behavior of the implementation, which follows the §9.1 letter):
> - Every probe compile of the test (the declared-symbol guard, the types control and the call probes) gets the same command-line pins as the unit compile.
> - A header with a fault of its own under the pins makes every probe that includes it fail. The guard then gives no answer, so the test gives no verdict for any declaration of that header. Nothing tells the user.
> - If the unit does not include that header (an @ffi fn header is not in the unit; the unit gets its own prototype), the build passes, and a wrong declaration is not found.
>
> MVCE (gcc 16, /tmp scratch):
>   blink.toml: [native-dependencies] mylib = { type = "vendored", path = "native/mylib.c", headers = ["mylib.h"] }
>   native/mylib.h:
>     static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
>     int mylib_get(int x);
>   native/mylib.c: int mylib_get(int x) { return x; }
>   src/main.bl:
>     @ffi("mylib", "mylib_get", header: "mylib.h")
>     @trusted(audit: "t")
>     fn c_get() -> I32 ! ()
>     fn main() { io.println("{c_get()}") }
>   blink build src/main.bl -> "built: build/main", exit 0. With the static inline line removed, the same build stops with E0861 at the @ffi line.
>
> Questions:
> Q0. Must anything change? That is, is a silent "no verdict" for a header that fails under the pins acceptable as written?
> Q1. Must a prototype test that cannot give a verdict for a declaration be visible to the user (for example as a warning, a note, or a stop)? On which commands?
> Q2. Must the pins apply to the code of the header the same as to the probe's own call lines, or only to the lines that the test writes?
> Q3. Does the answer to Q1 also cover tcc, where the pins have no effect and the test can never give a fail?
>
> Ticket note (team-lead correction): the claim that the guard was blank before the pins on gcc 14+ (both
> warnings are errors by default there) is NOT verified. It holds only if the probe compile passes no
> -fpermissive or -Wno-error flag. Measure before you rely on it.
>
> ## Facts surfaced by the moderator (main 14e6f7ba; read the sources yourself)
>
> 1. §9.1 *The prototype test* starts at sections/07_trust_modules_metadata.md:116; the pins and tcc sentence
>    are at :118. *What the prototype test covers* is at :166. The test order and the I0017 note are at :196
>    ("If the header is there, the layout test and the prototype test pass, but the C compiler still rejects the
>    generated C, the stop is GeneratedCDidNotCompile (I0017) ... An example is a build with tcc"). :3282 says a
>    tcc build is outside the E0862 promise "as it is for E0861".
> 2. The header: spec (decisions/ffi-header-governs-prototype.md, ba6cc09a) says: header: emits one #include per
>    distinct header after the runtime prologue; for each symbol, a unit header that declares it governs the call;
>    every @ffi wrapper the unit compiles is in the test (V2 6-0); a header that is found but does not declare the
>    symbol for the target is E0861 (V1-E 6-0). Its implementation is not landed yet: today an @ffi fn header may
>    not be in the unit (the ticket's third behavior fact).
> 3. Order of the C tests: E0859 (header missing) -> E0862 (struct layout) -> E0861 (prototype). E0859 exists for
>    a header the C compiler cannot find.
> 4. [ticket] (E0861 message; voted today, not yet landed): on failure the test splits into pass/fail probes, and
>    when the verdict fails but no split probe reproduces it, it prints a generic E0861 text with no slot.
> 5. decisions/check-build-promise.md: `blink check` runs no C compiler.
>
> ## Already decided (do not reopen)
> - The prototype test exists, runs in build/test only, reads only pass or fail and never the C compiler's
>   text, and pins the two -Werror flags on the test and the unit compile (decisions/ffi-pointer-prototype.md).
> - The header: rules (fact 2). The test order (fact 3). The §9.1.1 pointer rules.
> - Pre-1.0: a new or changed error ships at once with a CHANGELOG line. Rollout and compat are not questions
>   for this panel.
>
> ## Your task
> Produce one or more proposals that answer the ticket. A proposal states BEHAVIOR: the exact output of
> `blink build` / `blink test` (code, message lines, help or none, exit code) for each case, and how a
> pass/fail-only test knows each fact it prints. Do not draft spec sentences. Each proposal must include, with
> Blink code (`fn`, `{ }`, no semicolons, double quotes, `[T]` generics) and the C header text:
> - the MVCE (header with its own fault under the pins, unit does not include it);
> - the same header once the header: implementation puts it in the unit;
> - a header with its own fault that is NOT under the pins (a plain warning) — does it matter?
> - a tcc build of a wrong declaration;
> - tradeoffs anchored in your domain (cost per build, false stops on third-party headers you cannot edit,
>   determinism across gcc/clang/zig cc, a message a human or model can act on);
> - a short cross-language note when relevant (cgo, Zig @cImport, Rust bindgen/cc crate, Swift).
> You may propose "do nothing" if justified.
>
> Write your full proposal to [scratch path]/<your-seat>-A.md, then reply to team-lead with "written" plus a
> 3-line summary. Keep it under ~800 words.

- **Systems:**

> # [ticket] Phase A — Systems seat
>
> ## Measured first (probe/sys, empty TU that includes the header, `-c -o x.o`)
>
> | header fault `long *q = p;` | default flags | with the two pins | via `-isystem`, pins |
> |---|---|---|---|
> | gcc 16.2 | exit 1 | exit 1 | exit 1 |
> | clang 23.1 | exit 1 | exit 1 | **exit 0** |
> | zig cc (clang 22.1) | exit 1 | exit 1 | **exit 0** |
> | tcc | exit 0 | exit 0 | exit 0 |
>
> - The moderator's doubt is right, and wider than gcc. On gcc 14+ and on current clang, the MVCE header fails with NO pins. The pins are not the cause. The header is broken C for every supported compiler except gcc 13. The pins only change the verdict on gcc 13.
> - `-fpermissive` makes gcc 16 pass it (exit 0).
> - clang turns the error off inside a system header, even with the pins. gcc does not. So "one verdict on every host" already fails for header code.
> - Plain warnings (`-Wunused-variable`, `-Wpointer-sign` from `unsigned *` to `int *`) give exit 0 on all of them, pins or not.
>
> ## Proposal S1 (recommended): one "header compiles" probe on the failure path, plus one compiler canary
>
> **Q0.** Yes, change it. A silent "no verdict" is a pass that the build did not earn. A user who reads `built:` thinks the test ran.
>
> **Q1.** Yes, visible, as a stop. `blink build` and `blink test`. `blink check` runs no C compiler, so it shows nothing.
>
> How a pass/fail test knows: when the declared-symbol guard fails, compile one more file: an empty C file that holds only `#include "mylib.h"`, with the unit's flags and pins. If that file passes, the guard failed because of the symbol. That is the E0861 path we have now. If it fails, the header itself does not compile. The test reads only the exit status. The extra compile runs only after a failure, so a passing build pays nothing. It runs once per header, not once per declaration.
>
> Order: E0859 (cannot find the header), then the new stop (header does not compile), then E0862, then E0861. The layout test includes the header too, so a broken header can give a false E0862 now. The new step must come before E0862. I did not measure that case. The panel should check it.
>
> **MVCE** (header not in the unit):
>
> ```c
> // native/mylib.h
> static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
> int mylib_get(int x);
> ```
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get() -> I32 ! ()
>
> fn main() {
>     io.println("{c_get()}")
> }
> ```
> ```
> error[E08xx]: the C compiler rejects the header `mylib.h`
>  --> src/main.bl:1:28
>   |
> 1 | @ffi("mylib", "mylib_get", header: "mylib.h")
>   |                            ^^^^^^^^^^^^^^^^^ a C file that includes only this header does not compile
>   = note: the prototype test cannot test `c_get` (and 0 other declarations) against this header
>   = help: to see the errors of the C compiler, run:
>           gcc -c -o /dev/null -Werror=incompatible-pointer-types -Werror=int-conversion -Inative build/probe/hdr_mylib.c
> ```
> Exit 1. It names one header. If more declarations use the header, the note lists them. The help prints the probe's command and keeps its file. Blink still does not read the C compiler's text. The user or a model runs the line and reads it.
>
> **Same header in the unit** (once the header: change lands): the output is the same and the exit is 1. Without S1, the unit compile fails and the user gets the generic I0017. With S1, the stop names the header and comes before the unit compile.
>
> **Plain warning in the header** (`static inline int f(int a) { int b; return a; }`): the guard passes and the test gives a verdict. No output. It does not matter, because a warning does not change the exit status.
>
> **Q2.** The pins apply to the whole compile, header lines too. The unit compile includes the header, and C flags apply to the whole compile. The test must use the unit's flags, or its verdict does not predict the unit. On gcc 14+ and clang the header fails anyway, so a pin on the header can give a false stop only on gcc 13. There, the stop is correct: the same source then gives the same result on gcc 13 and gcc 16.
>
> **Q3 (tcc).** Yes, the same rule covers tcc, but the test knows it from a capability, not from a compiler name. Once per compiler identity (path + `--version` hash, cached), compile a canary with the pins: `int *p = 0; long *q = p;`. If the canary passes, the compiler does not obey the pins. That catches tcc, a `-fpermissive` in CFLAGS, and any unknown cc. Then:
>
> ```
> warning[W08xx]: the C compiler `tcc` accepts a pointer mismatch, so the prototype test cannot find a wrong `@ffi` prototype
>   = note: 3 `@ffi` declarations are not tested
> ```
> Exit 0. One line per build, not one per declaration. A stop would ban tcc, which the spec allows as a compiler outside the promise. A wrong declaration under tcc builds and gives undefined behavior at run time. The warning makes that cost visible.
>
> ## Option S2 (not recommended): put the pins only on the test's own lines
>
> Emit `#pragma GCC diagnostic error "-Wincompatible-pointer-types"` (and int-conversion) after the `#include` lines, and no command-line pins. gcc, clang and zig cc obey it. That changes the result only on gcc 13, and it does not remove the silence on gcc 14+ or clang. You still need S1 for that. It adds surface to the generated C for one old compiler. No.
>
> ## Tradeoffs (Systems)
> - Cost: a passing build pays 0 extra compiles. The canary costs 1 compile per compiler, cached. The header probe runs only after a guard fails.
> - Third-party headers you cannot edit: modern gcc and clang already reject this header in any C program, so the stop is not false. A header that clang reaches through `-isystem` passes on clang and fails on gcc. That host difference is in the C compilers. S1 reports it and does not hide it.
> - Determinism: one probe, one exit status, the same flags as the unit.
> - Actionable: one header, the declarations it blocks, and a command to run.
>
> ## Cross-language
> cgo, Rust bindgen (libclang), Zig `@cImport` (translate-c) and the Swift clang importer all stop when a header does not parse. None of them pass in silence. Blink is the only one where a broken header gives a green build.

- **Web/Scripting:**

> # [ticket] Phase A — Web/Scripting seat
>
> ## What I measured (probe/web/, gcc 16.2.1, clang 23.1.4, zig cc, tcc 0.9.28rc)
>
> 1. The prototype test is not on main (no E0861 emit site outside diag_catalog.bl; no pin flags in src/).
>    The ticket's MVCE builds with gen1 with or without the bad line. So I measured the C side only.
> 2. The MVCE header line `long *q = p;` is an **error with no flags** on gcc 16, clang 23 and zig cc.
>    `int x = p;` (int-conversion) is also an error by default on all three. The moderator's doubt
>    holds for the pins, but not for the fault: on these compilers the pins change nothing. Only gcc 13
>    (a supported compiler) makes these warnings by default, so only there do the pins add a stop.
> 3. You cannot scope the pins to the probe's own lines in a way that works on every compiler. With
>    `-isystem`, clang and zig cc hide the header fault; gcc still stops. That is one source, two verdicts.
> 4. tcc: the header fault passes. A pointer mismatch at a call is only a warning (pass). An arity
>    mismatch (`mylib_get()` against `int mylib_get(int x)`) is a hard error (fail). So tcc *can* give a
>    fail, just not for pointer types.
>
> ## Proposal W1 (my pick): a broken header stops at the header test, by name
>
> **Q0: yes, change.** A silent pass is the worst result a JS/Python dev can get. "It built, so the
> binding is checked" is what every user will think. They will be wrong, and the cause is a line in a
> header they never read.
>
> **Rule.** No C test may end in "no verdict" without output. Each probe result is pass or fail for a
> declaration, or the command stops.
>
> **How the test knows (pass/fail only).** The header test (E0859) gets a second probe per distinct
> header, with the unit's compiler, flags and pins:
> - probe 1: `#if !__has_include("mylib.h")` / `#error` / `#endif` — fails means not found → E0859 (as today).
> - probe 2: runtime prologue + `#include "mylib.h"` and nothing else — fails means found but does
>   not compile → new stop (working name `ForeignHeaderDidNotCompile`, code for DevOps to pick).
>
> This runs before E0862 and E0861. So the prototype test never sees a broken header, and its guard
> failing then means "header does not declare the symbol" (E0861, V1-E). No silent case is left. Any
> other probe result that is neither pass nor fail is an internal error, not a pass.
>
> **MVCE today (unit does not include the header):**
> ```
> error[ForeignHeaderDidNotCompile]: header "mylib.h" does not compile with this C compiler
>   --> src/main.bl:1:1
>    | @ffi("mylib", "mylib_get", header: "mylib.h")
>    = note: the header is found, but `#include "mylib.h"` alone fails with cc and the build's flags
>    = help: compile a file that has only `#include "mylib.h"` to see the C error; if you cannot
>            edit the header, write your own header that declares only the symbols you bind
> exit 1
> ```
> One stop per header, at the first `@ffi` line that names it; the note lists the other lines.
>
> **Same header once `header:` puts it in the unit:** the same stop, same text. Without W1 this build
> fails later as I0017, whose note says "maybe a wrong prototype" — a wrong lead. W1 names the file.
>
> **A plain warning in the header** (`int unused;`): probe 2 passes. No output, exit 0. It does not
> matter, and it must not: we never read compiler text.
>
> **Q1:** visible, as a stop, on `blink build` and `blink test`. `blink check` runs no C compiler, so
> nothing there.
>
> **Q2:** the pins apply to the header code too. The unit includes the header under the pins, so the
> test must predict the unit. Scoping (fact 3) is not deterministic across compilers.
>
> **Q3: no.** tcc gives a verdict (pass); it is a wrong pass for pointer types, not a missing verdict.
> Keep the §9.1 tcc sentence and the I0017 note. Optional, my lean yes: one note line per build when
> `#if defined(__TINYC__)` passes: "note: tcc does not apply the pointer checks of the prototype test;
> a pointer mismatch at an @ffi call is not found". Exit unchanged. This is a pass/fail probe too.
>
> ### Tradeoffs (Web lens)
> - **Cost:** one extra compile per distinct header, not per declaration, cached with the header test.
> - **False stops on third-party headers:** on gcc 14+, clang and zig cc the header already fails by
>   default, so W1 adds no stop the user would not get from plain `cc`. Only gcc 13 users see a stop
>   that bare gcc 13 shows as a warning. That is the price of "one source, one verdict", which is decided.
>   The help gives a fix that needs no edit to the vendor's file (a shim header).
> - **Determinism:** same verdict on gcc/clang/zig cc, because the pins are on every compile.
> - **Actionable:** names the file and the exact command to see the C error. A model can act on it
>   without reading compiler text.
>
> ## Proposal W2 (rejected): a warning, build goes on
> Prints the same text as a warning. Today (unit without the header) the build passes, but no
> prototype is checked. Once `header:` lands the unit fails anyway, so the user gets a warning and then
> I0017: two messages for one fault, and the second points the wrong way. Not worth it.
>
> ## Cross-language
> cgo compiles the preamble and its headers and fails the build on a header error. Zig `@cImport` fails
> translate-c. bindgen fails on a clang parse error. Swift says "could not build module". None of them
> pass in silence. They show the C text; Blink cannot (pass/fail only), so naming the header plus the
> "compile it alone" help is the closest equal.

- **PLT:**

> # [ticket] Phase A — PLT seat
>
> ## Measured first (probe/plt, header-only compile, no call)
>
> | header fault | gcc 16.2 | clang 23.1 | zig cc 0.17.1 | tcc |
> |---|---|---|---|---|
> | `long *q = p;` (int * to long *), no pins | FAIL | FAIL | FAIL | ok |
> | same, with the two pins | FAIL | FAIL | FAIL | ok |
> | unused local (plain warning), either way | ok | ok | ok | ok |
>
> So the pins are not the cause of the MVCE on current compilers. Their defaults already reject that
> header. The pins change the result only on gcc 13 (and older clang), which is what they are for.
> The team-lead note holds for these three: the guard was blank before the pins too.
>
> ## Core claim
>
> The test is a decision procedure with three outcomes, not two: pass, fail, and **no verdict**.
> Today "no verdict" folds into "pass". That is unsound: the build then promises a check it did not
> make. A verdict must never be inferred from a probe that could not run. Q0: yes, something must change.
>
> ## Proposal P1 (my choice): split "no verdict" by one extra pass/fail probe, and stop
>
> Before the guard, compile the **header alone**: `#include "mylib.h"` and nothing else, same compiler,
> target, include paths, unit flags and pins. The header test (E0859) already proved the file is found.
>
> - Header-alone FAILS: the header does not compile with this unit's flags. New error, at the `@ffi`
>   line, exit 1, from `blink build` and `blink test` (not `blink check`, which runs no C compiler):
>
> ```
> error[ForeignHeaderDoesNotCompile] (E08xx) at src/main.bl:1
>   `mylib.h` is found, but it does not compile with this unit's C compiler and flags (gcc 16.2.1, x86_64-linux)
>   note: the prototype test cannot test `c_get`, because its header does not compile
>   help: fix the header, or remove `header:`; the call then uses this declaration's prototype, unchecked
> ```
>
>   One error per distinct header, listing each `@ffi` declaration that names it. The test knows
>   each fact by pass/fail only: E0859 passed (found), header-alone failed (does not compile).
> - Header-alone PASSES but the guard or the types control FAILS: the fault is in C that Blink wrote.
>   That is `GeneratedCDidNotCompile` (I0017), a compiler bug, not a user error.
> - Both pass: the test gives its verdict as today (E0861 or pass).
>
> This is a total partition. No branch leaves "no verdict" silent.
>
> **Not a false stop.** The header: rules are decided (V2 6-0): every header an `@ffi` names goes in the
> unit. Once that lands, this header breaks the unit compile anyway, and the user gets I0017, which
> blames Blink. P1 gives the same stop earlier, with the right owner and a fix. For a third-party
> header the user cannot edit, the help names the one fix that does not need an edit.
>
> ### The cases
>
> MVCE (unit does not yet include the header):
> ```c
> // native/mylib.h
> static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
> int mylib_get(int x);
> ```
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get() -> I32 ! ()
>
> fn main() {
>     io.println("{c_get()}")
> }
> ```
> Today: `built: build/main`, exit 0. P1: the E08xx error above, exit 1.
>
> Same header once header: puts it in the unit: same E08xx, exit 1. Without P1 it would be I0017.
>
> Header with a plain warning only (`static inline int w(int x) { int y; return x; }`): it does not
> matter. Header-alone passes, the test gives its verdict, Blink prints nothing about the warning (it
> never reads C compiler text). A user `-Werror` in cflags is already refused by `probe_unsafe_cflag`.
>
> ## Q2: pins on header code too
>
> Yes, the pins apply to the whole translation unit, header included. The test is sound only if it
> compiles the same program the unit compiles. The unit compile includes the header under the pins, so
> the test must too. Scoping the pins to Blink's own lines (`#pragma GCC diagnostic` around the
> `#include`) would have to apply to the unit as well, which reopens a decided item, and the table shows it
> buys nothing on gcc 14+, clang or zig cc. It would only make gcc 13 accept a header that every newer
> compiler rejects: two verdicts for one source, the thing the pins exist to stop.
>
> ## Q3: tcc
>
> Different case. Under tcc the test runs and gives "pass"; the oracle is blind, not absent. P1 does
> not cover it. I propose a **calibration probe**, not a check on the compiler name: compile one fixed
> known-bad pair (`int *p = 0; long *q = p;`) under the pins. If it passes, this compiler cannot give
> E0861. Print once per build, only when at least one `@ffi` names a header:
>
> ```
> note: this C compiler (tcc 0.9.27) accepts pointer type mismatches, so the prototype test cannot fail
> ```
>
> A note, not a warning: the user has no source fix, and a warning with no fix is noise under
> `--strict`. Exit code unchanged. It needs no list of compiler names, and it stays correct for any
> future compiler.
>
> Wrong declaration under tcc (`fn c_get(x: Ptr[I64]) -> I32 ! ()` against `int mylib_get(int *)`):
> the note above, then `built: build/main`, exit 0. Today: the same, without the note.
>
> ## Tradeoffs
>
> - Cost: one extra compile per distinct header, header only (cheap, cacheable on header hash plus
>   flags). The calibration probe is one compile per compiler, cacheable on the `--version` text.
> - Determinism: the stop follows the pins, so gcc, clang and zig cc agree. Only tcc differs, and it
>   says so.
> - Action: each message names the header, the declarations it blocks, and one fix.
>
> ## Cross-language
>
> cgo stops when the preamble or its headers fail. Rust bindgen fails when clang cannot parse the header.
> Swift's importer fails the module import. Zig `@cImport` stops when clang rejects the header. None of them
> treats a header that will not compile as a pass. Blink should not either.

- **DevOps:**

> # [ticket] — DevOps/Tooling seat, Phase A
>
> ## Measurements (probe/devops/, gcc 16.2.1, clang 23.1.4, zig cc 0.17.1 = clang 22.1.8, tcc)
>
> | Compile of `#include "mylib.h"` (MVCE header) + one call | gcc | clang | zig cc | tcc |
> |---|---|---|---|---|
> | no flags | fail | fail | fail | pass |
> | the two pins | fail | fail | fail | pass |
> | header with only `-Wall` warnings, pins + `-Wall -Wextra` | pass | pass | pass | — |
> | canary `int *p; long *q = p;` with pins | fail | fail | fail | pass |
>
> 1. The team-lead note holds on all three supported hosts: `int *` to `long *` is an error by default. The pins do not cause the MVCE. A header with this fault breaks the probes with no pins, and it breaks any unit that includes it. Only gcc 13 (not on this host) would differ.
> 2. The E0859 test is `__has_include` (src/cli.bl:2118). It never compiles the header body, so a header that is found but does not compile passes it.
> 3. A warning that is not one of the two pinned diagnostics does not change pass or fail.
>
> ## Q0: yes, change it
>
> A test that skips with no output is worse than no test: the user thinks it ran. Today the MVCE builds, and a wrong declaration goes to run time as UB. After the `header:` change lands, the same header is in the unit, and the build stops with I0017: exit 101, "internal error ... compiler bug". That points the user at us, not at the header.
>
> ## Proposal D1 (recommended): a header control, and a pin canary
>
> **Header control.** After E0859 and before E0862, compile each distinct header that an `@ffi` names, with only `#include <h>`, with the flags of the unit (pins included). One TU with all headers on the normal path. On failure, one TU per header to find which one. Pass/fail only:
> - control fails → the header does not compile here: new stop.
> - control passes, guard fails → the header does not declare the symbol: E0861 (V1-E, already decided).
> - control passes, guard passes → the call probes give the verdict.
>
> So "no verdict" can not occur on gcc, clang or zig cc.
>
> **Pin canary.** One compile of the canary line above with the pins. It is pass/fail only, and it does not depend on a compiler name. If it passes, the compiler does not enforce the pins, and no prototype test can fail.
>
> ### Case 1: MVCE (header not in unit, today)
>
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get() -> I32 ! ()
>
> fn main() { io.println("{c_get()}") }
> ```
> ```c
> static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
> int mylib_get(int x);
> ```
> `blink build`, `blink run`, `blink test`:
> ```
> error[ForeignHeaderDidNotCompile] (E08xx): header `mylib.h` does not compile with this C compiler (x86_64-linux)
>  --> src/main.bl:1:1
>   note: the prototype test can not check a declaration that names this header
>   note: the C compiler's output:
>         native/mylib.h:1:49: error: initialization of 'long int *' from incompatible pointer type 'int *'
>   help: correct the header, or remove `header:`; the call then uses this declaration's prototype, unchecked
> ```
> Exit 1. The unit compile does not start. The span is the first `@ffi` that names the header, and one note lists the others. The output note is copied text, not read: the verdict is from pass/fail only, as decided. Without the line, no person or model can act on it (I0017 already prints compiler output). `blink check` prints nothing (no C compiler).
>
> ### Case 2: same header, `header:` in the unit (after it lands)
>
> Same output, same exit 1. Today this build is I0017, exit 101. D1 changes no outcome here. It moves the stop earlier and makes it name the header. On these hosts the stop is not new.
>
> ### Case 3: header with only a plain warning
>
> ```c
> static inline int mylib_w(int x) { int unused; return x; }
> int mylib_get(int x);
> ```
> With a correct declaration: build passes, no output. With `fn c_get(x: Ptr[I64]) -> I32 ! ()`: E0861 as usual. The warning does not matter. The control reads pass/fail, and only the two pinned diagnostics become errors.
>
> ### Case 4: tcc and a wrong declaration
>
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get(x: Ptr[I64]) -> I32 ! ()
> ```
> `CC=tcc blink build`:
> ```
> note[PrototypeTestHasNoEffect] (I00xx): the C compiler does not refuse a pointer mismatch, so the prototype test can not find a wrong `@ffi` prototype on this host
>   help: build with gcc 13 or later, clang or zig cc to check the `@ffi` declarations
> built: build/main
> ```
> Exit 0. It shows once for each command, never once for each declaration. It shows only when the program has an `@ffi` fn. It is a note, not a warning: the user can not fix it in source, and `--strict` must not fail on it. This answers Q3: yes, the same rule covers tcc, but as a note, because the build is not wrong, only unchecked.
>
> ## Q2: the pins apply to header code, the same as to the unit
>
> The test must give the verdict of the unit compile. The unit compiles the header with the pins. If the test scoped the pins to its own lines (`#pragma GCC diagnostic` push/pop works on gcc and clang, measured), the test would pass and the unit would then stop with I0017. To scope them in the unit too, the generated C would turn a default error back into a warning. That weakens the compiler for a header that is wrong. On current hosts, scoping changes nothing anyway (see measurement 1).
>
> ## Cost
>
> Control: one extra compile per build when all headers pass, cached by header content, flags, CC and target. Canary: one compile per CC and target, cached. Both are a few tens of ms when cold and zero when warm. No test to run, no new flag.
>
> ## Third-party headers you can not edit
>
> A stop on a vendor header is not a false stop: the unit fails on that same header (measured on all three hosts). The help gives the way out that exists today (remove `header:`). A warning would be noise that nobody can fix, and users learn to ignore warnings.
>
> ## D0 (do nothing): rejected
>
> It keeps a silent skip, and it keeps I0017 with "compiler bug" for a fault in the user's header.
>
> ## Other languages
>
> cgo, Rust bindgen, Zig `@cImport` and the Swift ClangImporter all stop when a header does not compile, and show the clang or gcc text. None skips a header silently. None supports a compiler like tcc that accepts the mismatch: cgo needs gcc or clang.

- **AI/ML:**

> # [ticket], Phase A: AI/ML seat
>
> ## Measurements (probe/aiml/, header `mylib.h` of the MVCE)
>
> | compile | gcc 16.2 | clang 23 | zig cc (clang 22) | tcc |
> |---|---|---|---|---|
> | `#include "mylib.h"` alone, pins | fail | fail | fail | pass |
> | good call, **no pins**, `-I` | fail | fail | fail | pass |
> | good call, pins, `-isystem` | fail | pass | pass | pass |
> | wrong call (`long *` to `int`), pins | fail | fail | fail | pass |
> | header with `int y;` unused (plain warning), pins, `-Wall` | pass | pass | pass | - |
>
> Results:
> 1. The team-lead note holds. On gcc 16 and clang 23 the header fails with no pins at all. The pins are not the cause on current compilers. They matter only on gcc 13 (and old clang).
> 2. We cannot exempt header code from the pins portably. `-isystem` exempts it on clang and zig cc, but not on gcc. So "pins on the test lines only" (Q2, second option) gives a different verdict per host. That breaks the rule that one source gives one verdict.
>
> ## Proposal A1: a "header alone" probe makes the test total (recommended)
>
> The header test gets one more pass/fail probe for each distinct header: the runtime prologue, then the `#include` lines of the unit in unit order, with the flags and pins of the unit compile, and no line that the test writes. It runs after E0859 (header found) and before the layout test.
>
> - Probe fails: new stop `ForeignHeaderRejected` (E0863) at the first `@ffi` line that names the header, exit 1. The layout test, the prototype test and the unit compile do not start.
> - Probe passes: the header compiles by itself. Every later probe failure then comes from the lines that the test writes. A guard failure means the header does not declare the symbol (E0861, V1-E, decided). So "no verdict" cannot occur. If a probe that must pass (the types control) fails after this, the compiler has a bug: an ice, not a user error.
>
> How the test knows what it prints: one bit (pass/fail of the header-alone probe). It never reads the C compiler's text.
>
> ### Case 1: the MVCE (today, header not in the unit)
>
> ```c
> // native/mylib.h
> static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
> int mylib_get(int x);
> ```
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get() -> I32 ! ()
>
> fn main() { io.println("{c_get()}") }
> ```
> `blink build src/main.bl` and `blink test`:
> ```
> error[ForeignHeaderRejected] (E0863): the C compiler rejects header `mylib.h` by itself
>  --> src/main.bl:1:1
>   = note: the test compiled only `#include "mylib.h"` with the flags of the unit compile; the code of the header fails, not this declaration
>   = help: fix the header, or remove `header:` so that the signature of this declaration is the C prototype
> ```
> Exit 1. `blink check`: no output, exit 0 (no C compiler, decided).
>
> ### Case 2: the same header once `header:` puts it in the unit
>
> Same output, same exit. Without A1 this build stops at I0017, exit 101. I0017 is an ice code, and its note says "the code of the user is not the cause". That is wrong here, and a model that reads "ice" files a compiler bug or retries. E0863 names the file to fix.
>
> So A1 adds no new false stop: in Case 2 the build stops anyway. A1 only moves the stop earlier and names the cause.
>
> ### Case 3: a header fault that is a plain warning
>
> ```c
> static inline int w(int x) { int y; return x; }
> int mylib_get(int x);
> ```
> No output from the test. The probe passes (measured on all three compilers). Blink reads only pass/fail and adds no `-Werror` beyond the two pins. It does not matter.
>
> ### Case 4: tcc, wrong declaration
>
> ```c
> int mylib_get(int x);
> ```
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get(p: Ptr[I64]) -> I32 ! ()
> ```
> Under tcc: the header-alone probe passes, the prototype test passes, the unit compiles (measured: tcc gives warnings, exit 0). `built: build/main`, exit 0. No new output.
>
> Q3: no. tcc gives a verdict (pass); it is a known limit, which §9.1 already states. A warning on every tcc build has one fix, "use another compiler", and I0017 already refuses to say that. A warning that a user cannot act on teaches users and models to ignore warnings.
>
> ## Answers
>
> - Q0: yes. A silent pass that hides a wrong declaration is the worst result for a model: it trusts the green build and ships the bug.
> - Q1: the "no verdict" state goes away (A1). Its one real cause becomes a stop, E0863, on `blink build` and `blink test`. `blink check` is unchanged.
> - Q2: the pins apply to header code the same as to the test lines. One translation unit, one set of flags. Scoping them per line is not portable (measured).
> - Q3: no output for tcc.
>
> ## Tradeoffs (AI/ML lens)
>
> - Cost: one extra C compile per distinct header, cached with the other probes. Small next to the unit compile.
> - False stops on third-party headers: only a header that gcc 14+ and clang 23 already reject by default. That header breaks the build on those hosts with or without Blink. The help gives an exit that needs no edit to the header (drop `header:`).
> - Determinism: same verdict on gcc, clang and zig cc for the MVCE (measured). On gcc 13 the pins cause the stop; the message does not claim the pins are the cause, so it is true on every host.
> - Learnability: one code, one cause, one file to fix. No new decision point for the binding author: nothing to write in Blink.
>
> ## Proposal A0: do nothing (rejected)
>
> Case 1 passes silently with a wrong declaration. Case 2 stops at I0017 (ice, exit 101) with a note that blames the compiler. Both mislead a model.
>
> ## Cross-language
>
> cgo stops the build when the preamble does not compile. Zig `@cImport` stops when translate-c fails. Rust bindgen fails `build.rs` when clang cannot parse the header. Swift stops with "could not build module". None of them passes silently on a header that does not compile.

- **Minimalism:**

> # [ticket] — Minimalism (Min), Phase A
>
> ## Measured (main 14e6f7ba, gcc 16.2.1, clang, zig cc 0.17.1; probe/min/)
>
> 1. The MVCE header fails on all three compilers **with no pins**. `long *q = p;` (int * to long *) is
>    an error by default in gcc 14+, clang and zig cc. Plain `cc -c` exits 1 on each. The pins add
>    nothing here. Only gcc 13 (warning by default) turns pass into fail because of the pins.
> 2. The header test (E0859) runs `cc -E` (preprocess only, src/cli.bl:2125). A type fault in header
>    code never trips it. That is correct: the header is there.
> 3. On main, `blink build` of the MVCE passes with and without the `static inline` line. The pins
>    (`rg incompatible-pointer src/` = 0 hits) and the prototype test are not on main yet. The ticket
>    measures an unlanded branch.
>
> ## Proposal A (recommended): do nothing new; land `header:` as decided
>
> Q0: Yes, the silent pass is a defect. But it is a gap in the `header:` implementation, which is
> already decided (V2 6-0: every wrapper the unit compiles is in the test, with the includes of the
> unit). It is not a spec gap.
>
> The reason: every probe gets the same compiler, flags and includes as the unit. So a header that
> makes the guard give no answer makes the unit compile fail too. "No verdict" then always ends in a
> stop that already exists: `GeneratedCDidNotCompile` (I0017). No new code, no new message.
>
> Q1: Visible, yes, through I0017, on `blink build`, `blink run` and `blink test`. Not `blink check`
> (it runs no C compiler).
> Q2: The pins apply to the whole compile, header code included. Flags cannot pick lines. Scoping by
> `#pragma GCC diagnostic` push/pop around each `#include` is new machinery for a gcc-13-only case.
> One source, one verdict, on every supported compiler.
> Q3: tcc is already outside the promise (:118, :196, :3282). The I0017 note names tcc. No new text.
>
> ### Cases
>
> MVCE today (unit does not include the header): passes, wrong declaration not found. Fixed by
> landing `header:`. Ask for one corpus row with this MVCE when it lands.
>
> ```c
> // native/mylib.h
> static inline int mylib_peek(int *p) { long *q = p; return (int)*q; }
> int mylib_get(int x);
> ```
> ```blink
> @ffi("mylib", "mylib_get", header: "mylib.h")
> @trusted(audit: "t")
> fn c_get() -> I32 ! ()
>
> fn main() {
>     io.println("{c_get()}")
> }
> ```
>
> Same header, `header:` landed (unit includes it): E0859 passes (`-E`), the prototype test gives no
> verdict, the unit compile fails. Output:
> ```
> error[GeneratedCDidNotCompile] (I0017)
>   note: <C compiler text: mylib.h:1: incompatible pointer type 'int *' to 'long *'>
>   note: this program has @ffi declarations: c_get (src/main.bl:1); a wrong prototype can also cause this
> exit 101
> ```
> The cc text names `mylib.h:1`. A human or model can act on that. The test does not read it; I0017
> already prints the C compiler's output as notes.
>
> Header fault that is only a plain warning (say an unused static function, `-Wunused-function`):
> does not matter. Probes and unit pass; the test reads pass/fail only. Verdict as normal:
> `mylib_get(int)` against `fn c_get()` is E0861 at the `@ffi` line, exit 1.
>
> tcc, wrong declaration (`fn c_get(x: Ptr[U8]) -> I32` against `int mylib_get(int)`): tcc accepts,
> no E0861, build passes, wrong call at run time. Same as today's spec. No warning: a warning on every
> tcc build that says "tcc is unchecked" is noise the user cannot fix except by changing compiler.
>
> ## Proposal B (fallback, if the panel wants a precise cause): one note on I0017
>
> Only if a "no verdict" can reach I0017. Add one note to the I0017 that follows:
> ```
>   note: the prototype test could not compile its probes for `mylib_get` (src/main.bl:1);
>         a header the unit reads does not compile with this C compiler
> ```
> How the test knows: the guard probe failed (pass/fail bit) and the bare-include probe failed. No cc
> text read. Cost: one extra bare-include probe per header, only on the failure path. No new code
> number, no new stop, no warning.
>
> I reject a new warning or a new error for "no verdict". It adds a code and a doc for a case that
> already stops with the cause in the cc text.
>
> ## Tradeoffs
>
> - Cost per build: A adds zero probes. B adds one probe per header, failure path only.
> - Third-party headers you cannot edit: no new false stop. On gcc 14+/clang/zig the C compiler already
>   rejects the header in the unit; Blink adds nothing. gcc 13 is the one case where the pins alone
>   reject a header; the fix (newer compiler, or a wrapper header) is the same as on gcc 14.
> - Determinism: pins on the whole compile give the same verdict on gcc 13+, clang and zig cc.
> - Message: the cc text names the header line. B adds a line that a model can act on without
>   reading C errors.
>
> ## Cross-language
>
> cgo and Zig `@cImport` compile the whole header with the user's flags; a header that does not compile
> stops the build with the C compiler's text. Neither scopes warnings to its own lines. Rust bindgen
> reports a clang parse error the same way. Blink with A matches all three.

### Phase B — Debate (round 1)

The digest of the moderator, verbatim:

> # [ticket] — Phase A.5 digest (mechanical dedupe), Phase B round 1
>
> The full proposals are in this directory: sys-A.md, web-A.md, plt-A.md, devops-A.md, aiml-A.md, min-A.md. Read them all.
>
> ## Same in all six proposals (not on the ballot unless someone objects)
>
> - Q2: the pins apply to the whole compile, header code included (sys, web, plt, devops, aiml, min).
> - A header fault that is only a plain warning (not one of the two pinned diagnostics) does not change pass or fail. No output (all six).
> - `blink check` shows nothing, because it runs no C compiler (all six).
> - Measured by all six: gcc 16, clang 23 and zig cc reject the MVCE header with no pins. Only gcc 13 is different.
>
> ## Q0/Q1 — what happens when the header itself does not compile
>
> ### Option H: a "header alone" probe, and a new stop (sys S1, web W1, plt P1, devops D1, aiml A1)
>
> Compile `#include "mylib.h"` alone with the unit's compiler, flags and pins. If it fails: new error, exit 1, on build and test (devops: and run). The proposers' outputs:
>
> sys:
> ```
> error[E08xx]: the C compiler rejects the header `mylib.h`
>  --> src/main.bl:1:28
>   |
> 1 | @ffi("mylib", "mylib_get", header: "mylib.h")
>   |                            ^^^^^^^^^^^^^^^^^ a C file that includes only this header does not compile
>   = note: the prototype test cannot test `c_get` (and 0 other declarations) against this header
>   = help: to see the errors of the C compiler, run:
>           gcc -c -o /dev/null -Werror=incompatible-pointer-types -Werror=int-conversion -Inative build/probe/hdr_mylib.c
> ```
> web:
> ```
> error[ForeignHeaderDidNotCompile]: header "mylib.h" does not compile with this C compiler
>   --> src/main.bl:1:1
>    = note: the header is found, but `#include "mylib.h"` alone fails with cc and the build's flags
>    = help: compile a file that has only `#include "mylib.h"` to see the C error; if you cannot
>            edit the header, write your own header that declares only the symbols you bind
> ```
> plt:
> ```
> error[ForeignHeaderDoesNotCompile] (E08xx) at src/main.bl:1
>   `mylib.h` is found, but it does not compile with this unit's C compiler and flags (gcc 16.2.1, x86_64-linux)
>   note: the prototype test cannot test `c_get`, because its header does not compile
>   help: fix the header, or remove `header:`; the call then uses this declaration's prototype, unchecked
> ```
> devops:
> ```
> error[ForeignHeaderDidNotCompile] (E08xx): header `mylib.h` does not compile with this C compiler (x86_64-linux)
>  --> src/main.bl:1:1
>   note: the prototype test can not check a declaration that names this header
>   note: the C compiler's output:
>         native/mylib.h:1:49: error: initialization of 'long int *' from incompatible pointer type 'int *'
>   help: correct the header, or remove `header:`; the call then uses this declaration's prototype, unchecked
> ```
> aiml:
> ```
> error[ForeignHeaderRejected] (E0863): the C compiler rejects header `mylib.h` by itself
>  --> src/main.bl:1:1
>   = note: the test compiled only `#include "mylib.h"` with the flags of the unit compile; the code of the header fails, not this declaration
>   = help: fix the header, or remove `header:` so that the signature of this declaration is the C prototype
> ```
>
> Variations inside H (flagged for debate):
> - (a) When the probe runs. sys: "only after a failure, once per header" (when the guard fails). web, plt, aiml: always, once per distinct header, before E0862/E0861. devops: always, "One TU with all headers on the normal path. On failure, one TU per header to find which one." sys also says: "a broken header can give a false E0862 now. The new step must come before E0862. I did not measure that case."
> - (b) What the message gives the user to see the C error. devops: copies the C compiler's output into a note ("The output note is copied text, not read"). sys: prints the probe's command and keeps its file. web: help says compile the header alone. plt, aiml: neither.
> - (c) Help text. plt, devops, aiml: fix the header, or remove `header:`. web: write your own header with only the symbols you bind. sys: the command line.
> - (d) Span. sys: the `header:` argument. web, plt, devops, aiml: the `@ffi` line (the first that names the header; others listed in a note).
> - (e) Header-alone passes, but the guard fails. plt: "Header-alone PASSES but the guard or the types control FAILS: the fault is in C that Blink wrote. That is `GeneratedCDidNotCompile` (I0017)". web, devops, aiml: guard fails → E0861 ("header does not declare the symbol", V1-E); aiml: only the types control failing is an ice.
> - (f) Code: aiml names E0863 (checked unused). Others leave the number open.
>
> ### Option N: no spec change; land header: as decided (min A)
>
> min: "every probe gets the same compiler, flags and includes as the unit. So a header that makes the guard give no answer makes the unit compile fail too. 'No verdict' then always ends in a stop that already exists: `GeneratedCDidNotCompile` (I0017)."
> ```
> error[GeneratedCDidNotCompile] (I0017)
>   note: <C compiler text: mylib.h:1: incompatible pointer type 'int *' to 'long *'>
>   note: this program has @ffi declarations: c_get (src/main.bl:1); a wrong prototype can also cause this
> exit 101
> ```
> (Today, before header: lands: the MVCE builds, exit 0.)
>
> ### Option NB: N plus one note on the I0017 (min B, fallback)
>
> ```
>   note: the prototype test could not compile its probes for `mylib_get` (src/main.bl:1);
>         a header the unit reads does not compile with this C compiler
> ```
> From the guard bit plus a bare-include probe, failure path only. No new code, no new stop, no warning.
>
> ## Q3 — tcc (a compiler that accepts a pointer mismatch)
>
> - **T0, no output** (aiml, min; web's main answer is "no"). aiml: "A warning on every tcc build has one fix, 'use another compiler', and I0017 already refuses to say that."
> - **TN, a note from a canary probe** (plt, devops). Compile a known-bad pair (`int *p = 0; long *q = p;`) under the pins; if it passes, print one note per build. plt: "only when at least one `@ffi` names a header"; devops: "only when the program has an `@ffi` fn". Not a warning, so `--strict` does not fail. Exit 0.
>   plt: `note: this C compiler (tcc 0.9.27) accepts pointer type mismatches, so the prototype test cannot fail`
>   devops: `note[PrototypeTestHasNoEffect] (I00xx): the C compiler does not refuse a pointer mismatch, so the prototype test can not find a wrong `@ffi` prototype on this host` + `help: build with gcc 13 or later, clang or zig cc to check the `@ffi` declarations`
> - **TW, a warning from a canary probe** (sys). Cached per compiler identity; also catches `-fpermissive` in CFLAGS and an unknown cc. Exit 0.
>   `warning[W08xx]: the C compiler `tcc` accepts a pointer mismatch, so the prototype test cannot find a wrong `@ffi` prototype` + `= note: 3 `@ffi` declarations are not tested`
> - **Variation (web, optional, "lean yes")**: a note found by a `#if defined(__TINYC__)` probe instead of a canary: "note: tcc does not apply the pointer checks of the prototype test; a pointer mismatch at an @ffi call is not found". web also measured: under tcc an arity mismatch is a hard error, so tcc does give a real fail for arity.
>
> ## Facts surfaced by the moderator
>
> 1. V1-E of decisions/ffi-header-governs-prototype.md (6-0, decided): a named header that is found but does not declare the symbol for the target is E0861 at the @ffi line. (Relevant to variation (e).)
> 2. Already decided: the prototype test "reads only pass or fail, and it does not read the text of the C compiler" (§9.1). I0017 already prints the C compiler's output as notes (min). (Relevant to variation (b).)
> 3. The [ticket] panel (voted, not landed) settled that E0861's fallback text is used when no split probe reproduces the verdict.
>
> ## Round 1 task
>
> Reply to team-lead with your position on: Q0/Q1 (H, N or NB, and if H, your choice on each of variations (a)-(e)), and Q3 (T0, TN, TW; canary or `__TINYC__`). Answer the other seats' points where you disagree. Remember: the panel decides behavior; if a point is only wording, say so and it goes to the writer notes. Say "stable, ready to vote" if you are. Write your reply to <seat>-B1.md in this directory too.

- **Systems:**

> # [ticket] Phase B round 1 — Systems seat
>
> ## New measurement (probe/sys/canary.c: `q = p;` with `int *p`, `long *q`, pins on)
>
> | extra flag | gcc 16 pins first | gcc 16 pins last | clang 23 pins first | clang 23 pins last |
> |---|---|---|---|---|
> | none | 1 | 1 | 1 | 1 |
> | `-fpermissive` | 1 | 1 | 1 | 1 |
> | `-w` | 1 | 1 | 1 | 1 |
> | `-Wno-incompatible-pointer-types` | **0** | 1 | **0** | 1 |
>
> Correction to my sys-A: `-fpermissive` does NOT turn off the explicit pins. A user cflag
> `-Wno-incompatible-pointer-types` that comes after the pins does. `probe_unsafe_cflag` does not
> reject it today. So "the pins hold" depends on the order of flags. The pins must come last. (Order of
> flags is a codegen chore, but it shows that a capability probe finds what a name check does not.)
>
> ## Q0/Q1: H
>
> Against N (min A): once header: lands, the stop is I0017. I0017 is an ice code (exit 101) and says
> the user's code is not the cause. Here the user's header is the cause. aiml is right that a model
> reading "ice" files a compiler bug. N also leaves two holes. (1) A struct mirror on the same header:
> the layout probe includes the header and fails, so the user gets a false E0862 before the unit
> compile runs. (2) The build stays green until header: lands. NB puts a correct note on a wrong code
> and the wrong exit. No.
>
> Variations:
> - (a) When the probe runs. My choice: only after a probe that includes the header fails (layout or
>   guard), and before that probe's E0862 or E0861 is printed. This gives the same verdicts as
>   "always": the header-alone file is a prefix of every probe that includes the header, so if it fails,
>   each such probe fails too. The pass path then costs zero extra compiles. A condition: the
>   header-alone file must hold exactly what the probes put before the include (the runtime prologue,
>   the same macros), or the two can differ. I do not hold out on this. "Always, once per distinct
>   header" (web, plt, aiml) costs one small compile per header per build, and devops's "one file with
>   all headers, split on failure" costs one compile per build. All three give the same output. If the
>   panel wants one rule that is easy to state, I accept "always".
> - (b) Show the C text. I change to devops: copy the C compiler's output into a note, the same as
>   I0017 does. The verdict still comes from the exit status alone, so this does not break "reads only
>   pass or fail". Copying is not reading. My command line names a scratch path in build/, which a
>   user cannot always run as is. A cap on the line count is wording.
> - (c) Help text: wording. Writer notes: "fix the header" plus web's "write your own header that
>   declares only the symbols you bind" (the fix for a third-party header you cannot edit). "Remove
>   `header:`" is fine as a third choice if it says the call is then unchecked.
> - (d) Span: wording. I accept the `@ffi` line of the first declaration, others in a note.
> - (e) Header alone passes, guard fails: E0861 (V1-E, decided, 6-0). plt's I0017 here contradicts
>   V1-E: the header compiles and does not declare the symbol, which is a user fault. Only a failing
>   types control (a probe that must pass) is an ice. I agree with aiml.
> - Order: E0859 -> header compiles -> E0862 -> E0861.
> - (f) Number: any free code. Not mine to pick.
>
> gcc 13 is the one compiler where the pins alone make a header fail. The stop is right there: the
> same source then gives the same result on gcc 13 and gcc 16.
>
> ## Q3: TN with a canary (changed from TW)
>
> aiml and min are right that a warning with "use another compiler" as its only fix is noise, and a
> warning fails `--strict`. So: a note, not a warning. But not T0, and not `__TINYC__`:
> - The canary finds every case where the pins do not hold: tcc, a user cflag that turns the pins off
>   (measured above, on gcc and clang, which ARE supported compilers), and an unknown cc. `__TINYC__`
>   finds only tcc. The gcc case is the one that matters: a user on a supported compiler loses E0861
>   in silence.
> - Cost: one tiny compile, cached per compiler identity plus flags. Only when at least one `@ffi`
>   names a header (plt). With no header, the declaration's own signature is the C prototype, so the
>   test has nothing to find and the note would be noise. This is narrower than devops's "any `@ffi`
>   fn", and I take plt's rule.
> - Exit 0. The note names the compiler, and says the prototype test cannot fail on this host.
>
> Positions: H with (a) failure path (accept "always"), (b) copy C text, (e) E0861 per V1-E; Q3 TN
> with a canary. Stable, ready to vote.

- **Web/Scripting:**

> # [ticket] Phase B round 1 — Web seat
>
> ## Q0/Q1: H (a header-alone probe and a new stop). Not N, not NB.
>
> **Against N (min).** N says a broken header always ends in I0017. It does not:
> 1. V1-E (decided) reads "guard fails" as E0861 "the header does not declare `mylib_get`". Without a
>    header-alone result, a broken header gives that E0861. The message is false: the header does
>    declare the symbol. The user goes looking for a missing declaration that is there.
> 2. sys's point: the layout test (E0862) includes the header and runs first. A broken header can give
>    a false E0862 for a program that has an `@ffi.struct`. N never reaches I0017 there either.
> 3. When it does reach I0017, the code says "generated C did not compile", exit 101, and the note
>    points at a wrong prototype. Both point away from the real cause.
> To make N correct, the implementation must tell "header broken" from "symbol missing" anyway. That
> is the H probe. Once you run it, naming the header in its own stop costs nothing more.
> NB fixes only point 3, not 1 or 2.
>
> **Variations:**
> - (a) When it runs: behavior is "for a header that does not compile alone, this stop wins over E0862
>   and E0861". Always-run (me, plt, aiml), lazy after a failed test (sys), or one TU for all headers
>   (devops) give the same output. That is an implementation choice. One condition: if lazy, it must
>   run after a failed layout test too, not only after a failed guard (sys's own E0862 point).
> - (b) Show the C error: **devops** (copy the C compiler's output into a note). The verdict still
>   comes only from the exit status, and I0017 already copies cc text, so no decided rule breaks. For
>   a JS/Python dev this is the only line that says what is wrong. I drop my "compile it yourself"
>   help in favor of it. sys's command line is a good extra; wording, writer notes.
> - (c) Help: behavior point only: the help must not offer "remove `header:`" without saying the call
>   is then unchecked (plt's wording does this; aiml's does not). The shim header ("your own header that
>   declares only the symbols you bind") is the fix for a vendor header you cannot edit. Order and
>   words: writer notes.
> - (d) Span: wording. sys's span on the `header:` argument is the most precise; I accept it.
> - (e) Header alone passes, guard fails: **E0861 (V1-E)**, as devops and aiml say. The guard tests
>   only "is the symbol declared", so with a good header that is the only cause. Against plt: I0017
>   there contradicts a 6-0 decision. Only a failed types control (C that Blink writes for its own
>   types) is an internal error (aiml).
> - Run on `blink build`, `blink test`, and `blink run` (devops is right; run builds).
>
> ## Q3: TN, from a canary. Not `__TINYC__`.
>
> I change my `__TINYC__` idea to the canary (sys, plt, devops). The canary tests the capability, so it
> also catches `-fpermissive` in CFLAGS and an unknown cc. A name check does not.
>
> Note, not warning (against sys TW): with a warning, `--strict` fails every tcc build, and the only
> fix is "change compiler". Against T0 (aiml, min): many users do not pick their cc; CI images and
> `CC=` from a distro pick it. One line that says "your @ffi prototypes are not checked here" is the
> difference between knowing and not knowing. Exit 0, once per build.
>
> Condition: plt's, only when at least one `@ffi` names a header. With no header the declaration is the
> prototype, so there is nothing for the test to miss.
>
> **Stable, ready to vote.**

- **PLT:**

> # [ticket] Phase B round 1 — PLT seat
>
> ## Q0/Q1: H (rank H > NB > N)
>
> Answer to min (N). min is right that after `header:` lands, every "no verdict" ends in a stop. But the
> stop is I0017: severity "ice", exit 101, and the text says Blink wrote bad C. The fault is in the user's
> header. The category of a diagnostic is part of what it promises. Telling the user "compiler bug" for a
> user fault is a wrong verdict, not just a weak message. A model that reads I0017 will file a bug
> against Blink and not fix the header. NB adds a true note, but it keeps the wrong category and the wrong
> exit code. So H. min's cost point is answered by (a) below: on a passing build H costs zero.
>
> ### Variations
>
> **(a) When: failure path only (sys).** I change my position. Behavior must be the same *as if* the
> header-alone probe ran first, before E0862. Running it only when a probe that includes the header
> fails gives that same output. A broken header makes every probe that includes it fail, so no case
> can skip it. Rule: before Blink reports E0862 or E0861 for a declaration, it runs the header-alone probe
> for each header that the failing probe includes. If that probe fails, the new error replaces the E0862 or E0861.
> This also covers sys's false E0862. Passing builds pay 0 compiles. This is a cost choice with one
> result; I can live with "always" too.
>
> **(b) Show the C error: devops (copy the C compiler's output into a note) or sys (print the command).**
> No verdict reads the text, so the decided "pass or fail only" rule holds. I0017 already prints C
> output as notes, so this is not new surface. I lean devops: the text is the one thing that tells you
> which line is wrong, and a model acts on it at once. Mostly wording. Send it to the writer notes if the
> panel agrees that "print, never read" is allowed.
>
> **(c) Help: "fix the header, or remove `header:`".** web's "write your own header with only the symbols
> you bind" is a third fix, and it is the one that works for a third-party header you cannot edit and still
> keeps the check. I accept it as a second help line. This is wording.
>
> **(d) Span: wording.** I prefer sys's span on the `header:` argument (that names the cause), but it is
> not a behavior question.
>
> **(e) I concede to web, devops and aiml.** I mixed up the guard with the types control.
> - header-alone passes, declared-symbol guard fails: the header does not declare the symbol. That is
>   E0861 per V1-E (decided 6-0).
> - header-alone passes, guard passes, types control fails: the failing C is C that Blink wrote. That
>   is I0017 (aiml's split).
> - header-alone fails: the new error.
> So: a total partition, and each branch is known from pass or fail bits only.
>
> **(f) Code:** E0863 if it is free (aiml checked it). Writer item.
>
> ## Q3: TN, canary probe, note (not a warning)
>
> - **Canary over `__TINYC__`.** A name check lists compilers. It misses `-fpermissive` in CFLAGS (sys
>   measured that gcc 16 then passes the bad header) and any unknown cc. The canary tests the capability
>   the test needs: "does this compiler refuse a pointer mismatch under the pins?" That is the right
>   question to ask of a decision procedure. Cache it per compiler identity plus flags. With
>   `-fpermissive` in flags, the cache key must include the flags, or the result is stale.
> - **Note over warning (to sys).** A warning fails `--strict` on every tcc build, and on tcc the user
>   has no fix in their source. The note states a fact about the check: the test cannot fail here.
> - **To aiml and min (T0).** I0017 is never reached for a wrong pointer under tcc: tcc accepts the
>   unit, and the build is green. So no output today tells the user that the check did not run. That is
>   the same silent pass as Q0, on another axis. The note gives no advice, so it does not contradict
>   I0017. I drop devops's help line ("build with gcc ..."). The note only states the fact.
> - web's fact that tcc does refuse an arity mismatch: so the note must say "pointer mismatches", not "the
>   test cannot fail".
>
> ```
> note: this C compiler accepts a pointer type mismatch, so the prototype test cannot find a wrong pointer type in an `@ffi` prototype
> ```
> Once per build, only when at least one `@ffi` declaration is tested. Exit code unchanged.
>
> ## Status
> Stable, ready to vote: H with (a) failure path / as-if-first, (e) the three-way partition above, and TN canary note.
> (b), (c), (d), (f) are wording, for the writer notes.

- **DevOps:**

> # [ticket] — DevOps, Phase B round 1
>
> ## Q0/Q1: H. Against N and NB.
>
> New point against N (min A). V1-E is decided: "a header that is found but does not declare the symbol" is E0861, and the test knows it from a failed guard. Once `header:` lands, the guard for the MVCE fails because the header does not compile. With no header-alone probe, the test reads that as V1-E. The build then stops with a false E0861: "`mylib.h` does not declare `mylib_get` for this target". The header does declare it. So under N the user does not get I0017 with the cc text. The user gets an E0861 that lies, and the help tells them to remove `header:`. sys adds a second false stop: the layout test also includes the header, so a broken header can show as E0862 first. N does not end in I0017 every time. It ends in whichever probe fails first.
>
> NB has the same fault: the probes stop at E0862 or E0861 before the unit compile, so an I0017 note never runs.
>
> Even if N did reach I0017, I0017 exits 101 and says "an internal error ... compiler bug". A broken vendor header is not our bug. CI tooling and models read exit 101 as "report it to Blink".
>
> ## Variations
>
> **(a) When it runs.** The behavior to vote on: a header that does not compile gives the new stop, and no E0862 or E0861 is reported for a declaration that names it. When the probe runs is an implementation choice. I change to sys's lazy form, widened: run header-alone only when a probe that includes that header fails, whether it is a layout probe or a prototype probe, and run it before the stop is printed. A passing build pays zero extra compiles. The output is the same as "always". This drops my "one TU with all headers" plan.
>
> **(b) Showing the C error.** Keep the copied cc output in a note, capped at the first 10 lines and marked as the compiler's text. This is behavior, not wording. Decided fact 2 says the test does not *read* the text. Copying it is not reading it, and I0017 already copies it. A model in CI can act on it in one pass. With only a command line, it must rerun a probe file that may be gone, from a path on the build host. I accept sys's command line as an extra help line. I do not accept it as a replacement.
>
> **(c) Help.** Two fixes, and both are behavior because each tells the user a different action. (1) Point `header:` at a header you write that declares only the symbols you bind (web). The call is still checked. Put this first: it is the fix for a vendor header you cannot edit. (2) Remove `header:`; the call then uses this declaration's prototype, unchecked. "Correct the header" goes away: the user who can edit it does not need the help.
>
> **(d) Span.** Wording, so writer notes. I lean to sys: underline the `header:` argument, because that is the cause, and list the other declarations that name the header in one note.
>
> **(e) Header-alone passes, guard fails.** E0861 under V1-E (with web and aiml). Against plt: when the header compiles alone, a failed guard means the symbol is not declared. That is the decided V1-E case, not C that Blink wrote. Only a failed types control (a probe that must pass) is an internal error (aiml).
>
> **Code.** E0863 if it is still unused (aiml checked). I0017 stays for C that Blink wrote.
>
> ## Q3: TN, canary
>
> - **Canary, not `__TINYC__`.** The canary tests whether the pins work, not which compiler it is. It also catches `-fpermissive` in CFLAGS (sys measured that gcc 16 passes with it) and any unknown cc. `__TINYC__` catches only tcc.
> - **Note, not warning (against sys TW).** `--strict` and the warning gate treat a warning as a fault in the source. The user cannot fix a host property in the source. A warning makes `--strict` CI fail on every tcc host, and users then turn `--strict` off. A note shows the fact and costs nothing.
> - **Against T0 (aiml, min).** The spec at :118 says the test has no effect under tcc. Saying so once per build, when it is true on this host, is the honest output. Cost: one compile per compiler, cached. aiml's point that I0017 does not say "use another compiler" is about I0017, not about this note.
> - **Scope.** The note shows when the program has any `@ffi` fn, not only one that names a header (against plt). A binding with no `header:` is in the test too (§9.1 "What the prototype test covers"), so the test has no effect on it either.
> - **Help.** When the canary fails only because of a user cflag, the help names it. Whether the test can tell this from pass/fail: one more canary compile without the user's cflags. That costs a compile only when the first canary passes. Wording otherwise goes to writer notes.
>
> Stable, ready to vote.

- **AI/ML:**

> # [ticket], Phase B round 1: AI/ML seat
>
> ## Q0/Q1: H (a new stop). Against N and NB.
>
> To min (N): I0017 is the wrong code for this case, for three reasons a model acts on.
> 1. I0017 is an `I` code with exit 101. That means "a bug in the compiler". A model that reads it files a compiler bug or retries. It does not edit `mylib.h`.
> 2. The I0017 catalog row says: when the source passes `blink check`, a note says "the code of the user is not the cause". The MVCE passes `blink check`, so that note prints, and it is false: the user's vendored header is the cause.
> 3. The C text in the note does name `mylib.h:1`. But the diagnostic that frames it is wrong, so the reader starts from a false claim. A code that names the cause costs one bit: header alone passes or fails.
>
> NB keeps reasons 1 and 2. I reject it too.
>
> Cost is not a reason to pick N. With (a) as below, the normal path adds one C compile per build.
>
> ### Variations
>
> - (a) When: always, before E0862. Take devops's form: one TU with all `@ffi` headers on the normal path. Only if it fails, one TU per header to find which one. That is one extra compile on a passing build. sys's "only after a guard failure" is out: sys says a broken header can give a false E0862, and E0862 runs before the guard. The probe must come before E0862, so it cannot wait for the guard.
> - (b) C text: devops. Copy the C compiler's output into a note, the same way I0017 does today. Copying text is not reading it: no branch depends on it, so §9.1 holds. For a model, the C error line is the most useful thing on the screen: it names the file, the line and the fault. sys's command line is a good second choice, but the model must then run another command to get the same text. I change my A1: add the copied note.
> - (c) Help: "fix the header, or remove `header:`; the call then uses this declaration's prototype, unchecked" (plt/devops form). The word "unchecked" matters: a model must know that removing `header:` turns the check off. web's "write your own header with only the symbols you bind" is a good third option; add it if the writer wants. Wording only.
> - (d) Span: the `@ffi` line of the first declaration that names the header, with a note that lists the others. sys's `header:` argument span is fine too. Wording or span detail, writer notes.
> - (e) Header alone passes, guard fails: E0861 "header does not declare the symbol". V1-E (6-0) decides this already. To plt: the guard is only `#include` + a reference to the symbol. Once the header-alone TU passes, a guard failure has one cause: the symbol is not declared. That is the V1-E case, not I0017. Only a failure of the types control after the header-alone TU passes points at C that Blink wrote, and that is a compiler bug (an ice; I0017 is fine there).
> - (f) Code: E0863 is unused (checked). Number is a writer detail.
>
> ## Q3: I move from T0 to TN (a note, from a canary).
>
> sys found the reason I missed: `-fpermissive` in CFLAGS makes gcc 16 pass the pin checks. That is not tcc and is not "a known limit" the spec names. A canary finds it. A `__TINYC__` test does not. So: canary, not compiler name.
>
> - Canary: `int *p = 0; long *q = p;` compiled with the unit's compiler and flags plus the pins. Cached per compiler identity and flags.
> - Output if the canary passes: a note, not a warning. Exit 0. `--strict` does not fail.
> - Only when at least one `@ffi` names a header (plt's scope). With no header, the declaration is its own prototype and the test has nothing to find, so the note would be noise.
> - No help that says "use another compiler" (against devops's help line). The I0017 rule never tells the user to switch compilers. The note states the fact; the user picks.
>
> Against TW (sys): a warning has no fix inside the program. A warning that a user cannot clear teaches users and models to ignore warnings, and `--strict` would fail every tcc build for something outside the code.
>
> ## Stable, ready to vote
>
> H with (a) devops, (b) devops, (c) plt/devops, (e) V1-E. Q3: TN, canary, header-only scope, no "switch compiler" help.

- **Minimalism:**

> # [ticket] — Min, Phase B round 1
>
> ## Q0/Q1: I move from N to H
>
> Two points from the other seats break my N argument.
>
> 1. sys: the layout test (E0862) runs before the prototype test and also includes the header. So a
>    broken header can stop the build with a false E0862 ("layout mismatch") before my "it always ends
>    in I0017" invariant applies. That is a wrong error, worse than a generic one. N does not fix it.
> 2. devops, aiml: I0017 is an internal error, exit 101, that says "compiler bug". Here the fault is
>    in the user's header. That sends the user, and a model, the wrong way.
>
> So H does not add a case. It replaces two wrong outputs (false E0862, ice I0017) with one correct
> stop. That passes my bar. I drop N and NB.
>
> ## Variations
>
> (a) When it runs: **extend the existing header test (E0859). Do not add a step.**
> The header test already compiles all distinct headers in one TU and splits per header on failure
> (src/cli.bl:2054-2100). Today it runs `cc -E`. Change that one probe to a real compile (`-c -o
> /dev/null`) with the unit's flags and pins. Then:
> - all headers pass the compile: done. Same probe count as today (one), so 0 extra compiles.
> - the all-headers compile fails: the existing per-header split runs. For each header, `-E` fails
>   is E0859 (as today). `-E` passes and the compile fails is the new stop.
> This puts the new stop before E0862 by construction (sys's order). It is closest to devops's
> "one TU, split on failure", with no new step and no new cache. I reject sys's "only after the
> guard fails": E0862 runs before the guard, so the guard never sees the false E0862 case.
>
> (b) What the user sees: **copy the C compiler's output into a note (devops).** Copy, do not parse.
> The verdict comes from the exit bit only, as decided. I0017 already copies cc output, so this is
> not new machinery. A printed command (sys) makes the user do one more step; a help that says "compile
> it yourself" (web) is the same step with less detail. A message with the cc line is the one a
> human or model can act on at once.
>
> (c) Help text: wording, writer notes. I lean "fix the header, or remove `header:`" (plt, devops, aiml):
> it matches the E0861 help that V1-E already set. web's "write your own header" is a valid fix but it is
> the second fix of "remove `header:`".
>
> (d) Span: the first `@ffi` that names the header, a note lists the others. Mostly wording.
>
> (e) Header compiles alone, but the guard fails: **E0861 per V1-E (decided 6-0)**, as web, devops, aiml
> say. plt's I0017 here contradicts V1-E. If only the types control fails (C that Blink wrote), that is
> an internal error (aiml).
>
> (f) Code number: open; E0863 is fine if it is free.
>
> ## Q3: T0 (no output on tcc)
>
> - A canary adds a probe, a code, and a message whose only fix is "use another compiler". The spec
>   already says tcc is outside the promise, and the I0017 note names tcc. A note on every tcc build
>   is noise that a user learns to ignore (aiml).
> - web measured that tcc still gives a real fail for arity. "The test cannot fail" (plt and devops
>   text) is false on tcc.
> - sys's point about `-fpermissive` or `-Wno-error=...` in CFLAGS: that is a flag problem, not a
>   compiler problem. `probe_unsafe_cflag` (src/cc_flags.bl:34) already exists for cflags that change
>   probe verdicts. If the panel wants it covered, add those flags there. That needs no canary.
> - If the panel insists on output, I prefer web's `__TINYC__` probe over a canary (one fact, no
>   "known-bad pair" to keep correct), and a note, never a warning (`--strict` must not fail a
>   supported, documented setup).
>
> Stable, ready to vote: H with (a) extend the E0859 header test, (b) copied cc output, (e) E0861 per
> V1-E; Q3 T0.

### Phase C — Vote

The ballot of the moderator, verbatim:

> # [ticket] — Phase C ballot (silent vote)
>
> Vote alone. Do not message other seats. The B1 replies are in this directory (*-B1.md).
>
> ## Settled by all six in round 1 (not on the ballot)
>
> - The pins apply to the whole compile, header code included.
> - A header fault that is only a plain warning changes nothing and prints nothing.
> - `blink check` shows nothing, because it runs no C compiler.
> - When a header that an `@ffi` names does not compile alone with the unit's compiler, flags and pins, the build stops with the new error, and no E0862 or E0861 shows for a declaration that names that header. When the header-alone compile runs (always, only after a probe fails, or as part of the E0859 test) is an implementation choice. Each choice must give the same output.
> - The decision table, from pass/fail bits only: header alone fails → the new error. Header alone passes and the guard fails → E0861 (V1-E). Guard passes and the types control fails → I0017.
> - The new error copies the C compiler's output into a note (devops: the first 10 lines). It copies the text and does not read it; the verdict comes from the exit status only.
> - Commands: `blink build`, `blink test`, `blink run`. Exit 1.
>
> ## Writer notes (wording, not voted)
>
> - Help: never offer "remove `header:`" without saying the call is then unchecked (web, devops, plt, aiml). web, devops and plt want a second fix: point `header:` at your own header that declares only the symbols you bind. sys: the probe's command line as an extra help line.
> - Span: sys, web, devops and plt lean to the `header:` argument. aiml and min lean to the first `@ffi` line that names the header, with a note that lists the others.
> - Code: aiml and devops want E0863 if it is free.
> - tcc note text: say "pointer type mismatch", not "cannot fail", because tcc does refuse an arity mismatch (web, plt, min).
> - Implementation (sys, measured): a user cflag `-Wno-incompatible-pointer-types` placed after the pins turns them off on gcc 16 and clang 23; `-fpermissive` does not. The pins must come last on the command line. min: such flags belong in `probe_unsafe_cflag` (src/cc_flags.bl).
>
> ## Questions
>
> **Q1. Header that does not compile alone.**
> - **H**: the new error (a stop, exit 1), as in the settled list above.
>   ```
>   error[E08xx]: header `mylib.h` does not compile with this C compiler (x86_64-linux)
>     note: the C compiler's output:
>           native/mylib.h:1:49: error: initialization of 'long int *' from incompatible pointer type 'int *'
>     help: ...
>   exit 1
>   ```
> - **N**: no spec change; once header: lands the unit compile fails with I0017, exit 101.
> - **NB**: N plus one note on that I0017: "the prototype test could not compile its probes for `mylib_get` ...".
>
> **Q2. A C compiler that does not refuse a pointer mismatch under the pins (tcc, or a flag that turns a pin off).**
> - **T0**: no output. Build green, exit 0 (aiml-A, min).
> - **TN**: a canary probe (a known-bad pointer pair compiled under the pins, cached by compiler and flags). If it passes, print one note per build. Not a warning, so `--strict` does not fail. Exit 0. No compiler-name check.
>   ```
>   note: this C compiler accepts a pointer type mismatch, so the prototype test cannot find a wrong pointer type in an `@ffi` declaration
>   built: build/main
>   ```
>
> **Q3. If TN: when does the note show?** (Vote even if you voted T0.)
> - **HD**: only when at least one `@ffi` names a header (plt, web, aiml, sys).
> - **AF**: when the program has any `@ffi` fn, with or without `header:` (devops: "a binding with no header: is in the test too").
>
> ## Vote format
>
> For each question: **Vote** (the label), **Reasoning** (2-4 sentences, your domain), **Concern** (one sentence on what could go wrong with the winning option). Write it to <seat>-C.md in this directory and send team-lead "voted" with your three labels.

- **Systems:**

> # [ticket] Phase C — Systems seat
>
> ## Q1: H
> **Vote:** H
> **Reasoning:** It costs nothing on the pass path, and only one small compile per header after a failure, so a build gets a correct cause for almost no time. N stops with I0017, an ice code with exit 101, for a fault in the user's header. It also lets the header give a false E0862 first when a struct mirror uses the same header. NB keeps the wrong code and the wrong exit. The verdict comes from one exit status under the unit's own flags, so it is the same on gcc 13+, clang and zig cc.
> **Concern:** A header that clang reaches through `-isystem` passes on clang and fails on gcc. Users will read that as a Blink fault, when the two C compilers differ.
>
> ## Q2: TN
> **Vote:** TN
> **Reasoning:** I measured that a user cflag `-Wno-incompatible-pointer-types` after the pins turns them off on gcc 16 and clang 23, which are supported compilers. T0 then loses E0861 with no sign, and a check by compiler name cannot see that. A canary cached by compiler and flags costs one tiny compile per new toolchain. A note does not fail `--strict`.
> **Concern:** If the canary's C does not match what the real probes hit (for example the pins are not last on the command line in one of them), the note and the test can disagree.
>
> ## Q3: AF
> **Vote:** AF
> **Reasoning:** devops is right: a unit header (for example one that the runtime prologue includes) can govern a binding that has no `header:`, so the test can check that binding too, and a dead pin hides a fault there. HD would give no note in that case. The cost is the same canary either way.
> **Concern:** The stdlib has `@ffi` fns, so AF can show the note on nearly every tcc build. Users then learn to ignore it.

- **Web/Scripting:**

> # [ticket] Phase C — Web seat
>
> ## Q1
> **Vote:** H
> **Reasoning:** Without a header-alone result, a broken header gives a false E0861 ("does not declare") under V1-E, or a false E0862. Where it does reach I0017, the message says Blink's C failed and points at a wrong prototype. H names the file and shows the C error, which a JS/Python dev or a model can act on in one step. It costs one probe per header.
> **Concern:** A gcc 13 user with a vendor header they cannot edit gets a stop that bare gcc 13 shows only as a warning. The help must give the shim-header fix, or that user is stuck.
>
> ## Q2
> **Vote:** TN
> **Reasoning:** Many users do not pick their C compiler; a CI image or a distro `CC=` picks it. One note says plainly that pointer types are not checked on this host, and it does not fail `--strict`. The canary also catches a user flag that turns a pin off, and a check by compiler name cannot do that.
> **Concern:** Users who build with tcc on purpose see the note on every build and learn to ignore notes.
>
> ## Q3
> **Vote:** HD
> **Reasoning:** With no `header:`, the declaration is the C prototype, so the test has nothing to compare it against and cannot miss a mismatch. A note there would be noise, and noise teaches users to skip notes.
> **Concern:** If a test of a binding with no `header:` can in fact find a mismatch (devops's claim), HD hides the note in a case where it matters.

- **PLT:**

> # [ticket] Phase C — PLT seat
>
> ## Q1: H
> **Reasoning.** The fault is in the user's header, so the stop must say so. I0017 is an ice with exit 101 that blames Blink. The category of a diagnostic is part of its promise, so a user fault shown as a compiler bug is a wrong verdict. NB adds a true note, but it keeps the wrong category and exit code. H also gives a total decision table built only from pass/fail bits, so no case is left with no verdict.
> **Concern.** A header that clang accepts through `-isystem` but gcc rejects stops on one host and passes on another. That is a real difference between the C compilers, and the spec must not promise to hide it.
>
> ## Q2: TN
> **Reasoning.** Under tcc a wrong pointer type gives a green build and no output. That is the same unearned pass as the ticket's case, on another axis. The canary tests what the test needs, refusal of a pointer mismatch under the pins, not a compiler name. So it also catches a flag that turns a pin off and any unknown compiler. A note states a fact about the check without failing `--strict`, and the user has no source fix.
> **Concern.** If the cache key leaves out the user's cflags, a flag added later can leave a stale "pins work" result, and the note goes silent.
>
> ## Q3: AF
> **Reasoning.** I change from HD. devops is right: §9.1 *What the prototype test covers* puts every `@ffi` wrapper in the test, and a binding with no `header:` is checked through any header the unit reads that declares its symbol. So the test can catch a wrong pointer for a program with no `header:` at all, and on tcc it then cannot. The note must show whenever the test runs, which is whenever the program has an `@ffi` fn.
> **Concern.** A program whose `@ffi` fns have no header declaring their symbols gets a note about a check that could not have fired for them anyway. That is noise, but the note is still true.

- **DevOps:**

> # [ticket] — DevOps, Phase C vote
>
> ## Q1: H
>
> **Reasoning.** Once `header:` lands, a broken header fails the guard. With no header-alone result, V1-E reads that as "the header does not declare the symbol". So N and NB give a false E0861, or a false E0862 first. The I0017 they count on never comes. Even if it came, exit 101 with "compiler bug" points CI and models at Blink, not at the header. H gives exit 1, names the header, and copies the cc text, so a human or a model can act in one pass.
>
> **Concern.** A stop on a vendor header the user cannot edit may feel like a new block. The help must lead with the fix that keeps the call checked (your own header with only the bound symbols).
>
> ## Q2: TN
>
> **Reasoning.** The spec says the test has no effect under tcc. Saying it once per build, only when it is true on this host, is the honest output. The canary tests whether the pins work, not the compiler's name. So it also catches a user cflag that turns a pin off, and an unknown cc. It is a note, so `--strict` does not fail on a fact about the host, and the cost is one cached compile.
>
> **Concern.** If the canary pair or its cache key is wrong (for example, flags not in the key), the note can show or stay hidden on the wrong host. Give it a corpus row on tcc and one with a pin-off cflag.
>
> ## Q3: AF
>
> **Reasoning.** A binding with no `header:` is in the test too. The call goes through any prototype the unit reads, and that includes headers of the runtime prologue or of another declaration. Under a compiler that accepts the mismatch, that check is gone as well. One rule ("the program has an `@ffi` fn") is easier to explain and to predict than one that depends on which bindings name a header.
>
> **Concern.** On a program whose bindings have no header, the note may show for a check that had almost nothing to test. That is a small cost for one line.

- **AI/ML:**

> # [ticket], Phase C: AI/ML seat
>
> ## Q1: H
>
> **Reasoning.** A model acts on the code first. I0017 is an ice code with exit 101, and its note "the code of the user is not the cause" prints on the MVCE, which is false. A model then files a compiler bug or retries. H names the cause (this header), copies the C line that shows the fault, and costs one pass/fail bit. NB keeps the misleading ice frame.
>
> **Concern.** A user may hit the stop on a third-party header that gcc 13 accepts without the pins. The help must give an exit that needs no edit to that header (their own header, or no `header:`, unchecked).
>
> ## Q2: TN
>
> **Reasoning.** A green build that cannot find a wrong pointer type is a silent false pass, and a model trusts green. A canary finds tcc and also a user flag that turns a pin off, which a name check cannot. A note, not a warning, keeps `--strict` builds green for something the program cannot fix.
>
> **Concern.** A note on every tcc build can become noise that users learn to skip, so it must print once per build, never once per declaration.
>
> ## Q3: AF
>
> **Reasoning.** I change from HD. devops is right: a binding with no `header:` is in the test too. If a header that the unit reads (the runtime prologue, or another `@ffi` header) declares the symbol, the test checks the call against that prototype (§9.1 *What the prototype test covers*). So on tcc a headerless binding of `strlen` with a wrong pointer type also goes unchecked, and HD would hide that.
>
> **Concern.** A program whose `@ffi` fns no header in the unit declares gets a note about a check that had nothing to find. That is a small cost next to hiding a real gap.

- **Minimalism:**

> # [ticket] — Min, Phase C vote
>
> ## Q1: H
> **Reasoning:** H does not add a case. It replaces two wrong outputs with one correct stop. The two wrong outputs are a false E0862 from the layout test, which runs first, and an I0017 "compiler bug" with exit 101 for a fault in the user's header. It can be built on the existing E0859 header test (a real compile in place of `-E`, the same split on failure), so a passing build pays no extra compile. N and NB keep the wrong lead, so they are not the minimal answer.
> **Concern:** A third-party header that only gcc 13 rejects under the pins now stops with a new code that the user cannot fix by editing the header. The help must offer their own header, or `header:` removed (unchecked), as real fixes.
>
> ## Q2: T0
> **Reasoning:** The spec already says tcc is outside the E0861 promise, and the I0017 note names tcc. A canary adds a probe, a cache key and a message whose only fix is "use another compiler". Users and models learn to ignore a note like that. A flag that turns a pin off is a cflag problem: `probe_unsafe_cflag` (and pins placed last) covers it with no canary.
> **Concern:** A tcc user who has not read §9.1 ships a wrong pointer type with no sign at build time, and finds it as UB at run time.
>
> ## Q3: HD
> **Reasoning:** If the note ships at all, it should show only where it says something true and useful. A program with no `header:` checks almost nothing against a real prototype, so a note on every such build is noise. The narrower scope is the smaller surface.
> **Concern:** A binding with no `header:` that a runtime-prologue header happens to declare (for example `pipe` through `unistd.h`) goes unchecked on tcc with no note.

### Phase D — Q3 only

The moderator's message, verbatim:

> # [ticket] — Phase D, Q3 only (Q1 = H 6-0 and Q2 = TN 5-1 are decided)
>
> Q3. If TN: when does the note show?
> - **HD**: only when at least one `@ffi` names a header.
> - **AF**: when the program has any `@ffi` fn.
>
> Phase C result: AF 4 (sys, plt, devops, aiml), HD 2 (web, min).
>
> ## Fact surfaced by the moderator (spec text, sections/07_trust_modules_metadata.md:166, landed)
>
> > **What the prototype test covers.** The test compiles every `@ffi` wrapper that the unit compiles, with the includes of the unit. A binding with no `header:` is in the test. If another header that the unit reads declares its symbol, the call goes through that prototype (*What `header:` does*), and a wrong claim is `ForeignPrototypeMismatch` (E0861) at the `@ffi` line, exit `1`. It is never I0017.
>
> Its example: `@ffi("pipe")` with no `header:`, `fn c_pipe(fds: Ptr[SockIn])`, gives E0861 because `unistd.h` (named by another declaration) declares `pipe`.
>
> ## Phase C reasoning, verbatim
>
> - **web (HD):** "With no `header:`, the declaration is the C prototype, so the test has nothing to compare it against and cannot miss a mismatch. A note there would be noise, and noise teaches users to skip notes." Concern: "If a test of a binding with no `header:` can in fact find a mismatch (devops's claim), HD hides the note in a case where it matters."
> - **min (HD):** "If the note ships at all, it should show only where it says something true and useful. A program with no `header:` checks almost nothing against a real prototype, so a note on every such build is noise. The narrower scope is the smaller surface." Concern: "A binding with no `header:` that a runtime-prologue header happens to declare (for example `pipe` through `unistd.h`) goes unchecked on tcc with no note."
> - **sys (AF):** "a unit header (for example one that the runtime prologue includes) can govern a binding that has no `header:`, so the test can check that binding too, and a dead pin hides a fault there. HD would give no note in that case." Concern: "The stdlib has `@ffi` fns, so AF can show the note on nearly every tcc build. Users then learn to ignore it."
> - **plt (AF):** "§9.1 *What the prototype test covers* puts every `@ffi` wrapper in the test, and a binding with no `header:` is checked through any header the unit reads that declares its symbol. ... The note must show whenever the test runs, which is whenever the program has an `@ffi` fn." Concern: "A program whose `@ffi` fns have no header declaring their symbols gets a note about a check that could not have fired for them anyway. That is noise, but the note is still true."
> - **devops (AF):** "One rule ('the program has an `@ffi` fn') is easier to explain and to predict than one that depends on which bindings name a header." Concern: "On a program whose bindings have no header, the note may show for a check that had almost nothing to test."
> - **aiml (AF):** "on tcc a headerless binding of `strlen` with a wrong pointer type also goes unchecked, and HD would hide that." Concern: "a note about a check that had nothing to find. That is a small cost next to hiding a real gap."
>
> ## Your task
>
> One focused round, then the re-vote, in one reply. Write <seat>-D.md in this directory: optional rebuttal (max 150 words), then **Vote** (HD or AF), **Reasoning** (2-4 sentences), **Concern** (one sentence). If a point is only wording, say so. Send team-lead "voted D" + your label. Do not message other seats.

- **Systems:**

> # [ticket] Phase D — Systems seat
>
> ## Rebuttal
> web's premise, "with no `header:`, the test has nothing to compare against", is false under landed
> §9.1 text (:166). Its own `pipe` example gives E0861 with no `header:` on the declaration. The runtime
> prologue and the other declarations' headers bring in libc prototypes (`strlen`, `pipe`, `write`).
> A headerless binding of a libc symbol is the common case, not the rare one. min's own concern names
> the gap that HD opens. On cost: HD and AF use the same cached canary, so the scope changes only
> whether the note prints. The noise worry (my Phase C concern) is about wording. One note per build,
> not one per declaration, keeps it small.
>
> ## Vote: AF
> **Reasoning:** The test checks every `@ffi` wrapper against whatever prototype the unit's headers
> give, so a dead pin can hide a fault in a binding with no `header:`. AF prints the note in exactly
> the builds where the test runs, and costs no more than HD. One rule ("the program has an `@ffi` fn")
> is easy to predict.
> **Concern:** If the stdlib's own `@ffi` fns count, every tcc build prints the note, and users learn
> to skip it.

- **Web/Scripting:**

> # [ticket] Phase D, Q3 — Web seat
>
> Rebuttal: none. My Phase C concern came true. The landed §9.1 text (:166) puts a binding with no `header:` in the test, and the `pipe` example shows it can give E0861. My HD reason was wrong.
>
> **Vote:** AF
> **Reasoning:** A headerless binding that a unit header declares (`pipe` through `unistd.h`) is checked on gcc and clang, and unchecked on tcc. HD would hide that gap. One rule, "the program has an `@ffi` fn", is easy to predict, and a user does not need to know which header governs which binding to understand it.
> **Concern:** The stdlib has `@ffi` fns, so the note shows on nearly every tcc build. To keep users reading it, the note must be one line and print once per build (wording, writer notes).

- **PLT:**

> # [ticket] Phase D (Q3) — PLT seat
>
> ## Rebuttal
> To web: the premise "with no `header:` the test has nothing to compare against" goes against landed spec text (:166). A binding with no `header:` is in the test, and its `pipe` example gives E0861 through a header that another declaration names. web's own concern names this case. So HD hides the note in exactly the case where the check would have fired on gcc.
> To min: "smaller surface" is the same either way: one note, one condition. HD's condition is the harder one to predict, because whether a headerless binding is checked depends on which headers other declarations pull into the unit.
> To sys's concern: if the stdlib's `@ffi` fns put the note on almost every tcc build, that is correct. On almost every tcc build the test runs and cannot find a pointer fault. A true note that shows every time is not noise; a false silence is.
>
> ## Vote: AF
> **Reasoning.** The note must track when the check is in force. Per §9.1 the check covers every `@ffi` wrapper the unit compiles, `header:` or not. So the condition for the note is the condition for the test: the program has an `@ffi` fn. HD makes the condition depend on a syntax feature that does not decide coverage, and that is unsound.
> **Concern.** The note shows on nearly every tcc build, so users may learn to skip it. That is a wording and placement risk (one line, after `built:`), not a reason to narrow the scope.

- **DevOps:**

> # [ticket] — DevOps, Phase D (Q3)
>
> ## Rebuttal
>
> web's reason for HD ("with no `header:`, the test has nothing to compare it against") goes against landed spec text. In the :166 example, `@ffi("pipe")` has no `header:` and still gives E0861 through `unistd.h`. web's own concern names this case. min's concern also names it (`pipe` through a prologue header). So under HD, the binding that the spec uses as its example goes unchecked on tcc and gets no note.
>
> sys's concern (the stdlib's `@ffi` fns make the note show on nearly every tcc build) does not change the vote. On tcc the note is then true on nearly every build. It shows once per build, never once per declaration, and as a note it does not fail `--strict`. A note that is always true on one host is not noise. It is the fact about that host.
>
> ## Vote: AF
>
> **Reasoning.** The test covers every `@ffi` wrapper, with or without `header:` (:166, landed). The note says that the test has no effect, so it must show whenever the test runs. AF is one rule that a user or a tool can predict from the source alone. HD makes the note depend on a detail that the spec says does not decide coverage.
>
> **Concern.** If the note shows on every tcc build because of stdlib bindings, users can learn to skip it. The writer should keep it to one line.

- **AI/ML:**

> # [ticket], Phase D (Q3): AI/ML seat
>
> ## Rebuttal
>
> web's HD argument rests on "with no `header:`, the test has nothing to compare against". The landed text at :166 and its `pipe` example say this is false: a headerless binding is checked through any header that the unit reads. web's own concern names this case. min's concern names it too (`pipe` through `unistd.h`). So both HD votes accept that HD hides a real gap on tcc.
>
> sys's concern (the stdlib's `@ffi` fns put the note on nearly every tcc build) is true, but those stdlib bindings also go unchecked on tcc, so the note is still true there. The note prints once per build, so the noise is bounded.
>
> ## Vote: AF
>
> **Reasoning.** A model trusts a green build without a note. The test runs for every `@ffi` wrapper, so a dead pin hides faults in all of them, headerless ones included. One rule ("the program has an `@ffi` fn") is also easier to learn from the spec than a rule that depends on which bindings name a header.
>
> **Concern.** On tcc the note shows on almost every build, because of the stdlib's own `@ffi` fns, and users may learn to skip it.

- **Minimalism:**

> # [ticket] — Min, Phase D (Q3)
>
> **Rebuttal (and a change):** The spec text at :166 settles the fact that my Phase C concern raised.
> A binding with no `header:` is in the test, and a unit header can govern it (the `pipe` example). So
> HD hides the note in a case where the test can find a real fault. web's premise ("nothing to compare
> it against") is false when any unit header declares the symbol. One open point on sys's concern:
> "the program has an `@ffi` fn" should count the program's own declarations, as the I0017 note
> already does ("the program's own `@ffi` declarations"), not the stdlib's. Otherwise the note shows
> on every tcc build. I think that scope is a writer point, but the panel should confirm it.
>
> **Vote:** AF
>
> **Reasoning:** HD rests on a premise the landed spec contradicts. With HD the note is false by
> omission for a headerless binding that a unit header governs. AF is one rule ("the program has an
> `@ffi` fn"), and it is easier to state and to predict than one that depends on which bindings name a
> header. The smaller rule is the better minimal choice here.
>
> **Concern:** If "the program" includes stdlib `@ffi` fns, the note shows on nearly every tcc build,
> and users learn to ignore it.

### Final Spec

The sections of the spec that this decision changed are §9.1 (*A header that does not compile alone*, *The prototype test*, *A C compiler that accepts a pointer type mismatch*, and the test order after *What the prototype test covers*), §6.7.3 and §8.10.5 (the E0863 row and bullet), and `ERROR_CATALOG.md` (the E0863 row).

```blink
@ffi("mylib", "mylib_get", header: "mylib.h")
@trusted(audit: "MYLIB-GET")
fn c_get() -> I32 ! ()
```

```
$ blink build main.bl
error[ForeignHeaderDidNotCompile] (E0863): header `mylib.h` does not compile with this C compiler (x86_64-linux-gnu)
  --> main.bl:1:1
  label on `header:`: this header
  note: the C compiler said (first 10 lines):
        mylib.h: In function 'mylib_peek':
        mylib.h:1:51: error: initialization of 'long int *' from incompatible pointer type 'int *' [-Wincompatible-pointer-types]
  help: point `header:` at a header of your own that declares only the symbols that you bind
  help: or remove `header:`; the call then uses the prototype of this declaration, and the compiler does not check it
$ echo $?
1
```

```
$ blink build main.bl        # the C compiler is tcc
note: this C compiler accepts a pointer type mismatch, so the prototype test cannot find a wrong pointer type in an `@ffi` declaration
built: build/main
$ echo $?
0
```
