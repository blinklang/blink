# Blink Changelog

Single source of truth for release history. `blink llms` and `blink llms --full` both append this file after the reference text, and every release version is indexed as a topic (e.g. `blink llms --topic v0.36`). **Edit only here** — `llms.md` and `llms-full.md` hold only a `## Recent Changes` stub pointing at this file.

## What's New (v0.52.0)

- **Comparison operators on structs, enums, and core types.** `==`, `!=`, `<`, `>`, `<=`, `>=` now desugar to trait dispatch instead of emitting raw C. `@derive(Ord)` synthesizes a lexicographic comparison for a struct or enum (and auto-includes `Eq`, since `Ord: Eq`), so `a < b` on your own types works; `@derive(Eq)` alone gives you `==`/`!=`. A new prelude enum `Ordering` (`Less`/`Equal`/`Greater`) is auto-imported via `std.traits` and is what `.cmp(other)` returns. `Instant`/`Duration` compare by their nanosecond value and `Bytes` compares by content. Previously, comparison operators did **no** operand type-checking at all — `now > 0` (an `Instant` vs an `Int`), `"str" > 5`, and `Point == Point` all passed `blink check` and then emitted invalid C. They now type-check operands and reject mismatched or unordered ones with **E0300** (the enum-vs-int-literal exception is preserved). `time.read()` and `time.sleep()` are now typed (`Instant`/`Void`), so `time.read() > 0` errors at check time instead of leaking into bad C.
- **`@expect_panic` and per-case `for_each` results.** A test using `testing.for_each` now emits a nested `{label, status}` record per case under its parent test (a `"cases":[...]` array in the `--test-json` stream), so consumers can attribute pass/skip/fail to individual cases instead of seeing one record for the whole loop. Human output names a failing case as `test <name>::case[<label>] ... FAIL`.
- **`where`-clauses parse on `impl` blocks.** `impl[T] Trait for X where T: Bound` (a comma list of `Ident: Bound (+ ...)` constraints before the `{`) now parses and round-trips through the formatter. This is parse-and-store only for now — bound enforcement is follow-up work.
- **`--emit per-module-dir` is a documented flag.** `blink build <file.bl> --emit per-module-dir <outdir>` (or `-o <outdir>`) is the stable, documented surface for per-module C emission, replacing the hidden `__emit-per-module` subcommand (kept one release as a byte-equal deprecation alias).
- **`blink audit --ffi` gains a bytes-bridge section.** The audit now reports every `Bytes.with_ptr` call site — the raw-byte FFI crossings of the `libc.*_bytes` wrapper family — under a `bytes-bridge` category (keyed `"byte-pin"`), with a matching `byte_pin` count in the summary. The walker now descends into function bodies (blocks, match arms, if/else, loops, `with`-blocks, closures, args, ranges, `await`) rather than only inspecting top-level signatures.

## Fixes (v0.52.0)

- **String interpolation no longer truncates at 4095 bytes.** Interpolated strings were built into a fixed `char[4096]` buffer, silently cutting off any longer result. They now size the buffer exactly (spec §2.4: interpolation is unbounded concatenation), so large interpolations come through whole. A `match` over an interpolated scrutinee now binds a temp so side-effecting interpolants are evaluated once, not once per arm tested, and a top-level `Map[Int,Int] = Map()` now correctly selects integer key-ops.
- **`Result` construction no longer drops the other arm's type.** Three related miscompiles fixed: a function returning `Result[Struct, Int]` (or `Result[Void, Int]`) that constructs `Ok(...)` used to name its error carrier `_str` while declaring `_int`, producing uncompilable C; a `let x: Result[A, B] = Err(...)` where one side was a user struct emitted a malformed `_void` carrier and broke the match binding. Both now recover the declared carrier from the function/binding type.
- **`assert_eq` on `Option`/`Result` with struct or string payloads.** `assert_eq` over an `Option`/`Result` whose payload is a struct used to `memcmp` the raw payload bytes — comparing `Str` fields by pointer, so two content-equal runtime-built strings compared unequal. It now compares field-wise (`blink_str_eq` for strings, scalar `!=` for scalars), tag-first and only over the active arm, so the inactive arm's junk bytes are never read.
- **Cross-module `@derive` methods now link.** Derived `eq`/`cmp`/`clone`/`to_json`/`debug` symbols are type-owned, so a call site in another module now builds the C name from the type's module prefix instead of falling through to a bare, unprefixed symbol that failed to link.
- **Wrong-arity variant constructors error (E0300).** Constructing a qualified `Enum.Variant(...)` with the wrong number of arguments is now arity-checked, mirroring the bare-identifier path, instead of slipping past typecheck into broken C.
- **`testing.skip(reason)` works qualified.** A qualified `testing.skip(reason)` used to route to a no-op stdlib function and be silently swallowed (letting the rest of the test run and report failed); it now behaves as the test-skip intrinsic like bare `skip(reason)`.
- **Variant-name / enum-type shadowing in qualified construction.** `Enum.Variant(...)` where the qualifier name also names a variant of another enum used to resolve through value inference and pick the wrong enum; it now resolves the qualifier as a type first when no local of that name exists.
- **An uncaught panic in a test no longer kills the whole test binary.** A panic in a test body used to fall through to `exit(1)`, dropping that test's result and every later test. The test runner now records it as a failure and continues (non-test builds are unchanged). The human `FAIL` render also omits a bogus `(line 0)` when no line is known.
- **W0551 (UnrestoredMutation) now fires function-scoped per §4.16.7.** It was gated per-block, so a function whose save/restore lived in one block and whose unsaved broad-write lived in a sibling block did not warn (under-detection). It now fires whenever the function exhibits any save/restore pattern.
- **W0310 (Raw() parameterization bypass) is suppressed by `@trusted`, not `@allow`.** The warning was emitted unconditionally with help text wrongly pointing at `@allow`; per spec §3b the sanctioned suppressor is `@trusted(audit: "ID")` (an auditable trail), and the emit is now gated on `@trusted` with corrected help.
- **`blink audit --ffi` covers multi-file programs.** It only walked top-level functions and mis-attributed files; it now walks all four `Program` sublists and attributes each finding to its own source file.
- **Duplicate diagnostics are deduplicated.** A let-RHS method call evaluated by both the name-resolution and typecheck passes no longer reports its error twice; dedup keys on the full severity/code/location/message tuple so genuinely distinct diagnostics survive.

## Breaking Changes (v0.51.0)

- **Enums are no longer interchangeable with `Int`.** An enum value used to flow freely into and out of `Int` positions — you could assign an enum to an `Int` binding, pass it to an `Int` parameter, or return it where `Int` was declared, and vice versa. Per the nominal-typing decision (§3) an enum is now its own distinct type at `let`, argument, and return positions: those interchanges are type errors. Convert explicitly with `value.to_int()` and `EnumType.from_int(n)`. (`==` between an enum and an int literal still works, so existing comparisons are unaffected.) Separately, **positional enum-variant payloads (`Variant(Type)`) are now retained and round-tripped** instead of being parsed and discarded — declaring a data variant and matching `Variant(x)` to bind its payload both work.
- **`ffi.scope()` is now a `with`-resource, not a closure call.** The off-spec free-function form `ffi_scope(fn(scope) { ... })` has been removed. A scope is a `Closeable`: bind it with `with ffi.scope() as scope { ... }` (§9.1.1) and its allocations are freed when the block exits (normal return, `?`, or any other exit path). Binding it directly — `let s = ffi.scope()` — is rejected with **E0819**, because outside a `with` block there is nothing to free the arena and every allocation would leak. Methods on the bound scope are unchanged: `scope.alloc[T]()`, `scope.alloc_n[T](n)`, `scope.cstr(s)`, `scope.take(ptr)`.

## What's New (v0.51.0)

- **Polymorphic trait impls on `List[T]` now compile.** `impl[T] Trait[T] for List[T]` — a single impl covering the built-in list for every element type — used to parse but be rejected at typecheck with **E0908** ("write a separate impl per concrete type"). It now compiles: each concrete `List[T]` you actually use is monomorphized from the one polymorphic impl, and the full trait-contract checks (required methods, arities, parameter/return/effect match) run against the poly impl just as they do for a concrete one.
- **Binary syscall wrappers in `std.libc` + `std.io.read_fully`.** New `Bytes`-oriented libc wrappers that surface real errno values instead of folding everything into a sentinel: `read_bytes(fd, max)`, `recv_bytes(fd, max)`, and `getentropy_bytes(n)` return `Result[Bytes, Errno] ! IO`; `write_bytes(fd, data)` and `send_bytes(fd, data)` return `Result[Int, Errno] ! IO` (the count actually transferred). A short read/write is normal — it comes back as `Ok` with a shorter `Bytes` or a smaller count; only a `-1` syscall return is `Err(Errno(code))`. `std.io.read_fully(fd, n)` is a pure-Blink combinator that loops `read_bytes` until exactly `n` bytes are read or EOF. Calling a name that isn't a `std.libc` member now gets a did-you-mean hint.
- **`Errno` — a transparent, zero-cost newtype over `Int`.** `pub type Errno { Errno(Int) }` (`import std.errno`) is the error arm of the `*_bytes` wrappers. It is nominally distinct from `Int` — so a `write_bytes -> Result[Int, Errno]` can never confuse the count-written with the error code the way a bare `Result[Int, Int]` would — yet carries no box or tag: in emitted C a `Result` whose error arm is `Errno` holds a bare `int64_t`, including when nested as `Option[Errno]`. This is the first instance of the general transparent-newtype rule (single variant, single `Int` payload → lowered to `int64_t`). Extract the code by matching `Errno(rc)`.
- **`@expect_panic` test sugar.** `@expect_panic` on a `test` asserts the body panics; `@expect_panic("substring")` additionally requires the panic message to contain the given text — the annotation form alongside the existing `assert_panics { ... }` block.
- **Unqualified method calls that hit two traits now error clearly (E0522).** When `x.m()` resolves to a method `m` defined by two or more traits the receiver's type implements, the compiler can't tell which you meant and emits **E0522** instead of silently picking one. Disambiguate with the qualified escape hatch `Trait.m(receiver)`, which now works.
- **Bare int literals coerce to the sized-int operand in arithmetic.** `a * 2` where `a: I32` used to reject the `2` as a plain `Int`. A bare integer literal now takes the sized-int type of the other operand, so mixing literals with `I8`/`I16`/`I32`/`U8`/… in arithmetic just works (non-literal `Int` variables still error — this is a literal-only carve-out).

## Fixes (v0.51.0)

- **Escape analysis now runs on `blink check`, `blink build`, and the LSP — not just `blinkc`.** Use-after-free detection (E0601/E0700) was wired only into the low-level `blinkc` path, so `blink build` happily compiled and shipped binaries that returned pointers to freed scope/arena memory — exit 0, no diagnostic. The escape pass is now single-source and runs on every production surface. Two false-positive holes were closed in the same pass: a pure string literal no longer trips E0700, and the E0601 with-expr tail-capture path is now covered (catching alias-escapes the old codegen-side check missed).
- **Integer divide/modulo by zero is now a catchable panic, not `SIGFPE`.** `x / 0`, `x % 0`, and the `INT64_MIN / -1` overflow used to raise `SIGFPE` and kill the process with exit 136 — which, under the test runner, took sibling tests down with it. These now raise an ordinary catchable Blink panic (so `assert_panics` can catch them), including at trap sites resident in the stdlib archive.
- **Source paths containing `%` no longer garble or crash the panic message.** A file path with a `%` in it was fed through a format string in the div/mod/shift/overflow guard messages, corrupting the output (or crashing). Paths are now percent-escaped before formatting.
- **Enum and variant resolution fixes.** Two distinct enums that share a variant name now resolve correctly via the match scrutinee's type instead of colliding. And a user variant named like a builtin (`Char`, `Ok`, `Err`, `Some`) no longer poisons cross-module privacy checks or mis-routes its payload through the wrong codegen carrier.
- **Wrong-arity variant constructors error instead of emitting bad C (E0300).** Constructing a data variant with the wrong number of arguments used to slip past typecheck and produce broken C; it now reports **E0300** at the call site.
- **`let r = { ...; if ... }` threads the block's tail value.** A `let` bound to a block expression whose tail was an `if` (or other value-producing expression) declared the binding as `const void r = 0` and discarded the value. The binding now takes the real tail value.
- **Statement-position `match` no longer drops its value.** A `match` in block- or arm-tail position used to silently discard the arm values; it's now normalized so the value is threaded through. Relatedly, `Bytes.with_ptr` now accepts a bare block-bearing body.
- **`List[Map[K,V]]` keeps its value type.** Pushing to, or doing `.get().unwrap()` on, or storing a struct value into a `List[Map[K,V]]` used to lose the map's value type `V` and miscompile. The value type is now threaded through. Also fixed: `io.*` output inside `with arena { }` no longer false-flags E0700, and a daemon poll race that reported a stale `changed: 0`.
- **A cleanup body that panics during an `assert_panics` unwind surfaces as a secondary `E0824` warning** — the original panic is still preserved and reported; the cleanup panic no longer silently vanishes.

## Breaking Changes (v0.50.0)

- **Module-qualified calls now respect visibility (E1003).** A non-`pub` free function in another module used to be reachable through the qualified form — `mod.fn()` or the bare value reference `mod.fn` — even though the unqualified form was correctly rejected. The spec's visibility rule is form-agnostic (§6.3.4, §7), so this was an enforcement gap. All three forms now route through the same private-access check and report identically (a private type reached via `mod.Type` now says "private type", not "private function"). If you were relying on the qualified loophole, mark the target `pub`. (`Type.method()` is unaffected — it resolves through method resolution, not the private-import surface.)
- **`blink test --test-json` output now matches the spec §8.10 NDJSON shape.** Consumers of the machine-readable test stream see renamed keys: top-level `tests` → `results`, per-record `fail` → `failed`. `assert_eq` failures now carry separate `expected` (RHS) and `actual` (LHS) values instead of a single combined message, and every record plus the summary now reports `duration_ms` (monotonic clock). Re-point any tooling that parsed the old keys.

## What's New (v0.50.0)

- **`assert_panics` — assert that a block panics.** A fifth test assertion, recognized by the compiler: `assert_panics { risky() }` passes only if the block panics, and `assert_panics(matching: "divide by zero") { ... }` additionally requires the panic message to contain the given substring. The block is valueless and test-only — nothing (`PanicInfo`/`Result`/`Bool`) is ever bound, so `panic: Never` stays sound. Resources opened with `with`/`Closeable` inside the block are still closed and transactions still roll back on the caught panic. Diagnostics: **E0831** (block returned without panicking, including a `?`-propagated `Err`), **E0832** (message lacks the expected substring — shows expected + full actual + origin), **E0833** (used outside a test), **E0834** (lexically nested). The closure-call form (`assert_panics(fn() { ... })`) is rejected with a guided message pointing at the block form.
- **`.unwrap()` / `.unwrap_err()` panics now show the value.** Panicking on `.unwrap()` of an `Err` (or `.unwrap_err()` of an `Ok`) now renders the offending arm via `Display`: `panic: unwrap called on Err: <rendered> at file:line`. `Option.unwrap()` on `None` is unchanged.

## Fixes (v0.50.0)

- **Installed-toolchain ABI mismatches are caught before they corrupt memory (E0840).** A stdlib archive installed under `share/blink/` was linked into your binary with no check that it matched the linking compiler. When a fresh compiler emitted a translation unit against an archive built by an older toolchain, boxed values were read at the wrong struct offsets — surfacing as garbage reads and `SIGSEGV` at runtime (e.g. an `Option[Row]` from `db.query_one` rendering as `(null)` then crashing). The archive now carries an identity stamp (both shared header SHAs + compiler SHA + version); a mismatch (or a missing stamp) is rejected at link time with **E0840** instead of producing a corrupt binary.
- **`blink update` now re-stamps `blink-version` in `blink.toml`.** The version rewrite searched for the legacy `pact-version` field, so a modern manifest (what `blink init` writes) never matched and the rewrite was a silent no-op — leaving the toml stale while the lockfile bumped. It now updates the live `blink-version` field, and only rewrites when the content actually changes.
- **`std.time` Duration/Instant constructors are usable across modules.** The `Duration` and `Instant` types were `pub`, but their 17 constructor/combinator free functions were module-private — so another module could name the types but not construct or operate on values, tripping `E1003`. All 17 are now `pub`.
- **No more phantom `E1003`/`W0603` pointing into `lib/std`.** Declaring a non-`pub` top-level function whose name collided with a parameter or local used inside a stdlib function made the resolver flag the stdlib's own local use as a cross-module private access — emitting nonsensical errors and shadow warnings pointing at code you never wrote. The private-access check now only applies when the name resolves to a real top-level binding, and the shadow warning is keyed on module identity.
- **Annotated test headers give one clean error (E0515).** `test "x" -> Result[Void, Str] { ... }` used to produce a generic `UnexpectedToken` when the parser choked on the `->`. It now reports a single **E0515** at the arrow and recovers.
- **One error per broken interpolation (E1106).** A second unparseable `{...}` in the same string literal used to be swallowed silently (the recovery walked past it). Each broken interpolation in a string now gets its own **E1106**.
- **Unresolved methods on a known type error at typecheck (E0505).** Calling a method that doesn't exist on a known struct/enum used to slip through typecheck and only get caught later by a codegen fallback, which named the wrong receiver (`type Void`). It now errors at typecheck naming the real receiver type; the `.display()`-with-no-`impl Display` case carries an actionable `impl Display for <Type>` hint.
- **`StringBuilder.write_char` accepts a `Char`.** Previously `Str`-only, `write_char` now also takes a `Char` (lowered through the same path as `Char.fmt`). The formatter also no longer drops `: Bound` from type-parameter lists in `fn`/`type` definitions.
- **`if`/`match` producing an `Option`/`Result` derive the carrier from the branches.** An `if`/`match` expression yielding an `Option[T]`/`Result[T, E]` declared its C temporary from the enclosing function's return type instead of what the branches actually produce. `blink check` passed but the emitted C carried the wrong element type — real miscompiles surfaced from libraries. The carrier is now taken from the branch that carries a concrete payload.
- **`?` in a test body requires `Display` on the error (E0514).** A `?` in a test body renders the propagated error via `Display`, so `Display[E]` is required at each `?` site (spec §2.20 / §3c.2) — the gate is now wired and emits **E0514** when missing. A custom error implementing `Display` now actually renders through it in the runner instead of printing a `<Type>` placeholder.
- **Parser no longer OOMs on a malformed string interpolation.** A bare-brace interpolation containing two-or-more escaped-quote string literals separated by a comma (e.g. `"{\"a\",\"b\"}"`) drove the parser into unbounded allocation. Recovery now balances nested strings, and a no-progress backstop guarantees malformed input can't spin.

## What's New (v0.49.0)

- **`Display` trait — make your type printable.** A new prelude `Display` trait declares one required method, `fn fmt(self, sb: StringBuilder)`. You write `fmt` to render into a `StringBuilder`; the compiler synthesizes a sealed `fn display(self) -> Str` for every impl (it allocates a fresh `StringBuilder`, calls your `fmt`, and returns the string), so `x.display()` works on any type that implements `Display` without you writing it. `Display` is built in for `Int`, `Float`, `Bool`, `Char`, and `Str` (`42.display()` → `"42"`, `true.display()` → `"true"`), and works as a generic bound: `fn show[T: Display](x: T) -> Str { x.display() }`. Because `display()` is sealed (a derived view of `fmt`), writing your own `fn display(...)` inside an `impl Display` is rejected with **E0731** — implement `fmt` and delete the override.
- **Polymorphic impl headers now parse (but aren't compilable yet).** `impl[T] Trait[T] for Recv[T]` — type-parameter binders after `impl` and type arguments on the receiver — now parse and round-trip through the formatter (spec §3.6). Codegen support has not landed, so any impl carrying binders or receiver type arguments is rejected at typecheck with **E0908** (write a separate impl per concrete type for now); **E0909** flags a declared binder that never appears in the header's type positions. This is groundwork plus a clear error, not a usable feature yet.

## Fixes (v0.49.0)

- **A broken `"...{expr}..."` interpolation now gives one clear error (E1106).** An unparseable interpolation expression inside a double-quoted string used to emit a cascade — one generic parse error plus a stray-token error for every following token. It now emits a single **E1106** anchored at the opening `{`, with help pointing at the `\{` escape and raw `#"..."#` strings (where braces are literal). Common when pasting SQL or shell snippets with braces into a string.
- **`blink.toml [lints]` severity overrides are honored again.** Three stacked bugs kept `[lints]` overrides (spec §4.16.8) from working: the standalone `blinkc` binary never loaded them at all; code-keyed overrides (the documented `W0551 = "error"` form) never matched because lookup was by PascalCase name only; and the manifest path was hardcoded to the cwd instead of the compiled file's package root. All three are fixed. `--strict-struct-layout` now also escalates even when no manifest exists, matching its "flag always wins" intent.
- **W0550 / W0551 mutation diagnostics match the spec.** Both now emit at `warning` by default (the spec default; `error` only via `blink.toml [lints]`) instead of hard errors, W0551's message no longer contradicts its own firing condition, and both now carry the spec-mandated `= note:` lines naming the relevant write-set.
- **Chained methods on an inline `.unwrap()` / `.unwrap_err()` work.** An inline receiver like `mk(1).unwrap().foo()` (where `mk` returns a `Result`) lost the OK/Err inner type and defaulted to `Int`, so the chained call failed with a bogus "unresolved method on type Int" — in plain non-test code, not just edge cases. The inner type is now recovered correctly, and a missing `Bytes` case was added so `Result`/`Option` of `Bytes` unwraps correctly too.
- **Three codegen bugs where `blink check` passed but the emitted C was wrong.** (1) A monomorphized generic function calling another monomorphized function could emit a conflicting implicit `int()` declaration; forward declarations are now emitted for the whole pass first. (2) A `with ... as` block inside a generic function produced "unknown type name `__blink_cl_state_*`"; the cleanup-state typedef is now flushed before the body. (3) A let-bound `if/else` whose branches produce a heap value (`Bytes`, `List`, `Map`, `StringBuilder`) or a struct declared the binding as `const void x = 0` and discarded the branch value; the binding now takes the real value type.

## Breaking Changes (v0.48.0)

- **`+` on `Str` is now rejected (E0521).** Concatenating strings with `+` (`"a" + "b"`, or even `"x" + 1`) previously type-checked and silently compiled to a string concat. Per §02 (5-0 vote) `+` does not work on `Str` — it encourages O(n²) loops and is ambiguous with numeric `+`. Use interpolation `"{a}{b}"` or `.concat()` instead. The rejection now fires everywhere a `Str`-`+` could appear, including interpolation parts (`"{a + b}"`) and statement-position `match`/loop bodies that previously slipped through to a broken C compile.

## What's New (v0.48.0)

- **`@derive(Debug)` for structs and enums.** `@derive(Debug)` now auto-generates `fn debug(self) -> Str` (spec §3.6). Structs render as `Point { x: 5, y: 10 }`, unit enum variants as `Green`, data variants positionally as `Rect(3, 4)`; `Str` fields are quoted and escaped, and user-type fields recurse through their own `debug()`. A field whose user-type does not itself derive `Debug` is rejected at typecheck with E0520. **Container fields now render** too: `List` as `[a, b]`, `Option` as `Some(x)`/`None`, `Map` as `{k: v}` — conditionally on the element/key/value types being `Debug` (Map checks both `K` and `V`), with `[]`/`{}` for empties. v1 renders one container level; a nested container is a hard E0520 rather than a silent placeholder.

## Fixes (v0.48.0)

- **Module-global arguments are now type-checked.** A top-level `let` registered with no resolved type (`TYPE_UNKNOWN`), so passing a module global to a built-in that checks element types (List/Map/Set, `Str`) skipped the check entirely — bad arguments passed `blink check` and compiled to broken C. Globals now resolve their declared type at registration (annotation, then named type, then scalar-literal RHS), so the existing argument checks fire.
- **Assigning an int literal to a sized-int target now works.** `let x: I8 = -1` compiled but `x = -1` (and `x += 5`) was rejected with "cannot assign Int to I8". The assignment handler now mirrors the `let`-binding carve-out — gated on a literal RHS, so non-literal `Int` variables and incompatible types (e.g. `Str`) still error.
- **Unannotated closure bodies in List HOFs are now type-checked.** A genuinely-wrong body in an unannotated closure passed to `map`/`filter`/`for_each`/`any`/`all`/`find`/`fold` (e.g. using a `Str` element arithmetically) previously slipped past typecheck and surfaced as a raw C-compiler error. The body is now bound to the element/accumulator types the HOF supplies and walked once, producing a `TypeError` at compile time.
- **No more spurious "unknown method" warning (W0501) on `@derive`-generated methods.** Calling a derived method (`clone`, `eq`, `hash`, `debug`, `to_json`, `from_json`) emitted "unknown method — may fail at compile time" because derived names were only registered in codegen, after typecheck. They are now registered during name resolution; genuinely unknown methods still warn.
- **No more spurious "unrestored mutation" warning (W0551).** Seeding a local from a module-global sentinel (`let mut x = SENTINEL`) followed by a broad-write call was misread as an unrestored save/restore and flagged at every such call site. W0551 now requires real restore evidence (a `global = saved_local` assignment), so the false positive is gone while genuine unrestored-mutation detection is preserved.
- **`process.run()` no longer deadlocks on chatty children.** A child writing more than a pipe buffer's worth to both stdout and stderr could hang: the runtime drained stdout to EOF before reading stderr, so the child blocked on `write()` while the parent blocked on a `read()` that never saw EOF. Both descriptors are now drained concurrently via `poll()`.

## Breaking Changes (v0.47.0)

- **Bare calls to stdlib free functions now require an explicit `import` (E0504).** `list_map`, `parse_int`, `str_trim`, and every other stdlib *free function* previously resolved with no import because the prelude auto-loaded whole stdlib modules into name scope. Per §3.2.3 the prelude provides only compiler-known types, constructors, and traits — not library free functions. A bare call to one now errors with a hint naming the import to add. **Built-in method dispatch is unaffected** — `"hi".trim()`, `[1,2].map(...)`, etc. still need no import; only the standalone free-function forms changed.

## What's New (v0.47.0)

- **Built-in method-surface traits are now sealed (E0907).** `StrOps`, `BytesOps`, `StringBuildOps`, `Sized`, `Contains`, `ListOps`, `MapOps`, `SetOps`, and `Joinable` are prelude traits that back built-in method dispatch on `Str`/`List`/`Map`/`Set`/`Bytes`. User code may neither redefine one nor write an `impl` of one — both are now a hard error. (Naming one in a generic bound is still legal.)
- **`List.contains()` and `Map.contains()`.** `List.contains(x)` does a per-element linear scan for primitive element types (`Int`/`Bool`/`Str`/`Float`); `Map.contains(k)` mirrors `contains_key`. Struct/enum/nested-collection list elements remain unsupported (`==` on boxed values is pointer identity today).
- **A redundant selective import of a prelude trait no longer warns `UnusedImport`.** Importing a name that resolves to a prelude module is a no-op rather than dead code. Mixed and bare imports still warn.

## Fixes (v0.47.0)

- **Arguments are now type-checked across the board.** Built-in container methods (`[1,2,3].contains(2.0)`, `"hi".contains(5)`, `Map[Str,Int].get(5)`), user struct/enum trait methods (`p.add_to(2.0)` where `add_to` expects `Int`), `Bytes` intrinsic methods (`b.push(2.0)`), and explicitly-annotated closure params/returns of List HOFs (`map`/`filter`/`find`/`for_each`/`any`/`all`/`fold`) and `Bytes.with_ptr` all validate their arguments now. Mismatches previously rode the codegen-intrinsic path with an implicit C cast and could segfault; they now error at compile time with E0300.
- **`Bytes.new()` is now typed.** `let b = Bytes.new()` previously resolved to an unknown type, silently disabling every downstream `b.method(...)` argument check. It now resolves correctly.
- **Type-changing `map(...).collect()` keeps the new element type.** `map(fn(T) -> U).collect()` previously lost `U` and mistyped the result as `List[T]` — rejecting correct code and accepting wrong assignments. `map` now derives the element type from the closure's declared return (flat names; nested generics still fall back to `List[T]`).
- **Trait methods on stdlib-imported types now resolve in codegen.** A method called on a `mod.Type`-typed value (e.g. `net.TcpSocket`) passed `check` but failed `build` with `UnresolvedMethod` because the impl was registered under the bare type name. The qualified→bare strip is now centralized.
- **`Option[T]`'s type argument is preserved through tuple and enum-variant C lowering.** A bare `None` in a struct-style enum field, a `Result[(T, U), E]` destructured through `?`, and a monomorphized generic fn returning a tuple containing `Option[UserEnum]` all previously dropped `Option`'s argument (emitting `blink_Option_int`/`void`), passing `check` but failing the C compile with references to types the user never wrote. All now route through the canonical carrier name.
- **A struct-returning call in an `if`-expression branch no longer emits `const void`.** `let c = if cond { make(1) } else { make(0) }` (where `make` returns a struct) discarded both branch values and broke downstream member access. The same gap is closed for `match`-arm tails and nested `if`-expr branches.
- **`Bytes` intrinsic methods validate their `Int` offset/value arguments** — matching the List/Str/Map/Set treatment.

## What's New (v0.46.0)

- **Bare struct-style enum-variant construction.** `Variant { field: x }` now works without an enum qualifier, mirroring the long-supported bare tuple construction and bare struct-style *patterns*. Resolution is hint-first (binding annotation, return type, fn-arg param, or `Ok`/`Err`/`Some` carrier), falling back to a global-unique variant lookup. Bare and qualified forms emit byte-identical C.
- **New diagnostic E0518 (NameCollision)** — a struct type whose name equals an enum variant name is now a declaration-time error (bare construction would be ambiguous). Narrow: two enums may still share a variant name.
- **New diagnostic E0519 (AmbiguousConstruction)** — a bare `Variant { ... }` naming a variant that exists in more than one enum, with no expected type to disambiguate, is now a use-site error instead of silently picking one. (Replaces the prior silent struct-wins miscompile hazard.)

## Fixes (v0.46.0)

- **Call arguments are now type-checked.** Passing the wrong shape (e.g. `List[Int]` where `List[(Str, T)]` is expected) previously compiled and segfaulted at runtime; calls now verify each argument against its parameter type. (`resolve_type_ann` gained a Tuple case; `types_compatible` gained tuple recursion. Alias-underlying refinements and integer literals stay compatible.)
- **Bare `None`/`Some`/`Ok`/`Err` now adopt the correct carrier from context** — struct/enum fields, tuple slots, struct-literal fields, call arguments, method-call arguments, and generic-fn parameters. Previously these defaulted to `Option_int`/`Result_int_str`/`Option_void` and failed at C-compile time (errors the type-checker couldn't catch).
- **`Option[T]`/`Result[T,E]` typed parameters in methods and generic functions** no longer lower to a bare `void`; they emit their proper carrier C type.
- **Generic `Result[T, E]` infers `T` from the `Err` position** of a `Result` argument, not just the `Ok` position. `handle(Err(SomeErr { ... }))` against `handle[E](r: Result[Int, E])` now compiles.
- **Tuple carrier element tags are canonicalized at the annotation path** (return types, params, closures, map keys), so a type used both inside its module and at a selective-import site no longer produces two distinct mangled tuple-carrier C names ("incompatible types").
- **`let _ = expr` no longer collides** ("redefinition of '_'") when multiple discards appear in one scope.
- **Bare struct-style enum-variant patterns** (`QueryError { a, b, .. }` with no `Type.` qualifier) now bind and match correctly, routing field access through the variant's data union.
- **Generic closures returning a tuple** (`fn(T) -> (T, U)`) resolve the tuple carrier instead of lowering to `void`.

## Breaking Changes (v0.45.0)

- **SQLite is no longer bundled in the compiler binary.** Programs link SQLite only when they `import std.db_sqlite` (or a transitive db module). It ships as a sidecar under `share/blink/native/sqlite3/` and is resolved automatically by installed binaries. Pin your own build with `[native-dependencies] sqlite3 = { path = "vendor/sqlite3.c" }`. **Upgrading from ≤0.44.x:** reinstall via the v0.45.0 installer so the sidecar is present; if you maintain a custom layout, ensure `share/blink/native/` ships alongside the binary, or use the manifest override.
- **Stray `;` is now a hard error (E1113).** Previously the lexer printed a warning to stdout and the file still compiled (exit 0); now it is rejected and the build fails.
- **`blink --emit blink` (the formatter) exits non-zero on parser errors.** Tooling/CI that shelled out to the formatter and ignored exit codes will now observe failures.

## What's New (v0.45.0)

- **New diagnostic E0824** — cleanup body (BlockHandler/Closeable) that panics during unwind is now reported.
- **Parser tolerates newlines** inside `@where(...)`, `Fn(...)`, `#embed(...)`, `channel.new(...)`, and `assert(...)` argument lists, so these can wrap across lines.

## Fixes (v0.45.0)

- **Block-arm `match` type inference** now works for non-Int scalar arms (was Int-only).
- **`assert` failure messages report the correct source location** (anchored at the keyword, not the closing paren).
- **Panic messages report the originating file** and use canonical `lib/std/X.bl` paths instead of internal `<embedded:...>` forms.
- **Formatter emits reparseable output** for handler-expression bodies passed as call arguments and for IIFE bodies (previously emitted unparseable `{ ... }`).
- **Bare function name passed as a closure-typed argument** now synthesizes an ABI shim instead of failing.
- **Generic-function monomorphs propagate effect annotations** correctly.
- **Compound carrier names are disambiguated** when user and stdlib types collide.
- **`&&`/`||` short-circuit codegen strips redundant outer parens**, fixing builds under clang `-Wparentheses-equality`.
- **Forward declarations for `promote` are emitted before closure definitions.**
- **A peeled native dependency linked statically from its sidecar no longer also emits the dynamic `-l<name>` flag.** Importing `std.db_sqlite` previously appended `-lsqlite3` even though the vendored amalgamation already satisfied every symbol, leaving an undefined-symbol/`libsqlite3.so` dependency and breaking the link (`cannot find -lsqlite3`) on any host without `libsqlite3-dev` — including the v0.45.0 Docker image. The dynamic `-l` now applies only to a `{ system = true }` manifest override.
- **The user-TU object-cache compile now resolves a peeled dependency's header.** Building a program that imports `std.db_sqlite` on a host without a system `sqlite3.h` previously printed `fatal error: sqlite3.h: No such file or directory` (the cached `cc -c` lacked the sidecar `-I`) and only succeeded by falling through to the combined link. The vendored include path is now threaded into the cached compile.

## Fixes (v0.44.2)

- **Nested enum patterns inside `Some(...)` / `Ok(...)` / `Err(...)` now typecheck and codegen.** Arms like `Err(E.A(msg))` previously left `msg` untyped (typecheck only narrowed the outer Some/Ok/Err binding) and never declared `msg` from the unwrapped payload (codegen's recursive bind only handled bare ident / wildcard sub-patterns under the outer carrier). User code matching a user enum nested in a Result or Option payload no longer fails to compile.
- **`with` cleanup destructors now fire when `skip()` or `?` propagates out of a test body.** Per spec §2.20 these belong to the catchable-unwind set alongside `return`, but the longjmp-based exit path skipped C `__attribute__((cleanup))` destructors. A `with db.transaction() { let _ = q()? }` inside a `test {}` silently lost its rollback. The runner now uses a Result-sentinel propagation (plain `return` after setting runner globals) so destructors at every `with` site fire on the way out.
- **`std.testing.skip(reason: Str)` is now exposed as the canonical way to skip a test from its body.** Calls outside a test body are rejected as `E0516 SkipOutsideTestBody`. `testing.for_each` polls the runner between iterations so a failing or skipped case stops the loop.
- **Module-qualified generic-fn calls (`mod.fn[T](args)`) now compile correctly.** The MQ-call branch was a parallel implementation that never picked up generic-fn handling from the bare-name path, so the symbol came out unmangled and the result typed as void. Same-module generic-fn calls whose plain-T return resolved to a user struct or enum were silently miscompiled by the same shared inference gap and are also fixed.

## Fixes (v0.44.1)

- **`Option[E]` and `Result[E, _]` where `E` is a user enum now compile as fn parameters and return types.** v0.44.0 widened struct payloads through Option/Result codegen but left enum payloads on the type-erased path, so any user program passing or returning `Option[MyEnum]` failed to compile with `blink_Option_void` errors. Enum payloads now drive struct-tagged Option/Result emission across the coupled codegen sites.
- **Nested patterns inside `Some(...)`, `Ok(...)`, `Err(...)` are now actually tested.** Previously `Some(Cmd.Continue)` would also match `Some(Cmd.Quit)` because the arm only checked the outer tag and silently dropped the sub-pattern. The condition now recursively tests the sub-pattern against the unboxed payload.
- **`blink test` against an installed compiler no longer crashes building the stdlib archive.** The install layout puts `runtime.h` at `share/blink/runtime.h`, but the lookup only knew about `BLINK_ROOT/bootstrap` and `./bootstrap` and ultimately handed an empty path to `read_file`. Now resolves across five locations (`BLINK_ROOT/build`, `BLINK_ROOT/bootstrap`, `<install-root>/share/blink`, `./build`, `./bootstrap`) with an actionable diagnostic if all miss.
- **Docker image builds again.** v0.44.0 moved releases from bare per-platform binaries to per-target tarballs, and the Dockerfile still curled the old bare-binary URL and 404'd. The build now downloads the `.tar.gz` and extracts under `/usr/local/{bin,share}` so argv[0]-based stdlib resolution finds the archive. Stale default tag bumped from `v0.23.3` to current.

## Fixes (v0.44)

- **`blink build` / `blink run` invoked as bare `blink` from a user project now finds the stdlib archive.** v0.43 fixed the `~/.local/bin/blink` invocation by full path, but PATH-resolved invocation (`blink build src/main.bl`) still failed with `fatal error: libblink_std.h: No such file or directory`. `resolve_install_root()` ran `readlink -f blink`, which joined the bare basename onto the user's cwd and produced a nonexistent path; the dirname walk then resolved `share/blink/` against the wrong root and fell through to the relative `"build"` fallback. Now bare argv[0] is resolved via `command -v` before `readlink -f`, and the resolved path is verified to exist. (Closes 8gtzx8.)

## What's New (v0.44)

### Install / Distribution

- **Release binaries downloaded from GitHub can now compile user programs out of the box.** Each release ships a per-target tarball (`blink-<target>.tar.gz`) containing `bin/blink` plus `share/blink/{libblink_std.a, libblink_std.h, runtime.h}`. The binary locates the archive via `realpath(argv[0])` — no `BLINK_ROOT`, no `task install`, no missing `libblink_std.a` errors. Layout matches Go's `GOROOT` and `task install`.
- **`install.sh`** for one-line install: `curl -sSL https://github.com/blinklang/blink/releases/latest/download/install.sh | sh`. Detects platform (linux-x86_64, macos-x86_64, macos-aarch64), resolves the latest tag (or `--version vX.Y.Z`), and extracts to `$HOME/.local` by default (override with `--prefix` or `BLINK_PREFIX`; auto-sudo for non-writable prefixes).

### CI

- **`task test-installed` now covers PATH-resolved invocation** (`blink build` from a project subdir with the install prefix on `$PATH`), not just full-path invocation. This is the path that broke in 8gtzx8 and slipped past CI in v0.43.

## Breaking Changes (v0.43)

- **`Map[K, V]` key type now enforced at typecheck.** `Float`/`F32`/`F64` keys, and user struct/enum keys without `@derive(Hash, Eq)`, are rejected with `E1400 MapKeyNotHashable`. Previously these compiled and produced a `BLINK_COMPILER_BUG_kops_unsupported_K` sentinel or a cryptic C error. Generic K passes through to monomorphization.
- **`@module("")` is rejected as `E1008 InvalidModuleAnnotation`.** Never spec-authorized; existed only as an internal codegen carve-out. No in-tree uses remain.
- **Unknown `@derive(...)` names are rejected as `E1112 UnknownDerive`.** Only `Serialize`, `Deserialize`, `Eq`, `Clone`, `Hash` are accepted; bogus names previously silently no-op'd.
- **`?` in a test body now requires `Display` for the error type (`E0514 DisplayRequiredForQuestionMark`).** The error message is rendered via `Display.display(e)` at the propagation site.
- **Annotated test return type rejected (`E0515 AnnotatedTestReturnTypeRejected`).** `test "x" -> Result[Void, E] {}` is no longer accepted; elaboration is implicit when `?` appears in the body.
- **`impl Trait[T] for U` with unbound `T` is now rejected at typecheck.** Previously slipped past the single-letter carve-out and lowered T to `void` in codegen, producing C that failed to compile. Help text directs users to the canonical `impl[T] Trait[T] for Recv[T]` form.

## What's New (v0.43)

### Language

- **`Map[K, V]` over arbitrary key types.** `Int`, `Bool`, `Char`, all sized-int widths, user structs with `@derive(Hash, Eq)`, user enums (including data enums) with `@derive(Hash, Eq)`, and tuples of any combination of the above. Tuple `Hash`/`Eq` are structurally auto-derived (no annotation needed). (Closes h0geg9.)
- **`@derive(Hash)`** on structs and enums emits a structural hasher compatible with Map keys.
- **`?` operator in `test {}` bodies.** When `?` appears in a test body, the body is implicitly elaborated to `Result[Void, TestError]`. Propagated errors emit NDJSON `cause:"propagated_error"` with `{message, error_type}`. `blink check` and `blink test` now agree on what's a valid test program.

### CLI

- **`--deterministic`** on `build`/`run` — pins the map hash seed to 0 for reproducible iteration order. Default policy reads `$BLINK_MAP_SEED` or falls back to `time(NULL) ^ (getpid()<<16)`.

### Stdlib / Testing

- **`testing.for_each` runtime label-uniqueness check** — duplicate case labels panic with index info.
- **Test runner emits `"case":"<label>"`** alongside the parent test name when a `for_each` case body fails an assertion. Human-readable output gets a `(case "X")` suffix.
- **Map stdlib HOFs widened to `[K, V]`** — `map_for_each`, `map_filter`, `map_fold`, `map_map_values`, `map_merge` now generic over K (was `Map[Str, V]` only).

### Installed-binary improvements

- **`blink` installed at `~/.local/bin/` no longer requires `BLINK_ROOT`.** `task build` now ships `libblink_std.{a,h}` and `runtime.h` to `~/.local/share/blink/`. Resolution via `realpath(argv[0])`.
- **Embedded stdlib registry auto-generated from disk** — no more drift between `#embed` consts and `lib/std/*.bl`. Includes previously-missing `std.arena`, `std.float`, `std.libc`.

### Fixes

- **`Str` ordering operators (`<`, `<=`, `>`, `>=`)** now compare contents via `strcmp`. Previously emitted raw `const char*` pointer comparison, returning arbitrary results based on data-segment layout.
- **`Option[T]` / `Result[T, E]` in tuple element position** now lowers correctly. Previously type-erased to `int`/`void`, breaking any `update` fn returning `(Model, Option[Cmd])`.
- **Bare `None` in a tuple slot** now picks up the surrounding fn's tuple return ann instead of falling back to `Option[Int]`.
- **`.unwrap()` / `.unwrap_or()` / `.unwrap_err()`** on any `Option`/`Result` receiver (method-chained, if-expr tail, block-tailed) now infers the correct return type. Previously fell through to `Void` and emitted `const void s = 0;`, segfaulting on use.
- **`Option[UserEnum]`** compiles — `Some(<enum-value>)` now routes through the struct-option carrier.
- **`@derive(Eq)` on structs/enums with sized-int (`I8`..`U64`/`Char`) fields** now compares those fields. Previously skipped, with hash/eq divergence on Map keys.
- **`type Alias = T` at fn params/returns** now lowers correctly (was emitting `void`).
- **Closures with explicit tuple-typed parameters** (`fn(c: (Int, Int)) { ... }`) now compile (param type was lowering to `void`).
- **`for_each[T]` over a list of tuples** infers T correctly through the tuple element.
- **String interpolation of escaped quote (`"{f(\"x\")}"`)** now lexes correctly.
- **`\}` escape in string literals** preserved through `fmt` round-trip.
- **`Bytes.with_ptr(fn(p) -> I64 { ... })`** return-type propagation fixed.
- **Test-block names containing `\"` / `\\`** survive formatter round-trip.

## What's New (v0.42)

### Runtime contracts (spec §refinement-contracts)

- **`@ensures(expr)`** — postcondition runtime-checked at every return site. `result` binds to the return value.
- **`@where(expr)`** — runtime-checked at refined-type boundaries (param coercion, return coercion).
- **`old(expr)`** — inside `@ensures`, snapshot an argument's value at fn entry; the C codegen materializes `__old_N` locals at the prologue.
- **`@pure`** — declares the fn has no effects, no mutation, no FFI; calls only other `@pure` fns. Recursion allowed. Enforced at typecheck.
- **`@modifies(...)`** — parses-and-validates only (stub reserving syntax for the future SMT backend).
- New diagnostics: `E1300`–`E1306` (predicate validator — rejects loops, assignments, effectful/impure calls in predicates), `E1307` (purity check), `E1308` (`@modifies` shape check).

### Stdlib

- **`std.libc.poll(fds, timeout_ms) -> Result[List[Pollfd], Str] ! IO`** — first curated libc syscall wrapper (γ-doctrine). Exposes `Pollfd`, `POLL_EVT_IN/PRI/OUT/ERR/HUP/NVAL`. `timeout_ms` semantics match `poll(2)`.
- `std.float.fabs` and `std.float.is_nan` now annotated `@pure`; `std.float.close_to` carries an `@ensures` clause.

### FFI

- **`Ptr[T]`** is now accepted in `@ffi` signatures when `T` is `@ffi.struct` (E0810 message updated to mention `@ffi.struct`).
- When an `@ffi(..., header: "X")` references a header that an `@ffi.struct` already `#include`'d, the compiler suppresses its redundant `extern` declaration — the system header's prototype is the only one in scope.

### Fixes

- **String interpolation of sized integers (`I8`/`I16`/`I32`/`U8`/`U16`/`U32`/`U64`) no longer segfaults.** Previously fell through to a `%s` catch-all that passed the integer as a pointer.
- **`Result` `match` arms now bind the inner type.** `match res { Ok(out) => out.get(0)... }` no longer decays to `Option[Int]`.
- **`Option[List[T]]` returned from a fn now carries `T` through `match Some(out)` binding** — struct field access on the unwrapped value no longer fails C compile.
- **`if/else` and `match` branches now unify concrete payload types.** `if b { Ok(1) } else { Err(false) }` correctly infers `Result[Int, Bool]` instead of `Result[Int, ?]`, and let-annotation type checks now catch mismatched declarations.
- **`type Port = Int`** aliases now lower correctly at fn params/returns (was emitting `void` instead of `int64_t`).

## Breaking Changes (v0.41)

- **`return val` is now type-checked against the declared return type.**
  Early `return` statements with a value of the wrong type previously
  typechecked silently — only the trailing tail expression was checked.
  Programs like `fn f() -> Int { if c { return "wrong" } 0 }` now fail
  with a type error. (Likely to surface latent bugs rather than break
  intentional code.)
- **New diagnostics:**
  - `E0812 FfiStructInvalidField` — `@ffi.struct` field uses a
    GC-managed type (`Str`, `Bytes`, `List`, `Map`, `Set`, `Result`,
    `Option`, traits, non-`@ffi.struct` types).
  - `E0813 FfiPtrOffsetSingleton` — `.offset(i)` on a `Ptr[T]` that came
    from `scope.alloc()` rather than `scope.alloc_n[T](n)`.
  - `E0814 BytesWithPtrGrowthForbidden` — growth-effecting method on
    the receiver (`push`, `append`, `concat`, `extend`, `clear`,
    `truncate`, `resize`, `write_*_le/be`) inside a `Bytes.with_ptr`
    closure.
  - `E0815 BytesWithPtrAliasEscape` — passing the receiver as an
    argument inside a `Bytes.with_ptr` closure.
  - `E0816 BytesWithPtrMultiStmt` — multi-statement closure body to
    `Bytes.with_ptr` (single-expression only in v1).
  - `E0817 BytesPtrCastForbidden` — `Bytes.as_ptr()` outside a
    `Bytes.with_ptr` closure.
  - `W0812 MissingCanonicalHeader` — `@ffi.struct(header: "X.h")`
    whose header isn't declared in any
    `[native-dependencies].headers` list. Escalates to error under
    `--strict-struct-layout`.

## What's New (v0.41)

### FFI cluster (spec §9.1.3)

- **`@ffi.struct(header: "...", name: "...")`** annotation declares a
  Blink struct as the layout twin of a C struct. Codegen emits
  `_Static_assert(sizeof + offsetof)` against the named C type, locking
  the Blink typedef to the real C ABI; field-order or padding drift
  fails the C compile rather than silently corrupting memory.
- **`Ptr[@ffi.struct T].field.read() / .write(v)`** — typed access to
  fields through a `Ptr` receiver, lowered to direct C field reads and
  assignments (no temporaries).
- **`scope.alloc_n[T](n)`** — contiguous array allocation inside a
  scope's arena, returning `Ptr[T]` to the first cell. **`Ptr.offset(i)`**
  advances by `sizeof(T)` strides; chained offsets carry the inner
  struct so stride is correct at every link. `.offset()` on a singleton
  `scope.alloc()` is rejected with `E0813`.
- **`Bytes.with_ptr(fn(p) { ... })`** — the only sanctioned
  `Bytes -> Ptr[U8]` aliasing path. Closure body pins the buffer; a
  parser-level no-grow check rejects mutation that could relocate the
  buffer (`E0814`) or escape the alias (`E0815`).
- **`[native-dependencies].<dep>.headers = [...]`** in `blink.toml`
  declares which C headers are available. `@ffi.struct(header: "X.h")`
  warns (`W0812`) if its header isn't declared.
- **`blink shim init <name>`** — third-tier FFI escape hatch
  (§9.1.3 γ). Scaffolds `vendor/<name>.c`, `vendor/<name>.h`, and
  `src/<name>.bl` with a `@trusted(audit:"TODO")` Blink wrapper around
  vendored C — for cases (varargs, signal handlers, packed structs,
  alignment overrides) where `std.libc.*` and `@ffi.struct` aren't
  enough.

### `std.process` (new module)

- **`spawn(cmd, args) -> Pid`** plus **`PidOps`** trait
  (`wait`, `kill`, `send_signal`).
- **POSIX signal constants:** `SIGHUP`, `SIGINT`, `SIGQUIT`,
  `SIGKILL`, `SIGTERM`.
- **`cmd_test` (the `blink test` runner) now forwards SIGINT/SIGTERM
  to all live child workers** so a Ctrl-C reaps the whole tree
  instead of orphaning grandchildren.

### Power-assert

- **`assert(...)` failure messages now include source text and one
  level of operand introspection** (per spec §2.20 / §8.10.2). Top-
  level binary comparisons and logical operators have their operands
  lifted into typed temps and rendered into the failure message.
- **`blink test --json`** output now emits the spec-promised
  `assertion`, `introspection`, `span`, and `user_message` fields.
- Legacy `assert_eq` / `assert_ne` codegen unchanged.

### `std.testing`

- **`assert_close(a, b, tol)` / `assert_close_rel(a, b, rel)`** for
  float comparisons. Both panic on `NaN` inputs and on negative
  tolerance, short-circuit on exact equality (so identical
  infinities pass), and lazily build their failure-message
  `snprintf` only on the failure branch.
- **`for_each[T](cases: List[(Str, T)], body: fn(T))`** — fixed-list
  table-driven test helper (spec §8.10.2).

### `std.float` (new module)

- **`fabs(x)`** — pure-Blink absolute value (no FFI).
- **`is_nan(x)`** — IEEE `x != x` test, named.
- **`close_to(x, y, tol) -> Bool`** — non-panicking variant of
  `assert_close`.
- **Float method dispatch** — `x.close_to(y, t)`, `x.fabs()`,
  `x.is_nan()` resolve via the same trait-impl pathway as `Str`/`Int`.
  (Was registered but unreachable because the receiver-type lookup
  didn't map `CT_FLOAT` to `Float`.)

### `Bytes`

- **In-place setter family:** `set_u16_le/be`, `set_i16_le/be`,
  `set_u32_le/be`, `set_i32_le/be`, `set_u64_le/be`, `set_i64_le/be`
  (12 methods). Bounds-checked, `Result[Void, Str]`, no growth —
  the symmetric counterpart of `read_*_le/be`.
- **`Bytes.zeroed(n)`** — pre-sized zero-filled buffer constructor.

### `std.path`

- **`path_parent(p)`** — POSIX `dirname(1)` semantics. Strips trailing
  slashes before walking up: `path_parent("foo/")` is `"."`, not
  `"foo"`. Sister to `path_dirname`, which doesn't pop trailing
  empties.

### Stdlib

- **`Char.try_from(Int)`** — scalar-value-validating conversion via
  the `TryFrom[Int]` trait. Returns `Result[Char, ConversionError]`.
- **`Bytes.to_str` and `Str.char_at`** are now stdlib trait impls
  (were codegen-emitted C). No user-visible API change; the
  migration also fixed a latent bug where FFI bindings with
  `Result` / `Option` / `Tuple` returns silently emitted `void` C
  signatures, so the first call would read uninitialized memory.

### Reliability and correctness

- **`blink build <missing-file>`** now exits non-zero with a clear
  "not found" diagnostic in <1s instead of relying on the runtime
  to abort.
- **`blink test`** now does a serial typecheck pre-pass before
  spawning parallel workers, so 30 broken-on-purpose fixtures
  finish in ~3s with diagnostics instead of hanging indefinitely.
  A shared cancel channel stops new spawns when any worker
  unexpectedly fails.
- **ADTs that reference later-declared ADTs in the same file**
  now compile — codegen topo-sorts type definitions; cycles
  (self-references stored as `int64_t`) are tolerated.
- **`match` on a direct `Type.try_from(value)`** call no longer
  emits the wrong err-struct C type (was producing
  `Result_<ok>_void` instead of `Result_<ok>_ConversionError`).
- **Generic `for_each[Int]` over `List[(Str, T)]`** now
  monomorphizes `T` correctly (was emitting `Tuple2_str_void`
  and undeclared-type C errors).
- **Module-qualified `mod.fn(args)` and trait-qualified
  `Trait.method(args)`** now thread the hidden effect arg
  through, fixing "too few arguments" link errors at effectful
  qualified call sites.
- **`Result[Void, _]`** can now be returned with `Ok()` or
  `Ok(())`; `lib/std/{bytes, db_sqlite, db_stmt, net_tcp}` migrated
  off the `Ok(0)` workaround.
- **Chained `Char.from_code_point(x).unwrap()`** no longer reads
  `Int` for the inner type — the static branch now registers its
  result temp's struct fields.

### CLI / tooling

- **`tests/<pkg>/tests/foo.bl` can now `import <pkg>`** via the
  walk-up-to-`blink.toml` resolver (closes acceptance gap zg6yd9).
  Previously the resolver treated `tests/` as the src root.
- **`--strict-struct-layout`** flag (currently always-on; reserved
  for a future opt-out mode that would skip the FFI struct
  `_Static_assert`s).

## Breaking Changes (v0.40)

- **Package entry-point convention is now `src/<pkg>.bl`** (where
  `<pkg>` is `[package].name` from `blink.toml`). The `src/lib.bl`
  fallback is gone — bare `import <pkg>` resolves deterministically to
  `<pkg-root>/src/<pkg>.bl` or errors. Migration: rename
  `src/lib.bl` → `src/<your-package-name>.bl` and ensure
  `[package].name` in `blink.toml` matches `[a-z][a-z0-9_]*`.
- **Bare imports from files outside any `blink.toml`** now error with
  `E1010 OrphanFile`. Previously they silently resolved against the
  source file's directory.
- **Sized-int arithmetic now traps on overflow.** `+ - * / % unary -`
  on `I8` / `I16` / `I32` / `U8` / `U16` / `U32` / `U64` panic on
  overflow, division by zero, and signed `INT_MIN / -1` (was: silent
  wrap). Use `wrapping_add` / `wrapping_sub` / `wrapping_mul` /
  `wrapping_div` / `wrapping_rem` / `wrapping_neg` for explicit
  modular arithmetic.
- **New diagnostics:** `E1008 InvalidModuleAnnotation` (extended to
  cover entry-file `@module(X)` mismatches), `E1009
  PackageEntryNotFound`, `E1010 OrphanFile`, `E1011
  InvalidPackageName`.

## What's New (v0.40)

- **Bitwise operators** — `&`, `|`, `^`, `<<`, `>>`, `~` for `Int` and
  all sized-int types. Shift amounts are `U32` (`Int` literals
  coerce). Out-of-range literal shifts caught at compile time;
  non-literal shift amounts get a runtime bounds check. Right shift
  is arithmetic on signed types, logical on unsigned. New warning
  `W0700` fires when a bitwise op is applied to a comparison result
  without parentheses.
- **`From[T]` / `Into[T]` / `TryFrom[T]` / `ConversionError`** in
  `std.traits`, with full widening (`From`) and narrowing (`TryFrom`)
  matrices for `I8` / `I16` / `I32` and `U8` / `U16` / `U32` / `U64`
  in `std.int_conv`. `Type.from(x)` and `Type.try_from(x)` now accept
  builtin and sized-int target types, not just user structs and
  enums.
- **`wrapping_*` methods on sized ints** — `wrapping_add`,
  `wrapping_sub`, `wrapping_mul`, `wrapping_div`, `wrapping_rem`,
  `wrapping_neg` give explicit modular arithmetic for I8/I16/I32 and
  U8/U16/U32/U64. (`wrapping_div` still panics on divide-by-zero,
  matching Rust.)
- **User trait impls on builtin receivers** — `impl Trait for Str`
  (and `List`, `Map`, `Set`, `Bytes`, `StringBuilder`, `Template`)
  now actually dispatches. Previously the impl compiled but methods
  on a builtin receiver always routed through the hardcoded builtin
  emitter, so the impl was unreachable.
- **`Sized` is the canonical length / emptiness trait** for all
  collection types. `Map`, `Set`, `Bytes`, `Str`, `StringBuilder`,
  and `List` all provide `Sized` with uniform `.len()` and
  `.is_empty()`. `Map.is_empty()` is newly callable (it was declared
  but had no concrete provider — calling it was previously a hard
  error).

### Fixes

- `let c = 'A'; io.println("{c}")` no longer segfaults. `Char`
  interpolation was missing a codegen branch and the codepoint was
  passed as a `char*`.
- `blink add --path . <self-pkg-name>` no longer infinite-loops. Self
  dependencies are rejected up front and transitive path / git cycles
  are guarded.
- `import <pkg>` from a file outside `src/` (e.g. under `tests/`) now
  resolves through the package's `blink.toml` instead of picking up
  files next to the source.
- Stdlib helpers (`http_client`, `num.parse_int` / `parse_float`,
  `path`, `semver`, `toml`, `json.escape`, `term_style.strip_ansi`)
  no longer panic on non-ASCII bytes. `escape_json_str` is also now
  O(n) (was O(n²)).
- `Bytes` bounds-error messages now interpolate the offending offset
  (e.g. `"bytes read u16_be: offset 12 out of bounds"`).

## Breaking Changes (v0.39)

- **`Str.char_at(i)` now returns `Option[Char]`** (was `Int`). Returns `None` if
  out of range or `i` points at a UTF-8 continuation byte. Use `Str.byte_at(i)`
  for raw byte access.
- **`Char.from_code_point(n)` now returns `Result[Char, ConversionError]`** (was `Str`).
  Use `str_from_code_point(n)` (from `std.str`) to get the old `Str` behaviour.

## What's New (v0.39)

- **`Char` primitive type** — Unicode scalar value with single-quote literals
  (`'a'`, `'\n'`, `'\t'`, `'\\'`, `'\''`). Instance methods: `.to_int()`, `.to_str()`.
  `Char.from_code_point(n)` returns `Result[Char, ConversionError]`; use
  `str_from_code_point(n)` for the single-character `Str`.
- **Struct-style enum variants** — enums may now declare struct variants:
  `enum E { Variant { field: Type } }`. Construct as `E.Variant { field: val }`,
  destructure in `match` with `Variant { field } =>`.
- **`Str.byte_at(i) -> Int`** — raw byte access for byte-indexed scanning
  (replaces the old `char_at` when byte values are what you actually want).
- **`Str.trim_right()` / `Str.trim_left()`** — strip trailing / leading
  whitespace. Complement to the existing `.trim()`.
- **Parser diagnostics** — error messages now show token names ("expected IDENT,
  got `let`") instead of numeric kind IDs, and include a Rust-style source line
  with a caret gutter. Multi-character tokens produce `^^^^^` underlines.

### Fixes

- `str_to_upper` / `str_to_lower` no longer corrupt non-ASCII text. They now
  iterate codepoints instead of raw bytes.
- Qualified struct literals `module.Type { field: val }` now compile correctly
  (were rejected with "unknown type 'module'").
- Formatter idempotency: wrapped multi-line method calls and block-like
  expressions (`match`, `if`, closures, handlers, `async.scope`/`async.spawn`)
  in expression position now round-trip cleanly. `format(format(x)) == format(x)`.
- Truncated or malformed input (unterminated string interpolations, unclosed
  `match`/`impl`/`trait`/struct-lit/list-lit/`type` blocks) no longer panics
  or OOMs the parser — a structured diagnostic is emitted instead.
- `assert(cond, msg)` now prints `msg` on failure. Previously codegen dropped the
  second argument and hardcoded "assertion failed".
- `assert(cond, msg)` / `debug_assert(cond, msg)` evaluate `msg` lazily — only
  when the assertion actually fails, matching Rust/C semantics.

## What's New (v0.38)

- **Sized scalar integer types** — `I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`
  as first-class types (previously only inner types of `Ptr[T]`). Conversion
  methods `.to_i8` / `.to_i16` / `.to_i32` / `.to_u8` / `.to_u16` / `.to_u32`
  / `.to_u64` / `.to_int` with C-style wrapping casts. No implicit promotion
  with `Int`. Unblocks FFI against libc signatures like
  `int isatty(int fd)` and `uint32_t htonl(uint32_t)`.
- **`fs.remove(path)`** — built-in file deletion backed by `unlink(2)`.
- **Binary-safe TCP I/O** — `std.net` gains `tcp_read_bytes` / `tcp_write_bytes`
  returning `Result[Bytes, NetError]`, preserving null bytes and non-UTF-8
  sequences that the `Str`-based variants truncated. New `NetError.IoError`
  variant for these paths.
- **Fixed-width `bytes` accessors** — 16 new big-endian / little-endian
  integer accessors: `read_u16_be`, `read_u16_le`, `read_u32_be`, `read_u32_le`,
  `read_i32_be`, `read_i32_le`, `read_i64_be`, `read_i64_le` and matching
  `write_*` methods. Reads return `Result[Int, Str]` with explicit bounds
  check.

### Fixes

- `Result[Bytes, E].unwrap()` now emits the correct `Bytes` type (was `Int`),
  so downstream method calls on unwrapped bytes type-check.
- `let mut` captured and *read* inside a closure no longer raises W0601
  (dead-store) on writes in the enclosing scope — the closure can observe
  later writes when called, so the read is live.
- LSP no longer emits E0506 / E0300 false positives on `with arena { … }`
  blocks (the `arena` keyword is no longer mis-parsed as an undefined
  variable).

## What's New (v0.37)

- **`with arena { }` arena allocation** — opt-in bump allocator scoped to a block. Tail of `with arena { expr }` is deep-copied (promoted) into the enclosing arena or GC heap, so scratch work is reclaimed while the result survives. Functions that allocate into the caller's arena carry `! Arena`. Supports primitives, `Str`, structs (including `Str` fields), `List`, `Map`, `Option`, `Result`, nested arenas, and closure tails (including closures that capture other closures). See spec §5.2 / §5.2.1 and `blink llms --topic arena`.
- **Arena diagnostics** — E0700 (value escapes arena), E0701 (cyclic type across arena boundary), E0702a–d (unsupported closure tails), W0701 (redundant `! Arena`).
- **`std.arena.bytes_used()`** — live bytes in the innermost active arena. Intended for tests and introspection.
- **`arena.promote` trace event** — spanned begin/end events around each tail promotion, with target (`outer arena` / `GC heap`) and descriptor. Available under `--trace` and `--blink-trace codegen`.
- **`task bench`** — arena vs GC benchmark harness (`benchmarks/arena_process_batch.bl`).

### Fixes

- `List[Map[K, V]].get` / `.pop` no longer lose the inner `Map` type in codegen (previously produced `Option[Int]` and downstream `UnresolvedMethod` on `.get(key)`).
- Parser accepts `if` / `while` with the condition wrapped to a new line — `bin/blink fmt` output now round-trips through `check`.
- Formatter emits trailing `+` / `&&` (not leading) on wrapped binop chains, matching what the parser accepts.

## Breaking Changes (v0.36)

- **BREAKING: `Map.get` now returns `Option[V]`** — `Map.set`, `Map.has`, and `Map.raw_get` removed. Use `map[key] = value` for insertion and pattern-match the `Option` from `map.get(k)`.
- **BREAKING: `Option[Struct]` stores pointer** — `Option[T]` for struct `T` no longer stores an inline copy. Affects FFI/interop code that assumed inline layout.
- **BREAKING: mutation lints promoted to errors** — previously soft warnings around implicit mutation now hard-fail compilation.
- **`..` spread operator** — struct copy-update (`Point { x: 1, ..source }`) and list spread (`[..a, x, ..b]`). See spec §2.16.
- **String-backed enums** — enums can be declared with `Str` discriminants (`Open = "open"`), with auto-generated `to_str` / `from_str` and Serialize/Deserialize using the string values.
- **`@derive(Eq, Clone)`** — generates field-wise equality and value-copy clone for structs and enums.
- **`@deprecated`** — emits W2000 (DeprecatedUsage) at call sites. Supports `since` / `replacement` metadata; suppress with `@allow(DeprecatedUsage)`.
- **`std.term` honors `NO_COLOR`** — when set, style/color functions return strings unchanged per the no-color.org standard.
- **Fix** — Option[Map/List] type loss through `Map.get_opt`.
- **Fix** — `db.connect` handle leak.

## What's New (v0.35.1)

- **Fix** — if-expr type inference for module-qualified calls
- **Fix** — fn return type collisions in multi-file codegen
- **Fix** — cross-module private fn collisions and empty facade docs
- Doc comments added to undocumented stdlib modules

## Breaking Changes (v0.35)

- **BREAKING: `get_env()` removed** — use `env.var(name)` instead (returns `Option[Str]`, dispatches through Env effect vtable)
- **BREAKING: `std.flat_json` removed** — use `std.json` instead
- **Env effect namespace** — new `env.var(name)`, `env.cwd()`, `env.set_var(name, value)`, `env.remove_var(name)`, `env.exit(code)` methods dispatch through vtable, enabling handler interception
- **`db.connect(path)`** — convenience method to open a SQLite connection directly: `with db.connect(path) { ... }`
- **Map/List type unification** — struct field types for `Map` and `List` now use parameterized `tp_id` instead of duplicated type info
- **Fix** — formatter mangling tuple syntax and codegen losing tuple type in List elements
- **Fix** — List elem type leaking across function boundaries in codegen
- **Fix** — Map[K,V] type loss through struct field access
- **Fix** — `--trace codegen` undeclared `__trace_enter_ts` in effect handlers
- **Fix** — `db.exec` failing on PRAGMA statements that return result rows
- **Fix** — FFI lib detection improvements

## What's New (v0.34)

- **Tier-2 stdlib removed** — all `std.*` modules are now tier-1: embedded in the compiler binary, version-locked, no `blink.toml` entry required. `std.db` and `std.term` no longer need explicit dependency declarations. E1052 (PackageNotDeclared) gate removed for `std.*` imports.
- **Fix** — `blink doc std.db` now works on installed binaries (modules are embedded)

## What's New (v0.33)

- **`std.term` module** — ANSI styling (`bold`, `dim`, `italic`, `underline`, `strikethrough`, colors, background colors), TTY detection (`is_tty`, `terminal_width`, `terminal_height`), cursor control (`move_up`, `clear_screen`, `hide_cursor`, etc.). `import std.term`
- **Template[C] introspection** — new methods `parts()`, `count()`, `type_tag(idx)`, `get_str(idx)`, `get_int(idx)`, `get_float(idx)`, `get_bool(idx)` expose template internals, enabling DB drivers written in pure Blink
- **SQLite rewritten in pure Blink** — `std.db` no longer uses C runtime helpers for template query execution; uses Template introspection + low-level FFI bindings instead
- **Fix** — codegen handler state leak and W0501 Template parameter count diagnostic

## Breaking Changes (v0.32)

- **BREAKING: DB moved to stdlib** — database operations are now a user-defined effect in `lib/std/db.bl` instead of compiler magic. `import std.db` required. `DbRow` renamed to `Row`, `CT_ROW` removed.
- **BREAKING: `Template[C]` replaces raw SQL strings** — DB queries now use `Template[DB]` for automatic parameterization and injection safety. String interpolation in templates auto-extracts parameters. Use `Raw(expr)` to opt out.
- **BREAKING: DB operations return `Result`** — all `db.*` operations now return `Result[T, DBError]` instead of bare types. New `DBError` enum: `QueryError`, `ExecError`, `ConnectionError`, `NotFound`.
- **Associated types on traits** — traits can declare `type Name` members that implementers must define (e.g., `BlockHandler` has `type Context`)
- **`BlockHandler` trait** — scoped resource management with `enter()`/`exit()` methods and associated `Context` type. Enables `with db.transaction() { ... }` pattern.
- **`Closeable` trait cleanup** — `close()` now correctly called on early exit from `with`-blocks (break, return, error propagation)
- **Scoped `db.transaction()`** — auto-commit on success, auto-rollback on failure via `BlockHandler` implementation
- **`Stmt` type** — prepared statement support with `bind_int`, `bind_text`, `step`, `column_int`, `column_text`, `reset`, `finalize` methods
- **Handler captures** — handlers can capture values from their enclosing scope
- **E0601 diagnostic** — new error when `with...as` bindings escape via `async.spawn`
- **Fix** — W0602 false positive on Handler/Template type params
- **Fix** — `_self` param in impl methods generating invalid C void type
- **Fix** — `List[Str]` element type lost across function boundaries
- **Fix** — double-evaluation in `Result.unwrap()`/`unwrap_err()` codegen
- **Fix** — 4 codegen bugs: Set params, Map structs, for-in keys, if-expr methods
- **Fix** — list element type leak through struct impl method calls
- **Fix** — Option types and user-effect dispatch codegen bugs
- **Fix** — 2 formatter bugs: handler body collapse and import inlining

## What's New (v0.31)

- **Pact references removed** — all remaining `pact` references and `pact.toml` fallback support removed; `.pact` file extension fallback also removed
- **C output renamed** — generated C symbols now use `blink_` prefix instead of `pact_` (no user-facing impact unless inspecting emitted C)
- **Fix** — nested compound type codegen (`Option[Option[T]]`, `Result[Option[T]]`, etc.) now generates correct C types
- **Fix** — `unwrap()` on compound inner types no longer incorrectly returns `Void`
- **Fix** — match type inference for data enum pattern-bound variables
- **Fix** — nested generic return types no longer lose type information in the type tree
- **Fix** — intrinsic method shadowing with nested `Result` codegen
- **Fix** — `Result`+`Option` typedef collisions and function name collisions in C codegen
- **Build** — all compiler and C-level build warnings eliminated

## What's New (v0.30)

- **`std.testing` module** — `capture_log`, `capture_print`, `capture_eprint` handler factories for intercepting IO in tests
- **IO vtable dispatch** — `io.print`, `io.println`, `io.eprint`, `io.eprintln` now dispatch through the effect vtable, enabling handler interception
- **`io.print_raw` / `io.eprint_raw`** — bypass vtable for direct stdout/stderr output (escape hatches for when you need guaranteed raw output)
- **Fix** — codegen resolution of module-qualified type names (`Result[net.TcpSocket, net.NetError]` now works correctly)
- **Fix** — `Result.unwrap()` type propagation for `List` and `Map` inner types
- **Fix** — codegen type resolution for C-reserved variable names

## What's New (v0.29)

- **`Handler[E]` as first-class return type** — functions can return `Handler[E]`, store handlers in variables, and pass them as parameters; handlers are heap-allocated to survive beyond their creation scope
- **Fix** — false `UnusedVariable` warnings on pattern matches with built-in enum variants (`None`, `Some`, `Ok`, `Err`)
- **Fix** — handler metadata leakage when multiple functions returned handlers, causing incorrect behavior in `with` blocks
- **Fix** — static name collisions when multiple functions used handler expressions

## What's New (v0.28)

- **`std.traits` in prelude** — compiler-known traits (`Closeable`, `BlockHandler`, `Sized`, `Contains`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `BytesOps`, `StringBuildOps`, `Joinable`) are now auto-imported; no explicit `import std.traits` needed
- **`blink add` for stdlib** — `blink add std/<pkg>` works without `--path` or `--git`; packages are added with automatic version pinning
- **Fix** — `@module("")` annotation on trait-only modules now detected correctly (was ignored, causing false W0602)
- **Fix** — unused import checker skips empty module entries

## Breaking Changes (v0.27)

- **BREAKING: Selective import enforcement** — `import foo` now only provides qualified access (`foo.bar()`). Unqualified access requires selective imports: `import foo.{bar}`. Per-file scoping enforced.
- **Pub re-export semantics** — `pub import` re-exports formalized: consumers see re-exported items as if locally defined; name collisions (define + re-export same name) produce E1012
- **New module error codes** — E1004 (VersionConflict), E1007 (reject module-qualified type member access), E1008 (InvalidModuleAnnotation), E1009 (DuplicateModuleBinding), E1012 (DuplicatePubSymbol)
- **`capture_log` test instrumentation** — `std.testing.capture_log` handler factory spec'd for intercepting `io.log()` calls in tests
- **Fix** — module qualifier mangling, loop return type inference, `std.*` resolution
- **Fix** — pub import warnings and enum qualification errors
- **Fix** — false W0602 (unused import) on `pub let mut` assignment

## Breaking Changes (v0.26)

- **BREAKING: Language renamed Pact → Blink** — binary `pactc` → `blinkc`, env vars `PACT_*` → `BLINK_*`, file extension `.pact` → `.bl`, `pact.toml` → `blink.toml`. Compiler entry point renamed `src/pactc_main.bl` → `src/blinkc_main.bl`. Fallbacks removed in v0.31.
- **Cross-package cycle detection (E1002)** — circular dependencies between packages are now detected and reported at compile time
- **Pub import re-export flattening** — `pub import` re-exports are semantically flattened so downstream consumers see the original module's symbols
- **LSP inlayHints** — inferred types on `let` bindings shown as inline hints in editors
- **@capabilities budget enforcement** — `@capabilities` annotations on modules are now enforced during typechecking
- **Fix** — false `UnusedVariable` warnings on unqualified enum match arms eliminated

## What's New (v0.25)

- **Qualified module access** — `import auth` then `auth.login()`, `auth.Token`, `auth.MAX_RETRIES`. Covers functions, types, and constants. Selective imports don't restrict qualified access. Resolves name ambiguity (E1005) at the call site.

## What's New (v0.24)

- **Selective imports & aliases** — `import mod.{add, multiply as mul}` restricts which items are imported; aliases rename items at import site; ambiguous names across modules produce a compile error
- **`Closeable` trait** — `impl Closeable for T` enables `with expr as name { ... }` blocks that auto-call `.close()` on scope exit (reverse order for multi-resource)
- **Rich panic messages** — `unwrap()` / `unwrap_err()` panics now include source file and line number
- **LSP workspace/symbol & formatting** — `workspace/symbol` for project-wide symbol search; `textDocument/formatting` for in-editor format
- **Fix** — closures returning `Option[T]` now generate correct C type
- **Fix** — helpful E1109 error when `mut` is used on struct/enum fields (mutability is on the binding, not the field)

## What's New (v0.23.3)

- **Portable cross-compilation** — vendored GC source/headers embedded in binary; `blink build --target` now works from standalone installs without the source tree
- **Docker** — image includes `libgc-dev` for native builds and zig for cross-compilation
- **Perf** — `#embed` codegen uses byte arrays instead of escaped string literals; `escape_c_string` and other hot-path functions use StringBuilder (O(n) vs O(n²))

## What's New (v0.23.2)

- **Fixes** — for-in loop over `List[DataEnum]` now registers enum type for match inference
- **Docker** — image now includes zig for cross-compilation via `--target`

## What's New (v0.23.1)

- **Fixes** — recursive self-referencing data enum variants, data enum values in list literals, `?` operator Result type when fn returns struct

## What's New (v0.23)

- **`?` operator on `Option[T]`** — propagates None in Option-returning functions (mirrors Result `?`)
- **User-defined effects** — `effect` declarations with sub-effects, `with handler` blocks, namespaced dispatch (`metrics.counter(...)`)
- **Boehm GC** — automatic garbage collection via libgc, replaces manual memory management
- **`List.clear()` / `Map.clear()`** — in-place mutation to empty collections
- **Fixes** — Result/Option type resolution in match/? expressions, impl method return types, enum variant codegen

## What's New (v0.22)

- **`TcpSocket` / `TcpListener` types** — typed wrappers for TCP file descriptors with trait-based methods (`read`, `read_all`, `write`, `close`, `set_timeout`)
- **`std.net` TCP stdlib** — `tcp_listen`, `tcp_connect`, `tcp_accept`, `tcp_read`, `tcp_write`, `tcp_close`, `tcp_set_timeout`, `tcp_read_all`
- **`net.*` namespace methods** — `net.listen`, `net.accept`, `net.read`, `net.write`, `net.close`, `net.connect`, `net.set_timeout`, `net.read_all`
- **`NetError` enum** — Timeout, ConnectionRefused, DnsFailure, TlsError, InvalidUrl, BindError, ProtocolError
- **Fixes** — typecheck string methods, Result/Option type mismatches for enums/generics, nested compound type codegen, trait dispatch, LSP parser reset, async spawn, daemon parser reset

## What's New (v0.21)

- **`Set[T]` builtin type** — generic hash set with `insert`, `remove`, `contains`, `len`, `is_empty`, `union` methods
- **LSP completion** — dot-triggered symbol + keyword completion with type info
- **LSP documentSymbol** — file symbol listing with kinds and ranges
- **LSP signatureHelp** — function signature display on `(` and `,` with active parameter highlighting
- **LSP rename** — cross-file symbol rename
- **LSP codeAction** — quickfix actions from diagnostics
- **Fix** — stdlib diagnostic paths normalized to strip `build/` prefix

## Breaking Changes (v0.20)

- **BREAKING: `path_param()` removed** — replaced by `req_path_param(req, name)` on the Request object (per-request instead of global state)
- **Trait declarations** — builtin traits for all core types: Sized, Contains[T], StrOps, ListOps[T], MapOps[K,V], SetOps[T], BytesOps, StringBuildOps, Joinable
- **Trait-based method dispatch** — builtin type methods now routed through trait impl registry instead of hardcoded type checks
- **Trait impl validation** — compiler rejects `impl` blocks for undefined traits (E0904), validates method signatures match trait contracts
- **Concurrent HTTP server** — `server_serve_async()` with threadpool, `server_max_connections()` for backpressure
- **Fixes** — struct return from if/else in closures, Map type loss in closures, List[EnumType] codegen, Channel codegen gaps, multi-fn query, 4 codegen/typechecker bugs
- **Perf** — pre-split HTTP route patterns at registration time

## What's New (v0.19)

- **List HOF stdlib** — `list_map`, `list_filter`, `list_fold`, `list_any`, `list_all`, `list_for_each`, `list_concat`, `list_slice` — generic higher-order functions
- **Map HOF stdlib** — `map_for_each`, `map_filter`, `map_fold`, `map_map_values`, `map_merge`
- **String ops → Blink stdlib** — `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower` migrated from C runtime
- **HTTP client → Blink stdlib** — full HTTP client migrated from C runtime to Blink
- **Data enums in List** — `push`, `get`, and `match` now work with data enum elements
- **LSP textDocument/references** — find all usages of a symbol across files
- **Test compilation ~3x faster** — parallel test compilation on multi-core machines
- **Package system v1** — git + path dependencies verified end-to-end
- **Fixes** — generic monomorphization Option[T]/Result[T,E], match expression type inference for pattern bindings, diagnostic file attribution for @module("") modules, pub visibility in generic type params

## What's New (v0.18)

- **Stdlib migrations** — Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Blink stdlib
- **I/O primitives** — `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)`

## What's New (v0.17)

- **Stdlib migrations** — Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Blink stdlib
- **I/O primitives** — `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)` — stdin/stdout binary and line-oriented I/O
- **StringBuilder extras** — `.write_int(n)`, `.write_float(f)`, `.write_bool(b)`, `StringBuilder.with_capacity(n)`

## What's New (v0.16.1)

- **Bugfix** — git dependency import resolution used wrong cache subdirectory

## Breaking Changes (v0.16)

- **pub visibility enforcement** — enum variants, trait names, type references, and `let`/`const` bindings must be `pub` to use across modules. Existing cross-module references to non-pub items will now error.
- **`--trace` → `--blink-trace`** — compiler phase tracing flag renamed to avoid conflicts
- **`std.path` module** — `path_join`, `path_dirname`, `path_basename` moved from C builtins to `import std.path` (stdlib). Old builtin calls still work but prefer the import.
- **StringBuilder type** — new compiler-intrinsic `StringBuilder` with `new()`, `write()`, `write_char()`, `to_str()`, `len()`, `capacity()`, `clear()`, `is_empty()`
- **`--dump-ast` flag** — dump parsed AST for debugging
- **Auto-resolve deps** — `blink build/run/test/check` now auto-resolves dependencies (no manual `blink update` needed)
- **Self-bootstrap** — compiler bootstraps from PATH `blink`; no checked-in C bootstrap files
- **Quiet test output** — `blink test` is quiet by default; use `--verbose` for detail
- **Perf: O(N²) concat → StringBuilder** — lexer/formatter performance improvement
- **Bugfixes** — lockfile not loaded on second build, 3,718 compiler warnings eliminated, CT_TAGGED_ENUM leak as Void, nested list element type lost in type pool

## What's New (v0.15)

- **FFI system** — `@ffi("lib", "symbol")` annotation, `@trusted` audit marker, `Ptr[T]` type with methods (deref, addr, write, is_null, to_str, as_cstr), `ffi.scope()` resource management (alloc, cstr, take)
- **Keyword arguments** — named arguments in function calls: `fn(pos, name: val)`
- **`@allow` diagnostic suppression** — suppress specific warnings: `@allow(W0600)`
- **`@invariant` struct assertions** — struct-level invariants: `@invariant(self.balance >= 0)`
- **Vendored C cross-compilation** — compile vendored C sources with cross-compile support; SQLite3 amalgamation bundle included
- **`blink audit`** — FFI audit command: inventory @ffi calls, audit status, pointer operations
- **`blink update`** — updates dependencies, lockfile, and stamps `blink-version` in `blink.toml`
- **Native dependencies** — `blink.toml [native-dependencies]` section for linking C libraries
- **Bugfixes** — `\r` escape bootstrap, comment preservation in type/trait/impl bodies, UnaryOp type inference, TokenKind type annotations

## What's New (v0.14)

- **Unused variable warnings** — compiler emits W0600 for `let` bindings that are never read; prefix with `_` to suppress
- **Cross-compilation fix** — removed spurious libcurl link dependency that caused linker failures on non-host targets

## What's New (v0.13.3)

- **`List[List[T]]` function parameter fix** — nested list parameters now propagate inner element types correctly (`.get()` on inner list no longer produces `blink_Option_int`)

## What's New (v0.13.2)

- **Nested struct type propagation** — `List[List[Struct]]` and `Option[List[Struct]]` now correctly propagate inner struct types through `for` loops, `let` bindings, `??`, `.unwrap()`, and `match Some(x)`

## What's New (v0.13.1)

- **`List[List[T]]` codegen fix** — `.get()`, `.pop()`, `.unwrap()`, and `??` on nested lists now produce correct C types (`blink_Option_list` instead of `blink_Option_int`)
- **Extended string lexer fix** — `"#{"` no longer misparsed as end delimiter in extended strings

## What's New (v0.13)

- **SQLite `db.*` namespace** — 16 methods for database operations: `db.open`, `db.exec`, `db.execute`, `db.query`, `db.query_one`, `db.prepare`, `db.bind_int`, `db.bind_text`, `db.bind_real`, `db.step`, `db.column_text`, `db.column_int`, `db.reset`, `db.finalize`, `db.close`, `db.errmsg`
- **`blink.toml` versioning** — `blink init` stamps `blink-version` in project manifest
- **`\r` escape sequence** — carriage return now supported in string literals

## What's New (v0.12)

- **Tuple destructuring** — `let (a, b) = some_tuple` in let bindings
- **Extended strings** — `#"literal "quotes" and \backslashes"#` with `#{expr}` interpolation
- **Struct field defaults** — `type Point { x: Int = 0, y: Int = 0 }`, omit fields at construction
- **`@requires` contracts** — precondition annotations on functions
- **Nested generics** — `List[List[Int]]` and other parameterized inner types
- **`--release` flag** — optimized builds with `-O2`
- **Multi-target builds** — `bin/blink build -T linux -T macos-arm64`
- **Error catalog** — `blink explain E1234` with machine-applicable fix suggestions
- **Closure const-qualifier fix** — eliminated dozens of C compiler warnings in bootstrap
- **List[T] param fix** — struct element types now preserved through function parameters
- **`mod {}` parser error** — helpful E1015 error instead of generic parse failure

## What's New (v0.11.1)

- **Cross-module error locations** — diagnostics in imported modules now report the correct source file (was always showing main file)

## What's New (v0.11)

- **`blink doc --list`** — list available stdlib modules for discoverability
- **Type error locations** — type errors now report source file + line number
- **`set_version(p, ver)`** — set version string on ArgParser (shows in `--version` / help)
- **`args_get_all(a, name)`** — get all values for a repeated option (returns `List[Str]`)
- **`parse_argv(p, argv)`** — parse an explicit argv list instead of process args
- **`add_command_alias(p, alias, target)`** — register command aliases in CLI parser
- **Better CLI error messages** — bare-word errors in argument parsing

## What's New (v0.10)

- **`blink doc <module>`** — print module documentation (types, functions, traits with signatures and doc comments). Supports `--json` for machine-readable output
- **Embedded stdlib** — stdlib modules are compiled into the CLI binary; `blink doc std.args` works without source files on disk
- **Stdlib doc comments** — `///` doc comments with examples added to std.args, std.json, std.toml, std.semver, std.http_*

## What's New (v0.9)

- **List pattern matching** in `match`: `[]`, `[a, b]`, `[first, ...]` with rest wildcard
- **Nested subcommands** in `std.args`: dotted paths (`add_command(p, "daemon.start", ...)`), `args_command_path()` returns `List[Str]`
- **Parallel test execution**: `blink test --parallel` / `-P` (default 4 workers)
- `blink init` now idempotent for existing projects

## Breaking Changes (v0.8)

- `str_from_char_code()` removed → use `Char.from_code_point(n)` (returns `Str`)
- `\b` (backspace) and `\f` (form feed) escape sequences added
- CLI flags now scoped to subcommands

## What's New (v0.7)

- `process_exec(cmd, args)` — exec a binary directly (replaces current process)
- `args_rest(a)` — get remaining args after `--` from argparser
- 5 codegen/lexer bugfixes, test suite migrated to `test` blocks, CI parallelized

## Breaking Changes (v0.6)

- `List.get(idx)` returns `Option[T]` (was `T`). Use `?? default` or `match`.
- `const NAME = expr` for compile-time constants (was `let` at module level).
- `#embed("path")` compile-time file inclusion intrinsic.
