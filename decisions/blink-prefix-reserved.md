[< All Decisions](../DECISIONS.md)

# The `blink_` Symbol Prefix Is Reserved — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G4 ([ticket]) A user `@ffi` on a `blink_*` symbol`)

> What the hardware sees: the runtime prologue declares every `blink_*` symbol, and C has one flat
> symbol namespace. Any user declaration of a `blink_*` name, in either form, either clashes with the
> real prototype (today's ICE) or links straight into the runtime's private ABI, which changes
> without notice. A third-party library that exports a `blink_` name clashes with the runtime archive
> at link time anyway. So the prefix is reserved in every form.
>
> **G4-P1 (preferred): widen E0849 InvalidRuntimeBinding.** A `blink_*` (or `__blink_*`) symbol
> bound by anything other than `@runtime` in `lib/std` is E0849: the one-argument form, the
> two-argument form, and `@ffi let`. Error at the symbol string in the `@ffi` line, in `blink check`
> (a string prefix test, no C needed, so §6.7.1 holds). Help: "`blink_` names are the Blink runtime;
> call the std function that wraps it" and, for the two-argument form, "a C library that exports
> `blink_` names cannot be linked with a Blink program; wrap it in C under another name".
>
> ```blink
> @ffi("labs")
> @trusted(audit: "LIBC-LABS")
> fn c_abs(x: Int) -> Int ! ()                 // OK
>
> @ffi("blink_bytes_len")
> @trusted(audit: "P")
> fn plen(x: Int) -> Int ! FFI                 // error[InvalidRuntimeBinding] (E0849) at "blink_bytes_len"
>
> @ffi("thirdparty", "blink_init")
> @trusted(audit: "T")
> fn tp() -> Int ! FFI                         // error[InvalidRuntimeBinding] (E0849)
> ```
>
> Tradeoff: one code for one fact ("this is the runtime's namespace"); E0849 already owns the
> `blink_` prefix test in the other direction. Zero cost.
>
> **G4-P2: new code ReservedRuntimeSymbol.** Same behavior, separate code. Cleaner name, but two codes
> for one prefix rule.
>
> **G4-P3: E0820 MissingNativeDep.** Rejected: there is no dependency to declare; the help would
> send the user the wrong way.
>
> Cross-language: Rust reserves `__rust_*` and the C standard reserves `_[A-Z]` and `__` names; both
> are reservations by prefix.
>
> ---

- **Web/Scripting:** (excerpt, section `G4 ([ticket]): user `@ffi` on a `blink_*` symbol`)

> ### G4-P1 (PREFERRED): widen E0849 InvalidRuntimeBinding: the `blink_` prefix is reserved to `@runtime` in `lib/std`, both `@ffi` forms, at check
>
> - Any `@ffi` fn (one- or two-argument form) and any `@ffi let` whose symbol starts with
>   `blink_` is E0849, at the symbol string, in `blink check`.
> - Message: `` `blink_bytes_len` is a Blink runtime symbol; only lib/std binds those ``.
>   Help: call the std API that wraps it (name it when the compiler knows the wrapper), or bind a
>   C symbol from `c`, `m` or a declared library.
>
> ```blink
> @ffi("blink_bytes_len")                 // error[E0849]: `blink_` symbols are the runtime's
> @trusted(audit: "P")
> fn plen(x: Int) -> Int ! ()
>
> @ffi("mylib", "blink_hash")             // error[E0849]: also the two-argument form
> @trusted(audit: "Q")
> fn h(x: Int) -> Int ! ()
>
> @ffi("strlen", header: "string.h")      // OK
> @trusted(audit: "LIBC-STRLEN")
> fn strlen(p: Ptr[U8]) -> Int ! ()
> ```
>
> Tradeoffs: one rule ("`blink_` is ours"), one code a user can search for. The two-argument form
> must be included: the prologue declares every `blink_*` name, so a third-party `blink_hash` would
> clash in C anyway, and check must promise the build. A library that really exports `blink_*`
> names is rare and can be wrapped by a C shim with another name. E0849 already means "a runtime
> symbol was bound the wrong way", so a new code would split one idea in two.
>
> Cross-language: C and C++ reserve `__` and `_X` names; Python reserves dunder names. A reserved
> prefix is a familiar idea.
>
> ### G4-P2: a new code (ForeignRuntimeSymbol)
>
> Same behavior, own code. More precise search hit, but one more code to learn. Acceptable, not
> preferred. E0820 MissingNativeDep is the wrong message: there is no dependency to add.
>
> ---

- **PLT:** (excerpt, section `G4. A user @ffi on a blink_* symbol`)

> Soundness: a `blink_*` symbol has the runtime's ABI, where `Str`, `List[T]` and closures have a
> layout that the compiler owns. `@ffi` claims a C ABI under *Signature Types*. A user `@ffi` on a
> runtime symbol claims a C type for a non-C function: an unchecked cast through the trusted base.
> The `blink_` prefix is the runtime's reserved C namespace.
>
> ### G4-P1 (preferred): widen E0849 to every binding of a blink_* symbol outside @runtime in lib/std
>
> - E0849 InvalidRuntimeBinding fires for: `@runtime` outside lib/std; `@runtime` on a non-`blink_`
>   symbol (as today); and an `@ffi`, in either form, whose symbol starts with `blink_`, in any
>   package (lib/std included: it uses `@runtime`).
> - Site: the symbol string of the annotation. Command: check (so build and test too).
> - Help: "the `blink_` prefix is reserved for the Blink runtime. To call a C function of that
>   name in another library, wrap it in C under another name."
>
> ```blink
> @ffi("blink_bytes_len")                  // error[E0849]: `blink_` symbols are the runtime's
> @trusted(audit: "P")
> fn plen(n: Int) -> Int ! FFI
>
> @ffi("mylib", "blink_compat_init")       // error[E0849]: the two-argument form too
> @trusted(audit: "Q")
> fn compat_init() -> Int ! FFI
>
> @ffi("labs", header: "stdlib.h")         // OK
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! ()
> ```
>
> Two-argument form: yes, it fires. A third-party `blink_x` would share one link namespace with the
> runtime: a clash or an interposition, either way a symbol whose meaning depends on link order.
> A prefix rule is decidable in check with no runtime symbol table, and stays stable when the
> runtime adds symbols.
>
> Tradeoffs: one code for "the runtime bridge is closed", and the name already says it. The cost:
> a C library that exports `blink_` names needs a C shim. That is rare and the shim is two lines.
>
> ### G4-P2: a new code (ReservedRuntimeSymbol)
>
> Same behavior, own code. Acceptable; E0849 is a closer fit than a new code, and the catalog grows
> less. E0820 MissingNativeDep is wrong: it names a missing manifest entry, and no entry fixes this.
>
> Cross-language: Rust reserves no symbol prefix, but `#[no_mangle]` duplicate symbols are a link
> error; C reserves `_[A-Z]` and `__` for the implementation (P1 is the same idea, enforced).
>
> ---

- **DevOps:** (excerpt, section `G4 ([ticket]) user `@ffi` on a `blink_*` symbol`)

> **G4-P1 (preferred): widen E0849 InvalidRuntimeBinding: a `blink_*` symbol bound by anything
> other than `@runtime` in lib/std. Both `@ffi` forms. In `blink check`, at the symbol string.**
>
> ```blink
> @ffi("blink_bytes_len")                 // error[E0849] at "blink_bytes_len"
> @trusted(audit: "P")
> fn plen(p: P) -> Int ! FFI {}
>
> @ffi("mylib", "blink_hash")             // error[E0849] too
> @trusted(audit: "H")
> fn h(x: Int) -> Int ! ()
>
> @ffi("strlen")                          // OK
> @trusted(audit: "LIBC-STRLEN")
> fn c_strlen(s: Ptr[U8]) -> Int ! ()
> ```
> ```
> error[E0849]: `blink_bytes_len` is a Blink runtime symbol; `@ffi` cannot bind it
>   = note: the `blink_` prefix is reserved for the runtime; lib/std binds it with `@runtime`
>   = help: call the std API for this operation (`Bytes.len`)
> ```
> The help names the std fn when the runtime symbol has one `@runtime` binding in lib/std (a
> table lookup the compiler already has); otherwise it omits the line.
>
> Two-argument form: yes. Every unit's prologue declares all `blink_*` symbols, and the runtime
> archive defines them, so a third-party `blink_hash` collides at C compile or at link anyway.
> Reserve the prefix outright; the error then reads the same in both forms, and the user gets it
> in the editor, not as a link error. E0849 is the right home: it is already "the `blink_`
> namespace and `@runtime` are one pair"; this adds the other direction of the same pair.
>
> **G4-P2: new code `ReservedRuntimeSymbol`.** Clearer name in a search, but two codes for one
> rule split the docs and the `--explain` page. Weak second.
>
> E0820 (P-b): wrong. The user reads "declare a native dependency", does so, and still fails.
>
> ---

- **AI/ML:** (excerpt, section `G4: user @ffi on a blink_* symbol`)

> ### G4-P1 (PREFERRED): widen E0849, both forms, at check
>
> E0849 InvalidRuntimeBinding covers any binding of a `blink_*` symbol other than `@runtime` in
> `lib/std`: `@ffi("blink_x")` and `@ffi("lib", "blink_x")`, in any package (lib/std included,
> since lib/std must use `@runtime`). Fires in `blink check`, at the symbol string.
>
> ```blink
> @ffi("blink_bytes_len")                         // error[E0849]: `blink_` symbols belong to the Blink runtime
> @trusted(audit: "P")
> fn plen(n: Int) -> Int ! FFI {}
>
> @ffi("labs")                                    // OK
> @trusted(audit: "LIBC-LABS")
> fn c_labs(x: Int) -> Int ! ()
> ```
>
> Help: "call the std API that wraps it"; for the two-argument form, "the prologue declares every
> `blink_*` symbol, so a library symbol with this prefix cannot be bound; bind it from a C shim
> with another name".
>
> Tradeoffs (AI): one fact: "the `blink_` prefix is the runtime's, and only `@runtime` in lib/std
> binds it". One code for that fact, not two. The two-argument form must be in too: the prologue
> declares each runtime symbol, so a third-party `blink_x` collides at the C level anyway (the
> MVCE's ICE). Check must fire it or the promise breaks. The cost to real users is near zero; the
> benefit is that a model that has seen `blink_*` names in lib/std (training data!) and copies
> them gets a clear error, not an ICE.
>
> ### G4-P2: a new code (`ReservedRuntimeSymbol`)
>
> Same behavior, own name. Slightly clearer message, but two codes for one rule. Fine as a
> fallback.
>
> ---

- **Minimalism:** (excerpt, section `G4 ([ticket]) User @ffi on a blink_* symbol`)

> ### G4-P1 (PREFERRED): the `blink_` prefix belongs to `@runtime`; widen E0849
>
> E0849 InvalidRuntimeBinding: a `blink_*` symbol named by any form other than `@runtime` in
> lib/std. That is `@ffi("blink_x")`, `@ffi("lib", "blink_x")` and `@ffi let`, in any package.
> At the annotation argument, in check (a string-prefix test; no C headers needed).
>
> ```blink
> @ffi("blink_bytes_len")         // error[InvalidRuntimeBinding] (E0849): `blink_` symbols are the runtime's
> @trusted(audit: "P")
> fn plen(b: Bytes) -> Int ! FFI {}
>
> @ffi("m", "cos")                // OK
> @trusted(audit: "LIBM-COS")
> fn cos(x: Float) -> Float ! () {}
> ```
>
> Answers: (1) E0849, widened; no new code. (2) Yes, the two-argument form too. The generated C
> declares every `blink_*` runtime symbol, so a third-party `blink_x` collides at the C level and
> the link level anyway. One reserved prefix is simpler than a case split. A library that exports
> `blink_x` is out of luck; a C shim with another name fixes it. (3) Yes, check.
>
> Facts the writer must know: lib/std has 0 `@runtime` uses today and many `@ffi("blink_...")`
> (db_sqlite 26, process 14, fs_ops 8, ...). So this is a 3-step bootstrap: build `@runtime`,
> migrate lib/std, then turn on the error. And 07_trust_modules_metadata.md :260-310 and :585-598
> show `@ffi("blink_...")` examples: stale examples, a chore to rewrite.
>
> ### G4-P2 (rejected): new code / E0820
>
> E0820 says "declare the dependency", which is a wrong fix. A new code splits one rule in two.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> ## G4: keep both variations.
>
> - `@ffi let` with a `blink_` symbol: yes. Same flat C namespace; the prologue declares it too.
> - `__blink_` prefix: yes. bootstrap/runtime_*.h declare 148 distinct `__blink_*` names
>   (`__blink_cleanup_push`, `__blink_panic_dispatch`, ...). They are more private than `blink_*`,
>   and a user binding to `__blink_panic_dispatch` breaks the "never returns" invariant the
>   runtime depends on. One prefix test, zero cost.

- **Web/Scripting:** (excerpt)

> ## G4: no change. Include `@ffi let` and the `__blink_` prefix. The impl must migrate lib/std's ~60 `@ffi("blink_...")` uses to `@runtime` first, which is not a panel matter.

- **PLT:** (excerpt)

> ## G4: E0849, both @ffi forms, in check; also `@ffi let`; also `__blink_`
>
> - `@ffi let` with a `blink_` symbol: yes. It is the same namespace and the same ABI hazard, and
>   a rule with an exception for `let` would be arbitrary.
> - `__blink_`: yes. The runtime's internal symbols (such as `__blink_panic_dispatch`) are the same
>   trusted base. C already reserves `__` for the implementation, so this costs a user nothing.
> - The migration of lib/std's ~60 `@ffi("blink_...")` uses comes before the error lands. That is an
>   impl ordering matter, not a vote matter.

- **DevOps:** (excerpt)

> ## G4: no change. Yes to both variations: `@ffi let` with a `blink_` symbol, and the `__blink_` prefix
> (the same reason: the prologue and runtime own the C namespace, so a collision is certain).

- **AI/ML:** (excerpt)

> ## G4: no change. Support both variations
>
> - `@ffi let` with a `blink_` symbol: yes. The rule is "the prefix belongs to the runtime"; the
>   form of the binding must not matter, or a model learns two rules.
> - `__blink_` prefix: yes, same reason; it is runtime-internal and the cost is one prefix test.
> - lib/std migration (about 60 `@ffi("blink_...")` uses) is impl work, as min says.

- **Minimalism:** (excerpt)

> ## G4: widen E0849 for both forms. YES to `@ffi let`: one prefix rule for every `@ffi` form.
> YES to `__blink_`: one test for "a prefix the runtime owns"; `@runtime` cannot bind it either,
> so no user form may. Migration of lib/std is an impl matter.

#### Phase C — Final vote

- **G4-Q1: widen E0849 for any `@ffi` form** (6-0, option A; the other option was to reject)
- **G4-Q2: also `@ffi let`** (6-0, yes)
- **G4-Q3: also the `__blink_` prefix** (6-0, yes)

- **Systems:**

> ## G4-Q1: A
> Reasoning: the runtime prologue declares every `blink_*` symbol and C has one flat namespace, so any user binding either clashes with the real prototype or reaches a private ABI. A prefix test at check keeps §6.7.1.
> Concern: lib/std's ~60 `@ffi("blink_...")` uses must move to `@runtime` before the error lands, or std stops building.

> ## G4-Q2: YES
> Reasoning: same namespace, same hazard; the form of the binding must not matter.
> Concern: none.

> ## G4-Q3: YES
> Reasoning: 148 `__blink_*` names in bootstrap/runtime_*.h are the most private part of the runtime; a user binding to `__blink_panic_dispatch` breaks its never-returns invariant.
> Concern: none.

- **Web/Scripting:**

> ## G4-Q1: A
> Reasoning: "the `blink_` prefix belongs to the runtime" is one rule, and E0849 already means a runtime symbol was bound the wrong way.
> Concern: lib/std must migrate its ~60 `@ffi("blink_...")` uses first, or the error lands on our own stdlib.

> ## G4-Q2: YES
> Reasoning: same namespace, same hazard. A `let` exception would be one more rule to learn.
> Concern: none.

> ## G4-Q3: YES
> Reasoning: it costs a user nothing, since C already reserves `__`, and it protects invariants like the never-returning panic dispatch.
> Concern: none.

- **PLT:**

> ## G4-Q1: A
> Reasoning: a `blink_*` symbol has the runtime's ABI, not a C ABI. `@ffi` on it is an unchecked cast through the trusted base. The prefix rule can be decided in check, and it stays stable when the runtime adds symbols.
> Concern: lib/std's ~60 `@ffi("blink_...")` uses must move to `@runtime` before the error lands, or the stdlib stops building.

> ## G4-Q2: YES
> Reasoning: it is the same namespace and the same hazard. An exception for `let` would be arbitrary.
> Concern: none.

> ## G4-Q3: YES
> Reasoning: the runtime's internal symbols, such as `__blink_panic_dispatch`, are part of the same trusted base. C already reserves `__` for the implementation, so this costs a user nothing.
> Concern: none.

- **DevOps:**

> ## G4-Q1: A
> Reasoning: the prologue and runtime own the `blink_` C namespace, so a user binding either collides or gives an ICE. One code (E0849) for "this namespace and `@runtime` go together" in both directions keeps one `--explain` page. It fires in check, so the LSP shows it.
> Concern: lib/std's ~60 `@ffi("blink_...")` uses must move to `@runtime` before the error lands, or `task ci` breaks on the stdlib itself.

> ## G4-Q2: YES
> Reasoning: the binding form must not change the prefix rule; one rule is easier to state and to test.
> Concern: none.

> ## G4-Q3: YES
> Reasoning: `__blink_` names are more private than `blink_` ones (`__blink_panic_dispatch` must never return), and C already reserves `__` for the implementation. One more prefix test, no user cost.
> Concern: none.

- **AI/ML:**

> ## G4-Q1: A
> Reasoning: one fact, one code: the `blink_` prefix belongs to the runtime and only `@runtime` in lib/std binds it. Models that copy `blink_*` names from lib/std training data get a clear check error, not an ICE.
> Concern: the lib/std migration of about 60 `@ffi("blink_...")` uses must land first, or the stdlib itself fails the gate.

> ## G4-Q2: YES
> Reasoning: the rule is the prefix, not the binding form; an exception for `@ffi let` is one more thing to learn.
> Concern: none.

> ## G4-Q3: YES
> Reasoning: same namespace, more private than `blink_` (`__blink_panic_dispatch` must never return); one extra prefix test.
> Concern: none.

- **Minimalism:**

> ## G4-Q1: A
> Reasoning: the `blink_` prefix belongs to `@runtime`; one prefix test, an existing code, both forms.
> Concern: lib/std has about 60 `@ffi("blink_...")` uses and no `@runtime`; turning the error on before the migration breaks the stdlib build.

> ## G4-Q2: YES
> Reasoning: one rule for every `@ffi` form; an exception for `let` would be arbitrary.
> Concern: none beyond G4-Q1.

> ## G4-Q3: YES
> Reasoning: same rule, one more prefix; `__blink_` names are the most private part of the runtime (sys: `__blink_panic_dispatch` must never return).
> Concern: the message must say "a prefix the runtime owns", not only `blink_`, so the `__blink_` case reads right.

### Final Spec

```blink
@ffi("blink_bytes_len")                      // error[E0849]: one-argument form
@trusted(audit: "P")
fn plen(b: Bytes) -> Int ! ()

@ffi("sodium", "blink_randombytes_fill")     // error[E0849]: two-argument form
@trusted(audit: "SODIUM-1")
fn randombytes(mut buf: Bytes) ! Rand {}

@ffi("blink_flags", header: "flags.h")       // error[E0849]: `@ffi let`
pub let FLAGS: Int

@ffi("__blink_panic_dispatch")               // error[E0849]: `__blink_` prefix
@trusted(audit: "P")
fn dispatch(msg: Str) ! ()
```

- Q1 (6-0): E0849 `InvalidRuntimeBinding` widens. A symbol that starts with `blink_` and is bound by anything other than `@runtime` in `lib/std` is E0849 at the symbol string, in `blink check`. The one- and the two-argument form of `@ffi` are both covered.
- Q2 (6-0): `@ffi let` with a `blink_` symbol is E0849.
- Q3 (6-0): the `__blink_` prefix is E0849 for every form.
- The help says to call the standard library function that wraps the symbol. For a C library that exports such a name, the help says to wrap it in C under another name.
- The spec examples that showed a user `@ffi("blink_...")` now bind a `shim_` symbol from a declared library.
- The implementation must move the `@ffi("blink_...")` uses in `lib/std` to `@runtime` before the error lands.
- Spec text: §9.1 *A `blink_` Symbol Belongs to the Runtime*, *`@ffi let` — Foreign Constants*, E0849 in ERROR_CATALOG.md.
