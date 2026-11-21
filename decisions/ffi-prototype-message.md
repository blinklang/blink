[< All Decisions](../DECISIONS.md)

# What E0861 Prints, and When It Gives Help — Design Rationale

**Gap:** §9.1 said that the prototype test "reads only pass or fail", and its examples still printed C types as if the test had read them (`connect` takes `const struct sockaddr *`; `pipe` takes `int *`). A pass or fail probe cannot read a C type. The `connect` example also passes on glibc, because glibc declares the parameter as a transparent union. The help `Ptr[Void]` was true for `connect` and false for a function that takes exactly one struct type. The spec did not say what the message names for a wrong count, for several wrong slots, or for a by-value struct.

```blink
@ffi("pipe", header: "unistd.h")
@trusted(audit: "UNISTD-PIPE")
fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
```

Before this decision, the spec printed "`pipe` takes `int *`", a C spelling that no probe proved. After it, the message says "the header takes a pointer to `int`", and each fact comes from a probe that passed or failed.

This decision relates to [A `Ptr` at an `@ffi` Call](ffi-pointer-prototype.md), [The Header Governs the Prototype](ffi-header-governs-prototype.md) and [A Struct Mirror That Does Not Match Its C Struct](ffi-struct-layout-mismatch.md). The first gave the prototype test and the rule that it reads only pass or fail. The third split its probes for each mirror and each check, on the failure path only. E0861 does the same for each slot.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | What does E0861 print? | `A`: only what pass or fail probes proved (the failing slot, a proved scalar pointee), and a help only when a probe proves the fix. The spec lists each closed set of probe types, and nothing outside them is printed. The C side of the declaration comes from the declaration. | 6-0 |
| Q2 | The sign of a proved scalar pointee | `S2`: the classification ladder adds `-Werror=pointer-sign`, on the ladder only, so exactly one type passes. If none or two pass, the two-sign text. | 6-0 (Systems and Minimalism moved from `S1`) |
| Q3 | The mirror probe when `Ptr[Void]` could be the help | `R1`: probe the program's own `@ffi.struct` mirrors as a closed set. One passes: the help names it only. None passes, two pass, or the cap is passed: the two-way help. | 5-1 (Minimalism dissents for `R2`) |
| Q4 | Arity | `C1`: the exact count; a parameter to remove only when exactly one typed drop-one probe passes. | 6-0 (Minimalism moved from `C2`) |
| Q5 | Several failing slots | `E`: every failing slot in one E0861, one line and one secondary label for each. | 6-0 (Minimalism moved from `F`) |
| Q6 | A scalar slot that got a pointer | `N`: "the header takes a number; this declaration passes `FILE *`", no help. | 6-0 (PLT and AI/ML moved from `K`) |

The owner approved the tally on 2026-11-21. Phase B ran one round. Phase D did not run.

### Dissent

**Minimalism, Q3** voted `R2` (no mirror probe). The vote, verbatim:


> ## Q3: R2
> R1 rarely helps. If the program already had the right mirror, the author would almost always have used it. The two-way help already names the action. R2 has no probe set that grows with the program, so one rule covers every case.
> Concern: in the rare program that does hold the right mirror, R2 makes the user find it by hand, and a model may take the `Ptr[Void]` branch where the mirror would keep the check.

The panel chose `R1` (5-1). AI/ML's vote for `R1`, verbatim:


> ## Q3: R1
> Reasoning: a mirror the program already has, proved by a probe, gives the exact fix (`Ptr[TimeSpec]`) in one edit. It is the best help a model can get. The two-way help remains only for the case where no mirror passes, so `Ptr[Void]` is never the first thing a model sees when a proved fix exists. The set is closed and finite (the program's own mirrors), so nothing is guessed.
> Concern: a mirror can pass the probe because it has the right C tag while its fields are wrong. E0862 runs first and catches that, but the ballot should keep that order explicit. Without it, the help could point to a wrong mirror.

The spec keeps the mirror set closed and capped. Past the cap the help is the two-way help that `R2` would give.

### Position changes

Each change is quoted from the panelist's own file.

**Minimalism, round 1, from `M` to `A`:**


> ## I move from M to A
>
> My case for M was "the header side needs an unbounded guess list". For scalar pointees that is wrong: the C scalar types form a closed set of about 7 (sign folds under the pins, as sys, web and aiml all checked). A closed set of fixed probe texts is not a guess. It proves facts, and it gives two things M cannot:
> - the real fix for pipe (`Ptr[I32]`), so the help gives a fix and not only "compare";
> - an honest gate for `Ptr[Void]` (a pointer slot, with no scalar pointee passing), which answers Q3 with proof, not with a rule that the test cannot decide.
>
> The cost is only on the failure path, roughly 10 ms per probe, and the build has already failed. A smaller language surface does not mean a weaker error. Keep M only as the text for a slot where a ladder runs and proves nothing. Option G stays the fallback for probes that disagree (for example a by-value struct slot that `0` cannot erase), as web and aiml say.

**Systems, Q2, from `S1` to `S2`:**


> ## Q2: S2 (I move from S1)
> My S1 reason was that the probe flags must not drift from the unit's flags. That holds for the verdict probe and the slot probes, which decide whether there is an error and where. The pointee ladder only classifies a slot that has already failed under the unit's flags. So adding `-Werror=pointer-sign` to the ladder cannot create an error or move one. gcc, clang and zig cc all have `-Wpointer-sign` with the same semantics. Exactly one type passes, and the help gives one exact fix.
> Concern: types whose sign the implementation chooses. An enum pointee is compatible with `unsigned int` or `int` depending on the compiler's choice of enum type, and plain `char` is its own type. The ladder must contain `char` and the enum case must give a deterministic result across gcc and clang. If it does not, the help names different types on different hosts.

**Minimalism, Q2, from `S1` to `S2`:**


> ## Q2: S2
> I objected to an extra flag because a split probe could then disagree with the verdict. That objection does not hold if the flag is only on the ladder: the slot is still found with the unit's flags, and `-Werror=pointer-sign` only picks which of the closed types passes. The result is one help line with one fix, not "I32 or U32", so the output is smaller.
> Concern: a supported compiler may put a char/signed char/unsigned char case or an enum pointee under some other warning, so that no type passes, or two do. The spec must say what prints then (fall back to the S1 two-sign text), and a gcc/clang/zig cc test row must pin the behavior.

**Minimalism, Q4, from `C2` to `C1`:**


> ## Q4: C1
> In round 1 my objection was to drop-one probes with `0` in every slot; those cannot tell which parameter is extra. Typed drop-one probes can: in `pipe(fds, flags)`, dropping `fds` puts an `int` in an `int *` slot and fails, and dropping `flags` passes. When exactly one probe passes, the help is proof, and in every other case there is no help.
> Concern: when two adjacent parameters have the same type, several drop-one probes pass, so no help shows. That is correct, but users may read the missing help as an inconsistency; the spec example should show that case.

**Minimalism, Q5, from `F` to `E`:**


> ## Q5: E
> Slot probes do not cascade (unlike E0862 offsets), and the P_i probes run anyway, so E reports what the test already knows and saves a rebuild cycle per extra bad slot. Only the ladders add cost, and only on failure.
> Concern: one wrong mirror type used in many bindings or slots gives a long report. The report needs a stable order (parameters left to right, then the result) so the output is byte-stable across runs and hosts.

**PLT, Q6, from `K` to `N`:**


> ## Q6: N
> The message already says "the header takes a number". A help line that repeats it in other words adds tokens and no new fact. No width can be proved, so a help that is more specific than the message is not available.
> Concern: a model may read "no help" as "no known fix" and reach for `Ptr[Void]`. A short note in `blink explain E0861` covers that.
>
> Letters: A S2 R1 C1 E N

**AI/ML, Q6, from `K` to `N`:**


> ## Q6: N
> Reasoning: I change from K. The message line already says "the header takes a number", which tells the model the fix. A help line that repeats it costs tokens, adds nothing, and makes the output look like it has more to say than it does. A rule I can defend: give help only when it adds a fact or an edit the message does not hold.
> Concern: a weak model may still try another `Ptr` type. With N it gets no fallback hint. The web note ("compare `n` with the prototype ...") can cover that.
>
> Votes: Q1 A, Q2 S2, Q3 R1, Q4 C1, Q5 E, Q6 N

### Writer notes

Notes from the Phase C votes, and where the spec meets them:

- The spec lists each closed set of probe types and says that nothing outside them is printed (Minimalism, PLT). §9.1 *The probes* does.
- The sign ladder falls back to the two-sign text when no type or two types pass. `-Werror=pointer-sign` is on the ladder only (Minimalism, Web/Scripting, AI/ML, DevOps, PLT). §9.1 *The probes*, step four.
- Two mirrors that pass give the two-way help. The mirror probe has a cap. E0862 runs first (Systems, PLT, Web/Scripting, DevOps, AI/ML). §9.1 *The help of `Ptr[Void]`*.
- The same-kind-neighbors arity case shows several drops that pass and no help (Minimalism, Web/Scripting, AI/ML, Systems, DevOps). §9.1 *The count*, the `dup2` example.
- A wrong by-value struct, and a binding that fails in every slot, give the fallback text (PLT, Web/Scripting). §9.1 *The fallback text*.
- Probes compile with `-c`, never `-fsyntax-only` (Systems). §9.1 *The prototype test*.
- The note "compare `<slot>` with the prototype" stays where no help applies (Web/Scripting). §9.1 *What a slot line says*.
- The message says "a pointer to `int`", not "takes `int *`" (AI/ML). §9.1 *What E0861 prints*.
- The output has a fixed order, and the probes can run in parallel (DevOps, Minimalism). §9.1 *What E0861 prints* and *The probes*.
- The `connect` example now has a target note (the verdict on glibc differs from musl and macOS), and the mirror examples use `nanosleep` (settled in round 1). §9.1 *The help of `Ptr[Void]`*.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path that the reply contains shows as `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals


- **Systems:**

> # [ticket] — Systems seat, Phase A
>
> ## Probe findings (gcc 16.2, clang 23.1, zig cc; probe dir probe/sys/)
>
> 1. **The connect example is false on glibc.** With `_GNU_SOURCE` (the spec's fixed glibc macro set), `connect` takes `__CONST_SOCKADDR_ARG`, a `__transparent_union__`. `connect(0, (struct sockaddr_in *)0, 0)` PASSES under gcc, clang and zig cc. It fails only with `_DEFAULT_SOURCE` alone (or on musl/macOS). The spelling "takes `const struct sockaddr *`" is also wrong for glibc: the parameter is a union.
> 2. Pointer sign is invisible: `pipe((unsigned *)0)` passes (gcc and clang put `-Wpointer-sign` outside `incompatible-pointer-types`). `pipe((long *)0)` fails. So a probe can prove "pointee is `int` or `unsigned int`", never which one.
> 3. A literal `0` passes for every scalar and every pointer parameter. A non-constant `void *v` passes only for a pointer (or transparent union); a non-constant `long x` passes only for a scalar. gcc and clang agree on every case I tried.
> 4. Cost: a `-fsyntax-only` probe with `unistd.h` takes ~7 ms. Ten failure-path probes cost less than one unit compile.
>
> ## Proposal S1 — print only what a probe proved; split on failure (E0862 model)
>
> **Q0:** Yes, change. Two of the three spelled header types (`const struct sockaddr *`, `char *`) cannot come from pass/fail without a guess, and one of them is false on glibc.
>
> **Q1: No.** The message never spells the header's type. A guessed spelling that is wrong (sign, const, union, typedef) is a false fact in an error, and gcc vs clang can differ on it. The message gives the header's *kind* for the failing slot, which fixed probes prove: `a pointer`, `a number`, `a struct by value`; for a pointer whose pointee probes to a fixed number-type list, `a pointer to a 32-bit integer` (etc.).
>
> **Q2: Yes.** Name the slot (`parameter 2 \`buf\``, `the result`, or the count). This is what makes the fix one edit.
>
> **Q3:** Help `Ptr[Void]` iff (declaration fact) the slot's pointee is an `@ffi.struct`/`@ffi.opaque` AND (probe) the header slot is a pointer AND (probe) no number-type pointee passes. Otherwise no `Ptr[Void]` help.
>
> **Probe plan.** Success path: unchanged, one probe per declaration. Failure path only, run in parallel, same flags and includes as the unit:
> - A (arity): call with N literal `0`s (by-value struct args kept as declared). Fail -> try counts 0..N+1 to find the one that passes.
> - P_i (slot): argument i as declared, every other argument `0`. One per parameter that is a `Ptr` or by-value struct (scalars cannot fail, §9.1.1).
> - R (result): `<declared C return> r = f(0, ...)`.
> - K (kind of a failing slot): `void *v` probe, `long x` probe; if pointer, one probe per C number type in a fixed list (char, short, int, long, long long, float, double).
> Report the first failing slot in order: arity, parameters left to right, result. Deterministic: every probe is a fixed text, so gcc/clang/zig cc see the same inputs.
>
> ### Outputs
>
> ```blink
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! ()
> // glibc: no error (transparent union). macOS/musl: P_2 fails, K: pointer, no number pointee
> //   error[ForeignPrototypeMismatch] (E0861): `connect` parameter 2 `addr`: the header takes a pointer to a different type; this declaration passes `struct sockaddr_in *`
> //   help: declare the parameter `addr: Ptr[Void]`. It takes a `Ptr` to any struct
> ```
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! ()
> // P_1 fails; K: pointer; `int *` probe passes
> //   `pipe` parameter 1 `fds`: the header takes a pointer to a 32-bit integer; this declaration passes `struct sockaddr_in *`
> //   help: declare the parameter `fds: Ptr[I32]` or `fds: Ptr[U32]`
> ```
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> @trusted(audit: "STRING-STRERROR-R")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: Int) -> I32 ! ()
> // R fails; K on the result (`void *r = f(...)` passes)
> //   `strerror_r` result: the header returns a pointer for this build; this declaration returns an integer
> //   help: declare the result `Ptr[U8]`        (the char-pointer probe passed)
> ```
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type CFile
>
> @ffi("fgets", header: "stdio.h")
> @trusted(audit: "STDIO-FGETS")
> fn c_fgets(buf: Ptr[U8], n: Ptr[CFile], stream: Ptr[CFile]) -> Ptr[U8] ! ()
> // only the 2nd is wrong. P_1, P_3, R pass; P_2 fails; K: `long x` passes -> number
> //   `fgets` parameter 2 `n`: the header takes a number; this declaration passes `FILE *`
> //   (no help: pointee is @ffi.opaque but the slot is not a pointer)
> ```
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[I32], extra: I32) -> I32 ! ()
> // A fails with 2 zeros; 1 zero passes
> //   `pipe` takes 1 parameter; this declaration has 2
> //   help: remove the parameter `extra`
> ```
> (For a variadic function more counts pass; the message then says "takes at least 1".)
>
> JSON: `slot` ("param"|"result"|"arity"), `index`, `name`, `header_kind`, `passes` (the C type).
>
> ### Tradeoffs
> - **Cost:** zero on success. Failure: ~3 + P + 9 probes at ~10 ms, parallel; dwarfed by the unit compile it replaces.
> - **One edit:** slot + kind is enough to act on; the header type is one `man` away. A wrong spelling sends a model down a wrong edit; a missing one does not.
> - **False help:** the help is gated on a proved pointer slot with a proved non-number pointee, which fixes the aiml "reflex `Ptr[Void]`" concern.
> - **Determinism:** no compiler text read; gcc's and clang's agreement on the two pinned groups carries over. Pointer sign stays unprovable, so the help names both signs.
>
> ## Q4
> No. The connect example must name a target where it fails (macOS or musl) or use a function whose struct pointer is not a glibc transparent union. Every message takes the slot-and-kind form and drops the spelled header type.
>
> ## Cross-language
> bindgen, Zig `@cImport` and Swift read the header through libclang, so they spell types, at the cost of a clang dependency. Go cgo learns kinds by compiling probes and parsing gcc's error text, and has broken on gcc message changes for years. Blink's pass/fail rule is the safer half of cgo's design; S1 keeps it and spends extra probes only on failure.

- **Web/Scripting:**

> # [ticket] Phase A — Web/Scripting seat
>
> ## Position
>
> Q0: yes, something must change. The spec's messages print a header type ("takes `const struct sockaddr *`") that no pass/fail test can learn. A JS/Python dev who reads that line trusts it. If the build can't prove it, we must not print it.
>
> My test for every line: can a dev or model fix the binding with **one edit** without opening the header? And nothing printed may be a guess.
>
> ## Proposal W1: split on failure, print only what the probes prove
>
> On the success path nothing changes: one compile per unit. Only after a FAIL does the test run small probes for that one declaration. Each probe uses the same compiler, flags and includes and reads only pass or fail. This matches the E0862 precedent (split per mirror, then per check).
>
> Probe kit (all checked on gcc 16 and clang. On zig cc the warnings match: sign is `-Wpointer-sign`, only a warning):
> 1. **Arity**: call with k literal `0` args, for k = n-1, n+1, then 0..n+1. `0` is a null pointer constant, so it fits any pointer or scalar slot. The k that passes is the header's count. If every k >= m passes, the function is variadic.
> 2. **Slot**: for slot i, pass a value of the declared C type in slot i and `0` in every other slot. Only the bad slot fails. For the return: `T r = f(0, ...)`.
> 3. **Shape** of a bad slot: does `(void *)0` pass? If yes, the header wants a pointer. If no, it wants a scalar.
> 4. **Scalar-pointee ladder** for a pointer slot: try `char *`, `short *`, `int *`, `long *`, `long long *`, `float *`, `double *`, `long double *`. Under the pinned flags, `int *` vs `unsigned int *` is only a warning, so the ladder folds sign. That's fine: §9.1.1 never checks a scalar pointee's sign or width anyway. If every rung fails, the header's pointee is a non-scalar named type (struct, pointer, function).
>
> Q1: no. The message names the header type only when the ladder proved it (a scalar pointee or a scalar return). Otherwise it says "a pointer to a different C type" and a note names the header file. The compiler knows the file name from `header:`.
> Q2: yes, always: the parameter's name and position, or "the result", or the count.
> Q3: show the help `Ptr[Void]` when two things hold: the declared pointee is `@ffi.struct`/`@ffi.opaque` (a fact of the declaration), and the probes prove that the header slot is a pointer and the ladder found no scalar. That is the spec's "pointer to a different named C type", now decided by probes. When the ladder finds a scalar, the help names the matching `Ptr[I32]`-style type, which is the real fix.
> Q4: rewrite both examples as below.
>
> ## The five cases
>
> ```blink
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! () {}
> // error[ForeignPrototypeMismatch] (E0861)
> //   `connect` takes a pointer to a different C type for parameter 2 `addr`; this declaration passes `struct sockaddr_in *`
> //   note: compare `addr` with the prototype of `connect` in `sys/socket.h`
> //   help: declare the parameter `addr: Ptr[Void]`. It takes a `Ptr` to any struct
> ```
> Probes: slot (only 2 fails), shape (pointer), ladder (all rungs fail) → Ptr[Void] help.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> //   `pipe` takes `int *` for parameter 1 `fds`; this declaration passes `struct sockaddr_in *`
> //   help: declare the parameter `fds: Ptr[I32]`
> ```
> Probes: shape (pointer), ladder (`int *` passes). No Ptr[Void]: the ladder proved a scalar pointee. The help gives the real fix, so models learn `Ptr[I32]`, not the `Ptr[Void]` reflex (the aiml concern).
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> @trusted(audit: "STRING-STRERROR-R")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: U64) -> I32 ! () {}
> //   `strerror_r` returns `char *` for this build; this declaration returns an integer
> //   help: declare the result `Ptr[U8]`
> ```
> Probes: return slot (`int r = ...` fails), shape (`void *r = ...` passes), ladder (`char *r` passes). This is the spec's message as written, and now it is provable.
>
> ```blink
> @ffi("getsockname", header: "sys/socket.h")
> @trusted(audit: "NET-GETSOCKNAME")
> fn c_getsockname(fd: I32, addr: Ptr[SockIn], len: Ptr[U32]) -> I32 ! () {}
> //   `getsockname` takes a pointer to a different C type for parameter 2 `addr`; this declaration passes `struct sockaddr_in *`
> //   note: compare `addr` with the prototype of `getsockname` in `sys/socket.h`
> //   help: declare the parameter `addr: Ptr[Void]`. It takes a `Ptr` to any struct
> ```
> Probes: slot (1 and 3 pass, 2 fails). One report per declaration, for the first bad slot in order (return last), the same as E0862's "first failing check".
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[I32], flags: I32) -> I32 ! () {}
> //   `pipe` takes 1 parameter; this declaration has 2
> //   note: compare each parameter with the prototype of `pipe` in `unistd.h`
> ```
> Probes: arity (k=1 passes, k=2 fails). No help: the probes can't tell which parameter is extra, and a guess ("remove `flags`") is false help. Arity is checked first, and the slot probes don't run when it fails.
>
> Fallback: a probe can't erase a by-value struct slot with `0`, so the probes may give no clean answer. Then the test prints the plain message "`f` does not match its prototype in `h.h`", the compare-note, and no help. It's honest, and it's rare.
>
> ## Tradeoffs
>
> - **Cost**: zero on a green build. A failing declaration costs about n+2 arity probes + n slot probes + up to 8 ladder probes. With each probe about 30 ms, that's well under a second, once, on a path that already stops the build.
> - **One-edit fix**: every case names the slot. Four of the five give the exact replacement.
> - **No false help**: Ptr[Void] shows only when probes prove a non-scalar pointee and the declaration names a struct. Its position and the header name are never guesses.
> - **Determinism**: each probe uses only the two pinned errors plus hard errors (arity). On gcc, clang and zig cc, sign is a warning, so the ladder's result matches on all three. Printing the signed spelling is fine, because sign is the author's claim (§9.1.1).
>
> ## Cross-language
>
> Go cgo and Zig @cImport read the header, so they print the C type for free. Blink chose pass/fail, and this design gets most of that clarity back by asking yes/no questions. Rust bindgen generates the binding, so the mismatch can't happen. Swift's ClangImporter is the same as Zig's. Python ctypes has no check at all and segfaults. That's the baseline a scripting dev knows, so even the fallback message beats it.

- **PLT:**

> # [ticket] Phase A — PLT seat
>
> ## Finding first: the connect example does not fire on glibc
>
> Probe (gcc 15 and clang, `-Werror=incompatible-pointer-types -Werror=int-conversion`, `_GNU_SOURCE`):
> `connect(0, (struct sockaddr_in *)0, 0)` PASSES. glibc declares
> `connect(int, __CONST_SOCKADDR_ARG, socklen_t)`, and `__CONST_SOCKADDR_ARG` is a
> `__transparent_union__` of every sockaddr pointer type. So on the feature macros §9.1 fixes for
> glibc, the §9.1 connect example gives no E0861, and its message ("takes `const struct sockaddr *`")
> names a type the header does not declare there. On macOS and musl it does fire. The spec must not
> show a target-dependent verdict as unconditional. That alone answers Q0: something must change.
>
> ## Principle
>
> A diagnostic is a claim. A claim the test cannot prove is unsound, and a model will learn the
> unsound claim as fact. So E0861 prints only facts that are (a) known from the declaration, or (b)
> proved by a pass/fail probe over a CLOSED candidate set. It never prints a guess. Extra probes run
> only after the one-probe verdict fails, so the success path costs one compile, as now.
>
> ## Proposal P1 — closed-set probes after failure (my pick)
>
> After the verdict probe fails, run these, each pass/fail, same compiler/target/includes/macros.
> Literal `0` is both a null pointer constant and an int, so it is a universal "erased" argument for
> any scalar or pointer parameter.
>
> 1. Arity: `f(0, …, 0)` with n zeros. Fail → try k = 0..n+1 zeros. Exactly one k passes → "takes k
>    arguments". (None passes → by-value struct or variadic; message says the call shape does not match.)
> 2. Locate: for each parameter i, the declared arg at i, `0` elsewhere. Return: `(void)f(0…)` passes
>    and `T r = f(0…)` fails → the return is wrong.
> 3. Classify a failing slot: `(void *)0` passes → header slot is a pointer (else a scalar).
>    Pointer: try `(T *)0` for each C arithmetic type T (15 types, closed set) with `-Werror=pointer-sign`
>    added — exactly one passes. Then each `@ffi.struct`/`@ffi.opaque` mirror of the program (closed).
>    Return: `void *r = f(…)` passes → returns a pointer.
>    Qualifiers are not probed, so the printed type has none.
>
> Help rule (Q3): a fact the test proves about the header, not the declaration alone.
> - slot is a pointer to arithmetic T → help names the Blink pointee (`int` → `Ptr[I32]`).
> - slot is a pointer to a mirror → help names that mirror.
> - slot is a pointer to none of those → help offers `Ptr[Void]`, or a mirror of the header's type.
> - slot is a scalar / return is a pointer → help names the kind (`Ptr[...]` / an integer).
>
> ### The five cases
>
> ```blink
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! ()
> // glibc: passes (transparent union). macOS/musl:
> //   `connect` parameter 2 (`addr`) takes a pointer to a C type that this program does not mirror;
> //   this declaration passes `struct sockaddr_in *`
> //   help: declare `addr: Ptr[Void]`, or mirror the header's type with @ffi.struct
> ```
> Probes: arity 1, locate 3, `void*` 1, arithmetic 15, mirrors 1 → about 21.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! ()
> //   `pipe` parameter 1 (`fds`) takes `int *`; this declaration passes `struct sockaddr_in *`
> //   help: declare `fds: Ptr[I32]`
> ```
> Verified: `(int *)0` passes, `(unsigned *)0` fails with pointer-sign, `(long *)0` fails.
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> @trusted(audit: "STRING-STRERROR-R")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: Int) -> I32 ! ()
> // glibc:
> //   `strerror_r` returns a pointer for this build; this declaration returns an integer
> //   help: declare the result as a `Ptr`
> ```
> The test cannot prove `char *` (pointee of a return is not probed: a scalar pointee crosses as
> `void *`, §9.1.1, so `Ptr[U8]` and `Ptr[Void]` give the same C). Verified: `int r = strerror_r(…)`
> fails, `void *r = …` passes on gcc and clang. The spec's "`char *`" and "`Ptr[U8]`" must change.
>
> ```blink
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "UNISTD-READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[SockIn], n: Int) -> Int ! ()
> //   `readlink` parameter 2 (`buf`) takes `char *`; this declaration passes `struct sockaddr_in *`
> //   help: declare `buf: Ptr[U8]`
> ```
>
> ```blink
> @ffi("getpid", header: "unistd.h")
> @trusted(audit: "UNISTD-GETPID")
> fn c_getpid(x: I32) -> I32 ! ()
> //   `getpid` takes 0 arguments; this declaration passes 1
> //   help: remove parameter `x`
> ```
>
> Several bad slots: one E0861 per declaration, one line per bad slot, in order (same shape as E0862's
> "one report per mirror").
>
> ## Proposal P2 — minimal fallback (if P1 cost is refused)
>
> No classification. Locate only (arity + n + return, n+2 probes). Message names the slot and the
> declaration's C type; no header type; help offers no type, it says "compare `addr` with the
> header's prototype". Sound, but the pipe/connect help split is lost, so `Ptr[Void]` is never offered
> (the aiml concern is met by omission).
>
> ## Answers
>
> - Q0: yes, change. The connect verdict is target-dependent, and `const struct sockaddr *`, `char *`
>   are unprovable. The "any means" reading fails: no pass/fail means names an open-set C type.
> - Q1: name the header type only when a closed-set probe proves it (arithmetic pointee, a mirror).
>   Otherwise name the class ("a pointer to a C type this program does not mirror", "a pointer").
> - Q2: yes, the slot by index and Blink name, or the return, or the arity.
> - Q3: a proved fact about the header slot (class from step 3), never the declaration alone: the
>   declaration alone cannot tell pipe from connect.
> - Q4: no. Rewrite connect (mark it macOS/musl, or use a function that is not a transparent union),
>   pipe (add slot + `Ptr[I32]` help), strerror_r (drop `char *`).
>
> ## Tradeoffs
>
> - Cost: success path unchanged (1 compile). Failure path ~20 small compiles, run in parallel; one
>   failing build, not every build.
> - Determinism: all three flags exist in gcc 13+ and clang/zig cc, with the same split
>   (int* vs long* = incompatible; int* vs unsigned* = pointer-sign). `char` vs `signed char` is
>   pointer-sign in both. Typedefs print as the base type (`size_t *` → `unsigned long *`), which is true.
> - One edit: every message names the slot and, where help exists, the exact edit.
>
> ## Cross-language
>
> bindgen and Zig `@cImport` read the header with libclang and can print any type, at the cost of a
> C front end in the tool. cgo reads gcc's DWARF output. Blink chose pass/fail; the sound answer under
> that choice is closed-set probing, the same move as E0862's per-check split.

- **DevOps/tooling:**

> # [ticket] Phase A: DevOps/tooling
>
> ## Two probe facts the panel must have (gcc 15, clang, zig cc 0.17.1, glibc, -c with the pinned flags)
>
> 1. **The connect example does not fail on glibc.** With `_GNU_SOURCE` (our fixed macro set), glibc declares `connect` with `__CONST_SOCKADDR_ARG`, a `__transparent_union__` that includes `struct sockaddr_in *`. `connect(0,(struct sockaddr_in*)0,0)` passes under all three compilers. Without `_GNU_SOURCE` it fails. So on glibc the spec example gives no error, and the header's type is not `const struct sockaddr *`. It fails on macOS.
> 2. **Signedness is invisible.** `pipe((unsigned*)0)` passes against `int *`; `unsigned char *r = strerror_r(...)` passes against `char *`. Only `-Wpointer-sign` sees it, and we do not pin it. `int *` vs `long *` fails.
>
> ## Proposal A (recommended): print only what a probe proved
>
> Q0: yes, change. Three example texts claim facts that no pass/fail result gives. Two of them (pipe, strerror_r) can be proven cheaply. The connect one cannot.
>
> **Probes.** On success, one compile per declaration, as now. Only on failure the test splits (E0862 precedent: same flags, same includes, pass/fail only, one compile each):
> - **Arity:** a call with N bare `0` arguments. If it fails, try N-1 and N+1; then try dropping each parameter in turn.
> - **Slot i:** the declared C type in slot i as a typed variable (never a literal, since `(int)0` is a null pointer constant). Every other slot gets `0`.
> - **Return:** `T r = f(0,...)` with the declared result type.
> - **Shape, for a failed slot:** a `void *` variable passes means the header takes a pointer. Then scalar candidates in a fixed order: `char`, `short`, `int`, `long`, `long long`, `float`, `double`. Stop at the first one that passes.
>
> Worst case is about N+10 tiny compiles, only on the error path. No text is read. The verdicts were the same on gcc, clang and zig cc.
>
> **Q1:** name the header's type only when a candidate proves it, and say "signed or unsigned". Never print a struct spelling: that needs a guess. **Q2:** yes. Name every failing slot (slot probes do not cascade, unlike E0862 offsets). Arity short-circuits. Primary span stays the `@ffi` line. Add a secondary label on each failing parameter, and give it as `related` in JSON (E0862 pattern). **Q3:** the help depends on three proven facts: the declared pointee is `@ffi.struct`/`@ffi.opaque`, the header slot is a pointer, and no scalar candidate passes. Even then the probe cannot tell "any sockaddr" (connect) from "exactly `struct timespec`" (nanosleep). So the help names the mirror first and `Ptr[Void]` second, with its condition.
>
> JSON adds `slot` (`param`|`return`|`arity`), `index`, `name`, `declared_c`, `header_shape` (`pointer`|`scalar`|`pointer_to_scalar`), `header_scalar` (when proven).
>
> ### The five cases
>
> ```blink
> @ffi("connect", header: "sys/socket.h")   // macOS target
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! () {}
> //   parameter 2 `addr` of `connect` does not match `sys/socket.h`: this declaration passes `struct sockaddr_in *`; the header takes a pointer to some other non-scalar type
> //   help: declare `addr: Ptr[T]` with the `@ffi.struct` that mirrors the header's type; if `connect` takes more than one struct type, declare `addr: Ptr[Void]`
> ```
> Probes: base, arity, 3 slots, `void *`, 7 candidates (all fail).
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> //   parameter 1 `fds` of `pipe` does not match `unistd.h`: the header takes a pointer to `int` (signed or unsigned); this declaration passes `struct sockaddr_in *`
> //   help: declare `fds: Ptr[I32]`
> ```
> The `int` candidate passes. Signed comes first by a fixed rule, because signedness is the author's claim (§9.1.1).
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: Int) -> I32 ! ()
> //   the result of `strerror_r` does not match `string.h` for this build: the header returns a pointer to `char` (signed or unsigned); this declaration returns an integer
> //   help: declare the result `Ptr[U8]`
> ```
> The return probe fails, `void *r` passes, and `char *r` passes.
>
> ```blink
> @ffi.opaque(header: "stdio.h", name: "FILE")
> type CFile
> @ffi("fgets", header: "stdio.h")
> fn c_fgets(buf: Ptr[U8], n: Ptr[SockIn], f: Ptr[CFile]) -> Ptr[U8] ! ()
> //   parameter 2 `n` of `fgets` does not match `stdio.h`: the header takes a scalar; this declaration passes `struct sockaddr_in *`
> //   help: declare `n` with the integer type that `stdio.h` gives
> ```
> Slots 1 and 3 pass, slot 2 fails, and `void *` fails, so the header takes a scalar. A scalar width is never checked, so the help names no width.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[I32], flags: I32) -> I32 ! () {}
> //   `pipe` takes 1 argument in `unistd.h`; this declaration passes 2
> //   help: remove the parameter `flags`
> ```
> The 2-arg call fails and the 1-arg call passes. Dropping `flags` passes and dropping `fds` fails, so the help names `flags`. If no single drop passes, or a by-value struct makes every `0` call fail, the message reads "the call with 2 arguments fails in every slot; check the count and any struct passed by value", with no help.
>
> **Q4:** the connect example must change. Move it to a macOS target, or use a binding that fails on glibc (nanosleep with `Ptr[TimeVal]`), and show the two-way help. Pipe and strerror_r keep their meaning, with the slot name added and "signed or unsigned".
>
> ## Proposal B (fallback): one probe, generic text
>
> There is no split. The message is "`connect` does not match its prototype in `sys/socket.h`", and the help says "compare each `Ptr`, by-value struct, the count and the result with the header". This is the cheapest option and never false. But a person or a model cannot act on it in one edit, which is what the web and aiml concerns ask for. I rank it below A.
>
> ## Tradeoffs
>
> - Cost: the success path is unchanged. The failure path takes at most ~20 compiles of one small file, which is under a second and can run in parallel.
> - Determinism: the verdicts came from the two pinned flags and were the same on three compilers. The candidate order is fixed, so the output is byte-stable.
> - False help: A never claims a struct name. Its remaining guess (connect vs nanosleep) is printed as a condition, not as the reflex fix.
>
> ## Cross-language
>
> bindgen and Zig `@cImport` parse the header with libclang, so they know the real type and there is no claim to check. cgo shows gcc's raw text, which Blink forbids. Swift's ClangImporter is like Zig. Proposal A gets the cgo verdict with Zig-grade slot naming and no text parsing.

- **AI/ML:**

> # aiml — Phase A, [ticket]
>
> ## Position
>
> Q0: change it. A model reads an error message as ground truth. If the message prints `const struct sockaddr *` and the test did not prove it, the model copies it into the next edit. Rule: **E0861 prints only facts that a pass/fail probe proved, or that the compiler knows from the declaration.** It names the parameter. It describes the header side as a *class* that bounded probes can prove, never as a guessed type spelling.
>
> ## Proposal AIML-1: "proved class" diagnosis, failure path only
>
> **Success path:** no change. One pass/fail probe for each declaration, as the spec has now. A build that passes pays nothing more.
>
> **Failure path:** the build fails anyway, so more probes cost little. Each probe uses the unit's flags and includes and reads only pass or fail. Run them in parallel, at most about N+15 compiles for each failing declaration:
>
> 1. **Arity.** Call with N args. Each arg is `0`, or `(struct T){0}` for a declared by-value struct. If that fails, try k = 0..N+4 args. The k that passes gives the header's arity. A variadic header passes for every k >= m.
> 2. **Which parameter.** Probe i passes the declared C type at position i and `0` at every other position. The first i that fails is the parameter the message names.
> 3. **Class of a failing parameter.** Pass `(void *)0`. If that passes, the header takes a pointer. If it fails, the header takes a scalar or a by-value struct. For a pointer, try `(T *)0` for each scalar family: char, short, int, long, long long, float, double, long double, _Bool. A pass names the family. If no family passes, the pointee is non-scalar: a struct, a union or a pointer.
> 4. **Return.** `(void)f(args)` passes, but `R r = f(args)` fails. Then `const void *r = f(args)` tells pointer from scalar, and `const T *r` gives the family. These targets must be const-qualified. My probe below shows why.
>
> Signedness merges into one family (`int`/`unsigned int`, the three chars). A sign mismatch is `-Wpointer-sign`, which no supported compiler makes an error. I checked gcc 16, clang 23 and zig cc: all three give the same verdict on each probe above. So the output is the same on every supported host.
>
> If the probes disagree (for example every single probe passes but the whole call fails), use the fallback message: "`f` does not match its prototype in `h.h`; compare each `Ptr` parameter, each by-value struct parameter and the result with the header". This is the Phase C ask.
>
> ### Cases
>
> ```blink
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! () {}
> //   `connect` parameter 2 `addr`: the header takes a pointer to a non-scalar C type, not `struct sockaddr_in *`
> //   help: declare `addr: Ptr[Void]`. It takes a `Ptr` to any struct
> //   note: the prototype is in `sys/socket.h`
> ```
> Probes: steps 1-3. `struct sockaddr_in *` comes from the declaration.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> //   `pipe` parameter 1 `fds`: the header takes a pointer to `int` or `unsigned int`, not `struct sockaddr_in *`
> //   help: declare `fds: Ptr[I32]` (or `Ptr[U32]`)
> ```
> Probes: steps 1-3. The `int *` family probe passes.
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> @trusted(audit: "STRING-STRERROR-R")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: Int) -> I32 ! ()
> //   `strerror_r` returns a pointer to `char` for this build; this declaration returns an integer
> //   help: declare the result `Ptr[U8]`
> ```
> Probes: step 4. `const char *r` passes.
>
> ```blink
> @ffi("f3", header: "h.h")      // int f3(int a, const struct sa *b, unsigned c)
> @trusted(audit: "H-F3")
> fn c_f3(a: I32, b: Ptr[SockIn], c: U32) -> I32 ! ()
> //   `f3` parameter 2 `b`: the header takes a pointer to a non-scalar C type, not `struct sockaddr_in *`
> //   help: declare `b: Ptr[Void]`. It takes a `Ptr` to any struct
> ```
> A secondary label marks `b`. JSON gives `param_index: 2`, `param_name: "b"`, `header_class: "ptr_nonscalar"` and `declared_c: "struct sockaddr_in *"`.
>
> ```blink
> @ffi("abs", header: "stdlib.h")
> @trusted(audit: "STDLIB-ABS")
> fn c_abs(x: I32, extra: I32) -> I32 ! ()
> //   `abs` takes 1 parameter for this build; this declaration has 2
> //   help: remove parameter `extra`
> ```
> Probes: the step 1 scan.
>
> ### Q3, when help offers Ptr[Void]
>
> All three must hold. Two are facts of the declaration and one is a probe result:
> - the declared pointee is an `@ffi.struct` or `@ffi.opaque` (declaration);
> - the header parameter is a pointer (the `void *` probe);
> - no scalar family passes (the family probes).
>
> The pipe case fails the third condition, so its help names a scalar `Ptr` and never `Ptr[Void]`. That stops models from learning `Ptr[Void]` as a reflex. One gap remains: a `struct x **` header parameter also lands in "non-scalar". `Ptr[Void]` compiles there and is a wrong claim. That is rare, and the `blink audit` inventory shows it.
>
> ## Tradeoffs (AI/ML)
>
> - **One-edit fix:** the message names the parameter, gives its span and gives a concrete help. A model edits one token. Today's spec examples also allow one edit, but on a type that was never proved. That is a lying-oracle risk: a model learns to trust text that an implementation cannot produce.
> - **Token cost:** each message is one line longer at most. The JSON fields let a tool skip parsing the text.
> - **No false help:** help needs proof. When the probes cannot prove a case, the fallback names no fix.
> - **Cost:** zero on success. On failure, ~N+15 compiles of a few ms each, run in parallel.
> - **The family probes cannot be dropped.** Only the family probes tell a scalar pointee from a non-scalar one, and Q3 depends on that. A smaller variant (AIML-1b) runs the probes but leaves the family name out of the message ("a pointer to a scalar C type"). It saves nothing in compiles. It costs the model the I32-vs-I64 hint.
>
> ## Answers
>
> Q0 yes. Q1 no: name the proved class, never a guessed spelling. Q2 yes: by index, name and span; for arity, the count. Q3 two declaration facts plus probe results, as above. Q4 the connect, pipe and strerror_r examples change to the forms above.
>
> ## Side finding (for the moderator, outside Q0-Q4)
>
> Header `const char *f(void)`, wrapper `void *r = f();` with the pinned flags: **gcc passes, clang and zig cc fail.** Clang puts discards-qualifiers under `-Wincompatible-pointer-types`. So "one source gives one verdict on every host" is false when a header returns `const T *` and the declaration returns a `Ptr`, unless the generated call casts or binds through `const`. This needs a codegen/spec chore whatever this ticket decides.
>
> ## Cross-language
>
> Rust bindgen, Zig `@cImport` and Swift read the clang AST, so they know the exact type and a mismatch cannot occur. Go cgo is the precedent for pass/fail: `cmd/cgo/gcc.go` classifies each name (type, constant, expression) with deliberate compile-error probes. Blink's split-and-classify follows that pattern, and E0862 already splits the same way.

- **Minimalism:**

> # [ticket] — Minimalism seat, Phase A
>
> ## Probe finding first (changes the connect example)
>
> Probe dir: scratchpad/[scratch path]/probe/min. `-fsyntax-only -Werror=incompatible-pointer-types -Werror=int-conversion`:
>
> | probe | gcc | clang | zig cc |
> |---|---|---|---|
> | `connect(0, (struct sockaddr_in *)a, 0)` with `-D_GNU_SOURCE -D_DEFAULT_SOURCE` | PASS | PASS | FAIL |
> | same, no feature macros | FAIL | FAIL | FAIL |
>
> glibc declares `connect` with `__CONST_SOCKADDR_ARG`, a `__transparent_union__`, when the compiler is GNU C. With the fixed glibc macro set (§9.1 *Feature macros*), **the spec's connect example gives no E0861 under gcc or clang**. It fires under `zig cc`. So the flagship example is wrong for the main host, and the verdict for one source differs between supported compilers. Whatever this panel picks, the connect example must change (Q4: no, it does not stay). Suggest `bind`/`connect` be replaced by a function with a plain named-struct pointer and no transparent union (for example `gettimeofday(struct timeval *, ...)` passed a `Ptr[Tm]`), and that the moderator logs the cross-compiler gap as its own ticket.
>
> Other probes (gcc, glibc): `void *p = strerror_r(0,0,0)` PASS; `long p = strerror_r(...)` FAIL; `connect(0,(void*)0,0)` PASS; `connect((void*)0,0,0)` FAIL; `connect(0,0,0,0)` FAIL; `connect(0,0,0)` PASS; `pipe((struct sockaddr_in*)a)` FAIL.
>
> ## Proposal M1 — say only what pass/fail can prove (recommended)
>
> Q0: yes, change. The messages at :76/:108 and the strerror_r line print the header's type. No pass/fail test can produce a C type name without a guess list, and a guess list is a C type printer by another name. Spec output that the test cannot honestly make is a spec bug, not a quality goal.
>
> **Facts the message may print, and their source:**
>
> 1. The declaration's C type for a parameter or result: from the compiler, no probe.
> 2. Which parameter, the result, or the count: failure-only split probes (E0862 precedent). Zero cost on success.
>    - P0 count: call with `0` for every non-struct argument, result discarded. FAIL means count (or a by-value struct; then P1 says which).
>    - P_i: the real argument at position i, `0` elsewhere. First FAIL names parameter i.
>    - P_r: `0` arguments, result stored in the declared C return type.
> 3. Pointer-or-scalar class of the header side: one more probe at the failing slot, `(void *)0` in (or `void *r = f(...)` out). PASS means the header has a pointer there. `0` and `void *` are the only C values that need no guess.
>
> Worst case N+3 compiles, only on a failing declaration. Same flags as the unit, so the split agrees with the verdict.
>
> **Q1:** no. **Q2:** yes. **Q3:** no `Ptr[Void]` in help at all. The help has one shape: compare the named slot with the header. `Ptr[Void]` moves to `blink explain E0861`, next to the sockaddr idiom. This answers the aiml concern (no reflex fix printed) and deletes the help-or-no-help rule at :156, which the test cannot decide anyway (connect and pipe give identical probe results).
>
> **Outputs:**
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> //   `pipe`: parameter `fds` does not match `unistd.h`; this declaration passes `struct sockaddr_in *`, the header takes another pointer type
> //   help: compare `fds` with the prototype of `pipe` in `unistd.h`
> ```
> Probes: full FAIL, P0 PASS, P1 FAIL, `(void *)0` PASS.
>
> The connect case (under zig cc, or a replacement example) prints the same two lines with `addr`. Same probes, same output. That is the point: the test cannot tell it from pipe, so it does not pretend to.
>
> ```blink
> @ffi("strerror_r", header: "string.h")
> @trusted(audit: "STRING-STRERROR-R")
> fn c_strerror_r(e: I32, buf: Ptr[U8], n: Int) -> I32 ! ()
> //   `strerror_r`: the result does not match `string.h` for this build; this declaration returns `int32_t`, the header returns a pointer
> //   help: compare the result with the prototype of `strerror_r` in `string.h`
> ```
> Probes: P0 PASS, P1..P3 PASS, P_r FAIL, `void *r` PASS. "Returns a pointer" is enough for `Ptr[U8]` in one edit.
>
> ```blink
> @ffi("frob", header: "frob.h")      // int frob(int a, struct frob_ctx *c, size_t n)
> @trusted(audit: "FROB")
> fn c_frob(a: I32, c: Ptr[Other], n: Int) -> I32 ! ()
> //   `frob`: parameter `c` does not match `frob.h`; this declaration passes `struct other *`, the header takes another pointer type
> //   help: compare `c` with the prototype of `frob` in `frob.h`
> ```
> Probes: P0 PASS, P1 PASS, P2 FAIL (stop), `(void *)0` at 2 PASS.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> @trusted(audit: "UNISTD-PIPE")
> fn c_pipe(fds: Ptr[I32], extra: I32) -> I32 ! ()
> //   `pipe`: this declaration has 2 parameters; `unistd.h` declares another count
> //   help: compare the parameters with the prototype of `pipe` in `unistd.h`
> ```
> Probes: P0 FAIL. (C rejects too many and too few arguments to a prototyped function on all three compilers.) Exact count is not printed: finding it needs a probe per count, and "another count" plus the header name is one edit.
>
> JSON: `slot: "param" | "result" | "count"`, `index`, `name`, `decl_c_type`, `header_kind: "pointer" | "scalar" | null`. No `header_c_type` field.
>
> ## Proposal M2 — M1 with conditional help (fallback if the panel keeps `Ptr[Void]` in help)
>
> Same message. Help when the failing slot is a `Ptr` to an `@ffi.struct`/`@ffi.opaque` and the header side is a pointer: "compare `addr` with the header; if it takes a pointer to a different struct, declare `addr: Ptr[Void]`". A fact of the declaration plus one probe, no header knowledge. Cost: the pipe case also gets the conditional `Ptr[Void]` line. The "if" keeps it honest, but it is the reflex aiml warned about. I prefer M1.
>
> ## Rejected: do nothing (Q0 "no")
>
> Keeping :76/:108 forces a guess list (try `int *`, `const struct sockaddr *`, ...) or reading C diagnostics. The first is unbounded and grows forever; the second is decided out. "Free to find them by any means" is a promise with no means.
>
> ## Tradeoffs
>
> - Cost: success path unchanged (one compile). Failure path is bounded and linear in arity.
> - Act in one edit: slot name + header name + pointer/scalar class. A human or model opens the header at one parameter.
> - False help: none in M1; the help never claims a fix.
> - Determinism: every probe uses `0` or `void *`, which mean the same in gcc, clang and zig cc. The cross-compiler gap above is in the headers, not in the probes.
>
> Cross-language: cgo prints the C compiler's text (Go reads it; Blink decided not to). Zig `@cImport` and bindgen sidestep the question by generating the signature from the header, so there is no mismatch to explain. Swift's ClangImporter likewise. Blink chose hand-written claims, so it should report only what it can check: Go-style smallness, no type printer.

### Phase B — Debate (round 1)


The moderator's digest of Phase A, verbatim:

> # [ticket] — Phase B, round 1: deduped option-space (from Phase A, verbatim snippets)
>
> Full proposals: [scratch path]/<seat>-A.md (sys, web, plt, devops, aiml, min). Read the others before you reply.
>
> ## Points every seat proposed (no debate needed unless you object)
> - Q0: change. The success path stays one pass/fail probe per declaration.
> - On failure only, split probes (E0862 precedent), pass/fail only: arity, then each slot with `0` in the other slots, then the result, then a `void *` probe to tell pointer from scalar.
> - Q2: the message names the failing slot (parameter by name, or the result).
> - Never print a struct spelling that no probe proved.
> - Q4: the connect example must change. Probe fact (sys, plt, devops, min): with `_GNU_SOURCE`, glibc declares `connect` with a `__transparent_union__`, so `Ptr[SockIn]` passes on glibc (min reports zig cc differs).
>
> ## Options
>
> ### Option A — print what the probes proved, including a proved scalar pointee; Ptr[Void] help gated on proved facts
> Proposers: sys, web, plt, devops, aiml (variations below).
>
> sys:
> ```
> //   `pipe` parameter 1 `fds`: the header takes a pointer to a 32-bit integer; this declaration passes `struct sockaddr_in *`
> //   help: declare the parameter `fds: Ptr[I32]` or `fds: Ptr[U32]`
> ```
> web:
> ```
> //   `pipe` takes `int *` for parameter 1 `fds`; this declaration passes `struct sockaddr_in *`
> //   help: declare the parameter `fds: Ptr[I32]`
> ```
> devops:
> ```
> //   parameter 2 `addr` of `connect` does not match `sys/socket.h`: this declaration passes `struct sockaddr_in *`; the header takes a pointer to some other non-scalar type
> //   help: declare `addr: Ptr[T]` with the `@ffi.struct` that mirrors the header's type; if `connect` takes more than one struct type, declare `addr: Ptr[Void]`
> ```
> aiml:
> ```
> //   `connect` parameter 2 `addr`: the header takes a pointer to a non-scalar C type, not `struct sockaddr_in *`
> //   help: declare `addr: Ptr[Void]`. It takes a `Ptr` to any struct
> ```
>
> ### Option M — name the slot and its kind only; help always "compare"; no Ptr[Void] in help
> Proposer: min (M1; recommended by min).
> ```
> //   `pipe`: parameter `fds` does not match `unistd.h`; this declaration passes `struct sockaddr_in *`, the header takes another pointer type
> //   help: compare `fds` with the prototype of `pipe` in `unistd.h`
> //   `pipe`: this declaration has 2 parameters; `unistd.h` declares another count
> //   help: compare the parameters with the prototype of `pipe` in `unistd.h`
> ```
> min M2 (fallback variant): the same, plus a conditional help line "if it takes a pointer to a different struct, declare Ptr[Void]". Ptr[Void] otherwise moves to `blink explain E0861`.
>
> ### Option G — no split; one generic message
> Proposer: devops (fallback B, ranked below A). aiml, plt and web give a similar text as the fallback when probes disagree.
> ```
> //   `connect` does not match its prototype in `sys/socket.h`
> //   help: compare each `Ptr`, by-value struct, the count and the result with the header
> ```
>
> ## Variations inside Option A (and across options) to debate
> (a) **Proved scalar pointee: print a C type or a kind?**
>  - type: web `takes \`int *\``, plt `takes \`int *\``, devops `a pointer to \`int\` (signed or unsigned)`, aiml `a pointer to \`int\` or \`unsigned int\``
>  - kind: sys `a pointer to a 32-bit integer`; min `another pointer type` (Option M)
> (b) **When does help offer Ptr[Void]?**
>  - three proved facts (pointee is @ffi.struct/opaque; slot is a pointer; no scalar pointee passes): sys, web, plt, devops, aiml
>  - mirror first, Ptr[Void] second with its condition: devops (`declare \`addr: Ptr[T]\` with the \`@ffi.struct\` ...; if \`connect\` takes more than one struct type, declare \`addr: Ptr[Void]\``), plt (`declare \`addr: Ptr[Void]\`, or mirror the header's type with @ffi.struct`)
>  - Ptr[Void] alone: sys, web, aiml (`help: declare \`addr: Ptr[Void]\`. It takes a \`Ptr\` to any struct`)
>  - never in help: min M1; conditional text: min M2
> (c) **Arity message and help**
>  - exact count + help naming the parameter: sys/aiml `takes 1 parameter; this declaration has 2` + `help: remove the parameter \`extra\``; plt `takes 0 arguments`; devops (drop-each probe proves which one; else "fails in every slot; check the count and any struct passed by value", no help)
>  - exact count, no help: web (`note: compare each parameter with the prototype of \`pipe\` in \`unistd.h\``)
>  - no count: min (`declares another count`)
> (d) **How many slots per report**
>  - every failing slot, one E0861 per declaration with one line (or secondary label + JSON related) per slot: plt, devops
>  - first failing slot: aiml ("The first i that fails is the parameter the message names"); sys/web — state yours
> (e) **strerror_r result text**
>  - `returns \`char *\``: web; devops/aiml `returns a pointer to \`char\`` (devops adds "(signed or unsigned)")
>  - `returns a pointer`: sys (help still `Ptr[U8]` because the char-pointer probe passed), plt (help `declare the result as a \`Ptr\``), min (help "compare")
>  - aiml: return probes must bind through `const` (`const void *r`, `const T *r`) — see side finding
> (f) **Sign of a proved pointee**
>  - fold it (no extra flag): sys (offers I32 or U32), devops, aiml, web
>  - add `-Werror=pointer-sign` to the split probes so sign is proved: plt
> (g) **Help text for a scalar slot (3-param case, 2nd wrong, header takes a number)**
>  - no help: sys (`(no help: pointee is @ffi.opaque but the slot is not a pointer)`)
>  - help without a width: devops (`help: declare \`n\` with the integer type that \`stdio.h\` gives`)
>
> ## Side finding (aiml, for the record; a follow-up ticket, not a ballot item)
> Header `const char *f(void)`, wrapper `void *r = f();` under the pins: gcc passes, clang and zig cc fail. So one source can get two verdicts on two hosts when a header returns `const T *` and the declaration returns a `Ptr`.
>
> ## Your reply
> Write to [scratch path]/<seat>-B1.md (S = [scratch path]): your position on Options A/M/G and on each of (a)-(g), with reasons in your domain. Phrasing disputes go to writer notes; argue behavior (what the output contains, which probes run). Then reply to team-lead "written", and say "stable, ready to vote" if you are.

- **Systems:**

> # [ticket] — Systems seat, Phase B round 1
>
> ## A correction for the record: zig cc agrees on connect
>
> min reports that zig cc FAILS `connect(0, (struct sockaddr_in *)0, 0)` under `_GNU_SOURCE`. I re-ran it with zig 0.17.1:
> - `zig cc -c -o x.o ...` PASSES, the same as gcc and clang.
> - `zig cc -fsyntax-only ...` "fails" with `error: failed to rename 'tmp/...-g.o' ... FileNotFound` at 1:1. That is a known zig driver bug with `-fsyntax-only`, not a verdict on the code.
>
> So all three compilers agree: connect passes on glibc. It is not a cross-compiler gap. **Behavior consequence:** a probe must compile with `-c -o <tmp>.o`, never `-fsyntax-only`, or zig cc gives a false FAIL on every probe. A false FAIL on the verdict probe is a false E0861. I ask the writer to put "-c, not -fsyntax-only" in the implementation note.
>
> ## Options
>
> **Option A: yes.** **M: no.** **G: no**, except as the text for "the split probes do not reproduce the verdict" (see below).
>
> Against M: the scalar-pointee ladder is not "a type printer by another name". It is a fixed list from the C standard (char, short, int, long, long long, float, double, long double), and it does not grow. It costs about 8 probes of ~10 ms each, and only on the failure path. "Compare with the header" makes every human and every model open the header for a fact that the build could prove in 80 ms. The connect and pipe cases do NOT give the same probe results once the ladder runs: `int *` passes for pipe, and no rung passes for connect. So the help-or-no-help rule at :156 can be decided.
>
> ## (a) Proved scalar pointee: a C type, both signs
>
> I drop my "a pointer to a 32-bit integer". The probe proves compatibility with `int`, not a width, so "32-bit" claims something no probe tested. Take aiml/devops: "a pointer to `int` or `unsigned int`" (and for chars, "`char`, `signed char` or `unsigned char`"). For the C type spelling I prefer the aiml form, because it names both types and avoids the bare `int *` that web/plt print. A bare `int *` claims a sign that the test did not prove.
>
> ## (b) Ptr[Void] help: three proved facts, a mirror first
>
> devops is right that the probes cannot tell connect ("any sockaddr") from nanosleep ("exactly `struct timespec`"). Behavior:
> 1. Add plt's closed mirror probe: for each `@ffi.struct`/`@ffi.opaque` mirror in the program, try `(T *)0`. If exactly one passes, the help names that mirror: `declare addr: Ptr[SockAddr]`. It is proved and it is the precise fix.
> 2. If no mirror passes, and the three facts hold, the help gives both fixes, mirror first: mirror the header's type with `@ffi.struct`, or `Ptr[Void]` if the function takes more than one struct type.
> 3. If any fact fails, there is no `Ptr[Void]` help.
>
> This answers aiml's reflex concern: `Ptr[Void]` is never the only fix offered.
>
> ## (c) Arity: exact count; help names the parameter only when proved
>
> Use k = 0..n+1 zero-argument probes. If exactly one k passes, print "takes k". If every k >= m passes (the function is variadic), print "takes at least m". If none passes, a by-value struct is the cause, so fall through to the slot probes. The help "remove the parameter `extra`" appears only when a drop-each probe (declared args with arg j removed) passes for exactly one j. Otherwise there is no help. That is n more probes, on the failure path only.
>
> ## (d) Every failing slot
>
> Change from my Phase A "first slot". The slot probes zero the other slots, so they do not cascade, and they all run anyway. Report every failing slot in one E0861 per declaration: a secondary label on each, with `related` in JSON (the E0862 pattern). It costs nothing more, and a second build to find the second error costs a full unit compile.
>
> ## (e) strerror_r: "returns a pointer to `char` (or `signed char`/`unsigned char`)"; help `Ptr[U8]`
>
> The result probes bind through `const` (aiml): `const void *r`, then `const T *r` for each rung of the ladder. That gives the same verdict on gcc, clang and zig cc.
>
> ## (f) Fold sign
>
> Do not add `-Werror=pointer-sign`. The split probes must use the unit's flags exactly. If they use other flags, a split can reach a verdict that the verdict probe did not. §9.1.1 makes sign the author's claim anyway.
>
> ## (g) Scalar slot: "takes a number", no help
>
> A non-constant `double` passes to an `int` parameter (implicit conversion, no error under the pins), so int and float cannot be told apart. The message says "the header takes a number; this declaration passes `FILE *`". A help line without a type ("declare it with the integer type the header gives") adds no fact, so I give none.
>
> ## Splits that disagree with the verdict
>
> If the verdict fails but every split probe passes, print the Option G text ("does not match its prototype in `<header>`"; help: compare each `Ptr`, by-value struct, the count and the result). That is deterministic, and it never names a wrong slot.
>
> ## Side finding (const return): a determinism bug that matters now
>
> `void *r = f()` against `const char *f(void)` passes on gcc and fails on clang/zig. That breaks "one source gives one verdict on every host" for the verdict probe and for the unit compile itself, not only for the split. It needs a ticket now (the wrapper must bind through `const` or cast), not later.
>
> Stable, ready to vote: A with (a) both-sign C type, (b) mirror probe, then mirror first, then conditional Ptr[Void], (c) exact count with proved-only help, (d) all slots, (e) const-bound result probes, (f) fold, (g) no help; G text for split/verdict disagreement.

- **Web/Scripting:**

> # [ticket] Phase B1 — web
>
> ## Options
> **A.** M and G fail the one-edit test. Take pipe: the probes already proved `int`, and M1 still says "another pointer type, compare". That sends a JS/Python dev into `/usr/include` to rediscover a fact we threw away. G is worse. Asking 10-20 yes/no questions on the error path costs nothing on a green build. If we spend those probes, we print what they proved.
>
> M is right on one point, and A must keep it: never print what no probe proved. Every A variant does that.
>
> ## (a) Proved scalar pointee: type or kind
> **Print the C type.** I changed my mind on how: use plt's (f) so the type is exact (see (f)). Then the message says `int *` and nothing else. A scripting dev reads `int *` faster than "a pointer to a 32-bit integer". The help line converts it to Blink (`Ptr[I32]`) anyway. A kind phrase makes the reader do a mapping that the help line already does.
>
> ## (b) When help offers Ptr[Void]
> Keep the three proved facts as the gate. **Change the help text to the devops/plt form: the mirror first, Ptr[Void] second.**
>
> devops's nanosleep point moved me. `nanosleep(const struct timespec *, ...)` passed a `Ptr[SockIn]` gives the same three facts as connect. For nanosleep, Ptr[Void] is the wrong fix: it compiles and drops the check. A help that is false in half the cases where it shows is the reflex aiml warned about. Two clauses in one help line are fine if the first one is the usual fix:
> ```
> //   help: declare `req: Ptr[T]` with an `@ffi.struct` that mirrors the header's type; if `nanosleep` takes more than one struct type here, declare `req: Ptr[Void]`
> ```
> Phrasing goes to the writer. The behavior: the mirror comes first, Ptr[Void] is conditional, and Ptr[Void] never shows when a scalar or a non-pointer was proved.
>
> ## (c) Arity
> - Print the exact count; the arity probes prove it.
> - Help naming the parameter (devops drop-each): **yes, but only when exactly one drop passes.** A drop leaves the other slots with their declared-type values, not all `0`. With all `0`, every drop gives the same call. In pipe, `fds` is a pointer and `flags` an int, so only dropping `flags` passes, and "remove the parameter `flags`" is proved.
> - When two drops pass (two adjacent scalars), or a by-value struct blocks the `0` calls: give the count, then the compare note, and no help.
>
> This beats my A text (always no help), and it guesses nothing.
>
> ## (d) Slots per report
> **Every failing slot**, as plt and devops propose. I'm dropping my "first slot" position. The slot probes are independent (each erases the others), so they don't cascade the way E0862's offsets do. Reporting all of them lets the user or model fix the binding in one pass instead of one build per slot. One E0861 per declaration, one line per bad slot, and a secondary label plus JSON `related` on each parameter (E0862 pattern). Arity still short-circuits.
>
> ## (e) strerror_r result
> `returns \`char *\`` with help `Ptr[U8]`. With (f), the char rung is exact. Adopt aiml's rule: return probes bind through `const` (`const void *r`, `const char *r`), so gcc and clang agree on a `const T *` return. The message then prints `const char *` only if a non-const bind fails and the const bind passes. That needs one extra probe, and only on this path.
>
> ## (f) Sign
> **Add `-Werror=pointer-sign` to the split probes only** (plt). I checked it in probe/web with `-c -o /dev/null` on gcc 16, clang and zig cc:
> - `unsigned int *` → `int *` param: FAIL on all three
> - `int *` → `int *`: PASS on all three
> - `signed char *` and `unsigned char *` → `char *`: FAIL on all three; `char *` → `char *`: PASS
>
> So the ladder becomes exact: char, signed char and unsigned char are separate rungs, plus each integer in both signs. That's about 15 rungs, still only on the error path. The main test keeps its two pins, so the verdict is unchanged. Payoff: one type in the message and one fix in the help. Without the flag we'd print "`Ptr[I32]` or `Ptr[U32]`", and that is the guess we said we would not make (socklen_t is unsigned).
>
> ## (g) Scalar slot, header takes a number
> - An integer of another width converts silently, so the probes cannot prove a scalar slot's width.
> - So the message is "the header takes a number, not a pointer; this declaration passes `struct X *`". The help names no type; it is the compare note. Don't use devops's "the integer type that `stdio.h` gives" as a help line, because it is not one edit. Keep it as a note.
>
> ## Q4
> The connect example changes. On glibc with `_GNU_SOURCE` it is a transparent union, and it passes on gcc and clang. Replace it with nanosleep (or gettimeofday). That also shows the mirror-first help. The zig-vs-gcc split on transparent unions, and aiml's `const` return split, each go on a ticket of their own.
>
> Stable, ready to vote: A with (a) type, (b) mirror first + Ptr[Void] conditional, (c) count + proved-drop help, (d) every slot, (e) `char *` with const bind, (f) pointer-sign in split probes, (g) no type help for a scalar slot.

- **PLT:**

> # [ticket] Phase B1 — PLT seat
>
> ## A fact to settle first: zig cc and connect
>
> min reports zig cc FAILS connect on glibc. I re-ran it with `-c -o x.o` instead of
> `-fsyntax-only`, because zig's `-fsyntax-only` reports a false FileNotFound failure at 1:1:
> - `zig cc` (native glibc target), pinned flags, `_GNU_SOURCE`: PASS
> - `zig cc -target x86_64-linux-gnu`: PASS
> - `zig cc -target x86_64-linux-musl`: FAIL (plain `const struct sockaddr *`)
>
> So the verdict depends on the libc of the TARGET, not the compiler. That agrees with sys and
> devops, and it keeps "one source, one verdict per target". I think min's zig row is the
> `-fsyntax-only` artefact. If min has a FAIL from `-c`, that is a real determinism bug and gets its
> own ticket. Either way the connect example names its target.
>
> ## Option: A
>
> M is sound but discards proofs the test can make for a few ms on a path that already stops the
> build. Not printing a proved fact is not "more correct". It only means a less useful oracle. G
> is the fallback when the split cannot decide (a by-value struct makes every `0` call fail, or the
> probes disagree). It is not a design of its own.
>
> The sound core every A-variant must keep: **each printed fact is (i) from the declaration, or
> (ii) the single survivor of a closed candidate set under a fixed probe.** No open-set spelling
> (no struct names, no typedef names, no qualifiers unless probed).
>
> ## (a) Proved scalar pointee: type or kind
>
> Type, but only as precise as the probe proved it. Printing `int *` after a probe that cannot tell
> `int` from `unsigned int` (web) is unsound: it states a sign the test did not prove. Either fold
> it in the text ("`int` or `unsigned int`", aiml/devops) or prove it (f). sys's "32-bit integer"
> is also sound, but it loses `int` vs `long` on ILP32 targets, and `float` vs `int` (both 32-bit).
> The C family name is the precise fact.
>
> ## (b) When help offers Ptr[Void]
>
> Three proved facts (declared pointee is a mirror; slot is a pointer; no scalar family passes).
> Then name the mirror first and `Ptr[Void]` second, with its condition (devops/plt). Reason: the
> probes cannot tell connect (any sockaddr) from nanosleep (exactly `struct timespec`), and
> `Ptr[Void]` alone is false help for the second. aiml also notes the third case, `struct x **`.
> Whatever the wording, the help must not present `Ptr[Void]` as THE fix when the evidence also
> fits "mirror the right struct".
>
> Add a fourth candidate set: the program's own mirrors (`(struct M *)0` for each
> `@ffi.struct`/`@ffi.opaque` in the unit). The set is closed and usually small. If exactly one
> passes, the help names it ("declare `addr: Ptr[TimeSpec]`"), and that is a one-edit fix with no
> guess. It costs nothing on success.
>
> ## (c) Arity
>
> Exact count when exactly one k in 0..N+1 passes, "at least m" when every k >= m passes
> (variadic). Help naming the parameter only when devops's drop-each probe proves it (exactly one
> drop passes). Without that probe, "remove `extra`" is a guess (the extra one may be the first).
> web's no-help is correct when the drop probe is not run. I adopt devops's drop-each.
>
> ## (d) Slots per report
>
> Every failing slot. Slot probes are independent by construction (every other slot erased to
> `0`), so unlike E0862 offsets they do not cascade. Reporting only the first hides a fact the test
> already holds, and costs a second build cycle. One E0861 per declaration, one line (plus a
> secondary label and JSON `related`) per bad slot, then the result. Arity short-circuits.
>
> ## (e) strerror_r result
>
> "returns a pointer to `char`" only if the family probe on the result ran and passed, bound
> through `const` (aiml's finding: clang rejects `void *r = (const char *)…`; my probe shape
> `void *r` was wrong for clang on a `const T *` return). Return probes use `const void *r` and
> `const T *r`. Help `Ptr[U8]` follows from `char`. I withdraw my "returns a pointer" text in favour
> of the proved family.
>
> ## (f) Sign
>
> My pick: add `-Werror=pointer-sign` to the CLASSIFICATION probes only. It does not touch the
> verdict (the pin stays), and only refines a fact after the verdict. Checked: gcc, clang and zig cc
> all honour it the same way (`int *` vs `unsigned *` fails in all three). Gain: exact family
> (`int` vs `unsigned int`; `char` vs `signed char` vs `unsigned char`), so the help names one type,
> not "I32 or U32". If the panel wants the classification flags equal to the pin, fold the sign and
> say so in the text. Both are sound. Printing an unproved sign is not.
>
> ## (g) Scalar slot help
>
> devops: help without a width ("declare `n` with the integer type the header gives"). The test
> never checks a width (§9.1.1), so naming one would be a guess. A help that says "a number, not a
> `Ptr`" is an exact one-kind edit. sys's no-help is also fine. I mildly prefer the kind help.
>
> ## Side finding (aiml const return)
>
> Agree it needs its own ticket: under the pins, one source gives gcc PASS and clang FAIL for a
> `const T *` return into `void *`. That breaks the pin's stated promise. The fix is in codegen
> (bind through `const void *`, or cast), not here.
>
> stable, ready to vote.

- **DevOps/tooling:**

> # [ticket] Phase B1: DevOps/tooling
>
> ## Two probe corrections (probe/devops, gcc, clang, zig cc 0.17.1; each compile is `-c -o x.o`)
>
> 1. **The connect example passes on zig cc too, not only gcc and clang.** Min reports that zig cc fails it. That result is a tool artifact. `zig cc -fsyntax-only` prints `error: failed to rename ... FileNotFound` at `1:1` for a clean file. With `-c -o x.o`, `connect(0,(struct sockaddr_in*)0,0)` under `_GNU_SOURCE` passes on all three compilers, so the three compilers agree here. Any panel probe made with zig `-fsyntax-only` should be run again with `-c`.
> 2. **`-Werror=pointer-sign` proves sign in the candidate probes, the same way on all three compilers.** `pipe((unsigned*)0)` fails and `(int*)0` passes. For `strerror_r`, `const char *r` passes, while `const unsigned char *r` and `const signed char *r` fail. aiml's const finding is real: header `const char *cf(void)` with `void *r = cf()` passes on gcc and fails on clang and zig cc, while `const void *r` passes on all three. So return probes must bind through `const`. That gives three compilers and one verdict.
>
> ## Options: A, then M2, then G, then M1
>
> A. Min calls a candidate list "a C type printer by another name". The scalar pointee set is closed: the C arithmetic types, about 15 with sign. It does not grow. The pay-off is the one-edit fix: "takes `int *`" plus `help: declare fds: Ptr[I32]` gives a human or model an edit with no header lookup. M1's "takes another pointer type" makes every user open the header, and the test has already proven the answer. The extra cost is ~15 compiles, only on the error path, and they can run in parallel.
>
> ## (a)–(g)
>
> **(a) Print the C type.** I adopt plt's (f). With `-Werror=pointer-sign` on the candidate probes, sign is proven, so the type is exact (`int *`, `char *`), and I drop my "(signed or unsigned)". The candidates use a fixed order and stop at the first pass, so the output is byte-stable.
>
> **(b) The mirror first, `Ptr[Void]` second, with its condition. `Ptr[Void]` alone is false help.** The proof is the replacement examples that seats propose (`nanosleep` with `Ptr[TimeVal]`, min's `gettimeofday` with `Ptr[Tm]`). Their probe results match connect exactly: slot is a pointer, no scalar candidate passes. In both, `Ptr[Void]` is the wrong fix. It removes the check, and the right fix is the `TimeSpec`/`TimeVal` mirror. A help that is wrong on the panel's own examples is the reflex aiml warned about. Gate: pointee is `@ffi.struct`/`@ffi.opaque`, slot is a pointer, no scalar candidate passes. I accept plt's shorter order ("declare `addr: Ptr[Void]`, or mirror the header's type with `@ffi.struct`") only if the mirror comes first.
>
> **(c) Give the exact count when a probe proves it, and name the parameter when a drop probe proves it.** Web objects that "remove `flags`" is a guess. It is not a guess: the drop-each probe compiles the call without `flags` with typed variables in the other slots, and that call passes, while the call without `fds` fails. The help names a parameter only when exactly one drop passes. Otherwise the message gives the count and has no help. If no count N±1 passes, the message says "another count" (min's text). The cost is N+2 compiles, only on an arity failure.
>
> **(d) Every failing slot, in one E0861 per declaration.** Slot probes are independent. One wrong slot does not move another, so E0862's cascade reason does not apply. First-fail costs the user one build per wrong slot, and each build reruns the header test and the slot probes. A model in an edit loop pays that again for each slot. Give one label per failing slot in order (parameters left to right, then the result), with the JSON `related` entries in the same order. Arity short-circuits: if the count is wrong, no slot probes run.
>
> **(e) "returns `char *`".** Use const-bound return probes (aiml) plus pointer-sign (plt). With them, `const char *r` passes and the other char types fail, as measured above. Help: "declare the result `Ptr[U8]`".
>
> **(f) Add `-Werror=pointer-sign` to the candidate probes only, never to the base probe or the unit.** The verdict stays the decided one. The extra flag only names the type after the verdict has failed.
>
> **(g) No help for a scalar slot. I concede to sys.** "Declare `n` with the integer type the header gives" adds nothing to the message "the header takes a scalar". A scalar width is never checked, so the probe cannot prove a better line. A help line that carries no fact is noise for a model.
>
> ## JSON (unchanged from A, plus sign)
>
> `slot`, `index`, `name`, `declared_c`, `header_shape` (`pointer`|`scalar`|`pointer_to_scalar`), `header_c` (present only when a candidate proved it, for example `"int *"`).
>
> ## Follow-ups (not ballot items)
> - aiml's const-return gap: the generated return in the unit must bind through `const`, or one source gets two verdicts. Same chore as aiml's.
> - Probe hygiene: zig `-fsyntax-only` gives a false FAIL. The implementation must compile with `-c` to a temporary object.
>
> Stable, ready to vote.

- **AI/ML:**

> # aiml — Phase B round 1, [ticket]
>
> ## Option: A. Against M and G.
>
> M1 gives the same output for connect and pipe, but the right fixes differ (`Ptr[Void]` or a mirror for connect, `Ptr[I32]` for pipe). Under M1 the model has to open the header, so each fix takes two turns. G is worse: no slot, so the model edits by guess. Both are honest, but A is honest too, and it gives the fix in one edit. M1 keeps `Ptr[Void]` out of the help to stop the reflex. A does that better: it names the proved scalar `Ptr` for pipe, so the model sees the right fix and does not learn to drop the help.
>
> ## (a) Proved scalar pointee: print the C type, with sign proved
>
> I now take plt's (f). Add `-Werror=pointer-sign` to the **diagnosis probes only**, never to the verdict probe or the unit, so the verdict does not change. I checked with the two pinned flags plus `-Werror=pointer-sign` on gcc 16, clang 23 and zig cc. All three agree:
>
> | probe | result |
> |---|---|
> | `int *` to `int *` | pass |
> | `unsigned *` to `int *` | fail |
> | `int *` to `unsigned *` | fail |
> | `signed char *` to `char *` | fail |
> | `unsigned char *` to `char *` | fail |
> | `char *` to `const char *` | pass |
> | `unsigned char *` to `const char *` | fail |
>
> So exactly one family member passes. The output then gives one help (`Ptr[I32]`), not two (`Ptr[I32]` or `Ptr[U32]`). Each fork in a help line is one more choice for the model, and one more way to pick wrong. Writer note: say "a pointer to `int`", not "takes `int *`". The probe does not see `const`, and "takes `int *`" would be false for a `const int *` parameter.
>
> ## (b) When help offers Ptr[Void]: mirror probe first, then two-way help
>
> devops is right that "pointer to non-scalar" does not tell connect (any sockaddr) from nanosleep (exactly `struct timespec`). For nanosleep, `Ptr[Void]` alone is false help. It compiles and throws away a type the header pins. So I drop "Ptr[Void] alone":
> 1. Use plt's closed mirror set. Probe `(struct M *)0` for each `@ffi.struct` and `@ffi.opaque` in the program. If exactly one passes, the help names it: `declare addr: Ptr[TimeSpec]`. That help is proved and is one edit.
> 2. If no mirror passes, and the three proved facts hold, use devops's two-way help: mirror first, then `Ptr[Void]` with its condition. That is one choice, but the header settles it, and the mirror comes first, so `Ptr[Void]` is not the default.
> 3. Otherwise, no `Ptr[Void]` in the help.
>
> ## (c) Arity: exact count, and name the extra parameter only when a drop probe proves it
>
> The help reads "remove `x`" only when exactly one drop-one probe passes. Those probes use typed arguments (devops), not `0`, because with `0` in every slot every drop passes. If two or more drops pass, or for too few parameters, print the count and the compare note, with no help. I withdraw my Phase A "remove `extra`" when nothing proves it (web's objection is right). A variadic header prints "takes at least m".
>
> ## (d) Report every failing slot: one E0861 per declaration, one line for each slot
>
> I change my Phase A "first slot" answer. With `0` in every other slot, the slot probes are independent, so one bad slot does not make another fail. A model that sees every bad slot fixes them all in one turn. With first-slot reporting it needs one build per slot. Each slot gets a secondary label, and each is a JSON `related` entry (devops/plt). A failed arity probe stops the run before the slot probes.
>
> ## (e) strerror_r: "returns a pointer to `char`", help `Ptr[U8]`
>
> The return probes bind through `const` (`const void *r`, `const char *r`). Without that, a `const char *` return gives gcc pass and clang fail (my side finding). With `const`, the result is the same on all three compilers, and `char` is proved (the table above). plt's objection is that `Ptr[U8]` and `Ptr[Void]` lower to the same C, so naming `char` adds nothing. I disagree: it decides the Blink type the model writes (`Ptr[U8]`, not `Ptr[I64]`), and the probe proves it.
>
> ## (f) Prove the sign. See (a).
>
> ## (g) Scalar slot: help names the kind, no width
>
> Help: "declare `n` as a number, not a `Ptr`". No probe can prove the width (int to double converts in silence), so the help does not print one. I would rather give this help than none, because it rules out the wrong edit (another `Ptr` type).
>
> ## Q4 and the connect example
>
> The connect example must move to a function with a plain named-struct pointer. nanosleep with a wrong mirror shows both the mirror probe and the help. Log the zig cc / transparent-union verdict gap (min) as a determinism ticket next to my `const` return finding. Both break "one source gives one verdict on every host".
>
> ## My five cases now (behavior)
>
> - **pipe**, `Ptr[SockIn]`: "`pipe` parameter 1 `fds`: the header takes a pointer to `int`; this declaration passes `struct sockaddr_in *`". Help: `declare fds: Ptr[I32]`.
> - **nanosleep**, `Ptr[TimeVal]` where the program also mirrors `TimeSpec`: "parameter 1 `req` ... a pointer to `struct timespec`". The mirror probe proves it. Help: `Ptr[TimeSpec]`.
> - **connect** on a target with no transparent union, no matching mirror: "a pointer to a C type this program does not mirror". Help: mirror it with `@ffi.struct`, or `Ptr[Void]` if the function takes more than one struct type.
> - **strerror_r**: "returns a pointer to `char` for this build; this declaration returns an integer". Help: `Ptr[U8]`.
> - **3 parameters, the 2nd wrong**: one line for the 2nd parameter only, with a label on it.
> - **arity**: "`pipe` takes 1 parameter; this declaration has 2". Help: `remove flags` (only `flags` passes the drop probe).
>
> Cost: still zero on success. On failure, about N+25 compiles (the mirror set adds M), each ~7 ms, run in parallel.
>
> Stable, ready to vote.

- **Minimalism:**

> # [ticket] — Minimalism, Phase B round 1
>
> ## Correction to my Phase A
>
> My "zig cc differs" fact was false. `zig cc -fsyntax-only` reports a FileNotFound error at 1:1 on a clean file (a zig 0.17.1 cache bug), and I read that as FAIL. With `-c -o t.o`: zig cc on x86_64-linux-gnu PASSES `connect(0, (struct sockaddr_in *)a, 0)` under `_GNU_SOURCE`, the same as gcc and clang. Only `-target x86_64-linux-musl` fails. So the verdict depends on the target libc, not on the compiler. Drop my "own ticket for the cross-compiler gap". The connect example still must change (sys is right: it holds on musl/macOS only).
>
> ## I move from M to A
>
> My case for M was "the header side needs an unbounded guess list". For scalar pointees that is wrong: the C scalar types form a closed set of about 7 (sign folds under the pins, as sys, web and aiml all checked). A closed set of fixed probe texts is not a guess. It proves facts, and it gives two things M cannot:
> - the real fix for pipe (`Ptr[I32]`), so the help gives a fix and not only "compare";
> - an honest gate for `Ptr[Void]` (a pointer slot, with no scalar pointee passing), which answers Q3 with proof, not with a rule that the test cannot decide.
>
> The cost is only on the failure path, roughly 10 ms per probe, and the build has already failed. A smaller language surface does not mean a weaker error. Keep M only as the text for a slot where a ladder runs and proves nothing. Option G stays the fallback for probes that disagree (for example a by-value struct slot that `0` cannot erase), as web and aiml say.
>
> ## Variations
>
> **(a) Kind in the message, Blink type in the help.** Print the proved family once, as a C kind with sign folded: "a pointer to `int` or `unsigned int`" (aiml) or "a pointer to a 32-bit integer" (sys). The writer picks the wording. Do not print a bare `int *`: the probes did not prove the sign. The actionable fact is the Blink type in the help (`fds: Ptr[I32]`), because a Blink user edits Blink.
>
> **(b) Gate Ptr[Void] on three proved facts (all five seats agree). Help: the mirror first, Ptr[Void] second, with its condition (devops/plt).** devops's nanosleep point settles it: the probes cannot tell "any sockaddr" (connect) from "exactly `struct timespec`". A bare `Ptr[Void]` help would throw away a check that a correct mirror keeps. That is the false-help reflex aiml warned about, aimed one level down. My M2 conditional text is the same idea.
>
> **(c) Arity: give the exact count. Give no help that names a parameter.** The count costs at most N+2 probes over a closed range (0..N+1). "Remove the parameter `extra`" is a guess: with `0` in every slot, dropping any one parameter gives the same count, so no probe shows which one is extra. I side with web: count yes, named removal no. For a variadic function, say "takes at least N".
>
> **(d) Report the first failing slot only.** This is the E0862 rule ("the first failing check"). It runs one ladder, not one ladder per bad slot, and gives one fact and one edit. Two wrong parameters cost one more build, and that build has a short failure path. I would not oppose "every failing slot" if the others want it, because the P_i probes run anyway. Each extra ladder is the real cost.
>
> **(e) strerror_r: "returns a pointer to `char`" (sign folded), help "declare the result `Ptr[U8]`".** The rule is the same as in (a). I endorse aiml's const binding for the result probes (`const void *r`, `const char *r`): without it, gcc and clang disagree on a `const T *` return, which breaks determinism.
>
> **(f) Fold the sign. Add no flag.** Adding `-Werror=pointer-sign` to the split probes only would make the probes use flags that the unit does not use. The split could then fail a slot that the verdict passed. The split must use exactly the unit's flags. Sign is the author's claim (§9.1.1) anyway.
>
> **(g) A scalar slot that a pointer was passed to (fgets `n`): the message says "the header takes a number", with no help.** Scalar widths are never checked, so no probe can choose `I32` over `Int`, and "declare it with the integer type the header gives" restates the message. A help line that adds no fact is surface with no gain.
>
> ## Position
>
> Option A with: (a) the C kind with sign folded, plus the Blink type in the help; (b) the three-fact gate, mirror first and `Ptr[Void]` second with its condition; (c) the exact count with no named removal; (d) the first failing slot; (e) the const-bound result probes; (f) no extra flag; (g) no help for a scalar slot. The text from G and M stays as the fallback when the probes prove nothing.
>
> Stable, ready to vote.

### Phase C — Vote

> # [ticket] — Phase C ballot (silent vote)
>
> Every seat said "stable, ready to vote" after round 1. Vote on your own; do not message other seats.
>
> ## Settled in round 1 (every seat agreed; not on the ballot)
> - The success path is one pass/fail probe. On failure only: split probes, same flags and includes as the unit, compiled with `-c` (never `-fsyntax-only`), pass/fail only.
> - The message names the failing slot. It never prints a struct spelling.
> - Ptr[Void] appears in help only when three facts hold: the declared pointee is @ffi.struct/@ffi.opaque, a probe proved the slot is a pointer, and no scalar pointee passes. When it appears, a mirror comes first and Ptr[Void] second, with its condition.
> - Result probes bind through `const` (`const void *r`, `const T *r`). The help for the strerror_r case is `Ptr[U8]`.
> - If the verdict fails but no split probe reproduces it, print the Option G text (no slot, "compare" help).
> - A variadic header gives "takes at least m".
> - The connect example changes. On glibc it passes because of the transparent union; on musl it fails. The verdict depends on the target libc, not on the compiler.
>
> ## Q1. Which option?
> - **A**: print what the probes proved, with the slot, a proved scalar pointee and gated help.
> - **M**: slot and kind only; help always "compare"; no Ptr[Void] in help.
> - **G**: no split; one generic message.
>
> ## Q2. The sign of a proved scalar pointee (pipe with `Ptr[SockIn]`)
> - **S1, fold the sign; the probes use the unit's flags only** (sys, min):
>   `the header takes a pointer to \`int\` (or \`unsigned int\`)` / `help: declare the parameter \`fds: Ptr[I32]\` or \`fds: Ptr[U32]\``
> - **S2, add `-Werror=pointer-sign` to the diagnosis probes only, so exactly one type passes** (plt, web, devops, aiml):
>   `the header takes a pointer to \`int\`` / `help: declare \`fds: Ptr[I32]\``
>   (strerror_r under S2: "returns a pointer to `char`")
>
> ## Q3. The mirror probe when the three Ptr[Void] facts hold
> - **R1, probe the program's own @ffi.struct mirrors as a closed set** (sys, plt, aiml). If exactly one mirror passes, the help names that mirror only. If none passes, use the two-way help:
>   `help: declare \`req: Ptr[T]\` with an \`@ffi.struct\` that mirrors the header's type; if \`nanosleep\` takes more than one struct type here, declare \`req: Ptr[Void]\``
> - **R2, no mirror probe**: always use the two-way help above.
>
> ## Q4. Arity (`fn c_pipe(fds: Ptr[I32], flags: I32)`)
> - **C1, exact count; name the parameter only when exactly one typed drop-one probe passes; otherwise no help** (sys, plt, web, devops, aiml):
>   `\`pipe\` takes 1 parameter; this declaration has 2` / `help: remove the parameter \`flags\``
> - **C2, exact count; never name a parameter to remove** (min):
>   `\`pipe\` takes 1 parameter; this declaration has 2` (no help)
>
> ## Q5. Several failing slots in one declaration
> - **E, every failing slot in one E0861, one line (and a secondary label) per slot** (sys, plt, web, devops, aiml)
> - **F, the first failing slot only** (min)
>
> ## Q6. A scalar slot that got a pointer (fgets `n: Ptr[...]`, header takes a number)
> - **N, no help**: `the header takes a number; this declaration passes \`FILE *\`` (sys, web, devops, min)
> - **K, a kind help with no width**: the same message plus `help: a number, not a \`Ptr\`` (plt, aiml)
>
> ## Writer notes (wording; not on the ballot)
> - aiml: say "a pointer to `int`", not "takes `int *`". The probe does not see `const`, so "takes `int *`" is false for a `const int *` parameter.
> - web: keep the "compare `<slot>` with the prototype of `f` in `h`" line as a note where no help applies.
>
> ## Your vote
> Write to [scratch path]/<seat>-C.md (S = [scratch path]). For each of Q1-Q6 give:
> 1. your vote (the option letter)
> 2. your reasoning, 2-4 sentences from your domain
> 3. one concern: what could go wrong with the winning option, in your view
> Then reply to team-lead with "voted" and your six letters.

- **Systems:**

> # [ticket] — Systems seat, Phase C vote
>
> ## Q1: A
> Each extra probe costs about 10 ms and runs only after the verdict has failed. So proving the slot, the pointee and the help costs less than one unit compile, and it saves a second build. M throws away facts the build can prove cheaply. G makes every user open the header.
> Concern: the number of failure-path probes grows with arity × ladder × mirrors. The implementation must run them in parallel, under the gate cap, and stop once each slot is classified, so a large binding does not spend seconds per bad declaration.
>
> ## Q2: S2 (I move from S1)
> My S1 reason was that the probe flags must not drift from the unit's flags. That holds for the verdict probe and the slot probes, which decide whether there is an error and where. The pointee ladder only classifies a slot that has already failed under the unit's flags. So adding `-Werror=pointer-sign` to the ladder cannot create an error or move one. gcc, clang and zig cc all have `-Wpointer-sign` with the same semantics. Exactly one type passes, and the help gives one exact fix.
> Concern: types whose sign the implementation chooses. An enum pointee is compatible with `unsigned int` or `int` depending on the compiler's choice of enum type, and plain `char` is its own type. The ladder must contain `char` and the enum case must give a deterministic result across gcc and clang. If it does not, the help names different types on different hosts.
>
> ## Q3: R1
> The program's mirrors are a closed set the compiler already has, so the probes cost almost nothing. A proved mirror is the exact fix, and it keeps `Ptr[Void]` out of the help when the precise type exists, which answers the reflex concern.
> Concern: two mirrors of one C type, or a typedef and its tag mirrored separately, can both pass. The "exactly one" rule must then fall back to the two-way help, not pick one by declaration order.
>
> ## Q4: C1
> The drop-one probes are n compiles, only on the failure path, and the help prints only when exactly one passes. That keeps the help provable, and the fix is one edit.
> Concern: when the extra parameter has the same C kind as its neighbor (two `I32`s), more than one drop passes. Then there is no help, and users may read that as a missing feature. The message must still give the count.
>
> ## Q5: E
> The slot probes put `0` in the other slots, so a failure in one slot never causes a failure in another. They all run anyway. Reporting each slot avoids a second full build per error.
> Concern: a by-value struct slot can fail together with the count. The ordering rule (count first, slots only when the count passes) must hold, or E prints a cascade of slot lines that are all one count error.
>
> ## Q6: N
> An int and a float are not distinguishable under the pins (implicit conversion), so "a number" is the whole proved fact, and the message already says it. A help line that repeats it adds output and no fact.
> Concern: a model may want an imperative line to act on, and "takes a number" alone may lead it to guess `I32` where the header has `size_t`. That is the author's claim under §9.1.1, so it is not a false-error risk.
>
> Six letters: A S2 R1 C1 E N

- **Web/Scripting:**

> # [ticket] Phase C — web vote
>
> ## Q1: A
> The probes have already proved the slot, the pointer or scalar shape, and often the exact pointee. If we throw that away, as M and G do, a JS/Python dev has to open `/usr/include` to learn what we already knew. A gives most failures a one-edit fix and prints no guesses.
> Concern: the output gets richer, so it needs more tests. Every line kind (slot, scalar pointee, mirror help, Ptr[Void] condition, arity drop, fallback) needs a corpus test on each supported compiler, or one of them will quietly go stale.
>
> ## Q2: S2
> "`Ptr[I32]` or `Ptr[U32]`" hands the user a coin flip, and socklen_t shows the flip has a wrong side. A help that gives two choices is not one edit. `-Werror=pointer-sign` acts the same on gcc, clang and zig cc (I checked in probe/web). It runs only on the error path, so the verdict stays the same.
> Concern: a compiler we add later might not treat pointer-sign as an error. Then two rungs pass at once. The rule for that case must be "fall back to the folded S1 text", never "pick the first rung".
>
> ## Q3: R1
> If exactly one of the program's own mirrors passes, then "declare `req: Ptr[Timespec]`" is a proved, one-edit fix. That is the best DX this ticket can give, and the mirror set is closed and small. The two-way help stays as the fallback, so nothing is guessed.
> Concern: cost and noise in programs with many mirrors. Cap it at the mirrors that the unit compiles. If more than one passes (identical layouts behind typedefs), fall back to the two-way help, never a list.
>
> ## Q4: C1
> A typed drop-one probe that passes proves which parameter is extra, so "remove `flags`" is a fact, not a guess. When drops are ambiguous we print no help, which is still honest.
> Concern: two neighbouring scalars of the same kind make the drop probes ambiguous, and users may expect a name every time. The spec example should show the no-help case too.
>
> ## Q5: E
> The slot probes are independent, so listing every failing slot costs no extra probes. It also saves one rebuild per bad slot, and that is the real time cost for a human or a model fixing a binding.
> Concern: a declaration with the wrong function name, or a by-value struct, can fail in every slot and print a wall of lines. If every slot fails, collapse them to the arity/fallback text.
>
> ## Q6: N
> The message already says "the header takes a number". A help reading "a number, not a `Ptr`" says it twice with no type, so it isn't an edit. Help lines should mean "here is the fix". A help that only repeats the message teaches users to skip help lines.
> Concern: a model may still reach for the wrong integer width. The "compare with the prototype in `stdio.h`" note (writer note) must stay, so the reader has a next step.

- **PLT:**

> # [ticket] Phase C — PLT vote
>
> ## Q1: A
> Each fact A prints comes from the declaration, or it is the only candidate left from a closed set under a fixed probe. So every claim is sound. M is sound too, but it throws away facts the test already proved. That is less information, not more correctness. G is kept as the fallback for when the split probes cannot reproduce the verdict.
> Concern: the scalar candidate list must be fixed in the spec, with the extended types named (`_Bool`, `long double`, `char` family). If an implementation grows the list, the output differs between implementations.
>
> ## Q2: S2
> With `-Werror=pointer-sign`, exactly one candidate passes. That makes the help a single edit, not an "or". The flag runs only in the diagnosis probes, after the verdict, so it cannot change pass/fail. gcc, clang and zig cc all honour it the same way (I checked).
> Concern: the diagnosis probes then use flags the unit does not use. A future change that adds more diagnosis flags could drift until a slot probe disagrees with the verdict. The spec must say that only this one flag is added, and only to the classification probes, not to the slot probes.
>
> ## Q3: R1
> The program's mirrors are a closed set the compiler already holds. When exactly one passes, naming it is a proved, one-edit fix, which is better than the two-way help. It costs nothing on success.
> Concern: two mirrors can share one C tag (or one can be a typedef of the other), so more than one passes. Then the rule must fall back to the two-way help and never pick one.
>
> ## Q4: C1
> A typed drop-one probe that passes for exactly one parameter proves which parameter is extra. Without that proof, naming one is a guess, so there is then no help.
> Concern: the drop probes keep the declared types, so a second, independent slot error can make every drop fail. The result is "no help" even when the count fact is clear. That is acceptable, but it is less useful.
>
> ## Q5: E
> The slot probes put `0` in every other slot, so they are independent and cannot cascade. Reporting only the first slot hides facts the test already holds, and it forces one more build per bad slot.
> Concern: a by-value struct slot cannot take `0`, so it must keep its declared form. If that slot is itself wrong, every other probe fails too, and E reports false extra slots. In that case, fall back to the arity/G path and not to E.
>
> ## Q6: N
> The message already says "the header takes a number". A help line that repeats it in other words adds tokens and no new fact. No width can be proved, so a help that is more specific than the message is not available.
> Concern: a model may read "no help" as "no known fix" and reach for `Ptr[Void]`. A short note in `blink explain E0861` covers that.
>
> Letters: A S2 R1 C1 E N

- **DevOps/tooling:**

> # [ticket] Phase C: DevOps/tooling vote
>
> ## Q1: A
> Reasoning: the probes have already proven which slot fails, its shape, and often the exact pointee. Hiding that makes every human and model open the header to learn what the test knew. A gives a one-edit fix at no cost on the success path, and with a bounded cost only on a failure.
> Concern: the error path now runs many small compiles. On a slow C compiler, a binding with many parameters and several failing slots could take seconds. Run the probes in parallel, and bound them so the order of the output never depends on timing.
>
> ## Q2: S2
> Reasoning: with `-Werror=pointer-sign` on the diagnosis probes only, exactly one candidate passes. I measured the same verdict on gcc, clang and zig cc. One proven type gives one help line, and "`Ptr[I32]` or `Ptr[U32]`" invites a coin toss. The flag never touches the base verdict or the unit, so the decided rules stay as they are.
> Concern: a future compiler could move pointer-sign into a different warning group, so that two candidates pass or none does. The implementation must then fall back to S1 text, not to a wrong single type. The corpus should pin one probe that asserts the sign split.
>
> ## Q3: R1
> Reasoning: the program's own `@ffi.struct` mirrors are a closed set the compiler already has. A passing mirror is proof, not a guess. "Declare `req: Ptr[TimeSpec]`" is the true one-edit fix, and it avoids the `Ptr[Void]` reflex on the `nanosleep` case. The cost is one compile per mirror, only after all the other diagnosis probes.
> Concern: in a program with hundreds of mirrors the probe count grows. Batch the mirror probes or cap them, and fall back to the two-way help past the cap, so the output stays deterministic.
>
> ## Q4: C1
> Reasoning: the drop-one probe is a compile. When exactly one drop passes, naming that parameter is a proven fact, not a guess. "Remove `flags`" is the edit a model makes in one step. When the evidence is unclear, there is no help, so the help is never false.
> Concern: with neutral `0` slots, drop probes can pass for more than one parameter of the same shape, so the help disappears in exactly the cases where it would help most. That is acceptable, but tests must cover it.
>
> ## Q5: E
> Reasoning: slot probes are independent, so there is no cascade to hide. First-fail costs one full build cycle (header test, struct test, probes) per wrong slot, and an agent loop pays that again for each slot. Give one diagnostic with ordered labels, and JSON `related` entries in the same order.
> Concern: tools that read only the primary span see the `@ffi` line and one message, so the per-slot lines must each carry the slot name in the text, not only in the labels.
>
> ## Q6: N
> Reasoning: a scalar width is never checked, so no probe can prove a better help than the message itself ("the header takes a number"). A help line that adds no fact is noise, and models learn to copy noise.
> Concern: some tools treat "no help" as "no fix known" and stop. The message must state the fix direction plainly (a number, not a pointer), so N stays actionable.
>
> Letters: A S2 R1 C1 E N

- **AI/ML:**

> # aiml — Phase C vote, [ticket]
>
> ## Q1: A
> Reasoning: A is the only option where a model can fix the binding in one edit without opening the header. With M, pipe and connect give the same output but need different fixes, so a model needs two turns or guesses. A also deals with the `Ptr[Void]` reflex: pipe's help names the proved scalar `Ptr`, so models see the right fix there.
> Concern: the split probes can disagree with the verdict probe in a way the spec does not foresee. If the implementation then prints a slot line anyway, a confident false line teaches models something wrong. The fall-back to the G text must be strict: print the G text unless every printed fact came from a probe that passed or failed.
>
> ## Q2: S2
> Reasoning: Each fork in a help line ("`Ptr[I32]` or `Ptr[U32]`") is one more choice for the model, and one more way to pick wrong. I checked on gcc 16, clang 23 and zig cc: with `-Werror=pointer-sign` in the diagnosis probes only, exactly one member of each family passes, and all three compilers agree. The verdict does not change, because the flag never reaches the verdict probe or the unit.
> Concern: a future compiler could move part of the sign check out of `-Wpointer-sign` (clang has split warning groups before). Then no member, or two members, would pass. The rule must fall back to the folded S1 text when the count is not exactly one, and never pick one in silence.
>
> ## Q3: R1
> Reasoning: a mirror the program already has, proved by a probe, gives the exact fix (`Ptr[TimeSpec]`) in one edit. It is the best help a model can get. The two-way help remains only for the case where no mirror passes, so `Ptr[Void]` is never the first thing a model sees when a proved fix exists. The set is closed and finite (the program's own mirrors), so nothing is guessed.
> Concern: a mirror can pass the probe because it has the right C tag while its fields are wrong. E0862 runs first and catches that, but the ballot should keep that order explicit. Without it, the help could point to a wrong mirror.
>
> ## Q4: C1
> Reasoning: "remove the parameter `flags`" is a one-edit fix, and the typed drop-one probe proves it. When no single drop passes, there is no help, so no false help. That is the line between a proved fix and a guess, and it is the same line as every other help in A.
> Concern: two parameters with the same C type (`(I32, I32)`, header takes one) make both drops pass, so there is no help. That is honest. But users may read the missing help as a bug, so the spec example should show that case too.
>
> ## Q5: E
> Reasoning: the slot probes are independent (`0` in every other slot), so there is no cascade, and every line is true. A model that sees all bad slots fixes them in one turn. With first-slot reporting it needs one build for each slot, and each build costs tokens and wall time. E0862 already reports every bad mirror in one run, so this matches it.
> Concern: a binding that is wrong in every slot (for example the wrong function) gives a long report where a single "wrong function?" hint would help more. That is acceptable, since the arity check usually catches it first.
>
> ## Q6: N
> Reasoning: I change from K. The message line already says "the header takes a number", which tells the model the fix. A help line that repeats it costs tokens, adds nothing, and makes the output look like it has more to say than it does. A rule I can defend: give help only when it adds a fact or an edit the message does not hold.
> Concern: a weak model may still try another `Ptr` type. With N it gets no fallback hint. The web note ("compare `n` with the prototype ...") can cover that.
>
> Votes: Q1 A, Q2 S2, Q3 R1, Q4 C1, Q5 E, Q6 N

- **Minimalism:**

> # [ticket] — Minimalism, Phase C vote
>
> ## Q1: A
> Every fact A prints comes from a closed set of fixed probe texts, so it is proof, not a guess, and it runs only on a path that has already failed. M leaves the pipe user with no fix and decides Q3 with no proof. G throws away facts that cost about 10 ms each.
> Concern: the probe ladder grows into a C type printer by accretion (qualifiers, function pointers, more kinds). The spec should list the closed sets and say that nothing outside them is printed.
>
> ## Q2: S2
> I objected to an extra flag because a split probe could then disagree with the verdict. That objection does not hold if the flag is only on the ladder: the slot is still found with the unit's flags, and `-Werror=pointer-sign` only picks which of the closed types passes. The result is one help line with one fix, not "I32 or U32", so the output is smaller.
> Concern: a supported compiler may put a char/signed char/unsigned char case or an enum pointee under some other warning, so that no type passes, or two do. The spec must say what prints then (fall back to the S1 two-sign text), and a gcc/clang/zig cc test row must pin the behavior.
>
> ## Q3: R2
> R1 rarely helps. If the program already had the right mirror, the author would almost always have used it. The two-way help already names the action. R2 has no probe set that grows with the program, so one rule covers every case.
> Concern: in the rare program that does hold the right mirror, R2 makes the user find it by hand, and a model may take the `Ptr[Void]` branch where the mirror would keep the check.
>
> ## Q4: C1
> In round 1 my objection was to drop-one probes with `0` in every slot; those cannot tell which parameter is extra. Typed drop-one probes can: in `pipe(fds, flags)`, dropping `fds` puts an `int` in an `int *` slot and fails, and dropping `flags` passes. When exactly one probe passes, the help is proof, and in every other case there is no help.
> Concern: when two adjacent parameters have the same type, several drop-one probes pass, so no help shows. That is correct, but users may read the missing help as an inconsistency; the spec example should show that case.
>
> ## Q5: E
> Slot probes do not cascade (unlike E0862 offsets), and the P_i probes run anyway, so E reports what the test already knows and saves a rebuild cycle per extra bad slot. Only the ladders add cost, and only on failure.
> Concern: one wrong mirror type used in many bindings or slots gives a long report. The report needs a stable order (parameters left to right, then the result) so the output is byte-stable across runs and hosts.
>
> ## Q6: N
> Scalar widths are never checked, so no probe can choose a width. "A number, not a `Ptr`" repeats the message. A help line that adds no fact is surface with no gain.
> Concern: a model may expect every E0861 to have a help line and invent one. The web writer note (a "compare" note where no help applies) covers that.

### Final Spec

```blink
@ffi("pipe", header: "unistd.h")
@trusted(audit: "UNISTD-PIPE")
fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
// unistd.h: int pipe(int fds[2]);
// blink build: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
//   `pipe` does not match its prototype in `unistd.h`
//   parameter 1 `fds`: the header takes a pointer to `int`; this declaration passes `struct sockaddr_in *`
//   label on `fds`: the header takes a pointer to `int`
//   help: declare the parameter `fds: Ptr[I32]`

@ffi("pipe", header: "unistd.h")
@trusted(audit: "UNISTD-PIPE")
fn c_pipe2(fds: Ptr[I32], flags: I32) -> I32 ! () {}
// blink build: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
//   `pipe` takes 1 parameter; this declaration has 2
//   help: remove the parameter `flags`

@ffi("fgets", header: "stdio.h")
@trusted(audit: "STDIO-FGETS")
fn c_fgets(buf: Ptr[U8], n: Ptr[CFile], f: Ptr[CFile]) -> Ptr[U8] ! () {}
// blink build: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
//   `fgets` does not match its prototype in `stdio.h`
//   parameter 2 `n`: the header takes a number; this declaration passes `FILE *`
//   label on `n`: the header takes a number
//   note: compare `n` with the prototype of `fgets` in `stdio.h`
```
