[< All Decisions](../DECISIONS.md)

# A `Ptr` at an `@ffi` Call — Design Rationale

**Gap:** §9.1 said `blink check` does not look at C headers, and that a wrong prototype can cause `GeneratedCDidNotCompile` (I0017, exit 101). `Ptr[T]` lowers to `T*`. So a `Ptr` to an `@ffi.struct` that the header takes as a pointer to a different struct stopped the build with an internal compiler error. This program passes `blink check`:

```blink
@ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }

@ffi("connect", header: "sys/socket.h")
fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! () {}

fn main() {
    with ffi.scope() as scope {
        let a: Ptr[SockIn] = scope.alloc[SockIn]()
        io.println("{c_connect(-1, a, 16)}")
    }
}
```

`blink build` stopped with I0017 and exit 101, because `connect` takes `const struct sockaddr *`. C programs pass a `sockaddr_in` or a `sockaddr_in6` to it through a cast, and Blink has no pointer cast.

This decision relates to [What a Clean `blink check` Promises](check-build-promise.md), Q3a. Q3a said that a header test finds a missing header (E0859) and that a C compiler failure that remains is I0017. That still holds. A wrong prototype that the new prototype test finds is now E0861, and I0017 keeps the wrong prototype that the test does not find.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | What happens to a `Ptr` at the C call | `P-W1n`: at an `@ffi` call argument, one level deep, `Ptr[T]` passes to a `Ptr[Void]` parameter (a coercion, not a subtype; E0601 reads the argument's own type). C keeps the pointee type only for an `@ffi.struct` or `@ffi.opaque` pointee (its `name:`). Every other pointee erases to `void *` at any depth: `Void`, every scalar, and a `Ptr` to those. A `Ptr` return reads through an implicit conversion | 5-1 (Minimalism dissented) |
| Q2 | A build-time prototype test | `T-yes`: `blink build` and `blink test` test each `@ffi` declaration and read only pass or fail. A fail is `ForeignPrototypeMismatch` (E0861) at the `@ffi` line, exit 1, before the unit compile. The test and the unit compile pin `-Werror=incompatible-pointer-types -Werror=int-conversion` | 5-1 (Minimalism dissented) |

Q1b (the coercion) is part of `P-W1n`. Q1c (the audit mark) was a Phase C item that counted only if `P-E` won. The owner approved the tally on 2026-11-19 with the reading that the audit marks each scalar and `Void` pointee "not checked against the header".

Writer notes from the Phase D votes:

- `name:` spells the C type exactly as the header of the target spells it, and the compiler writes it as it is written (PLT, AI/ML, DevOps).
- The docs and the audit say plainly that scalar and `Void` pointees are not checked (Web/Scripting, Minimalism).
- The spec shows one example of the `Ptr[SockIn]` to `Ptr[Void]` fix, so `Ptr[Void]` is not taught as a general cure (AI/ML). The help of E0861 offers it only for a pointer to a different named C type.
- The spec names the supported C compilers. `tcc` ignores the `-Werror` pin.
- Notes for the implementation only (not for the spec): pin the feature macros of the unit the same on every target; the CI runs the prototype test on at least one Linux target and one macOS target; the cache key of the test; the test reuses the wrapper emitter of the unit compile.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path in the copy is replaced by `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

- **Systems:**

> # [ticket] — Systems seat (sys), Phase A
>
> ## What the compiler does today (probed, build/blink, gcc 16.2.1)
>
> The MVCE lowers to a wrapper that calls the header prototype directly:
>
> ```c
> int32_t blink_2c_1connect(int32_t b_fd, blink_4SockIn* b_addr, uint32_t b_len) {
>     return connect(b_fd, ((struct sockaddr_in*)(b_addr)), b_len);
> }
> ```
>
> - The cast names the Blink pointee (`struct sockaddr_in*`), so cc checks it against `const struct sockaddr *` and stops: I0017, exit 101, with the false note "the cause is a bug of the compiler".
> - Removing `header:` changes nothing. The prologue includes `<sys/socket.h>` for `connect` anyway (src/cg_emit.bl:168), so the prototype is always in scope.
> - `addr: Ptr[Void]` builds clean. But Blink has no pointer cast, and `.addr()` has no inverse, so no Blink code can turn a `Ptr[SockIn]` into a `Ptr[Void]`. **Today Blink cannot bind the sockets API at all.**
> - A scalar mismatch (`I32` where C takes `double`) compiles. The header prototype is in scope, so C converts the value correctly. Only these mismatches stop cc: pointer against non-pointer, struct by value against a different struct, and a wrong argument count.
>
> ## Proposal S1 (recommended): pointer arguments cross as `void*`; build tests the prototype
>
> ### Q2: yes
>
> Each `Ptr[T]` argument lowers to `(void*)arg`. A `Ptr[T]` return goes through an implicit conversion, `void *r = f(...); return (T*)r;`, never through an explicit cast.
>
> - **Cost: zero.** On every supported target (x86-64, aarch64, riscv64, wasm32) all data pointers have the same size and the same register class. The cast changes no machine code.
> - `void*` converts to any object pointer, with or without `const`. A pointer to a different struct therefore compiles. That is the C sockets idiom with one cast fewer.
> - Pointer against scalar still fails. gcc (≥14) and clang (≥15) make `-Wint-conversion` an error by default. I checked `abs((void*)a)` and `void *t = abs(3)`: both are errors. Pointer-to-integer truncation is the one pointer mismatch that changes the ABI, and the C compiler still catches it.
> - I do not use a function-pointer cast (`((int(*)(...))connect)(...)`). It is UB in C, it turns off the header's checks for scalars, and an `I32`/`double` mismatch would then pass values in the wrong register class with no error.
>
> ### Q1: build reports a Blink error; check stays blind
>
> Put a **prototype test** in the header test's TU. That TU has the same includes as the unit, including the prologue, plus the wrapper for each `@ffi` declaration. On the happy path this adds no cc run. If the TU fails, split it: headers alone first (E0859), then one TU per declaration. A declaration that fails alone is `ForeignPrototypeMismatch` (new E08xx) at the `@ffi` line, exit 1, and the unit compile does not start. The test reads only pass or fail, never cc text, as Q3 of the promise decision requires. Cache the result by (header set, lowered wrapper, target, cc), as the obj-cache does. After this, I0017 is a compiler bug again, so its note tells the truth.
>
> ### Q0
>
> A clean `blink check` promises nothing about whether a C header agrees with an `@ffi` signature. `check` reads no header (decided). A mismatch is a host fact, like a missing header. Its place is a build error (exit 1), never exit 101. This keeps [ticket]'s goal: the user sees no ICE.
>
> ### Examples (S1)
>
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
> type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, sin6_addr: In6Addr, sin6_scope_id: U32 }
> // In6Addr: glibc's in6_addr holds a union (__in6_u), and @ffi.struct cannot mirror it today.
> // That is a separate gap from this ticket. This ticket is only about the pointer at the call.
>
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT4")
> fn c_connect4(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! Net.Connect {}
> @ffi("bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND6")
> fn c_bind6(fd: I32, addr: Ptr[SockIn6], len: U32) -> I32 ! Net.Listen {}
>
> fn main() {
>     with ffi.scope() as scope {
>         let a = scope.alloc[SockIn]()
>         let b = scope.alloc[SockIn6]()
>         io.println("{c_connect4(-1, a, 16)} {c_bind6(-1, b, 28)}")
>     }
> }
> ```
>
> | Example | check | build | audit |
> |---|---|---|---|
> | MVCE | clean (W UnauditedFfi) | builds; prints `-1` | lists `c_connect` UNAUDITED, ptr param `addr:Ptr[SockIn]` |
> | connect/bind with sockaddr_in and sockaddr_in6 above | clean | builds, runs | lists both, AUDITED, ptr params |
> | `fn c_pipe(fds: Ptr[SockIn]) -> I32` bound to `pipe` (`int *`) | clean | **builds**; C writes two ints into the struct | lists it, so the auditor must catch it |
> | `fn c_close(fd: Ptr[SockIn]) -> I32` bound to `close` (`int`) | clean | E08xx ForeignPrototypeMismatch, exit 1 | lists it |
> | `fn c_connect(fd: I32, a: Ptr[SockIn]) -> I32` (one argument short) | clean | E08xx, exit 1 | lists it |
>
> The third row is the price. A pointer-type mismatch moves into the audit trust base. That is the same place it has in C, Rust and Zig, and the same place as every "what does C do with this memory" claim (§9.1 row 1). The compiler cannot check pointee types in a well-defined way without reading headers, and doing that in `check` is decided against.
>
> ## Proposal S2 (not recommended): keep strict typing, add `.cast[U]()`
>
> Add `Ptr[T].cast[U]() -> Ptr[U]` (C `(U*)p`, zero cost). Then the user mirrors `struct sockaddr` and writes `c_connect(fd, a.cast[SockAddr](), 16)`.
>
> - More ceremony: one more mirror per call shape, and `sockaddr_storage` has padding fields with private names that the user cannot mirror cleanly.
> - More surface: a general pointer cast inside every FFI region, used where no C call needs it.
> - The plainly wrong `int*` case still compiles as soon as someone writes `.cast`. The safety gain over S1 is small.
> - The prototype test from S1 is still necessary, because the other mismatches still reach cc.
>
> ## Cross-language
>
> - **Rust (libc):** `connect(fd, &sa as *const sockaddr_in as *const sockaddr, len)`. The cast costs nothing and is unchecked, and the binding is the author's claim, as in Blink. bindgen reads headers. Blink decided not to.
> - **Zig @cImport:** reads the header, so the user must `@ptrCast` to `*const sockaddr`. That is S2's ceremony, but it is checked at compile time because Zig owns a C front end.
> - **Go cgo:** `(*C.struct_sockaddr)(unsafe.Pointer(&sa))`. It goes through `unsafe.Pointer`, which is S1's `void*` with the cast spelled out by the user.
> - **C itself:** the idiom is an explicit cast at each call. S1 moves that cast into the wrapper, where the `@ffi` signature already serves as the written claim.

- **Web/Scripting:**

> # [ticket] — Web/Scripting seat, Phase A
>
> ## Probe facts (build/blink on main, cc = GCC 16.2.1; probe dir probe/web/)
>
> - MVCE: check clean, build I0017 exit 101. Same with no `header:` (runtime.h already includes `sys/socket.h`). The C call is `connect(b_fd, ((struct sockaddr_in*)(b_addr)), b_len)`.
> - `addr: Ptr[Void]` in the declaration: check fails, `TypeError: argument 2 of c_connect expects Ptr[Void], got Ptr[SockIn]`. The Ptr table has no cast. A `sockaddr` mirror cannot help either (no array fields, and the layout check tests field names).
> - **So today a user cannot bind `connect`/`bind`/`accept` with a sockaddr_in at all.** Every spelling fails at check or at build. `std.net` works only through runtime helpers.
> - Scalars already pass: `fn c_abs(x: I64)` against `int abs(int)` builds and runs. C converts. Only a pointee mismatch stops the build, and only because GCC 14+ makes `-Wincompatible-pointer-types` an error. With an older GCC it is a warning and the same source builds.
> - Two `@ffi` declarations of the same symbol (`c_connect4`, `c_connect6`) pass check; the compiler takes both.
> - `blink audit` lists `c_connect [UNAUDITED]`, `ptr params: addr:Ptr[SockIn]`.
>
> ## Proposal A (recommended): the pointee is the author's claim; the foreign call erases it
>
> **Behavior.** At the call into the C symbol, codegen passes each `Ptr[T]` argument as `(void*)`, and reads a `Ptr[T]` return through `(void*)`. Blink-side types stay as they are: `Ptr[T]` is still `T*` everywhere in Blink code and in the wrapper parameter. Only the one C call expression changes. C converts `void*` to any object pointer (with or without `const`) with no diagnostic, on every compiler.
>
> - Q0: yes. A clean check promises the build for a pointee mismatch. The pointee is part of the signature claim, and `@trusted(audit: K)` owns it, as it already owns `I64` vs `int`.
> - Q1: no Blink error for a different pointee. Check reads no header (decided), and build reads only pass/fail.
> - Q2: yes, by the rule above.
> - A **kind** mismatch (pointer where C takes `int`, or `Int` where C takes a pointer) still fails the C compile and stays I0017. Not in scope here, but: when the unit has user `@ffi` declarations, put the "wrong `@ffi` prototype" note first. A newcomer who reads "the cause is a bug of the compiler" first files a bug instead of fixing their declaration.
>
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
>
> @ffi("c", "connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT4")
> fn c_connect4(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! Net.Connect
>
> @ffi("c", "bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND4")
> fn c_bind4(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! Net.Listen
>
> // sockaddr_in6: one more declaration of the same symbol, own mirror.
> // (The in6_addr field needs array fields; that is outside this ticket.)
> @ffi("c", "connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT6")
> fn c_connect6(fd: I32, addr: Ptr[SockIn6], len: U32) -> I32 ! Net.Connect
>
> fn main() {
>     with ffi.scope() as scope {
>         let a = scope.alloc[SockIn]()
>         a.sin_family.write(2)
>         io.println("{c_connect4(-1, a, 16)}")
>     }
> }
> ```
>
> Plainly wrong prototype, same kind (`int pipe(int fds[2])`):
>
> ```blink
> @ffi("c", "pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! IO
> ```
>
> | Example | check | build | audit |
> |---|---|---|---|
> | MVCE (no `@trusted`) | W UnauditedFfi, exit 0 | builds, runs, prints `-1` | `[UNAUDITED]`, `addr:Ptr[SockIn]` |
> | connect/bind 4 and 6 (`@trusted`) | clean | builds | `[AUDITED]`, pointer params listed |
> | `c_pipe(Ptr[SockIn])` | W UnauditedFfi | builds; wrong at run time, the same as a wrong `I32` | `[UNAUDITED]`, `fds:Ptr[SockIn]` |
> | `c_abs(x: Ptr[SockIn])` vs `int abs(int)` | W UnauditedFfi | I0017 exit 101 (kind mismatch, unchanged) | `[UNAUDITED]` |
>
> Suggested audit tweak (small): a pointer param whose pointee is an `@ffi.struct` shows "pointee not checked against the header", so a reviewer knows where to look.
>
> **Tradeoffs (DX).**
> - Plus: the usual sockets code works with no new syntax to learn. A Go/Python developer who copies the C idiom gets a build, not an "internal compiler error".
> - Plus: the build no longer depends on the C compiler version. Today the same source builds with an older GCC and fails with GCC 14+. That breaks "the promise covers any supported target".
> - Plus: one rule for scalars and pointers: C type differences inside a kind are the author's claim; the audit owns them.
> - Minus: the C compiler stops catching `Ptr[SockIn]` vs `int *`. That catch was never a promise (the header test reads only pass/fail), and it reached the user as I0017 "bug of the compiler", which is the wrong message.
> - Minus: one declaration per address family. Acceptable: no generics in `@ffi`, and `std.libc`/`std.net` should own these bindings for most users anyway.
>
> ## Proposal B (optional addition to A): `p.as_void()`
>
> Add one row to the Ptr table: `fn as_void(self) -> Ptr[Void]`, C `(void*)ptr`. Widening only; there is no way back to `Ptr[T]`. Then one declaration `fn c_connect(fd: I32, addr: Ptr[Void], len: U32)` serves both families, and the call reads `c_connect(fd, a.as_void(), 16)`. A reader sees the type change at the call site.
>
> - check: clean. build: builds without A too (`void*` to `const struct sockaddr*` is legal C). Without A, the MVCE as written stays I0017.
> - I support B only together with A. B alone still lets the MVCE give a "compiler bug" message, and a newcomer will write the MVCE first.
>
> ## Rejected
>
> - **Do nothing.** Sockets cannot be bound from user code at all (probe 2). The user meets an ICE that blames the compiler.
> - **Check or build compares to the header.** Reopens the decided promise (check reads no header; no cc-text parsing).
>
> ## Cross-language
>
> - Rust: `extern "C"` declarations are never compared to headers; callers write `&sin as *const _ as *const sockaddr`. The pointee is the author's claim, as in A.
> - Zig `@cImport`: the types come from the header, so the user writes `@ptrCast`. Explicit, like B.
> - Go cgo: `(*C.struct_sockaddr)(unsafe.Pointer(&sa))`. Explicit, through an erased pointer, like B.
> - Swift: `withMemoryRebound(to: sockaddr.self)`. Explicit.
> Every one of these languages has a way to make this call. Blink today has none; A gives it with no new syntax, B adds the explicit form the others use.

- **PLT:**

> # [ticket] — PLT seat, Phase A
>
> ## What the probes show (gen1 at main, probe dir probe/plt/)
>
> - MVCE: check clean; build I0017 (`connect(b_fd, ((struct sockaddr_in*)(b_addr)), b_len)`).
> - The same binding with no `header:` fails the same way. The runtime prologue already includes `sys/socket.h`, so the header prototype rules the call even when the author names no header. "No header, no header check" is false today.
> - `Ptr[Void]` param plus a `Ptr[SockIn]` argument: check gives TypeError. Blink has no cast, so the user has no correct spelling of `connect` today.
> - **The spec's own out-param idiom breaks too.** `fn c_strtol(s: Ptr[U8], end: Ptr[Ptr[Void]], base: I32)` with `header: "stdlib.h"`: check clean, build I0017 (`void **` vs `char **`). `sqlite3_open(..., db: Ptr[Ptr[Void]])` (§9.1, ~693) has the same shape against `sqlite3 **`. So the bug is in the lowering, not in user code.
>
> ## The type-theory view
>
> The `@ffi` signature is the only type Blink knows. The pointee type of a C parameter is a fact in a header that check does not read (decided). So no rule inside check can tell "sockaddr_in where sockaddr is expected" (correct C) from "sockaddr_in where int is expected" (wrong). Both are the same judgment in Blink's type system, so they must get the same verdict. Any design that gives them different verdicts must read the header.
>
> Today the C compiler re-checks one part of the claim, the pointee, against the header. Blink never makes that judgment itself, so a clean check cannot promise it. The fix is to stop asking C to make it: at the boundary, a `Ptr[T]` is a C object pointer whose pointee is the author's claim (trust-base entry 1). The Blink side stays nominal and invariant (`Ptr[SockIn]` is not `Ptr[Void]`; the TypeError above stays).
>
> ## PLT-1 (first choice): erase the pointee at the C call
>
> **Behavior.** In the C wrapper of an `@ffi` call, each `Ptr[T]` argument is passed as `(void*)arg`. A `Ptr[T]` result is read through an explicit cast `(T*)sym(...)`. C converts `void*` to any object pointer type with no diagnostic (C11 6.3.2.3p1), including `const struct sockaddr*` and `char**`. The header prototype still rules the ABI: integer promotions, `restrict`, `const`, calling convention.
>
> Answers: **Q0** yes, for every pointee mismatch. **Q1** no. **Q2** yes, and so may any other object pointer.
>
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
> type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, sin6_addr0: U32, sin6_addr1: U32, sin6_addr2: U32, sin6_addr3: U32, sin6_scope_id: U32 }
>
> @ffi("c", "connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT4")
> fn c_connect4(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! Net.Connect {}
>
> @ffi("c", "connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT6")
> fn c_connect6(fd: I32, addr: Ptr[SockIn6], len: U32) -> I32 ! Net.Connect {}
>
> @ffi("c", "bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND4")
> fn c_bind4(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! Net.Listen {}
> ```
>
> One binding per pointee type is the Blink spelling of the C cast. The type system then checks each call site nominally: `c_connect4(fd, a6, 28)` with `a6: Ptr[SockIn6]` is a TypeError at check. That is stronger than C, where a cast to `sockaddr*` accepts any pointer.
>
> | Example | check | build | audit |
> |---|---|---|---|
> | MVCE | ok, W UnauditedFfi | builds; prints -1 | lists `c_connect` unaudited, Ptr arg |
> | connect4/connect6/bind4 above | ok | builds, runs | lists 3 keys, Ptr args |
> | `strtol` with `end: Ptr[Ptr[Void]]` | ok | builds (was I0017) | as today |
> | wrong: `@ffi("pipe", header: "unistd.h") fn c_pipe(fds: Ptr[SockIn]) -> I32` | ok, W UnauditedFfi | **builds**; at run, `pipe` writes 8 bytes into the 16-byte cell, so the claim is wrong but no check sees it | unaudited, Ptr arg |
> | wrong: `@ffi("time", header: "time.h") fn c_time(t: Ptr[I32]) -> I64` | ok | **builds**; `time` writes 8 bytes into a 4-byte cell, undefined | unaudited |
>
> The last two rows are the cost. They are exactly as wrong as a wrong scalar width (`-> I32` for a `long` result), which C also accepts today. The audit key is the guard, as for every other claim in a signature.
>
> **What the promise still does not cover.** A header that disagrees in arity, in pointer-vs-non-pointer kind (`I32` where the header takes `int*`), or in a struct passed by value still fails the C compile. Those stay I0017 with the `@ffi` note. This residue is small and needs the header to close; see PLT-2.
>
> ## PLT-2 (add-on to PLT-1, second choice): a prototype test beside the header test
>
> **Behavior.** At build and test, after the header test (E0859) passes, the compiler compiles one probe per `@ffi` declaration that names or gets a header: a dead C function that calls the symbol with zero values of the declared C types, pointers erased as in PLT-1. It reads pass or fail only, the same rule as the header test, with no cc-text parsing. A fail is a new error, working name `ForeignPrototypeMismatch` (E08xx), at the `@ffi` line, exit 1; the unit compile does not start. One batched compile in the clean case; split per declaration only on failure.
>
> ```blink
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: I32) -> I32 ! () {}
> // blink check: ok, W UnauditedFfi
> // blink build: error[ForeignPrototypeMismatch] at the @ffi line, exit 1
> //   the C compiler rejected a call to `pipe` with the types of this declaration
> //   help: compare each parameter with the prototype of `pipe` in `unistd.h`
> ```
>
> With PLT-2, an `@ffi` program reaches I0017 only through a real compiler bug. That puts the I0017 note "the cause is a bug of the compiler" back in line with the truth. The promise of check stays "clean check ⇒ build, except the header facts", and E0859 already sets that exception.
>
> ## Rejected
>
> - **Call through a function pointer cast to the Blink prototype** (GHC `ccall` style: the declaration, not the header, rules). It closes every residue, but it drops the header's ABI facts. A variadic C function bound with a fixed signature then breaks at run time on Apple arm64. A symbol that the header gives only as a macro has no address. GHC itself added `capi` to get header semantics back.
> - **`Ptr[T] <: Ptr[Void]` subtyping, or a `.cast[U]()` op.** Width subtyping on a mutable cell is unsound one level down: `Ptr[Ptr[SockIn]] <: Ptr[Ptr[Void]]` lets C, or Blink, store a `Ptr[Void]` back into a `Ptr[SockIn]` cell. It also does not fix `Ptr[Ptr[Void]]` vs `char**`, which is a C-side mismatch. A cast op is a new escape hatch on a closed list, for a problem that is in the lowering.
>
> ## Cross-language
>
> Rust `extern "C"` and Haskell `ccall` never read headers. The declaration is the claim, and a pointee mismatch is the author's problem, the same as PLT-1. Zig `@cImport`, Go cgo and Swift read headers, so they force `@ptrCast` / `(*C.struct_sockaddr)(unsafe.Pointer(&sa))` / `withMemoryRebound`. Blink decided not to read headers at check, so it belongs with Rust and GHC. One binding per pointee type gives it the nominal check that cgo's cast does not give.

- **DevOps:**

> # [ticket] — DevOps/Tooling seat, Phase A
>
> ## Probe facts (gen1 `build/blink`, probe dir `.../probe/devops/`)
>
> - MVCE: check exit 0 (only W UnauditedFfi). build exit 101, I0017, note "this source passes `blink check`; the cause is a bug of the compiler", plus "please report it at github". The report is false: the user wrote the bug. A CI pipeline that routes exit 101 to the compiler team routes this to the wrong team.
> - Leaving out `header:` does not help: `runtime.h` already includes `sys/socket.h`, so the prototype is still in scope. The user cannot opt out of a header they never named.
> - `addr: Ptr[Void]` (the C form that compiles: `void*` converts to `const struct sockaddr*` with no cast) is TypeError at check: `Ptr[SockIn]` does not pass as `Ptr[Void]`. There is no `Ptr` cast op. So **today no legal Blink program can call `connect` with a `sockaddr_in6`** (28 bytes, larger than `sockaddr`).
> - Plainly wrong (`pipe(Ptr[SockIn])`, `abs(Ptr[SockIn])`): same exit 101 with the same false note.
> - Toolchain: the same C fails under gcc 16, clang 23, zig cc, and **passes under tcc** (gcc < 14 also only warns). Units add only `-Werror=implicit-function-declaration`. So pass/fail of one Blink source depends on which cc the host has. That breaks Q7 of the promise decision (any supported target).
> - `blink audit` already lists `ptr params: addr:Ptr[SockIn]` for each `@ffi`.
>
> ## Proposal D1 (recommended): prototype test at build + `Ptr[T]` widens to `Ptr[Void]` at an `@ffi` call
>
> **Q0.** A clean check promises the Blink side only (types, E0810/E0848, regions). It promises nothing about agreement with a C header, because check reads no header (decided). It does promise that build never answers a prototype disagreement with exit 101: build gives a user error at the `@ffi` line (exit 1) or it builds. Exit 101 then means only "compiler bug", and CI can trust the code.
>
> **Q1.** Yes, at build/test, not at check. New error `ForeignPrototypeMismatch` (E08xx), exit 1, at the `@ffi` line. Mechanism mirrors the header test: after E0859 passes, compile one test TU with the same prelude (`runtime.h`), cc, target, include paths and flags as the unit, holding one wrapper per `@ffi` declaration, written exactly as the unit writes it. Pass/fail only; no cc text is read. On fail, recompile one wrapper per TU to find the declarations that fail, and report each. Cache by (declaration hash, headers, target, cc identity). The prototype is a fact of the target's C library (`ioctl` differs between glibc and musl), so it belongs beside E0859, not in check.
>
> Pin the flags: the unit and the test both add `-Werror=incompatible-pointer-types -Werror=int-conversion`, so gcc 13, gcc 16, clang and zig cc agree. tcc ignores them, but then the test and the unit both pass, so the test still gives no error for a program that builds.
>
> **Q2.** No for `Ptr[S]` to `Ptr[OtherS]`. The author declares the parameter `Ptr[Void]`, the C form for "any object pointer". At an `@ffi` call argument, inside a region, `Ptr[T]` widens to `Ptr[Void]` without a cast (C's own rule). `Ptr[Void]` to `Ptr[T]` stays an error. For E0601 rule 4 (pointer-holding), the check reads the argument's own type, not the widened `Ptr[Void]`, so widening hides no store.
>
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
> type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, a0: U64, a1: U64, sin6_scope_id: U32 }
>
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net.Connect {}
> @ffi("bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND")
> fn c_bind(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net.Listen {}
>
> fn main() {
>     with ffi.scope() as scope {
>         let a4: Ptr[SockIn] = scope.alloc[SockIn]()
>         let a6: Ptr[SockIn6] = scope.alloc[SockIn6]()
>         io.println("{c_connect(-1, a4, 16)}")   // Ptr[SockIn] widens to Ptr[Void]
>         io.println("{c_bind(-1, a6, 28)}")
>     }
> }
> ```
> check: clean. build: clean; C is `connect(b_fd, (void*)b_addr, b_len)`. Run: prints `-1` twice.
>
> The MVCE (`addr: Ptr[SockIn]` against `const struct sockaddr *`):
> ```
> check: clean (W UnauditedFfi)
> build: error[ForeignPrototypeMismatch] (E08xx) at 3:1, exit 1
>   `c_connect` does not compile against the C declaration of `connect` in `sys/socket.h`
>   help: if C takes a pointer to a different struct (such as `struct sockaddr *`), declare the parameter `Ptr[Void]`
> ```
> The help is static text, shown when the declaration has a `Ptr` parameter; it does not read cc output.
>
> Plainly wrong:
> ```blink
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}   // C: int pipe(int *)
> ```
> check: clean. build: E08xx at the `@ffi` line, exit 1. Never I0017. The cc net stays, because widening applies only to a declared `Ptr[Void]`.
>
> `blink audit`: no new check (audit runs no cc). It already lists `ptr params`; it adds a mark on each `Ptr[Void]` parameter that a call site widened, so a reviewer sees where struct types erase.
>
> **Tradeoffs.** Cost: one extra cc run per build when `@ffi` declarations exist (cached; the header test is the precedent). Gain: correct attribution (exit 1 vs 101), the same result on every cc, the sockets idiom works for v4 and v6. Loss: `Ptr[Void]` drops the `sockaddr` struct check, but C's `struct sockaddr *` is itself a pun with no real check.
>
> ## Rejected alternatives (for the record)
>
> - **D2: codegen passes every `Ptr` argument as `(void*)`.** Fixes the MVCE with no language change, but `pipe(Ptr[SockIn])` then builds and corrupts memory at run time. A compile error becomes a silent run-time fault. No.
> - **D3: call through a cast function pointer.** Every prototype builds, including `abs(Ptr[...])`. Same fault, plus C UB. No.
> - **D4: a `p.cast[U]()` op.** Matches Rust/Go, but a new op in the closed table for what C does with no cast; more surface than D1. Second choice if the panel rejects implicit widening.
>
> ## Cross-language
>
> Zig: `*T` coerces to `*anyopaque` implicitly; `@cImport` reads the header, so a mismatch is a compile error. Swift: a typed pointer converts to a raw pointer at a call argument implicitly. Rust/libc: explicit `as *const sockaddr`; no header check (bindgen produces the prototype). Go cgo: explicit `unsafe.Pointer`; cgo reads the header and reports a mismatch as a cgo error, not as a Go compiler bug.

- **AI/ML:**

> # [ticket] — aiml seat, Phase A
>
> ## What I measured (build/blink, main tree, probe dir probe/aiml/)
>
> - MVCE: check clean; build I0017 exit 101, note "this source passes `blink check`; the cause is a bug of the compiler". The generated wrapper is `return connect(b_fd, ((struct sockaddr_in*)(b_addr)), b_len);`.
> - Same MVCE with **no** `header:` gives the same I0017: runtime.h already includes `sys/socket.h` and `netinet/in.h`. So the `header:` argument does not decide whether cc sees the real prototype.
> - A symbol that no header declares gets a compiler-written `extern int32_t my_weird_sym(struct sockaddr_in*)`. That can never conflict.
> - Binding `addr: Ptr[Void]` and passing a `Ptr[SockIn]`: check gives `TypeError: argument 2 of c_connect expects Ptr[Void], got Ptr[SockIn]`.
> - The Ptr table has no cast. Result: **a user cannot bind `connect` at all today.** Every spelling is either a type error at check or a "compiler bug" at build.
>
> The AI/ML view: the MVCE is what a model writes first, since it matches the C declaration it has seen most. Today the model gets exit 101 plus "your code is not the cause", and no legal spelling exists. A model can't recover from that, and it will retry or edit correct code. That is the worst case for self-correction.
>
> ## Proposal P1 (recommended): `Ptr[T]` widens to `Ptr[Void]`, plus a prototype test at build
>
> **Rule 1 (Q2: no implicit pointee change, except to `Void`).** A `Ptr[T]` is accepted where a `Ptr[Void]` is expected: an argument, an annotated `let`, a return. The other direction does not exist. This is C's own rule (`T*` to `void*` needs no cast). The caller keeps its typed allocation and reads fields from it, so out-params (`accept`, `recvfrom`) need no reverse cast. The Ptr ops table stays the same. A `Ptr[Void]` C param is call-compatible with `const struct sockaddr *` in C, so the generated C compiles.
>
> **Rule 2 (Q1: yes, at build and test, never check).** Before the unit compile, next to the header test, the build compiles one probe per `@ffi` declaration whose symbol a header declares. The probe uses the same cc, flags, target and includes as the unit compile. It calls the symbol with arguments of the claimed C types and stores the result in the claimed return type. It reads pass or fail only and no cc text, as E0859 does. A fail is a new user error, `ForeignPrototypeMismatch` (E08xx), at the `@ffi` line, exit 1. The message names the symbol and the header. The help says: check the binding against the header; for a struct that C passes through a cast (sockaddr_in to sockaddr), declare that parameter `Ptr[Void]`.
>
> **Q0.** A clean check makes no promise about the header prototype, because check reads no header (decided). The build gives a named user error at the `@ffi` line, never I0017. So "wrong prototype" leaves the I0017 note list. I0017 then means a compiler bug again, which matches the panel's Q1 intent.
>
> ### Examples
>
> ```blink
> // 1. MVCE: typed pointer where the header takes struct sockaddr *
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
> @ffi("connect", header: "sys/socket.h")
> fn c_connect(fd: I32, addr: Ptr[SockIn], len: U32) -> I32 ! () {}
> // check: clean (plus W UnauditedFfi)
> // build: error[ForeignPrototypeMismatch] at the @ffi line, exit 1
> //   `connect` in `sys/socket.h` does not take the argument types this declaration claims
> //   help: declare `addr: Ptr[Void]`; a `Ptr[SockIn]` passes to it
> // audit: c_connect [UNAUDITED], ptr params: addr:Ptr[SockIn]
> ```
>
> ```blink
> // 2. The sockets idiom, IPv4 and IPv6, one binding
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
> type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, a0: U64, a1: U64, sin6_scope_id: U32 }
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net.Connect {}
> @ffi("bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND")
> fn c_bind(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net.Listen {}
>
> fn dial(fd: I32) -> I32 ! Net.Connect {
>     with ffi.scope() as scope {
>         let a4 = scope.alloc[SockIn]()
>         a4.sin_family.write(2)
>         let a6 = scope.alloc[SockIn6]()
>         a6.sin6_family.write(10)
>         let r4 = c_connect(fd, a4, 16)    // Ptr[SockIn] widens to Ptr[Void]
>         c_connect(fd, a6, 28)             // Ptr[SockIn6] widens too
>     }
> }
> // check: clean. build: probe passes (void* -> const struct sockaddr *), builds, runs.
> // audit: c_connect [AUDITED] ptr params: addr:Ptr[Void]
> ```
>
> ```blink
> // 3. Plainly wrong: pipe takes int *
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> // check: clean. build: error[ForeignPrototypeMismatch] at the @ffi line, exit 1.
> // Written `fds: Ptr[Void]` instead: probe passes; that is an explicit untyped claim,
> // owned by the audit record, the same as C.
> ```
>
> ### Tradeoffs (AI/ML)
>
> - **One edit to green.** The error names the line, and the help names the exact fix. A model fixes it in one turn. Today it can't fix it in any number of turns.
> - **No new op to learn.** The C, Rust (`as *const c_void`), Go (`unsafe.Pointer`) and Zig (`*anyopaque`) data all teach "pass it as a void pointer". Implicit widening costs zero tokens at each call site.
> - **Pass/fail only.** The probe works per declaration, so it needs no cc-text parsing and stays deterministic. The cost is one small cc run per `@ffi` declaration that a header declares, and it can be cached by declaration plus header hash. Devops may prefer to run probes only after a unit-compile failure (zero cost when green, same verdict). I accept either.
> - **Limit.** The probe can't say which parameter failed. Per-parameter probes could, at N times the cost. I would not do that now.
> - **Limit.** `Ptr[Void]` hides a wrong pointee from the probe. That is the author's explicit claim, and `blink audit` lists it.
>
> ## Alternative P2: the claim always wins (call through a cast function pointer)
>
> The wrapper calls `((claimed_fn_type)&connect)(...)`, so cc never compares the claim with the header. Q0 then answers yes for every `@ffi`, and Q1 and Q2 add nothing new. I reject it. Example 3 then builds and corrupts memory at run time. A model can't learn from a segfault, but it can learn from a named error. It drops a free check that cc already does.
>
> ## Alternative P3: do nothing
>
> Rejected. The sockets idiom has no legal spelling, and the failure tells the agent that its code is correct.
>
> ## Cross-language
>
> Rust bindgen/libc bind `connect(.., *const sockaddr, ..)` exactly. The caller casts `&sin as *const _ as *const sockaddr`, and rustc checks nothing against the header. Zig `@cImport` reads the header, and the caller writes `@ptrCast`. Go cgo reads the header, and the caller writes `(*C.struct_sockaddr)(unsafe.Pointer(&sa))`. Swift uses `withMemoryRebound`. All four put the cast at the call or in a void pointer. None accepts a wrong struct pointer in silence. P1 matches the C and Zig rule ("void * accepts any object pointer") and gets the header check from cc as pass or fail.

- **Minimalism:**

> # [ticket] — Minimalism seat (min), Phase A
>
> ## Probes (gen1-era build/blink, probe dir probe/min/)
>
> - MVCE as given: `blink build --emit c` writes `return connect(b_fd, ((struct sockaddr_in*)(b_addr)), b_len);`. The cc error follows from the declared `Ptr[SockIn]`, as the ticket says.
> - Same program with `addr: Ptr[Void]` in the `@ffi` declaration: `blink check` gives
>   `error[TypeError]: argument 2 of c_connect expects Ptr[Void], got Ptr[SockIn]`.
> - So today a Blink user can NOT bind `connect` for a `sockaddr_in` at all. `Ptr[SockIn]` fails at cc; `Ptr[Void]` fails at check; the Ptr table has no cast. That is the real gap. The header question is a side issue.
>
> ## Existing rules that already answer most of this
>
> - Escape hatch row 1: the `@ffi` signature is the author's claim; `@trusted(audit:)` is where a person checks it against the header. Agreement with the header is an audited premise, not a checked fact.
> - Decided: `blink check` reads no header; build reads only pass/fail of cc; a cc failure is I0017.
> - C itself: any object pointer converts to `void*` with no cast, and `void*` converts to any object pointer with no cast. `Ptr[Void]` is `void*`.
>
> ## Proposal M1 (recommended): one conversion, no new syntax
>
> **Q0 — No.** A clean check promises nothing about agreement between an `@ffi` signature and its header. That agreement is escape hatch row 1. The promise covers what Blink owns; the `@ffi` signature is the one place where Blink owns nothing but the author's word. No change to the decided promise.
>
> **Q1 — No new error.** check cannot see headers (decided). build cannot read cc text (decided). So a struct-pointer mismatch stays I0017 with the note that names the `@ffi` declarations. Chore, not spec: the second I0017 note ("this source passes blink check; the cause is a bug of the compiler") is false when the program has `@ffi` declarations; the decided spec (07:59, §8.10.5) already asks for the `@ffi` note instead. The compiler must not tell the user both.
>
> **Q2 — No, but give the user a correct spelling.** A `Ptr[SockIn]` parameter does not stand for a `struct sockaddr *` prototype. The user declares the C parameter as `Ptr[Void]`. One new rule: **at an argument of a call to an `@ffi` function, a value of type `Ptr[T]` passes to a parameter of type `Ptr[Void]`.** This is the C rule `T* -> void*`, at the one boundary where C rules apply. The reverse direction needs no rule: an `@ffi` declaration can already return `Ptr[T]` for a C `void*` return, and the C code converts it.
>
> No new operation, no new Signature Types entry, no new keyword, no new code. Generated C passes `void*`; C converts it to `const struct sockaddr *` with no diagnostic.
>
> ```blink
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
> type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }
>
> @ffi.struct(header: "netinet/in.h", name: "in6_addr")
> type In6Addr { hi: U64, lo: U64 }
>
> @ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
> type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, sin6_addr: In6Addr, sin6_scope_id: U32 }
>
> @ffi("connect", header: "sys/socket.h")
> @trusted(audit: "NET-CONNECT")
> fn c_connect(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net.Connect {}
>
> @ffi("bind", header: "sys/socket.h")
> @trusted(audit: "NET-BIND")
> fn c_bind(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! Net {}
>
> fn main() {
>     with ffi.scope() as scope {
>         let a4: Ptr[SockIn] = scope.alloc[SockIn]()
>         let a6: Ptr[SockIn6] = scope.alloc[SockIn6]()
>         io.println("{c_connect(-1, a4, 16)}")   // Ptr[SockIn] -> Ptr[Void]
>         io.println("{c_bind(-1, a6, 28)}")      // Ptr[SockIn6] -> Ptr[Void]
>     }
> }
> ```
> check: clean. build: clean (header test passes, cc accepts `void*`). audit: lists NET-CONNECT and NET-BIND with their records, as for any `@ffi`. Runs: prints `-1` twice.
>
> The MVCE (declared `Ptr[SockIn]`):
> check: clean (plus W UnauditedFfi). build: I0017, exit 101; note names `c_connect` and `SockIn` and says a wrong `@ffi` prototype can cause it. audit: lists `c_connect` as unaudited. The fix the user reads in the help: declare the parameter `Ptr[Void]`. (Help text is a chore.)
>
> Plainly wrong prototype (`pipe` takes `int *`):
> ```blink
> @ffi("pipe", header: "unistd.h")
> fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
> ```
> check: clean (W UnauditedFfi). build: I0017, exit 101, same `@ffi` note. audit: unaudited. If the author writes `fds: Ptr[Void]` and passes a `Ptr[SockIn]`, build succeeds and the call writes 8 bytes into a 32-byte struct. That is the author's claim and the auditor's job, exactly as for a wrong scalar width today. Blink cannot know `int *` without reading the header, which the panel already ruled out for check.
>
> ## Tradeoffs (minimalism)
>
> - Cost: one sentence of type rule, scoped to `@ffi` call arguments. No new table row, no new syntax, no new Signature Types entry.
> - It makes a currently unbindable C idiom bindable. Sockets are not rare: also `setsockopt` (`const void *`), `memcpy`, `qsort`, `pthread_create`.
> - Lost: cc's struct-pointer check on a `Ptr[Void]` parameter. The author opts in to that loss by writing `Ptr[Void]`; a `Ptr[SockIn]` parameter keeps the check.
> - Implicit, not explicit: Blink has no implicit numeric widening, and a reader may want to see the conversion. But the conversion is total, safe in C, and visible in the declaration. An explicit op would add a row to the closed Ptr table for the same power.
>
> ## Fallback M1b (if the panel wants no implicit conversion)
>
> Add one Ptr operation: `.erase()` with signature `fn erase(self) -> Ptr[Void]`, C mapping `(void*)ptr`. Call site reads `c_connect(-1, a4.erase(), 16)`. Same power, one more table row, one more name to learn. Never add the reverse (`Ptr[Void] -> Ptr[T]`): an `@ffi` return or out-parameter declaration already covers it.
>
> ## Rejected
>
> - Header-reading check, or cc-text parsing at build: both reopen decided items.
> - Codegen casts every pointer argument to `void*`: hides the plainly wrong `int *` case with no opt-in, and is an implementation choice that changes what a declaration means.
> - A generic `Ptr[T].cast[U]()`: every cast that M1 does not need is a new way to write UB.
> - "Do nothing": leaves `connect`/`bind`/`setsockopt` unbindable. Minimal is not zero when the language cannot express a standard C call.
>
> ## Cross-language
>
> - Rust libc: `connect(fd, &sa as *const sockaddr_in as *const sockaddr, len)`; explicit `as` pointer casts, any type to any type.
> - Zig `@cImport`: `@ptrCast(&sa)`; explicit and unrestricted.
> - Go cgo: `(*C.struct_sockaddr)(unsafe.Pointer(&sa))`; through `unsafe.Pointer`, the same `void*` hub M1 uses.
> - Swift: `withUnsafePointer` + `withMemoryRebound(to: sockaddr.self)`.
> All four need a cast because their bindings use the header's exact type. Blink declares its own binding, so it can name `void*` once in the declaration instead of at each call.

### Phase B — Debate (round 1)

- **Systems:**

> # [ticket] — sys, Phase B round 1
>
> ## Axis P: P-E (unchanged). P-W only as an optional add-on, with min's scope. Reject P-X2. P-X1 not needed.
>
> New probe (gcc 16.2.1, clang 23 agrees), probe/sys/ll.c:
>
> ```c
> void a(int64_t *p){ takes_ll(p); }  // takes_ll(long long *)  -> error, incompatible-pointer-types
> void c(void **p)  { takes_cpp(p); } // takes_cpp(char **)     -> error
> void b(uint8_t *p){ takes_char(p); }// takes_char(char *)     -> warning only (pointer-sign)
> ```
>
> This is why P-W alone fails as a fix:
>
> 1. **The pointee check depends on the target.** `Int` is `int64_t`. On Linux that is `long`, and on macOS it is `long long`. `Ptr[Int]` against `sqlite3_int64 *` (`long long *`) fails on Linux and builds on macOS. Against a `long *` API it is the other way round. The same Blink source gives two different verdicts. That breaks Q7 of the promise decision. Blink has no scalar name for `long long` as distinct from `long`, so the user has no spelling to fix it except `Ptr[Void]`.
> 2. **P-W does not fix nested pointers** (fact 1). `Ptr[Ptr[Void]]` lowers to `void **`, which does not convert to `char **` or `sqlite3 **`. The spec's own `sqlite3_open` and `strtol` examples still fail under P-W. P-E passes `(void*)cell`, and C converts that to `char **`.
> 3. **Cost.** P-E costs zero machine code on every supported target, because all data pointers have the same representation and register class. The rule needs no change to the type system.
>
> On D2 / min's "P-E hides `pipe(Ptr[SockIn])`": the net that P-E removes is not a real net. It catches a wrong pointee only when the header names a type that has a different C spelling. It misses `Ptr[I32]` for `time_t *` (truncation) on both P-E and P-W. It gives false errors for `long` against `long long`. And under P-W the author drops it anyway by writing `Ptr[Void]`. The audit record owns the pointee, as §9.1 row 1 already says. min says P-E "changes what a declaration means". It does not: it makes the lowering match the rule that the signature is the author's claim.
>
> P-W at `@ffi` call arguments only (min's scope) is harmless under P-E: it lets one binding serve v4 and v6. I accept it but do not need it. I reject aiml's wider scope (`let`, return). That is subtyping on a mutable cell, and plt's `Ptr[Ptr[SockIn]] <: Ptr[Ptr[Void]]` argument shows it is unsound.
>
> **Return variation: I hold to the implicit conversion** (`void *r = sym(...); return r;`). plt's `(T*)sym(...)` and web's `(void*)sym(...)` are explicit casts. An explicit cast also turns an `int` return into a pointer with no diagnostic. On LP64 that truncates the upper 32 bits, which is a real ABI fault. The implicit form makes this an int-conversion error, so the kind check stays. The same holds for arguments: `(void*)arg` into an integer parameter is an int-conversion error (probed).
>
> ## Axis T: T-yes
>
> - After P-E, the residue is a mismatch in kind, arity, or a struct passed by value. These are real ABI disagreements, and the build can decide each one with a pass/fail compile of the declaration. Fact 5 (the Q3a ballot said "the build cannot decide it") predates the per-declaration probe. Minimalism's own dissent says this "can land later as a pure narrowing of I0017", and this is that narrowing.
> - Exit 101 for a user error routes CI failures to the wrong team (devops). T-no keeps that.
> - **Flags (devops): accept.** Pin `-Werror=int-conversion -Werror=incompatible-pointer-types` on the unit and on the test. gcc 13 then agrees with gcc 16 and clang. The flags cost nothing.
> - **When to run it: either.** Inside the header-test TU, split only on failure (mine), or only after a failed unit compile (aiml). Both cost no extra cc run on the green path and give the same verdict. That is an implementation choice, not a spec choice.
>
> ## Changed position
>
> None on P or T. I now accept P-W as an add-on (min's scope) and devops's flag pin.
>
> STABLE

- **Web/Scripting:**

> # [ticket] — web, Phase B round 1
>
> ## Changed position
>
> Phase A: P-E with T-no. **Now: P-W + T-yes.** I no longer support P-E.
>
> Why I changed: aiml and devops are right about `c_pipe(fds: Ptr[SockIn])`. Under P-E it builds, and `pipe` writes into the wrong memory with no message. From a newcomer's view, a silent run-time corruption is the worst outcome. A named error at the `@ffi` line with a one-edit help is much better than a build that "just works" but is sometimes wrong. P-E fixes the MVCE by taking away the one check the user had.
>
> ## Axis P: P-W
>
> - Scope variation: take **min/devops: only at an argument of a call to an `@ffi` function**. Not aiml's wider scope (`let`, return). An implicit conversion that a reader can see in only one place, the call into C, is easy to learn: "C takes any pointer as `void*`". A wider conversion makes `Ptr` typing in ordinary region code harder to reason about, and the sockets idiom does not need it.
> - devops: E0601 reads the argument's own type, not the widened `Ptr[Void]`. Yes.
> - P-X1 (`.as_void()` / `.erase()`): fallback only, if the panel rejects any implicit conversion. I drop my "only together with A" condition.
> - P-X2 `.cast[U]()`: no. A general cast is a new way to write UB, and the sockets idiom does not need it.
>
> ## Axis T: T-yes
>
> - With P-W, the MVCE gives `ForeignPrototypeMismatch` at the `@ffi` line, exit 1, with the static help "if C takes a pointer to a different struct, declare the parameter `Ptr[Void]`". One edit to green, for a human or a model. That is the DX goal I had for my "note order" chore, done properly: the user never sees "bug of the compiler" for their own declaration.
> - Flags variation: **yes to devops's pinned `-Werror=incompatible-pointer-types -Werror=int-conversion`** in both the unit and the test. Without it, the verdict depends on the host cc (GCC 14+ vs older GCC, tcc), and the same source builds on one machine and not on another. That breaks Q7.
> - Timing variation (sys: same TU as the header test, split on fail; aiml: probe only after a unit-compile failure): either is fine for DX, because both give the same verdict. I prefer sys's form, because the error comes before the unit compile, the same as E0859.
>
> ## Facts
>
> - **Fact 1 (plt: `strtol` `Ptr[Ptr[Void]]` vs `char **`, and the spec's `sqlite3_open` example).** This was the strongest point for P-E. Under P-W + T-yes, that declaration gets E08xx at the `@ffi` line, not I0017. The fix is `end: Ptr[Void]`, passing a `Ptr[Ptr[U8]]` cell that widens. The spec's `sqlite3_open(..., db: Ptr[Ptr[Void]])` examples are then wrong against `sqlite3 **`. That is a chore: rewrite them with `@ffi.opaque` (§9.1.4) or `db: Ptr[Void]`. It is not a reason for P-E: the spec examples should show a binding that a C compiler accepts.
> - Fact 3 (scalars convert silently): this is still true, and it is not an argument for erasing pointers. A scalar conversion keeps the value. A wrong pointee lets C write past the end of the cell.
> - Fact 5 (min's Q3a dissent: "B can land later as a pure narrowing of I0017"): users hit it now. Sockets cannot be bound, so it is time.
> - plt's argument that both judgments "must get the same verdict" in Blink: correct for **check**. T-yes gives them different verdicts at **build**, from a host fact, the same as E0859 does. That does not break the decided promise.
>
> STABLE

- **PLT:**

> # [ticket] — PLT seat, Phase B round 1
>
> ## Position change: P-E → P-W + T-yes
>
> My Phase A case for P-E was this: check cannot tell the sockaddr idiom from `pipe(Ptr[SockIn])`, so both must get the same verdict. That holds only if no stage can tell them apart. T-yes adds a stage that can, by pass or fail alone. With T-yes in place, P-E throws away a judgment the build now reports cleanly. Devops and aiml are right that P-E turns a named error into a silent fault at run time. **So I move to P-W, with T-yes.** The author writes `Ptr[Void]` to give up the pointee check. A typed `Ptr[S]` keeps it.
>
> ## Axis P: P-W, at min's scope, as a coercion and not a subtype
>
> - **Scope: min's wording.** The rule applies only at an argument of a call to an `@ffi` function. It is a coercion site, like Rust's coercion sites. It is not a subtyping relation. Aiml's scope (any `let`, any return) adds `Ptr[T] <: Ptr[Void]` to the type system as a whole. Then it meets HM inference (a metavar with a `Ptr[Void]` bound), generic instantiation (`List[Ptr[SockIn]]` as `List[Ptr[Void]]`) and variance. Each of those needs its own ruling, and nothing needs them.
> - **One level only.** `Ptr[Ptr[SockIn]]` does not coerce to `Ptr[Ptr[Void]]`. Through a mutable cell that is unsound: C, or Blink, could store some other `void*` into a `SockIn*` cell.
> - **E0601 reads the argument's own type** (devops). That is required, or widening would hide a pointer-holding store from rule 4.
> - **Codegen: erase only where the author wrote `Void`.** A parameter whose declared type has `Void` at any depth passes as `(void*)arg`. This answers moderator fact 1: `end: Ptr[Ptr[Void]]` against `char **`, and the spec's `db: Ptr[Ptr[Void]]` against `sqlite3 **`. Under P-W alone those still fail, because C converts `void**` to `char**` only with a cast. `Void` means "the author does not name this pointee". So the chain below it is the author's claim, and the compiler must not ask cc to check it. A typed pointee keeps today's typed cast, and the prototype test sees it.
> - **Return variation:** the same rule. A typed `Ptr[T]` return has no cast, so the prototype test checks it. A return with `Void` in it goes through `void*`, which needs no cast in C. I withdraw my explicit `(T*)sym(...)`, because it would mask a typed mismatch.
> - **P-X1:** only as min's fallback, if the panel rejects the coercion. **P-X2:** reject. A general cast is a new way to write UB, and nothing needs it.
>
> ## Axis T: T-yes
>
> - Moderator fact 5: my own Q3a ballot kept a wrong prototype under I0017 "because the build cannot decide it". A pass/fail test for each declaration *does* decide it, with no cc text. This is the narrowing of I0017 that min's dissent foresaw. It reopens nothing that was decided.
> - **Pin `-Werror=incompatible-pointer-types -Werror=int-conversion` in the unit and in the test (devops): required.** Without them, moderator fact 2 (tcc and gcc < 14 accept the code) makes the verdict depend on the host's cc. That breaks Q7. With them, the test and the unit always agree, and that agreement is the soundness property that matters.
> - Merged TU, split on failure (sys), or a probe after a failure (aiml): an implementation choice. All give the same verdict. I accept any of them.
> - **Against T-no (min, web):** T-no leaves the "bug of the compiler" signal false for every `@ffi` program. Exit 101 then stops meaning one thing. A diagnostic code whose meaning depends on the program is a broken invariant, not a wording chore.
>
> ## Examples under P-W + T-yes
>
> - MVCE (`addr: Ptr[SockIn]`): check clean; build `ForeignPrototypeMismatch` at the `@ffi` line, exit 1. The help says to declare `Ptr[Void]`.
> - `c_connect(fd, addr: Ptr[Void], len)` called with `Ptr[SockIn]` and with `Ptr[SockIn6]`: check clean, it builds, it prints `-1`.
> - `c_pipe(fds: Ptr[SockIn])`: build E08xx, exit 1. The same declaration with `fds: Ptr[Void]` builds. That is the author's written claim, listed by audit.
>
> OPEN: whether codegen erases `Ptr[Ptr[Void]]` (fact 1) as part of this ticket, or the spec examples change `db:` to `Ptr[Void]` instead

- **DevOps:**

> # [ticket] — devops, Phase B round 1
>
> ## Axis P: I change from P-W to P-E
>
> Two facts moved me.
>
> 1. **Fact 1 (plt's `strtol` probe).** P-W does not repair the spec's own out-param idiom. `Ptr[Ptr[Void]]` lowers to `void **`, and `void **` is not `char **` or `sqlite3 **`, so cc still rejects it. Under P-W plus T-yes, the §9.1 `sqlite3_open` example would get `ForeignPrototypeMismatch`. A rule that makes the spec's own example a build error is the wrong rule. P-E erases the pointee at the top level, so `(void*)arg` converts to `char **` and `sqlite3 **` with no diagnostic.
> 2. **Fact 2 (my own probe).** Today a pointee mismatch fails under gcc ≥ 14, clang and zig cc, and builds under tcc and gcc 13. The "cc safety net" that P-W keeps is not one CI can trust, because its verdict depends on the host compiler. With P-E no pointee mismatch reaches cc on any toolchain. The verdict is the same everywhere, which is what Q7 of the promise decision asks for.
>
> The cost is real: `c_pipe(fds: Ptr[SockIn])` now builds and corrupts memory at run time. But that is the same class as `-> I32` for a `long` result, which builds today (fact 3). One rule for both: inside a kind, C type differences are the author's claim, owned by `@trusted(audit:)`. I withdraw D1's widening rule. P-E needs no type rule, and plt's point (widening on a mutable cell is unsound one level down) is correct.
>
> **Return variation: sys's form.** `void *r = sym(...); return r;`, an implicit conversion, never an explicit cast. An explicit `(T*)sym(...)` (plt) or `(void*)sym(...)` (web) turns an `int` return into a pointer with at most a warning, so a kind mismatch on the return would build and fault at run time. The implicit form keeps that a hard `-Wint-conversion` error, so T catches it.
>
> **P-X1 / P-X2:** not needed with P-E. No.
>
> **Audit add-on (web's tweak, which I support):** `blink audit` marks each `Ptr` parameter or return of an `@ffi` declaration "pointee not checked against the header". The trust boundary then shows in the report a reviewer reads.
>
> ## Axis T: T-yes (unchanged)
>
> P-E does not remove the residue: kind (`Ptr` vs `int`), arity, and a struct passed by value. Those still reach cc. Under T-no they stay I0017, exit 101.
>
> To min and web: the note text is the small part of the damage. Exit 101 is the contract that CI reads ("file a compiler bug"). A pipeline that routes 101 to the compiler team, as the decided promise asks it to, routes a user's wrong prototype there. Moving a note first does not change the exit code. On fact 5: the build *can* decide it. A TU of the same wrappers that passes or fails is the same pass/fail judgment as E0859, and it reads no cc text. Minimalism's dissent said "B can land later if users hit it". The MVCE in this ticket is that hit.
>
> **Variations:**
> - **Where it runs: sys's form.** Put the wrappers in the header test's TU. It adds no cc run on the happy path. On a fail, split the TU: headers alone first (E0859), then one TU per declaration (E08xx). I prefer this to aiml's "probe only after a unit failure". With that form, an `@ffi` error would show up after unit work has started and written obj-cache entries. It would also leave E0859 and E08xx in different phases, and a CI log is easier to read when every host-fact error comes first, before any unit compile.
> - **Flags: keep the pin**, narrowed to `-Werror=int-conversion` (and `-Werror=incompatible-pointer-types`, now relevant only to struct-by-value mismatches). Both the test TU and the unit compile use it, so gcc 13 and gcc 16 give the same verdict on the residue. tcc ignores both flags, but it then passes both the test and the unit, so there is still no false error. The CI gate should name the supported cc list; that is a chore.
>
> ## Facts 4 and 6
>
> Fact 4: `header:` does not control which prototype is in scope. That is one more reason the per-declaration test must use the unit's full prelude, not only the named header. Fact 6: agree it is a separate ticket.
>
> STABLE

- **AI/ML:**

> # [ticket] — aiml, Phase B round 1
>
> ## Axis P: P-E (changed from P-W)
>
> I move to P-E. P-W was my Phase A choice. Two facts changed my mind.
>
> 1. **Fact 1 (plt's strtol / sqlite3_open).** P-W does not fix `Ptr[Ptr[Void]]` against `char **` or `sqlite3 **`. `void **` is not implicitly `char **`. `Ptr[Ptr[U8]]` (`uint8_t **`) against `char **` fails too. Under P-W plus T-yes, the spec's own `sqlite3_open` example becomes a build error, and the user has no way to spell it. Under P-E it builds.
> 2. **The first draft builds.** The MVCE is what a model writes first, because it copies the C type it read in the man page. Under P-E it builds with no edit. Under P-W the model gets an error, has to learn that "declare it `Ptr[Void]`" is the fix, and then sees two valid spellings of the same binding. Two spellings mean one more choice a model can get wrong. Each P-E binding is nominal, so `c_connect4(fd, a6, 28)` is a TypeError at check. That is a better check than `Ptr[Void]` gives.
>
> The cost is that `c_pipe(fds: Ptr[SockIn])` builds. I accept that, for three reasons:
> - Fact 2: the check that catches it today depends on the C compiler. It passes under tcc and gcc < 14, so it breaks Q7.
> - Fact 3: a wrong scalar width already builds silently.
> - Under P-W, `fds: Ptr[Void]` builds silently anyway.
>
> So the pointee check only ever covered a narrow class, and not reliably. Audit stays the guard (trust-base row 1).
>
> **Return variation: sys's form.** `void *r = f(...); return (T*)r;`. plt's `(T*)sym(...)` and web's `(void*)sym(...)` are explicit casts. An explicit cast turns an `int` return bound as `-> Ptr[U8]` into a `-Wint-to-pointer-cast` warning, which hides a 64-bit truncation. sys's implicit form keeps `-Wint-conversion` as an error, so T-yes still catches it.
>
> **P-W as an add-on:** no for now (YAGNI). P-E already binds every case in the ticket. A widening rule beside it adds a second spelling. If `memcpy`/`qsort` show friction later, P-X1 or P-W can come as a separate ticket.
>
> **P-X2:** no. P-E makes no cast necessary, and plt is right that a general cast is a new way to write UB.
>
> ## Axis T: T-yes
>
> Under P-E, the residue is arity, pointer against scalar, and a struct by value. That residue is small, but today it reaches the user as exit 101 with "the cause is a bug of the compiler". That is the one message that stops a model from fixing its own code: it either retries or edits correct code. A named E08xx at the `@ffi` line with exit 1 is a one-turn fix. It also makes I0017 mean only one thing again.
>
> **Variations:**
> - **devops's pinned flags (`-Werror=incompatible-pointer-types -Werror=int-conversion` on the unit and the test): yes, required.** Without them the verdict depends on the cc version (fact 2), and the agent sees different results on different hosts.
> - **When the test runs: sys's batched TU.** It adds no cc run when the TU passes and splits per declaration only on failure. I prefer it to my Phase A "per declaration".
>
> ## Responses
>
> - **min / web (T-no):** min says the note chore is enough. But even with the note first, the code is still I0017 and the exit is still 101. CI and agents route on the code and the exit status, not on the order of the notes. Fact 5 shows that min's own Q3a dissent ("B can land later as a pure narrowing of I0017") predicted this ticket. Users hit the problem, so this is the time.
> - **plt fact 5 ("the build cannot decide it"):** a per-declaration pass/fail compile does decide it, with no cc-text parsing. It is the same move that made E0859 possible.
> - **devops (D2 rejected because pipe builds silently):** I covered this above. That check is cc-dependent today, and P-W loses it as soon as the author writes `Ptr[Void]`.
> - **Fact 6:** I agree it is out of scope. `in6_addr` needs union or array fields in a separate ticket.
>
> STABLE

- **Minimalism:**

> # [ticket] — Minimalism seat (min), Phase B round 1
>
> ## Axis P: I change to P-E (from P-W)
>
> Two facts moved me.
>
> 1. **Fact 1 (plt, strtol / sqlite3_open).** The spec's own out-param idiom, `db: Ptr[Ptr[Void]]` against `sqlite3 **`, fails the C compile today. P-W does not fix it: `void **` does not convert to `sqlite3 **` in C. So P-W needs a second rule, or a cast op, or the spec example stays broken. P-E fixes both shapes with one rule, because `(void*)cell` converts to `sqlite3 **`.
> 2. **Fact 2 (devops, toolchains).** Today the same source builds under tcc and gcc < 14 and fails under gcc 16, clang and zig cc. With P-W, the pointee check in a typed `Ptr[S]` parameter is still delegated to cc, so the verdict depends on which cc the host has. That breaks Q7 of the promise. P-E removes the pointee from the cc verdict on every compiler.
>
> PLT's argument settles it for me: Blink's type system sees `Ptr[SockIn]` vs `struct sockaddr *` and `Ptr[SockIn]` vs `int *` as the same judgment, so they must get the same verdict. A rule that lets cc split them is a rule Blink cannot state.
>
> On the minimalism scale, P-E is the smallest: no type rule, no new op, no Signature Types entry, no change to Blink-side typing (`Ptr[SockIn]` is still not `Ptr[Void]`). The spec gains one fact: at the C call, the pointee of a `Ptr` is the author's claim (trust-base row 1), as a scalar width already is. The cost (`c_pipe(Ptr[SockIn])` builds) is in the audit, exactly where `-> I32` for a `long` sits today. One binding per pointee type also gives a nominal check at each call site that a `void*` parameter would not.
>
> **Return variation:** sys's form. A `Ptr[T]` return goes through an implicit conversion from the C result, never through an explicit cast. An explicit `(T*)abs(3)` silences an int-to-pointer kind mismatch; the implicit form keeps it an error. Behavior: a C object-pointer return builds; a C scalar return for a `Ptr` claim does not.
>
> **P-W scope variations:** moot for me. If P-W wins, I take min's narrow scope (call argument only). I reject aiml's `let`/return widening: PLT's `Ptr[Ptr[SockIn]] <: Ptr[Ptr[Void]]` unsoundness applies.
>
> **P-X1 / P-X2:** no. With P-E, neither has a case to serve. P-X2 is a general escape hatch on a closed list.
>
> ## Axis T: T-no (unchanged)
>
> After P-E, the residue is kind, arity, and struct-by-value mismatches. Nobody has shown a user hitting those. The ticket's case is the pointee case, and P-E removes it. The Q3a record holds my dissent: "B can land later as a pure narrowing of I0017" when users hit it. That trigger has not fired for the residue. T-yes adds a new error code, a second cc run, a cache key and a split-on-failure path for a case with no reported user.
>
> Two chores I support under T-no (codegen, no spec vote needed):
> - The I0017 note: when the unit has user `@ffi` declarations, do not say "the cause is a bug of the compiler". Put the `@ffi` note first (web's form).
> - Pin `-Werror=int-conversion` in the unit compile (devops's flag, minus the pointer flag P-E makes moot), so the residue fails the same way on gcc 13, gcc 16, clang and zig cc. That serves Q7 with no new error.
>
> If T-yes wins, I prefer sys's form (same TU as the header test, no cc run on the happy path).
>
> STABLE

### Phase C — Vote

Options on the ballot: Q1 `P-E` (erase every `Ptr` argument as `(void*)arg`), `P-W1` (the coercion; erase only where the author wrote `Void`), `P-W2` (the coercion; codegen unchanged). Q1b and Q1c counted only if `P-E` won. Q2 `T-yes` or `T-no`. Result: Q1 `P-W1` 4, `P-E` 2, so Phase D; Q2 `T-yes` 5-1.

- **Q1: what happens to a `Ptr` at the C call**
  - **Systems:**

    > ## Q1 — P-E
    >
    > **Reasoning.** On every supported target, `(void*)` at the call costs no machine code. It is the only option where a Blink source gets the same verdict on every target. Under P-W1, a typed `Ptr[Int]` against a `long long *` parameter gives E08xx on Linux (where `int64_t` is `long`) and builds on macOS. Under P-W1 the reverse holds for a `long *` parameter. So the C compiler's pointee check measures how C spells a type on that platform, not whether the claim is right. It misses the real width faults (`Ptr[I32]` for `time_t *`) under every option. The pointee belongs to the audited claim (§9.1 row 1), and P-E makes the lowering say that.
    >
    > **Concern.** A same-kind wrong pointee (`c_pipe(fds: Ptr[SockIn])`) now builds with no diagnostic. Only the audit record stands between it and memory corruption at run time.

  - **Web/Scripting:**

    > ## Q1 — Ptr at the C call
    >
    > 1. **Vote:** P-W1
    > 2. **Reasoning:** P-W1 keeps the one check that saves a newcomer from silent memory corruption (`c_pipe(fds: Ptr[SockIn])` is E08xx at the `@ffi` line, not a run-time fault). It also keeps the out-param idiom that the spec already teaches (`db: Ptr[Ptr[Void]]`, `end: Ptr[Ptr[Void]]`) working as written. So I prefer it to my own P-W2: a user who copies a spec example gets a build, not a new error and a rewrite. The rule is easy to say: "where you write `Void`, C takes any pointer; where you write a type, C checks it."
    > 3. **Concern:** under P-E, the user never learns that the pointee is unchecked. A wrong binding builds and fails only at run time, far from the `@ffi` line, which is the hardest failure for a newcomer (or a model) to trace back.

  - **PLT:**

    > ## Q1 — P-W1
    >
    > **Reasoning.** With T-yes in place, the build can decide whether a typed pointee agrees with the header. P-E throws that judgment away for every `Ptr`, so `c_pipe(fds: Ptr[SockIn])` turns from a named error into a silent fault at run time. P-W1 erases exactly where the author wrote `Void`: the type of each parameter says what is checked and what is the author's claim. It also keeps the spec's own `Ptr[Ptr[Void]]` out-param idiom (`strtol`, `sqlite3_open`) working without a rewrite, which P-W2 does not.
    >
    > **Concern.** The coercion must stay a coercion at the call site. If a later change turns it into a general subtype, it meets inference and variance and becomes unsound one level down.

  - **DevOps:**

    > ## Q1 — `Ptr` at the C call
    >
    > **Vote:** P-W1
    >
    > **Reasoning:** In round 1 I moved to P-E for two reasons. P-W1 answers both. First, it erases the pointee wherever the author wrote `Void`, at any depth, so `strtol` and the spec's `sqlite3_open` example (`Ptr[Ptr[Void]]` against `char **` / `sqlite3 **`) build. Second, T pins `-Werror=incompatible-pointer-types` on both the test and the unit, so the typed-pointer check gives the same verdict on gcc 13, gcc 16, clang and zig cc. tcc ignores the flag, but then it passes both the test and the unit, so it gives no false error. With both answered, a named build error at the `@ffi` line for `c_pipe(fds: Ptr[SockIn])` beats a binary that builds and then corrupts memory. A CI pipeline catches the first; it never sees the second. The author's opt-out is visible in the source: they write `Void`.
    >
    > **Concern:** A wrong typed pointer that tcc (or another cc that ignores the pinned flags) lets through builds there and fails on gcc. So the supported cc list must be named, or the verdict still depends on the host.

  - **AI/ML:**

    > ## Q1 — P-W1 (changed from P-E in round 1)
    >
    > **Reasoning.** I chose P-E in round 1 for two reasons. P-W1 meets both of them, and it keeps the check that P-E drops.
    > 1. **The `Ptr[Ptr[Void]]` shapes:** under P-W1, strtol `char **` and `sqlite3 **` build, because codegen erases where the author wrote `Void`.
    > 2. **The first draft:** under P-W1 the MVCE does not build, but it gets a named error at the `@ffi` line, exit 1, with a static help ("declare `Ptr[Void]`"). That is a one-turn fix.
    >
    > The pinned `-Werror` flags remove my other objection: the typed check no longer depends on the cc version. So the plainly wrong `pipe(Ptr[SockIn])` becomes a deterministic build error and not memory corruption. A model can learn from a named error. It can't learn from a segfault.
    >
    > **Concern.** Models may learn "make it `Ptr[Void]`" as the reflex fix for every `ForeignPrototypeMismatch`, and that throws the typed check away. The help must name `Ptr[Void]` only for a pointer to a different struct, and the examples must show typed `Ptr[T]` as the default.

  - **Minimalism:**

    > ## Q1 — Vote: P-E
    >
    > Reasoning: P-E adds no type rule, no coercion and no new operation. It fixes the MVCE and the spec's own `Ptr[Ptr[Void]]` examples with one codegen fact. P-W1 needs a coercion rule plus a depth-sensitive erase rule ("only where the author wrote `Void`, at any depth"), which is two rules for the job P-E does with zero. Blink cannot tell a right pointee from a wrong one without the header, so the pointee belongs in the audited claim, beside scalar width.
    >
    > Concern: if P-E wins, a wrong pointee (`c_pipe(fds: Ptr[SockIn])`) builds and corrupts memory at run time, and only an auditor who reads the header will catch it.

- **Q1b: the `@ffi`-argument coercion, if `P-E` wins**
  - **Systems:**

    > ## Q1b — Yes
    >
    > **Reasoning.** The coercion is scoped to `@ffi` call arguments, applies at one level only, and is not a subtype. It costs zero, because the C call already erases the pointee. It lets one `Ptr[Void]` binding serve `sockaddr_in` and `sockaddr_in6`, and that is the shape C programmers expect. It also gives a sound spelling to a C API whose parameter really is `void *`, such as `setsockopt`, `memcpy` or `qsort`.
    >
    > **Concern.** Two spellings now bind the same symbol (typed per pointee, or `Ptr[Void]`), and the docs must say which one std.libc uses.

  - **Web/Scripting:**

    > ## Q1b — if P-E wins, coercion Ptr[T] → Ptr[Void] at @ffi arguments
    >
    > 1. **Vote:** Yes
    > 2. **Reasoning:** one `c_connect` binding for v4 and v6 is what a Go/Python developer expects from C's `void*`, and it halves the bindings a newcomer writes. A `Ptr[Void]` parameter in the declaration tells the reader "any pointer" plainly. That is clearer than two bindings of one symbol that differ only in the pointee.
    > 3. **Concern:** two correct spellings of the same binding (typed, or `Ptr[Void]`) can confuse a learner about which one is idiomatic. The docs must pick one for sockets.

  - **PLT:**

    > ## Q1b — Yes
    >
    > **Reasoning.** A coercion at an `@ffi` argument is sound at one level, and it is the C rule at the C boundary. It lets one binding serve v4 and v6. Without it, P-E still forces one binding per pointee type for no gain in safety, since P-E already erases.
    >
    > **Concern.** Under P-E, a binding then has two spellings for one fact (a typed `Ptr[S]` and `Ptr[Void]`). Neither is checked, so the typed one gives a false sense of safety.

  - **DevOps:**

    > ## Q1b — if P-E wins, the `Ptr[T]` → `Ptr[Void]` coercion too?
    >
    > **Vote:** Yes
    >
    > **Reasoning:** It lets one audited binding serve both `sockaddr_in` and `sockaddr_in6`, so there is one audit key, not one per address family. It is the same rule as in P-W1, so the language keeps one spelling whichever way Q1 goes.
    >
    > **Concern:** With P-E, a typed binding and a `Ptr[Void]` binding behave the same in C, so the two spellings mean the same thing and code will mix them with no reason.

  - **AI/ML:**

    > ## Q1b — No
    >
    > **Reasoning.** If P-E wins, every typed binding already builds. Adding the coercion gives two correct spellings of the same binding, and that is one more choice a model can get wrong. One binding per pointee also keeps the nominal check at the call site (`c_connect4(fd, a6, 28)` is a TypeError).
    >
    > **Concern.** Without the coercion, `memcpy`/`qsort`-style APIs need one binding per pointee type, which costs tokens. Users may then ask for the coercion later anyway.

  - **Minimalism:**

    > ## Q1b — Vote: No
    >
    > Reasoning: under P-E, one binding per pointee type already serves v4 and v6. The coercion would add a second spelling for the same call, and a rule the spec and every reader must learn, for no case P-E leaves open. If a real need shows up later, it can land as a pure addition.
    >
    > Concern: if Yes wins, authors will write `Ptr[Void]` parameters by habit and lose the nominal per-call-site check that one binding per pointee gives.

- **Q1c: the audit mark, if `P-E` wins**
  - **Systems:**

    > ## Q1c — No
    >
    > **Reasoning.** Under P-E no `Ptr` pointee is checked against a header. A mark on every `Ptr` row carries no information. `blink audit` already lists the `ptr params` of each `@ffi` declaration, and that list is the reviewer's work list. Uniform noise trains reviewers to skip the column.
    >
    > **Concern.** A reviewer who is new to Blink may assume that a typed `Ptr[SockIn]` was checked against the C header. The audit docs, not each row, must say that it was not.

  - **Web/Scripting:**

    > ## Q1c — if P-E wins, audit marks pointee not checked
    >
    > 1. **Vote:** Yes
    > 2. **Reasoning:** under P-E the compiler stops checking the pointee, so the audit report is the only place where a reviewer can see that fact. A short mark costs nothing and tells the reviewer where to look.
    > 3. **Concern:** if the mark is on every `Ptr` parameter, reviewers learn to ignore it. Keep it one short line per declaration.

  - **PLT:**

    > ## Q1c — Yes
    >
    > **Reasoning.** Under P-E, every `Ptr` pointee in an `@ffi` signature is an unchecked claim. The audit report is where a trust-base premise must be visible, as it is for every other escape-hatch row. A premise that no tool shows is not an audited premise.
    >
    > **Concern.** If the mark goes on every `Ptr`, it becomes noise that reviewers learn to skip.

  - **DevOps:**

    > ## Q1c — if P-E wins, audit marks "pointee not checked against the header"?
    >
    > **Vote:** Yes
    >
    > **Reasoning:** Under P-E no tool checks a pointee, so `blink audit` is the only report a reviewer reads that can show this trust boundary. The mark is static text from the declaration, and it costs no cc run.
    >
    > **Concern:** If the mark is on every `Ptr` line it becomes noise that reviewers skip. The writer should keep it to one column or one summary count.

  - **AI/ML:**

    > ## Q1c — Yes
    >
    > **Reasoning.** If P-E wins, the pointee becomes a pure claim that no tool checks. The audit report is the one place a reviewer, human or model, reads the trust boundary. A fixed static mark costs nothing and tells the auditor exactly where to compare against the header.
    >
    > **Concern.** The mark is on every `Ptr` parameter, so it can turn into noise that reviewers skim past.

  - **Minimalism:**

    > ## Q1c — Vote: No
    >
    > Reasoning: under P-E, no `Ptr` pointee is ever checked against the header, so the mark would appear on every `Ptr` parameter and return and carry no information. `blink audit` already lists `ptr params`. The rule belongs once in the spec and in audit's help text, not repeated on every line.
    >
    > Concern: if Yes wins, the mark becomes noise that reviewers learn to skip, which hides the lines that do need a look.

- **Q2: a build-time prototype test**
  - **Systems:**

    > ## Q2 — T-yes
    >
    > **Reasoning.** After P-E, the C compiler rejects only a pointer-vs-scalar kind mismatch, a wrong argument count, or a different struct passed by value. Each of these is a real ABI disagreement. A pass/fail compile of the declaration decides it, and no cc text is read. With the flags pinned, it costs no extra cc run on the green path, whether the test shares the header test's compile unit or runs only after a failed unit compile. Without the test, exit 101 keeps lying about who wrote the bug.
    >
    > **Concern.** The split-on-failure path and its cache key are new build machinery. A stale cache entry would hide a fixed declaration or keep a broken one, so the cache key must include the cc identity, the target and the header set.

  - **Web/Scripting:**

    > ## Q2 — Build-time prototype test
    >
    > 1. **Vote:** T-yes
    > 2. **Reasoning:** a newcomer who gets a wrong prototype must get an error at their own `@ffi` line with exit 1, not "internal compiler error ... the cause is a bug of the compiler". That message sends them to file a bug instead of fixing one line. Pinning the `-Werror` flags makes the same source give the same verdict on every host cc, which the "any supported target" promise needs.
    > 3. **Concern:** the error reads only pass or fail, so it cannot say which parameter is wrong. The help must tell the user plainly to compare each parameter with the header, or the fix is not fast.

  - **PLT:**

    > ## Q2 — T-yes
    >
    > **Reasoning.** Pass or fail per declaration decides the prototype question with no cc text. So it narrows I0017 back to its one meaning, "a compiler bug". The pinned `-Werror` flags make the unit and the test agree on every cc, which keeps the promise target-independent (Q7). Under T-no, the meaning of exit 101 depends on the program, and that is a broken invariant.
    >
    > **Concern.** If the test TU and the unit TU ever differ in prelude, flags or wrapper text, the test can pass while the unit fails. The test must reuse the unit's own wrapper emitter, not a copy of it.

  - **DevOps:**

    > ## Q2 — build-time prototype test
    >
    > **Vote:** T-yes
    >
    > **Reasoning:** Exit 101 is the contract CI reads as "file a compiler bug". Under T-no, a user's wrong prototype still exits 101, so the pipeline routes it to the compiler team, whatever the note says. T-yes uses the same pass/fail rule as E0859, reads no cc text, and adds no cc run on a clean build if it shares the header test's TU. After it, I0017 means only a compiler bug again.
    >
    > **Concern:** If the test and the unit compile ever differ in prelude, flags or include paths, the test passes and the unit fails. That is I0017 again, now with no `@ffi` note to help, so the implementation must build both from one source of flags and includes.

  - **AI/ML:**

    > ## Q2 — T-yes
    >
    > **Reasoning.** Exit 101 with "the cause is a bug of the compiler" is the one signal that stops a model from fixing its own code. It retries or edits correct code. A named E08xx at the `@ffi` line with exit 1 is actionable in one turn, and it lets I0017 mean only a compiler bug again. The test reads only pass or fail, so it keeps the decided "no cc-text parsing" rule.
    >
    > **Concern.** The test can report the declaration but not the parameter. A model with a many-parameter binding may then guess at the wrong parameter, so the help should tell it to compare every `Ptr` and every by-value struct parameter with the header.

  - **Minimalism:**

    > ## Q2 — Vote: T-no
    >
    > Reasoning: after P-E, the residue is arity, pointer-vs-scalar kind, and struct-by-value mismatches, and no user has reported one. T-yes adds an error code, a second cc run on some path, a cache key and a split-on-failure path. The Q3a record already says this can land later as a pure narrowing of I0017 when users hit it. The two chores (no "bug of the compiler" note with user `@ffi`; pin `-Werror=int-conversion`) give most of the gain at a small part of the cost.
    >
    > Concern: if T-yes wins, the prototype test can drift from the unit compile (flags, prologue, includes), and a test that passes while the unit fails puts I0017 back for a user error. So the test must reuse the unit's exact prologue and flags.

### Phase D — Re-vote on Q1

Phase C left Q1 at 4-2. PLT proposed `P-W1n` in its Phase D reply: `P-W1` with a scalar erase. Phase D ran once.

#### Replies

- **Systems:**

> # [ticket] — sys, Phase D
>
> ## I change to P-W1.
>
> My P-E case had three legs. Here is how each one stands now.
>
> 1. **`Ptr[Ptr[Void]]` against `char **` / `sqlite3 **`.** P-W1 erases wherever the author wrote `Void`, at any depth, so these build. Answered.
> 2. **Cost.** P-W1 also costs zero machine code. Both the erase and the typed pass are pointer moves with no conversion. Answered.
> 3. **Verdicts that depend on the target** (`Ptr[Int]` against `long long *` fails on Linux and builds on macOS). Nobody answered this directly. devops's pinned flags make the compilers agree, but the targets still differ. On reflection it does not decide the vote. The verdict is a named build error at the `@ffi` line (exit 1), not an ICE. A build-time host fact that varies by target is already accepted for E0859. The fix is in the source and the same on every target: write `Ptr[Void]`.
>
> So P-E's only remaining advantage is that it never gives a false E08xx. P-W1 instead catches `c_pipe(fds: Ptr[SockIn])` before it corrupts memory. From the hardware's view, a deterministic build error beats a store into the wrong layout at run time. The rule also reads well: the parameter type says what the C compiler checks.
>
> min's "two rules against zero": the erase rule is the coercion's lowering, not a second rule. `Void` already means `void*`. P-W1 only makes `Ptr[Ptr[Void]]` lower so that C accepts it for any `T **`.
>
> ## Conditions I attach (writer / impl notes, not new options)
>
> - **The `Ptr` return keeps the implicit conversion** (`void *r = sym(...); return r;`), so int against pointer stays an error and an LP64 truncation cannot pass.
> - **The E08xx help must not assume the cause.** It names `Ptr[Void]` only as the fix for a pointer to a different C type. aiml's concern applies here.
> - **The spec gets one example of the target case.** `Int` is `int64_t`. A `long long *` API (`sqlite3_int64 *`) may fail on LP64 Linux, and the portable binding is `Ptr[Void]`.
>
> STABLE

- **Web/Scripting:**

> # [ticket] — web, Phase D
>
> I stay with **P-W1**.
>
> **sys (`Ptr[Int]` vs `long long *` differs between Linux and macOS).** This is real, and it is the best argument for P-E. But under P-W1 with T-yes, the result is a named E08xx at the user's `@ffi` line, exit 1, on the platform where it fails. That is the same class as E0859: a fact of the host's C library, reported as a user error. It is not an ICE, and it is not a silent fault. Under P-E, the cost moves to the opposite case: `c_pipe(fds: Ptr[SockIn])` builds on every platform and corrupts memory on every platform. From a newcomer's view, "an error on Linux with a clear fix" is much better than "a crash everywhere with no pointer to the cause". Writer note: the E08xx help should name both fixes plainly. For a pointer to a different struct, declare `Ptr[Void]`. For an integer pointer whose C type is spelled `long`/`long long`, also `Ptr[Void]`, and say why. Then the platform case is a one-edit fix too.
>
> **sys (it misses `Ptr[I32]` for `time_t *` under every option).** Yes, but that is an argument that no option catches it, not an argument against catching the cases that P-W1 does catch.
>
> **min (P-W1 is two rules, P-E is zero).** Counted for a reader, P-W1 is one sentence: "where you write `Void`, C takes any pointer; where you write a type, C checks it." P-E is also one sentence, "C never checks the pointee", but the user learns that only from a crash. A rule the user can see in the source is worth one more line of spec.
>
> **aiml's concern (models reach for `Ptr[Void]` as a reflex).** Agreed. The help must give `Ptr[Void]` only for the different-struct and integer-spelling cases, and the examples must keep typed `Ptr[T]` as the default.
>
> **devops's concern (name the supported cc list).** Agreed; that is a writer/impl item, not a reason to change the option.
>
> STABLE

- **PLT:**

> # [ticket] — PLT seat, Phase D round 1
>
> **Sys's argument is correct, and it is a soundness point against P-W1 as written.** The C compiler compares pointees by their C spelling, not by what they claim. `I64` lowers to `int64_t`. That is `long` on Linux and `long long` on macOS. So a *correct* claim, `time(t: Ptr[I64])` against `time_t *`, builds on Linux and gets E08xx on macOS. The reverse happens for `long long *`. Worse, `Ptr[Ptr[U8]]` against `char **` (strtol's `end` written with a byte type) fails on every target: `uint8_t **` and `char **` are not compatible in C. A check that rejects correct programs depending on the target fails Q7. It does not measure the claim.
>
> **Min's argument** (two rules where P-E needs none) holds only if both rules carry the same weight. The coercion is needed under either option for one binding to serve v4 and v6 (Q1b). So the real difference is the erase rule.
>
> **Amended position: P-W1 with nominal pointees only.** C keeps the pointee type only when the Blink pointee names a C type by name: an `@ffi.struct` or `@ffi.opaque` (`name:`). Every other pointee erases to `void*`, at any depth: `Void`, every scalar, and `Ptr` to those. A C struct name is the same on every target, so the check gives one verdict everywhere. It still catches what P-E loses: `c_pipe(fds: Ptr[SockIn])` against `int *` is E08xx, and so is `Ptr[SockIn]` against `struct sockaddr *` (the help says to use `Ptr[Void]`). It drops only the scalar-width faults, which, as sys notes, no option catches reliably.
>
> If the amendment is not on the ballot, I still vote P-W1 over P-E. A false E08xx has a one-line fix (`Ptr[Void]`). A silent struct mix-up is memory corruption at run time.
>
> OPEN: whether P-W1 erases scalar pointees as well as Void (pointee kept only for @ffi.struct / @ffi.opaque names)

- **DevOps:**

> # [ticket] — devops, Phase D
>
> ## I change back to P-E. sys's argument holds, and I probed it.
>
> My P-W1 vote rested on "the pinned flags give the same verdict on every cc". That is true for one target. It is false across targets, and the promise covers every supported target (Q7). Probe (`zig cc -Werror=incompatible-pointer-types`, `probe/devops/w.c`):
>
> | correct binding | x86_64-linux-gnu | aarch64-linux-musl | aarch64-macos |
> |---|---|---|---|
> | `time(t: Ptr[Int])` (`int64_t *` vs `time_t *`) | builds | builds | **error** (`long long *` vs `long *`) |
> | `getline(.., n: Ptr[U64], ..)` (`uint64_t *` vs `size_t *`) | builds | builds | **error** (`unsigned long long *` vs `unsigned long *`) |
>
> Both bindings are right on every target: same width, same sign. Under P-W1 + T-yes they pass Linux CI and give `ForeignPrototypeMismatch` on a developer's Mac. That is a false error on correct code, and it depends on the target. It is the worst result for a CI pipeline: a green gate on one target says nothing about another. The type check sees how a libc *spells* a type, not whether the claim is right. And as sys says, it still misses the real width fault (`Ptr[I32]` for `time_t *`) on every target.
>
> The P-W1 fix for the user is to write `Ptr[Void]`, which drops the check anyway. So the check P-W1 keeps costs false errors and still lets a determined author through.
>
> To web, plt and aiml: I agree that a named error beats a run-time fault, *when the error is right*. Here it is right for `pipe(Ptr[SockIn])` and wrong for `time(Ptr[Int])` on macOS, and the tool cannot tell those two cases apart without reading the header. Under P-E, the verdict is the same on every target. T-yes still catches kind, arity and struct-by-value mismatches, and those do not depend on how a libc spells a type. The audit mark (Q1c yes) keeps the unchecked pointee in view for the reviewer.
>
> aiml's concern ("models learn `Ptr[Void]` as the reflex fix") also goes away under P-E: there is no error to reflex on.
>
> STABLE

- **AI/ML:**

> # [ticket] — aiml, Phase D (Q1)
>
> ## I change to P-E. sys's target argument holds, and I checked it.
>
> Probe (zig cc, `-Werror=incompatible-pointer-types`):
> ```c
> void f(char **l, uint64_t *n, FILE *fp, int64_t *t) { getline(l, n, fp); time(t); }
> ```
> - On `x86_64-linux-gnu` it compiles.
> - On `aarch64-macos` it gives 3 errors. On macOS, `uint64_t` is `unsigned long long` and `size_t` is `unsigned long`, and `int64_t` is `long long` while `time_t` is `long`.
>
> Under P-W1, `fn c_getline(l: Ptr[Ptr[U8]], n: Ptr[U64], fp: Ptr[Void])` and `fn c_time(t: Ptr[Int])` build on Linux CI and fail with `ForeignPrototypeMismatch` on a Mac. Every width in those bindings is correct. That breaks Q7 of the promise decision, which says the promise covers any supported target. It breaks it for very common APIs, not for an edge case.
>
> ## Why this outweighs my Phase C reasons (AI/ML)
>
> - **The signal is wrong, not just late.** P-W1 would hand a model a named error on a correct binding, and the only fix that works is `Ptr[Void]`. That trains exactly the "make it `Ptr[Void]`" reflex I flagged as the risk of P-W1. Through that reflex, P-W1 ends up erasing anyway, but only after a confusing failure on one host.
> - **The pipe case is rare for models.** The likely model mistake is the MVCE itself, a correct pun. A typed pointer to an unrelated struct is much less likely. I overweighted it in Phase C.
> - **One rule is easier to learn.** P-E has one rule: "the pointee is your claim, and audit owns it", the same as for scalar width. P-W1 adds a coercion and a depth-sensitive erase, and its verdict depends on the platform.
>
> ## Responses
>
> - **web, devops ("a named error beats a segfault"):** I agree in principle. But here the named error also fires on correct code, depending on the host, and a false error teaches the wrong fix. devops's own concern (the cc list) is the same problem seen from the toolchain side.
> - **plt (the build can decide):** it decides how C spells the type on this target, not whether the claim is right (sys).
> - **Mitigation I keep:** Q1c yes. An audit mark makes the unchecked pointee visible where a reviewer, human or model, reads it. Q1b stays no: one spelling per binding.
>
> STABLE

- **Minimalism:**

> # [ticket] — Minimalism seat (min), Phase D round 1 (Q1)
>
> I keep P-E.
>
> **What P-W1 got right.** T-yes is decided, so the cost of a build-time check is paid already. P-W1 reuses it, and its erase-at-`Void` rule fixes the `Ptr[Ptr[Void]]` shapes. Those were my two round-1 reasons, and P-W1 does answer them. Devops and aiml are right about that.
>
> **Why I stay.** Sys's point decides it for me. The typed check that P-W1 keeps does not test "is the claim right". It tests "does C spell the type the same way on this platform":
> - `Ptr[I64]` against `long long *` fails on Linux and builds on macOS. Against `long *` it is the other way round. Blink has no type that names `long long` apart from `long`, so the only fix is `Ptr[Void]`. The check pushes users to `Void`, and the typed check is lost anyway.
> - It misses the real width fault (`Ptr[I32]` for `time_t *`) under every option.
>
> So P-W1 buys a check that is right for one class (a wrong struct pointee) and is noise for the integer pointees, at the cost of two rules: a call-site coercion and an erase rule that depends on depth. P-E costs zero rules and puts every pointee in the audited claim, beside scalar width, where §9.1 row 1 already puts it.
>
> **If P-W1 wins**, I support it on these conditions:
> - The coercion stays at `@ffi` call arguments and goes one level only. It is never a subtype (plt's concern).
> - The `ForeignPrototypeMismatch` help names `Ptr[Void]` only for a pointer to a different struct (aiml's concern).
> - File the integer-pointee portability split (`long` vs `long long`) as its own ticket. Under P-W1 it becomes a target-dependent build error with no typed fix.
>
> STABLE

#### Votes

- **Q1: what happens to a `Ptr` at the C call**
  - **Systems:**

    > # [ticket] — sys, Phase D re-vote
    >
    > ## Q1 — P-W1n
    >
    > **Reasoning.** P-W1n cuts along the line that matters to the hardware. A scalar pointee's C spelling (`int64_t` against `long`/`long long`, `uint8_t` against `char`) varies by target, so the C compiler's check of a scalar pointee is noise. P-W1n erases those pointees, and `time`, `getline` and `strtol` build on every target, as devops's and aiml's probes require. A struct or opaque name is the same on every target. Keeping that pointee typed still turns `c_pipe(fds: Ptr[SockIn])` into a named E08xx and not a store into the wrong layout at run time. Both the erase and the typed pass cost zero machine code, so the choice is about verdicts only, and P-W1n is the one option that is deterministic across targets and still catches the struct mix-up.
    >
    > **Concern.** A libc can still spell a struct-pointer parameter differently by target. glibc's `__CONST_SOCKADDR_ARG` transparent union under `_GNU_SOURCE` is one case, and a typedef of an anonymous struct is another. So the unit's feature macros must be pinned the same on every target, or a nominal pointee can split verdicts the way scalars did.

  - **Web/Scripting:**

    > # [ticket] — web, Phase D re-vote (Q1)
    >
    > 1. **Vote:** P-W1n
    >
    > 2. **Reasoning:** devops's and aiml's probes convinced me that plain P-W1 gives a false error on correct code (`time(t: Ptr[Int])`, `getline(.., n: Ptr[U64], ..)` on macOS, `Ptr[Ptr[U8]]` against `char **` everywhere). A newcomer who gets a false error learns the wrong fix, so I can't keep P-W1 as written. P-W1n removes exactly that class: scalar and `Void` pointees erase, so every correct binding builds on every target. It still keeps the one check that saves a user from silent struct corruption (`c_pipe(fds: Ptr[SockIn])` is E08xx). The rule is easy to teach: "a pointer to a C struct you named is checked against the header; any other pointer is your claim."
    >
    > 3. **Concern:** a scalar pointee of the wrong width (`Ptr[I64]` for `int *`, `Ptr[I32]` for `time_t *`) now builds and corrupts memory at run time with no message, so the docs and the audit report must say plainly that scalar pointees are unchecked.

  - **PLT:**

    > # [ticket] — PLT seat, Phase D re-vote (Q1)
    >
    > 1. **Vote:** P-W1n
    >
    > 2. **Reasoning.** Devops, aiml and min moved to P-E for one reason: the check is target-dependent for scalar pointees (`time(Ptr[Int])` and `getline(.., Ptr[U64], ..)` fail on aarch64-macos only). P-W1n removes exactly that class. Scalar and `Void` pointees erase at any depth, so those bindings build on every target. That meets Q7 and gives no `Ptr[Void]` reflex to learn on correct code. What it keeps is the one check that measures the claim and not a libc's spelling: a nominal C struct or opaque name, which is the same on every target. So `c_pipe(fds: Ptr[SockIn])` stays a named build error and does not become memory corruption at run time. The rule reads from the declaration: "a pointer to a named C type is checked by name; any other pointer is your claim".
    >
    > 3. **Concern.** A `typedef`-named struct whose tag differs from the `name:` given (or one that a libc spells differently per target) could still give a target-dependent E08xx. So the writer should state that `name:` names the C type exactly as the target header spells it.

  - **DevOps:**

    > # [ticket] — devops, Phase D re-vote (Q1)
    >
    > **Vote:** P-W1n
    >
    > **Reasoning:** I changed to P-E in D1 for one reason. My zig cc probe showed P-W1's typed check fails correct bindings (`time(Ptr[Int])`, `getline(.., Ptr[U64], ..)`) on aarch64-macos and passes them on Linux. P-W1n removes exactly that case. It erases every scalar pointee, and those are the only ones whose C spelling (`long` vs `long long`) depends on the target. It keeps the check only for named C types, whose names are the same on every target. So the verdict is the same on every target, which Q7 and a multi-target CI need. It still turns `c_pipe(fds: Ptr[SockIn])` into a named E08xx at the `@ffi` line, not memory corruption at run time. A gate that is deterministic and also catches the struct mix-up beats P-E's gate, which is deterministic but blind.
    >
    > **Concern:** A named C type can still be spelled differently on different targets. For example, a typedef name against its struct tag (`FILE` is `struct _IO_FILE` on glibc and `struct __sFILE` on macOS), or a libc that renames a struct tag with a macro (`stat` vs `stat64`). So codegen must emit the `name:` exactly as the author wrote it, and CI should run the prototype test against at least one Linux and one macOS target, to prove the "one verdict everywhere" claim.

  - **AI/ML:**

    > # [ticket] — aiml, Phase D re-vote (Q1)
    >
    > **Vote:** P-W1n
    >
    > **Reasoning.** I left P-W1 for P-E because of one problem: a correct `Ptr[Int]` or `Ptr[U64]` binding gives a named error on macOS and builds on Linux. That breaks Q7 and pushes a model toward a `Ptr[Void]` reflex on correct code. P-W1n removes exactly that case. Scalar and `Void` pointees erase, and only an `@ffi.struct` or `@ffi.opaque` pointee keeps its C name, which is spelled the same on every target. So every E08xx that is left gives the same verdict on every host, and its one fix (`Ptr[Void]` for a pointer to a different struct) is the right fix every time. The help can say that with no hedging. The model still gets a named, one-turn error for `c_pipe(fds: Ptr[SockIn])` and never a silent fault in memory, which P-E cannot give.
    >
    > **Concern.** A C struct reached only through a typedef whose tag differs per libc could still split the verdict by target. The writer should state that the C spelling a pointee keeps is the `name:` of its mirror, and give one example of the MVCE-to-`Ptr[Void]` fix, so models learn that pattern and do not reach for `Ptr[Void]` as a general cure.

  - **Minimalism:**

    > # [ticket] — Minimalism seat (min), Phase D re-vote (Q1)
    >
    > ## Vote: P-E
    >
    > ## Reasoning
    >
    > The devops and aiml probes confirm the target split. A typed pointee check rejects correct bindings (`time(Ptr[Int])`, `getline(.., Ptr[U64], ..)`) on macOS and passes them on Linux, so P-W1 fails Q7. P-W1n fixes that, but it does so with a third rule, "keep the pointee only for a named C type", on top of the coercion and the erase. It still rejects the usual sockets idiom (the MVCE) first, and it catches only an unrelated-struct mix-up, which aiml judges rare. P-E gives one verdict on every target with zero new rules. The pointee is the author's claim, beside scalar width, where §9.1 row 1 already puts it, and T-yes still catches kind, arity and struct-by-value faults.
    >
    > ## Concern
    >
    > If P-E wins, a wrong struct pointee (`c_pipe(fds: Ptr[SockIn])`) builds on every target and corrupts memory at run time, so the spec text and the audit help must say plainly that no build step checks the pointee.


### Final Spec

```blink
@ffi.struct(header: "netinet/in.h", name: "sockaddr_in")
type SockIn { sin_family: U16, sin_port: U16, sin_addr: U32, sin_zero: I64 }

@ffi.struct(header: "netinet/in.h", name: "sockaddr_in6")
type SockIn6 { sin6_family: U16, sin6_port: U16, sin6_flowinfo: U32, sin6_addr0: U32, sin6_addr1: U32, sin6_addr2: U32, sin6_addr3: U32, sin6_scope_id: U32 }

@ffi("connect", header: "sys/socket.h")
@trusted(audit: "NET-CONNECT")
fn c_connect(fd: I32, addr: Ptr[Void], len: U32) -> I32 ! () {}   // OK: one binding for v4 and v6

@ffi("pipe", header: "unistd.h")
@trusted(audit: "UNISTD-PIPE")
fn c_pipe(fds: Ptr[SockIn]) -> I32 ! () {}
// blink build: error[ForeignPrototypeMismatch] (E0861) at the @ffi line, exit 1

@ffi("time", header: "time.h")
@trusted(audit: "TIME-TIME")
fn c_time(t: Ptr[Int]) -> Int ! ()                                // builds: a scalar pointee erases to `void *`

fn main() {
    with ffi.scope() as scope {
        let a4: Ptr[SockIn] = scope.alloc[SockIn]()
        let a6: Ptr[SockIn6] = scope.alloc[SockIn6]()
        io.println("{c_connect(-1, a4, 16)}")      // OK: an `@ffi` call argument
        io.println("{c_connect(-1, a6, 28)}")      // OK
        let v: Ptr[Void] = a4                      // ERROR E0300: not an `@ffi` call argument
    }
}
```

- At an `@ffi` call argument only, and one level deep, a `Ptr[T]` passes to a `Ptr[Void]` parameter. It is not a subtype.
- C keeps the pointee type of an `@ffi.struct` or `@ffi.opaque` pointee. Every other pointee becomes `void *` at every depth.
- `blink build` and `blink test` test each `@ffi` declaration against its header and stop with E0861. `blink check` does not.
- `blink audit` marks a `Void` or scalar pointee "not checked against the header".
