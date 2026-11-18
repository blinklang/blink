[< All Decisions](../DECISIONS.md)

# A `lib/std` Handle to a Runtime-Owned C Type — Design Rationale

**Gap:** §9.1.4 writes `@ffi.opaque(header, name)` and says a missing `header` or `name` is a malformed annotation. `lib/std` declares six handles with a `name` and no `header` (`@ffi.opaque(name: "blink_tcp_handle")`) for C types that the runtime defines. An install has no runtime header on the C include path. In user code, a header-less `@ffi.opaque` checked clean and then failed in the C compile.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | How `lib/std` declares a runtime-owned C type | `Runtime`: a bodiless type with `@runtime("blink_x")`. The `@runtime` gates apply (`lib/std` only, a `blink_` symbol, else E0849). No `#include` and no `@ffi` signature check. `@ffi.opaque` needs `header` and `name` everywhere (E1134), and a `blink_` name in `@ffi.opaque` is E0849 in every package | 6-0 |
| Q2 | The spelling | `Bare`: `@runtime("blink_tcp_handle") pub type TcpHandle` | 6-0 |
| Q3 | Whether `blink audit` tags a `@runtime` handle `opaque-ffi-handle` | `NoTag`: it is runtime ABI | 6-0 |

Shared by all six seats (not on the ballot):

- User code `@ffi.opaque(name: "x")` with no `header` is E1134 at check, with a help that prints the full form. It no longer reaches the C compile.
- User code `@ffi.opaque(header: .., name: "blink_...")` is E0849 at check.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote rounds. There was no Phase D. Each panelist's text below is a verbatim excerpt of the panelist's own reply.

### Phase A — Independent proposals


- **Systems:**

> ## G3: an `@ffi.opaque`-like handle to a runtime-owned C type
>
> ### Proposal G3-A (my pick): `@runtime` on a bodiless type; `@ffi.opaque` keeps `header` required
>
> `lib/std` names a runtime C type with the runtime bridge it already uses for functions:
>
> ```blink
> // lib/std/net_tcp.bl
> @runtime("blink_tcp_handle")
> pub type TcpHandle
>
> @runtime("blink_tcp_handle_new")
> fn tcp_handle_new(fd: Int) -> TcpHandle
> ```
>
> Behavior:
>
> - A `@runtime` type has the same semantics as an `@ffi.opaque` type: bodiless, nominal, inert, maps to `blink_tcp_handle *`, `Option[TcpHandle]` maps to a nullable pointer, minted only at the boundary (here: a `@runtime` or `@ffi` return). A body is E1134.
> - It has no header. Codegen emits no `#include`: the runtime text that the compiler puts into the C already declares the type.
> - The `@runtime` rules apply as they are: only `lib/std` (else E0849), the name starts with `blink_` (else E0849).
> - `@ffi.opaque(..., name: "blink_x")` anywhere is E0849, by the existing rule "a `blink_` symbol belongs to the runtime" widened from symbols to C type names. The help points to the stdlib type that wraps it.
> - `@ffi.opaque` without `header` is E1134 at check, in user code and in `lib/std`. The six `lib/std` handles move to `@runtime`.
>
> Q3, user code today: `@ffi.opaque(name: "x")` with no `header` is E1134 `AnnotationArguments` in `blink check`, help prints `@ffi.opaque(header: "...", name: "...")`. That turns today's ICE (C "unknown type name x") into a check error, so a clean check again promises the build.
>
> ```blink
> @ffi.opaque(name: "sqlite3")                              // E1134: missing `header`
> type Db
>
> @ffi.opaque(header: "x.h", name: "blink_tcp_handle")      // E0849: `blink_` belongs to the runtime
> type Mine
>
> @runtime("blink_tcp_handle")                              // E0849 outside lib/std
> type Also
> ```
>
> Systems tradeoffs:
>
> - Cost: zero; both forms are a C pointer typedef use. The difference is only who declares the C type. With `@runtime` the compiler knows the type is in its own prologue, so the header probe (E0859) and the `#include` are both skipped by rule, not by a missing argument.
> - One owner per prefix: `blink_` functions and `blink_` types both bind only through `@runtime` in `lib/std`. The E0849 check is one string test for both. The runtime ABI stays private: user code cannot name `blink_tcp_handle`, so the runtime can change that struct without a user break.
> - `header` stays mandatory for user code: the build must probe each header (E0859) and the C compile needs the type declared. A header-less user form has nothing to probe and can only fail in `cc`, which is the ICE we have now.
> - Note: the same `lib/std` files bind `blink_tcp_handle_new` with `@ffi("blink_...")`, which §9.1 already makes E0849. Moving the types to `@runtime` fits the same open migration.
>
> Cross-language: Rust's `extern { type Foo; }` (unstable) is header-free because Rust has no headers; Zig `opaque {}` likewise. Go's runtime types are reachable only through the `runtime` package. Blink's split (headers for C, a private bridge for the runtime) is the Go shape.
>
> ### Proposal G3-B (acceptable): header-less `@ffi.opaque` only for a `blink_` name in `lib/std`
>
> `@ffi.opaque(name: "blink_x")` with no header is legal only in `lib/std`; elsewhere a missing header is E1134 and a `blink_` name is E0849. Same codegen and cost as G3-A. Tradeoff: one annotation then has two argument rules keyed on module path and name prefix, and `@ffi` would bind a `blink_` name, which the E0849 rule says only `@runtime` does. I rank it second.
>
> ### Not proposed
>
> A reserved header string such as `header: "<runtime>"`: a magic value inside a C header slot, which the E0859 probe and the include emitter must each special-case.

- **Web/Scripting:**

> ## G3: @ffi.opaque with no header
>
> ### Proposal G3-A (my pick): `@ffi.opaque` keeps its form; lib/std uses `@runtime.opaque(name)`
>
> - `@ffi.opaque(header, name)` stays as written. A missing `header` is E1134 at `blink check`, in every package, lib/std included. The help prints the form.
> - lib/std declares a handle to a runtime type with a new form `@runtime.opaque(name: "blink_tcp_handle")`. It gets the `@runtime` rules: only lib/std may write it (E0849 elsewhere), and the name must start with `blink_` (E0849 when not). The type has the same behavior as an `@ffi.opaque` type: nominal, inert, `Option` maps to NULL. The compiler emits no `#include`; the runtime text already defines the type.
> - An `@ffi.opaque` whose `name` starts with `blink_`, in any package, is E0849, by the rule "a `blink_` symbol belongs to the runtime".
>
> ```blink
> // lib/std/net_tcp.bl
> @runtime.opaque(name: "blink_tcp_handle")
> type TcpHandle
>
> // app/main.bl
> @ffi.opaque(name: "my_handle")               // ERROR E1134 at check: missing `header`
> type MyHandle                                 // help: @ffi.opaque(header: "...", name: "...")
>
> @ffi.opaque(header: "runtime_tcp.h", name: "blink_tcp_handle")   // ERROR E0849 at check
> type Stolen                                   // help: use the std.net type that wraps it
>
> @runtime.opaque(name: "blink_tcp_handle")    // ERROR E0849: `@runtime` is reserved for lib/std
> type Stolen2
> ```
>
> - Q0: user-facing text stands (header required). lib/std moves to a new form.
> - Q1: a new `@runtime.opaque(name)`.
> - Q2: reserved to lib/std, by the same rule as `@runtime`.
> - Q3: E1134 at check. Never a C compile failure.
>
> Tradeoffs (DX):
> - Users read one rule in the docs: "`@ffi.opaque` needs `header` and `name`". No footnote "except in lib/std". A user who copies a lib/std file sees a different annotation, and the `@runtime` docs explain it in one line: "this is how lib/std talks to the runtime".
> - Today the user case is the worst one: clean check, then a C error. That breaks the "clean check means the build works" promise (§6.7.1). Any rule that fails at check fixes it.
> - Cost: one more annotation name, but users never write it.
>
> ### Proposal G3-B (accept, not my pick): header is optional only for a `blink_` name in lib/std
>
> Same behavior, no new annotation: `@ffi.opaque(name: "blink_...")` with no header is legal in lib/std only. Outside lib/std, no header is E1134 and a `blink_` name is E0849. Less to add to the compiler, but the docs for `@ffi.opaque` must carry a lib/std exception, and a user who reads lib/std as an example will copy the header-less form and get E1134. A then reads more clearly.

- **PLT:**

> ## G3: a lib/std handle to a C type that the runtime owns
>
> Facts that decide it: the decided E0849 rule already makes `@ffi("blink_tcp_handle_new")` in `net_tcp.bl` an error, so these handles' functions move to `@runtime`. The §9.1.4 mint rule says a handle comes from "the return value of an `@ffi` function". Once the functions are `@runtime`, that rule no longer covers these handles. So a header-less `@ffi.opaque` exception in lib/std would leave a handle that no legal declaration can produce.
>
> ### G3-A (my pick): `@runtime` on a type
>
> ```blink
> // lib/std/net_tcp.bl
> @runtime("blink_tcp_handle")
> pub type TcpHandle
>
> @runtime("blink_tcp_handle_new")
> fn tcp_handle_new(fd: Int) -> TcpHandle
> ```
>
> Behavior:
> - `@runtime("blink_x") type H` declares a bodiless nominal handle with every §9.1.4 property: inert, flows through ordinary code, `Option[H]` is NULL. It needs no header, because the compiler puts the runtime's text into the C, so the C name is always declared. A clean check promises the build (§6.7.1).
> - It obeys the `@runtime` gates: outside lib/std it is E0849; a name that does not start with `blink_` is E0849.
> - A value of `H` comes from the return of a `@runtime` fn, or from a `Ptr` cell in an FFI region, as for `@ffi.opaque`.
> - `@ffi.opaque` keeps `header` required everywhere. A missing `header` is E1134 at check (answers Q3 and removes today's internal compiler error).
> - An `@ffi.opaque` whose `name` starts with `blink_` or `__blink_` is E0849, in any package, lib/std included. C keeps typedef names and functions in one namespace, so the runtime's prefix covers its type names too. So `@ffi.opaque(header: "runtime_tcp.h", name: "blink_tcp_handle")` in user code is E0849 at check, not E0859 at build.
>
> User code:
>
> ```blink
> @ffi.opaque(name: "sqlite3")
> type Db                          // E1134: `@ffi.opaque` needs `header`
>
> @ffi.opaque(header: "x.h", name: "blink_tcp_handle")
> type T                           // E0849: `blink_` belongs to the runtime
>
> @runtime("blink_tcp_handle")
> type U                           // E0849: `@runtime` is reserved for lib/std
> ```
>
> PLT tradeoffs:
> - **One trust base, one annotation.** `@runtime` already marks "the runtime ABI, which the compiler owns". A runtime type belongs there, not in `@ffi`, whose rules (header, signature types, audit) speak about foreign C. No exception in either rule.
> - **Q2 by the existing rule.** Reserved to lib/std by the `@runtime` package rule, not by a module-path test or a name test inside `@ffi`.
> - **Check ⇒ build.** Each of the three user forms above fails at check, with a code. No form passes check and then fails in the C compile.
> - **Audit.** Crossings of a `@runtime` handle are runtime ABI, like `@runtime` fns, which are outside the signature rule. I would not tag them `opaque-ffi-handle`. Other seats may weigh this.
>
> ### G3-B (rejected by me): header-less `@ffi.opaque` in lib/std when `name` starts with `blink_`
>
> - It puts a package test and a prefix test inside `@ffi.opaque`, so the rule has an exception.
> - It leaves no legal producer: `@ffi` cannot bind `blink_` functions (E0849), and the §9.1.4 mint rule names only `@ffi`. Either the mint rule grows a `@runtime` case anyway, or the handle cannot be built.
> - It answers Q3 the same way (E1134 for user code), so its only gain is no new annotation target.
>
> Cross-language: GHC keeps its own runtime types (`MutVar#`, `ThreadId#`) as primitive types in `GHC.Prim`, apart from `foreign import` types. Rust std does the same with lang items. Both keep the runtime ABI apart from the user FFI.

- **DevOps:**

> ## G3: a `lib/std` opaque handle to a runtime-owned C type
>
> Q0: the text "a missing `header` is E1134" stands for `@ffi.opaque` everywhere. `lib/std` moves to a runtime form, the same move §9.1 already made for functions (`@ffi("blink_tcp_handle_new")` in `lib/std/net_tcp.bl` is already E0849 under the current text and must become `@runtime`).
>
> ### Proposal G3-A (my pick): `@runtime.opaque("blink_symbol")`
>
> ```blink
> // lib/std/net_tcp.bl
> @runtime.opaque("blink_tcp_handle")
> pub type TcpHandle
>
> @runtime("blink_tcp_handle_new")
> fn tcp_handle_new(fd: Int) -> TcpHandle
> ```
>
> - The type has every property of an `@ffi.opaque` type (nominal, bodiless, inert, `Option` = NULL, minted only at the boundary). Only the source of the C type differs: the runtime text the compiler already writes into the C, so no header and no `#include`.
> - It follows the `@runtime` rules: only `lib/std` (else E0849, at the annotation); the name must start with `blink_` (else E0849, at the string).
> - The `blink_` rule covers type names too. `@ffi.opaque(header: "x.h", name: "blink_tcp_handle")` anywhere is E0849 at the name string, with the help "use the standard library type that wraps it" (here `TcpSocket`). This also kills fact 4 (clean check, then E0859, then a bad `#include`).
> - Annotation table: one new row, `@runtime.opaque(symbol)`, target type, "lib/std only".
>
> **Q3, what user code gets at check:**
>
> ```blink
> @ffi.opaque(name: "sqlite3")
> type Db
> ```
>
> ```
> error[AnnotationArguments]: `@ffi.opaque` needs `header` and `name`
>  --> db.bl:1:1
>   |
> 1 | @ffi.opaque(name: "sqlite3")
>   |            ^^^^^^^^^^^^^^^^^ `header` is missing
>   |
>   = help: write `@ffi.opaque(header: "<file>.h", name: "sqlite3")`; the header is resolved against `[native-dependencies].headers`
> ```
>
> E1134 at check, exit 1. The fix is not machine-applicable (only the user knows the header). With `name: "blink_..."` the error is E0849 only, not also E1134: the one actionable fix is "use the std type", and a second error about the header would send the user the wrong way.
>
> Tradeoffs from my seat:
> - **Visible at the declaration.** A reader and `blink audit` see "runtime-owned" on the line, the same as `@runtime` on a fn. A path rule (G3-C) hides the exemption in where the file lives; the language server cannot explain an error that depends on the file path.
> - **Hover can say what it is**: "opaque handle to the runtime type `blink_tcp_handle`", with no fake header to show.
> - `blink audit` can list runtime handles apart from C library handles; they need no audit record, because the runtime is the trusted base.
>
> ### Proposal G3-B (reject): a reserved header name, e.g. `header: "<blink/runtime>"`
>
> A magic string that the header lookup must special-case and the user can type. The language server must teach that one string is special. Codegen must not emit it. More surface than G3-A for the same result.
>
> ### Proposal G3-C (reject): `header` optional in `lib/std` only, by module path
>
> No mark at the site, a rule that depends on the file's path, and a user who copies a `lib/std` line gets E1134 with no clue why the same line works in std.
>
> Cross-language: Rust's std uses `#[lang = "..."]` items and `rustc_*` attributes that user crates cannot use; Go's runtime uses `//go:linkname`, now restricted to std. Both mark the item at the site, which is what G3-A does.

- **AI/ML:**

> ## G3: a lib/std handle to a runtime-owned C type
>
> Facts I checked: §9.1.4 writes `@ffi.opaque(header, name)` and says a missing `header` reuses the malformed-annotation diagnostic (E1134). `@runtime("blink_symbol")` is the lib/std-only bridge to the runtime, with the `blink_` prefix and E0849 for any other use. All six lib/std handles name `blink_` types.
>
> ### G3-P1 (my pick): `@runtime` on a bodiless type declares the handle; `@ffi.opaque` always needs a header
>
> - `@runtime("blink_tcp_handle")` on a bodiless `type` declares an opaque handle to that runtime C type. It behaves as an `@ffi.opaque` handle does (nominal, inert, `Option` maps to NULL, minted only at the boundary). It emits no `#include`.
> - The E0849 rules of `@runtime` apply as written: only lib/std may use it, and the name must start with `blink_`.
> - `@ffi.opaque` needs both `header` and `name`, in every package. A missing `header` is E1134 at check, and the help prints `@ffi.opaque(header: "...", name: "x")`. This answers Q3: user code with `name` and no `header` gets E1134 from `blink check`, never an ICE at C compile.
> - `@ffi.opaque(header: ..., name: "blink_...")` is E0849, as for any other binding of a `blink_` name.
>
> ```blink
> // lib/std/net_tcp.bl
> @runtime("blink_tcp_handle")
> type TcpHandle
>
> @runtime("blink_tcp_connect")
> fn tcp_connect(host: Str, port: Int) -> TcpHandle?
> ```
>
> ```blink
> // app/main.bl
> @ffi.opaque(name: "x")                                 // error[E1134]: `@ffi.opaque` needs `header`
> type X                                                 // help: @ffi.opaque(header: "...", name: "x")
>
> @runtime("blink_tcp_handle")                           // error[E0849]: `@runtime` is reserved for lib/std
> type MyTcp
>
> @ffi.opaque(header: "net.h", name: "blink_tcp_handle") // error[E0849]: `blink_` belongs to the runtime
> type MyTcp2
> ```
>
> Why, from my seat:
>
> - **lib/std is training data.** Models read and copy lib/std source. If lib/std writes `@ffi.opaque(name: "blink_tcp_handle")` with no header, a model copies that shape into user code, gets E1134 "needs header", and then invents a header (`runtime_tcp.h`), which checks clean and fails later at build with E0859. Three steps, the last one late. With `@runtime`, a copied line fails at once with E0849, whose text says why ("reserved for lib/std") and points to the public API. One step, and the error is true.
> - **No new name.** `@runtime` already means "this binds the runtime, lib/std only, `blink_` names". A type is one more thing it binds. A model learns zero new annotations. The user-facing form of `@ffi.opaque` stays one form with no exception.
> - **The reserve rule stays syntactic.** It is the same module rule and prefix rule as today, not a new "lib/std may drop the header" clause hidden in §9.1.4.
>
> Cross-language: Zig writes `opaque {}` and needs no header because it imports C through `@cImport`; Rust's `extern type` (unstable) has no header either. Neither has a runtime/user split, so there is no close match. Go's `runtime` package uses `//go:linkname`, which Go also limits to the standard library, the same split as here.
>
> ### G3-P2: header optional only in lib/std, only for a `blink_` name
>
> `@ffi.opaque(name: "blink_x")` with no header is legal in lib/std; in any other package it is E1134 (no header) or E0849 (a `blink_` name).
>
> Tradeoffs: no change to lib/std source. But the form a model sees most often in lib/std is the one form it may not write, and nothing at the site says so. The E1134 help then pushes the model to make up a header. I rank it below P1.
>
> ### G3-P3: a reserved header string (for example `header: "blink:runtime"`)
>
> Tradeoffs: keeps one annotation, but adds a magic string that a model will copy and that needs its own refusal rule outside lib/std. More to learn than P1, with no gain.

- **Minimalism:**

> ## G3: `@ffi.opaque` for a runtime type with no header
>
> Q0: the text for user code stands. Lib/std needs a door, but we already have one: the `blink_` prefix rule (*A `blink_` Symbol Belongs to the Runtime*). Extend that rule to types. No new annotation, no reserved header name, no pseudo-module.
>
> ### Proposal G3-A (my pick): the `blink_` prefix decides
>
> - `@ffi.opaque(name: N)` with no `header`:
>   - legal only when `N` starts with `blink_` and the declaration is in `lib/std`. The type is a runtime type; the compiler already has its C text, so it emits no `#include`.
>   - in user code: E1134 `AnnotationArguments` at check (the current text). This answers Q3.
> - `@ffi.opaque` whose `name` starts with `blink_` or `__blink_` outside `lib/std`, with or without `header`: E0849 `InvalidRuntimeBinding` at the name string, at check. Same rule and same code as for a function symbol: the prefix belongs to the runtime.
> - In `lib/std`, a `blink_` name with a `header`: E0849 too. A runtime type has no header.
>
> ```blink
> // lib/std/net_tcp.bl
> @ffi.opaque(name: "blink_tcp_handle")                          // OK: lib/std, runtime type
> pub type TcpHandle
>
> // app/main.bl
> @ffi.opaque(name: "my_handle")                                 // E1134: `header` is missing
> type MyHandle
>
> @ffi.opaque(header: "runtime_tcp.h", name: "blink_tcp_handle") // E0849: `blink_tcp_handle` is a runtime type
> type Stolen
>
> @ffi.opaque(header: "mylib.h", name: "my_handle")              // OK, as today
> type Good
> ```
>
> Tradeoffs:
> - Zero new syntax. The rule "a `blink_` name belongs to the runtime" already exists for symbols; this says it covers type names too, which is the same C namespace.
> - Fact 4 (check clean, then E0859) and fact 5 (check clean, then ICE) both become check-time errors, so a clean check promises the build (§6.7.1).
> - Lib/std code does not change: the six handles already have this exact form.
> - Note for the record: those lib/std files also bind `blink_` functions with `@ffi`, which the decided E0849 rule refuses. That move to `@runtime` is open compiler work, not part of this ticket.
>
> ### Proposal G3-B (not my pick): `@runtime` on a type
>
> `@runtime("blink_tcp_handle") type TcpHandle`, lib/std only (E0849 elsewhere). Clean in concept, since `@runtime` is already the lib/std-only bridge. But it gives `@runtime` a second meaning (types as well as functions) and changes six declarations for no gain in behavior. Acceptable if the panel thinks a prefix check on a type name is too implicit.
>
> ### Not proposed
> - A reserved header name (`header: "<runtime>"`): a magic string, a second way to say what the prefix says.
> - Opening the header-less form to user code: the C build then fails with an ICE (fact 5), and there is no way for the compiler to know the type.


### Phase B — Debate highlights

The Phase B digest set `Runtime` (a bodiless `@runtime` type; sys, aiml, plt) against `Exempt` (a header-less `@ffi.opaque` for a `blink_` name in `lib/std`; min). PLT's argument against `Exempt`: the decided E0849 rule already refuses `@ffi("blink_tcp_handle_new")`, so those functions move to `@runtime`, and the §9.1.4 mint rule names only `@ffi` returns. All six seats marked STABLE, and min moved to `Runtime`.


- **Systems:**

> ## G3-Q1: how lib/std names a runtime C type
>
> Position: **G3-Runtime**.
>
> Against G3-Exempt: plt's mint argument settles it. The decided E0849 already refuses `@ffi("blink_tcp_handle_new")`, so those functions must move to `@runtime`. §9.1.4 lets a handle be minted only by an `@ffi` return or an FFI-region read. So under Exempt no legal declaration can produce a `TcpHandle`, unless the spec adds a second exception. Exempt also leaves `@ffi` binding a `blink_` name, which E0849 says only `@runtime` does. Codegen is the same for both options: a `blink_x *` with no `#include`. The only difference is which rules the compiler checks, and Runtime uses rules the spec already has.
>
> ## G3-Q2: spelling
>
> Position: **`@runtime("blink_tcp_handle")`** on a bodiless type. `@runtime.opaque("blink_tcp_handle")` is acceptable.
>
> Argument: the runtime never exposes a struct layout to Blink, so a `@runtime` type can only be an opaque handle. `.opaque` adds a name that has no alternative. One annotation and one gate (lib/std plus the `blink_` prefix) for both functions and types is one string check in the compiler. The declaration form (bodiless `type` or `fn`) already says which one it is. A body on a `@runtime` type is E1134.
>
> On plt's audit note: I agree. Do not tag `@runtime` handles `opaque-ffi-handle`. They belong to the runtime's trusted base, not to a user's C binding, so they have no audit claim.
>
> STABLE

- **Web/Scripting:**

> ## G3-Q1: lib/std handle to a runtime type
>
> **Position: G3-Runtime.**
>
> Against G3-Exempt: plt's producer argument settles it for me. The decided E0849 rule already moves the `blink_` functions to `@runtime`, and the §9.1.4 mint rule names only `@ffi` returns. So Exempt needs a `@runtime` exception in the mint rule anyway, plus a lib/std footnote in the user-facing `@ffi.opaque` docs. The DX cost is real: users read lib/std as example code, copy the header-less form, and get E1134. Under Runtime, the copied form gets E0849 with the help "`@runtime` is reserved for lib/std", which tells them why.
>
> ## G3-Q2: spelling
>
> **Position: `@runtime("blink_tcp_handle") type TcpHandle`. I drop my `@runtime.opaque(name: ..)`.**
>
> It is one annotation with one argument form, on a fn or a bodiless type, and users never write it. A second name adds nothing a reader needs.
>
> On plt's audit note: agree, do not tag `@runtime` handles `opaque-ffi-handle`. A user runs `blink audit` to see their own FFI surface, and lib/std runtime plumbing in that list is noise.

- **PLT:**

> ## G3-Q1: how lib/std names a runtime-owned C type
>
> Position: **G3-Runtime**. G3-Exempt is acceptable only with the mint fix below.
>
> Against G3-Exempt (min). min writes "Lib/std code does not change". That is true only for the six `@ffi.opaque` lines. The functions that mint and take these handles (`@ffi("blink_tcp_handle_new")` and others) are already E0849 under the decided rule, so they move to `@runtime` in any case. min says so too ("open compiler work"). After that move, the §9.1.4 mint rule ("the return value of an `@ffi` function") covers no producer of a `blink_` handle. Exempt then needs a second exception in the mint rule. So Exempt puts two lib/std exceptions inside `@ffi`, whose rules exist for foreign C. Runtime puts the type where its functions already are: one trust base, one gate, no exception.
>
> The two options give users the same behavior (E1134 with no header, E0849 for a `blink_` name). They differ only in where lib/std's rule lives.
>
> ## G3-Q2: the spelling
>
> Position: **`@runtime("blink_tcp_handle") pub type TcpHandle`**. It is the same annotation with the same argument form as on a fn. The declaration kind (a bodiless `type`) already says "handle". `@runtime.opaque` adds a name that has nothing to contrast with until `@runtime` gets a second kind of type. Both are sound. This is a weak preference.
>
> Audit tag: no seat answered my question. I keep my view: a `@runtime` handle is runtime ABI and is not tagged `opaque-ffi-handle`.
>
> STABLE

- **DevOps:**

> ## G3-Q1: how lib/std names a runtime-owned C type
>
> **Position: G3-Runtime.**
>
> Against G3-Exempt (min): plt's mint point decides it. The decided E0849 moves every `blink_` fn in lib/std to `@runtime`, and §9.1.4 mints a handle only from an `@ffi` return. Exempt leaves a handle no legal declaration produces, unless the mint rule grows a `@runtime` case, which is G3-Runtime by another name. From my seat: the exemption is invisible at the site. A user who copies `@ffi.opaque(name: "blink_tcp_handle")` from std gets E0849 and cannot see why the same line is fine in std. A distinct annotation explains itself on hover.
>
> On min's "six declarations change": they change anyway, since their fns move to `@runtime` in the same files.
>
> ## G3-Q2: spelling
>
> **Position: `@runtime("blink_x")` on a type. I drop `@runtime.opaque`.**
>
> One annotation with two targets (fn, type) is one table row and one gate. The diagnostic loss is small: a `@runtime` type with a body gets the same error as an `@ffi.opaque` with a body. No seat showed a case that the extra `.opaque` makes clearer.
>
> ## G3 note (audit)
>
> Agree with plt: do not tag `@runtime` handle crossings `opaque-ffi-handle`. They are runtime ABI with no audit record, like `@runtime` fns. Tagging them would list std internals in every user's FFI inventory, which is noise in the one report meant to show the user's own foreign code.

- **AI/ML:**

> ## G3-Q1: how lib/std names a runtime type
>
> **Position: G3-Runtime.**
>
> Against G3-Exempt (min): lib/std is training data. Models read and copy lib/std. If lib/std writes `@ffi.opaque(name: "blink_tcp_handle")` with no header, a model copies that form, gets E1134 "needs `header`", and then makes up a header (`runtime_tcp.h`). That passes check and fails at build with E0859. Under Runtime, a copied `@runtime(...)` line fails at once with E0849 "reserved for lib/std", which is the true reason. plt's point settles it from the language side too. E0849 already moves the handle's functions to `@runtime`, and the §9.1.4 mint rule names only `@ffi` returns. So Exempt leaves a handle that no legal declaration can produce.
>
> ## G3-Q2: spelling
>
> **Position: bare `@runtime("blink_tcp_handle")` on the type. `@runtime.opaque("blink_tcp_handle")` (devops's positional form) is acceptable.**
>
> The spec already chooses by declaration kind for `@ffi`: the same annotation binds a fn, or a `let` (`@ffi("blink_flags", header: ...) pub let`). `@runtime` on a fn or a type follows that precedent, adds no annotation name, and keeps the E0849 text ("`@runtime` is reserved for lib/std") true as written. `@runtime.opaque` gains a match with `@ffi.opaque`, which helps a reader. Few people outside lib/std ever write either form, so the cost to learn either is small. If the panel prefers `.opaque`, I ask for the positional form to match `@runtime("sym")`, not `name:`.
>
> Audit tag (plt's note): agree. A runtime handle is part of the trusted runtime ABI and needs no `opaque-ffi-handle` audit entry.

- **Minimalism:**

> ## G3-Q1: G3-Runtime (moved from G3-Exempt)
>
> plt's point decides it. The decided E0849 already moves `blink_tcp_handle_new` and its siblings from `@ffi` to `@runtime`. The §9.1.4 mint rule says a handle comes only from an `@ffi` return or a `Ptr` read in an FFI region. So under G3-Exempt, no legal declaration could produce a header-less handle unless we also amend the mint rule. That is two exceptions, against one door (`@runtime`) that already exists and is already lib/std-only. G3-Runtime also leaves `@ffi.opaque` with one form and no exception, which is the smaller result.
>
> ## G3-Q2: `@runtime("blink_tcp_handle")` on the bodiless type
>
> It is the same annotation and the same argument form as on a function, and no new sub-name. `@runtime.opaque(...)` adds a second spelling of something the bodiless type already says. A `@runtime` type has no body, so it is opaque by construction.
>
> I agree with plt: do not tag `@runtime` handles `opaque-ffi-handle`. They are runtime ABI, not FFI.
>
> STABLE


### Phase C — Silent ballot

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. How `lib/std` declares a runtime-owned C type | Runtime | Runtime | Runtime | Runtime | Runtime | Runtime | Runtime, 6-0 |
| Q2. Spelling | Bare | Bare | Bare | Bare | Bare | Bare | Bare, 6-0 |
| Q3. Audit tag for a `@runtime` handle | NoTag | NoTag | NoTag | NoTag | NoTag | NoTag | NoTag, 6-0 |


- **Systems:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** Codegen is the same either way: a `blink_x *` with no `#include`. Runtime reuses the gates the spec already has (lib/std only, a `blink_` prefix, E0849). It also fits the decided move of the `blink_` functions to `@runtime`, so the mint rule needs no second exception. A `blink_` name now has one binder for both functions and types.
> **Concern:** The compiler must declare every `@runtime` type's C name in the prologue in every emit mode, including archive-linked builds, or the C compile fails as an internal compiler error.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** The runtime never exposes a struct layout to Blink, so a `@runtime` type can only be an opaque handle, and `.opaque` names a choice that has no alternative. The declaration kind (a bodiless `type` or a `fn`) already says which one it is. With one annotation, the compiler does one gate check for both.
> **Concern:** A reader may not know that a bare `@runtime` on a type means "opaque handle" without reading §9.1.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** A `@runtime` handle belongs to the runtime's trusted base, which ships with the compiler. It is not a C binding that the user wrote and has to audit. Tagging it would add stdlib internals to every user's FFI inventory and hide the user's own handles among them.
> **Concern:** An auditor who wants the whole native surface, runtime included, gets no list from `blink audit` and must read lib/std.

- **Web/Scripting:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** The user-facing `@ffi.opaque` docs keep one rule with no lib/std footnote. A user who copies a lib/std handle gets E0849 "`@runtime` is reserved for lib/std", which says why, not a bare E1134. plt's producer point settles it: the `blink_` functions move to `@runtime` anyway, so Exempt needs a second exception in the mint rule.
> **Concern:** lib/std authors must move six declarations and their functions together, and a half-done move must fail at check, not in the C compile.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** One annotation with one argument form, on a fn or a bodiless type, is less to read. Users never write it, so a second name gives no reader any gain.
> **Concern:** A reader of lib/std may not see at a glance that `@runtime` on a type declares a handle, so §9.1.4 must show the form next to `@ffi.opaque`.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** A user runs `blink audit` to see their own FFI surface. lib/std runtime plumbing in that list is noise, and it hides the rows the user must review.
> **Concern:** A security reviewer who wants the full trust base must know that runtime handles sit under `@runtime`, not in the FFI inventory.

- **PLT:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** The functions that make and take these handles must move to `@runtime` anyway (the decided E0849 rule). After that, the §9.1.4 mint rule (an `@ffi` return) covers no producer of a `blink_` handle. Runtime puts the type in the same trust base as its functions, with one gate and no exception in `@ffi`. User-visible behavior is the same under both options.
> **Concern:** The mint rule for a `@runtime` handle (a `@runtime` return, or a Ptr cell in an FFI region) must be written down, not left implied by §9.1.4.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** It is the same annotation with the same argument form as on a fn, and the bodiless `type` already says "handle". `.opaque` adds a name that has nothing to contrast with. Both are sound.
> **Concern:** If `@runtime` later gets a second kind of type, the bare form may need a qualifier then.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** `@runtime` declarations are the compiler's own trusted ABI, outside the signature rule and outside the user's FFI. Tagging them would put stdlib internals in every user's FFI inventory, and the user did not write those crossings and cannot audit them.
> **Concern:** A user who wraps a std handle may expect `blink audit` to list it. The audit docs should say that runtime handles are left out on purpose.

- **DevOps:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** The mark is visible where the type is declared, so hover can say "runtime-owned handle" and E0849 explains itself. Exempt hides the rule in the file path, so a line copied from std gets an error with no visible cause. Exempt also needs a second mint exception for `@runtime` returns, which is Runtime by another name. The six std files change anyway when their fns move to `@runtime`.
> **Concern:** The compiler must emit no `#include` and no `@ffi` signature check for a `@runtime` type, or fact 4 (clean check, broken build) comes back by another path.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** One annotation, two targets (fn, type), one table row and one gate. No case was shown where `.opaque` makes a diagnostic clearer; a `@runtime` type with a body gets the same body error as `@ffi.opaque`.
> **Concern:** The E1110 target message for `@runtime` must list both fn and type, or a misplaced one gives a confusing "not a target" error.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** These crossings are runtime ABI with no audit record, like `@runtime` fns. A tag would put std internals in every user's FFI inventory, which is noise in the one report meant to show the user's own foreign code.
> **Concern:** A future std bug at a runtime handle crossing will not show in `blink audit`, so std review must cover these sites.

- **AI/ML:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** lib/std is training data. A copied header-less `@ffi.opaque` gets E1134, the model then invents `runtime_tcp.h`, and the build fails late with E0859. A copied `@runtime` line fails at once with E0849, whose text gives the true reason. Exempt also leaves a handle that no legal declaration produces unless the mint rule gets a second exception.
> **Concern:** Six lib/std declarations and their producer functions must move in one change, or lib/std stops checking.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** `@ffi` already chooses its meaning by declaration kind (a fn or a `let`), so `@runtime` on a type follows a known pattern and adds no annotation name. The E0849 text "`@runtime` is reserved for lib/std" stays true as written. Few people outside lib/std ever write either form, so the cost to learn either is small.
> **Concern:** A reader who knows `@ffi.opaque` may look for `@runtime.opaque` first and miss that bare `@runtime` covers types.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** A runtime handle is part of the trusted runtime ABI, like a `@runtime` fn, and the user did not write it. Tagging it would fill every user's FFI audit list with entries they cannot act on. That noise teaches people and models to skim the audit list.
> **Concern:** A user who wants a full list of every C pointer type in their binary will not find the runtime handles in `blink audit`.

- **Minimalism:**

> ## G3-Q1
> **Vote:** Runtime
> **Reasoning:** `@runtime` is already the one door that only lib/std may use, and the decided E0849 moves the handle functions onto it anyway. Exempt would need two exceptions: a header-less `@ffi.opaque`, plus a mint rule that accepts `@runtime` returns. Runtime leaves `@ffi.opaque` with one form and no exception.
> **Concern:** Six lib/std declarations and their minting functions must move together, or lib/std stops compiling in the middle of the change.
>
> ## G3-Q2
> **Vote:** Bare
> **Reasoning:** It is the same annotation and the same argument form as on a function. A bodiless type is already opaque by construction, so `.opaque` adds a second spelling and says nothing new.
> **Concern:** A reader may not see at once that a bodiless `@runtime` type is a pointer handle; the spec text must say so in one line.
>
> ## G3-Q3
> **Vote:** NoTag
> **Reasoning:** A `@runtime` handle is runtime ABI that ships with every program, not a foreign dependency the user chose. Tagging it adds lines to every audit that the user cannot act on.
> **Concern:** A runtime handle with a bug would not show in the FFI inventory, so the runtime's own audit must cover it.


#### Concerns and notes the writer carried into the spec

- **PLT** (Q1 concern): the mint rule for a `@runtime` handle must be written down. The spec says a value comes from the return of a `@runtime` fn, or from a read of a `Ptr` cell in an FFI region, as for an `@ffi.opaque` handle.
- **Systems** (Q1 concern): the compiler must declare every `@runtime` type's C name in the prologue in every emit mode, archive-linked builds included. This is compiler work. The spec says only that the compiler emits no `#include` and that the runtime text declares the type.
- **Systems** (Q2 concern) and **Minimalism**: a reader may not know that a bare `@runtime` on a type means a handle. The spec says in one line that a bodiless `@runtime` type is a pointer handle, and shows the form next to `@ffi.opaque` in §9.1.4.
- **PLT, DevOps, Systems, Web, Minimalism** (Q3): the audit leaves a `@runtime` handle out on purpose, and the runtime's own review covers it. The spec says so in §9.1.4.
- **DevOps** (Phase B note): the E1110 target text for `@runtime` lists both a fn and a bodiless type. The E1110 row of `ERROR_CATALOG.md` says so, and the E0849 row covers the type form. §11.1 has no `@runtime` row today, so the spec adds none: a row change needs a panel vote, and none was on this ballot.
- **Implementation, not spec:** moving the six `lib/std` handles (three in `db_sqlite.bl`, and those of `net_tcp.bl`, `net_unix.bl` and `process.bl`) to `@runtime` is compiler and library work.

## Final Spec

The rules are in `sections/07_trust_modules_metadata.md`: §9.1 *`@runtime` — The Runtime Bridge* (one new bullet), §9.1 *A `blink_` Symbol Belongs to the Runtime* (`@ffi.opaque` joins the list), §9.1.4 *`@ffi.opaque`* (`header` and `name` both required, E1134 sample) and the new §9.1.4 *A Runtime-Owned Handle*. `ERROR_CATALOG.md` widens the E0849 row and the E1110 row.

```blink
// lib/std/net_tcp.bl
@runtime("blink_tcp_handle")
pub type TcpHandle                                  // OK: lib/std, a runtime-owned C type

@runtime("blink_tcp_handle_new")
fn tcp_handle_new(fd: Int) -> TcpHandle             // the mint

// app/main.bl
@runtime("blink_tcp_handle")                        // E0849: `@runtime` is reserved for `lib/std`
type MyTcp

@ffi.opaque(name: "my_handle")                      // E1134: `header` is missing
type MyHandle

@ffi.opaque(header: "x.h", name: "blink_tcp_handle") // E0849: `@ffi.opaque` cannot name a `blink_` type
type Other
```

Locked points, one line each:

- `lib/std` declares a runtime-owned C type as a bodiless type with `@runtime("blink_x")`.
- The `@runtime` gates apply: only `lib/std`, and the symbol starts with `blink_`, else E0849.
- The compiler emits no `#include` and does no `@ffi` signature check for it.
- A bodiless `@runtime` type is a pointer handle.
- `@ffi.opaque` needs both `header` and `name` in every package. A missing `header` is E1134 at check, and the help prints the full form.
- A `blink_` name in `@ffi.opaque` is E0849 in every package, `lib/std` included.
- The spelling is bare: `@runtime("blink_tcp_handle") pub type TcpHandle`.
- A `@runtime` handle value comes from the return of a `@runtime` fn, or from a read of a `Ptr` cell in an FFI region, as the rule of §9.1.4 allows for an `@ffi.opaque` handle.
- `blink audit` does not tag a `@runtime` handle `opaque-ffi-handle`. The inventory leaves it out on purpose, and the runtime's own review covers it.
- E1110 for `@runtime` names both targets, a fn and a bodiless type.
