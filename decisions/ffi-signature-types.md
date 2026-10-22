[< All Decisions](../DECISIONS.md)

# FFI Signature Types — Design Rationale

**Resolution:** one closed list says which types an `@ffi` parameter or return may use. The compiler checks the list at the declaration, after alias expansion. A type that is not on the list is the new error `FfiIncompatibleType` (E0848). `Str` is not on the list: a `Str` parameter is E0848, and its `help:` gives the `ffi.scope` fix. `@trusted(audit: K)` does not cover E0848 and `@allow` does not suppress it. `lib/std` binds the Blink runtime with `@runtime("blink_...")`, which is outside the list and legal only in `lib/std`. Use of `@runtime` anywhere else is the new error `InvalidRuntimeBinding` (E0849).

**Vote:** Q1 6-0 (L1); Q2 6-0 (S0); Q3 5-1 (T1; Minimalism: T2); Q4 5-1 (RB1; Minimalism: RB3+); spelling `@runtime` 5-1 (Web: `@ffi.runtime`). AI-First 5/5 pass.

## The Gap

An `@ffi` signature is an audited claim, but the compiler accepted every type in every position. Each case below checked clean, and then either emitted wrong C or emitted C that does not compile.

| Signature | Result before this decision |
|---|---|
| `fn f(n: Int) -> Option[Never]` | checks; C can produce `Some(x)` with `x : Never` |
| `fn f(name: Ptr[U8]) -> Option[Str]` | checks; the generated C does not compile |
| `fn f(n: Never) -> Int` | checks; the prototype says `int64_t` |
| `fn f(s: Str) -> Int` | checks; C gets a runtime-layout pointer the spec never describes |

`decisions/ffi-never-return.md` left the general rule open (see its *Open gap*). `lib/std` has about 130 bodiless `@ffi("blink_...")` declarations that use `Str`, `List[T]`, closures and `! FFI`. Any closed list rejects them.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. No Phase D ran: no question closed closer than 5-1.

#### Phase A — Independent proposals (excerpts)

All six seats chose the same first proposal: one closed list, checked at the declaration, with one new code. They differed on three variations (`@ffi.struct` by value, `Buf[T]`, a `Str` input form) and on the `lib/std` bridge.

- **Systems:**

  > My test for every type in an `@ffi` signature is one question: **what C type does the prototype spell, and does the C ABI carry the Blink value with no hidden work?**

  On the bridge: "Proposal: the sys-1 rule applies to **every** `@ffi` decl. The runtime bridge moves to its own lib/std-only form (working name `@runtime("blink_sb_write")`), which is not part of the user language: a use outside lib/std is a compile error."

- **Web/Scripting:**

  > Any closed list with a good `help:` line beats what we have. The fight is over which list.

  Web's first choice was a `Str` input form: "**web-2 is my first choice**; web-1 is an acceptable fallback". web-2 text: "`Str` is FFI-compatible **as an `@ffi` parameter**. C receives a read-only, NUL-terminated UTF-8 `const char *` that is valid for the duration of the call."

- **PLT:**

  > So the fix is a closed inductive set, defined once and checked at the declaration. It must not be a list of bad cases. A closed set closes `Option[Never]` by construction, so we need no `FfiNeverPosition` code, which matches Q5 of ffi-never-return.md.

  On the bridge: "The runtime ABI is a property of the declaration, so it belongs on the declaration and not on the file's location. Give it its own marker, for example `@ffi.runtime("blink_sb_write")`."

- **DevOps:**

  > An error in C the user did not write is the worst diagnostic a toolchain can give. Any rule is better than that.

  On the bridge: "Grep and LSP can tell the two forms apart by attribute, not by path or symbol prefix."

- **AI/ML:**

  > Define the term once, then give each position a short "plus" list. One concept, one table, one diagnostic. A model holds one list in its head, not four.

  On the bridge: "Do not exempt them silently inside `@ffi`: a model that reads `lib/std/sb.bl` would learn that `@ffi` takes `Str`, `! FFI` and a `{}` body, which §9.1 forbids."

- **Minimalism:**

  > The gap is not a missing idea. It is a missing sentence that says the same set governs the signature.

  And: "A closed list is the minimal choice for a second reason: widening a closed list later is backward compatible, narrowing an open one is a breaking change." On the bridge: "do not write a lib/std exemption into sections/. That would be a second, hidden FFI dialect in the spec."

#### Phase B — Debate highlights (1 round)

The moderator grouped the proposals into the list (L1) and four variations: V1, `@ffi.struct` by value; V2, `Buf[T]`; V3, `Str` as an input-only parameter; V4, a sentence on `@trusted`. Bridge options: RB1 (a form only `lib/std` may use, defined in sections/), RB2 (the spec exempts `blink_*` symbols in `lib/std`), RB3 (nothing in sections/).

Key shifts:

- **Minimalism conceded V1 and V2.** V1: "I stop resisting. One condition: the row says "an `@ffi.struct` type", with no extra rules for nested structs. Each field already follows E0812." V2: "L1 must not restate the `Buf` rules. It should say "`Buf[T]` as §9.1.3.2 allows" and point there".
- **AI/ML moved to support the `Str` form (V3).** "What decides it for my seat: Token cost. A string input is the most common FFI parameter." It also asked the other seats: "if you keep `Str` out, say which hazard web-2 adds that `scope.cstr` does not already have. I could not find one." AI/ML ended Phase B "not ready: V3".
- **PLT, Systems, DevOps and Minimalism opposed V3.**
  - PLT: "web-2 is sound only if every `Str` is one contiguous, NUL-terminated buffer, or if the compiler inserts a copy for one that is not. The spec states neither." And: "It is additive later; the reverse is breaking. [...] A rule should fail closed."
  - PLT on lifetimes: "Scope tags and E0601 govern every pointer that Blink gives to C (`as_cstr`, `scope.cstr`, `Bytes.with_ptr`). A `Str` parameter gives C an address whose lifetime is only "for the call", and only an audit sentence states that limit."
  - Systems: "The cost of a binding would change with a runtime change the author never sees. That is exactly the hidden cost sys exists to refuse."
  - DevOps: "`putenv(name: Str)` checks clean, and the bug shows up as a use-after-free with no diagnostic to point at."
  - Minimalism: "A promise that is free today and may cost an allocation tomorrow is the exact thing the signature should not hide."
- **Web held the `Str` form and asked for a record.** "web-2 is a strict superset of L1, so nothing breaks if it comes later. If V3 loses, I ask that the decision file record it as **deferred, not rejected**, with one trigger: once real bindings show the `scope.cstr` wrapper on most string calls, a spec ticket reopens it."
- **Web moved from RB2 to RB1.** "devops-2 changed my mind with an argument from my own domain: users and models copy lib/std."
- **`c_strtod`.** Minimalism found that `lib/std/num.bl` `c_strtod(text: Str)` binds a real libc symbol. Systems: "it shows RB2's prefix test would not even catch the real problem case (wrong prefix direction: a real C symbol with a non-C type)."
- **PLT's amendment to the crossing sentence.** "If V1 is in, the crossing sentence must say: a parameter whose type contains `H` is a consume crossing, and a return type that contains `H` is a produce crossing. [...] Without this sentence a handle can be minted through `-> S` and no crossing records it."

#### Phase C — Final vote

Each panelist voted alone on a written ballot.

##### Q1 — The signature rule — **L1** (6-0)

- **Systems: L1.** "Every type on the list has exactly one C spelling and crosses the call with no copy, scan, box or tag, so the compiler prints the prototype directly and `cc` applies the platform ABI (by-value structs included)." Concern: "If the checker reads the type before alias expansion or misses a nested position (a `Ptr[FS]` field path, `Option[Alias]`), one hole stays open and emits bad C again, so the implementation needs a probe row for each rejected shape".
- **Web/Scripting: L1.** "A closed list that fails at `check`, on the user's own line, with a fix in the `help:` line, is the biggest DX gain in this ticket." Concern: "If the `help:` table is thin, users get "not FFI-compatible" with no way forward".
- **PLT: L1.** "L1 is a closed set that one pass over the signature checks, so it fails closed. A type Blink adds later is outside the set until a vote puts it in." Concern: "The writer could copy the scalar list into E0810 and E0812 again instead of making them refer to the L1 set, and the three lists would then drift apart again".
- **DevOps: L1.** "A closed list gives one error code at the one wrong type node. Each type is reported once, and the specific codes (E0828, E0810, the `Buf` rules) keep their sites, so the LSP shows one squiggle per problem." Concern: "If the alias-expanded type is the one the error names, the user sees a type they did not write."
- **AI/ML: L1.** "A closed allow-list with one code and a help line for each type is the shape a model can learn from the spec alone." Concern: "a model reading L1 next to E0810 will see two lists that disagree."
- **Minimalism: L1.** "L1 adds one rule and one code and no new type, form or conversion." Concern: "By-value `@ffi.struct` widens the C ABI surface that codegen must get right on each target".

##### Q2 — `Str` as a parameter — **S0** (6-0)

S0: no `Str` in an `@ffi` signature. S1: `Str` as an input-only parameter. Web and AI/ML backed S1 in Phase B and voted S0 here.

- **Web/Scripting: S0.** "Three of plt's arguments change my vote. First, if we add `Str` later, nothing breaks, but if we take it back, user code breaks, so the rule should fail closed." And: "The decision file must record web-2 as **deferred**, and the trigger to reopen it is evidence from real bindings that most string parameters need the `scope.cstr` wrapper."
- **AI/ML: S0.** "plt answered it: a `scope.cstr` pointer carries a scope tag and E0601 checks it, but a bare `Str` gives C an address that only an audit sentence limits." And: "The token cost of the `ffi.scope` wrapper is real, so the decision file should record web-2 as deferred, with web's trigger, not as rejected." Concern: "the E0848 help line for a `Str` parameter must show the full `with ffi.scope() as scope { ... scope.cstr(name) ... }` fix".
- **PLT: S0.** "S1 is sound only if every `Str` is one contiguous NUL-terminated buffer, or if the compiler inserts a hidden copy." Concern: "The deferral must be recorded as a ticket, or the DX cost stays and nobody reviews it again."
- **Systems: S0.** "`scope.cstr` keeps that cost and lifetime in the source. S0 is a strict subset, so S1 can still land later with no break."
- **DevOps: S0.** "L1 is a strict subset of S1, so S1 can come later with evidence and no break. I support recording web-2 as deferred, with web's trigger." Concern: "If it only says "use `Ptr[U8]`", users will hit `as_cstr` lifetime errors next and blame the rule."
- **Minimalism: S0.** "S1 adds a second way to pass a string, plus a choice rule the spec must teach and a lint to enforce it." Concern: "the `help:` text for a `Str` parameter must name the exact `scope.cstr(s)` fix".

Web-2 is **deferred, not rejected**. Trigger: real bindings show that most string parameters need the `scope.cstr` wrapper. The spec does not describe a later `Str` form.

##### Q3 — `@trusted` and the new error — **T1** (5-1)

T1: one sentence in §9.1 says `@trusted(audit: K)` does not cover E0848 and `@allow` does not suppress it. T2: no new sentence; the audit-gated list already omits the code.

- **Systems: T1.** "An audit says a claim is true. It cannot make a type with no C spelling well-formed, because the emitted C is wrong whatever the auditor writes."
- **Web/Scripting: T1.** "T2 makes the reader find the answer by its absence from a list at 07:192-194, and nobody reads a spec that way." Concern: "The sentence must sit in the rule paragraph itself, not in a footnote."
- **PLT: T1.** "no audit claim can give a type a C representation. If the rule says so in its own text, nobody needs to find out by reading a list somewhere else that the code is missing from it."
- **DevOps: T1.** "The first FAQ after L1 lands will be "I added `@trusted(audit: ...)`, why does it still fail?"" Concern: "The sentence must say "does not cover" in the same words as the catalog row and the `note:`."
- **AI/ML: T1.** "A model that gets an error on a decl that already has `@trusted` will try to widen the trust or add `@allow`." Concern: "the text must name both."
- **Minimalism: T2 (dissent).** "07:192-194 says the audit-gated mechanism is stated once "for every diagnostic that uses it. No other section restates it." A §9.1 sentence would restate it and start a habit of a "trust does not cover X" line for each new error." Concern: "the next FFI error will also want its own "trust does not cover this" sentence".

##### Q4 — The `lib/std` runtime bridge — **RB1** (5-1); spelling **`@runtime`** (5-1)

RB1: §9.1 defines the form in a short paragraph. RB3+: one sentence in sections/, the rest in docs/build/.

- **Systems: RB1, `@runtime`.** "The runtime bridge uses a different ABI from C: `Str`, `List[T]` and closures have a layout the compiler owns. It needs its own form that the compiler checks, not a prefix test (RB2)".
- **Web/Scripting: RB1, `@ffi.runtime` (dissent on spelling).** "A marker they see there must be one they can look up in the spec. With RB1 they find a short paragraph, and if they use the marker outside lib/std, its own error tells them why it fails." And: "`@ffi.runtime` sits beside `@ffi.struct` and `@ffi.opaque`, so the LSP lists it in the family users already know." Concern: "The paragraph could grow into a second FFI dialect with its own type rules in the user spec."
- **PLT: RB1, `@runtime`.** "The ABI is a property of the declaration, so the typing rule should depend only on syntax. `@ffi` means the C ABI and L1, and `@runtime` means the runtime ABI and lib/std only." Concern: ""The runtime's own ABI" may stay undefined in the spec, so the form becomes a hole with no rule that limits its types. The paragraph should at least say that the compiler and runtime own those signatures as part of the trusted base."
- **DevOps: RB1, `@runtime`.** "A form that has its own error needs a catalog row and a spec section, or `blink explain` points at nothing." And: "The outside-lib/std error should also fire for a non-`blink_*` symbol under `@runtime`, so the form cannot be used to skip L1."
- **AI/ML: RB1, `@runtime`.** "the `ffi.` prefix tells a model "this is a kind of `@ffi`", and the model will then carry the bridge's freedoms (`Str`, closures, generics) back into `@ffi`." Concern: "If the outside-lib/std error is not clear ("`@runtime` binds the Blink runtime and is reserved to lib/std; for a C function use `@ffi`"), models that copy lib/std will get stuck there."
- **Minimalism: RB3+, `@runtime` (dissent).** "No user can write the bridge form, so it is not language surface. Its spelling, its exemptions and its error are facts about how the compiler builds its own stdlib, and they belong in docs/build/, not in sections/." Concern: "If RB1 wins, the spec takes on a semantics paragraph and an error code for a form that only the compiler team can use".

#### No Phase D

No question closed closer than 5-1, so the moderator ran no Phase D.

#### AI-First Review

- Learnability: pass. One closed list, one code, and a `help:` line for each shape written; the spec shows the full `Str` fix.
- Consistency: pass. The list reuses the term FFI-compatible, and E0810, E0812, E0828 and the `Buf` rule keep their own sites. One report for each type.
- Generability: pass. A model that translates a C header line by line writes a legal signature, including structs by value and `Option[H]`.
- Debuggability: pass. The error names the type and the position, and its note says `@trusted` and `@allow` do not help. `@runtime` outside `lib/std` has its own error with a `help:`.
- Token efficiency: pass. One new list and two codes; the `Str` input needs a three-line wrapper, which the decision accepts and records as deferred.

### Final Spec

```blink
@ffi.opaque(header: "sqlite3.h", name: "sqlite3")
type Sqlite3

@ffi.struct(header: "time.h", name: "timespec")
type Timespec {
    tv_sec: Int,
    tv_nsec: Int,
}

// Legal
@ffi("sqlite3", "sqlite3_next_stmt")
@trusted(audit: "DB-005")
fn raw_next(db: Sqlite3) -> Option[Sqlite3] ! IO

@ffi("c", "abort")
@trusted(audit: "LIBC-ABORT")
fn c_abort() -> Never ! ()

@ffi("c", "getenv")
@trusted(audit: "ENV-001")
fn raw_getenv(name: Ptr[U8]) -> Ptr[U8] ! Env

pub fn getenv(name: Str) -> Option[Str] ! Env {
    with ffi.scope() as scope {
        raw_getenv(scope.cstr(name)).to_str()
    }
}

// Illegal: E0848
@ffi("c", "getenv")
@trusted(audit: "P")
fn bad_str(name: Str) -> Ptr[U8] ! Env

@ffi("c", "getenv")
@trusted(audit: "P")
fn bad_option(name: Ptr[U8]) -> Option[Str] ! Env

@ffi("c", "abs")
@trusted(audit: "P")
fn bad_never(n: Never) -> Int ! ()
```

```blink
// lib/std only
@runtime("blink_sb_write")
fn sb_write(mut sb: StringBuilder, s: Str)
```

Locked points:

- One closed list, checked at the `@ffi` declaration, after alias expansion (Q1). A parameter is a sized scalar (`I8 I16 I32 Int U8 U16 U32 U64 F32 Float Bool`), `Ptr[T]` (E0810 governs `T`), `Buf[T]` (§9.1.3.2), an `@ffi.opaque` type `H` or `Option[H]`, or an `@ffi.struct` type by value. A return is one of those, or `()`, or `Never` as the whole return type. An `@ffi` fn has no type parameters.
- The only type arguments are the `T` of `Ptr[T]` and `Buf[T]` and the `H` of `Option[H]`.
- One report for each type: `Void` keeps E0828, a bad `Ptr` argument keeps E0810, a bad `Buf` argument keeps its own rule. E0848 covers every other type. `Str`, `Option[Str]`, `Bytes`, `List[U8]`, `Option[Int]`, `Option[Never]`, a `Never` parameter, a plain struct, a closure type and a type parameter are E0848.
- The E0810 and E0812 text does not copy the scalar list.
- A parameter whose type contains `H` is a consume crossing. A return type that contains `H`, or a `Ptr` out-cell whose pointee contains `H`, is a produce crossing.
- `Str` has no parameter form (Q2). The `help:` for a `Str` parameter gives `Ptr[U8]` and `scope.cstr(s)` inside `ffi.scope()`. A later `Str` form is deferred; the spec does not describe one.
- `@trusted(audit: K)` does not cover E0848, and `@allow` does not suppress it. The `note:` of E0848 and its catalog row say the same (Q3). The audit-gated subsection is unchanged.
- `@runtime("blink_...")` is legal only in `lib/std`, binds only `blink_*` runtime symbols, and is outside the list (Q4). Any other use, and a symbol that does not start with `blink_`, is E0849. The list binds every `@ffi` declaration with no exception clause.
- `@ffi("symbol")` binds only `c` and `m` symbols.
- The `help:` table: `Str` parameter, `Ptr[U8]` and `scope.cstr(s)`; `Str` or `Option[Str]` return, `Ptr[U8]` and `.to_str()`; `Bytes` or `List[U8]`, `Bytes.with_ptr` or `Buf[U8]`; `Option` of a type that is not a handle, the bare type; `Option[Never]`, `-> Never`; `Never` parameter, remove it; plain struct, `@ffi.struct`; closure type, not supported; type parameter, one declaration for each type.

### Concerns for implementation

- By-value `@ffi.struct` widens the C ABI surface on every target. The compiler must pass or reject it correctly on each one (Minimalism).
- Do not copy the scalar list into the E0810 and E0812 text. They point to the one list (PLT).
- Expand aliases before the check, and test every nested position. Write one test for each rejected shape (Systems).
- If the `lib/std` migration lags, `lib/std` must not keep `! FFI` on the old bridge declarations. That row teaches the E0538 contradiction (Systems).
- Move `lib/std/num.bl` `c_strtod(text: Str)` to `Ptr[U8]` as an ordinary `@ffi` declaration. Migrate the bridge declarations to `@runtime` as a chore, in the three bootstrap steps (add the form, move `lib/std`, enforce the rule) (Minimalism, Systems, DevOps).
- A ratchet row on the count of old-form bridge declarations keeps the migration from stalling (DevOps).
- The E0848 message prints an alias as written and adds a `note:` with the expanded type (DevOps).
- A ticket records the deferred `Str` form and its trigger (PLT, Web).

### Related

- `decisions/ffi-never-return.md` left the general rule open; this decision closes it.
- Two friction items go to the backlog and were not voted here: the `Ptr` pointee list in E0810 lacks `F32`, `Bool`, `@ffi.opaque` and `@ffi.struct`; the lists write `Int` and `Float` where some spec text writes `I64` and `F64`.
