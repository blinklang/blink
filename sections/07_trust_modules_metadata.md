## 9. Trust Boundaries & FFI

Blink's type system, effect system, and contract system form a closed verification envelope. Everything inside that envelope is compiler-checked. FFI crosses the boundary of that envelope — foreign code is unverified, untyped (from Blink's perspective), and potentially unsafe. The language treats this boundary explicitly.

### 9.1 FFI Rules and Annotations

Every foreign function binding carries `@ffi`, an explicit effect row and `@trusted`. Only `@trusted` may be omitted, and omitting it gives a warning (W0800).

#### `@ffi` — Declaring the Foreign Binding

```blink
@ffi("libsodium", "crypto_secretbox_easy")
@trusted(audit: "SEC-042")
fn sodium_secretbox(
    ciphertext: Ptr[U8],
    message: Ptr[U8],
    msg_len: U64,
    nonce: Ptr[U8],
    key: Ptr[U8]
) -> Int ! Crypto
```

The `@ffi("library", "symbol")` annotation names the shared library and the symbol to link. The compiler does not type-check the foreign function's body — it does not have one. The signature is the developer's claim about what the foreign function expects and returns.

The library argument is a key of `[native-dependencies]` in `blink.toml`, or one of the two runtime libraries: `"c"` (the C library) and `"m"` (the math library). The runtime libraries need no manifest entry (§9.1.2, *Runtime libraries*).

**One-argument form.** `@ffi("symbol")` binds a symbol from the runtime libraries `c` and `m`. It needs no `[native-dependencies]` entry and adds no link flag. An optional `header:` argument names the C header that declares the symbol, and it has the same meaning in both forms:

```blink
@ffi("cos", header: "math.h")
@trusted(audit: "LIBM-COS")
fn c_cos(x: Float) -> Float ! ()
```

Outside `lib/std`, prefer the two-argument form. It names the library that supplies the symbol, so a reader and `blink audit` can see where the symbol comes from. The one-argument form does not make a third-party symbol legal: a symbol that is not in `c` or `m` must use the two-argument form with a declared library.

#### The Effect Row — Declared by the Author

Because the compiler cannot analyze foreign code, the author **must** write the effect row of an `@ffi` function. It uses the same `!` syntax as every other function (§4.2). The compiler assumes this row — it cannot verify it. This is the one place in Blink where an effect row is not compiler-proven (§4.5, *Proven and assumed rows*).

```blink
@ffi("libcurl", "curl_easy_perform")
@trusted(audit: "NET-007")
fn curl_perform(handle: Ptr[Void]) -> Int ! Net, IO
```

**There is no `FFI` effect.** A foreign call is not an effect of its own. The row of an `@ffi` decl names the Blink effects the foreign code has: `Net`, `IO`, `Crypto` and so on (§4.3). Callers see that row by the usual transitivity rule (§4.5), exactly as they see the row of a Blink function. `! FFI` is not a valid row: `FFI` is not a declared effect, so it is rejected with `UnknownEffect` (E0538, §4.3).

The declared row is an **accounting** claim, not routing. It says which capabilities a caller must hold to reach the foreign code. How it relates to handlers is stated once, in §4.5 *Proven and assumed rows*. When a foreign effect must be replaceable — mocked in a test, sandboxed, swapped — the safe wrapper performs it through a Blink effect operation, and a handler then replaces that operation (§4.7):

```blink
effect Clock {
    fn cpu_ticks() -> Int
}

@ffi("c", "clock")
@trusted(audit: "TIME-001")
fn raw_clock() -> Int ! Time.Read

// The real implementation calls C; a test installs its own `handler Clock`.
pub fn real_clock() -> Handler[Clock] {
    handler Clock {
        fn cpu_ticks() -> Int {
            raw_clock()
        }
    }
}
```

Omitting the row on an `@ffi` function is a compile error (`FfiNoEffects`, E0802). The compiler refuses to guess. This holds for a pure binding too: a foreign function with no effects (`strlen`, `memcmp`) states that claim with the explicit empty row `! ()`, so a missing row and a claimed-pure row never look the same:

```blink
@ffi("c", "strlen")
@trusted(audit: "LIBC-STRLEN")
fn c_strlen(s: Ptr[U8]) -> Int ! ()
```

`! ()` means "no effects". It is not a return type. It is legal only on an `@ffi` decl; everywhere else an omitted row already means pure, and `! ()` is an error (§4.2, `EmptyRowOutsideFfi`). The E0802 help names both choices, and neither is machine-applicable, because the row is a claim about foreign code:

```
error[FfiNoEffects]: foreign function `c_strlen` has no effect row
 --> str.bl:3:1
  |
3 | fn c_strlen(s: Ptr[U8]) -> Int
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  = help: write the effects the foreign code has after the return type
          (`-> Int ! IO`), or `! ()` (the empty effect row) if it has none
```

There is no `@effects` annotation. The row goes after `!` in the signature, on foreign and Blink functions alike. Code written for an earlier draft of this section that puts `@effects(...)` on any function gets one error (`EffectsAnnotationRemoved`) and not E0802 as well:

```
error[EffectsAnnotationRemoved]: `@effects` is not an annotation
 --> sys.bl:2:1
  |
2 | @effects(IO)
  | ^^^^^^^^^^^^ effects go in the signature, after `!`
  |
  = help: remove `@effects(IO)` and write the row after the return type:
          `-> Int ! IO`; on an `@ffi` decl with no effects, write `! ()`
```

No fix is machine-applicable: moving the row into the signature would make a tool write the claim for the author.

#### `@trusted` — Audit Trail

`@trusted(audit: K)` records a claim, by an author who may be human or agent, that the binding matches the foreign code: its types, its effect row and its memory use. The compiler assumes the claim; it does not prove it. `K` must name a record of that claim. The language promises that the record exists, not who wrote it.

`audit: K` is the only argument. Authorship, dates and ticket links go in the record's `claim` text or in version control, not in the annotation. The record lives in the package's `audits.toml` (*Audit Records* below).

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO
```

FFI without `@trusted` compiles but emits a warning:

```
warning[W0800]: unaudited foreign function
 --> db/sqlite.bl:4:1
  |
4 | fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  = note: FFI function `sqlite3_open` has no @trusted annotation
  = help: if `std.libc` already binds this symbol, call that binding instead
  = help: after you check the binding against the C header, record the review:
          add @trusted(audit: "AUDIT-ID") and a record `AUDIT-ID` in audits.toml
```

Neither help line is machine-applicable. No tool writes a claim for the author (§9.1, *Audit Records*).

#### Audit-Gated Diagnostics — One Channel, Stated Once

A handful of diagnostics exist to force a **record**, not to report a mistake. The program they fire on is legal and may well be correct; what the language asks is that its author, human or agent, looked at it and wrote a claim in a place a reviewer can find. `@trusted(audit: K)` is that place, and this subsection states the mechanism once for every diagnostic that uses it. No other section restates it.

**`audit:` is mandatory and non-empty.** `@trusted` without an `audit:` argument, or with an empty one, is rejected. A bare `@trusted` would silence the diagnostic and record nothing, which is the one outcome the annotation exists to prevent.

```blink
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")           // OK
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

// intentional-error example
@ffi("sqlite3", "sqlite3_close")
@trusted                            // error[TrustedRequiresAudit]: `@trusted` requires a non-empty
                                    //   `audit:` identifier
                                    // help: `@trusted(audit: "DB-004")`
fn sqlite3_close(db: Ptr[Void]) -> Int ! IO
```

**`@trusted(audit: K)` is the sole channel.** For the diagnostics listed below, it is the only construct that suppresses them. In particular they are **not** reachable from `@allow(Name)` (§4.16.8) and **not** reachable from `[lints]` in `blink.toml`.

**Naming one of them in another channel is refused, not ignored.** Writing `@allow(RawBypassesParam)`, or `RawBypassesParam = "off"` under `[lints]`, is an error whose message names `@trusted(audit: …)`. A suppression that silently fails to apply and one that silently succeeds are equally bad — in both cases the author cannot tell which happened.

**The list.**

| Diagnostic | What the record is for |
|------------|------------------------|
| `UnauditedFfi` (W0800) | The author claims this foreign binding matches the C header: types, effect row, memory use |
| `RawBypassesParam` (W0310) | The author claims this un-parameterized interpolation cannot carry an injection |

**Membership criterion.** A diagnostic belongs on this list **only when silently suppressing it would destroy a record the language promises exists**. That is the whole gate. A diagnostic an author merely finds noisy does not qualify, however strongly; the list is not a place to park warnings someone wants to be unignorable.

**Unsilenceable means no channel that records nothing** — not no channel at all. `@trusted(audit: K)` stays available for the legitimate case, so the list is a turnstile rather than a wall. A rule with no way through relocates the pressure into source: an indirection or a helper that launders the value past the trigger, leaving no record whatsoever, which is worse than the suppression it refused.

**Every position that can raise one of these can annotate.** `test` blocks are annotatable, so a diagnostic raised inside one has somewhere to attach. An audit-gated diagnostic must never fire in a position from which its own repair cannot be written (§3.1).

**This removes a capability that works today.** `@allow` currently reaches these warnings. Narrowing it is a breaking change, not a clarification, and release notes should say so in those words.

#### Audit Records — `audits.toml`

`K` in `@trusted(audit: K)` is not free text. It names a record in the package's **`audits.toml`**, a TOML file at the package root, next to `blink.toml`. Every package has its own: the standard library has one, and each dependency ships its own. A package resolves `K` only against its own file.

A record is a TOML table keyed by `K`. It holds exactly two keys:

- `claim` — required, non-empty text. What the author claims and why it holds. Ticket links and authorship go here when a team wants them.
- `pins` — a table from the path of each function that carries `@trusted(audit: K)` to that function's pin.

```toml
# audits.toml
[DB-003]
claim = "Checked against sqlite3.h 3.45: two pointer params, int return, file IO only. The wrapper passes a NUL-terminated path from Str.as_cstr() and a fresh out-cell."
pins = { "db.sqlite.sqlite3_open" = "ast1:3f9c0a4e1b7d" }

[RPT-002]
claim = "table is checked against REPORT_TABLES in the same function before Raw()."
pins = { "report.fetch_table" = "ast1:c08e51aa2d90" }
```

**A pin covers one whole function.** The pin is a hash of the function's syntax tree: its signature, its effect row and its body. It ignores formatting and comments, so `blink fmt` and a comment edit never make a pin stale. An `@ffi` decl has no body, so its pin covers only its signature and row. Pins are opaque: `blink audit pin` writes them, and nobody edits them by hand.

The pin covers the function's own body and nothing else. A guard in a **caller** is outside every pin: deleting it changes no pin, and the claim can become false with no warning. Keep the guard inside the audited function, and keep that function small:

```blink
pub fn fetch_table(table: Str) -> Result[List[Row], DBError] ! DB.Read {
    if !REPORT_TABLES.contains(table) {
        return Err(DBError.PermissionDenied("unknown table {table}"))
    }
    db.query("SELECT * FROM {Raw(table)}")
}
```

Give `fetch_table` the annotation `@trusted(audit: "RPT-002")` and the record above. When someone later deletes the `contains` check, the pin no longer matches and `RawBypassesParam` fires again. If the guard were in the caller, the same deletion would leave the pin unchanged.

**How a suppression applies.** `@trusted(audit: K)` on a function `f` suppresses an audit-gated diagnostic in `f` only when all three hold:

1. `audits.toml` has a record `K` with a non-empty `claim`;
2. that record has a pin for `f`;
3. the pin equals the current hash of `f`.

The compiler checks this in `blink check`, `blink build` and the LSP. The rule applies to every `@trusted(audit: K)`, whatever diagnostic it is for, including `ScopedValueWithoutWith` (§5).

**A missing record is an error.** When `audits.toml` has no record `K`, or record `K` has an empty `claim`, the annotation is rejected:

```
error[AuditRecordNotFound]: no audit record `DB-003`
 --> db/sqlite.bl:3:1
  |
3 | @trusted(audit: "DB-003")
  |                 ^^^^^^^^ no record `DB-003` in audits.toml
  |
  = help: add a `[DB-003]` table with a non-empty `claim` to audits.toml,
          then run `blink audit pin DB-003`
```

**A stale or missing pin is not an error.** When record `K` exists but has no pin for `f`, or its pin for `f` does not match, the suppression lapses: the original diagnostic fires again, with a note that names `K` and the reason. No new diagnostic code is involved.

```
warning[RawBypassesParam]: Raw() bypasses parameterization
 --> report.bl:5:30
  |
5 |     db.query("SELECT * FROM {Raw(table)}")
  |                              ^^^^^^^^^^ concatenated into the query text, not parameterized
  |
  = note: `report.fetch_table` changed since audit record `RPT-002` was pinned
  = help: re-read the claim in `RPT-002`; if it still holds, run `blink audit pin RPT-002 report.fetch_table`
```

`blink audit --require-all` treats a lapsed suppression as unaudited, so CI fails on it.

**The schema is closed.** A key other than `claim` and `pins` in a record is an error, `AuditRecordUnknownKey`. It names the allowed keys and suggests the nearest one:

```
error[AuditRecordUnknownKey]: unknown key `claims` in audit record `DB-003`
 --> audits.toml:2:1
  |
2 | claims = "checked against sqlite3.h"
  | ^^^^^^ a record holds only `claim` and `pins`
  |
  = help: did you mean `claim`?
  = note: put ticket links and authorship in the `claim` text; version control records who wrote it
```

**Who writes what.** The author writes `claim` by hand. `blink audit pin K [fn]` writes pins only:

- It refuses when `audits.toml` has no record `K`, or when its `claim` is empty.
- With `fn`, it pins that function. Without it, it pins every function that carries `@trusted(audit: K)`.
- It prints the existing claim before it writes, so the author re-reads what the pin vouches for.

No command re-pins more than one record at a time, and no autofix writes a claim. A command may list stale pins, but it never re-pins them in bulk. A re-pin is therefore always visible in review: the diff shows the function change and, beside it, a pin change under an unchanged claim.

#### Mandatory Safe Wrappers

FFI functions are **not callable from application code directly**. They must be wrapped in a safe Blink function that validates inputs, translates error codes, and presents a Blink-native API.

```blink
// The raw FFI binding — private, unsafe, audited
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn raw_sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

// The safe wrapper — this is what application code calls
pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    let db_ptr = alloc_ptr[Void]()
    let rc = raw_sqlite3_open(path.as_cstr(), db_ptr.addr())
    match rc {
        0 => Ok(Database.from_ptr(db_ptr))
        _ => Err(DbError.from_code(rc))
    }
}
```

The compiler enforces this: any call to an `@ffi` function from outside the declaring module is a compile error. FFI functions are implicitly private — `pub` on an `@ffi` function is rejected.

```
error[E0801]: FFI function cannot be public
 --> db/sqlite.bl:3:1
  |
3 | pub fn sqlite3_open(...) -> Int
  | ^^^ FFI functions must be wrapped in safe Blink functions
  |
  = help: make the FFI function private and create a pub wrapper
```

#### Contract Ineligibility

FFI functions cannot carry `@requires` or `@ensures` annotations. The compiler cannot verify contracts against foreign code. The safe wrapper is where contracts belong:

```blink
@ffi("zlib", "compress")
@trusted(audit: "COMP-001")
fn raw_compress(dest: Ptr[U8], dest_len: Ptr[U64], src: Ptr[U8], src_len: U64) -> Int ! IO

@requires(data.len() > 0)
@ensures(result.is_ok() => result.unwrap().len() <= data.len())
pub fn compress(data: List[U8]) -> Result[List[U8], CompressError] ! IO {
    // safe wrapper with contracts
}
```

#### `blink audit` — FFI Inventory

The `blink audit` command lists every FFI call site in the project with its declared effects and audit status:

```
$ blink audit

FFI Summary: 7 bindings across 3 modules

  db/sqlite.bl:
    sqlite3_open      effects: IO        audit: DB-003   OK
    sqlite3_exec      effects: IO, DB    audit: DB-004   OK
    sqlite3_close     effects: IO        audit: DB-005   OK

  crypto/sodium.bl:
    crypto_secretbox  effects: Crypto    audit: SEC-042  OK
    crypto_sign       effects: Crypto    audit: SEC-043  OK

  net/curl.bl:
    curl_easy_init    effects: Net       audit: NONE     WARNING
    curl_easy_perform effects: Net, IO   audit: NET-007  OK

Audit coverage: 6/7 (85.7%)
Unaudited: net/curl.bl:curl_easy_init

Raw Query Summary: 2 raw queries across 1 module

  db/legacy.bl:
    Raw()           line 42    UNAUDITED
  db/migration.bl:
    Raw()           line 8     audit: MIG-001  OK

Raw query audit coverage: 1/2 (50%)
```

This output is structured JSON when `--json` is passed. CI pipelines can enforce `blink audit --require-all` to block merges with unaudited FFI. Under `--require-all`, a `@trusted` function whose pin is stale or missing counts as unaudited (*Audit Records* above).

`blink audit pin K [fn]` writes the pins of record `K` in `audits.toml`. See *Audit Records* above for what it refuses and why there is no bulk re-pin.

### 9.1.1 FFI Type Specification

This section formally defines the pointer types, operations, and lifetime semantics used by FFI bindings. These types exist **exclusively for C interop** — they are not general-purpose Blink types and are not available in the module prelude.

#### FFI import resolution and the real gates

The `ffi` namespace and the FFI pointer types are **compiler-known intrinsics**, not a distributable module. This has two consequences future readers must not re-derive a phantom gate from:

**Resolution.** `import blink.ffi` and `import blink.core` resolve as **recognized, inert, optional no-ops** — accepted, never required, and never `ModuleNotFound`. The `ffi` namespace works with **no import at all**, exactly like `io`/`net`/`time`. Selective forms such as `import blink.ffi.{Ptr, Void, alloc_ptr, null_ptr}` are satisfiable no-ops: the names they list are compiler-known regardless, so the import is a documentation marker (signalling "this file does FFI") and never a capability gate. An aliased form, `import blink.ffi.{Ptr as RawPtr}`, binds the alias to the compiler-known name; a module that declares its own `Ptr` uses it to reach the builtin (§10.6 *Shadowing Rules*). This follows the `blink.*` reservation in §10.7 (Standard Library Resolution).

**The two real gates.** The unsafe FFI surface is gated twice, and these are the *only* gates:

1. **`PtrOutsideFFI` (E0811)** — a `Ptr[T]` may appear only inside an **FFI region**: the body of an `@ffi`/`@trusted` function, or a `with ffi.scope() as _ { }` block (the canonical region list lives with *Pointer Operations*, E0811, below). This is a per-function capability gate on *where* pointer types are allowed, checked structurally regardless of imports.
2. **`#275` native-dependency manifest** — an `@ffi` declaration that names a library with no matching `[native-dependencies]` entry in `blink.toml` is a compile error. The runtime libraries `c` and `m` need no entry (§9.1.2).

There is **no import gate** on FFI. A per-file `import blink.ffi` requirement would be strictly weaker than `rg '@ffi'` and would make `import` a capability boundary it is nowhere else in the language. See [FFI import namespace resolution](../decisions/ffi-import-namespace-resolution.md).

#### The `Ptr[T]` Type

`Ptr[T]` is a compiler-known generic type representing a typed C pointer. It maps directly to `T*` in the generated C code.

```blink
import blink.ffi.{Ptr, Void, alloc_ptr, null_ptr}
```

This import is **optional** — a documentation marker, not a requirement. `Ptr[T]`, `Void`, and the pointer operations are compiler-known and available without it; the `ffi` namespace is a no-import intrinsic like `io`/`net`/`time`. See *FFI import resolution and the real gates* below.

**Nullability:** `Ptr[T]` is **non-null by convention, not by proof**. Nothing in the type system prevents a null value at type `Ptr[T]`: `null_ptr[T]()` constructs one, `scope.alloc` can fail, and any C function may return `NULL`. Inside the `@ffi`/`@trusted` region where a `Ptr[T]` may appear (E0811), non-nullness is an **audited premise** the author asserts — not a guarantee the compiler discharges. `.is_null()` re-validates that premise at runtime, and `.deref()`/`.write(v)` trust it (see *Pointer Operations*).

```blink
// A raw C pointer — may be null; the @trusted audit owns the invariant
fn raw_sqlite3_exec(db: Ptr[Void], sql: Ptr[U8]) -> Int

// A C function that can return NULL — test the result with .is_null()
@ffi("c", "getenv")
@trusted(audit: "ENV-001")
fn raw_getenv(name: Ptr[U8]) -> Ptr[U8] ! Env
```

`Ptr[T]?` (sugar for `Option[Ptr[T]]`) is **reserved** for a future *enforced* nullability model in which the compiler inserts a null-check at FFI return boundaries and forbids `.deref()` until the `Option` is eliminated. That model — and the boundary check — are **not yet implemented**; until they are, a possibly-null C return is spelled `Ptr[T]` and validated with `.is_null()`. When `Ptr[T]?` lands it must be revisited together with `.to_str()`, whose `Option[Str]` result is earned only because `Ptr[U8]` admits null today.

**Nesting:** `Ptr[Ptr[T]]` is allowed and maps to `T**`. This is required for C out-parameters (e.g., `sqlite3_open`'s `sqlite3**` parameter): allocate the cell with `scope.alloc[Ptr[T]]()`, pass it directly to C, then read it back with `.deref()` (which yields `Ptr[T]`).

**The `Void` type:** `Void` is the FFI-only marker for C's incomplete `void` pointee type. It is **well-formed only as the argument of `Ptr[_]`** — `Ptr[Void]` is `void*`. `Void` has no value representation (see *`.deref()` / `.write()` on `Ptr[Void]`* below): it is not a value type, and it may not appear as a standalone type, a function parameter or return type, a field type, or a generic argument anywhere except directly under `Ptr`. Every such non-`Ptr` use is a compile error (**E0828**) whose fix points at the unit type — the type that carries "no meaningful value" for a Blink value, parameter, or return is `()` (the unit type, §3.8), never `Void`.

`()` and `Void` are two different kinds of thing, and the confinement of `Void` to `Ptr[Void]` is its definition, not a restriction bolted onto a general type. `()` is an *inhabited* value type: one value, a representation, usable as a return, a field, or a generic argument (`Result[(), E]`, `Map[Str, ()]`). `Void` mirrors C's incomplete `void` — no value representation, existing only as the thing a `void*` points at. This is exactly why `Ptr[Void].deref()` / `.write()` are rejected (E0825, below): there is no value of type `Void` to read or write.

**Valid type parameters:** `Ptr[T]` accepts only FFI-compatible types: `Void`, `U8`, `U16`, `U32`, `U64`, `I8`, `I16`, `I32`, `Int` (maps to `int64_t`), `Float` (maps to `double`), and `Ptr[T]` itself (for pointer-to-pointer). Using a GC-managed type (e.g., `Ptr[Str]`, `Ptr[List[T]]`) is a compile error.

```
error[E0810]: invalid Ptr type parameter
 --> db/sqlite.bl:5:20
  |
5 | fn bad(data: Ptr[Str]) -> Int
  |                  ^^^ `Str` is GC-managed and cannot be pointed to
  |
  = help: use `Ptr[U8]` for C strings, convert with `.as_cstr()`
```

#### Pointer Operations

All pointer operations are methods on `Ptr[T]` and compiler-known functions in the `ffi` namespace. They are available **without any import** — `ffi` is a no-import intrinsic namespace like `io`/`net`/`time`, and `import blink.ffi[.{...}]` is an **optional documentation marker**, never a requirement. The capability gate is on *where* a `Ptr[T]` may appear — inside an **FFI region** (`PtrOutsideFFI`, E0811) — not on any import (see *FFI import resolution and the real gates* above).

**FFI regions.** A `Ptr[T]` — and every pointer operation in the table below — may appear only inside one of three lexical regions. This is the single, canonical statement of where E0811 permits a pointer; other sections point here rather than restate it:

1. the body of an `@ffi` function;
2. the body of an `@trusted` function;
3. a `with ffi.scope() as _ { }` block (§9.1.1, *`ffi.scope`* — the block that owns the pointer's lifetime).

The region is a **purely syntactic**, per-function structural property, decided without type resolution. A term that closes over its lexical environment inherits the region; an item does not:

- A closure literal written inside a region **inherits** it — the pointer operations stay legal in the closure body.
- A `fn` clause in a `handler E { }` expression written inside a region **inherits** it, the same as a closure literal. A handler clause is a member of an expression value that captures its environment the same way a closure does (§4.7, *Basic handler syntax*), not an item: you cannot call, import or refer to it by name.
- A **named** nested `fn` item does **not** inherit the enclosing region: it is its own function and needs its own `@ffi`/`@trusted` annotation or its own `ffi.scope` block. Blink does not parse named nested `fn` items today; this rule fixes their region behavior in advance, and it does not apply to handler clauses.

**E0811 covers bodies, not only signatures.** E0811 rejects a `Ptr[T]` (or an `@ffi.struct` that holds a `Ptr` field) at every site outside a region: a parameter or return type, a `let` annotation, and every expression in a function body whose checked type is a `Ptr[T]`. Whether a site is in a region is syntactic; whether an expression is a `Ptr` comes from its checked type. So a `p.deref()` in an ordinary function, outside every region, does not compile.

A pointer that *escapes* its region dynamically — returned, stored past it, captured by an escaping closure, passed to an effect handler, or passed beside a pointer-holding argument — is not E0811's concern; that is the scope-escape diagnostic E0601 (§9.1.1, *Scope tags*).

An `@ffi.struct` type with a `Ptr` field, directly or through a nested `@ffi.struct` field, is subject to E0811 exactly as `Ptr[T]` is (§9.1.3).

This is the **canonical** `Ptr[T]` operations table. §9.1.3 extends it with `@ffi.struct` field projection (`p.field.read()` / `p.field.write(v)`) and array regions (`scope.alloc_n`); no other section redefines these operations.

| Operation | Signature | C Mapping | Description |
|-----------|-----------|-----------|-------------|
| `alloc_ptr[T]()` | `fn alloc_ptr[T]() -> Ptr[T]` | `calloc(1, sizeof(T))` | Allocate zero-initialized memory for one `T` (GC-registered fallback; prefer `scope.alloc`) |
| `null_ptr[T]()` | `fn null_ptr[T]() -> Ptr[T]` | `NULL` | Construct a null pointer of type `Ptr[T]` — the only way to spell `NULL` in Blink |
| `.deref()` | `fn deref(self) -> T` | `*ptr` | Read the value behind the pointer. **No null check** — the pointee is an audited premise (see *Nullability*). Rejected on `Ptr[Void]` (E0825) |
| `.write(value)` | `fn write(self, value: T)` | `*ptr = value` | Write a value through the pointer. Takes plain `self`: a write through a pointer is an effect, not a `mut` mutation (§3.6 *Mutable Parameters*). Rejected on `Ptr[Void]` (E0825) |
| `.is_null()` | `fn is_null(self) -> Bool` | `ptr == NULL` | Test whether the pointer is null. Defined as shorthand for `p == null_ptr()` |
| `.addr()` | `fn addr(self) -> Int` | `(intptr_t)ptr` | The pointer's numeric address as an `Int`. **NOT** `&ptr` — an observation, not an out-parameter |
| `.offset(i)` | `fn offset(self, i: Int) -> Ptr[T]` | `ptr + i` | Pointer to element `i` of an `alloc_n` region (§9.1.3). Rejected on a singleton `alloc[T]()`/`alloc_ptr[T]()` result (E0813) |
| `.as_cstr()` | `fn as_cstr(self: Str) -> Ptr[U8]` | `strdup(s)` | Convert a Blink `Str` to a null-terminated C string copy (method on `Str`) |
| `.to_str()` | `fn to_str(self: Ptr[U8]) -> Option[Str]` | null-check + copy | Convert a null-terminated C string to a Blink `Str`. `None` if the pointer is null |

`Ptr[T]` also supports `==` / `!=`; equality against `null_ptr()` is the primitive that `.is_null()` desugars to.

**`.deref()` semantics — bare `T`, `Option` is not returned.** `deref` reads the pointee and returns it **unwrapped**. It performs no null check: dereferencing a null or dangling pointer is undefined behaviour, accounted for by the `@ffi`/`@trusted` audit gate (E0811), not by the type. The reason `Option` is *not* returned follows the **"Option must be earned"** principle: an operation returns `Option[T]` only when a failure is observable as a value the operation itself produces (as `.to_str()` observes a null terminator). A load's null-partiality is not recoverable as a value, so no `Option` can honestly model it — wrapping it would advertise a check `deref` does not perform. When you need the null test, spell it: `if p.is_null() { ... }` before the read.

**`.deref()` / `.write()` on `Ptr[Void]` — rejected (E0825).** `Void` has no value representation, so there is no bare `T` for `deref` to return and no value for `write` to store (`*(void*)p` is a C constraint violation). Both ops are rejected at compile time; see *Diagnostic Integration*. Every other operation — `.addr()`, `.offset()`, `==`, `.is_null()`, `null_ptr[Void]()`, and passing the pointer to C — is unaffected, so `Ptr[Void]` remains fully usable as an opaque handle.

**`.addr()` semantics — numeric address, not address-of.** `addr` returns the pointer's address as a plain `Int`, mapping to `(intptr_t)ptr` — an *observation* of the pointer's value. It is **not** `&ptr`: there is no `Ptr.from_int(Int)` and none is provided, so the integer is not a capability to reconstruct the pointer. For a C **out-parameter** (`T**`), do not take the address of a local — allocate the cell as a pointer-to-pointer and pass it directly:

```blink
with ffi.scope() as scope {
    let cell = scope.alloc[Ptr[Void]]()   // a Ptr[Ptr[Void]] cell
    let rc = raw_sqlite3_open(cstr, cell)  // pass the cell, not cell.addr()
    let db = cell.deref()                  // read the T** back out — a Ptr[Void]
}
```

**`null_ptr[T]()` semantics.** Constructs a null `Ptr[T]`. It is the sole way to spell `NULL` in Blink surface — required to pass `NULL` *into* C and to compare against a possibly-null C return (`p == null_ptr()`, or equivalently `p.is_null()`).

**`.write()` restriction:** Writing a GC-managed reference through a pointer is a compile error. Only FFI-compatible values (integers, floats, other pointers) can be written.

**`.as_cstr()` semantics:** Creates a `malloc`'d null-terminated copy of the Blink string's bytes. The copy is allocated outside the GC and must be freed via `ffi.scope()` or manual cleanup. This is a method on `Str`, not on `Ptr[T]`.

**`.to_str()` semantics:** Reads bytes from a `Ptr[U8]` until a null terminator, creates a GC-managed Blink `Str`. Returns `None` if the pointer is null — an `Option` earned by the walk to the terminator, which observes nullness as a value.

#### Example: Complete FFI Wrapper

```blink
import blink.ffi.{Ptr, Void, alloc_ptr}

@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn raw_sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! IO

@ffi("sqlite3", "sqlite3_close")
@trusted(audit: "DB-004")
fn raw_sqlite3_close(db: Ptr[Void]) -> Int ! IO

pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    with ffi.scope() as scope {
        let db_ptr = scope.alloc[Ptr[Void]]()   // a Ptr[Ptr[Void]] out-param cell
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, db_ptr)  // pass the cell directly
        match rc {
            0 => {
                let raw_db = db_ptr.deref()      // Ptr[Void] — bare, no Option
                Ok(Database.from_ptr(scope.take(raw_db)))
            }
            _ => Err(DbError.from_code(rc))
        }
    }
}
```

#### Lifetime and Cleanup: `ffi.scope()`

Pointer memory is managed through **scoped allocation** using `ffi.scope()`, which integrates with Blink's existing `Closeable` trait and `with...as` syntax (§5.5).

```blink
import blink.ffi

with ffi.scope() as scope {
    let ptr = scope.alloc[U8]()       // allocated within scope
    let cstr = scope.cstr("hello")    // C string copy within scope
    raw_process(ptr, cstr)
}
// scope.close() runs here: frees ptr, cstr, and all scope allocations
```

**`FfiScope` operations** — the receiver in every row is the `FfiScope` value `ffi.scope()` returns (see *The `FfiScope` type*, below):

| Operation | Signature | Description |
|-----------|-----------|-------------|
| `scope.alloc[T]()` | `fn alloc[T](self) -> Ptr[T]` | Allocate zero-initialized memory, tracked by scope |
| `scope.cstr(s)` | `fn cstr(self, s: Str) -> Ptr[U8]` | Create scoped null-terminated C string copy |
| `scope.take(ptr)` | `fn take[T](self, ptr: Ptr[T]) -> Ptr[T]` | Transfer pointer ownership out of scope (not freed at scope exit) |

**Scope rules:**
- All allocations made through a scope are freed when the `with` block exits (normal return, `?` early return, or any other exit path).
- `scope.take(ptr)` removes a pointer from the scope's cleanup list. The caller assumes responsibility for the pointer's lifetime — typically by wrapping it in a safe Blink type whose `Closeable.close()` calls the appropriate C cleanup function.
- Scope-allocated pointers that escape the scope without `.take()` trigger a compile error (reusing E0601 from `Closeable` diagnostics). The compiler finds these by inferring a scope tag for each pointer; see *Scope tags*, below.

**The `FfiScope` type.** `ffi.scope()` returns a value of type `FfiScope`. `FfiScope` is **scope-bound**: a value of this type may occur only as the resource of a `with ... as` block, **and nowhere else**. It may not be bound by a `let`, passed as an argument, returned, stored in a field, or written as a type argument.

```blink
import blink.ffi

fn read_name() ! IO {
    with ffi.scope() as scope {          // OK -- the only position an `FfiScope` may occupy
        let buf = scope.alloc[U8]()
        raw_gethostname(buf, 256)
    }
}

// intentional-error example
fn leaks() ! IO {
    let arena = ffi.scope()              // error[FfiScopeNotWithResource]: an `FfiScope` may occur
                                         //   only as a `with ... as` resource
                                         // help: bind it as a `with` resource:
                                         //   `with ffi.scope() as arena { ... }`
                                         // help: for one plain allocation with GC cleanup, use
                                         //   `alloc_ptr[T]()` instead of a scope
    let buf = arena.alloc[U8]()
}
```

The rule is stated over the **type**, not over the `ffi.scope()` call, because the hazard belongs to the value. A scope owns a libc `malloc`/`free` arena whose extent must be lexical, and every position the rule excludes is a position from which that arena outlives the block that frees it — however the value arrived there. A rule stated over the call site would test how the call is *written*, so any binding or indirection walks past it while the hazard is unchanged, and it would need a fresh clause for every future function that produces a scope.

**Why this is an error where the `Closeable`-without-scope rule is a warning.** A `Closeable` value used outside `with ... as` is still reclaimed; that warning reports a resource released late and non-deterministically. An `FfiScope` used outside `with ... as` releases **nothing** — its arena is libc memory the collector does not see, so every allocation made through it leaks for the life of the process. The two rules differ in severity because they differ in outcome, not in strictness. (See §5.5, *`Closeable` values and `with ... as`*, named here rather than cited by code number.)

**Message conditions** (normative, per §3.1 *Diagnostic Discipline*):
- The shown repair carries the **author's own binder**, not a hardcoded `scope`.
- The `let` → `with ... as` rewrite is **not** machine-applicable, and must not be offered as one: no fixer can decide where the block should end.
- A second `help:` names `alloc_ptr[T]()`, so a writer who wanted one plain allocation is not taught to wrap a `with` block around the rest of the function.
- Where `.take()` is named in a repair it is explained in the same breath — it removes a pointer from the scope's cleanup list and transfers that pointer's lifetime to the caller (see *Scope rules*, above).

**Long-lived pointers:** For C handles that must outlive a lexical scope (e.g., a database connection stored in a struct field), use `scope.take()` to transfer ownership, then wrap in a `Closeable` type:

```blink
pub type Database {
    handle: Ptr[Void]
}

impl Closeable for Database {
    fn close(self) ! IO {
        raw_sqlite3_close(self.handle)
    }
}

pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    with ffi.scope() as scope {
        let db_ptr = scope.alloc[Ptr[Void]]()   // a Ptr[Ptr[Void]] out-param cell
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, db_ptr)  // pass the cell directly
        match rc {
            0 => {
                let raw_db = db_ptr.deref()      // Ptr[Void]
                Ok(Database { handle: scope.take(raw_db) })
            }
            _ => Err(DbError.from_code(rc))
        }
    }
}
```

**Standalone `alloc_ptr[T]()`:** The top-level `alloc_ptr[T]()` function (not on a scope) allocates GC-registered memory with a finalizer that calls `free()` on collection. This is the fallback for simple cases where scoped allocation is unnecessarily ceremonial. Prefer `ffi.scope()` for deterministic cleanup.

```blink
// Simple case: GC handles cleanup
let buf = alloc_ptr[U8]()  // GC-registered, freed on collection
let rc = raw_gethostname(buf, 256)
let hostname = buf.to_str() ?? "unknown"
// buf freed whenever GC collects it
```

**Guidance:** Use `ffi.scope()` when the C library requires deterministic cleanup (databases, file handles, allocated buffers). Use standalone `alloc_ptr` only for trivial, short-lived allocations where GC collection is acceptable.

#### Scope tags

Decided by panel deliberation [`ffi-scope-tag-inference`](../decisions/ffi-scope-tag-inference.md).

The compiler gives each value that can carry a pointer a **scope tag**: the `ffi.scope` block whose exit frees the memory, or **unscoped** when no block frees it. The compiler infers every tag. Blink has no syntax to write a tag — not in a type, not in a signature, not anywhere. This is the same rule as for arena-local parameters (§5.2.1): no region-variable annotations are required or accepted.

**Notation.** In this spec, `Ptr[T]^σ` and `Buf[T]^σ` are meta-notation for "a `Ptr[T]` (or `Buf[T]`) whose scope tag is σ". They are not source syntax: in source, `^` is only bitwise XOR. Hover and diagnostics print a tag as `(scope: outer)`, never as `^σ`.

**Pointer-bearing types.** A type is *pointer-bearing* when `Ptr` or `Buf` occurs anywhere in it, including through the fields of an `@ffi.struct` at any depth (`Ptr[U8]`, `Option[Ptr[T]]`, `List[Ptr[T]]`, an `@ffi.struct` with a `Ptr` field). Only values of pointer-bearing types, and closures that capture them, carry a tag.

**Tag identity.** A tag is the binder of one `with ffi.scope() as s` block — the syntax node, not its name. Two nested blocks that both bind `s` give two different tags. When two live binders have the same name, diagnostics and hover print the name with its line: `s (line 4)`.

**Order.** An `FfiScope` cannot be let-bound, passed, returned or stored (*The `FfiScope` type*, above), so scope blocks nest lexically and the live tags at any point form one chain. Tag `a` **encloses** tag `b` when block `a` is block `b` or contains it, so `a` is freed at the same time as `b` or later. Unscoped encloses every tag. Any set of live tags therefore has exactly one innermost member.

**Inference rules.** Each rule reads only the expression and the declared types of its callee. No rule reads the body of another function.

| Expression | Tag of the result |
|---|---|
| `s.alloc[T]()`, `s.alloc_n[T](n)`, `s.cstr(str)` | `s` |
| `libc.copy_to_buf(b)` | the innermost `ffi.scope` block around the call |
| `s.take(p)` | unscoped |
| `alloc_ptr[T]()`, `null_ptr[T]()` | unscoped |
| `p.offset(i)`; `p.deref()` or `p.field.read()` that gives a pointer-bearing value | the tag of `p` |
| A struct literal, tuple, `Some(v)`, `Ok(v)` or `Err(v)` | the innermost tag of its parts; unscoped if none has a tag |
| A closure literal | the innermost tag of the values it captures; unscoped if none has a tag |
| A pointer-bearing parameter of a closure literal (e.g. the `p` in `bs.with_ptr(fn(p) { ... })`) | a fresh tag whose block is the closure body: it encloses every scope block the body opens, and every tag live around the literal encloses it |
| Any other call whose result type is pointer-bearing | the innermost tag of its pointer-bearing arguments (a method receiver is an argument); unscoped if there are none |

A **cell** is a place that holds a value after the expression that puts it there ends. The cell's tag decides what it may hold:

- the pointee of a `Ptr` (including a field reached through `p.field`): the tag of the `Ptr`;
- a `let mut` binding: the innermost `ffi.scope` block around its declaration, or unscoped;
- a `List`, `Map` or `Set` value: the innermost `ffi.scope` block around the expression that creates it, or unscoped;
- an effect handler: the innermost `ffi.scope` block around the `with` that installs it, or unscoped.

**`E0601 (value-escape)`.** A value with tag `s` that leaves block `s` as its result — by `return`, by `?`, or as the block's tail expression — is an error. `s.take(p)` is the way out: its result is unscoped.

**`E0601 (tag-mismatch)`.** A value with tag `v` stored into a cell with tag `c` is an error unless `v` encloses `c`. There are exactly four ways to store a value into a cell:

1. **Write.** `c.write(v)`, `c.field.write(v)`, or assignment `x = v` to a `let mut` binding.
2. **Capture.** A closure that captures a value with tag `s` follows the escape rules of a closure that captures a `Closeable` bound by block `s` (§2, *Closures and Scoped Resources*; §5.5): it may not be returned from block `s` or stored in a cell that `s` does not enclose.
3. **Effect argument.** Passing a tagged value as an argument to an effect operation stores it into the handler that receives it. A handler installed inside block `s` may receive a value with tag `s`; a handler installed outside `s` may not.
4. **Call beside a pointer-holding argument.** At a call, a tagged value passed next to an argument whose declared parameter type is *pointer-holding* counts as stored into that argument. A parameter type is pointer-holding when a callee can store a pointer through it that the caller can reach after the call: `Ptr[P]` for a pointer-bearing `P` (`Ptr[Ptr[T]]`, or `Ptr[S]` for an `@ffi.struct S` with a `Ptr` field at any depth), or a `List`, `Map` or `Set` whose element type is pointer-bearing. `Ptr[U8]`, `Ptr[Void]` and `Ptr[S]` for a struct with no `Ptr` field are not pointer-holding. So `memcpy(dst, src)` with `dst` and `src` from different scopes is legal, and `c_writev(fd, iov, 2)` (one pointer argument) never pairs anything.

This list is **closed and exhaustive**. A language change that adds a new way to store a value must add a row to it.

**Pointer parameters inside `@trusted` bodies.** In the body of an `@trusted` function, every pointer-bearing parameter has one shared tag: the caller's. That tag encloses every scope block the body opens. A store from one parameter into another therefore passes the check inside the body. This is sound because rule 4 already rejected, at every call site, each call that pairs a younger pointer with an older pointer-holding argument. `blink audit` lists each such parameter-into-parameter store as `ptr-store-param`.

```blink
@ffi.struct(header = "sys/uio.h", name = "iovec")
pub type IoVec {
    iov_base: Ptr[U8],
    iov_len: U64,
}

@trusted(audit: "NET-012")
fn set_iov(iov: Ptr[IoVec], buf: Ptr[U8], len: U64) {
    iov.iov_base.write(buf)   // OK here: `iov` and `buf` share the caller's tag
    iov.iov_len.write(len)
}

fn send_two(fd: Int) ! IO {
    with ffi.scope() as outer {
        let iov = outer.alloc_n[IoVec](2)
        with ffi.scope() as inner {
            let buf = inner.alloc_n[U8](64)
            set_iov(iov, buf, 64)   // error[E0601] tag-mismatch: rule 4
        }
        c_writev(fd, iov, 2)        // would read `buf` after `inner` freed it
    }
}
```

**C-side retention is out of scope.** Tag checks see only stores the Blink program makes. A C function that keeps a pointer after it returns (`aio_write`, `io_uring` submission, `setvbuf`) or stores through a `Ptr[Void]` is part of the audited trust base, the same as an `@trusted` body. Passing the tag checks does not prove the absence of a use-after-free inside C. `blink audit` lists every `@ffi` function that takes a pointer-bearing argument, so a reviewer can find these.

#### Diagnostic Integration

Pointer types integrate with Blink's existing diagnostic infrastructure:

```
error[E0810]: invalid Ptr type parameter
 --> crypto/sodium.bl:5:20
  |
5 | fn bad(data: Ptr[List[U8]]) -> Int
  |                  ^^^^^^^^ `List[U8]` is GC-managed
  |
  = help: use `Ptr[U8]` and convert manually

error[E0811]: Ptr[T] used outside FFI context
 --> app/main.bl:12:5
  |
12|     let p = alloc_ptr[Int]()
  |     ^^^^^^^^^^^^^^^^^^^^^^^^ pointer allocation outside @ffi module
  |
  = note: Ptr types are for FFI interop only
  = help: use normal Blink types for application code

warning[W0810]: unscoped pointer allocation
 --> db/sqlite.bl:15:5
  |
15|     let ptr = alloc_ptr[Void]()
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ allocated outside `ffi.scope()`
  |
  = help: wrap in `with ffi.scope() as scope { scope.alloc[Void]() }`
  = note: unscoped pointers rely on GC finalization (non-deterministic)

error[E0825]: cannot deref `Ptr[Void]` — the pointee type is unknown
 --> db/sqlite.bl:22:13
  |
22|     let v = handle.deref()
  |             ^^^^^^^^^^^^^^ `Void` names no value to read
  |
  = note: `Ptr[Void]` is an opaque handle: pass it to C and test it with
          `.is_null()`, but there is no value behind it to read or write
  = help: if you know the pointee type, declare it — `Ptr[Int]`, `Ptr[U8]`, …
  = help: for a C struct, use `@ffi.struct` and read fields with `p.field.read()`

error[E0601]: pointer from a shorter-lived scope passed beside a pointer container (tag-mismatch)
  --> src/net.bl:9:9
   |
 9 |         set_iov(iov, buf, 64)
   |                 ---  ^^^ `buf` belongs to scope `inner` (line 7)
   |                 |
   |                 `iov` belongs to scope `outer` (line 4)
   = note: parameter `iov: Ptr[IoVec]` can hold pointers (`IoVec.iov_base: Ptr[U8]`),
           so `set_iov` may store `buf` in it
   = help: allocate `buf` from `outer`
```

**E0601 message conditions** (normative, per §3.1 *Diagnostic Discipline*):
- Each tag prints as the author's own scope binder. When two live binders have the same name, it prints with its line: `s (line 4)`.
- A tag-mismatch error names the store form (write, capture, effect argument, or call). For a call, it names the pointer-holding parameter and, for an `@ffi.struct` pointee, the `Ptr` field that makes it pointer-holding.
- When a tag came from the call rule, the error names the argument that set it.
- The repair ("allocate from `outer`") is not machine-applicable: the allocation site may be far from the store.
- `blink explain E0601` gives one example per store form and states the C-side retention limit.

`blink audit` includes pointer allocations alongside FFI call sites and `Raw()` query sites:

```
Pointer Allocations: 3 across 2 modules
  db/sqlite.bl:
    ffi.scope()       line 15    scoped (OK)
    ffi.scope()       line 28    scoped (OK)
  net/curl.bl:
    alloc_ptr[Void]   line 7     unscoped (WARNING)
```

### 9.1.2 Native Dependency Resolution

When Blink code uses `@ffi` to bind a C library, the compiler must *link* against that library. On the host system, dynamic linking (`-l`) works if the library is installed. Cross-compilation breaks this: the target system's libraries are not available on the build machine.

This section specifies how native C dependencies are declared, resolved, and linked — for both user `@ffi` bindings and compiler-provided built-in modules.

#### Two-Tier Model: Compiler-Managed vs User-Managed

Native C dependencies fall into two categories:

**Compiler-managed** dependencies back language-defined effect domains. The `db.*` operations (backed by sqlite3) and `net.*` operations (backed by POSIX sockets) are language primitives — they participate in the effect system, have compiler-known semantics, and are defined by the language, not imported from C headers. The compiler is responsible for providing these dependencies on all supported targets. Users never declare them in `blink.toml`.

**User-managed** dependencies are C libraries bound via `@ffi`. The user is responsible for declaring how to resolve them. The compiler cannot know what arbitrary C libraries a project needs.

The boundary is crisp: if the API is behind a Blink effect handle (`db.*`, `net.*`, `io.*`), the compiler manages its native deps. If it's raw `@ffi`, the user manages it, except for the runtime libraries `c` and `m`, which every program links (*Runtime libraries*, below).

#### `[native-dependencies]` in `blink.toml`

User `@ffi` bindings require a corresponding entry in the `[native-dependencies]` section of `blink.toml`. An `@ffi` annotation that names a library not declared in `[native-dependencies]` is a compile error (E0820). The two runtime libraries `c` and `m` are the only exception (*Runtime libraries*, below).

A program with no `blink.toml` gets the same check as a manifest with an empty `[native-dependencies]` section. It can bind `c` and `m`; any other library is E0820, and the help tells the user to create `blink.toml`.

```toml
[native-dependencies]
# System library — dynamic link, must be installed on target
libsodium = { type = "system" }

# Vendored source — compiled alongside generated C
libpq = { type = "vendored", path = "vendor/libpq.c" }

# pkg-config lookup (host builds only, cross-compile falls back to vendored)
zlib = { type = "pkg-config", name = "zlib" }
```

**Schema:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `"system"` \| `"vendored"` \| `"pkg-config"` | How to resolve the library |
| `path` | `Str` (optional) | Path to vendored C source file(s), relative to project root |
| `name` | `Str` (optional) | pkg-config package name (defaults to dependency key) |
| `link` | `"static"` \| `"dynamic"` (optional) | Override default linking strategy |

**Diagnostic — missing native dependency:**

```
error[E0820]: @ffi references undeclared native dependency
 --> crypto/sodium.bl:3:1
  |
3 | @ffi("libsodium", "crypto_secretbox_easy")
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ library "libsodium" not in [native-dependencies]
  |
  = help: add to blink.toml:
  = help:   [native-dependencies]
  = help:   libsodium = { type = "system" }
```

When the program has no `blink.toml`, the help shows a complete file to create, not a section to add:

```
  = help: create blink.toml (`blink init` writes one), with:
  = help:   [package]
  = help:   name = "sodium_demo"
  = help:   version = "0.1.0"
  = help:
  = help:   [native-dependencies]
  = help:   libsodium = { type = "system" }
```

#### Runtime libraries

The runtime row of the *Compiler-Managed Dependency List* (below) names libc and libm. Every Blink program links them, so the compiler manages them. In `@ffi` they have exactly one name each: `"c"` for libc and `"m"` for libm. That row is the whole set: no other library is implicit (pthreads, sqlite3 and POSIX sockets are not), and the set changes only by spec revision.

- `@ffi("c", ...)` and `@ffi("m", ...)` need no `[native-dependencies]` entry, and they add no link flag. The one-argument form `@ffi("symbol")` binds from the same two libraries (§9.1).
- `@ffi("libc", ...)` and `@ffi("libm", ...)` are E0820. The library is not declared, and the fix changes only the library argument to `"c"` or `"m"`. The fix is machine-applicable, and it never changes the symbol argument.
- A `[native-dependencies]` key that names a runtime library (`c`, `m`, `libc` or `libm`) is a compile error (E0841). The compiler already links that library, so the entry can only add a second copy to the link or be ignored. The diagnostic points at the key in `blink.toml`, and its machine-applicable fix deletes the line.

```blink
@ffi("c", "getenv")
@trusted(audit: "ENV-001")
fn raw_getenv(name: Ptr[U8]) -> Ptr[U8] ! Env

@ffi("m", "cos")
@trusted(audit: "LIBM-COS")
fn raw_cos(x: Float) -> Float ! ()
```

**Diagnostic — runtime library spelled with a `lib` prefix:**

```
error[E0820]: @ffi references undeclared native dependency
 --> env.bl:1:1
  |
1 | @ffi("libc", "getenv")
  |      ^^^^^^ library "libc" not in [native-dependencies]
  |
  = note: libc is a runtime library; @ffi names it "c"
  = help: replace "libc" with "c"
```

**Diagnostic — runtime library declared in the manifest:**

```
error[E0841]: native dependency names a runtime library
 --> blink.toml:7:1
  |
7 | m = { type = "system" }
  | ^ "m" is a runtime library; the compiler links it into every program
  |
  = note: @ffi("m", ...) needs no [native-dependencies] entry
  = help: delete this line
```

#### Linking Strategy

The compiler uses different linking strategies for host and cross-compilation targets:

**Host builds** (`blink build` with no `--target`): Dynamic linking by default. The compiler uses system-installed libraries via `-l` flags. `pkg-config` entries are resolved via the host's `pkg-config` tool.

**Cross-compilation** (`blink build --target <triple>`): Static linking by default. The compiler compiles vendored C sources alongside the generated C output using the cross-compiler (e.g., `zig cc -target <triple>`). Dependencies declared as `type = "system"` with no vendored fallback produce a clear error:

```
error[E0821]: native dependency unavailable for cross-target
 --> blink.toml:8:1
  |
8 | libsodium = { type = "system" }
  | ^^^^^^^^^ "libsodium" is system-only but target is aarch64-linux-gnu
  |
  = note: cross-compilation requires vendored source or static archive
  = help: provide source: libsodium = { type = "vendored", path = "vendor/sodium.c" }
  = help: or override linking: libsodium = { type = "system", link = "dynamic" }
```

The `link = "dynamic"` override forces dynamic linking for a cross-target. This is an explicit opt-in — the user accepts that the target system must have the library installed.

**Compiler-managed deps** follow the same strategy automatically: the compiler bundles source for its own dependencies (e.g., the sqlite3 amalgamation) and compiles them from source during cross-compilation, or dynamically links on the host. Users never interact with this.

#### Compiler-Managed Dependency List

The following native C dependencies are compiler-managed. This list is exhaustive — additions require a spec revision:

| Module | C Dependency | Strategy |
|--------|-------------|----------|
| `db.*` | sqlite3 | Amalgamation bundled with compiler |
| `net.*` | POSIX sockets | System headers (no library linkage) |
| runtime | libc, libm (`@ffi` names: `c`, `m`) | System (always available) |
| `async.*` | pthreads | System (`-pthread` flag) |

#### Interaction with `blink audit`

`blink audit` includes native dependency status alongside FFI call sites:

```
Native Dependencies:
  compiler-managed:
    sqlite3           bundled (3.45.0)    OK
    pthreads          system              OK
  user-managed:
    libsodium         vendored            vendor/sodium.c    OK
    zlib              pkg-config          host-only          WARNING (no cross-target source)
```

### 9.1.3 FFI Struct Construction & Buffer Bridges

Section 9.1.1 fixes `Ptr[T]` as an opaque single-cell handle and freezes the 8-op table. That's right for SQLite handles and other named pointer types, but `Ptr[T]` alone cannot construct values whose C declaration is a multi-field `struct` or an N-element array — `pollfd[]` for `poll(2)`, `iovec[]` for `readv(2)`, `sigaction` for `sigaction(2)`. This subsection is the resolution of that gap, decided by panel deliberation [`ffi-struct-construction`](../decisions/ffi-struct-construction.md).

Three mechanisms ship together:

1. **β-minimal — `@ffi.struct` types and `Ptr[@ffi.struct T]` field access** (primary, for typed records).
2. **α-1 — `Bytes.with_ptr` closure-scoped borrow** (helper, for opaque byte payloads — `read`/`write`/`recv`/`send`/`mmap`/`iovec.iov_base`).
3. **γ-doctrine — curated `std.libc.*` wrappers** is the recommended user-facing surface; user-defined `@ffi.struct` is allowed but discouraged outside stdlib.

#### `@ffi.struct` — declaring a C-shaped record

```blink
import blink.ffi.{Ptr, I16, I32, U16}

@ffi.struct(header = "poll.h", name = "pollfd")
pub type Pollfd {
    fd: I32,
    events: I16,
    revents: I16,
}
```

`@ffi.struct(header, name)` declares that a Blink type mirrors a named C struct from a specific C header. The header is resolved against the project's `[native-dependencies].headers` list. Fields are listed in declaration order and must use sized FFI-compatible types: `I8`/`I16`/`I32`/`Int`, `U8`/`U16`/`U32`/`U64`, `F32`/`Float`, `Bool`, `Ptr[T]`, or another `@ffi.struct` type. List, Str, Bytes, Map, Result, Option, and trait types are rejected with `E0812` (extending the existing GC-types-cannot-cross-FFI rule from `E0810` for `Ptr[T]`). A `Buf[T]` field is rejected with `E0822`: a `Buf` value is a `blink_buf_t*`, not the C pointer the field declares, and the size `_Static_assert` cannot catch the difference. Use `Ptr[T]`.

**`Bool` at the FFI boundary.** In an FFI position (an `@ffi.struct` field, an `@ffi` parameter or an `@ffi` return), `Bool` is C `bool` (`_Bool`): the struct mirror and the foreign prototype spell it `bool`, with C's size and alignment. A `Bool` read from C (an `@ffi` return, or an `@ffi.struct` field read) is always `true` or `false`, as every `Bool` is (§3.4 *`Bool` Is Distinct from `Int`*). A C `int` used as a flag is not a `bool`: declare it `I32` and convert with `!= 0`.

```blink
import blink.ffi.{Ptr, Void, I32}

@ffi.struct(header = "opts.h", name = "opts_t")
pub type Opts {
    verbose: Bool,     // C: bool verbose;
    level: I32,        // C: int level;
}

@ffi("libfoo", "foo_is_open")
@trusted(audit: "FOO-1")
fn foo_is_open(h: Ptr[Void]) -> I32 ! IO // C: int foo_is_open(foo_t *h);

@trusted(audit: "FOO-1")
fn is_open(h: Ptr[Void]) -> Bool {
    foo_is_open(h) != 0
}
```

A `Bool` field that mirrors a C `int` field fails the layout check; the diagnostic says to declare the field `I32`.

**Pointer-bearing structs and E0811.** An `@ffi.struct` with a `Ptr` field, directly or through a nested `@ffi.struct` field at any depth, is subject to E0811 exactly as `Ptr[T]` is: a value of it may appear only in an FFI region (§9.1.1). The E0811 error names the field, e.g. "`IoVec` holds `Ptr` in field `iov_base` (line 3), so it may appear only in an FFI region". A pointer stored into such a field is subject to the scope-tag store rules (§9.1.1, *Scope tags*).

#### Field access on `Ptr[@ffi.struct T]`

`p.field` on a `Ptr[T]` where `T` is `@ffi.struct` desugars to a typed pointer-to-field that supports `.read()` / `.write(v)`:

```blink
with ffi.scope() as scope {
    let p: Ptr[Pollfd] = scope.alloc[Pollfd]()
    p.fd.write(fd)
    p.events.write(POLLIN)
    p.revents.write(0)

    let rc = c_poll(p, 1, timeout_ms)
    let revents = p.revents.read()
}
```

Desugaring rule: `p.field.read()` lowers to `*(typeof(field)*)((char*)p + offsetof(T, field))`; `p.field.write(v)` lowers to the same `lvalue = v`. The `_Static_assert` codegen described below witnesses that the offsets the Blink compiler computed match the C ABI.

`p.field` outside a `read()`/`write()` call is rejected. There is no first-class "pointer to field" value in user surface — `field_addr` is a compiler-internal desugar, not a user-callable op.

#### Array allocation: `scope.alloc_n[T](n)`

```blink
with ffi.scope() as scope {
    let pfds: Ptr[Pollfd] = scope.alloc_n[Pollfd](fds.len())
    for (i, e) in fds.enumerate() {
        let p = pfds.offset(i)
        p.fd.write(e.fd)
        p.events.write(e.events)
        p.revents.write(0)
    }
    let rc = c_poll(pfds, fds.len(), timeout_ms)
}
```

`scope.alloc_n[T](n)` allocates `n * sizeof(T)` zeroed bytes (`calloc`) and returns a `Ptr[T]` aliasing the first cell. The result lives until the enclosing `ffi.scope` exits. `pfds.offset(i)` (added to the §9.1.1 op table as op #9) returns a `Ptr[T]` aliasing cell `i`; bounds are not checked at the language level — the user is responsible for staying within `n`.

`offset(i)` is permitted only on `Ptr[T]` values returned by `alloc_n` or by another `offset`; it is rejected on the singleton-cell `alloc[T]()` result with `E0813`.

#### `Bytes.with_ptr` — opaque-byte FFI helper

For libc surfaces that take `void*` / `uint8_t*` / `char*` (read, write, recv, send, mmap-region, `iovec.iov_base`, `getrandom`, `ioctl`-data), the curated `std.libc.*` wrappers use `Bytes.with_ptr`:

```blink
fn read(fd: I32, n: Int) -> Result[Bytes, Str] ! IO {
    let buf = Bytes.zeroed(n)
    let got = buf.with_ptr(fn(p) { c_read(fd, p, n) })
    if got < 0 {
        Err("read failed")
    } else {
        Ok(buf.slice(0, got))
    }
}
```

Signature:

```blink
fn with_ptr[R](self: Bytes, body: fn(Ptr[U8]) -> R ! _) -> R ! _
```

The closure body holds a `Ptr[U8]` aliasing the `Bytes`'s GC-managed `data` field. Soundness rests on three invariants:

1. **The Boehm-Demers-Weiser collector is non-moving by design contract.** This is a runtime constraint on the GC choice, not an accident; replacing BDW with a moving collector would require revisiting α-1.
2. **The closure capture of `self` keeps the `Bytes` reachable** for the duration of the call — BDW's conservative scan sees the `blink_bytes*` on the C stack inside the inlined closure body.
3. **The closure body must not call growth-effecting methods on `self`.** This is the closure-lexical no-grow check (§9.1.3.1 below).

`Bytes.with_ptr` forwards the effect row of its closure (`! _`, §4.15.2): the call has exactly the effects of the `@ffi` functions the closure calls. It ships in `std.bytes`. It is the only sanctioned form of Bytes→Ptr aliasing. User-code Bytes→Ptr bridges are forbidden (see Bytes Bridge Doctrine below).

##### 9.1.3.1 Closure-lexical no-grow check

Inside the body of `b.with_ptr(fn(p) { ... })`, the parser rejects any of the following calls applied syntactically to `b` (the receiver of the `with_ptr` call):

- `b.push(_)`, `b.append(_)`, `b.concat(_)`, `b.extend(_)`
- `b.write_*_le(_)` / `b.write_*_be(_)` (the append-style writers)
- `b.clear()`, `b.truncate(_)`, `b.resize(_)`
- Any future method tagged `@bytes_grows` in the stdlib.

Diagnostic: `E0814: cannot grow Bytes inside with_ptr closure` with a caret on the offending call and a note pointing at the enclosing `with_ptr` site.

The check is **syntactic and conservative**: it does not walk into helper functions called from the closure body. Passing `b` as a `Bytes` argument to a function call inside the closure is rejected with `E0815: pinned Bytes cannot escape with_ptr closure as argument`. The user can pass `p` (the `Ptr[U8]`) or an integer slice instead.

The check accepts that helper-function bodies are out of scope. Documentation marks `with_ptr` as the FFI-only helper that, like Rust pinning, requires the user not to defeat the pin via reflection-style escapes; the audit category for `with_ptr` calls in `blink audit` makes the call sites easy to review.

#### Bytes Bridge Doctrine

User code is **forbidden** from constructing a `Ptr[U8]` that aliases a `Bytes`'s backing storage. Specifically:

- There is no `Bytes.as_ptr()` method.
- `scope.bind(b)` / `scope.pin(b)` are not in the API.
- Casting between `Ptr[U8]` and `Bytes` raises `E0817`.

The sanctioned paths for Bytes ↔ FFI interop are:

1. `Bytes.with_ptr(fn(p) { ... })` — closure-scoped, for use inside an FFI region only.
2. `libc.copy_to_buf(b: Bytes) -> Buf[U8]` — copies bytes into a freshly-allocated, scope-tied `Buf[U8]`. See §9.1.3.2 for the runtime representation, surface, and naming rules.
3. `libc.copy_from_buf(buf: Buf[U8]) -> Bytes` — copies bytes out of a `Buf[U8]` into a fresh `Bytes`. The byte count is read from the buffer's internal length field.
4. `libc.copy_from_buf_n(buf: Buf[U8], n: I64) -> Bytes` — truncating copy: copies up to `n` bytes (or fewer if the buffer is shorter) into a fresh `Bytes`. Used by syscalls whose return value reports the actual byte count (`read(2)`, `recv(2)`).

The copies are the soundness witness: bytes cross the firewall, addresses do not. The cost is one `memcpy` per call; high-throughput byte-payload bindings (`read`, `write`, `recv`, `send`) avoid it by using `with_ptr` directly.

##### Why the bridge is forbidden in user code

Two reasons. First, `Bytes.data` is `GC_MALLOC`/`GC_REALLOC`-managed (see `bootstrap/runtime_core.h:146-174`); a `Ptr[U8]` aliasing it is invalidated by any growth-effecting call on the source `Bytes`, and the panel rejected the alias analysis required to detect such a call across helper boundaries. Second, the language goal is preserving the moving-GC migration option as a future possibility — keeping `Ptr` and `Buf` from naming GC-managed memory in user code makes that migration mechanical rather than ABI-breaking.

##### 9.1.3.2 `Buf[T]` runtime representation

Resolves the v1 ambiguity in §9.1.3 about what `Buf` actually *is*. Decided by panel deliberation [`buf-u8-runtime-representation`](../decisions/buf-u8-runtime-representation.md).

**One generic type.** `Buf[T]` is a single generic nominal type, tagged to the enclosing `ffi.scope` by the same inferred scope tags as `Ptr[T]` (§9.1.1, *Scope tags*; `Buf[T]^σ` is meta-notation for that tag, not source syntax). The typechecker accepts any `T` at declaration sites in `@ffi.fn` signatures. There is no separate `Buf[U8]` sibling type.

**Bridge alphabet.** A spec-encoded, closed set of element types — `{U8}` in v1 — is permitted to flow through the byte-bridge primitives (`copy_to_buf`, `copy_from_buf`, `copy_from_buf_n`). Formally, `BridgeAlpha(λ)` is a function from the language version `λ` to a finite, spec-enumerated set of element types, with `BridgeAlpha(v1) = {U8}`. Membership is consulted **only** to decide whether `W0816` fires; it is *not* an instantiation gate — `Buf[T]` type-checks for every `T`, and the alphabet narrows nothing about the type, it governs only which `T` cross the byte-bridge primitives without a diagnostic.

Here "**language version**" denotes the compiler/spec revision reported by `blink --version` (the `blink 0.3.0` field of `blink 0.3.0 (stdlib 0.3.0)`), **not** the per-package `edition` (§8.16.1) and **not** package semver. The bridge alphabet is governed by three guarantees:

- **G1 — Language-version constant.** `BridgeAlpha` is a function of the language version alone. It does not depend on edition, package semver, stdlib version, compiler flag, environment variable, manifest field, or any link-time or runtime input. This is what makes `W0816` source-deterministic — a function of `(source, language version)` only (see also `W0816` below).
- **G2 — Expansion = deliberation + version bump.** Adding an element type to the bridge alphabet is a language-version change: it requires panel deliberation recorded in `DECISIONS.md` and ships only in a new compiler release that carries a language-version bump. Membership is monotonically non-shrinking across versions — once `T ∈ BridgeAlpha(λ)`, `T ∈ BridgeAlpha(λ')` for every later `λ' ≥ λ` — so every expansion is a conservative extension: an `@ffi` declaration that previously drew `W0816` only ever *loses* the warning on upgrade, never the reverse. Introducing any bridge-membership declaration form is itself such a change, never an incremental addition.
- **G3 — No third-party or link-time extension.** No third-party crate, stdlib helper, `@ffi` declaration, build script, edition, or linked object may add an element type to the alphabet. The set is closed **by construction**: Blink provides no surface syntax — no attribute, trait, keyword, manifest key, or registration API — by which membership could be declared. You cannot extend what has no extension point; this is a stronger guarantee than a rejection rule, and no diagnostic is reserved for an extension attempt (there is no construct to reject).

**Sealed user surface.** `Buf[T]` has no public methods. Specifically:

- No `.len()` (length lives in the runtime struct and is read by bridge primitives only).
- No `.as_ptr()`, `.read(i)`, `.write(i, v)`.
- No public constructors. The only way to obtain a `Buf` is `libc.copy_to_buf(b)`, which returns a `Buf[U8]` tagged to the innermost enclosing `ffi.scope`. `scope.alloc_n[T](n)` returns a `Ptr[T]`, not a `Buf` (§9.1.3; see [`ffi-scope-tag-inference`](../decisions/ffi-scope-tag-inference.md), which amends this section's original decision).

**Runtime representation.** A `Buf[T]` value is a pointer to a heap-allocated struct of the shape:

```c
typedef struct {
    void*  data;     /* malloc'd, sizeof(T) * len bytes */
    int64_t len;     /* element count, not byte count */
    int64_t cap;     /* element capacity */
} blink_buf_t;
```

The struct and its `data` payload are `malloc`'d (not GC-managed), registered with the enclosing `ffi.scope`, and freed in LIFO order on scope unwind. No finalizer is registered; lifetime is purely lexical.

**Nameability — the V3 carve-out.** Whether `Buf` can be named in source depends on the syntactic context:

| Context | Naming `Buf[T]` |
|---|---|
| `@ffi.fn` parameter and return types | **Legal** |
| `@ffi.struct` field types | **Error `E0822`** (use `Ptr[T]`; §9.1.3) |
| Inferred `let` binding (`let b = libc.copy_to_buf(bs)`) | **Legal** (the type is computed by the typechecker, never written) |
| Annotated `let` / `var` binding (`let b: Buf[U8] = ...`) | **Error `E0822`** |
| Function parameter or return type in user Blink code | **Error `E0822`** |
| Struct field type in user Blink code | **Error `E0822`** |
| Generic parameter bound | **Error `E0822`** |

`E0822` fires on user-authored references to the name `Buf` outside `@ffi.fn` signatures. Help text directs the user to `libc.recv_bytes` / `libc.read_bytes` / `libc.getentropy_bytes` (for byte-payload syscalls) or `scope.alloc_n[T]` (for typed regions).

**Source-deterministic warning `W0816`.** When a `Buf[T]` appears in an `@ffi.fn` signature for a `T` outside the bridge alphabet, the compiler emits:

```
W0816: Buf[i32] declared in @ffi.fn signature; only Buf[U8] crosses the
       byte bridge in this version of Blink. The bridge alphabet is fixed
       by the compiler version and cannot be extended by a package, stdlib
       helper, edition, or build flag. For a typed scope-tied region use
       `scope.alloc_n[i32](n)` instead. See `blink doc bytes-bridge`.
```

`W0816` is **source-deterministic**: it depends only on `(source, language version)`, not on stdlib version, edition, or package semver. The bridge alphabet is the language-version-encoded set `BridgeAlpha(λ)` (§9.1.3.2 G1); stdlib helpers do not influence the warning. The message is self-contained and edition-invariant — it names the working path (`scope.alloc_n[T]`) inline and never says "wait for v2," because `scope.alloc_n[T]` is the answer indefinitely.

`W0816` is per-declaration suppressible with `@allow(W0816)`. Suppression at a binding-author's discretion is expected for vendored bindings that intentionally use a non-`U8` element type for typed-region work.

**Curated `libc.*_bytes` helpers — the primary user-facing API.** Most user code never names `Buf`. The recommended path is:

```blink
let bs = libc.recv_bytes(fd, 4096)?       // recv up to 4096 bytes from a socket
let entropy = libc.getentropy_bytes(32)?  // 32 CSPRNG bytes, no fd, no Buf, no scope
let chunk = libc.read_bytes(fd, 8192)?    // read up to 8192 bytes from any fd
libc.write_bytes(out_fd, chunk)?          // write raw bytes to a file/pipe/socket fd
```

These wrappers do **not** use the byte-bridge primitives. They are built on `Bytes.with_ptr` (§9.1.1, the sanctioned `Bytes → Ptr[U8]` borrow): a read pins a `Bytes.zeroed(n)` buffer to receive into and returns `buf.slice(0, got)`; a write pins the caller's `Bytes` read-only and hands C a `const uint8_t*`. `copy_to_buf` / `copy_from_buf` / `copy_from_buf_n` are reserved **exclusively** for the sealed-`Buf` path (where the user can never name `Buf`); the curated wrappers never call them. The boundary is *user-owned `Bytes` (→ `with_ptr`)* vs *unnameable sealed `Buf` (→ bridge primitives)*, not reads-vs-writes.

##### 9.1.3.3 The v1 `libc.*_bytes` minimum set (A2 ship gate)

Decided by panel deliberation [`libc-bytes-wrapper-coverage`](../decisions/libc-bytes-wrapper-coverage.md). Resolves the A2 ship gate flagged in §9.1.3.2 — the `libc.*_bytes` family is the primary user-facing surface, so v1 must ship a coherent minimum set or users are stranded at the sealed bridge with no power-user fallback.

**The ratified v1 set is exactly these five wrappers** (the four base-shape direction × domain quadrants — file/socket × read/write — plus the standalone CSPRNG fill):

```blink
fn read_bytes(fd: Int, max: Int) -> Result[Bytes, Errno] ! IO
fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO
fn write_bytes(fd: Int, data: Bytes) -> Result[Int, Errno] ! IO
fn send_bytes(fd: Int, data: Bytes, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Int, Errno] ! IO
fn getentropy_bytes(n: Int) -> Result[Bytes, Errno] ! IO
```

Each member ships at v1; the set **blocks the v1 release**.

**Directional return-typing rule (normative).** The actual byte count is always carried *in the return type*, never out-of-band:

- **Bytes-out** (`read_bytes`, `recv_bytes`, `getentropy_bytes`) → `Result[Bytes, Errno]`, where the returned `Bytes.len()` *is* the syscall's reported count (`slice(0, got)`). A short read is success with a shorter `Bytes`; only a `-1`/errno return is `Err`. `getentropy_bytes` is all-or-nothing (`.len() == n` on success, no truncation arm).
- **Bytes-in** (`write_bytes`, `send_bytes`) → `Result[Int, Errno]`, where the `Int` is the count actually written. Short writes are normal and surfaced as `Ok(n < data.len())` — the caller must loop; collapsing this to `Result[(), Errno]` would be unsound for the partial-write contract.

**`recv_bytes` / `send_bytes` take `flags` as a trailing keyword argument** of type `MsgFlags` (§9.1.3.4), with the default `MsgFlags.NONE`. A call that omits `flags` behaves as `flags = 0`, so the examples above do not change. The keyword is part of the v1 signature: labels are call-site sugar, so adding the parameter after v1 would change the function-value type. No separate flagged name (such as `recv_flags_bytes`) exists or will be added.

**Error type.** Every member returns `Result[_, Errno]`, where `Errno` is a newtype over the OS errno `Int`: a single-variant enum, `type Errno { Errno(Int) }`, nominally distinct from `Int` (§3). It carries a name/projection (`.code() -> Int`, named errno constants) so callers match on errno meaningfully rather than on a bare `Int`, and so a `write`'s two return arms (count-written vs errno) are nominally distinct. A rich variant `IoError` hierarchy is **not** part of this gate — it is a separate post-v1 task, layered additively on `Errno` (e.g. `.kind()`) without changing any wrapper signature. `Errno` is domain-neutral; a file read's `ENOSPC` is *not* typed as a network error.

**Naming law (normative).** Every `libc` byte-moving syscall wrapper conforms to a fixed shape, so the family is name-predictable and post-v1 additions are mechanical rather than designed:

- **Name** = `libc.<posix_syscall_name>_bytes` (e.g. `recvfrom` → `recvfrom_bytes`, never `recv_from_bytes`).
- **Arguments** = POSIX C argument order. The `(void* buf, size_t len)` pair is replaced in place by `max: Int` (reads) or `data: Bytes` (writes; length is `data.len()`, never passed explicitly). `flags` is always the trailing keyword `-- flags: MsgFlags = MsgFlags.NONE`, exempt from C order.
- **Return** = `Result[Bytes, Errno]` (Bytes-out) or `Result[Int, Errno]` (Bytes-in), bound to direction — a write may not be typed `Result[Bytes, Errno]`. A non-buffer out-parameter moves into the success value as a tuple after the `Bytes` or count, in C order. A pointer-typed out-parameter that may be empty is `Option` (e.g. `recvfrom_bytes` → `Result[(Bytes, Option[SockAddr]), Errno]`).
- **Effect** = `! IO`.
- **Mechanism** = `Bytes.with_ptr`, never the byte-bridge primitives.

The law governs only the *shape* of a wrapper; it is not a license to auto-add wrappers (see growth governance below). `getentropy_bytes` is the one principled exception to the arg rule (no fd, no `(buf, len)` pair) — it takes `n: Int` and fills exactly `n`. Syscalls that cannot conform — vectored I/O (`readv`/`writev`, which need an `iovec[]` array), `recvmsg`/`sendmsg` (`msghdr`), or any surface requiring a non-`Bytes` buffer shape — are **out of scope of the law** and must not be forced into a `*_bytes` wrapper; they get their own deliberated API.

**Deferred, with the reason recorded** (so the line is defensible, not arbitrary):

- ~~`recvfrom_bytes` / `sendto_bytes`~~ — **resolved** by the UDP gate (§9.1.3.4), which adds `SockAddr` and a `std.net` datagram caller.
- `pread_bytes` / `pwrite_bytes` — positional variants add only an `off_t` argument over `read`/`write` (same buffer-fill shape, no new crossing) and have no demonstrated v1 caller. They ship under the demonstrated-demand gate.
- `readv_bytes` / `writev_bytes` — vectored I/O needs an `iovec[]` bridge that has not been designed and is excluded by the naming law.

**Growth governance.** A `libc.*_bytes` wrapper is added beyond the v1 set only on **demonstrated high-frequency Bytes-in/Bytes-out usage where the allocate-before-call asymmetry makes `scope.alloc_n[T]` ergonomically prohibitive** — never as a default for every `uint8_t*` C function, and never speculatively ahead of a real caller. Any addition must conform to the naming law above.

**`read_fully_bytes` is not a `libc` member.** Reading exactly `n` bytes (looping over `read_bytes` until `n` or EOF) is a derived combinator with no syscall and no bridge crossing of its own; it lives in `std.io` as ordinary Blink (`std.io.read_fully`), preserving the "`libc.*` is exactly one syscall, 1:1" invariant that keeps the `libc` surface auditable. It ships at v1 (a hard, gate-coupled deliverable — `read_bytes` alone is a short-read footgun), and the `read_bytes` doc/hover **must** cross-reference it: "`read_bytes` may return fewer than `max`; for read-until-`n` use `std.io.read_fully`."

**Audit category.** `blink audit` reports a `bytes-bridge` category with three subcategories:

- `bridge-call` — call sites of `copy_to_buf` / `copy_from_buf` / `copy_from_buf_n` (the sealed-`Buf` path).
- `buf-mention` — any source mention of `Buf` (legally, inside `@ffi.fn` signatures).
- `byte-pin` — `Bytes.with_ptr` call sites (the `libc.*_bytes` family's crossings, both read-side and write-side pins).

A single `blink audit bytes-bridge` query therefore returns *every* raw-byte crossing in a module — sealed-`Buf` copies and `with_ptr` pins alike — with no direction asymmetry. CI may use `blink build --no-unaudited-bridges` to require every `bytes-bridge` subcategory entry outside `lib/std/` to be approved by `blink audit approve`.

A curated `*_bytes` wrapper **must keep its `@ffi` syscall call inline inside the `with_ptr` closure body** — the closure-lexical no-grow / no-escape check (§9.1.3.1) is syntactic and does not descend into helper functions, so factoring the call out would defeat the `E0814`/`E0815`/`E0817` pin guarantees.

**Doc / LSP.** `blink doc` and the LSP hover for `Buf[T]` render a fixed banner, followed by the value's tag as `(scope: name)` when hovering a value:

> **Opaque, scope-tied, bridge-only.** Bridge alphabet (v1): `{U8}`.
> `Buf[T]` is a buffer freed with its `ffi.scope`, used by FFI bridge primitives.
> User code should prefer `libc.*_bytes` helpers; for typed regions, use `scope.alloc_n[T]`.
> See `blink doc bytes-bridge`.

The `bytes-bridge` doc page (`blink doc bytes-bridge`) is the single canonical explainer for the byte bridge, and the `W0816` and `E0822` diagnostic explain-texts both deep-link it. It answers, in order: (1) most code never names `Buf` — use `libc.recv_bytes` / `read_bytes` / `getentropy_bytes`; (2) `Buf` is bridge-only and `U8`-only, fixed by the compiler version; (3) for a typed region use `scope.alloc_n[T]`.

**Machine-queryable alphabet — one constant, three projections.** The bridge alphabet exists as exactly one normative source: a compile-time constant in the compiler (the same constant `W0816` consults). Every reporting surface is a projection of that constant, never an independently-maintained list. A build-time test asserts each surface equals the constant the typechecker reads, so they cannot drift on a future expansion:

1. **`blink --version --json`** — the normative machine surface, for CI and humans:

   ```json
   {
     "compiler": "0.3.0",
     "stdlib": "0.3.0",
     "bridge_alphabet": ["U8"],
     "bridge_alphabet_extensible": false
   }
   ```

   A CI pipeline pins the alphabet in one line — `blink --version --json | jq -e '.bridge_alphabet == ["U8"]'` — and fails the build if a toolchain upgrade ever silently widened it.

2. **`llms.txt` `language:` stanza** — a derived view for AI agents reading the offline doc bundle (§8.16.4), so a tool generating an `@ffi.fn` knows which `T` are bridge-legal without trial-and-error:

   ```
   language:
     bridge_alphabet: [U8]              # T legal in Buf[T] through byte-bridge primitives
     bridge_alphabet_extensible: false
     bridge_diag: W0816                 # fires on any other T in @ffi.fn/@ffi.struct
   ```

3. **`W0816` firing set + help text** — the at-the-caret surface for the binding author.

##### 9.1.3.4 The UDP gate: `recvfrom_bytes`, `sendto_bytes`, and `MsgFlags`

Decided by panel deliberation [`udp-gate-sockaddr-flags`](../decisions/udp-gate-sockaddr-flags.md). Resolves the UDP gate that §9.1.3.3 deferred. The `std.net` caller and the `SockAddr` type are specified in §4.4.6.

```blink
fn recvfrom_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[(Bytes, Option[SockAddr]), Errno] ! IO
fn sendto_bytes(fd: Int, data: Bytes, dest: SockAddr, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Int, Errno] ! IO
```

Both follow the naming law of §9.1.3.3: the peer address is a non-buffer out-parameter, so it follows the `Bytes` in the success tuple, and it is `Option` because the kernel may return no address.

**`MsgFlags` (normative).** `MsgFlags` is the type of the `flags` argument of `recv_bytes`, `send_bytes`, `recvfrom_bytes` and `sendto_bytes`. It is an opaque type: it has no public constructor and no public field.

- The only values are the named constants. This gate ratifies two: `MsgFlags.NONE` (no flags) and `MsgFlags.PEEK` (read a datagram without removing it from the queue). Each is a const expression (§2.21), so it is legal as a keyword default.
- The bits inside `MsgFlags` use **Blink's** numbering, not the platform's. The runtime translates each Blink bit to the native `MSG_*` value from the C headers. A named constant has the same meaning on every platform.
- The wrapper checks the bits before the syscall. A bit that is not a ratified constant returns `Err(Errno(ERR_INVAL))` on every platform, and the syscall does not run. A native value never reaches the kernel as a native flag.
- `MsgFlags` has no `|` operator yet. The bit-or implementation ships with the second ratified constant that can combine with `PEEK`.
- New constants (for example `DONTWAIT`, `WAITALL`) are added under the growth gate of §9.1.3.3. Each addition is one constant plus one row in the runtime translation table, and it does not change the meaning of any existing call.
- User code cannot write `MsgFlags(n)` or `MsgFlags { bits: n }`; either is a compile error. A general rule for fields that are private to their module does not exist yet. Until it does, `MsgFlags` is opaque by compiler knowledge, in the same way as `Instant` (§3).

```blink
let head = libc.recv_bytes(fd, 16, flags: MsgFlags.PEEK)?   // peek at the header
let (pkt, peer) = libc.recvfrom_bytes(fd, 1500)?            // peer: Option[SockAddr]
libc.recv_bytes(fd, 16, flags: 0x40)                        // error: expected MsgFlags, found Int
```

**Datagram semantics (normative).**

- The returned `Bytes.len()` is `min(rc, max)`, where `rc` is the count the syscall returned. This also holds when a platform reports the full datagram length (Linux `MSG_TRUNC`).
- A 0-length result from `recvfrom_bytes` is an empty datagram, not end-of-file.
- A datagram larger than `max` is truncated without an error. Code that must detect truncation uses a larger `max`; `recvmsg` stays out of the scope of the naming law.
- The peer is `None` when the kernel returns no address, or returns an address of a family that `SockAddr` does not model (for example `AF_UNIX`). `None` is not an error.
- `sendto_bytes` encodes `dest` into a C `sockaddr_in` or `sockaddr_in6` inside the runtime. `SockAddr` never crosses as a C struct.
- These wrappers have the effect `! IO`, the same as every `libc.*_bytes` member. They are not subject to `Net` attenuation (§4.3). The `byte-pin` audit category reports them.

#### Static layout assertions

For every `@ffi.struct` declaration, the codegen emits, into the generated C immediately after the corresponding `typedef`:

```c
_Static_assert(sizeof(blink_pollfd) == sizeof(struct pollfd),
               "blink_pollfd size mismatch with C struct pollfd");
_Static_assert(offsetof(blink_pollfd, fd) == offsetof(struct pollfd, fd),
               "blink_pollfd.fd offset mismatch");
_Static_assert(offsetof(blink_pollfd, events) == offsetof(struct pollfd, events),
               "blink_pollfd.events offset mismatch");
/* ... one per field ... */
```

The C compiler is the authoritative oracle for the C ABI. If the headers used at user-build time differ from the layout encoded in the `@ffi.struct` declaration (libc version bump, cross-compile platform mismatch, BSD vs glibc), the C compiler emits a static-assert failure with file and line, and the Blink build fails before linking.

The static-assert codegen requires `[native-dependencies].headers` to point at the canonical headers:

```toml
[native-dependencies]
poll = { system = true, headers = ["poll.h"] }
```

When `[native-dependencies].headers` is missing, the compiler emits `W0812: @ffi.struct declared without canonical header — layout drift will not be detected`. Under `--strict-struct-layout` (default-on for `@ffi` modules), W0812 is escalated to an error.

#### γ-doctrine: curated `std.libc.*` is the recommended path

User code should reach for stdlib first:

- `std.libc.poll(fds: List[Pollfd], timeout_ms: Int) -> Result[List[Pollfd], Str] ! IO`
- `std.libc.recvfrom_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[(Bytes, Option[SockAddr]), Errno] ! IO`
- `std.libc.sigaction(...)` — etc.

`@ffi.struct` is the implementation primitive used inside `std.libc.*`. User-defined `@ffi.struct` outside stdlib is **discouraged but not banned**. `blink audit` reports a `user-defined @ffi.struct count` metric per project. If, within 12 months of v1 ship, the registry shows >50 distinct user-defined `@ffi.struct` types across third-party projects (or 5+ projects vendoring functionally-equivalent `@ffi.struct` declarations for the same syscall family), the panel reconvenes to consider stdlib expansion of `std.libc.*` to absorb them.

For C surfaces β cannot reach (varargs, signal handlers, glibc-version-conditional dispatch, packed structs, bitfields, unions, alignment overrides), `blink shim init` scaffolds a vendored C source file plus the `[native-dependencies]` registration plus the `@trusted` wrapper template. This is the third tier — used after `std.libc.*` and `@ffi.struct` are both inadequate.

#### Diagnostic codes added by §9.1.3

| Code | Class | Meaning |
|------|-------|---------|
| `E0812` | error | `@ffi.struct` field uses GC-managed type |
| `E0813` | error | `offset(i)` called on singleton `alloc[T]()` result |
| `E0814` | error | growth-effecting call on `Bytes` inside its `with_ptr` closure body |
| `E0815` | error | pinned `Bytes` passed as argument inside `with_ptr` closure body |
| `E0817` | error | `Bytes` ↔ `Ptr[U8]` cast or `as_ptr` use in user code (use `with_ptr`, `libc.copy_to_buf`, or `libc.copy_from_buf`) |
| `E0822` | error | `Buf` named in user Blink-typed code outside `@ffi.fn` signatures, including as an `@ffi.struct` field type (§9.1.3, §9.1.3.2) |
| `W0812` | warning | `@ffi.struct` declared without canonical header in `[native-dependencies].headers`; escalated to error under `--strict-struct-layout` (default-on for `@ffi` modules) |
| `W0816` | warning | `Buf[T]` declared in an `@ffi.fn` signature for `T` outside the v1 bridge alphabet `{U8}`; redirects to `scope.alloc_n[T]` (§9.1.3.2). Per-decl suppressible with `@allow(W0816)`. |

`E0601` (existing) gains two sub-kinds for the scope-tag interactions raised by `Ptr` aliasing across `ffi.scope` boundaries. Both are defined by the inferred scope tags of §9.1.1, *Scope tags*:

- `E0601 (value-escape)`: a `Ptr[T]` value escapes its allocating `ffi.scope`.
- `E0601 (tag-mismatch)`: a scope-tagged Ptr/Buf stored, by write, capture, effect argument, or a call beside a pointer-holding argument, into a cell whose scope it does not enclose. (A value of any pointer-bearing type counts as a Ptr here.)

Diagnostic codes `W0811` (init-flow analysis), `W0813` (zero-len Buf), and `E0818` (endian-tag tracking) considered during deliberation are **not** shipped — see decision rationale.

### 9.1.4 Opaque FFI handle types (`@ffi.opaque`)

Section 9.1.1 gives `Ptr[Void]` for opaque C pointers, and §9.1.3 gives `@ffi.struct` for C records whose layout is fully known. Neither models a handle whose C type is **incomplete on the Blink side** — `sqlite3*`, `sqlite3_stmt*`, a `FILE*`, an OpenSSL `SSL_CTX*` — that must also **flow through ordinary non-FFI Blink code** (struct fields, wrapper functions, bindings). `Ptr[Void]` cannot: it is E0811-gated so it may not leave an `@ffi`/`@trusted` context, and it is non-nominal — every opaque handle collapses to the one type `Ptr[Void]`, so `sqlite3*` and `sqlite3_stmt*` become interchangeable. `@ffi.struct` cannot: an incomplete C type has no layout to mirror. This subsection is the resolution of that gap, decided by panel deliberation [`opaque-ffi-handles`](../decisions/opaque-ffi-handles.md) (6-0).

#### `@ffi.opaque` — declaring an opaque C handle

```blink
@ffi.opaque(header = "sqlite3.h", name = "sqlite3")
type Sqlite3

@ffi.opaque(header = "sqlite3.h", name = "sqlite3_stmt")
type Sqlite3Stmt
```

`@ffi.opaque(header, name)` declares a **bare nominal, arity-0** handle type that mirrors a named, possibly-incomplete C type. The type has **no body** — no fields, no variants (a body is rejected). `header` is resolved against `[native-dependencies].headers` exactly as for `@ffi.struct` (§9.1.3). `name` is the C type the handle points at; the Blink type lowers to `name *` — one machine word. Because the pointee is incomplete, **no `sizeof`/`offsetof` `_Static_assert` is emitted** (the deliberate contrast with `@ffi.struct`, whose whole purpose is a known layout).

Each `@ffi.opaque` declaration is its own **nominal type**. `Sqlite3` and `Sqlite3Stmt` are distinct and never interchangeable, even though both lower to a C pointer — the nominal distinctness `Ptr[Void]` could not provide.

#### Flows freely in non-FFI code — containment stays syntactic

An `@ffi.opaque` type **is not a `Ptr[T]`**, so E0811 (`PtrOutsideFFI`) never applies to it. It flows through ordinary Blink code like any nominal type — struct fields, function parameters and returns, `let` bindings — with no `@trusted` and no capability gate:

```blink
pub type Connection {
    db: Sqlite3,
}

// ordinary Blink code — no @ffi, no @trusted: `Sqlite3` is not a `Ptr`
pub fn table_count(conn: Connection) -> Int {
    count_tables(conn.db)   // holds and passes the handle freely
}
```

This does **not** relax E0811. The rule is unchanged — "a `Ptr[T]` may appear only inside an `@ffi`/`@trusted` context" — and remains statable purely syntactically. An opaque handle is simply not a `Ptr[T]`; its E0811-exemption is *by construction of a distinct declared type*, not a carve-out in the gate. (The rejected alternative — narrowing E0811 to exempt `Ptr[Void]` itself — would have kept the raw-pointer surface `.addr()`/`==` reachable from non-FFI code and left every handle collapsed to one type; see the decision rationale.)

#### Inert — no operations

An `@ffi.opaque` type has **no methods and no operations**. There is no `.deref()`, `.addr()`, `.offset()`, field access, arithmetic, or `==`. The only things you can do with a handle are hold it, pass it, return it, and store it in a field. It carries no readable value — its C type is incomplete. A method access is rejected by the ordinary "no method on `<Type>`" diagnostic; a field access is rejected by the general field-existence diagnostic E0525 (`NoSuchField`), because an opaque handle is a bodiless nominal type that declares zero fields, so every field access on it is provably absent from its declared shape. Neither diagnostic is dedicated to opaque handles — both are the ordinary nominal-type machinery applied to a type with no members. This inertness is **permanent and by construction**: the handle exposes zero raw-pointer surface to non-FFI code, which is exactly why it is safer than a `Ptr[Void]` in the wild.

#### Nullability — `Option[T]`, with guaranteed null-pointer optimization

An `@ffi.opaque` handle is **non-null by the FFI-boundary contract**. Absence is modeled **only** by `Option[Sqlite3]`, and only where a C API makes NULL an observed outcome (a constructor or lookup that can fail) — the "Option must be earned" principle (§9.1.1, *Nullability*). Unlike `Ptr[T]`, an opaque handle has **no `.is_null()`** and **no null sentinel** (`null_opaque` / `Opaque[T]?` were considered and rejected as a second null channel). `Option` is the sole absence channel.

**Null-pointer optimization is guaranteed, not best-effort.** `Option[Sqlite3]` is represented as a single machine word: the C `NULL` pointer *is* the `None` niche, and a present handle is the non-null pointer. A nullable handle therefore costs exactly one word and one comparison — never a tagged struct. This guarantee holds for every `@ffi.opaque` type because the compiler knows the representation is a pointer whose null value is unused.

#### Construction — sealed to the FFI boundary

A handle value can be produced **only at the FFI boundary**: as the return value of an `@ffi` function, or by reading one out of a `Ptr` cell wherever a `Ptr[T]` may legally appear — an **FFI region** in the sense of E0811 (§9.1.1, *Pointer Operations* — an `@ffi`/`@trusted` body or a `with ffi.scope() as _ { }` block). The mint boundary is exactly that region set: it is not restated here, so the two cannot drift. There is no literal and no user-callable constructor; constructing or coercing an `@ffi.opaque` value from ordinary Blink code is rejected by the existing construction / type-mismatch diagnostics (no new error code). `Ptr[Sqlite3]` is a legal FFI inner type (it lowers to `sqlite3 **`, the standard out-parameter shape), so a handle is minted by dereferencing the out-cell at the boundary:

```blink
// raw FFI binding — private, audited
@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
fn raw_sqlite3_open(path: Ptr[U8], out: Ptr[Sqlite3]) -> Int ! IO

// safe wrapper — mints the opaque handle at the boundary
pub fn open(path: Str) -> Option[Connection] ! IO {
    with ffi.scope() as scope {
        let out = scope.alloc[Sqlite3]()          // Ptr[Sqlite3] out-cell — a sqlite3**
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, out)
        if rc != 0 { return None }
        Some(Connection { db: out.deref() })      // Ptr[Sqlite3].deref() -> Sqlite3, at the boundary
    }
}
```

`out.deref()` returns a bare `Sqlite3` (deref on a non-`Void` pointer is legal — E0825 rejects only `Ptr[Void]`, §9.1.1). Round-tripping a handle *back* to a raw pointer to hand to another C call is likewise confined to an FFI region (E0811, §9.1.1): you store the handle into a `Ptr` cell with `.write(h)`, and the C call takes the cell. The `.write` is the crossing. The C call that then takes the cell is an ordinary consume, which the declaration's audit record already covers. Because the handle has no `.addr()` in ordinary code, it cannot be fabricated or re-crossed outside the boundary.

#### Audit category `opaque-ffi-handle`

Every boundary crossing that produces or consumes an opaque handle is tagged with the `blink audit` category **`opaque-ffi-handle`**, so the FFI inventory (§9.1, *`blink audit`*) lists them alongside pointer allocations and `Raw()` sites. The audit records two kinds of crossing.

**Declaration records.** For each `@ffi` declaration, a parameter whose type is `H` or `Option[H]` is a **consume** crossing, and an opaque return type or a `Ptr` out-cell parameter whose pointee contains `H` (defined below) is a **produce** crossing. The audit records these once per declaration, not once per call. Passing a handle by value to an `@ffi` function is therefore not a body site: the handle is the C pointer, so nothing goes back to raw memory, and the call may sit in ordinary code.

**Body sites.** Inside an FFI region (§9.1.1, *Pointer Operations*), and only there:

- a **mint** (direction `produce`) is a `.deref()` or `.read()` that loads a value whose type is or contains an `@ffi.opaque` type `H`;
- a **round-trip** (direction `consume`) is a `.write(v)` that stores such a value.

A type **contains** `H` when it is `H`, `Option[H]`, or an `@ffi.struct` with a field whose type contains `H`, at any depth. Type aliases resolve first. The walk stops at `Ptr`: a `Ptr[H]` is a pointer, not a handle, so loading one is not a mint. The form of the receiver does not matter. A binder, a field projection `p.field`, an `.offset(i)` element, an index, a call result, and a `match` or `for` binder all count. A site that loads or stores more than one handle type gets one tag for each distinct `H`. (Today only the `H` case can occur: `Ptr[Option[H]]` is not a valid `Ptr` type (E0810, §9.1.1), and §9.1.3 does not allow an `@ffi.opaque` field in an `@ffi.struct`. The rule names the `Option` and struct cases so that a later change to those rules cannot open a gap in the audit.)

```blink
@ffi.opaque(header: "stdio.h", name: "FILE")
type CFile

@ffi("shim", "register_stream")
@trusted(audit: "P-2")
fn c_register(cell: Ptr[CFile]) -> Int ! IO   // declaration record: produce (out-cell)

pub fn hand_back(h: CFile) -> CFile ! IO {
    with ffi.scope() as scope {
        let cell = scope.alloc[CFile]()
        cell.write(h)             // round-trip: CFile stored into raw memory
        c_register(cell)          // no body tag: the declaration record covers it
        cell.deref()              // mint: CFile loaded from raw memory
    }
}
```

**Completeness.** The audit and E0811 share one region predicate, which is syntactic (§9.1.1). Whether a site loads or stores a handle is a type question, so the audit classifies each site from its checked type, not from the shape of the code. `blink audit` therefore typechecks the program first. If the program does not typecheck, the audit prints the type errors, says that it needs a program that typechecks, and exits non-zero; it does not print a partial inventory. The contract is exact: for every program that compiles, the audit tags every mint and round-trip site exactly once for each handle type, and tags nothing else. Because E0811 also covers function bodies (§9.1.1), no such site can compile outside a region, so none can slip the audit.

#### Choosing among the three FFI type mechanisms

| Mechanism | C shape | Flows in non-FFI code? | Nominal identity | Layout known |
|-----------|---------|------------------------|------------------|--------------|
| `Ptr[Void]` (§9.1.1) | `void *` | No — E0811-gated | No — all collapse to one type | n/a (opaque) |
| `@ffi.struct` (§9.1.3) | complete `struct` | via `Ptr[T]`, E0811-gated | Yes | Yes (`sizeof`/`offsetof` asserted) |
| `@ffi.opaque` (§9.1.4) | incomplete type, held as `T *` | **Yes** — not a `Ptr` | **Yes** — one per declaration | No — incomplete by design |

Use `@ffi.opaque` for a named handle whose innards C hides from you and that your Blink code must carry around; use `@ffi.struct` when you own the layout and read fields; drop to `Ptr[Void]` only for a fully anonymous pointer that never leaves the `@ffi` region.

#### Diagnostic codes added by §9.1.4

**None.** This is a deliberate design point: an opaque handle reuses the ordinary nominal-type machinery end to end. A bad method access reuses the existing "no method on `<Type>`" and a bad field access reuses the general field-existence diagnostic E0525 (`NoSuchField`) — a bodiless handle declares zero fields — neither of which is opaque-specific; construction outside the boundary reuses the existing construction / type-mismatch diagnostics; a malformed `@ffi.opaque` declaration (a body, or a missing `header`/`name`) reuses the existing malformed-annotation diagnostics. The only new artifact is the `blink audit` category `opaque-ffi-handle`. A dedicated code (`E0826`, *opaque handle constructed outside FFI*) was considered for the boundary-construction violation and deferred — the existing diagnostics carry the message, and adding a code remains available to the implementation if the reused error proves unclear in practice.

### 9.2 System Boundary — Runtime Validation

Inside Blink, contracts (`@requires`, `@ensures`) are verified statically by the SMT solver wherever possible. But at the edges of the system — HTTP handlers, CLI entry points, message consumers, gRPC endpoints — input arrives from the outside world. External input cannot satisfy `@requires` statically because the compiler has no control over what a client sends.

The compiler detects system boundary functions and **automatically inserts runtime validation** at these points. This is the one place where runtime contract checking is implicit rather than opt-in.

```blink
@requires(id > 0)
@requires(email.len() > 0)
pub fn create_user(id: Int, email: Str) -> Result[User, ValidationError] ! DB {
    // Inside here, id > 0 and email.len() > 0 are guaranteed
    // ...
}

// When called from an HTTP handler, the compiler inserts runtime checks:
pub fn handle_create_user(req: Request) -> Response ! IO, DB {
    let id = req.param("id").parse_int()?
    let email = req.param("email")?
    // Compiler inserts: runtime check that id > 0 and email.len() > 0
    // Violation returns a structured 400 error, not a panic
    let user = create_user(id, email)?
    Response.json(user)
}
```

How the compiler identifies system boundaries:

1. **HTTP handlers** — functions passed to `server.route()`, `server.get()`, `server.post()`, etc. (§4.4.2). The compiler marks these as boundary entry points at route registration time.
2. **`fn main()`** — the program entry point, when it processes `env.args()`
3. **Message consumers** — functions bound to queue/topic handlers via the messaging effect
4. **gRPC/RPC handlers** — functions exposed as service methods

At these boundaries, `@requires` violations are routed through the `Validation` effect (§4.4.2). The compiler generates `validation.contract_violation(param, constraint, value)` calls instead of panics. The default `Validation` handler returns a structured 400 JSON response:

```json
{
    "error": "validation_failed",
    "violations": [
        { "param": "id", "constraint": "id > 0", "value": "-1" }
    ]
}
```

Users can swap the validation handler via `with custom_handler { server.serve() }` to customize the response format (422, JSON:API, localized messages) without modifying handler code.

For internal function calls (Blink calling Blink), the compiler still attempts static proof. If it can prove the caller always satisfies the callee's `@requires`, no runtime check is emitted. If it cannot prove it, a warning is emitted and a runtime assertion is inserted — same as the standard contract behavior described in the contracts section.

### 9.3 Injection Safety — `Template[C]` Parameterized Queries

**Status: v1. Resolved by unanimous panel vote (3-0).**

Blink's universal string interpolation creates an injection risk when interpolated strings flow to databases, shells, or HTML renderers. The `Template[C]` type solves this at the type boundary without taint tracking.

**v1 mechanism:** Effect handle methods that execute interpreted strings accept `Template[C]` instead of `Str`. When an interpolated string literal appears where `Template[C]` is expected, the compiler decomposes it into literal parts and typed values — `{expr}` becomes a value the handler binds as a parameter, not string concatenation (§3b.5).

```blink
// Developer writes this — identical to a normal interpolated string:
fn get_user(id: Int) -> User? ! DB.Read {
    db.query_one("SELECT * FROM users WHERE id = {id}")
    // The handler receives parts ["SELECT * FROM users WHERE id = ", ""] and values [TemplateValue.Int(id)]
}

// Str → Template is a compile error:
let q: Str = "SELECT * FROM users WHERE id = {id}"
db.query_one(q)  // ERROR: expected Template[DB], got Str
```

**Escape hatch:** `Raw(expr)` constructs a value of the marker type `Raw[T]`, which bypasses parameterization for a single interpolated expression within a `Template[C]` string. Folding a `Raw[T]` into a template raises `RawBypassesParam`, an audit-gated warning: `@trusted(audit: K)` is its only suppression channel (see §9.1, *Audit-Gated Diagnostics*). See §3b.5 for the type rules.

```blink
// Auditable escape hatch for dynamic SQL:
db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
// WARNING: Raw() bypasses parameterization for {Raw(table)}
// Note: {id} is still safely parameterized
```

**Extensibility:** The phantom type `C` in `Template[C]` enables the same mechanism for shell commands (`Template[Shell]`), HTML templates (`Template[HTML]`), and other injection contexts. See section 3.12 for the full type specification.

See [DECISIONS.md](../DECISIONS.md) for the full deliberation record.

### 9.4 Information Flow Tracking (v2+ Roadmap)

**Status: v2+ roadmap. Deferred — `Template[C]` covers 95% of injection cases for v1.**

The eventual goal is taint tracking via effect provenance. Values originating from certain effects would carry their provenance through the program, and the compiler would enforce sanitization policies:

```blink
// FUTURE SYNTAX — not finalized
fn handle_query(req: Request) -> Response ! IO, DB {
    let user_input = req.param("q")           // tainted: Net.Read
    // let results = db.query(user_input)      // ERROR: Net.Read value flows to DB.Write
    let sanitized = sql.escape(user_input)     // sanitized: taint cleared
    let results = db.query(sanitized)          // OK
    Response.json(results)
}
```

This requires tracking effect provenance on values — a significant type system extension that interacts with inference, generics, and the effect system. The design challenges:

- **Type inference interaction** — taint labels on values multiply the type space. Inference must track provenance without requiring manual annotation everywhere.
- **Performance** — provenance tracking must not impose runtime cost in production builds. It should be a compile-time-only analysis.
- **Granularity** — which effects produce tainted values? All of them? Only `Net`? Configurable per project?

This is deferred to v2+. The `Template[C]` mechanism in v1 covers the most critical injection cases (SQL, shell, HTML) at the type boundary. Full information flow tracking would catch additional categories (reflected XSS through non-handle paths, data flow between unrelated effects) but at significantly higher implementation cost.

---

## 10. Module System

This section resolves open questions 10.1 (module mapping), 10.3 (visibility), and partially 10.8 (FFI, covered in section 9).

### 10.1 File = Module, Directory = Package

A Blink source file is a module. A directory containing Blink files is a package. No ceremony required.

```
myapp/
  blink.toml           # project manifest
  src/
    main.bl          # module: main (entry point)
    auth/
      login.bl       # module: auth.login
      token.bl       # module: auth.token
      rate_limit.bl  # module: auth.rate_limit
    db/
      connection.bl  # module: db.connection
      queries.bl     # module: db.queries
```

The module name is derived from the file path relative to `src/`. The directory structure IS the package hierarchy. There is no `mod.bl` index file, no `__init__` file, no module declarations in a parent file.

**Why file = module:** Go proved this works at scale. One file, one module, one namespace. No indirection. An AI agent looking at `auth/login.bl` knows immediately that it's the `auth.login` module. No configuration to parse, no module maps to resolve.

#### `@module` — Explicit Module Naming

The `@module` annotation at the top of a file overrides the path-derived name. This is optional — most files don't need it.

```blink
// File: src/auth/login.bl
// Without @module, this module is auth.login
// With @module, it can be renamed:
@module("auth")

// Now this file's public items are importable as auth.login(), auth.Token, etc.
// rather than auth.login.login(), auth.login.Token
```

The primary use case for `@module` is when a directory has a single "main" file that should represent the package itself:

```
auth/
  auth.bl        # @module("auth") — the package's primary module
  rate_limit.bl  # module: auth.rate_limit
  token.bl       # module: auth.token
```

Without `@module`, you'd import as `auth.auth.login()`. With `@module("auth")` on `auth.bl`, you import as `auth.login()`.

**Constraint:** `@module` can only set the name to the parent package name. You cannot use `@module` to move a module into a completely different package. The compiler rejects `@module("billing")` on a file inside `auth/`.

#### Imports

Imports are explicit. No auto-imports beyond the module prelude (§10.6), which provides all compiler-known types, constructors, and traits.

```blink
import auth                          // import the auth package
import auth.token                    // import a specific module
import auth.token.{Token, verify}    // import specific items
```

Namespace usage after import:

```blink
import auth

fn handle_login(req: Request) -> Response ! IO, DB, Crypto {
    let session = auth.login(req.email, req.password)?
    // ...
}
```

Or with specific item imports:

```blink
import auth.{login, AuthError}

fn handle_login(req: Request) -> Response ! IO, DB, Crypto {
    let session = login(req.email, req.password)?
    // ...
}
```

#### Qualified Access

After importing a module, you can access its `pub` items using `module.name` syntax:

```blink
import auth

fn handle_login(req: Request) -> Response ! IO, DB, Crypto {
    let session = auth.login(req.email, req.password)?
    let token = auth.Token.new(session)
    // ...
}
```

**Rules:**
- Qualified access works for functions (`auth.login()`), types (`auth.Token`), and constants (`auth.MAX_RETRIES`). Enum variants use their type qualifier: `Role.Admin`, not `auth.Role.Admin`.
- Only the leaf module name is used as qualifier. `import std.num` enables `num.parse_int()`, not `std.num.parse_int()`. For modules with the same leaf name, use aliases: `import legacy.auth as legacy_auth`.
- Selective imports do NOT restrict qualified access. `import auth.{login}` restricts bare `Token` but `auth.Token` still works.
- A whole-module import binds only its qualifier. If `import foo` and `import bar` both export `helper`, nothing collides: call `foo.helper()` or `bar.helper()`. Two imports that bind one name, bare name or qualifier, are E1005 (*Imported Names*, §10.5).
- Local definitions shadow module names: if `let auth = 5` exists, `auth.login()` is a method call on the integer, not a module-qualified call.

**No wildcard imports.** `import auth.*` does not exist. Every name in scope is explicitly imported. This is non-negotiable for locality of reasoning — an AI reading a file can determine every available name from the import block alone.

#### 10.1.1 No Inline Modules

Blink has no `mod name { }` syntax for creating sub-modules within a file. The `mod` keyword is reserved but unused in v1 (§2.23 *Reserved Words*).

**The rule is absolute: one file = one module.** If you need a sub-module, create a separate file in a subdirectory.

```
// WRONG — not valid Blink syntax:
mod schema {
    type SchemaRule { ... }
    pub fn validate(obj: Map) -> Result[(), Error] { ... }
}

// RIGHT — create a separate file:
//   json_validator/schema.bl
// Then import it:
import json_validator.schema.{SchemaRule, validate}
```

**Why no inline modules:** Inline modules create a second module-like entity alongside file-modules, introducing ambiguity about visibility, importability, and identity. Go demonstrated that "package = directory" scales without inline namespaces. Maintaining one kind of module keeps the import story, tooling (LSP go-to-definition, symbol search), and AI code generation maximally simple.

**Panel vote: 4-1** (Web/Scripting dissented, preferring file-scoped namespaces for lightweight grouping). See [DECISIONS.md](../DECISIONS.md).

If `mod name { }` syntax is encountered, the compiler reports:

```
error[E1015]: inline modules are not supported
 --> app.bl:10:1
  |
10| mod schema {
  | ^^^ Blink uses file-based modules
  |
  = help: create a separate file `schema.bl` in a subdirectory instead
  = note: see §10.1 — one file = one module
```

### 10.2 Visibility: `pub`, Default Private

All items (functions, types, constants, let bindings, traits) are **module-private by default**. The `pub` keyword makes an item visible to other modules.

```blink
// Private — only this module can call it
fn hash_password(pwd: Str) -> Str ! Crypto {
    crypto.argon2(pwd)
}

// Public — importable by other modules
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    let user = find_user(email)?
    let hashed = hash_password(pwd)
    verify(user, hashed)
}

// Public type — part of the module's API
pub type AuthError {
    BadCredentials
    AccountLocked
    RateLimited
}

// Private type — implementation detail, invisible outside this file
type PasswordHash {
    value: Str
    algorithm: Str
    salt: Str
}
```

**`pub let` exports immutable module-level bindings.** A module-level `let` (without `mut`) marked `pub` is importable by other modules as a read-only value. `pub let mut` is a compile error (E1013, not yet enforced) — mutable state must be accessed through functions, with mutation tracked by the compiler's write-set analysis (§4.16). See §2.12.1 for full rules on module-level bindings.

There is no `pub(crate)`, no `protected`, no `internal`, no `friend`. Two levels: private and public. This is a deliberate constraint.

**Why only two levels:** Visibility modifiers beyond private/public create decision paralysis for both humans and AI. Rust's `pub(crate)`, `pub(super)`, `pub(in path)` are almost never used correctly on the first try. Two levels means zero ambiguity: either something is part of the API or it isn't.

**Package-level visibility:** If a module needs to expose items only to sibling modules within the same package (not to external consumers), use a convention: create an `internal.bl` module that re-exports internal items. External consumers see the package's public API; internal modules import from `internal`. This is a convention, not a language feature — keeping the language simple.

### 10.3 Module Capability Budgets

A module can declare a capability ceiling with `@capabilities`. This sets a hard upper bound on what effects any function in the module is allowed to perform.

```blink
@module("auth")
@capabilities(DB, Crypto, IO)

// OK — DB and Crypto are within budget
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}

// COMPILE ERROR — Net is not in the capability budget
pub fn call_external_api(url: Str) -> Str ! Net {
    // ...
}
```

```
error[E0900]: effect exceeds module capabilities
 --> auth/login.bl:15:1
  |
1 | @capabilities(DB, Crypto, IO)
  | ----------------------------- module capability budget
  ...
15| pub fn call_external_api(url: Str) -> Str ! Net {
  |                                             ^^^ effect `Net` not in budget
  |
  = note: module `auth` allows: DB, Crypto, IO
  = help: add `Net` to @capabilities or move this function to a different module
```

**Why capability budgets:** They enforce architectural boundaries at compile time. The auth module should never make network calls — that's a code smell indicating misplaced responsibility. Without capability budgets, an AI might add a "convenient" HTTP call inside an auth function, slowly eroding module boundaries. With `@capabilities`, the compiler stops it immediately.

Capability budgets compose hierarchically. A package-level `@capabilities` in the directory's primary module constrains all modules in that package:

```blink
// auth/auth.bl
@module("auth")
@capabilities(DB, Crypto, IO)
// All modules under auth/ inherit this ceiling
```

A child module can declare a **narrower** budget but never a wider one:

```blink
// auth/token.bl — can narrow the budget
@capabilities(Crypto)

// Only Crypto is allowed here, not DB or IO
pub fn issue_token(user: User) -> Token ! Crypto {
    // ...
}
```

Omitting `@capabilities` means "no restrictions" — the module can use any effect. This is the default for application code. Library authors should always set capability budgets.

### 10.4 Provenance Tracking (`@src`)

The `@src` annotation links code to external artifacts: requirements documents, design RFCs, issue trackers, compliance mandates.

```blink
@src(req: "AUTH-001")
@src(design: "RFC-2026-07")
@src(issue: "GH-1234")
@src(compliance: "SOC2-CC6.1")
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

Provenance is metadata — it does not affect compilation, type checking, or code generation. It is tracked by the compiler and queryable through tooling.

#### `blink trace` — Requirement Traceability

```
$ blink trace AUTH-001

Requirement: AUTH-001
Linked code:

  auth/login.bl:
    pub fn login(...)           @src(req: "AUTH-001")
    fn verify_credentials(...)  @src(req: "AUTH-001")

  auth/rate_limit.bl:
    pub fn check_rate(...)      @src(req: "AUTH-001")

  auth/token.bl:
    pub fn issue_token(...)     @src(req: "AUTH-001")

Coverage: 4 functions, 2 test blocks
Last modified: 2026-01-28
```

Reverse tracing works too:

```
$ blink trace --reverse auth.login

Function: auth.login
Links:
  req: AUTH-001 (User authentication)
  design: RFC-2026-07 (Auth system redesign)
  issue: GH-1234 (Add rate limiting to login)
  compliance: SOC2-CC6.1 (Logical access controls)
```

**Why provenance in the language:** Compliance-heavy environments (healthcare, finance, government) require traceability from requirements to code. Currently this lives in spreadsheets, Jira queries, and tribal knowledge. Embedding it in the source makes it versionable, verifiable, and impossible to lose. For AI agents, provenance provides context about _why_ code exists — not just what it does.

### 10.5 Import Resolution

This section specifies how the compiler resolves `import` declarations to source files, handles dependency versions, detects cycles, and supports re-exports.

#### Resolution Algorithm

Import resolution is a deterministic function from module path to file path. No search path lists, no environment variables, no `BLINK_PATH`.

**Local modules** (project source):

```
resolve("auth.token") → <project>/src/auth/token.bl
resolve("auth")       → <project>/src/auth.bl (if @module("auth"))
                        OR <project>/src/auth/ (package — exposes pub items)
```

The compiler resolves module paths relative to the project's `src/` directory. The path segment separator `.` maps to the filesystem `/`. The file extension `.bl` is implicit and must not appear in the import.

```blink
import auth.token           // resolves to src/auth/token.bl
import auth.token.{Token}   // resolves to src/auth/token.bl, imports Token
import db.connection        // resolves to src/db/connection.bl
```

**External dependencies** (from `blink.lock`):

```blink
import std.http            // stdlib or dependency declared in blink.toml
import std.json.{parse}    // specific item from dependency
```

External packages are namespaced by their registry org/name (§8.9.2, §8.9.7). The `std/http` package is imported as `std.http`. The compiler resolves them from the lockfile's content-addressed store (or from the bundled stdlib for implicit deps — see §10.7). The resolution order:

1. Check local `src/` for a matching path
2. Check dependencies declared in `blink.toml` (resolved via `blink.lock`)
3. No match → compile error

Local modules shadow dependencies with the same name. This is intentional — it allows wrapping a dependency without changing consumer imports. The compiler emits a warning when shadowing occurs:

```
warning[W1000]: local module shadows dependency
 --> src/http.bl:1:1
  |
1 | @module("http")
  | ^^^^^^^^^^^^ shadows package `blink.http` from blink.toml
  |
  = help: this is allowed but may confuse consumers expecting the library
```

#### Package Entry Resolution

A bare package import — `import <pkg>` with no sub-path — resolves deterministically to a single file derived from the package name:

```
resolve("pg")    → <pkg-root>/src/pg.bl
resolve("redis") → <pkg-root>/src/redis.bl
```

The entry filename equals `[package].name` from the package's `blink.toml`, with `.bl` appended. There is no fallback. `src/lib.bl` is **not** a recognized entry-point convention; it is a regular module file like any other and the compiler does not probe for it on bare imports.

```blink
// libs/pg/blink.toml
// [package]
// name = "pg"

// libs/pg/src/pg.bl  -- the entry file (mandatory for bare external import)
@module("pg")

pub fn connect(url: Str) -> Connection { ... }
```

```blink
// consumer
import pg                    // resolves to libs/pg/src/pg.bl
import pg.protocol           // resolves to libs/pg/src/protocol.bl
```

**Package name grammar.** The `[package].name` field must match `[a-z][a-z0-9_]*` (validated as `error[E1011]`). Hyphens are forbidden. Dots are forbidden in the bare name (dots are the import sub-path separator and are reserved for registry paths per §8.9.2). The constraint exists so that the four-way invariant — `[package].name` = directory name = entry filename stem = `@module(...)` argument — holds character-for-character with no transformation table.

**Project root discovery.** A source file's package root is the nearest ancestor directory containing a `blink.toml`, walking up from the file being compiled. `src/` beneath the package root is the source root. Files under `tests/`, `examples/`, and `bench/` are *peers* of `src/`, not children: their imports resolve against the same package root that walking up from `src/` would find. This rule applies uniformly to first-party (self-package) and third-party imports — there is no special-case "self-import" branch.

```
libs/pg/
  blink.toml              [package].name = "pg"
  src/
    pg.bl                 @module("pg") — entry
    protocol.bl           @module("pg") — sibling, merges into pg.*
  tests/
    test_connect.bl       walks up to libs/pg/blink.toml,
                          import pg → libs/pg/src/pg.bl
```

A source file with no enclosing `blink.toml` is not part of any package. Bare external imports from such a file are a compile error (E1010); only stdlib imports (`std.*`) and absolute file paths from the compiler driver are allowed.

**`@module` on the entry file.** The entry file's `@module(...)` argument, if present, must equal `[package].name`. If they disagree, the compiler rejects with `error[E1008]`. The annotation may be omitted on the entry file — its meaning is implied by location — but conforming style is to declare it explicitly for parity with non-entry files.

**Failure mode.** When the entry file is missing, the compiler reports a single path:

```
error[E1009]: package entry not found
  --> tests/test_connect.bl:3:8
   |
 3 | import pg
   |        ^^ package `pg` has no entry file
   |
   = note: package root: libs/pg/ (from blink.toml)
   = note: expected:    libs/pg/src/pg.bl
   = help: create src/pg.bl, or check the `name` field in blink.toml
```

There is no second candidate to mention. The diagnostic names exactly one expected path because there is exactly one rule.

#### `@module` Resolution

When a file declares `@module("parent_package")`, its public items merge into the parent package namespace. The compiler validates that `@module` only refers to the immediate parent:

```
src/auth/
  auth.bl         @module("auth") — items available as auth.X
  token.bl        items available as auth.token.X
  rate_limit.bl   items available as auth.rate_limit.X
```

If two files in the same directory both declare `@module` with the same name, or if `@module` conflicts with a sibling module name, the compiler rejects it:

```
error[E1001]: duplicate module name
 --> src/auth/helpers.bl:1:1
  |
1 | @module("auth")
  | ^^^^^^^^^^^^ module name `auth` already claimed by src/auth/auth.bl
```

#### Cycle Detection

**Intra-package cycles are allowed.** Modules within the same package (directory) may import each other freely. The compiler resolves all declarations within a package before type-checking bodies — the same approach used by ML-family languages.

```blink
// src/auth/login.bl
import auth.types.{AuthError}    // sibling — allowed

// src/auth/types.bl
import auth.login.{LoginEvent}   // sibling — allowed (intra-package cycle)
```

Within a package, the compiler:
1. Collects all declarations (function signatures, types, traits) from all modules in the package
2. Builds a unified symbol table for the package
3. Type-checks all function bodies against the unified table

**Cross-package cycles are compile errors.** If package `auth` imports from package `billing` and `billing` imports from `auth`, the compiler rejects it:

```
error[E1002]: circular package dependency
  |
  = note: auth → billing → auth
  = help: extract shared types into a common package
```

Cross-package cycles indicate an architectural boundary violation. The fix is always to extract shared types into a third package that both depend on.

#### Diamond Dependencies

**Exactly one version per package.** If two dependencies require different versions of the same transitive dependency, the compiler reports a conflict:

```
error: dependency version conflict
  myapp depends on http 0.5
  auth 1.0 depends on http 0.6

  resolution: only one version of `http` allowed in the dependency graph

  help: run `blink update http` to find a compatible version
        or pin auth to a version compatible with http 0.5
```

One-version-per-package is required for type identity. If `auth` produces an `http.Response` from http 0.6 and `myapp` expects `http.Response` from http 0.5, these are incompatible types. Allowing both silently would violate Blink's explicit-over-implicit philosophy.

The `blink update` command uses minimum version selection: it picks the lowest version that satisfies all constraints. This makes builds reproducible — adding a dependency never upgrades unrelated transitive deps.

#### Re-exports (`pub import`)

A module can re-export items from other modules using `pub import`. This decouples a package's public API from its internal file structure.

```blink
// src/auth/auth.bl
@module("auth")
pub import auth.token.{Token, verify}
pub import auth.login.{login, AuthError}
pub import auth.rate_limit.{RateLimiter}

// Consumers import from the package directly:
// import auth.{Token, login, AuthError}
// instead of knowing the internal module structure
```

`pub import` rules:
- Re-exported items must be `pub` in their source module
- Re-exports are transitive — `pub import` of a `pub import` works
- The compiler tracks the original declaration for go-to-definition (LSP lands on the source, not the re-export)
- `pub import` of an entire module re-exports all its `pub` items: `pub import auth.token` makes `auth.Token`, `auth.verify` etc. available
- Circular re-exports are detected and rejected at compile time
- Any module can use `pub import` — no restriction to `@module`-annotated facade files

**Consumer-side access:** Re-exported items are indistinguishable from locally-defined `pub` items. If module A does `pub import B.{foo}`, then consumers can access `foo` via both selective import (`import A.{foo}`) and qualified access (`A.foo`). The same access rules apply as for any other pub item in A's namespace.

**Name collisions:** a module that both defines and re-exports one name gets E1012, the same error as for a plain import (*Imported and Declared Names* below).

**Unused import warnings:** `pub import` never triggers W0602 (unused import). Re-exports declare public API surface, not local usage intent. The re-exporting module does not need to use the re-exported items itself.

Re-exports enable API evolution: moving a type from `auth.token` to `auth.session` internally only requires updating the `pub import` in the package root — downstream consumers' imports don't change.

Re-exports also enable shared import modules within a project:

```blink
// src/codegen_common.bl — shared re-exports for codegen subsystem
pub import codegen_types.{emit_line, CT_INT, CT_STRING, CT_VOID}
pub import codegen_types.{c_fn_name, c_safe_name, c_type_str}

// src/codegen_expr.bl — consumes the shared re-exports
import codegen_common.{emit_line, CT_INT, CT_STRING, c_fn_name}
```

#### Imported and Declared Names

A selective import binds each listed name in module scope, and module scope is one flat namespace (§2.12.1, §10.6 *Shadowing Rules*). So a module may not both import a name and declare it. A module-level declaration of a name that a selective import binds is a compile error, `DuplicateSymbol` (E1012). The rule covers every declaration kind in both namespaces: `type`, type alias, `trait`, `effect`, `fn` and module-level `let`. It applies to `import` and `pub import` alike, and to every visibility of the declaration.

```blink
import alpha.{Point}

type Point {    // error[E1012]: `Point` is imported from `alpha`
    b: Int
}
```

```
error[E1012]: `Point` is both imported and declared in module `main`
 --> src/main.bl:3:6
  |
1 | import alpha.{Point}
  |               ^^^^^ imported from `alpha` here
3 | type Point {
  |      ^^^^^ also declared here
  |
  = help: drop `Point` from the import list and use `alpha.Point`,
          or import it under another name: import alpha.{Point as AlphaPoint}
```

The check uses the name that the import binds, which is the name after `as` when there is one:

```blink
import alpha.{Point as P}
type P { b: Int }        // error[E1012]: `P` is both imported and declared
```

```blink
import alpha.{Point as AlphaPoint}
type Point { b: Int }    // OK: the import binds `AlphaPoint`, not `Point`
```

A whole-module import (`import alpha`) binds no bare name, so it never collides with a declaration.

**Fix.** For a plain `import`, the fix "drop the name from the import list" is machine-applicable (§8.6): every bare use of the name then means the local declaration. When the edit empties the list, the fix rewrites the line to `import alpha`, because a selective import also gives qualified access (§10.1 *Qualified Access*). It deletes the line only when no name in the file resolves through the `alpha` qualifier; the check uses name resolution, not text search. For `pub import`, the same edit changes the module's public API, so the fix is a suggestion only. On that import entry, E1012 replaces W0602 (unused import): one mistake gives one diagnostic.

#### Imported Names

Each file has its own binding table. A selective import binds each listed name, and a whole-module import binds its qualifier (the leaf name, or the name after `as`). Bare names and qualifiers share one table, because `X.y` can be qualified access or access through a type. Two imports in one file that bind one name to different items are a compile error, `AmbiguousImport` (E1005). The check uses the name that each import binds, which is the name after `as` when there is one. It covers both namespaces and applies to `import` and `pub import` alike. The compiler checks each import when it reads it, whether or not the file uses the name.

```blink
import auth.{Error}
import db.{Error}             // error[E1005]: `Error` is imported twice
```

```
error[E1005]: `Error` is imported twice in module `main`
 --> src/main.bl:2:12
  |
1 | import auth.{Error}
  |              ^^^^^ first imported from `auth` here
2 | import db.{Error}
  |            ^^^^^ imported again from `db` here
  |
  = help: import one under another name: import db.{Error as DbError}
          or drop it from the list and use `db.Error`
```

The same rule covers qualifiers:

```blink
import http
import http2 as http          // error[E1005]: `http` is imported twice

import db
import auth.{Token as db}     // error[E1005]: `db` is imported twice
```

Two imports that bind one name to the **same** item are not E1005. The compiler compares the items that name resolution reaches after it follows `pub import` chains, not the import paths. The later entry gets W0602 (unused import), with a machine-applicable fix that deletes it (§8.6). One item under two names binds no name twice, so it is legal:

```blink
import auth.{Error}
import auth.{Error}                   // warning[W0602]: `Error` already imports this item
import auth.{Token, Token as AuthToken}   // OK: two names, one item
```

**Fix.** Which import should keep the name is the author's choice, so the fix is a suggestion only: rename one import with `as`, or drop the name and use the qualified path. The help should print a concrete name that is not already bound in the file. On the colliding entry, E1005 replaces W0602: one mistake gives one diagnostic. When a declaration also takes the name, every import entry that collides with it gets E1012 (*Imported and Declared Names*), and E1005 applies only between import entries that have no E1012.

#### Import Errors

| Code | Error | Cause |
|------|-------|-------|
| E1000 | Module not found | No file at resolved path, no matching dependency |
| E1001 | Duplicate module name | Two files claim same `@module` name |
| E1002 | Circular package dependency | Cross-package import cycle |
| E1003 | Private item access | Referencing or importing a function, type, trait, variant or other item that is not `pub` in its declaring module |
| E1004 | Version conflict | Diamond dependency with incompatible versions |
| E1005 | Ambiguous import | Two imports in one file bind one name, bare name or qualifier, to different items |
| E1006 | Import not selected | A bare name comes from an imported module but is not in the selective import list |
| E1007 | Module-qualified type member | A type member or variant is reached through a module qualifier (`mod.Type.Member`) instead of an imported type |
| E1008 | Invalid module annotation | `@module(...)` disagrees with parent package or entry file's `[package].name` |
| E1009 | Package entry not found | Bare `import <pkg>` resolved to a package whose `src/<name>.bl` does not exist |
| E1010 | Orphan file | Bare external import from a file with no enclosing `blink.toml` |
| E1011 | Invalid package name | `[package].name` violates the `[a-z][a-z0-9_]*` grammar |
| E1012 | Duplicate symbol | A module-level declaration takes a name that a selective import (`import` or `pub import`) binds |
| E1013 | `pub let mut` forbidden | A module-level `let mut` is marked `pub` (§2.12.1). Not yet enforced |
| E1015 | Inline module not supported | A `mod name { ... }` block appears in source (§10.1.1) |
| E1016 | Duplicate module binding | Two module-level declarations bind one name in one namespace (§2.12.1) |

```
error[E1003]: item `Token` is private in module `auth.internal`
 --> src/api/handler.bl:2:1
  |
2 | import auth.internal.{Token}
  |                       ^^^^^ not visible — `Token` is not `pub`
  |
  = help: import from the public API: `import auth.{Token}`
```

#### Import Aliases

Imports can be renamed at the import site to resolve ambiguity or improve local clarity:

```blink
import auth.{AuthError as LoginError}
import db.connection.{Connection as DbConn}
```

Aliases are local to the importing file. They do not affect the imported module or any other consumers. Two imports in one file that bind one alias to different items are E1005 (*Imported Names*); two files may bind one alias to different items.

An alias that is a compiler-known name (`import auth.{Error as Option}`) shadows it and gets W1010 (§10.6 *Shadowing Rules*).

### 10.6 Module Prelude

Every Blink module has a set of names automatically in scope — the **module prelude**. These are compiler-known items whose semantics are baked into the language: operator desugaring, literal typing, `for` loop expansion, `?`/`??` expansion, `@derive`, and string interpolation all depend on them. Requiring explicit imports for items the compiler already knows about would add ceremony without information.

The prelude is fixed. It cannot be extended by users or libraries. Only compiler-known items are eligible.

#### Keywords and Literals

`true` and `false` are the two values of type `Bool`. The keywords are in the one table in §2.23 *Reserved Words*.

A keyword cannot name a binding, so a keyword cannot be shadowed or imported. A keyword can name a member: a field, or a method in an `impl` or `trait` body (§2.23 *Members and Bindings*).

#### Prelude Types

All built-in types are in the prelude. They are available in every module without import.

**Primitive types:**

| Name | Description |
|------|-------------|
| `Int` | 64-bit signed integer (the default integer type) |
| `I8`, `I16`, `I32`, `I64` | Sized signed integers |
| `U8`, `U16`, `U32`, `U64` | Unsigned integers |
| `Float` | 64-bit IEEE 754 floating point |
| `F32`, `F64` | Sized floating point (§3.2.3) |
| `Str` | UTF-8 string, GC-managed |
| `Char` | Unicode scalar value |
| `Bool` | Boolean (`true` / `false`) |
| `()` | Unit type |

**Parameterized collection types:**

| Name | Description |
|------|-------------|
| `List[T]` | Growable ordered sequence. `[T]` is sugar for `List[T]` |
| `Map[K, V]` | Hash map |
| `Set[T]` | Hash set |

**Core ADTs and their constructors:**

| Name | Description |
|------|-------------|
| `Option[T]` | Optional value type |
| `Some(T)` | `Option` variant: value present |
| `None` | `Option` variant: value absent |
| `Result[T, E]` | Success-or-error type |
| `Ok(T)` | `Result` variant: success |
| `Err(E)` | `Result` variant: error |
| `Ordering` | Comparison result type |
| `Less`, `Equal`, `Greater` | `Ordering` variants |

#### Prelude Traits

All compiler-known traits are in the prelude. They are compiler-known for one of two reasons: they participate in operator desugaring, `for` loop expansion, `@derive`, string interpolation, and conversion protocols; **or** they back the method surface of a built-in type (`"x".len()`, `sb.write(...)`). Requiring imports for either would mean every file using `==`, `<`, `for`, `"{value}"`, or `.len()` needs boilerplate imports.

| Trait | Used by |
|-------|---------|
| `Eq` | `==`, `!=` operators |
| `Ord` | `<`, `>`, `<=`, `>=` operators |
| `Hash` | `Map`, `Set` key requirements |
| `Display` | String interpolation `"{value}"` |
| `Clone` | `@derive(Clone)` |
| `Add`, `Sub`, `Mul`, `Div`, `Rem`, `Neg` | Arithmetic operators (sealed) |
| `From[T]` | Infallible conversion, `Into` auto-derivation |
| `Into[T]` | `.into()` method (auto-derived from `From`) |
| `TryFrom[T]` | Fallible conversion |
| `Closeable` | `with...as` scoped resources |
| `Iterator[T]` | Lazy iteration, adapter methods |
| `IntoIterator[T]` | `for x in expr` desugaring |
| `Sized` | `.len()` / `.is_empty()` on built-in types |
| `Contains` | `.contains()` element membership (`Set`; `List`/`Map` planned) |
| `StrOps`, `BytesOps`, `StringBuildOps` | methods on `Str` / `Bytes` / `StringBuilder` |
| `ListOps`, `MapOps`, `SetOps`, `Joinable` | methods on `List` / `Map` / `Set` |

The built-in method-surface traits (`Sized`, `Contains`, `StrOps`, `BytesOps`, `StringBuildOps`, `ListOps`, `MapOps`, `SetOps`, `Joinable`) are **sealed**: their implementations are compiler-provided for the built-in types, and user code may neither implement nor redefine them (see §3.2.2 for the full method surface and the sealing rule). Method dispatch on a built-in receiver is resolved intrinsically and never depends on the trait name being imported.

Because every prelude name is unconditionally in scope, **importing a prelude name is permitted and has no effect** — it binds nothing new and is not an error.

#### Test Builtins

Inside `test` blocks, the following functions are auto-available without import:

| Name | Signature |
|------|-----------|
| `assert(cond)` | `fn assert(cond: Bool)` |
| `assert_eq(a, b)` | `fn assert_eq[T: Eq + Debug](left: T, right: T)` |
| `assert_ne(a, b)` | `fn assert_ne[T: Eq + Debug](left: T, right: T)` |
| `prop_check(f)` | `fn prop_check[...](f: fn(...) -> ())` — the property closure given directly to the intrinsic may use `?`; it is elaborated to `fn(...) -> Result[(), TestError]` like a test body (§2.20) |

These are compiler intrinsics — not library functions. They capture source locations, generate diffs, and are stripped from release builds. They are scoped to `test` blocks; using them outside a test block is a compile error.

User-defined names shadow test builtins within test blocks (standard scoping rules). The compiler warns when a test builtin is shadowed.

#### Compiler-Known Type Names (closed set)

The table below is the **complete** set of compiler-known type names a program can write. Each one is usable in every module **without import**. The set is **closed**: a name the table does not list is not compiler-known, and the compiler must not treat it as one. A new built-in type is added as an ordinary declaration in a named `std` module and is reached through `import`, as `Duration` and `Instant` are in `std.time` (§3.2.3). It is never added to this table.

| Name | Home | Specified in | Declaring it |
|------|------|--------------|--------------|
| `Int`, `I8`, `I16`, `I32`, `I64` | prelude | §3.2 | reserved |
| `U8`, `U16`, `U32`, `U64` | prelude | §3.2 | reserved |
| `Float`, `F32`, `F64` | prelude | §3.2, §3.2.3 | reserved |
| `Str`, `Char`, `Bool` | prelude | §3.2 | reserved |
| `Void` | `blink.ffi` | §9.1.1 | reserved |
| `Self` | — | §3.6 *The `Self` Type* | reserved |
| `List[T]`, `Map[K, V]`, `Set[T]` | prelude | §3.2 | shadows, W1010 |
| `Option[T]`, `Result[T, E]`, `Ordering` | prelude | §3.2, §3.6 | shadows, W1010 |
| `Iterator[T]` | prelude | §3c.1 | shadows, W1010 |
| `Never` | prelude | §2.20 | shadows, W1010 |
| `Bytes`, `StringBuilder` | prelude | §3.2.1, §3.2.3 | shadows, W1010 |
| `Handle[T]`, `Channel[T]` | prelude | §4.13 | shadows, W1010 |
| `Template[C]`, `Raw[T]`, `TemplateValue` | prelude | §3b.5 | shadows, W1010 |
| `ConversionError` | `blink.core` | §3c.2 | shadows, W1010 |
| `Range[T]` | `blink.core` | §2.10 | shadows, W1010 |
| `Handler[E]` | `blink.core` | §4.7.1 | shadows, W1010 |
| `Ptr[T]`, `Buf[T]` | `blink.ffi` | §9.1.1, §9.1.3 | shadows, W1010 |

The prelude trait names in *Prelude Traits* share the type namespace and follow the same shadowing rule, except the sealed method-surface traits: user code may not redefine those (§3.2.2).

Every name marked *shadows* can also be named through a pseudo-module: `Ptr` and `Buf` through `blink.ffi`, every other one through `blink.core`. No such import is needed; `import blink.core.{Handler}` is an inert documentation marker (§10.7). An **aliased** import (*Import Aliases*, §10.5) binds the alias to the compiler-known type — `import blink.core.{Handle as TaskHandle}` — and this is how a module that shadows one of these names still reaches the builtin.

`FfiScope` is not in the table. No program can write it: an `FfiScope` value occurs only as the resource of a `with ... as` block (§9.1.1), and its type is never written. The name is not reserved, and a user type named `FfiScope` is an ordinary type with no diagnostic. The same holds for spellings the compiler uses internally for function types (`fn(A) -> B`) and tuple types (`(A, B)`): they are not names, and a user may declare `type Fn` or `type Tuple` like any other type.

#### Shadowing Rules

A **reserved** name cannot be declared. The reserved names are `Self`, the scalar types that literal syntax produces (`Int`, `I8`–`I64`, `U8`–`U64`, `Float`, `F32`, `F64`, `Str`, `Char`, `Bool`), and `Void`. Declaring one is an error:

```
error[ReservedTypeName]: `Int` is a reserved type name
 --> geo/units.bl:1:6
  |
1 | type Int {
  |      ^^^ reserved: literals produce this type in every module
  |
  = help: choose another name, for example `type IntValue`
```

The reserved set grows only when literal syntax grows.

Every **other** compiler-known type name, and every prelude trait name, may be declared. The declaration wins in its module (§3.4 *Type Name Resolution*), and the compiler emits one warning at the declaration:

```
warning[W1010]: name shadows compiler-known type
 --> app/effects.bl:3:6
  |
3 | type Handler {
  |      ^^^^^^^ shadows compiler-known type `Handler[E]` (blink.core)
  |
  = help: to use the compiler-known type in this module, import it under another name:
          import blink.core.{Handler as EffectHandler}
```

The rule covers every declaration that puts a name in the type namespace: `type` (struct or enum), type alias, `trait`, and `effect`. It also covers such a name that another module declares and this module imports (`import geo.{Handler}`). Local bindings (`let`) live in the value namespace and are not type declarations.

**Shadowing happens only between nested scopes**: prelude under module, dependency under local module (W1000, §10.5), and outer under inner in a function (§2.2). Two bindings of one name in one namespace of module scope, from declarations or selective imports, are a duplicate, never a shadow. One rule covers every pair, and the code tells which pair collided: two selective imports are E1005 (`AmbiguousImport`), a selective import and a declaration are E1012 (`DuplicateSymbol`), and two declarations are E1016 (`DuplicateModuleBinding`, §2.12.1). So `import blink.core.{Handler}` together with `type Handler` is E1012 (*Imported and Declared Names*, §10.5), not W1010. A plain `type Handler` with no such import still gets W1010. The rule in §10.1 *Qualified Access* that a local definition hides a module qualifier (`let auth = 5` makes `auth.login()` a method call) is a different layer, and this rule does not change it.

**Diagnostics that involve a shadowing name.** The escape must be visible where the error is, not only at the declaration. So:

1. The W1010 `help:` line names the aliased-import fix: `import blink.core.{X as Y}`, or `import blink.ffi.{X as Y}` for `Ptr` and `Buf`.
2. Every diagnostic whose subject is a name that shadows a compiler-known type — type-argument arity (E0303), type mismatch (E0300), missing method, and any other — adds a `note:` that gives the shadowing declaration's location and the builtin's home, and repeats the `help:` line from (1).
3. When two different types with the same name appear in one diagnostic, each prints as `Name (module)`. Hover in the language server uses the same form.

```blink
type Handler {
    n: Int
}

fn with_db(h: Handler[DB]) { }    // error[TypeArgArity]: see below
```

```
error[TypeArgArity]: type `Handler` takes 0 type arguments, found 1
 --> app/effects.bl:5:15
  |
5 | fn with_db(h: Handler[DB]) { }
  |               ^^^^^^^^^^^
  |
  = note: `Handler` here is `type Handler` (app/effects.bl:1), which shadows the compiler-known `Handler[E]` (blink.core)
  = help: import blink.core.{Handler as EffectHandler}
```

Shadowing never changes what the compiler inserts. `x?`, `T?`, `for`, `..`, `with`, `async.spawn` and every other desugaring use the compiler-known type by identity (§3.4 *Type Name Resolution*, *Hygiene*).

Keywords and the literals `true` and `false` cannot be shadowed, because a keyword cannot name a binding (§2.23).

### 10.7 Standard Library Resolution

The standard library is a set of packages that ship with the Blink compiler. They are available to every Blink program without explicit declaration in `blink.toml`. The compiler treats them as **implicit dependencies** — they participate in the same resolution algorithm as explicit deps (§10.5), with no special resolution step.

#### Stdlib as Implicit Dependencies

Tier 1 stdlib packages (§8.1, OPEN_QUESTIONS §2.2) are injected into the dependency graph as if the user had declared them in `blink.toml`. They are pinned to the compiler version and cannot be overridden.

Conceptually, the compiler prepends these implicit entries before resolving dependencies:

```toml
# Implicit — injected by compiler, not written by user
[dependencies]
std/core = { builtin = true }       # blink.core types (ConversionError, Range, Handler)
std/collections = { builtin = true } # additional collection utilities
std/io = { builtin = true }         # io.println, io.print, etc.
std/fs = { builtin = true }         # fs.read, fs.write, fs.list_dir
std/toml = { builtin = true }       # TOML parser
std/json = { builtin = true }       # JSON codec — completes Serialize/Deserialize (§10.7.1)
std/semver = { builtin = true }     # version parsing and constraint matching
```

The exact set of Tier 1 packages is determined by the compiler version. `blink --version` reports both: `blink 0.3.0 (stdlib 0.3.0)`.

#### Import Syntax

Stdlib packages live under the `std` namespace, matching the `std/` org on the registry (§8.9.2). Import paths follow the `org/name` → `org.name` mapping established in §8.9.7:

```blink
import std.toml                    // TOML parser
import std.semver                  // version parsing
import std.toml.{toml_parse, toml_get}  // selective import
```

The `std` prefix is mandatory. There are no bare stdlib imports — `import toml` resolves only to local `src/toml.bl`, never to stdlib. This avoids the ambiguity that plagues Python's stdlib (is `json` local or stdlib?) and matches Rust's `std::` convention.

The `blink.*` namespace remains reserved for compiler-internal pseudo-modules (`blink.core`, `blink.ffi`) that are part of the language definition, not distributable packages. Imports from this reserved namespace resolve as **recognized no-ops** — accepted, inert, never required, and never `ModuleNotFound`. The pseudo-modules' contents (`ffi`'s pointer types and operations per §9.1.1, and the `blink.core` names per §10.6 *Compiler-Known Type Names*) are compiler-known and usable without importing them; the import is an optional documentation marker (see [FFI import namespace resolution](../decisions/ffi-import-namespace-resolution.md)). The one import from these pseudo-modules that has an effect is an aliased one, `import blink.core.{X as Y}`: it binds `Y` to the compiler-known type, which a module that declares its own `X` needs (§10.6 *Shadowing Rules*).

#### Resolution Order

The resolution algorithm from §10.5 is unchanged:

1. Check local `src/` for a matching path
2. Check dependencies declared in `blink.toml` (resolved via `blink.lock`) — **stdlib packages are included here as implicit entries**
3. No match → compile error

Local modules shadow stdlib with warning W1000 (same as any dependency shadowing). Explicit `blink.toml` entries for `std/` packages override the bundled version — this is the escape hatch for pinning a specific stdlib version when needed.

#### Physical Location

Stdlib source ships alongside the compiler binary in `<blinkc_dir>/lib/std/`. The compiler discovers this path relative to its own binary — no environment variables, no configuration. This satisfies the existing 5-0 decision: "no env vars, no configurable roots."

```
blink/
  bin/blink              # compiler binary
  lib/std/
    toml.bl           # std.toml module
    semver.bl         # std.semver module
    core.bl           # std.core (ConversionError, Range, Handler)
    ...
```

When the compiler encounters `import std.toml`, it resolves to `<blinkc_dir>/lib/std/toml.bl` through the normal dependency resolution path.

#### All Stdlib is Implicit

All standard library packages — including web-service modules like `std.http`, `std.db`, `std.term` — ship with the compiler and are available as implicit dependencies. There is no tier-2 concept; `std.*` means "ships with the compiler, always available, version-locked."

This was decided by panel vote (3-2, see `decisions/stdlib-tier-architecture.md`). The rationale: a single-tier stdlib minimizes resolution complexity, eliminates "which is tier-1 vs tier-2?" confusion, and provides the best LLM code generation accuracy. If a module doesn't belong in stdlib, it should be an ecosystem package without the `std.*` prefix.

**Stagnation mitigation:** Frequent point releases for stdlib fixes, the edition system for API evolution (§11), and intentionally small stdlib surface area. Only include modules where there's a clear single "right" design.

```toml
# All implicit — injected by compiler, not written by user
std/core = { builtin = true }
std/fs = { builtin = true }
std/toml = { builtin = true }
std/semver = { builtin = true }
std/json = { builtin = true }
std/http = { builtin = true }
std/db = { builtin = true }
std/term = { builtin = true }
```

#### 10.7.1 Web-Service Module Classification

The following modules ship with the compiler as part of the standard library. Effect system types (`Request`, `Response`, `Headers`, `NetError`, `Template[C]`, `JsonValue`, `Serialize`, `Deserialize`) are compiler-known; convenience modules provide ergonomic layers above these primitives.

| Module | Description |
|--------|-------------|
| `std.json` | JSON codec — `parse`, `stringify`, `decode[T]`, `encode[T]`, `pretty`. Completes `@derive(Serialize)` |
| `std.http` | HTTP client convenience: builder patterns, retry, redirects, connection pooling |
| `std.http.server` | HTTP server: routing, middleware, error handling |
| `std.db` | Database effect API: `DB.Read`, `DB.Write`, `Template[DB]`, SQLite driver |
| `std.term` | Terminal styling, ANSI colors, TTY detection, cursor control |

#### Stdlib Errors

| Code | Error | Cause |
|------|-------|-------|
| E1050 | Stdlib not found | Compiler installation is incomplete or corrupted |
| E1051 | Stdlib version mismatch | Lockfile records a different stdlib version than current compiler |

```
error[E1050]: stdlib module not found
 --> app.bl:2:1
  |
2 | import std.toml
  |        ^^^^^^^^ module `std.toml` not found
  |
  = note: expected at /usr/lib/blink/lib/std/toml.bl
  = help: your Blink installation may be incomplete; reinstall with `blink self update`
```

### 10.8 Compilation Model

The Blink compiler uses an **emit-all** compilation model. When a module is imported, all of its items — both `pub` and non-pub — are included in the generated C output. The `pub` keyword controls Blink-level visibility, not C-level inclusion.

#### Why Emit-All

The compiler generates a single `.c` file per program. When module `auth.token` is imported, every function, type, and constant defined in `auth/token.bl` appears in the C output — including private helpers that pub functions call internally. This eliminates the class of linker errors where pub functions reference missing private dependencies.

```blink
// auth/token.bl

fn validate_format(token: Str) -> Bool {
    token.len() > 0 && token.contains(".")
}

pub fn verify(token: Str) -> Result[Claims, AuthError] ! Crypto {
    if !validate_format(token) {
        return Err(AuthError { message: "invalid token format" })
    }
    // ... verification logic
}
```

When another module writes `import auth.token.{verify}`, both `verify` and `validate_format` appear in the C output. The importer can call `verify` but **cannot** call `validate_format` — the compiler rejects it:

```
error[E1003]: item `validate_format` is private to module `auth.token`
 --> app.bl:5:12
  |
5 |     let ok = validate_format(raw)
  |              ^^^^^^^^^^^^^^^^ not accessible from this module
  |
  = note: `validate_format` is defined in `auth.token` but not marked `pub`
  = help: if this item should be accessible, add `pub` to its declaration
```

#### Visibility Enforcement

Visibility is enforced at **compile time** by the name resolution pass, not at the C level:

1. **Name resolution** builds a symbol table of all items and their declaring modules
2. When a function call or type reference crosses a module boundary, the resolver checks `pub` status
3. Non-pub items from other modules produce error E1003 (*Import Errors*, §10.5)
4. Items within the same module can access all sibling items regardless of `pub`

This means `pub` is a **hard guarantee**, not advisory. Code that compiles respects all module boundaries. The emit-all model is an implementation detail of the C backend, not a visibility loophole.

#### Symbol Naming

All symbols in generated C use **module-qualified names** to prevent collisions and aid debugging:

```c
// Generated from auth/token.bl
int blink_auth_token_validate_format(blink_string* token) { ... }
blink_result blink_auth_token_verify(blink_string* token) { ... }

// Generated from auth/session.bl
blink_session* blink_auth_session_create(blink_claims* claims) { ... }
```

The naming scheme is `blink_<module_path>_<item_name>`, where module path separators (`.`) become underscores. This applies to **all** items — pub and private alike. Benefits:

- **No collisions**: Two modules defining private `helper()` produce distinct C symbols
- **Debuggable**: gdb/lldb backtraces show which module a function belongs to
- **Separate-compilation ready**: Symbols are already globally unique when the compiler eventually moves to one `.c` per module

#### Relationship to Separate Compilation

Emit-all is the v1 compilation model. The intended v2 optimization is **separate compilation**: each module emits its own `.c` file, compiled to `.o`, then linked. The design choices made here — enforced `pub`, module-qualified symbols — ensure that the migration path from emit-all to separate compilation requires no language-level changes. User code written against v1 will compile identically under v2's separate compilation.

| Property | v1 (emit-all) | v2 (separate compilation) |
|----------|---------------|--------------------------|
| C files per program | 1 | 1 per module |
| Dead code | Included (gcc may optimize) | Excluded by linker |
| Incremental rebuild | Full recompile | Per-module |
| `pub` enforcement | Name resolution | Name resolution + linker |
| Symbol naming | Module-qualified | Module-qualified (unchanged) |

---

## 11. Metadata & Annotations

Annotations use the `@` prefix and are compiler-checked. They are not comments, not decorators, not optional. They participate in type checking, verification, optimization, and tooling.

### 11.1 Complete Annotation Reference

| Annotation | Target | Purpose | Checked by |
|------------|--------|---------|------------|
| `@src(kind: "ID")` | fn, type, module | Provenance link to requirement, design doc, issue, or compliance mandate. | `blink trace` tooling |
| `@requires(expr)` | fn | Precondition. Must hold when the function is called. | SMT solver (compile-time) or runtime assertion |
| `@ensures(expr)` | fn | Postcondition. Must hold when the function returns. `result` refers to the return value. | SMT solver (compile-time) or runtime assertion |
| `@where(expr)` | fn, type | Type-level constraint on generics or refinements. | Compile-time type checker |
| `@invariant(expr)` | type | Invariant that must hold for all instances of this type at all times. | SMT solver + runtime checks on construction/mutation |
| `@perf(constraint)` | fn | Performance contract. Benchmark assertion, not statically provable. | `blink bench --check-contracts` |
| `@capabilities(list)` | module | Hard ceiling on effects permitted in this module. | Compile-time effect checker |
| `@ffi("lib", "sym")` | fn | Declares a foreign function binding. | Linker (compile-time) |
| `@trusted(audit: "ID")` | fn | Records a claim the compiler assumes: an FFI binding matches its foreign code, or an audit-gated diagnostic is safe to suppress. `ID` must name a record in `audits.toml`. Never makes an `@ffi` fn `pub` (E0801). | Compile-time record check (`AuditRecordNotFound`); `blink audit` tooling |
| `@alt("ID", "desc")` | fn | Marks an alternative implementation. | Tooling (`blink alt list`, `blink alt select`) |
| `@verify(strategy)` | fn | Hints to the SMT solver about verification strategy. | Verification engine |
| `@derive(Trait, ...)` | type | Auto-generate trait implementations. Compiler-known traits only in v1: `Eq`, `Ord`, `Hash`, `Debug`, `Clone`, `Display`, `Serialize`, `Deserialize`. | Compile-time codegen |
| `@allow(WarningName, ...)` | fn | Suppress specific compiler warnings within the annotated function. Takes PascalCase warning names (e.g., `UnrestoredMutation`, `IncompleteStateRestore`). Function-level override of `blink.toml` `[lints]` config. See §4.16.8. | Compiler diagnostic filter |
| `@deprecated(since, removal, replacement, fix)` | fn, type | Edition-aware deprecation with structured migration. Fields: `since` (edition, required), `removal` (edition, optional), `replacement` (qualified name, optional), `fix` (`"replace"`/`"inline"`/`"manual"`, optional). Emits W2000 when current edition < `removal`, E2001 when current edition >= `removal`. Machine-applicable fixes in structured diagnostics when `fix` is `"replace"` or `"inline"`. See §8.16.2. | Compiler warning/error (edition-gated) |

#### Canonical Ordering

`blink fmt` enforces a deterministic annotation order. No style debates.

```blink
@module("auth")                          // 1. module declaration
@capabilities(DB, Crypto)             // 2. capability budget
@src(req: "AUTH-001")                 // 3. provenance

@src(req: "AUTH-001")                 // 4. provenance (on function)
@requires(email.len() > 0)           // 5. preconditions
@ensures(result.is_ok() => result.unwrap().token.is_valid())  // 6. postconditions
@perf(p99 < 200ms)                   // 7. performance contracts
@deprecated(since: "2026", removal: "2028", replacement: "login_v2", fix: "replace")  // 8. deprecation
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The ordering: `@module` > `@capabilities` > `@derive` > `@src` > `@requires` > `@ensures` > `@where` > `@invariant` > `@perf` > `@ffi` > `@trusted` > `@alt` > `@verify` > `@allow` > `@deprecated`.

Rationale: metadata about the container (module, capabilities) comes first. Then provenance (why does this exist?). Then contracts (what must be true?). Then operational concerns (performance, FFI). Then lifecycle (alternatives, deprecation).

### 11.2 Performance Contracts (`@perf`)

Performance contracts are **benchmark assertions**. They are explicitly NOT statically provable — the SMT solver does not attempt to verify them. They exist in a separate verification domain from `@requires`/`@ensures`.

```blink
@perf(p99 < 200ms)
@perf(memory < 50mb)
@perf(throughput > 1000rps)
pub fn process_batch(items: List[Item]) -> Summary ! DB, IO {
    // ...
}
```

#### What `@perf` Is

- A **benchmark target** checked by `blink bench --check-contracts`
- A **CI gate** — the benchmark runner fails if the constraint is violated
- A **regression detector** — performance changes are caught the same way type errors are
- A **documentation signal** — developers and AI know the performance expectations from the signature

#### What `@perf` Is Not

- Not a compile-time guarantee. The compiler does not attempt to prove performance properties.
- Not a runtime enforcement mechanism. `@perf` does not insert timing checks into production code.
- Not a contract in the formal verification sense. It will never be fed to the SMT solver.

#### Supported Constraints

| Constraint | Meaning | Example |
|------------|---------|---------|
| `p50 < Xms` | 50th percentile latency | `@perf(p50 < 50ms)` |
| `p95 < Xms` | 95th percentile latency | `@perf(p95 < 150ms)` |
| `p99 < Xms` | 99th percentile latency | `@perf(p99 < 200ms)` |
| `memory < Xmb` | Peak memory usage | `@perf(memory < 50mb)` |
| `throughput > Xrps` | Requests per second | `@perf(throughput > 1000rps)` |
| `allocs < N` | Heap allocations per call | `@perf(allocs < 100)` |

#### Usage in CI

```sh
blink bench                     # run all benchmarks
blink bench --check-contracts   # run and fail if any @perf violated
blink bench --module auth       # benchmark a specific module
blink bench --json              # structured output for CI integration
```

Example CI failure:

```
$ blink bench --check-contracts

FAIL  auth.login
  @perf(p99 < 200ms) — measured p99: 342ms (exceeded by 142ms)
  Benchmark: 10000 iterations, 3 warmup rounds

PASS  auth.check_rate
  @perf(p99 < 50ms) — measured p99: 12ms

1 of 2 performance contracts violated.
```

### 11.3 Provenance (`@src`)

Provenance links code to the external artifacts that justify its existence. Four categories are supported:

| Kind | Purpose | Example |
|------|---------|---------|
| `req` | Requirement document | `@src(req: "AUTH-001")` |
| `design` | Design document or RFC | `@src(design: "RFC-2026-07")` |
| `issue` | Issue tracker reference | `@src(issue: "GH-1234")` |
| `compliance` | Regulatory or compliance mandate | `@src(compliance: "SOC2-CC6.1")` |

Multiple `@src` annotations can stack:

```blink
@src(req: "AUTH-001")
@src(design: "RFC-2026-07")
@src(issue: "GH-1234")
@src(compliance: "SOC2-CC6.1")
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

#### Provenance on Types

Types can carry provenance too — useful when a type exists because of a specific requirement:

```blink
@src(compliance: "PCI-DSS-3.4")
@invariant(self.value.len() == 16)
pub type MaskedCardNumber {
    value: Str
}
```

#### Provenance on Modules

Module-level provenance applies to the entire module:

```blink
@module("auth")
@src(req: "AUTH-001", "AUTH-002", "AUTH-003")
@src(design: "RFC-2026-07")

// All functions in this file inherit the module-level provenance context
```

#### Tooling Integration

Provenance is queryable through the compiler-as-service API and the CLI:

```sh
blink trace AUTH-001              # find all code linked to AUTH-001
blink trace --reverse auth.login  # find all artifacts linked to auth.login
blink trace --coverage            # report which requirements have implementing code
blink trace --orphans             # find code with no provenance links
blink trace --stale               # find provenance links to closed/deleted issues
```

The `--coverage` report is designed for compliance audits:

```
$ blink trace --coverage

Requirement Coverage:
  AUTH-001  4 functions, 2 tests    COVERED
  AUTH-002  2 functions, 1 test     COVERED
  AUTH-003  0 functions, 0 tests    MISSING
  PAY-001   3 functions, 0 tests    PARTIAL (no tests)

Coverage: 2/4 fully covered (50%)
```

Provenance is metadata — it has zero runtime cost, zero imblink on compilation, and zero interaction with the type system. It exists purely for traceability and tooling. But it is compiler-tracked, meaning the compiler knows about it, stores it in the AST, and exposes it through the query API. It is not a comment that can silently drift.
