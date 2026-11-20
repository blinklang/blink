[< All Decisions](../DECISIONS.md)

# What `header:` Means on an `@ffi` Binding — Design Rationale

**Gap:** §9.1 said that `header:` names the C header that declares the symbol, and that the symbol "gets the C signature that the declaration gives". It did not say whether the header goes into the C unit, whether the prototype of the header or the Blink signature is the C prototype of the call, or what happens when the header does not declare the symbol. The same binding could then build on one host and fail on another, and a binding with no `header:` could give I0017 when another header of the unit declared its symbol.

```blink
@ffi("memfd_create", header: "sys/mman.h")
fn c_memfd_create(name: Ptr[U8], flags: U32) -> I32 ! ()    // Linux: declared; macOS: not declared
```

This decision relates to [A `Ptr` at an `@ffi` Call](ffi-pointer-prototype.md), which added the prototype test (E0861), and to [A Struct Mirror That Does Not Match Its C Struct](ffi-struct-layout-mismatch.md).

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q0 | Does the spec need a change? | Yes. | 6-0 |
| (a) | What does `header:` do? | It puts the named header into the unit, after the runtime prologue, in a fixed order, with one `#include` for each distinct header. The prototype test reads the same includes and feature macros as the unit. | 6-0 |
| (b) | Which prototype governs the C call? | Per symbol. If any header that the unit reads declares the symbol, the call goes through that prototype and C converts the arguments. The Blink signature governs the Blink side; it is the claim of the author, and E0861 checks it. Scalar widths are for `blink audit`. If no header declares the symbol, the signature of the declaration is the C prototype. | 6-0 |
| V2 | Which wrappers does the prototype test cover? | Every `@ffi` wrapper that the unit compiles, with the includes of the unit. A binding with no `header:` whose symbol another header of the unit declares gets E0861 at its `@ffi` line, exit 1, never I0017. | 6-0 |
| V1 | A binding names a header that is found but does not declare the symbol in this build | `V1-E`: E0861 at the `@ffi` line, exit 1, from `blink build` and `blink test` only. | 4-2 in Phase C (Web/Scripting and Minimalism for `V1-F`); 6-0 in the Phase D re-vote |
| Q-M | Which feature macros? | `M-W`: the unit and the test define a wide, fixed set for each libc, and the spec states it: `_DEFAULT_SOURCE` and `_GNU_SOURCE` on glibc, `_DARWIN_C_SOURCE` on macOS; the same set on every host of a libc. | 5-1 (Minimalism dissents for `M-N`) |

The owner approved the tally.

### Dissent

**Minimalism, Q-M** voted `M-N` (no set in the spec). The vote, verbatim:

> Reasoning: under V1-F the macro set changes only whether a call is checked, never whether it builds, so the spec does not need to fix it. A wide set is not free. `_GNU_SOURCE` changes prototypes, not just visibility: `strerror_r` returns `char *` under it (bootstrap/runtime_errno.h:13 deals with exactly this), and `basename` changes too. A wide set written into the spec locks the language to those variants on every libc. The spec already says the test and the unit share one set, and that is the rule that matters. Which set it is stays an implementation choice the compiler can widen when a real binding needs it.
>
> Concern: without a stated set, an implementation can narrow the macros, and a binding that was checked becomes unchecked with no notice in the spec.

The panel chose `M-W`. The spec states the set and shows the GNU `strerror_r` case, as Systems, AI/ML, Web/Scripting and PLT asked in their votes.

**Web/Scripting and Minimalism, V1 in Phase C** voted `V1-F` (fall back to the Blink signature, and let `blink audit` mark the binding). Their votes, verbatim:

- **Web/Scripting:**

> Reasoning: The user writes the header the man page names. A build that stops with "this header does not declare this symbol" contradicts the man page, so the user has to learn feature macros just to get unstuck. The only help available is "remove `header:`", which teaches people to delete the thing that turns on checking, and on macOS that loses a check that would have run. F builds on every host, costs no new code path, and `blink audit` records the gap where an auditor will look.
> Concern: Some users will assume a binding is checked because it names `header:`, when on glibc it quietly runs on the unchecked Blink extern. The audit mark is the only signal they get.

- **Minimalism:**

> Reasoning: V1-F is the one rule that already ships. If a header the unit reads declares the symbol, its prototype governs; if none does, the guarded Blink extern governs. V1-E adds a second rule and an error path. That path stops a build on the host where the program works (glibc `memmem`), and its fix (drop `header:`) also removes the check on every host where the header does declare the symbol. plt's "one meaning on every target" is bought with a host split in what builds, which is the worse kind of split.
>
> Concern: an author can name a `header:` that never declares the symbol on their main host, and read the build as checked when it is not. The audit mark is the only place that says so.

The count was 4-2 for `V1-E`, so Phase D ran. After `M-W` was decided, both seats moved to `V1-E`. Their Phase D re-votes are in the Phase D section below. The concern of Web/Scripting and Minimalism, that an author may think a binding is checked when it is not, is met by the message, which says that the header does not declare the symbol for this target, and by `blink audit`.

Writer notes from the votes, and where the spec meets them:

- The rule is per symbol, not per binding (PLT, Web/Scripting). §9.1 *What `header:` does* says so.
- The E0861 message for `V1` says "for this target". It does not say that the header or the symbol is missing, and it does not name a feature macro (AI/ML). The help offers only "remove `header:`; the call then uses this declaration's prototype, unchecked", with no per-target gate (Minimalism, DevOps, Systems, AI/ML, PLT; Blink has no conditional compilation). For a symbol that the target lacks, the text says "not available for this target", because dropping `header:` only moves the stop to the linker (Web/Scripting). §9.1 *What the prototype test covers* shows it with `memfd_create`.
- The E0861 note of `V2` names the header that declares the symbol (Systems).
- The docs tell authors to name `header:` when that header declares the symbol. AI/ML withdrew "on every binding".
- The docs name the macro set and show the GNU `strerror_r` case (Systems, AI/ML, Web/Scripting, PLT).
- Every rule has an example: `cos`, `sqrtf` and `readlink` with a header, a binding no header declares, `realpath` on macOS, the `V2` case, `memfd_create` on macOS, and `strerror_r`.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote and re-vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path that the reply contains shows as `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

- **Systems:**

> # [ticket] — Systems seat (sys), Phase A
>
> ## What main does today (probed: build/blink build --emit c)
>
> The user unit includes only `libblink_std.h`. Each non-prologue symbol gets a guarded prototype from the Blink signature:
>
> ```c
> #ifndef BLINK_DECLARED_readlink
> extern int64_t readlink(void* b_path, void* b_buf, uint64_t b_n);
> #endif
> ```
>
> `realpath` (prologue list) gets no prototype. So which prototype a call meets, and which **link symbol** it binds, depends on what the runtime's own headers happen to include. That is a runtime detail, not something the user wrote.
>
> Two facts drive my answer:
>
> 1. **The header prototype is the real ABI.** If the Blink prototype says `double f(double)` and the C function is `float f(float)`, the caller puts a double in xmm0 and the callee reads a float: a wrong value, no error. Through the header's prototype, C converts double to float at the call. The machine code costs the same, and only one of the two is right.
> 2. **The test and the unit must see the same prototype.** E0861 compiles the call "against the prototype in the header". If the unit then calls through the Blink prototype, the test passes a program that the unit compiles differently. The `float` case above passes E0861 (C converts the scalar) and then runs wrong.
>
> ## Proposal S1 (recommended): `header:` goes into the unit; the header's prototype governs
>
> - **Q0: yes.** Today the answer depends on runtime internals, and on macOS it decides which symbol links.
> - **(a) yes.** Each distinct `header:` is `#include`d in the unit after the prologue, under the unit's pinned feature macros. The prototype test reads the same includes.
> - **(b) the header's.** When a header the unit reads declares the symbol, the call goes through that prototype. C converts the arguments as for any C call, with no added casts. The Blink signature is the author's claim about that prototype. The Blink side of the binding (its callers, its types) uses the Blink signature. E0861 checks the claim (pointers, arity, int/pointer), and `blink audit` marks scalar widths. When no header the unit reads declares the symbol (no `header:`, or a macro hides it), the prototype from the Blink signature governs, as today. 07:115 then reads as "the Blink signature governs the Blink side", not "the C call".
> - **The test covers every symbol a unit header declares**, not only bindings that name `header:`. Otherwise a binding with no `header:`, whose symbol another binding's header declares, fails in the unit compile as I0017.
>
> ### Examples
>
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> ```
> check: no error. build/test: E0859 passes, E0861 passes, the call meets math.h's `double cos(double)`. Same code as today, but the result does not hang on whether `libblink_std.h` reaches math.h.
>
> ```blink
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> ```
> check: no error. build: E0861 passes (`void *` converts to `const char *restrict`, `uint64_t` to `size_t`, `ssize_t` to `int64_t`). The call meets the header's prototype. No `extern int64_t readlink(...)` is written, so a target where `int64_t` is `long long` and `ssize_t` is `long` gets no conflicting types.
>
> ```blink
> // glibc hides strlcpy unless _DEFAULT_SOURCE (or glibc >= 2.38)
> @ffi("strlcpy", header: "string.h")
> @trusted(audit: "STRLCPY")
> fn c_strlcpy(d: Ptr[U8], s: Ptr[U8], n: U64) -> U64 ! ()
> ```
> build: string.h is included. The probe finds `strlcpy` not declared under the pinned macros, so the Blink prototype governs. If libc has the symbol, it links. If not, the link step fails as it does today. The pinned macros make this the same verdict on every host with one libc. A hidden symbol is not an error of its own.
>
> ```blink
> @ffi("realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(p: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
> ```
> build on x86_64-macos: the call meets stdlib.h's prototype and binds `_realpath$DARWIN_EXTSN`. The same holds for `readdir`/`stat` (`$INODE64`). A Blink prototype would bind the legacy symbol and read the old struct layout with no error. With no `header:` on a symbol that no unit header declares, you get the plain symbol. `blink audit` marks a binding with no `header:` "link symbol not checked against a header".
>
> ### Tradeoffs (systems)
>
> - **Run-time cost: zero.** It is still the same direct call in the same unit, so the wrapper still inlines. This is why I reject a per-header shim unit, which keeps the includes apart but costs a call that cannot inline without LTO (hot `cos` loops).
> - **Compile cost:** one `#include` per distinct header. The probe already compiles the prefix.
> - **Namespace risk:** header macros (`stat`, `major`, `getc`) can hit generated names. Generated names are `blink_*`/`b_*`. The probe already treats a macro of the symbol's name as declared, and a function-like macro call compiles.
> - **Two bindings, one symbol, different headers:** C takes one prototype. The bindings meet the same header prototype, and E0861 judges each claim.
>
> ## Proposal S2: do nothing (header: names only the tests)
>
> The unit keeps what main does. I reject it: E0861 and the unit would check against different prototypes. The macOS rename and the scalar-width conversion would depend on runtime include order. Pre-1.0, we should fix it now.
>
> ## Cross-language
>
> Zig `@cImport`, Go cgo (preamble) and Swift (Clang importer) all call through the header's prototype, so they get renames and conversions for free. Rust `extern` uses the author's signature. The `libc` crate must hand-write `#[link_name = "realpath$DARWIN_EXTSN"]` per target, and gets bugs when it misses one. S1 puts Blink on the Zig/Go side and keeps Rust's explicit signature as the checked claim.

- **Web/Scripting:**

> # [ticket] Phase A: Web/Scripting seat
>
> ## Where things stand
>
> The spec reads two ways now. §9.1:61 says E0861 tests the call "against the prototype in the header". §9.1:115 says "the symbol gets the C signature that the declaration gives". On main, the unit calls through the header's prototype only if the runtime's includes declare the symbol. Otherwise it calls through `extern <Blink signature>`. So **the prototype that E0861 tests can be different from the one the program runs.** That gap is the bug. A JS or Python dev will reasonably read `header: "math.h"` as `#include <math.h>`. Today it is an existence test only.
>
> Q0: **yes.** The spec has to say this, because whoever implements E0861 must know what to do when the header does not declare the symbol (see the feature-macro example).
>
> ## Proposal W1 (preferred): one prototype, the one the test saw
>
> Behavior:
> 1. `header:` puts the named header into the C unit that calls the symbol (Q(a): yes).
> 2. If any header that the unit reads declares the symbol, **the header's prototype governs** (Q(b)). The build writes no prototype from the Blink signature. C converts the arguments as it does for any call. The Blink signature is the author's claim. E0861 checks its pointer and int/pointer parts, and `blink audit` marks scalar widths, as already decided.
> 3. If no header that the unit reads declares the symbol (no `header:`, or the header hides it behind a feature macro), the Blink signature governs (`extern <Blink signature>`, as D1 does). The prototype test has nothing to test, so it passes. `blink audit` marks the binding "prototype not checked".
> 4. The prototype test reads the same includes, with the same fixed feature macros, as the unit. So the test and the run always see the same prototype.
> 5. The user cannot set feature macros (YAGNI). One source gives the same verdict on every host, as decided.
>
> The rule a user learns: *"If a header declares it, C uses the header. Your signature must agree with it."*
>
> ### Example A: cos
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> ```
> - check: no error, exit 0. It reads no header.
> - build/test: E0859 passes and E0861 passes. The unit reads math.h, and the call meets `double cos(double)`. It runs.
> - A wrong claim `fn c_cos(x: Int) -> Int` gets no E0861 (scalar). Under W1, C converts the value (`(double)x`, and the result is truncated), so the program runs and gives a usable answer. Under a Blink-signature extern, the Int goes into an integer register while cos reads xmm0, so the result is garbage. **When the header governs, a wrong scalar claim becomes a C conversion, not an ABI break.**
>
> ### Example B: readlink
> ```blink
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> ```
> - check: no error.
> - build/test: the pointers cross as `void *` (§9.1.1), which C accepts for `const char *restrict`. U64 converts to `size_t`, and the `ssize_t` result converts to Int. E0861 passes. The call goes through unistd.h's prototype, and it runs. The Blink signature is the claim, and C checks it against the header.
>
> ### Feature macro: memmem (glibc hides it without _GNU_SOURCE; the unit sets _POSIX_C_SOURCE 200809L)
> ```blink
> @ffi("c", "memmem", header: "string.h")
> @trusted(audit: "MEMMEM")
> fn c_memmem(h: Ptr[U8], hl: U64, n: Ptr[U8], nl: U64) -> Ptr[U8] ! ()
> ```
> - check: no error.
> - build/test on glibc: E0859 passes. string.h does not declare memmem under the unit's macros, so the test passes with nothing to check, and the unit gets `extern void *memmem(void *, uint64_t, void *, uint64_t)`. It runs. Audit: "prototype not checked".
> - On macOS, string.h declares memmem, so the header governs and E0861 checks it. The same source builds on both hosts.
> - The existing objection ("a header can hide its symbol") does not apply: including a header that hides the symbol does no harm, because the guard keeps the extern.
>
> ### macOS rename: realpath, and a header outside the prologue
> ```blink
> @ffi("c", "realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(p: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
>
> @ffi.opaque(header: "fts.h", name: "FTS")
> type Fts
> @ffi("c", "fts_open", header: "fts.h")
> @trusted(audit: "FTS-OPEN")
> fn c_fts_open(argv: Ptr[Ptr[U8]], opts: I32, cmp: Ptr[Void]) -> Ptr[Fts] ! FS.Read
> ```
> - realpath: the prologue already reads stdlib.h, so the call binds `_realpath$DARWIN_EXTSN` both today and under W1.
> - fts_open on x86_64-macos: fts.h renames it to `fts_open$INODE64`. **Today:** E0861 tests against fts.h and passes, but the unit does not read fts.h, so it links the plain, legacy `fts_open` with the old 32-bit inode layout. Nothing reports it, and the data is wrong at run time. **W1:** the unit reads fts.h, the call binds the renamed symbol, and the result is correct. This is the case I would expect to see on Stack Overflow ("passes on Linux, garbage on Intel Mac").
>
> ### What happens on a clash of names
> Two bindings can name headers that declare the same symbol. Under D1's guard, both calls go through the header's prototype. Real system headers agree with each other. If two third-party headers disagree, C rejects them, and that is a genuine conflict that the user has to fix.
>
> ## Rejected: W0, the status quo (header: is an existence test only)
> It has less unit text and no header parse per unit. But the test and the run see different prototypes. The rename case breaks without any error, `header:` misleads every reader, and §9.1:61 vs :115 stays contradictory. The fix for the spec would be "header: does not include the header", which a newcomer will find surprising.
>
> ## Tradeoffs (DX)
> - + One rule that matches what users already expect from `#include`, cgo and Zig.
> - + No new error code, no new knob, and E0861 means what it says.
> - + Macros and renames work. GHC added `capi` for exactly this reason.
> - − More C parsing per unit that holds a binding, with a small effect on build time. The object cache absorbs it.
> - − A third-party header can define macros that touch generated C. Blink's C names are prefixed, so the risk is low. If it happens, it is a user-visible I0017 with a note about the header.
>
> ## Other languages
> cgo: the preamble `#include` governs, and a mismatch is a cgo error. Zig `@cImport`, Swift (Clang importer) and Kotlin/Native cinterop: the header governs, and there is no hand-written signature. Rust: an `extern` block is an unchecked claim, and you need bindgen to read headers. GHC: `ccall` (the signature governs) proved too weak, so `capi` (the header governs) was added. W1 is the cgo/capi model with a Blink-signature fallback.

- **PLT:**

> # [ticket] — PLT seat, Phase A
>
> ## Q0: yes. The spec today has two rules for one call
>
> §9.1:61 says E0861 checks the call "against the prototype in the header". §9.1:115 says "the symbol gets the C signature that the declaration gives". Today the unit never reads the binding's `header:`. So the test (once built) would certify one C program and the build would run another. A check is sound only if it checks the program that runs.
>
> Probe (main, gen `build/blink`, x86_64 Linux):
>
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: I32) -> Float ! ()
>
> fn main() {
>     io.println("{c_cos(3)}")    // prints 1, not -0.98999
> }
> ```
>
> The unit gets `extern double cos(int32_t)` (math.h is not in the unit, so the guard keeps it). The `3` goes in an int register and `cos` reads `xmm0`. Against math.h, C would convert `3` to `3.0`, and a prototype test would pass. Test passes, program is wrong: that is the unsound split. The choice of prototype is also visible at run time on macOS (realpath rename) and on 32-bit targets (`U64` vs `size_t`). So it is semantics, not codegen detail, and the spec must state it.
>
> ## Proposal PLT-1 (recommended): one include set, the header governs
>
> **Rule 1 (a).** Each `header:` of a declaration goes into the C that calls the symbol. The unit's include set is the prologue, then each named header once, in a fixed order (order of first appearance in the program's modules). `@ffi.struct(header:)` already works this way.
>
> **Rule 2 (b).** For each bound symbol S: if a header in that include set declares S, the call meets the header's prototype. Else the call meets a prototype written from the Blink signature. This is a fact of the symbol, not of one declaration: C has one global namespace, so S has one prototype in a unit. (D1 already does this for the prologue; Rule 2 only widens the set.)
>
> **Rule 3 (one verdict).** The prototype test compiles the same wrappers, in the same include set, as the unit. E0861 is then a fact about the program that runs.
>
> **What the Blink signature still governs:** the type at every Blink call site (typecheck), and the C signature of the wrapper function. So §9.1:115 becomes true of the wrapper; the call inside the wrapper follows Rule 2. Two layers, each with one rule.
>
> ### Examples
>
> ```blink
> // A: header not in the prologue
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> ```
> - check: no error, reads no header.
> - build/test: E0859 if math.h is missing (exit 1). Else the unit reads math.h, the call meets `double cos(double)`, the test passes, runs. With `x: I32` (probe above) it also passes and C converts the value, so the program prints -0.98999. The wrong width stays the author's claim and `blink audit` marks it; it no longer corrupts registers.
>
> ```blink
> // B: types no Blink signature spells
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> ```
> - check: no error.
> - build/test: call meets `ssize_t readlink(const char *restrict, char *restrict, size_t)`. `Ptr[U8]` crosses as `void *` (§9.1.1), which converts to `const char *`; `U64` converts to `size_t`; the answer converts to `int64_t`. Test passes, runs. On wasm32, `size_t` is 32 bits: C converts, where a Blink-signature prototype would mismatch the ABI.
>
> ```blink
> // feature macro hides the symbol
> @ffi("pipe2", header: "unistd.h")
> @trusted(audit: "PIPE2")
> fn c_pipe2(fds: Ptr[I32], flags: I32) -> I32 ! ()
> ```
> - check: no error.
> - build/test: unistd.h is in the unit. If the pinned feature macros hide `pipe2`, no header declares it, so the guarded Blink-signature prototype stays and the call meets it. The test compiles the same wrapper and passes. Links the libc `pipe2`. `blink audit` marks it "not declared by its header on this target". No error: the author's claim "this header declares S" is false only under the runtime's macros, and the fallback is exactly the old behavior.
>
> ```blink
> // macOS renames the symbol
> @ffi("realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(path: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
> ```
> - check: no error.
> - build/test on x86_64-macos: the call meets stdlib.h's prototype and links `_realpath$DARWIN_EXTSN`, the same symbol a C program gets. On Linux, plain `realpath`. Under a Blink-signature prototype it would bind the legacy symbol with different behavior. Rule 2 makes Blink and C agree.
>
> ### Tradeoffs
>
> - Sound: the test and the unit see one prototype, so E0861 and I0017 keep clean meanings (I0017 = compiler bug or unchecked claim).
> - Safer: a scalar width error becomes a C conversion, not undefined behavior.
> - Not local: adding `header:` to one declaration can change the prototype that another declaration of a different symbol meets (the header declares it too). I accept this: it is how C linkage already works, D1 already has it for the prologue, and Rule 3 means the test re-checks every affected call. Two declarations of the same symbol with different Blink signatures is then visible as two wrappers over one prototype, each tested.
> - Cost: headers bring macros into the unit. The generated C must not use a name a libc header can define as a macro (implementation, not spec). A fortify macro (`read` to `__read_chk`) applies, as in C.
> - Determinism: include order is fixed by the rule, so one source gives one unit.
>
> ## Proposal PLT-0 (rejected): `header:` names only the E0859 test
>
> The unit never reads it; the prototype test must then also not read it, or Rule 3 breaks. Then E0861 never checks Example A at all, and `header:` is a comment that a missing file can fail. If the panel picks this, §9.1:61 must change to "against the prototypes the unit reads", and the probe above stays silent garbage.
>
> ## Cross-language
>
> - Zig `@cImport`: the header is the only prototype; Zig types are derived from it. PLT-1 is the same, but keeps the Blink signature as a checked claim.
> - Rust `extern "C"`: the Rust signature is the only prototype; no check at all. Hence bindgen and `ctest`. PLT-0 is this model.
> - Go cgo: calls go through the header's prototype in the preamble; macOS renames work. PLT-1 matches cgo.
> - Swift: Clang importer, header governs.

- **DevOps:**

> # [ticket] — DevOps/Tooling seat, Phase A
>
> Probe (main today, build --emit c): `cos`/math.h and `memfd_create`/sys/mman.h get
> `#ifndef BLINK_DECLARED_<sym>` + `extern <Blink signature>`; neither header goes into the unit.
> `readlink` gets the same guarded extern, dropped at build because the prologue reads unistd.h.
>
> My test for every option: **does the verdict of the test match the C the unit compiles?** Today it
> does not. E0861 compiles the call against `math.h`, then the unit calls `cos` through
> `extern double cos(double)`, a prototype the test never saw. A green test certifies a call the
> program does not make. That gap is the source of the remaining I0017s and of silent wrong-symbol links.
>
> ## Q0: yes
>
> The spec must say which prototype the call meets. 07:61 ("against the prototype in the header") and
> 07:115 ("the C signature that the declaration gives") contradict each other for Example A today.
>
> ## Proposal D-1 (recommend): the header governs; the test is the unit
>
> (a) **Yes.** `header:` puts the named header into the C that calls the symbol, with the same macros,
> flags, target and include paths that the prototype test uses. The test and the call read one context.
>
> (b) **The header's prototype governs** whenever a header that the calling C reads declares the
> symbol (the binding's own `header:` or a prologue header). The Blink signature is then the author's
> claim: E0861 checks the pointer and int-conversion part, `blink audit` marks scalar widths (as
> 07:61 already says). The Blink signature governs (`extern`) only when no header declares the
> symbol: no `header:`, and the prologue does not declare it. 07:115 holds only in that case.
>
> New pass/fail outcome, no compiler text read: the header is found (E0859 passes) but does not declare
> the symbol under the build's macros. That is E0861 at the `@ffi` line, exit 1, with its own message.
> Never a silent fall-back to the Blink extern: the author wrote a claim; the build must not drop it.
>
> The header's macros and other declarations must not change the C of any other Blink code. A clash
> there is I0017 (a compiler bug), so codegen must isolate it. How is a codegen chore, not spec.
>
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> // check: no error (reads no header)
> // build/test: E0859, E0861 pass; the call meets math.h `double cos(double)`; exit 0
>
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> // check: no error
> // build/test: the call meets `ssize_t readlink(const char *restrict, char *restrict, size_t)`;
> //   Ptr[U8] crosses as void * (§9.1.1), U64 -> size_t, ssize_t -> Int; E0861 passes; exit 0
>
> @ffi("memfd_create", header: "sys/mman.h")
> @trusted(audit: "MEMFD")
> fn c_memfd(name: Ptr[U8], flags: U32) -> I32 ! ()
> // check: no error
> // build, glibc: sys/mman.h hides memfd_create behind _GNU_SOURCE; the unit sets
> //   _POSIX_C_SOURCE 200809L only
> //   error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
> //   `sys/mman.h` does not declare `memfd_create` for this build
> //   help: remove `header:`; the call then uses this declaration's prototype, unchecked
> // build, x86_64-macos: the same E0861 at the @ffi line (no memfd_create on macOS),
> //   in place of a link error today
>
> @ffi("realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(path: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
> // build, x86_64-macos: the call meets stdlib.h's prototype and binds _realpath$DARWIN_EXTSN
> //   (D1 gives this already: the prologue reads stdlib.h)
>
> @ffi.opaque(header: "fts.h", name: "FTS")
> type Fts
> @ffi("fts_close", header: "fts.h")
> @trusted(audit: "FTS-CLOSE")
> fn c_fts_close(f: Ptr[Fts]) -> I32 ! ()
> // fts.h is NOT a prologue header, so D1 alone binds plain `fts_close`.
> // D-1, x86_64-macos: the call meets fts.h and binds fts_close$INODE64, which matches the
> //   FTS layout from fts_open$INODE64. Without D-1 it links clean and fails at run time.
> ```
>
> Tradeoffs:
> - One verdict. The same compile decides E0861 and the unit. I0017 goes back to meaning a compiler
>   bug, as the check-build promise wants.
> - Per-target correctness. Renames (`$DARWIN_EXTSN`, `$INODE64`, glibc `__REDIRECT`, LFS `*64` on
>   32-bit) come from the target's own headers, also under `zig cc` cross builds. The Blink-signature
>   extern binds the plain symbol: no error, wrong behavior. That failure has the worst possible
>   diagnostic surface: none.
> - Cost: a binding to a symbol behind a feature macro that works today (memfd_create on glibc) now
>   stops at build. The stop is at the `@ffi` line with a named fix, and it is the same stop the author
>   gets on macOS. I take that over a host-only link that passes CI on Linux.
> - Cost: codegen must keep header macros away from other generated C. The runtime prologue already
>   pays this cost for ~35 headers.
>
> ## Proposal D-2 (reject): `header:` is a name for the tests only
>
> Today's model plus D1. The call meets the Blink signature unless a prologue header declares the
> symbol. Example A gets `extern double cos(double)`; the fts example binds the wrong symbol on
> x86_64-macos and nothing reports it. E0861 tests a call the unit never makes, so a pass means less
> than it says. Cheaper to build, but whether a binding is checked hangs on a hidden list (which
> headers the prologue reads), which changes when the runtime adds an include.
>
> ## Cross-language
>
> Go cgo, Swift and Zig `@cImport` call through the header's prototype; renames come free. Rust
> bindgen emits `#[link_name = "\u{1}_realpath$DARWIN_EXTSN"]` from the header. Hand-written Rust
> `extern "C"` (the `libc` crate) repeats each rename by hand with `cfg_attr(..., link_name = ...)`:
> that is the upkeep D-2 pushes onto every Blink author.

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase A
>
> ## What main does today (probed, build/blink, gcc)
>
> ```blink
> @ffi("cos", header: "math.h")        // math.h is NOT in the prologue
> fn c_cos(x: Float) -> Float ! ()
> @ffi("labs", header: "stdlib.h")     // stdlib.h IS in the prologue; claim is wrong on purpose
> fn c_wrong(x: Float) -> Float ! ()
> ```
>
> - `cos`: unit gets `#ifndef BLINK_DECLARED_cos extern double cos(double)` — the Blink signature. math.h never enters the unit.
> - `labs`: no prototype; the call meets stdlib.h's `long labs(long)`. C converts double to long and back. It builds and prints `3`. The header governs.
> - So today the governing prototype depends on whether the *prologue* happens to include the header. That list is an implementation detail. An AI (or a human) cannot learn it from the spec. And 07:115 ("the symbol gets the C signature that the declaration gives") says the opposite of what the `labs` call does.
> - The E0861 test (spec, open) checks the call "against the prototype in the header". For `cos` the test would check against math.h while the unit calls through the Blink extern. The checked call is not the call that runs.
>
> ## Proposal M1 (recommended): `header:` is an `#include`; a visible header prototype governs
>
> Q0: yes. The spec must say it; 07:115 and 07:61 conflict today.
>
> (a) Yes. `header:` puts the named header into the C that calls the symbol, as `#include` does in C.
>
> (b) When a header that this C reads declares the symbol, the call goes through the header's prototype. The Blink signature is the author's claim; E0861 checks its pointer and shape parts against that prototype; scalar width stays the author's claim and `blink audit` marks it (already decided). When no header that the C reads declares the symbol (none named, or a feature macro hides it), the call goes through a prototype from the Blink signature, as D1 does now.
>
> One more rule keeps the test honest: the prototype test reads the same headers as the C that calls the symbol (the prologue plus every `header:` of the unit). Then the test verdict is the unit verdict, and I0017 stays a compiler bug.
>
> ### Examples
>
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> ```
> check: clean. build/test: E0859 test passes; E0861 passes; the unit reads math.h; the call meets `double cos(double)`. Runs.
>
> ```blink
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> ```
> check: clean. build/test: E0861 passes (`void *` to `const char *restrict` is fine per §9.1.1; `U64` to `size_t`). The call meets `ssize_t readlink(const char *restrict, char *restrict, size_t)`. The binding means the header's prototype; the Blink signature is the claim the test checks.
>
> ```blink
> @ffi("pipe2", header: "unistd.h")      // glibc hides pipe2 behind _GNU_SOURCE
> @trusted(audit: "PIPE2")
> fn c_pipe2(fds: Ptr[I32], flags: I32) -> I32 ! ()
> ```
> check: clean. build/test: unistd.h exists (E0859 passes); it declares no `pipe2` under the unit's macros, so the prototype test has nothing to compare and passes; the call goes through `extern int32_t pipe2(void *, int32_t)` from the Blink signature. Runs on glibc. `blink audit` marks it "not checked against the header". (On macOS no `pipe2` exists: a link stop, outside this ticket.)
>
> ```blink
> @ffi("realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(path: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
> ```
> check: clean. build/test on x86_64-macos: the call meets stdlib.h's prototype, so it binds `_realpath$DARWIN_EXTSN`, the variant a C program with `#include <stdlib.h>` gets (it allocates when `out` is null). On Linux: plain `realpath`. Same Blink source, same meaning as C on each target.
>
> ## Proposal M2 (reject): `header:` is only a name for E0859; the Blink signature always governs
>
> The unit would have to stop the prologue's own prototypes from meeting the call (separate TU or asm labels), or every prologue symbol hits I0017. On macOS the binding links the plain, legacy `realpath`: the program differs from the C program the author had in mind, with no error. Rust shows the cost: the `libc` crate hand-writes `link_name = "realpath$DARWIN_EXTSN"` per symbol, and it is a known bug source.
>
> ## Tradeoffs (AI/ML view)
>
> - **Decision points: zero added.** An LLM already writes `header:` the way it writes `#include`. M1 makes that intuition true. Today the meaning of `header:` is "existence test only", which no model will guess.
> - **One rule, no hidden list.** The outcome no longer depends on the prologue's include list. The spec can teach it in two sentences.
> - **The checked call is the run call.** E0861 means something only if the test and the unit see the same prototype.
> - **Near misses fail safe.** Models often write `Int` where C says `int`. With the header in scope, C converts; with the Blink extern, the return reads garbage upper bits with no error.
> - **Cost:** a wrong scalar claim converts silently (the `labs` probe prints `3`). That is already decided as the author's claim plus an audit mark; M1 does not make it worse. A header can declare a name that another binding spells its own way: D1's guard drops that binding's prototype, and the shared-headers rule makes E0861, not I0017, catch the rest.
> - **Teaching note for the writer:** recommend `header:` on every binding in docs and llms.txt, so the result never falls back to the Blink signature by accident. No new lint.
>
> ## Cross-language
>
> Zig `@cImport`, Go cgo and Swift's Clang importer all call through the header's prototype; the header governs. Rust `extern` uses the declared signature and needs per-symbol `link_name` for macOS renames. Models write the first three with fewer ABI bugs. M1 puts Blink in that group while keeping the Blink signature as a checked claim.

- **Minimalism:**

> # [ticket] — Minimalism seat (min), Phase A
>
> ## Q0: yes, but only to delete a contradiction
>
> "Do nothing" fails. The spec now says two things that cannot both be true:
>
> - §9.1:61, the prototype test: the call "the declaration gives" is compiled "against the prototype in the header". So the header's prototype is the one that judges the call.
> - §9.1:115: "The symbol gets the C signature that the declaration gives." So the Blink signature is the prototype.
>
> Today the build tests the call against the header (E0861), then (for a symbol no unit header declares) calls through a different prototype, the one from the Blink signature. We test one thing and ship another. The fix is to pick one prototype. No new syntax, no new error code, no new flag.
>
> ## Proposal M1 (recommended): `header:` names the prototype; the header governs
>
> One rule: **if a binding names a `header:`, the C call goes through that header's prototype. If it names none, the call goes through a prototype from the Blink signature.** The Blink signature is always what Blink code sees and what the effect and type checks use. It is never what C sees when a header exists.
>
> - (a) Yes. `header:` goes into the C that calls the symbol. The prototype test already reads the header in its own C file. M1 only makes the unit read the same header the test read, with the same feature macros (the decision notes already pin these).
> - (b) The header's. When any header the unit reads declares the symbol, no prototype from the Blink signature is written. This is D1's rule, made the spec's rule.
> - Without `header:`, D1 stays as it is: a guarded `extern <Blink signature>`, dropped when the unit's includes declare the symbol. This is the "I claim it; check nothing" path, the Rust `extern` model.
> - `blink check`: no change for any example. It reads no header (check-build-promise).
>
> ### Example A: `cos`
>
> ```blink
> @ffi("cos", header: "math.h")
> @trusted(audit: "LIBM-COS")
> fn c_cos(x: Float) -> Float ! ()
> ```
>
> - check: exit 0. build/test: header test pass, prototype test pass, unit reads math.h, call meets `double cos(double)`. Exit 0.
> - Wrong claim, `fn c_cos(x: Int) -> Int ! ()`: the prototype test passes (C converts `int64_t` to `double`), and the scalar is the author's claim that the audit marks. Under M1 the call meets math.h, so C converts the value: the program runs with a wrong-but-defined answer (truncated). Under "Blink signature governs", the unit writes `extern int64_t cos(int64_t)`: the argument goes in an integer register, `cos` reads a float register. That is garbage with no diagnostic. M1 turns an ABI fault into a value conversion, at no cost in surface.
>
> ### Example B: `readlink`
>
> ```blink
> @ffi("readlink", header: "unistd.h")
> @trusted(audit: "READLINK")
> fn c_readlink(path: Ptr[U8], buf: Ptr[U8], n: U64) -> Int ! FS.Read
> ```
>
> - check: exit 0. build/test: tests pass. The call meets `ssize_t readlink(const char *restrict, char *restrict, size_t)`. `Ptr[U8]` crosses as `void *` (§9.1.1), which C converts to `const char *` with no diagnostic. Exit 0. The binding means the header's prototype; the Blink signature is a claim, and the test checks the parts C can check.
>
> ### Feature macro: `pipe2` on glibc
>
> ```blink
> @ffi("pipe2", header: "unistd.h")
> @trusted(audit: "PIPE2")
> fn c_pipe2(fds: Ptr[I32], flags: I32) -> I32 ! ()
> ```
>
> - check: exit 0.
> - build/test on glibc (the unit sets `_POSIX_C_SOURCE 200809L`, not `_GNU_SOURCE`): unistd.h, as the unit sees it, does not declare `pipe2`. The prototype test's call is an implicit declaration, which gcc 14+, clang 16+ and `zig cc` reject. That is E0861 at the `@ffi` line, exit 1, before the unit compile. The help says the header does not declare the symbol on this target, and that a binding without `header:` takes its prototype from the Blink signature.
> - build/test on macOS: declared, exit 0.
> - So the "header hides the symbol" fear in the src/cg_decl.bl comment does not reach the unit: the test stops first. The fix the author has is to drop `header:` and own the claim. Honest, and no new knob such as a `define:` argument. YAGNI until a real binding needs one.
>
> ### macOS rename: `realpath`
>
> ```blink
> @ffi("realpath", header: "stdlib.h")
> @trusted(audit: "REALPATH")
> fn c_realpath(path: Ptr[U8], out: Ptr[U8]) -> Ptr[U8] ! FS.Read
> ```
>
> - check: exit 0. build/test on x86_64-macos: the call meets stdlib.h's prototype and binds `_realpath$DARWIN_EXTSN`, the symbol a C program gets. Exit 0.
> - Without `header:`: `extern` from the Blink signature binds plain `realpath`, the legacy symbol with other behavior. That is a silent wrong-symbol bug, and the reason "Blink signature governs" must not be the rule when a header exists. (realpath happens to be in the prologue today, so D1 already gets this right; M1 makes it true for every `header:`, not for a hand set.)
>
> ## Alternative M0 (rejected): `header:` is a test input only
>
> The unit never reads a binding's header; only the prototype test does. Spec text: §9.1:115 stays, §9.1:61 is reworded. Smaller change to the compiler, but the language then says: "we checked your call against prototype X, then called prototype Y." It keeps the scalar ABI fault and the macOS wrong-symbol fault for every symbol the prologue does not reach. Two prototypes is more surface than one.
>
> ## Tradeoffs (minimalism)
>
> - M1 adds zero syntax and zero codes. It removes a concept: the Blink signature as a C prototype, whenever a header is named.
> - Cost: a header in the unit can declare a symbol that another binding (with no `header:`) spells another way. D1's guard already drops that binding's prototype. The one case D1 does not guard (a wrapper whose call differs under the header) should also run the prototype test when a unit header declares its symbol, so it gets E0861, not I0017. That is an implementation note, not new spec surface.
> - Cost: a header with heavy macros now shapes the unit. The unit already reads the prologue headers, so this is a difference of degree, not of kind.
>
> ## Cross-language
>
> - Go cgo, Zig `@cImport`, Swift's Clang importer: the header governs. M1 with `header:`.
> - Rust `extern "C"`: the Rust signature governs; no header read. M1 without `header:`.
> - Blink gets both models from one existing optional argument. Nothing new to learn.

### Phase B — Debate (round 1)

- **Systems:**

> # [ticket] — sys, Phase B round 1
>
> ## V1: I move from V1-F to V1-E
>
> In Phase A I chose the fallback. The devops and min case changes my vote. My Phase A argument was "the header's prototype is the real ABI". V1-F breaks that argument without saying so. The author writes `header:` to get the header's prototype and its check. Under V1-F, glibc gives that author an unchecked Blink extern, and the only sign is a line in `blink audit`. That is cost hidden behind a word that promises the opposite. With V1-E, the generated C follows the source: `header:` means the call meets the header's prototype or the build stops. With no `header:`, the call meets the Blink extern. The C never takes a third path that the source does not show.
>
> Moderator fact 1 confirms that V1-F is a second codegen path. For a symbol that its own `header:` does not declare, the build must write the Blink extern, or every supported compiler rejects the implicit declaration. Two paths for one source line, picked by host headers, is less predictable than one path and a named stop.
>
> The host split cuts both ways. Under V1-E, `memmem` builds on macOS and stops on glibc. Under V1-F, it builds on both, checked on one and unchecked on the other. I take the loud split. The help ("remove `header:`; this declaration's prototype then governs, unchecked") is a one-line fix that states the cost.
>
> Condition, for the implementation (not a ballot item): V1-E is only usable if the pinned feature macros are wide, i.e. `_DEFAULT_SOURCE` or `_GNU_SOURCE` on glibc and `_DARWIN_C_SOURCE` on macOS, the same set on every host of a libc. With only `_POSIX_C_SOURCE 200809L`, `pipe2`, `memfd_create`, `accept4` and `strlcpy` all stop, and V1-E turns into friction. The macro set does not change the run-time cost, only which prototypes are visible.
>
> ## V2: unchanged, agree with aiml and min
>
> The test covers every binding whose symbol a header in the unit declares, whether or not that binding names `header:`. C takes one prototype per symbol, so the two bindings already share it. The test must say so at the `@ffi` line (E0861, exit 1), not as I0017. One side effect: adding `header:` to binding X can make binding Y, which has no `header:`, stop with E0861. That is correct, because it is a real conflict that C would reject anyway. The note of the error should name the header that declares Y's symbol.
>
> ## Facts
>
> Moderator fact 3: yes, my claims about the macOS renames and about which headers `libblink_std.h` reaches are reasoned, not probed. Neither changes the vote. Both are cases where the header the unit reads decides the answer, and S1 makes that header explicit.
>
> STABLE

- **Web/Scripting:**

> # [ticket] B1: Web/Scripting seat
>
> ## V1: I hold V1-F (fall back to the Blink extern)
>
> Devops and min make one fair point: under F, the same source meets a different prototype on each host (memmem: the header's prototype on macOS, the Blink extern on glibc). But both builds compile and both run correctly. That is not "passes CI on Linux, fails elsewhere". It works everywhere.
>
> The cost of V1-E falls on the 90% user:
> - The man page for `pipe2` or `memmem` says "unistd.h" / "string.h". The user writes exactly that, and the build stops with "`string.h` does not declare `memmem`". That is false from the user's point of view. To understand it, they have to learn about `_GNU_SOURCE`. Expect a Stack Overflow question per hidden symbol.
> - The help "remove `header:`" teaches users to delete `header:`. On macOS, that also deletes the check that would have run. So the fix makes the program less checked.
> - aiml wants the docs to recommend `header:` on every binding. Under E, following that advice breaks working builds. You cannot hold both positions.
>
> I concede devops' memfd_create case on macOS: the symbol does not exist there. Under F, the build writes the extern and the link fails. That stop should be clear and should name the binding. It is a link-error question, though, not a prototype question, and E0861 is the wrong code for it ("prototype mismatch" when no prototype exists). If the panel wants it, I would take a separate ticket.
>
> ## V2: I agree with sys
>
> The prototype test covers every binding whose symbol any header in the unit declares, including the prologue's headers and another binding's `header:`, not only bindings that name `header:`. A mismatch C would reject then stops as E0861 at the `@ffi` line, never as I0017 ("compiler bug"). For a user, "your line 12 disagrees with stdlib.h" is a fix. "Internal compiler error" is a bug report they cannot act on.
>
> ## Response to min's one option
>
> The wording "if a binding names `header:`, the header governs; if it names none, the Blink signature governs" is wrong for prologue symbols. `labs` with no `header:` is still declared by stdlib.h, which the unit reads, so writing a Blink extern conflicts with it. The rule has to key on *any header the unit reads that declares the symbol*, not on the binding's own `header:`. That is D1's guard, and the plt/aiml probes (labs prints 3) show it is how main behaves today.
>
> ## Facts
> Moderator fact 1 confirms that F must write the extern. It cannot leave the call undeclared, and D1's guard already does that. No new mechanism is needed.
> Fact 4 confirms the fts_open$INODE64 rename I gave without a probe, so the case for (a) now rests on a probed fact.
>
> OPEN: V1 (F vs E). I also want min to confirm the rule keys on "any unit header declares it", not on "binding names header:".

- **PLT:**

> # [ticket] — PLT seat, Phase B round 1
>
> ## V1: I move from V1-F to V1-E
>
> devops and min convinced me. The question is what `header:` means. Under V1-F it has two meanings, and the target picks one: "check my call against this header" where the header declares the symbol, and "nothing" where it does not. Only `blink audit` shows which one you got. Under V1-E it has one meaning on every target: the call meets this header's prototype, or the build stops. A rule that holds on every target beats one that quietly weakens.
>
> V1-E also needs no new test. Moderator fact 1: a call that meets no declaration does not compile under any supported C compiler. So the prototype test, run as in my Rule 3 (same wrappers, same includes, no Blink extern for a symbol whose binding names `header:`), fails, and E0861 follows from the existing pass/fail rule. It matches E0859: a header claim that is false on this host stops the build on this host.
>
> The cost is real (memmem builds on macOS, stops on glibc), but the stop is at the `@ffi` line with a fix that puts the choice in the source: drop `header:` and own the claim. That is more honest than a silent fallback.
>
> ## V2: agree with sys
>
> The test covers every symbol whose call meets a header prototype, whether or not its own binding names `header:`. Without that, the case sys names (no `header:`, but another binding's header declares the symbol) reaches the unit compile unchecked and stops as I0017, which must mean "compiler bug".
>
> ## On min's one-option wording
>
> It is per binding: "if it names none, the call goes through a prototype from the Blink signature". That is wrong in exactly the V2 case. In one C unit a symbol has one prototype. If any unit header declares it, the call meets that prototype, and a second `extern <Blink signature>` either conflicts (I0017) or D1's guard drops it. The rule must be per symbol:
> - a binding that names `header:`: that header must declare the symbol (else E0861);
> - any symbol a unit header declares: the call meets the header's prototype, and the test checks it;
> - otherwise: the guarded Blink extern.
>
> The ballot wording must be per symbol. If it is, I am ready to vote.
>
> ## Fact 4 (fts `$INODE64`, realpath `$DARWIN_EXTSN`)
>
> This settles (b) for me. On macOS a Blink extern for `fts_open` binds the 32-bit-inode symbol and reads an `FTSENT` with the wrong layout. That is wrong behavior, not a style choice. Only the header's prototype gives the right symbol, so where a header declares the symbol it must govern.
>
> STABLE

- **DevOps:**

> # [ticket] — devops, Phase B round 1
>
> ## V1: I move to V1-F (fall back to the Blink extern)
>
> web's memmem case changes my answer. Under V1-E the only fix is "remove `header:`". That turns off the
> check on every target, macOS included, where string.h declares memmem and E0861 could check it. So
> V1-E makes a cross-platform binding less checked overall. That is the wrong trade for a gate.
>
> Fact 1 (implicit declaration fails on every supported C compiler) shows V1-E is not needed for a
> correct compile: the build must write the Blink extern for a hidden symbol either way. What remains
> is whether the user is told. My conditions for V1-F:
>
> 1. `blink audit` marks it "not declared by its header on this target" (plt). Audit is the right
>    channel. A build warning that appears or not by host is noise in a CI matrix. Rows go away and
>    come back as the target changes, and `--strict` builds fail on one host only.
> 2. One verdict still holds: the test compiles the same wrapper as the unit (guarded extern kept), so
>    the test and the unit agree.
> 3. A symbol that the target lacks entirely (memfd_create on macOS) falls back and then fails at link.
>    That stop must name the `@ffi` line, not show raw linker text. This is a separate tooling gap with
>    or without this ticket, so I do not put it on this ballot. I will log it as friction if the panel
>    agrees.
>
> I drop my "never fall back without a word" line from Phase A. Audit is the word.
>
> ## V2: agree with sys
>
> The prototype test covers every binding whose call meets a header prototype in the unit, whether or
> not that binding names `header:`. Example: binding X names `header: "unistd.h"` for `read`. Binding Y
> binds `read` with no `header:` and a wrong pointer claim. Y's call meets unistd.h, so a mismatch must
> be E0861 at Y's `@ffi` line, exit 1. It must not be I0017. Otherwise I0017 stops meaning "compiler bug"
> (decisions/check-build-promise.md). Rule: the test's set of calls equals the unit's set of
> header-governed calls.
>
> ## Other points
>
> - min's one-option text: fine, if "goes through that header's prototype" reads "when that header
>   declares it on this target". Otherwise it contradicts V1-F.
> - sys's macro-collision note (`stat`, `major` against generated names): agree. A clash there is
>   I0017 and a codegen bug. Header order fixed (plt) keeps the C byte-identical across runs, which
>   the build cache needs.
>
> STABLE

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase B round 1
>
> ## V1: I move from V1-F to V1-E
>
> My Phase A picked V1-F. devops and min changed my mind, on learnability grounds.
>
> The rule an AI learns is min's one sentence: "if a binding names a `header:`, the call goes through that header's prototype." V1-F adds a silent exception: "unless the header hides the symbol under macros you cannot see or set." No model can predict that from the spec. It depends on glibc internals and on Blink's pinned feature macros. Under V1-F the author wrote `header:` to get a check, and gets no check and no error. The only sign is a line in `blink audit`, which a model writing code never reads.
>
> V1-E keeps the rule true with no exception. When the rule cannot hold, the author gets E0861 at the `@ffi` line, with one fix. A model applies that fix in one step:
>
> ```blink
> @ffi("memfd_create", header: "sys/mman.h")
> @trusted(audit: "MEMFD")
> fn c_memfd(name: Ptr[U8], flags: U32) -> I32 ! ()
> // build, glibc: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
> //   `sys/mman.h` does not declare `memfd_create` for this build
> //   help: remove `header:`; the call then uses this declaration's prototype, unchecked
> ```
>
> Conditions for my vote:
> - The message must say that the header does not declare the symbol in this build. It must not imply that the header or the symbol is missing. The man page tells the author to `#define _GNU_SOURCE`, so the help must not point at a feature-macro knob, because Blink has none.
> - I withdraw my Phase A note "recommend `header:` on every binding". The docs say: name `header:` when that header declares the symbol. E0861 marks the cases where it does not.
>
> V1-E also gives one stop on every host. memmem builds on macOS and stops on glibc, both at the `@ffi` line. Under V1-F, Linux CI passes and the failure turns up somewhere else.
>
> Moderator fact 1 (a call with no declaration does not compile) does not decide V1. D1 already writes the extern for V1-F. Under V1-E that case never reaches the unit.
>
> ## V2: agree with sys
>
> The prototype test covers every binding whose symbol any header in the unit declares. That includes prologue headers and headers that other bindings name, not only bindings that name `header:`. This is my Phase A "test verdict = unit verdict" rule. Without it, a binding with no `header:` hits I0017 because of another binding's header, and I0017 would lie when it says "a bug of the compiler".
>
> Fact 4 (fts.h `$INODE64`, realpath `$DARWIN_EXTSN`) confirms why the header must govern when it declares the symbol. It does not decide V1.
>
> STABLE

- **Minimalism:**

> # [ticket] — min, Phase B round 1
>
> ## V1: I move to V1-F (fall back to the Blink extern)
>
> My Phase A rule ("names a `header:` → that header's prototype") breaks on V1 anyway, so the rule I take is the plain one under D1: **if a header the unit reads declares the symbol, its prototype governs; if none does, the guarded Blink-signature extern governs.** That is one rule, and it already ships (fact 2: the `BLINK_DECLARED_<sym>` guard). Fact 1 shows only that the extern must stay when nothing declares the symbol, and D1's guard already keeps it. V1-F costs no new code path.
>
> V1-E adds a second rule ("a named header must declare the symbol, or E0861") and an error path. It also makes the same source stop on glibc and build on macOS (`memmem`, web's example), which is a host split we add on purpose. Devops's case for V1-E is the Linux-only symbol (`memfd_create`). On macOS that symbol fails under both variants: at E0861 under V1-E, or at link (E0857) under V1-F. So V1-E only adds a stop on the host where the program works. Its fix, "remove `header:`", also throws away the check on every host where the header does declare the symbol. I was wrong in Phase A to call that honest. It is a cliff.
>
> The audit mark plt proposes ("not declared by its header on this target") does no harm and adds no error. I do not need it, and I do not oppose it.
>
> ## V2: agree with sys, in a smaller form
>
> There is no reason to choose which bindings the test covers. **The prototype test compiles every `@ffi` wrapper the unit compiles, with the unit's includes and macros.** For a binding that no header declares, the guarded extern stays and the test passes trivially. For one that a header declares, whether or not that binding named it, the header's prototype judges the call. So a binding without `header:` whose symbol another binding's header declares gets E0861, not I0017. One rule, no list. This replaces my Phase A implementation note.
>
> ## Other points
> - I agree that §9.1:115 is rewritten so the Blink signature governs the Blink side (sys).
> - Fact 4 (fts_open/fts_close `$INODE64`, realpath `$DARWIN_EXTSN`) confirms that a header must govern when one declares the symbol. A Blink extern binds the legacy symbols, and on `$INODE64` the struct layout differs. This changes nothing in V1-F, because these headers do declare the symbols.
> - I agree with no knob for feature macros, and no new lint (aiml).
>
> STABLE

### Phase C — Vote

# [ticket] — Phase C ballot (silent vote)

Round 1 replies: b9/[ticket]/<seat>-B1.md (read all six). Five seats wrote STABLE; web wrote "OPEN: V1".

## Decided (every seat agrees; not on the ballot)
- Q0 yes; (a) yes: `header:` puts the named header into the unit, after the prologue, in a fixed order.
  The prototype test reads the same includes and feature macros as the unit. No user knob for feature macros.
- (b): when a header the unit reads declares the symbol, the call goes through that header's prototype.
  The Blink signature governs the Blink side and is the author's claim; E0861 checks it.
- With no unit header that declares the symbol, the guarded `extern <Blink signature>` governs.
- V2 (6-0 in round 1): the prototype test compiles every `@ffi` wrapper the unit compiles, with the unit's
  includes. A binding with no `header:`, whose symbol another header in the unit declares, gets E0861 at
  its `@ffi` line, exit 1, never I0017.

## Q-V1 — the binding's `header:` is found, but it does not declare the symbol under the unit's feature macros

**V1-F (fall back to the guarded Blink extern; `blink audit` marks it)** — round 1: web, devops, min.
(min:) "if a header the unit reads declares the symbol, its prototype governs; if none does, the guarded
Blink-signature extern governs. ... V1-F costs no new code path."
(devops:) "`blink audit` marks it "not declared by its header on this target" (plt). ... A build warning
that appears or not by host is noise in a CI matrix."
Result: `@ffi("memmem", header: "string.h")` builds on glibc and macOS. glibc: unchecked Blink extern,
audit mark. macOS: string.h's prototype, E0861 checks it.

**V1-E (E0861 at the `@ffi` line, exit 1)** — round 1: sys, plt, aiml.
(aiml:)
```blink
@ffi("memfd_create", header: "sys/mman.h")
@trusted(audit: "MEMFD")
fn c_memfd(name: Ptr[U8], flags: U32) -> I32 ! ()
// build, glibc: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1
//   `sys/mman.h` does not declare `memfd_create` for this build
//   help: remove `header:`; the call then uses this declaration's prototype, unchecked
```
(plt:) "`header:` ... has one meaning on every target: the call meets this header's prototype, or the build
stops."
Result: `@ffi("memmem", header: "string.h")` builds on macOS and stops with E0861 on glibc.

## Q-M — which feature macros the unit and the test define (raised by sys; no seat opposed)
(sys:) "the pinned feature macros [are] wide, i.e. `_DEFAULT_SOURCE` or `_GNU_SOURCE` on glibc and
`_DARWIN_C_SOURCE` on macOS, the same set on every host of a libc. With only `_POSIX_C_SOURCE 200809L`,
`pipe2`, `memfd_create`, `accept4` and `strlcpy` all stop".
- **M-W (wide set, as sys states)**
- **M-N (no rule in the spec; the set stays an implementation choice)**
Result under M-W: `pipe2`, `memfd_create`, `accept4`, `memmem` are declared by their glibc headers, so the
header governs and E0861 checks them under either V1 option.

## Writer notes (not on the ballot)
- plt, web: the rule is per symbol, not per binding ("any header the unit reads declares it").
- aiml: if V1-E wins, the message says the header does not declare the symbol *in this build*; it must not
  imply the header or symbol is missing, and must not point at a feature-macro knob. aiml withdraws
  "recommend `header:` on every binding".
- sys: the E0861 note for the V2 case names the header that declares the symbol.
- devops (follow-up friction, not this ticket): a symbol the target lacks fails at link; that stop should
  name the `@ffi` line.

## Your vote
Write [scratch path] with, for each of Q-V1 and Q-M:
1. Vote (the option label).
2. Reasoning (2–4 sentences, your domain).
3. Concern (one sentence: what could go wrong with the option that wins).
Then reply to team-lead with "voted" and your two labels. Do not message other seats.

- **Systems:**

> # [ticket] — sys, Phase C vote
>
> ## Q-V1
> 1. Vote: **V1-E**
> 2. Reasoning: with V1-E, the source line decides the C. `header:` means the call meets that header's prototype or the build stops. The host's headers never pick silently between a checked call and an unchecked one. Under V1-F, the same line binds the header's prototype on one host and an unchecked Blink extern on another, and only a line in `blink audit` shows the difference. That is a cost hidden under a word that promises a check. Under M-W, glibc and Darwin declare the common Linux and BSD extras, so V1-E fires only on a symbol that the target's libc really does not offer to this build. There the honest answer is to stop at the `@ffi` line.
> 3. Concern: a binding to a symbol on only one platform (for example `memfd_create`) built on another host stops with E0861 where V1-F would have built and failed later at link or run time. The help must make "drop `header:` or gate the binding per target" plain.
>
> ## Q-M
> 1. Vote: **M-W**
> 2. Reasoning: the feature-macro set decides which prototypes a header shows, so it decides which programs build and which calls E0861 checks. Users see that behavior, so it is not a free choice for the implementation. A wide, pinned set (`_DEFAULT_SOURCE`/`_GNU_SOURCE` on glibc, `_DARWIN_C_SOURCE` on macOS, the same on every host of a libc) costs nothing at run time and makes `pipe2`, `accept4` and `memmem` checked calls, not exceptions. Without it, V1-E is friction and V1-F leaves most of the useful glibc surface unchecked.
> 3. Concern: `_GNU_SOURCE` changes the meaning of a few names (the GNU `strerror_r` returns `char *`, `basename`), so a binding written against the POSIX prototype gets E0861 or a different function, and the docs must name the set.

- **Web/Scripting:**

> # [ticket] C: Web/Scripting seat
>
> ## Q-V1: V1-F
> Reasoning: The user writes the header the man page names. A build that stops with "this header does not declare this symbol" contradicts the man page, so the user has to learn feature macros just to get unstuck. The only help available is "remove `header:`", which teaches people to delete the thing that turns on checking, and on macOS that loses a check that would have run. F builds on every host, costs no new code path, and `blink audit` records the gap where an auditor will look.
> Concern: Some users will assume a binding is checked because it names `header:`, when on glibc it quietly runs on the unchecked Blink extern. The audit mark is the only signal they get.
>
> ## Q-M: M-W
> Reasoning: A wide feature-macro set (`_DEFAULT_SOURCE`/`_GNU_SOURCE` on glibc, `_DARWIN_C_SOURCE` on macOS) means that what the man page lists is what the header declares. That makes the V1 case rare under either option. It is user-visible, because it decides which bindings get checked, so the spec should state it rather than leave it to the implementation.
> Concern: `_GNU_SOURCE` picks the GNU variants (`strerror_r` returns `char *`, `basename`), so a binding written to the POSIX man page meets the GNU prototype. E0861 catches the int/pointer swap, but the message must name the header's prototype so the user can tell why.

- **PLT:**

> # [ticket] — PLT seat, Phase C vote
>
> ## Q-V1
>
> 1. Vote: **V1-E**
> 2. Reasoning: `header:` is a claim the author writes in the source ("this header declares the symbol"), and a claim the build checks should hold or fail the same way on every target. Under V1-F the same line means "checked" on macOS and "unchecked" on glibc, and only `blink audit` says which. That is two meanings picked by the host. V1-E needs no new mechanism: a call that meets no declaration fails the existing pass/fail test (moderator fact 1), so E0861 follows from the rule we already have. The author who wants no check says so in the source by dropping `header:`.
> 3. Concern: if V1-F wins, a test passed on macOS gives false trust on glibc, so the audit mark must be prominent and the docs must say plainly that `header:` can be silently unchecked.
>
> ## Q-M
>
> 1. Vote: **M-W**
> 2. Reasoning: the feature macro set decides which symbols a header declares. Under the rule we decided, that decides which prototype governs the call and whether E0861 fires, so it changes what a program means. An input that changes meaning belongs in the spec, fixed per libc, or "one source gives one verdict" holds only per compiler build. The wide set also leaves very few V1 cases, so the V1 choice matters less.
> 3. Concern: a wide set (`_GNU_SOURCE`) also turns on GNU forms of some symbols (`strerror_r` returns `char *`, `basename` differs), so a binding written against the POSIX form now meets the GNU prototype. E0861 finds the int/pointer return mismatch, but not every change.

- **DevOps:**

> # [ticket] — devops, Phase C vote
>
> ## Q-V1: V1-E
>
> Reasoning: I moved to V1-F in round 1 for one reason. With a narrow macro set, V1-E stops `memmem` on
> glibc, and the only fix also turns off the check on macOS. M-W (below) removes that case, because
> glibc then declares `memmem`, `pipe2`, `memfd_create` and `accept4`. What V1 still covers is mostly a
> symbol that the target does not have in that header at all (`memfd_create` on macOS). Under V1-F that
> falls back and then fails at link with raw linker text. Under V1-E it is E0861 at the `@ffi` line,
> exit 1, and the message names the header and the target. That diagnostic is better: the `@ffi` line,
> before the unit compile, from a pass/fail test.
>
> Concern: a symbol that one libc declares in a different header from another (musl or a BSD against
> glibc) stops on that target only, and the author's only fix is to drop `header:` on every target.
>
> ## Q-M: M-W
>
> Reasoning: if the spec says nothing about the feature macros, whether a binding is header-checked
> depends on a runtime implementation detail that can change in any release. CI results would then
> change with no source change. A fixed wide set per libc (`_GNU_SOURCE`/`_DEFAULT_SOURCE` on glibc,
> `_DARWIN_C_SOURCE` on macOS) makes the verdict a function of source plus target only. That is what the
> check-build promise asks for. It also turns the common feature-macro cases into header-governed calls
> that E0861 checks, which is the point of `header:`.
>
> Concern: a wide set exposes more of each header's macros (`major`, `minor`, `stat` on glibc) to the
> generated C, so a name clash is an I0017 that codegen must prevent, and a libc update can add new
> clashes.

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase C vote
>
> ## Q-V1: V1-E
>
> Reasoning: An AI learns `header:` from one sentence: "the call meets this header's prototype, or the build stops." V1-F adds an exception that depends on libc feature macros nobody can see from the spec. The author asked for a check, gets none, and the only sign is an audit line that a model writing code never reads. V1-E fails at the `@ffi` line with one fix a model can apply in a single step. With M-W, V1-E fires rarely, so its cost is small.
>
> Concern: if the E0861 text for this case reads like "header not found" or names `_GNU_SOURCE`, a model will chase a knob that does not exist and not remove `header:`.
>
> ## Q-M: M-W
>
> Reasoning: Models copy symbols from man pages, and man pages assume `_GNU_SOURCE`/`_DEFAULT_SOURCE` on glibc and the full Darwin set on macOS. A wide, fixed set makes `pipe2`, `memfd_create`, `accept4` and `memmem` just work with `header:` checked. That removes most V1 cases under either option. The set is visible to the user (it decides which prototype governs), so the spec must state it: under M-N an AI cannot learn which symbols a header gives.
>
> Concern: `_GNU_SOURCE` changes some prototypes, for example GNU `strerror_r` returns `char *` (bootstrap/runtime_errno.h already works around it). A binding written to the POSIX form then stops with E0861 on glibc only, so the docs should show that case. `_DEFAULT_SOURCE` would avoid it where it is wide enough.

- **Minimalism:**

> # [ticket] — min, Phase C vote
>
> ## Q-V1: V1-F
>
> Reasoning: V1-F is the one rule that already ships. If a header the unit reads declares the symbol, its prototype governs; if none does, the guarded Blink extern governs. V1-E adds a second rule and an error path. That path stops a build on the host where the program works (glibc `memmem`), and its fix (drop `header:`) also removes the check on every host where the header does declare the symbol. plt's "one meaning on every target" is bought with a host split in what builds, which is the worse kind of split.
>
> Concern: an author can name a `header:` that never declares the symbol on their main host, and read the build as checked when it is not. The audit mark is the only place that says so.
>
> ## Q-M: M-N
>
> Reasoning: under V1-F the macro set changes only whether a call is checked, never whether it builds, so the spec does not need to fix it. A wide set is not free. `_GNU_SOURCE` changes prototypes, not just visibility: `strerror_r` returns `char *` under it (bootstrap/runtime_errno.h:13 deals with exactly this), and `basename` changes too. A wide set written into the spec locks the language to those variants on every libc. The spec already says the test and the unit share one set, and that is the rule that matters. Which set it is stays an implementation choice the compiler can widen when a real binding needs it.
>
> Concern: without a stated set, an implementation can narrow the macros, and a binding that was checked becomes unchecked with no notice in the spec.

### Phase D — Re-vote

# [ticket] — Phase D re-vote (Q-V1 only)

Phase D replies: b9/[ticket]/<seat>-D.md (read all six). All six wrote STABLE.

Q-V1 — the binding's `header:` is found, but it does not declare the symbol under the unit's (wide, M-W)
feature macros.
- **V1-F**: fall back to the guarded Blink extern; `blink audit` marks it.
- **V1-E**: E0861 at the `@ffi` line, exit 1.
Options and snippets as in ballot-C.md.

Fact (moderator): sections/07 line 168 says "Blink has no conditional compilation." There is no per-target
gate for a binding today.

Write [scratch path]
1. Vote (V1-F or V1-E). 2. Reasoning (2–4 sentences). 3. Concern (one sentence).
Then reply to team-lead with "voted" and your label. Do not message other seats.

- **Systems:**

> # [ticket] — sys, Phase D (Q-V1)
>
> V1-E holds. Under M-W, glibc `memmem`/`pipe2`/`accept4` are declared, so min's main case is gone. What V1 still covers:
>
> 1. **The target's libc does not have the symbol** (`memfd_create` on macOS, `strlcpy` on glibc < 2.38). E: E0861 at the `@ffi` line, exit 1. F: an unchecked extern, then raw linker text with no Blink line (devops's point).
> 2. **The symbol is in a different header on this libc, often with a different signature.** `sendfile` is `sys/sendfile.h` with 4 args on Linux and `sys/socket.h` with 6 args on macOS and FreeBSD. A binding `@ffi("sendfile", header: "sys/sendfile.h")` built for macOS fails the header test (E0859) on its own. But on a libc where the header exists without the symbol, F falls back to the Linux claim and may link against a symbol with another ABI: a wrong call with no error. E stops it. This is the case I care most about. A header that does not declare the symbol is strong evidence that the claim was written for another platform.
> 3. **A symbol still hidden under the wide set** (rare). E: E0861. F: unchecked.
>
> To web: the error says "does not declare it *in this build*", which is true and does not contradict the man page of another libc. To min: "drop `header:`" is the escape hatch, not the expected fix. In cases 1 and 2 the right fix is a binding per target, and the help should say that first. To devops's concern: a symbol that musl and glibc put in different headers usually has different prototypes too, so one binding per target was already right.
>
> V1-F costs no new rule, but it buys a silent path in exactly the cases where the claim is most likely wrong.
>
> STABLE

  Re-vote:

> # [ticket] — sys, Phase D re-vote
>
> 1. Vote: **V1-E**
> 2. Reasoning: the moderator's fact takes away the "binding per target" fix I pointed to, so I withdraw that part of my help text. The vote stands anyway. Without conditional compilation, a binding to a symbol that the target lacks (`memfd_create` on macOS) cannot work on that target under either option. E says so at the `@ffi` line, and F says so in raw linker text. A binding whose signature differs by platform (`sendfile`) has no correct portable form at all. There F can link a wrong call with no error, and E stops it.
> 3. Concern: since Blink has no per-target gate, the only fix under E (drop `header:`) also drops the check on targets where the header does declare the symbol. That cost stays until conditional compilation or per-target bindings exist.

- **Web/Scripting:**

> # [ticket] D: Web/Scripting seat
>
> I move F to E. My case for F was the glibc `memmem` stop: the man page says string.h, the build says no, and the only fix turns off checking. M-W removes that case. Under M-W, glibc declares memmem, pipe2, accept4 and memfd_create, so the header governs and E0861 checks them under either option.
>
> What V1 still covers under M-W:
> 1. The target does not have the symbol at all (`memfd_create` on macOS). F falls back to the extern and then fails at link with raw linker text that does not point at any Blink line. E stops with E0861 at the `@ffi` line, exit 1. For a JS/Python dev, E is clearly better: a stop at their own line, in Blink terms.
> 2. The symbol is in a different header on another libc (devops' musl/BSD concern). F builds, if that libc has the symbol, on the unchecked extern. E stops on that target only. This is the one case where E costs the user something, and it is rare.
> 3. My own concern on F was a binding that names `header:` but silently runs unchecked. E removes that: `header:` always means "checked against this header, or the build stops". That is one meaning, which is easier to teach.
>
> Conditions (writer, not ballot): the E0861 text says the header does not declare the symbol *for this target*. It must not say the header or symbol is missing, and it must not mention feature macros. The help names both fixes, drop `header:` or gate the binding per target, as sys asks.
>
> STABLE

  Re-vote:

> # [ticket] D re-vote: Web/Scripting seat
>
> 1. Vote: V1-E
>
> 2. Reasoning: Under M-W, the main case left is a symbol the target does not have. V1-E stops at the user's own `@ffi` line in Blink terms. V1-F fails later with raw linker text that names no Blink line. The no-gate fact removes the "gate per target" fix, so for the rare musl/BSD different-header case the only fix is to drop `header:` on every target. I accept that cost so that `header:` keeps one meaning: checked against this header, or the build stops.
>
> 3. Concern: The help must not offer a per-target gate, because none exists. For a symbol the target lacks, "drop `header:`" alone would only move the stop to the linker, so the help has to say the symbol is not available for this target.

- **PLT:**

> # [ticket] — PLT seat, Phase D
>
> I stay with **V1-E**.
>
> ## Cases V1 still covers under M-W
>
> 1. **The target's libc does not have the symbol** (`memfd_create` from sys/mman.h on macOS). V1-F: fall back to the Blink extern, then the link fails with raw linker text and no `@ffi` line. V1-E: E0861 at the `@ffi` line, exit 1.
> 2. **Another libc declares it in a different header** (musl or a BSD against glibc). V1-F: unchecked extern; it links if the library has the symbol, and the author never learns the check was off. V1-E: E0861 on that target only.
> 3. **The author names the wrong header, and that header exists** (`header: "stdio.h"` for `memmem`). V1-F: builds unchecked on every host, so `header:` claims a check that never runs. V1-E: E0861 on every host. Only V1-E catches this.
>
> ## Responses
>
> - min, "a second rule and an error path": the test compiles the call, and a call that meets no declaration does not compile (moderator fact 1). So E0861 comes from the existing test. V1-F is the one that needs an extra rule: "write the extern when the named header does not declare the symbol".
> - web, "contradicts the man page": under M-W, the build and the man page agree for every symbol the target's libc offers. Where they disagree, the target really lacks the symbol (case 1), and the build should say so at the `@ffi` line.
> - devops's concern (case 2) is real, but V1-F does not fix it. It hides it. The help should say "drop `header:`", plus any way the language has to pick a binding per target. It must not invent one.
>
> STABLE

  Re-vote:

> # [ticket] — PLT seat, Phase D re-vote
>
> 1. Vote: **V1-E**
> 2. Reasoning: `header:` is a claim the build checks, and it must mean the same thing on every target: the call checks against this header's prototype, or the build stops at the `@ffi` line. E0861 comes from the existing pass/fail test, because a call that meets no declaration does not compile. So V1-E adds no rule, and V1-F is the one that needs a fallback rule. V1-E alone catches a wrong header that exists, and it turns the "target lacks the symbol" case from raw linker text into a stop at the source line.
> 3. Concern: Blink has no conditional compilation (07:168). So a symbol that two libcs declare in different headers has one fix, drop `header:` on every target, and the help must say exactly that, with no mention of a per-target gate.

- **DevOps:**

> # [ticket] — devops, Phase D
>
> Position: V1-E holds.
>
> Under M-W, V1 still covers these cases:
>
> 1. **The target's libc lacks the symbol** (`memfd_create` with `header: "sys/mman.h"` on macOS).
>    F: the build writes the Blink extern and fails at link with raw linker text, at no Blink line.
>    E: E0861 at the `@ffi` line, exit 1, before the unit compile.
> 2. **The libc has the symbol but declares it in another header, often with another signature.**
>    `sendfile` with `header: "sys/sendfile.h"`: Linux takes 4 arguments. macOS declares a 6-argument
>    `sendfile` in sys/socket.h and has no sys/sendfile.h, so there E0859 fires first. The
>    same shape with a header that does exist on both hosts is the real hazard. F: the symbol links and
>    the unchecked 4-argument call runs against a 6-argument function. No error at all, wrong behavior
>    at run time. E: E0861 on that target. This is the worst case of F, and it is the strongest case for E.
> 3. **A macro outside the M-W set hides the symbol.** This is rare. Both options act as in 1 or 2.
>
> Responses:
> - min's and web's `memmem`-on-glibc case does not happen under M-W: `_GNU_SOURCE` declares it. Each
>   stop that remains is on a host where the program would fail to link or would call the wrong ABI, so
>   "stops on the host where it works" no longer applies.
> - web, "contradicts the man page": the man page for `memfd_create` names `_GNU_SOURCE`, which M-W
>   gives. On macOS there is no man page to contradict.
> - min, "second rule": E adds one pass/fail probe the test already makes ("is it declared?"). F
>   needs the same probe to choose the guard, so E adds no new detection. The only new part is the message.
> - sys's help text ("drop `header:` or gate the binding per target"): agree. That answers my concern.
> - Fact 2 (strerror_r): independent of V1. A binding of `strerror_r` that returns `-> I32` fails E0861 on
>   glibc under M-W (int-conversion), at the `@ffi` line. That is the behavior we want.
>
> STABLE

  Re-vote:

> # [ticket] — devops, Phase D re-vote
>
> 1. Vote: V1-E
>
> 2. Reasoning: under M-W, V1 covers only two cases. In one, the target lacks the symbol, so no fix makes
> the program work there. In the other, the target declares the symbol elsewhere with another signature,
> so the binding is wrong there. In both, V1-E gives a pass/fail stop at the `@ffi` line before the unit
> compile. V1-F gives raw linker text, or no error and wrong behavior at run time. The moderator's fact
> (no per-target gate) leaves "drop `header:`" as the only fix. But under V1-E the author makes that
> choice knowingly, with the target named. Under V1-F the same unchecked call happens with no word at
> build time.
>
> 3. Concern: with no per-target gate, the E0861 help must not offer "gate the binding per target". It
> can only offer "drop `header:`", and that turns a portable author's error into an unchecked call on
> every target.

- **AI/ML:**

> # [ticket] — AI/ML seat, Phase D
>
> I hold **V1-E**.
>
> ## What V1 still covers under M-W
> 1. **The target's libc does not have the symbol at all** (`memfd_create`, `pipe2` on macOS; `strlcpy` on glibc before 2.38). V1-F falls back to the Blink extern and fails at link with raw linker text and no Blink line. A model cannot map that text back to a binding. V1-E gives E0861 at the `@ffi` line, exit 1, and the build stops where the cause is.
> 2. **The symbol is in a different header on another libc** (musl or a BSD against glibc). V1-F builds there unchecked. V1-E stops on that target only, and the fix is to drop `header:` (or gate the binding per target, as sys says). This is the real cost of E. It is rare, and it fails loudly at the right line. F's cost is silent.
>
> ## Responses
> - min and web, glibc `memmem`: M-W declares it, so the header governs and E0861 checks it on both hosts. The case that made F look right is gone. The man page no longer contradicts the build: the header the man page names declares the symbol.
> - min, "second rule": V1-E is the first rule with no exception, "the call meets this header's prototype, or the build stops". V1-F is the rule with a hidden exception, "...unless the header hides it, then unchecked". For a model, a rule with an error path is easier to learn than a rule with a silent branch.
> - Writer note: the E0861 help for case 2 names both fixes (drop `header:`, gate per target) and does not mention feature macros.
>
> STABLE

  Re-vote:

> # [ticket] — AI/ML seat, Phase D re-vote
>
> 1. Vote: **V1-E**
>
> 2. Reasoning: The rule "the call meets this header's prototype, or the build stops" has no hidden branch. A model can learn it from the spec alone and repair any failure at the `@ffi` line in one step. Under M-W, V1-E fires mostly where the target's libc lacks the symbol. There V1-F gives raw linker text that names no Blink line, which is the worst failure for an AI to debug. I withdraw "gate the binding per target" from my Phase D writer note. The moderator's fact shows Blink has no such gate, so the help names only "remove `header:`".
>
> 3. Concern: with no per-target gate, a symbol that another libc declares in a different header forces the author to drop `header:` everywhere, and loses the check on the targets where it would have passed.

- **Minimalism:**

> # [ticket] — min, Phase D
>
> ## Position: I move to V1-E
>
> My case for F was the glibc `memmem` stop. M-W removes it, as devops says. What V1 still covers under M-W:
>
> 1. **The target lacks the symbol in that header** (`memfd_create` on macOS). F: the guarded extern stays, and the build fails at link with linker text, far from the `@ffi` line. E: E0861 at the `@ffi` line, exit 1, before the unit compile. Both stop. E stops earlier, at the right line, with a named code. So E does not add an error. It replaces a worse one, and that is the subtraction test passing.
> 2. **Another libc declares the symbol in a different header** (musl or a BSD against glibc). F: builds, with the call unchecked on that target. E: stops on that target only. This is E's one real cost. It is rare under M-W, and I accept it.
> 3. **The author names the wrong header on every target.** F: silently unchecked everywhere, with only an audit mark. E: E0861 on the author's own host. This is where E's "`header:` means one thing" pays.
>
> E also needs no new mechanism. Under the test, a call that meets no declaration already fails on every supported C compiler (fact 1 of B1). V1-E only drops the guard for a binding that names its header.
>
> ## Responses
> - web: the man page names the header under some macro set. Under M-W, a mismatch with the man page is now a real target difference, worth a stop.
> - sys: Blink has no conditional compilation, so the help must not say "gate the binding per target". The only fix it can offer is "drop `header:`", with the note that the call is then unchecked on every target.
>
> STABLE

  Re-vote:

> # [ticket] — min, Phase D re-vote
>
> 1. Vote: V1-E
>
> 2. Reasoning: under M-W, V1-E's stop mostly replaces a stop that already happens. A target that lacks the symbol (`memfd_create` on macOS) fails at link today, with linker text far from the source. Under V1-E it fails as E0861 at the `@ffi` line. V1-E also catches a wrong `header:` on the author's own host, so `header:` keeps one meaning, and it needs no new mechanism: a call that meets no declaration already fails the test. Its one real cost, a symbol that another libc declares in a different header, is rare under M-W.
>
> 3. Concern: Blink has no conditional compilation, so an author hit by the different-header case has only one fix, "drop `header:`", and that loses the check on every target. The help must say so plainly and must not suggest a per-target gate.


### Final Spec

```blink
@ffi("cos", header: "math.h")
@trusted(audit: "LIBM-COS")
fn c_cos(x: Float) -> Float ! ()               // the call goes through `double cos(double)` of math.h

@ffi("pipe")
@trusted(audit: "UNISTD-PIPE")
fn c_pipe(fds: Ptr[SockIn]) -> I32 ! ()
// error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1, when another header
// of the unit (`unistd.h`) declares `pipe`; the note names `unistd.h`

@ffi("memfd_create", header: "sys/mman.h")
@trusted(audit: "MMAN-MEMFD-CREATE")
fn c_memfd_create(name: Ptr[U8], flags: U32) -> I32 ! ()
// error[ForeignPrototypeMismatch] (E0861) on macOS: `sys/mman.h` does not declare
// `memfd_create` for this target
// help: remove `header:`; the call then uses this declaration's prototype, unchecked
```
