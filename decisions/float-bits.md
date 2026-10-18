[< All Decisions](../DECISIONS.md)

# Float Bits — Design Rationale

**Gap:** Float display renders `-0.0` as `0.0` and every NaN as `NaN` (§3.6 *Float Text Form*), so no Blink program can write the sign of zero or a NaN payload as text. Systems dissented on that ruling, and every seat that voted for `0.0` asked for a bit-exact path. The ticket asked: `Float.to_bits() -> U64` / `Float.from_bits(U64)`, a hex float text form, or both. The spec also gave `1.0 / x < 0.0` as the sign test, and the float-ieee-eq ruling said a later `to_bits()`/`is_sign_negative()` must replace that line.

```blink
fn main() {
    let z = -0.0
    io.println(z.display())     // 0.0 — no way to print "-0.0" or the bit pattern
}
```

## Result

| Question | Result | Vote |
|---|---|---|
| Settled in Phase A | A built-in bits pair on `Float` (`U64`) and `F32` (`U32`), no import; `from_bits` static and total; no NaN canonicalization; no hex float text form; *Float Text Form*, `==`, `Ord` and E1400 unchanged | all six proposals |
| Q1 Name | `to_bits()` / `from_bits()`, and §3c.3 now covers only `to_X` where `X` names a type (PLT's draft, "names a type" in place of "names a scalar type") | 6-0 |
| Q2 Sign | `is_sign_negative()` on `Float` and `F32` now; it replaces both `1.0 / x < 0.0` lines and the example assert. No `copysign`, `signum` or `is_sign_positive` | 6-0 |
| Q3a Help lines | A bitwise operator on a `Float` gets a help line that names `to_bits()`; no suggestion when `.to_bits()` is called on an integer | 6-0 |
| Q3b `-0.0` warning | A follow-up ticket, to ship before the next release, with the cases listed | 4-2 (DevOps, AI/ML dissent: in this change) |
| Q4 Const | No const `from_bits`; a follow-up goes with the `const fn` work | 6-0 |
| Q5 Laws | L1–L5 included 6-0; L6 excluded | L6 5-1 (AI/ML dissent) |
| Q6 Placement | H: a `####` heading *Float Bits* right after *Float Total Ordering*, with a pointer from *Float Text Form* | 4-2 in Phase D (Sys, Min dissent for P); 3-3 in Phase C |
| Q7 Literals above `Int` max | A separate, high-priority ticket; spec examples avoid literals at or above `0x8000000000000000` | 6-0 |

AI-first review: 5/5 pass, with one caveat on Debuggability: the silent `x == -0.0` trap stays until the Q3b follow-up lands. The user signed off on the tally and on the soft-consensus reading of Q3b (the majority's Concern fields endorse the dissent's point and ask that the follow-up ship before the next release).

**Conditions on Q6 (from the Phase D ballots).**
- *Float Bits* holds only the bits pair, `is_sign_negative` and laws L1–L5. Anything else needs a new vote (PLT, Web, Sys, Min, AI/ML).
- The llms-full.md *Float Methods* entry gets the three methods and the NaN-sign sentence (AI/ML; supported by Sys, PLT, DevOps, Min).
- Help lines name `to_bits()` exactly (Web, DevOps, Min in Phase C).

**Consequential edit.** The `parse_float` bullet said "A sign on `nan` has no effect. Blink has one NaN". With a bits path, that is false at the bit level. It now reads "A sign on `nan` has no effect under `==`: every NaN is `==` every other NaN". Which bit pattern `parse_float("-nan")` returns is a separate question.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are each panelist's own reply, verbatim; only heading levels are changed and local ticket IDs removed.

#### Phase A — Independent proposals

##### Systems

###### Systems seat, Phase A: a bits path, and no hex text form

###### Proposal 1 (primary): `to_bits` / `from_bits` as built-in methods

**API (no import, the same as `ieee_eq`):**

| Method | Signature |
|---|---|
| `Float.to_bits` | `fn(self) -> U64` |
| `Float.from_bits` | `fn(bits: U64) -> Float` (static, total) |
| `F32.to_bits` | `fn(self) -> U32` |
| `F32.from_bits` | `fn(bits: U32) -> F32` (static, total) |

```blink
fn main() {
    let z = -0.0
    io.println(z.display())                    // 0.0
    io.println(z.to_bits().display())          // 9223372036854775808
    assert(z.to_bits() >> 63 == 1)             // the sign of zero
    assert(0.0.to_bits() >> 63 == 0)

    let nan = Float.from_bits(z.to_bits() | 0x7ff8000000000001)
    assert(nan.is_nan())                       // needs import std.float
    assert(nan.to_bits() == z.to_bits() | 0x7ff8000000000001)  // payload kept

    let w = F32.from(1.5)
    assert(F32.from_bits(w.to_bits()) == w)
}
```

**Why these names and this shape.**
- `U64` and not `Int`. The sign bit is the high bit. On `U64`, `>>` is a logical shift, so `bits >> 63` gives `0` or `1`. On `Int`, the shift is arithmetic and `>> 63` gives `-1` for a negative value, which is a trap for users. `U64` is also what `hash` returns, so the type is not new to users.
- `from_bits` is total. Every 64-bit pattern is a valid binary64 value, so `Option` would only add an unwrap that can never fail. This is not like `Enum.from_int`, where some inputs have no value.
- A built-in, not a `std.float` function. This is a primitive of the type, the same as `ieee_eq`. It must also be const-evaluable, so that a program can write `let NEG_ZERO = Float.from_bits(...)` at top level. It obeys "Stdlib API surface: methods only".

**What it compiles to.** The C printer emits `memcpy(&u, &d, 8)` (or a union read). gcc and clang at -O2 turn that into one `movq %xmm0, %rax`, or nothing when the value is already in a general register. It adds no call, no branch and no check. For constant input, const-eval folds it. It is zero cost.

**The hard rule the spec must state: no NaN canonicalization.** `to_bits` returns the exact stored bits, and `from_bits` stores the exact bits it receives. That includes a signaling NaN. On x86-64 SSE, AArch64 and RISC-V, a plain move keeps every bit. On i386 x87, a load quiets a signaling NaN, so the codegen must move the value through integer registers there. I accept that cost, because a bits path that can lose bits is worthless. Arithmetic is a different matter: IEEE 754 does not fix the payload a NaN result gets, so the spec must not promise one.

**The `1.0 / x < 0.0` line (decided item 2) must change in the same commit.** That test has three faults:
- It costs a divide, about 13 to 20 cycles of latency.
- It raises the divide-by-zero flag.
- It is wrong for NaN: `1.0 / NaN < 0.0` is false whatever the sign is.

Replace it at both places with `x.to_bits() >> 63 == 1`. That is one bit test, and it is correct for every value, NaN included.

**Proposed spec text (§3.2, beside *Float Total Ordering*):**

> **Float bits.** `x.to_bits()` returns the IEEE 754 binary64 bit pattern of `x` as a `U64`. `Float.from_bits(b)` returns the `Float` whose bit pattern is `b`. Neither one changes any bit: `Float.from_bits(b).to_bits() == b` for every `U64` `b`, NaN payloads and signaling NaNs included, and `Float.from_bits(x.to_bits()) == x` for every `x`. Both are const-evaluable. `F32.to_bits() -> U32` and `F32.from_bits(U32) -> F32` do the same for binary32. Arithmetic on a NaN may return a NaN with a different payload; only these methods keep the bits.
>
> To test the sign of any `Float`, zero and NaN included, use `x.to_bits() >> 63 == 1`.

The *Float Text Form* paragraph changes to: "The text does not show the sign of zero or the bits of a NaN… To see them, use `x.to_bits()` (*Float bits*)."

**Hash.** `to_bits` does not reopen E1400. A user who keys a `Map` by `x.to_bits()` chose bit identity on purpose, and the key type is `U64`, not `Float`. That is the correct escape route, and the spec could name it in the "Round to an integer key instead" sentence.

**Cross-language.** Rust has `f64::to_bits` / `from_bits` (const since 1.83). Go has `math.Float64bits` / `Float64frombits`. Zig has `@bitCast`. Java has `doubleToRawLongBits`; note that Java's plain `doubleToLongBits` canonicalizes NaN, and the spec should copy the raw one. Every systems language ships this pair, and none ships it with an `Option`.

###### Proposal 2: reject a hex float text form (for now)

A hex float form (`-0x0p+0`, `0x1.8p+1`) does not fix the ticket:
- **It loses NaN payloads.** C's `%a` prints `nan`, and Python's `float.hex()` prints `'nan'`. To carry a payload, Blink would need its own grammar that no consumer reads.
- **It adds a second text grammar with an output that is not fixed.** glibc and musl normalize `%a` in different ways. Blink would need a full rule set the size of *Float Text Form*.
- **It is half a feature.** `parse_float` rejects hex input today, and that grammar belongs to a separate ticket.
- **It is not needed for the sign of zero.** Python reads `-0.0` from JSON already, so no wire format needs hex for that. When a program must keep the sign in text, it writes `x.to_bits().display()`, or an explicit `"-0.0"` that it chooses itself.

If a real consumer needs hex text later, that is a separate ticket. It can sit on top of `to_bits` with no new primitive.

###### Out of scope, but needed next (two follow-up tickets)

1. **Bytes.** Postgres binary COPY, `.npy`, protobuf `double` and Arrow all move floats as raw bytes. The real systems path is `b.write_f64_le(x)` / `b.read_f64_le(off)`. With this proposal, a user can build that from `to_bits`, except that `write_i64_le` takes `Int`, so the `U64 -> Int` conversion step needs checking. I ask the moderator to file it as a follow-up.
2. **Integer hex text.** There is no integer hex method, so the bits print only in decimal. This is a separate ticket.

###### Votes I will defend

- Ship `to_bits` / `from_bits` for both `Float` and `F32`, as built-ins, const-evaluable, with no canonicalization.
- No `is_sign_negative` / `copysign` now. Each one is one line on top of `to_bits`, and a later ticket can add them if usage shows the need. I will not die on this hill: if the panel wants `is_sign_negative()` so that the spec line reads well, it costs nothing at run time, and I would accept it.
- No hex float text form.

##### Web/Scripting

###### Web/Scripting seat: Phase A proposal

###### Recommendation: Proposal 1, with no hex float text

###### Proposal 1: three built-in methods, `is_sign_negative`, `to_bits` and `from_bits`

Most people who hit this gap want to answer one question: "is this a negative zero?" A few want the raw bits, for a wire format, a hash or a test that checks bits. Give each group one obvious method.

```blink
fn main() {
    let z = -0.0
    io.println(z.display())                     // 0.0 (unchanged)
    io.println(z.is_sign_negative().display())  // true
    io.println(0.0.is_sign_negative().display())// false

    let b = z.to_bits()                         // U64
    io.println(b.display())                     // 9223372036854775808
    let back = Float.from_bits(b)
    assert(back.is_sign_negative())
    assert(back.to_bits() == b)                 // bit-exact

    let n = Float.from_bits(0x7ff8000000000001.to_u64())  // NaN with payload 1
    assert(n.to_bits() == 0x7ff8000000000001.to_u64())
}

fn write_bits(out: Bytes, x: Float) {
    out.write_u64_le(x.to_bits())
}
```

The `write_u64_le` line is a placeholder. Today `Bytes` has no u64 read/write pair, and its read/write methods take and return `Int`. Proposal 1 does not depend on that line. The `Bytes` u64 pair would be a separate ticket.

Before this ships, check that `0x7ff8000000000001.to_u64()` is valid Blink. That literal is above `Int` max, and it is not clear that an `Int` literal can be that large. If it cannot, the NaN example needs a different way to build the U64.

**The exact shape:**
- `x.is_sign_negative() -> Bool`: true when the sign bit is set. That includes `-0.0`, `-inf` and a NaN whose sign bit is set.
- `x.to_bits() -> U64`: the IEEE 754 binary64 bit pattern. It does not change any NaN to one standard NaN.
- `Float.from_bits(b: U64) -> Float`: never fails, because every U64 is a valid binary64 value. It returns `Float`, not `Option`.
- F32 gets the same three methods, with `U32` in place of `U64`.
- These are compiler built-ins, like `ieee_eq`, so no `import` is needed. A JS or Python developer types `x.` and the method is there. If they have to know about `import std.float` first, that is one more Stack Overflow question. (`is_nan` living behind an import is a wart already. That is a separate chore, not part of this ticket.)

**Replace the `1.0 / x < 0.0` line in both places (~3505, ~4514), in the same change:**

> To test the sign of zero, use `x.is_sign_negative()`. To get the exact bits, including a NaN's payload, use `x.to_bits()`.

Also replace the `assert(1.0 / -0.0 < 0.0)` line in the example under *Float Total Ordering* with `assert((-0.0).is_sign_negative())`.

**Why the `1.0 / x` line must go:** it is a trick. It also gives the wrong answer for NaN: `1.0 / NaN < 0.0` is false even when the NaN's sign bit is set. A web developer will not guess this trick, and the AI that writes Blink code will not guess it either. A trick that has to be documented is the kind of thing that turns into many Stack Overflow questions.

**Proposed spec text (§3 *Float Total Ordering*, new paragraph):**

> **Sign and bits.** `x.is_sign_negative()` returns `true` when the sign bit of `x` is set. This includes `-0.0`, `-inf` and a NaN with the sign bit set. `x.to_bits()` returns the IEEE 754 binary64 bit pattern of `x` as a `U64`. It keeps the sign of zero and a NaN's sign and payload. `Float.from_bits(b)` returns the `Float` whose bit pattern is `b`. For all `b`, `Float.from_bits(b).to_bits() == b`. These methods are not equality: `x == y` does not imply `x.to_bits() == y.to_bits()`. Arithmetic does not keep NaN payloads, so only `from_bits` and `to_bits` keep them. `F32` has the same methods, with `U32` in place of `U64`.

**Tradeoffs (from the seat's view):**
- *Learning curve:* very small. The same names exist in Rust (`to_bits`, `from_bits`, `is_sign_negative`), and Kotlin has `toRawBits` / `Double.fromBits`. JS has `Object.is(x, -0)` for the sign check, plus `DataView` for bits. Python has `math.copysign(1, x) < 0` and `struct.pack('<d', x)`. Each of those languages has the sign check and a bits path, and in every case except Rust the bits path is awkward. Blink gets both as methods.
- *Footgun:* someone could use `to_bits()` as a hash key or as an equality test. The "not equality" sentence covers this, and so do the docs. The E1400 rule (no `Hash` on Float) stays as it is: a user who hashes `to_bits()` chooses that on purpose.
- *Cost:* three methods on each of two types, all built-ins, and all a single C bit-cast (`memcpy`).

###### Proposal 2 (reject): hex float text such as `-0x0p+0` or `0x1.8p+1`

I vote against this, both now and as an extra beside Proposal 1.
- JavaScript has no hex float form. Python has `float.hex()`, but it is used very little. In five years of reading web code, I have not seen it.
- It adds a new text form that has to be lexed, parsed and documented, plus questions about how it interacts with `parse_float` (a separate ticket).
- It does not help the stated consumers. Python's `json`, numpy and Postgres do not read hex floats in JSON. To send `-0.0` across the wire, the user must choose a format either way. A U64 (or `write_u64_le` to bytes) is a format that every language reads.
- If someone needs it later, a library can build it on top of `to_bits()`. YAGNI.

###### Proposal 3 (reject): do nothing / `copysign` only

`copysign` is a math-library name. It answers the sign question only indirectly, and it does not provide a bits path. The ticket asks for a bit-exact path, and every seat that voted for `0.0` asked for one. "Do nothing" breaks a promise this panel already made.

###### Summary vote position

- Yes: `is_sign_negative`, `to_bits`, `from_bits` on `Float` and `F32`, as built-ins.
- Yes: replace `1.0 / x < 0.0` in both places, and the example line, in the same change.
- No: hex float text.
- No change to Float Text Form, to `==`, or to E1400.

##### PLT

###### PLT seat — Phase A proposal

###### Frame: what `==` on Float is

Under the decided total order, Float `==` is an equivalence relation **coarser than identity**: it merges `-0.0`/`0.0` and all 2^53−2 NaN patterns into one class. Float already has an observer that splits a class: `1.0 / x` sends `-0.0` to `-inf` and `0.0` to `+inf`. So Blink never had the Leibniz law "x == y implies f(x) == f(y) for all f" for Float; the spec just does not say so. Any bits API must state this in plain words, or users will assume a law that does not hold. That is the real soundness debt here, more than the missing method.

###### Proposal P1 (my pick): `bits()` / `from_bits()`, no hex text

```blink
fn sign_of_zero_demo() {
    let z = -0.0
    let b: U64 = z.bits()                  // 0x8000000000000000
    io.println(b.display())
    assert(z.is_sign_negative())
    assert(z == 0.0)                       // == still merges the class
    assert(z.bits() != (0.0).bits())       // bits() does not
    let back = Float.from_bits(b)
    assert(back.bits() == b)               // exact round trip
}

fn f32_demo(h: F32) -> U32 {
    h.bits()                               // same shape on F32
}
```

**API (built-in methods, no import, like `ieee_eq`):**
- `Float.bits(self) -> U64`, `Float.from_bits(b: U64) -> Float`
- `F32.bits(self) -> U32`, `F32.from_bits(b: U32) -> F32`
- `Float.is_sign_negative(self) -> Bool`, `F32.is_sign_negative(self) -> Bool`

**Why `bits()`, not `to_bits()`.** §3c.3 has a law: "every `to_` conversion method is sugar over a `From` or `TryFrom` impl … A scalar has no `to_` method without such an impl." `From[Float] for U64` must not exist (a reader would take it as numeric conversion, `3.0 → 3`). So `to_bits` either breaks that law or makes the first exception to it, and one exception means a reader can no longer reason from `to_X` to `From`. `bits()` reads as an observation, like `Ptr.addr()` (§7), and claims no conversion. `from_bits` is a static constructor like `Char.from_code_point` / `Decimal.from_int`; no rule binds it.

**Why `from_bits` returns `Float`, not `Option[Float]`.** Every 64-bit pattern is a valid binary64 value, so the map is total. `Enum.from_int` returns `Option` because some Ints are not tags; that reason does not apply here. An `Option` would only teach users to `unwrap()`.

**Why `is_sign_negative` ships too.** It is the one observer the spec itself needs: decision 2 requires the `1.0 / x < 0.0` line to go in the same change, and a spec that tells users to write `(x.bits() >> 63) == 1` is worse text. It also covers the NaN sign bit, which `1.0 / x` cannot see (`1.0 / NaN` is NaN, `NaN < 0.0` is false) — so the current test is incomplete as well as indirect.

**Why no hex float text form.** Hex float (C `%a`, Java `toHexString`) shows the sign of zero but **not** NaN payloads — C prints `nan`, Java prints `NaN`. It does not close the ticket. It would also be a second text grammar that drags in `parse_float` (out of scope) and its own round-trip law. A library can build hex text from `bits()` with no loss; the integer is the primitive, text is derived.

**Laws to state (these make it sound):**
1. `Float.from_bits(b).bits() == b` for every `b: U64`, NaN patterns included. Codegen must use a bit copy (`memcpy`), never a float load/store path that quiets signaling NaNs. This is a real constraint on x87-style targets and on any later optimizer.
2. `x.bits() == y.bits()` implies `x == y`. The converse fails exactly for the zeros and NaN payloads.
3. `bits()` does not respect `==`. Building `Eq`/`Ord`/`Hash` through it defines a different, finer equivalence. That is legal when done on purpose (a cache keyed by `x.bits()`), but it is not Float `==`.
4. The NaN payload of an arithmetic result is unspecified. Only `from_bits`, `bits`, copy, move and storage preserve it. Without this law, implementations that differ on payload propagation (x86 vs ARM default-NaN mode) make programs non-portable.

**Proposed spec sentences:**

> *§3.6 Float Bits.* `x.bits()` returns the IEEE 754 binary64 bit pattern of `x` as a `U64`. `Float.from_bits(b)` returns the `Float` with bit pattern `b`; it is total, and `Float.from_bits(b).bits() == b` for every `b`. `F32` has the same pair over `U32` with binary32 patterns. `bits()` tells apart values that `==` treats as equal: `-0.0` and `0.0`, and NaNs with different sign or payload. So `x.bits() == y.bits()` implies `x == y`, but not the converse. Arithmetic does not specify the NaN payload of its result; only `from_bits`, copy and storage keep a payload. A bit pattern is not decimal text and is outside *One form everywhere*.
>
> `x.is_sign_negative()` is `true` exactly when the sign bit of `x` is set, including for `-0.0` and for a NaN with the sign bit set.

At ~3505 and ~4514, replace "To test the sign of zero, use `1.0 / x < 0.0`" with "To test the sign of zero, use `x.is_sign_negative()`; to see every bit, use `x.bits()` (*Float Bits*)."

**Cross-language.** Rust `f64::to_bits`/`from_bits`/`is_sign_negative`; Go `math.Float64bits`; Java `doubleToRawLongBits` (the non-raw form canonicalizes NaN — a known trap that law 1 rules out); Haskell `castDoubleToWord64`; OCaml `Int64.bits_of_float`. All take integer bits as the primitive; none uses hex text for it.

**Tradeoffs.** The name `bits` differs from Rust's `to_bits`, and LLM priors favor `to_bits`. An E-code help line that suggests `bits()` on a `to_bits()` call covers that cost. Keeping the `to_` law intact is worth more than matching Rust's name. Cost: three methods per float type.

###### Proposal P2 (fallback): P1 named `to_bits` + amend §3c.3

`to_bits()`, and add "except `to_bits`, which reads the representation" to the `to_` rule. Sound but less principled: the rule now has an exception list that will grow. I rank P1 > P2 > nothing.

###### Rejected: do nothing / stdlib only

Bit-casting cannot be written in safe Blink. A stdlib version needs `@ffi`/`@trusted` for a pure operation, which misstates its trust level. It must be a built-in.

###### Follow-up (separate ticket)

`Bytes` has no `u64`/`f64` read/write, and `U64 → Int` is `TryFrom`, so writing a negative Float's bits into `Bytes` needs a detour today. That is a composition gap; file it, but keep it out of this decision.

##### DevOps

**DevOps/Tooling seat: Phase A proposal**

###### Proposal T1 (main): built-in bits methods, no hex text form

Add five built-in methods. They need no import, the same as `ieee_eq`:

| Method | Signature |
|---|---|
| `Float.to_bits` | `fn(self) -> U64` |
| `Float.from_bits` | `fn(bits: U64) -> Float` (static) |
| `Float.is_sign_negative` | `fn(self) -> Bool` |
| `F32.to_bits` | `fn(self) -> U32` |
| `F32.from_bits` | `fn(bits: U32) -> F32` (static) |

```blink
fn main() {
    let z = -0.0
    io.println(z.display())                      // 0.0
    io.println(z.is_sign_negative().display())   // true
    io.println(z.to_bits().display())            // 9223372036854775808
    let back = Float.from_bits(z.to_bits())
    assert(back.is_sign_negative())
    assert(back.to_bits() == z.to_bits())        // bit-exact round trip
    let q = Float.from_bits(0x7FF8000000000001)  // NaN with payload 1
    assert(q.to_bits() == 0x7FF8000000000001)    // payload kept
}
```

**Why built-in rather than `std.float`.** The spec's sign-of-zero test must be replaced in the same change (float-ieee-eq, five seats). If that replacement needs `import std.float`, then the core-type example in §3 needs an import line, and a user who copies it without the import gets "no method `is_sign_negative` on Float". I want completion on `x.` to list `to_bits` and `is_sign_negative` beside `ieee_eq` in every file. `is_nan` sits behind an import today, and that is a wart; it should not spread. (Moving `is_nan` is a separate ticket.)

**Why `from_bits` returns `Float`, not `Option`.** Every 64-bit pattern is a valid binary64 value. Hover shows `fn(bits: U64) -> Float`, and that tells the user it cannot fail. This differs from `Enum.from_int`, where some inputs have no variant. The difference is real, so the two signatures should differ.

**NaN payloads: no canonicalization.** `to_bits` returns the stored bits and `from_bits` stores the given bits. If either one quieted or canonicalized a NaN, the "bit-exact path" would be bit-exact only some of the time. Users would then file bugs we cannot fix without a spec change. The spec should say plainly that arithmetic may change a NaN payload, but these two methods must not.

**Why I reject the hex float text form for now.**
- It is a second text form of `Float`. It needs a grammar, a decision on `parse_float` input (a separate ticket), and almost certainly a lexer literal (`0x1.8p3`), which `blink fmt`, the highlighter and the LSP tokenizer must all learn.
- Only C, Java and Python's `float.hex()` users can read it. The people in the Systems dissent (numpy, Postgres) read the sign through binary formats or `copysign`, not through hex text.
- `U64` text from `to_bits()` is already outside the Float Text Form rule ("a form that is not decimal text"). It needs no carve-out.

Defer hex text to a ticket that has a real user.

###### Diagnostics this must ship with

I judge the feature by these. Each one goes in the same change.

1. **A bitwise operator on Float** (`x & 0x8000000000000000`). The current error gets a help line: `help: use x.to_bits() to work on the bit pattern of a Float`.
2. **Comparing with a `-0.0` literal** (`x == -0.0`, `x != -0.0`, `x.ieee_eq(-0.0)`). This is a new warning. The comparison is true for `0.0` as well, so the user almost certainly meant a sign test. Message: `this comparison is true for 0.0 and -0.0`, with `help: use x.is_sign_negative() to test the sign`. A literal `-0.0` operand is a purely syntactic check, so it gives no false positives on computed values. This is the trap that sent the Systems dissent here. A spec that makes `==` blind to the sign must also warn when code looks like it relies on the sign.
3. **`.to_bits()` on Int or on a sized integer.** This reports the missing method and gives no suggestion. Do not suggest a cast: there is none.
4. **`blink explain`** for the warning in item 2 shows the three tools side by side: `==` (total order), `ieee_eq` (IEEE), and `to_bits`/`is_sign_negative` (bit identity).

###### Spec text (proposed)

In *Float Total Ordering*, replace "To test the sign of zero, use `1.0 / x < 0.0`." and the matching assert with:

> To test the sign of any `Float`, including a zero or a NaN, use `x.is_sign_negative()`. It returns the sign bit. To read or write the bit pattern, use `x.to_bits() -> U64` and `Float.from_bits(bits: U64) -> Float`. These are built-in methods. `Float.from_bits(x.to_bits())` has the same bits as `x` for every `x`, NaN payloads included: neither method changes a NaN payload. Arithmetic may change a NaN payload. `x.to_bits() == y.to_bits()` is the only test that tells every pair of distinct `Float` values apart.

```blink
assert((-0.0).is_sign_negative())
assert(!(0.0).is_sign_negative())
```

In *Float Text Form*, after the Laws, replace the closing sign-of-zero sentence with:

> The text does not show the sign of zero or the bits of a NaN. For a bit-exact form, write `x.to_bits()`. A `U64` is not decimal text of a `Float`, so *One form everywhere* does not bind it.

In the F32 paragraph, add:

> `F32` has `to_bits(self) -> U32` and `F32.from_bits(bits: U32) -> F32`, with the same rules for sign and payload.

###### Cross-language note

- Rust: `f64::to_bits`/`from_bits`/`is_sign_negative`, with the same names and the same no-canonicalize rule. Rust has a long issue history about payload guarantees, so stating ours in the spec settles it up front.
- Go: `math.Float64bits` and `math.Signbit`, which are free functions; our methods-only rule rules those out.
- Java keeps both `doubleToLongBits` (canonicalizes) and `doubleToRawLongBits` (raw). Having two forms is the confusion I want to avoid. Ship one form, the raw one.

###### Tradeoffs

- Five built-in method names are more compiler surface than a library module. The gain is that the methods are always visible to completion and that §3 examples need no import.
- No hex text means people read bits as a decimal `U64` (`9223372036854775808`), which is hard for a human to read. The fix for that is a general integer hex formatter (`U64` to hex text), which would help every bitmask user, not only Float users. I would file that as its own ticket and keep this one small.
- The `-0.0` literal warning adds one more warning code. I accept that cost: it catches a bug class that the decided `==` semantics make silent.

###### Follow-up tickets (not in this decision)

- A hex formatter for integers.
- `Bytes.write_f64_le/be` and `read_f64_le/be`, for wire formats that move bits without text.
- Moving `is_nan` to a built-in, for consistency with `is_sign_negative`.

##### AI/ML

###### AI/ML seat: Phase A proposal

###### Proposal 1 (my pick): `to_bits` / `from_bits` / `is_sign_negative` as built-in methods. No hex float text.

```blink
fn main() {
    let z = -0.0
    io.println(z.display())                 // 0.0
    io.println(z.to_bits().display())       // 9223372036854775808
    assert(z.is_sign_negative())
    assert(!(0.0).is_sign_negative())

    let b: U64 = 9221120237041090561        // a NaN with payload 1
    let n = Float.from_bits(b)
    assert(n.to_bits() == b)                // payload kept

    let f: F32 = F32.from_bits(2147483648)  // -0.0 as binary32
    assert(f.to_bits() == 2147483648)
}

fn json_num_signed_zero(x: Float) -> Str {
    if x == 0.0 && x.is_sign_negative() { "-0.0" } else { x.display() }
}
```

**Surface (four methods, two per float type):**

- `Float.to_bits(self) -> U64` and `Float.from_bits(bits: U64) -> Float`
- `F32.to_bits(self) -> U32` and `F32.from_bits(bits: U32) -> F32`
- `Float.is_sign_negative(self) -> Bool` and `F32.is_sign_negative(self) -> Bool`

They are compiler built-ins with no import, the same as `ieee_eq`.

**Why this shape (learnability and generation):**

1. **Names a model already knows.** `to_bits`, `from_bits` and `is_sign_negative` are Rust's exact `f64`/`f32` names, and Rust is the main training source for "get the bits of a float". A model will write these names before it has read the spec. Each new name we make up (`bits()`, `bit_pattern()`, `raw()`) is a guess the model can get wrong.
2. **No import step.** `is_nan` needs `import std.float`, and a missing import is a common LLM compile error. The sign-of-zero test sits in core spec text and must compile with no import, as `1.0 / x < 0.0` does today. These methods describe how a value is stored, as `ieee_eq` does, so they go with `ieee_eq`, not in `std.float`.
3. **F32 has the same names.** Models expect matching names across widths. If `F32` had none, people would write `Float.from(f).to_bits()`, which gives the binary64 bits, which is wrong and still compiles.
4. **`is_sign_negative` costs fewer tokens and fewer choices.** Without it, the sign test is `x.to_bits() >> 63 == 1`. That expression needs a `U32` shift amount and the integer operator-group rules (§2.19), which is two places to go wrong. `1.0 / x < 0.0` is a trick: a model cannot infer it from intent, and readers do not see it as a sign test. One named call removes both problems.

**I reject hex float text (`0x1.8p+1`) for now.** Outside C, C++ and Java, the training data has little of it. It adds a second text form, so every Float-to-text call gets a new choice ("display or hex?"). It also needs a parse grammar, and that ticket is out of scope here. Any program that needs exact text can write `to_bits().display()`: decimal `U64` text round-trips through integer parse. If users ask for hex later, add a general integer radix formatter (for example `U64.to_hex()`), which serves every integer, not only floats. That is a separate friction ticket.

**Debugging note.** `U64` is not a `Template` hole type (E0534), so `sql"... {x.to_bits()}"` fails at typecheck. The current help line (`Int.try_from(big)?`) fails for any bits with the top bit set, which includes every negative Float. The E0534 help for `U64` should add a second repair, `Bytes`, and that needs a writer for `U64`. I raise this so the moderator can open a follow-up ticket. It does not block this one.

**Cross-language.** Rust: `f64::to_bits`, `from_bits`, `is_sign_negative`, all the same. Go: `math.Float64bits`, `Float64frombits`, `Signbit`. Python: `struct.pack(">d", x)`, `math.copysign(1, x) < 0`. Java: `Double.doubleToRawLongBits`. JS: none (`Object.is(x, -0)`). Every language with a bits path uses a 64-bit unsigned integer, and none of them uses text.

**Proposed spec sentences (§3, Float Total Ordering):**

> `x.to_bits()` returns the IEEE 754 binary64 bit pattern of `x` as a `U64`. `Float.from_bits(b)` returns the `Float` whose bit pattern is `b`. For every `U64` value `b`, `Float.from_bits(b).to_bits() == b`, NaN payloads and the signaling bit included. `F32.to_bits()` and `F32.from_bits(b)` do the same with binary32 and `U32`. When arithmetic gives a NaN, the spec does not fix which NaN bit pattern it has.
>
> `x.is_sign_negative()` returns the sign bit of `x`. It is `true` for `-0.0`, for every `x < 0.0`, and for a NaN whose sign bit is set. To test the sign of zero, use `x.is_sign_negative()`.

In the same change, replace the two `1.0 / x < 0.0` lines (~3505 and ~4514) with `x.is_sign_negative()`, and replace the example line `assert(1.0 / -0.0 < 0.0)` with `assert((-0.0).is_sign_negative())`. This meets the float-ieee-eq condition.

**Tradeoff to state openly.** `is_sign_negative` returns `true` for a NaN with its sign bit set. `1.0 / x < 0.0` returns `false` for every NaN. These match Rust and IEEE `signbit`, and so they match what models expect. The spec must say this in one sentence, as above, or tests written from the old line will disagree.

**Spec choices in this proposal.** There is no Float hex text, so the Float Text Form stays the one float text form. `from_bits` keeps payloads exactly, with no canonicalization: canonicalization would break the round-trip law and surprise anyone who reads numpy or Postgres binary data. `from_bits` cannot fail, so it returns `Float`, not `Option`. This differs from `Enum.from_int`, and the spec should keep it that way: every `U64` value is a valid bit pattern.

###### Proposal 2 (fallback if the panel wants a smaller change): only `to_bits` and `from_bits`

Drop `is_sign_negative`. The sign test becomes `x.to_bits() >> 63 == 1`. I oppose this. It saves one method, but it puts a bit trick into the spec's own example where `1.0 / x` sits today, and those examples are what models copy. It still beats doing nothing.

###### Proposal 3: do nothing. Rejected.

Blink would stay the only language in this survey with sized integers and no float bits path. A model asked to "write -0.0 for Python" would write `to_bits` anyway (Rust prior), get a compile error, and have no fix to reach.

##### Minimalism

###### Minimalism seat: Phase A proposal

###### Position

Add one thing: a bit-cast pair. Reject hex float text, `is_sign_negative`, `copysign` and new Bytes methods for this ticket.

The test I apply: what can a Blink program not express today? It cannot reach the bits of a Float. That is a real gap, because no mix of existing operations can recover a NaN payload. The sign of zero is reachable now, but only through the `1.0 / x` trick, and that trick gives the wrong answer for a negative NaN. Text forms, sign predicates and copysign are all things you build once you have the bits. Bits are the primitive. Add that and nothing more.

###### Proposal M1 (recommended): `to_bits` / `from_bits`, built in, no import

```blink
fn main() {
    let z = -0.0
    io.println(z.display())                      // 0.0  (unchanged, §3.6)
    io.println("{z.to_bits()}")                  // 9223372036854775808
    assert((z.to_bits() >> 63) == 1)             // the sign of zero
    let back = Float.from_bits(z.to_bits())
    assert(back.to_bits() == z.to_bits())        // bit-exact round trip

    let w: F32 = F32.from(-0.0)
    assert((w.to_bits() >> 31) == 1)             // F32 uses U32
}
```

Surface:

| Method | Signature |
|---|---|
| `Float.to_bits` | `fn(self) -> U64` |
| `Float.from_bits` | `fn(bits: U64) -> Float` (static) |
| `F32.to_bits` | `fn(self) -> U32` |
| `F32.from_bits` | `fn(bits: U32) -> F32` (static) |

Placement: built-in methods, like `ieee_eq`, with no `import std.float`. A bit cast is a property of the type, not a numeric utility. Requiring an import for the one operation the spec now points users to for the sign of zero adds friction and buys nothing. The static constructor matches `Bytes.new()` and the "methods only" rule in §3.2.

Why F32 too: this is one rule ("each IEEE float type has a bit cast to the unsigned integer of the same width"), not a second feature. Leaving it out would mean F32 is the one float type with no bit path. F32 also exists for GPU and ML weights, where people inspect bit patterns most. The extra cost is two lines in a table.

**Proposed spec text (§3, after *Float Total Ordering*):**

> **Float bits.** `x.to_bits()` returns the IEEE 754 binary64 bit pattern of `x` as a `U64`. `Float.from_bits(b)` returns the `Float` with bit pattern `b`. For every `U64` `b`, `Float.from_bits(b).to_bits() == b`. This includes every NaN payload and both zeros. `F32` has the same pair over `U32` and binary32. These methods do not change `Float` equality or ordering: `-0.0 == 0.0` stays `true`, though their bits differ. Arithmetic does not promise which NaN payload it produces; only `from_bits` and `to_bits` keep a payload unchanged.

**Replace both `1.0 / x < 0.0` sentences (~3505 and ~4514), in the same change, as five seats required in float-ieee-eq:**

> To test the sign of a `Float`, including zero and NaN, use `(x.to_bits() >> 63) == 1`.

Update the example at ~3513 the same way. The new test is also more correct, because it gives the right answer for a NaN with the sign bit set.

**Float Text Form:** no change. Its own text already says a bit pattern is outside the rule. That was the point of that clause.

Cross-language: Rust `f64::to_bits`/`from_bits`, Java `Double.doubleToRawLongBits`/`longBitsToDouble`, Go `math.Float64bits`/`Float64frombits`, Zig `@bitCast`. Every one of these languages ships the bit cast as the base. The rest is optional and arrives later, or never.

###### What I reject, and why

**Hex float text (`0x1.8p+1`).** This adds a second text grammar and a second parser path. It interacts with the `parse_float` input-grammar ticket and with the exponent-literal ticket, which are both out of scope here. Hex float also still cannot show a NaN payload unless we invent a non-standard NaN syntax. That makes it a worse bit path than `to_bits` and a costly text path. A program that wants text can write `"{x.to_bits()}"`, or produce hex from the U64. If hex integer formatting is missing, that gap belongs to the integer types, not to Float.

**`is_sign_negative` / `copysign` / `signum`.** `(x.to_bits() >> 63) == 1` already expresses them. Each one adds a name, a doc entry and an edge-case rule for NaN. If use shows real demand, `std.float` can add them as plain Blink code over `to_bits`, with no compiler work. They are not foundational.

**`Bytes.write_f64_le` and similar.** These are serialization, not a bit path. `Bytes` has no `u64` read or write today. Fix that in the Bytes integer family if needed, then floats come for free through `to_bits`. A separate ticket can track it.

**NaN canonicalization in `to_bits`.** Do not canonicalize. The whole reason for this ticket is to make the payload visible. Canonical NaN is already what `display()` gives.

###### Interaction cost

- **Hash (E1400):** none. A user who wants a bitwise float key can write `Map[U64, V]` keyed by `to_bits()`. They have to choose that on purpose, and the hash then follows bits, not `Eq`. That is honest, and it needs no new rule.
- **Eq laws:** none. `to_bits` makes no claim about `==`.
- **Codegen:** a `memcpy` or union cast in C. No runtime, no import, no new types.
- **Total new surface:** four methods, one spec paragraph, two sentence replacements.

###### Alternatives on the ballot

- **M1 (my vote):** the bit-cast pair as above, for Float and F32. Hex text rejected. Sign helpers deferred to `std.float` on demand.
- **M2 (fallback):** M1 for `Float` only, with F32 deferred to its own ticket. I accept this, but it is a false saving.
- **Do nothing:** rejected. The gap is real, the cost is four methods, and the spec has already promised a bit path in two votes.

#### Phase B — Debate (one round; all six signalled stable)

The moderator's dedupe and the variation list V1–V7 went to all six seats. Each reply follows.

##### Systems

###### Systems seat, Phase B round 1

###### Positions

**V1: name.** `to_bits`, with PLT's P2 amendment to §3c.3. My second choice is `bits()`, and I will accept it. The name does not change codegen. PLT's point about the law (F1) is correct, and I do not want an exception that nobody wrote down. But Rust, the source that every reader and every model copies, uses `to_bits`. I would write the amendment as a rule for a class of methods, not as a list of names: "`to_bits` reads the stored bit pattern. It is not a conversion and has no `From` impl." If a later type gets a bits method, it uses the same name under the same rule, so the list does not grow.

**V2: `is_sign_negative`.** I change my vote to "ship now", for both `Float` and `F32`. AI/ML's argument moved me: the spec line is the one text that users and models copy, and `x.to_bits() >> 63 == 1` puts a U32 shift amount (F3) and the operator-group rules in that line. The method costs nothing at run time: it compiles to a sign-bit test (`movmskpd`, or `test` on the high bit). The spec must define it as exactly the sign bit, so that it is never read as `x < 0.0`.

**V3: replacement text.** `x.is_sign_negative()`, at both places and in the example assert.

**V4: diagnostics.**
- (a) Yes. It is a help line on an error that exists already.
- (c) Yes.
- (b) Not in this decision. A new warning code needs its own scope. Does it cover `x < -0.0`? A `match` arm on `-0.0`? A `-0.0` const? I support filing it as a follow-up ticket. It must not hold up this one.
- (d) Follows (b).

**V5: const.** I withdraw it. F2 shows that method calls are not const expressions under §2.21, and this ticket should not change §2.21. `Float.from_bits` is total and has no effects, so it would be a good first entry in the const operation set. That belongs in a follow-up ticket. F4 is also a real gap: until the spec says whether a `U64` literal above `Int` max is valid, spec examples must use only bit patterns below `0x7FFFFFFFFFFFFFFF`. Every quiet-NaN example the seats wrote is below that limit, but a `-0.0` literal pattern (`0x8000000000000000`) is not.

**V6: laws.** State all of these:
1. `Float.from_bits(b).to_bits() == b` for every `U64` `b`. Name signaling NaNs in the sentence. That is the sentence that stops an x87-style load or an optimizer from quieting the bits.
2. Copy, move, storage, and passing to or from `@ffi` keep every bit (PLT law 4). Arithmetic does not promise a NaN payload.
3. `x.to_bits() == y.to_bits()` implies `x == y`. The converse fails for the two zeros and for NaN patterns (PLT laws 2 and 3, Web's "not equality" sentence).
4. `x.is_sign_negative()` is `(x.to_bits() >> 63) == 1`, for NaN too. For `F32` it is bit 31.

**V7: placement.** A **Float bits** paragraph right after *Float Total Ordering*, because the sign-test line is there. A one-line pointer from *Float Text Form*. I have no strong view on the heading number.

###### Responses

To Minimalism: "`std.float` can add them as plain Blink code over `to_bits`." That puts an import in front of the one method that the core §3 text tells users to call. The compiler cost is a one-line lowering. I still hold the same line as you on `copysign` and `signum`: keep them out.

To PLT: "one exception means a reader can no longer reason from `to_X` to `From`." That is true for an exception nobody wrote down. A rule written into §3c.3 that names a class keeps the reasoning sound. If the panel does not accept that, I vote `bits()` over a silent exception.

To DevOps (b): I agree that the trap is real. My objection is only to scope.

To AI/ML on E0534: I agree. `U64` bits with the top bit set cannot go through `Int.try_from`, so the `Bytes` u64 pair and that help text go to the same follow-up.

###### Status

Stable, ready to vote.

##### Web/Scripting

###### Web/Scripting seat: Phase B round 1

###### 1. Positions on V1–V7

**V1 (name): `to_bits()`.** PLT's point is fair. The cure is to make the §3c.3 rule say what it means, not to rename the method. I propose this amendment:

> `.to_X()`, where `X` names a type, stands for `From`.

`bits` is not a type name, so `to_bits` claims no `From` impl. The rule then needs no exception list, because the rule never bound `to_bits` in the first place. Under this reading, `to_str`/`to_hex`-style methods on other types are consistent too. If the panel does not want to touch §3c.3, I still pick `to_bits` (PLT's P2) over `bits()`.

**V2 (`is_sign_negative`): ship now**, on `Float` and `F32`.

**V3 (replacement text): `x.is_sign_negative()`.** This follows from V2.

**V4 (diagnostics):**
- (a) Yes. It is a help line on an error that exists already, so it costs very little.
- (b) Yes. `x == -0.0` is the exact code a JS or Python developer writes when they think they are testing the sign. Today it passes in silence for `0.0`, so a warning fits this case. The check is on the literal only, so false positives stay low.
- (c) Yes.
- (d) Yes.

These are tooling work, not spec text. If they slow the spec change down, they can ship in the same release as a chore.

**V5 (const-evaluable): no, not in this ticket.** F2 says method calls are not const expressions. Making `from_bits` the first exception is a rule change that belongs to the `const fn` work. Users can write `let NEG_ZERO = -0.0` today, so this covers the common case.

**V6 (laws):** state all of these:
1. The round trip `Float.from_bits(b).to_bits() == b` for every `b`, with NaN payloads and signaling NaNs named.
2. `x.to_bits() == y.to_bits()` implies `x == y`, but the converse fails (PLT's law 2). This replaces my looser "not equality" sentence.
3. The NaN payload of an arithmetic result is unspecified.
4. `is_sign_negative` is `true` for a NaN whose sign bit is set (AI/ML's sentence). Tests written from the old `1.0 / x` line will disagree with this, so the spec must say it.

**V7 (placement): no strong view.** A paragraph near *Float Total Ordering* is where a reader of the `==` rules looks next, so I lean that way.

###### 2. Responses

To Minimalism: "`(x.to_bits() >> 63) == 1` already expresses them … `std.float` can add them."
- Putting it in `std.float` puts it behind an import. The spec line that replaces `1.0 / x` sits in core §3 text, so the example would then need an import line. DevOps and AI/ML make the same point.
- The bit-shift form asks a JS or Python developer three things they do not know: the `U32` shift amount, whether `>>` on `U64` is a logical shift, and the operator-group rules. Python users write `math.copysign(1, x) < 0`, and JS users write `Object.is(x, -0)`. Neither group writes `>> 63`.
- The cost of the extra method is one table row. The cost of leaving it out is one Stack Overflow question per new user.

To Systems: "would accept it". Then I ask Systems to vote for it. The codegen is one bit test, so it has no run-time cost to argue about.

To PLT on the AI/ML trade: "An E-code help line that suggests `bits()` on a `to_bits()` call covers that cost." That help line fires on every first try from Rust-trained users and models, which means we build a diagnostic to correct a name we chose. The §3c.3 amendment above removes the need for it.

On F4, a note for the person who writes the examples: Systems, DevOps and I all used a hex literal above `Int` max (`0x7ff8000000000001` fits; `0x8000000000000000` does not). Until the literal rule is settled, spec examples should build such values with `to_bits()` or with a decimal value that fits. The moderator should file the literal question as friction.

###### 3. Status

Stable, ready to vote.

##### PLT

###### PLT seat — Phase B round 1

###### Positions

**V1 (name): I move to `to_bits`, on one condition: §3c.3 must be scoped, not given an exception.**
Five seats chose `to_bits`, and no seat answered the §3c.3 point (F1: "A scalar has no `to_` method without such an impl"). As written, `to_bits` breaks that sentence. The fix must not be an exception list ("except `to_bits`"), because a list grows. The fix is to state what the rule covers. The rule is about `to_X` where `X` names a type, and `bits` names no type. Proposed amendment to §3c.3:

> The `to_` rule covers a method `to_X` or `to_X_checked` where `X` names a scalar type (`to_int`, `to_u64`). A `to_` method whose suffix names no type, such as `Float.to_bits`, is not a conversion and has no `From` impl behind it.

With that sentence, a reader can still reason from `to_u64()` to `From`, and `to_bits` matches the Rust name, which aiml weighs heavily. Without the sentence, I vote `bits()`.

**V2 (`is_sign_negative`): ship now.** This answers min: "`(x.to_bits() >> 63) == 1` already expresses them … `std.float` can add them as plain Blink code." Two points against that:
1. IEEE 754-2008 §5.7.2 lists `isSignMinus` as a required operation. Blink claims IEEE 754 binary64. A required operation of the standard is a primitive of the type, not a utility.
2. The spec's own sign test sits in core §3 text. If it needs `import std.float`, the core example will not compile as written, the same issue devops raised. The bit-shift form is correct, but it puts operator-group rules and a `U32` shift amount (F3) into the one line users copy.
I accept sys's "would accept it".

**V3: `x.is_sign_negative()`.** To test for negative zero specifically, show `x == 0.0 && x.is_sign_negative()`, as aiml's example does. `is_sign_negative` alone is also true for `-1.0`.

**V4 (diagnostics):** (a) yes. (b) yes. The check is purely syntactic and sound: `x == -0.0` and `x == 0.0` denote the same predicate under the decided `==`, so the warning never lies. (c) yes. (d) yes. None of these change the type system, so I defer to devops on wording.

**V5 (const-evaluable): no, not in this ticket.** F2 says method calls are not const expressions, and the const set is "a fixed set of total operations". Adding `from_bits` to it changes §2.21, which is a separate rule with its own ticket. The motivating constant needs no `from_bits`: `let NEG_ZERO = -0.0` already has the right bits. File it as a follow-up.

**V6 (laws): state four.**
1. Round trip at the bit level: `Float.from_bits(b).to_bits() == b` for every `b: U64`, signaling NaNs included (sys, aiml are right to name them).
2. `x.to_bits() == y.to_bits()` implies `x == y`; the converse is false for the two zeros and for NaNs with different sign or payload.
3. Arithmetic does not fix the NaN payload of its result.
4. `is_sign_negative` returns the sign bit, NaN included, and so differs from the old `1.0 / x` test on a negative NaN (aiml's tradeoff sentence).
Two repairs to drafts. Sys's "`Float.from_bits(x.to_bits()) == x` for every `x`" holds only under Blink `==`, which merges NaNs, so it is strictly weaker than law 1. Drop it. Devops's "`x.to_bits() == y.to_bits()` is the only test that tells every pair of distinct `Float` values apart" claims too much ("only"). Write it as law 2.

**V7 (place): no view.** A paragraph beside *Float Total Ordering* is fine.

###### Precondition the moderator should record (F4)

Several examples use `0x7FF8000000000001` or `0x8000000000000000` as a `U64`. The spec does not say whether an integer literal above `Int` max is valid where `U64` is expected. Either the spec states that rule, or the examples in this change must avoid such literals. A spec example that the compiler rejects is a defect. That is a friction ticket, and it must not block this decision.

###### Status

Stable. Ready to vote.

##### DevOps

###### DevOps/Tooling seat, Phase B round 1

###### Positions

**V1 (name): I change my vote to `bits()`, with `to_bits` as my fallback.** PLT is right about F1. The `to_` rule is mechanical today: a reader, the LSP and a stdlib lint can all map `.to_X()` to `From`, and `.to_X_checked()` to `TryFrom`, with no exception list. If `to_bits` ships, it is the first exception, and the first one makes the rule something you have to look up. The cost of `bits()` is that Rust users and LLMs will type `to_bits()`. A diagnostic fixes that cheaply, so I make it part of the feature:
`error: no method 'to_bits' on Float` / `help: use x.bits() to read the bit pattern`.
I also accept P2 (`to_bits` plus a written amendment to §3c.3). I reject `to_bits` with no amendment, because then the spec contradicts itself.

**V2 (`is_sign_negative`): ship now, for Float and F32.** Min says the `std.float` module "can add them as plain Blink code over `to_bits`". That puts the spec's own sign test behind an import. That is the `is_nan` wart again: a user copies the §3 line, gets "no method", and has to guess the import. A built-in costs one table row and no runtime.

**V3 (replacement text): `x.is_sign_negative()`.** This is a tooling argument, not taste. My warning (V4b) needs a fix to name in its `help:` line, and quick-fix text in the LSP. A method call is one token to insert. `(x.bits() >> 63) == 1` depends on a shift amount typed `U32` (F3) and on parentheses that fmt adds (§2.19), and it reads as noise in a help line. Sys says it "would accept it", so this costs that seat nothing.

**V4 (diagnostics): keep all four.** (b) matters most. The decided `==` makes `x == -0.0` true for `0.0`, and the language gives no other signal of that. A warning on a literal `-0.0` operand is purely syntactic and has no false positives. If the panel thinks (b) is too large for this ticket, I accept filing (b) and (d) as a follow-up ticket that ships before the next release. (a), and the `to_bits` help from V1, stay in this change.

**V5 (const-evaluable): not in this ticket.** F2 says method calls are not const expressions. Making `Float.from_bits` const would be the first method in const evaluation, and that is a language change of its own. `-0.0` and `0.0 / 0.0` already cover the common constants. What I do want: the error for a method call in a top-level `let` names the rule and points to §2.21. File const `from_bits` with the const-fn work.

**V6 (laws): state all of them.**
- The round trip, with signaling NaNs named (Sys, AI/ML).
- "`x.bits() == y.bits()` implies `x == y`, not the converse" (PLT 2).
- The NaN payload of arithmetic is unspecified.

PLT law 3 ("bits() does not respect `==`") is the sentence `blink explain` will quote when a user keys a `Map[U64, V]` by bits and is surprised. Keep it.

**V7 (place): a named heading, *Float Bits*, next to *Float Total Ordering*.** A heading gives `blink llms --topic`, `blink explain` and the help lines a stable anchor to link. Which section number it gets: no view.

###### New point: F4

My Phase A example, Sys's example and every sign-mask example need `0x8000000000000000` as a `U64`. If the compiler rejects that literal because it is above `Int` max, the first thing a user writes with this feature fails, and the error ("integer literal too large") hides the real question. Please file a ticket to settle whether a literal above `Int` max is valid when the expected type is `U64`. This feature does not depend on that ticket, but its examples do. Spec examples should avoid such literals until the ticket is settled.

###### Status

Stable, ready to vote.

##### AI/ML

###### AI/ML seat, Phase B round 1

###### 1. Positions on V1–V7

- **V1 (name): `to_bits()`.** I answer PLT's reason in section 2.
- **V2 (`is_sign_negative`): ship it now, as a built-in, on Float and F32.** Do not add `is_sign_positive`. A model will try it, because Rust has it, so the unknown-method error on Float should carry `help: use !x.is_sign_negative()`. That costs one help line and adds no name.
- **V3: `x.is_sign_negative()`.** This follows from V2.
- **V4 (diagnostics):**
  - (a) Yes.
  - (b) Yes. `x == -0.0` is the sign test a model writes when it has not read the spec, and under the decided `==` it is silently wrong. A warning on a literal operand is cheap and gives no false positives.
  - (c) Yes.
  - (d) Yes.
  - Also: if V1 goes to `bits()`, add the help that PLT names on `to_bits()`.
- **V5 (const): no, not in this ticket.** F2 says method calls are not const expressions. One exception for `from_bits` adds a rule a model cannot predict ("which methods are const?"). The one use case named, `NEG_ZERO`, is the literal `-0.0`. Leave it to the `const fn` work.
- **V6 (laws): state four:**
  1. `Float.from_bits(b).to_bits() == b` for every `b`, signaling NaNs named.
  2. `x.to_bits() == y.to_bits()` implies `x == y`, not the converse (PLT, web). This one sentence stops a model from using `to_bits` as a stand-in for `==`.
  3. Arithmetic does not fix the NaN payload of its result.
  4. A bit pattern is outside *One form everywhere*.

  Also F4: the spec must say that an integer literal above `Int` max is valid when the expected type is `U64`. Without that, a program cannot write `x.to_bits() == 0x8000000000000000`, the most obvious line a model writes after reading this section. Fix it here or file it as a blocker before the examples go in.
- **V7 (where): a named paragraph, "Float bits", right after *Float Total Ordering*.** A named heading gives `blink llms --topic` and readers one place to find it. The heading level is not important to me.

###### 2. Responses

**To PLT:** "`to_bits` either breaks that law or makes the first exception to it."

It would not be the first exception. `Char` is a built-in scalar under §3c.3, and `Char.to_digit(radix) -> Option[Int]` (§3.2.4) has no `From` impl behind it. So one of two things is true: the rule already has an exception, or it reads as "`.to_X()` where `X` names a type", which is what its own text says next ("`.to_X()` ... returns `X`"). `to_digit` and `to_bits` both fall outside that reading, because `digit` and `bits` are not types. So I propose PLT's P2 in a narrow form. Change the rule's wording to "every `to_<Type>` method", with no list of exceptions. This also makes `to_digit` legal on paper.

What `bits()` costs in my domain: Rust is the main prior for this operation, and every model writes `to_bits()` first. A help line fixes that after one failed compile, for each new program, forever. Changing the wording costs one edit, one time.

**To Minimalism:** "`std.float` can add them as plain Blink code over `to_bits`, with no compiler work."

That puts the core spec's own sign test either behind `import std.float` or as `(x.to_bits() >> 63) == 1`. The import is the exact failure DevOps describes: a model copies the example without the import and gets "no method". The shift form makes the reader, and the model, decode a bit trick in the place where spec examples get copied most. And if demand shows up later, a move from `std.float` to a built-in is a migration. One built-in now costs less than that path.

**To Systems:** I accept your logical-shift argument for `U64` in full. That is why the bits type must be `U64` and not `Int`.

###### 3. Status

Stable, ready to vote. I want the F4 literal question answered (spec text or blocker ticket) in the same change.

##### Minimalism

###### Minimalism seat: Phase B round 1

###### Positions

**V1 (name): `bits()`. `to_bits()` is my second choice.** I move to PLT's position. The deciding point is not taste. `to_bits` costs a rule change: §3c.3 says "A scalar has no `to_` method without such an impl", so `to_bits` needs either an exception to that sentence or a `From[Float] for U64` impl that we must not have. `bits()` needs no rule change. The minimal change is the one that leaves existing laws intact. `Ptr.addr()` sets the pattern for an observer that is not a conversion. `from_bits` stays as it is, because no rule binds static constructors. If the panel picks `to_bits`, the §3c.3 amendment must ship in the same change and must be narrow ("reads the bit pattern"), not an open list.

**V2 (`is_sign_negative`): I move to accept it.** I proposed leaving it out. Two arguments change my view:
- AIML: "it puts a bit trick into the spec's own example where `1.0 / x` sits today, and those examples are what models copy." The spec states a sign test twice. That shows a real user need, not a guess about one.
- PLT: "the one observer the spec itself needs." It replaces a trick (`1.0 / x`) that the spec teaches today, so it subtracts as well as adds. That meets my bar.

The limit: one sign method only. No `copysign`, `signum` or `is_sign_positive` in this change. Those stay in `std.float`, to be added on demand.

**V3:** `x.is_sign_negative()`, follows V2. Keep one clause that says it is `true` for a NaN with the sign bit set (AIML's point), because the old `1.0 / x` line gave `false` there.

**V4 (diagnostics):**
- (a) Help line on a bitwise operator applied to a Float: yes. It adds no new code and costs one line on an existing error.
- (b) New warning for comparing with a `-0.0` literal: not in this change. A new warning code is new surface with its own explain text, false-positive questions and `@allow` story. It does not depend on this decision. File it as its own ticket.
- (c) No suggestion on `.to_bits()` on an integer: yes. That is the default behavior, so it needs no work.
- (d) Follows (b): defer.

**V5 (const-evaluable): no.** F2 says method calls are not const expressions. Making two methods const opens the `const fn` question for every other pure built-in method, and that is a separate language feature. A user can keep the integer as the constant and call `from_bits` where they use it.

**V6 (laws): three sentences, no more.**
1. Round trip: `Float.from_bits(b).bits() == b` for every `b`, every NaN included, signaling NaNs too. Naming signaling NaNs costs two words and binds the codegen (sys's x87 point).
2. One sentence covering PLT's laws 2 and 3: "`bits()` tells apart values that `==` treats as equal (the two zeros, and NaNs with a different sign or payload). So `x.bits() == y.bits()` implies `x == y`, but not the converse." This tells readers that the Leibniz law does not hold, and it needs no extra rule text.
3. Arithmetic does not specify the NaN payload of its result.

**V7 (placement):** a bold paragraph right after *Float Total Ordering*, not a "§3.6 Float Bits" heading. §3.6 is about text, and bits are not text. A new numbered heading adds a section to keep in sync for one paragraph.

###### Responses

- To devops's "`x.ieee_eq(-0.0)` ... a new warning": the bug class is real. But "a spec that makes `==` blind to the sign must also warn" argues for a ticket, not for growing this change. Once `is_sign_negative` is in the spec text, the help target exists whenever that ticket lands.
- On F4: devops's and web's examples use `0x7FF8000000000001`, which is above `Int` max, and the spec does not say whether that literal is valid for `U64`. Spec examples for this change must not depend on an open question. Build NaN payload examples from `bits()` and `|` on a small literal, or leave them out. File the literal question separately.
- On F3: with `is_sign_negative` accepted, the `>> 63` form leaves the spec text, so the shift-amount type question does not reach users through this change.

###### Status

Stable, ready to vote. My ballot: `bits()`/`from_bits` plus `is_sign_negative` on Float and F32, all built in. V4 (a) and (c) only. No const evaluation. Three law sentences. Placement after *Float Total Ordering*. If `to_bits` wins V1, I accept it on the condition that the §3c.3 amendment ships in the same change.

#### Phase C — Final vote

Tally: Q1 6-0 A; Q2 6-0 Yes; Q3a 6-0 Yes; Q3b 4-2 Follow-up (DevOps, AI/ML *(dissent)*: In); Q4 6-0 No; Q5 L1–L5 6-0 include, L6 5-1 exclude (AI/ML *(dissent)*: include); Q6 3-3 (P: Sys, PLT, Min; H: Web, DevOps, AI/ML), so Phase D ran; Q7 6-0 S.

##### Ballot

###### Phase C — silent vote

All six seats signalled "stable, ready to vote" after round 1. The round 1 replies are in
B1_<seat>.md in this directory. Read the other five before you vote. Vote alone; do not
message other seats.

###### Final-positions notice: two facts the moderator checked

- F5. `Char.to_digit(self, Int) -> Option[Int]` exists (sections/03_types.md:1427,
  §3.2.4). `Char` is a built-in scalar under the §3c.3 `to_` rule, and no `From` impl
  stands behind `to_digit`. (AI/ML raised this.)
- F6. `0x7FF8000000000001` is below `Int` max (`0x7FFFFFFFFFFFFFFF`), so it is a valid
  `Int` literal. Literals from `0x8000000000000000` up are the ones above `Int` max.
  (This corrects the round 1 Minimalism reply.)

###### Settled by all six in Phase A (not on the ballot)

Built-in bits pair on `Float` (`U64`) and `F32` (`U32`), no import; `from_bits` static
and total; no NaN canonicalization; no hex float text form; Float Text Form, `==`, `Ord`
and E1400 unchanged.

###### Questions

**Q1 — name of the read method.**
- **A** `to_bits()`, with an amendment to §3c.3 that scopes the `to_` rule to `to_X`
  where `X` names a type (no exception list). Wording drafts: Systems (B1_sys V1), Web
  (B1_web V1), PLT (B1_plt V1), AI/ML (B1_aiml section 2). If you vote A, also name the
  draft you prefer.
- **B** `bits()`, §3c.3 unchanged, and a `help:` line on `.to_bits()` naming `bits()`.

**Q2 — `is_sign_negative()`.** Ship `Float.is_sign_negative(self) -> Bool` and
`F32.is_sign_negative(self) -> Bool` as built-ins now; it returns the sign bit (NaN
included). Replace both `1.0 / x < 0.0` lines and the example assert with it. No
`copysign`, `signum` or `is_sign_positive`. **Yes / No.**

**Q3a — diagnostics in this change:** (a) a help line on a bitwise operator applied to a
Float, naming the bits method; (c) no suggestion on the bits method called on an integer.
**Yes / No.**

**Q3b — the `-0.0` literal comparison warning (V4b) and its `blink explain` text (V4d).**
- **In** this change.
- **Follow-up** ticket.

**Q4 — const evaluation of `from_bits`.**
- **No** in this ticket; a follow-up with the `const fn` work.
- **Yes** in this ticket.

**Q5 — laws the spec states.** For each, **include / exclude**:
- L1. `Float.from_bits(b).<read>() == b` for every `U64` `b`, every NaN payload and
  signaling NaNs named; the same for `F32` over `U32`.
- L2. `x.<read>() == y.<read>()` implies `x == y`; the converse is false for the two
  zeros and for NaNs with a different sign or payload.
- L3. Arithmetic does not fix the NaN payload of its result.
- L4. `is_sign_negative` returns the sign bit, so it is `true` for a NaN with the sign
  bit set, unlike the old `1.0 / x` test (only if Q2 passes).
- L5. Copy, move, storage, and passing to or from `@ffi` keep every bit (Systems).
- L6. A bit pattern is outside *One form everywhere* (AI/ML; the Float Text Form text
  already says this).

**Q6 — placement.** Both seats' options sit right after *Float Total Ordering*.
- **P** a bold-run-in paragraph (**Float bits.**), with a one-line pointer from *Float
  Text Form*.
- **H** a named sub-heading *Float Bits*, with the same pointer.

**Q7 — the literal-above-`Int`-max question (F4).**
- **S** a separate ticket; spec examples in this change avoid literals at or above
  `0x8000000000000000`.
- **B** a blocker: the examples in this change wait until that rule is settled.

###### Vote format

For each question: **Vote**, **Reasoning** (2–4 sentences from your seat), **Concern**
(one sentence on what could go wrong with the option most likely to win, from your seat).


##### Systems

###### Systems seat: Phase C ballot

###### Q1: name of the read method
**Vote:** A (`to_bits()` plus the scoped §3c.3 amendment). Preferred draft: PLT (B1_plt V1), but say "names a type" in place of "names a scalar type", as Web's draft does.
**Reasoning:** The name has no effect on codegen. Rust is the source that readers and models copy, so `to_bits` saves one failed compile for each new user. F5 shows that `Char.to_digit` already falls outside the rule as written. A scoped rule fixes both methods with one edit and no exception list. PLT's draft says in plain words that `to_bits` is not a conversion, and that is the sentence I care about.
**Concern:** If the amendment slips out of the change, the spec contradicts itself at §3c.3.

###### Q2: `is_sign_negative()`
**Vote:** Yes.
**Reasoning:** It lowers to a single sign-bit test, so it costs nothing at run time. It fixes the old `1.0 / x` test, which costs a divide, raises the divide-by-zero flag, and is wrong for a NaN with the sign bit set. With the method in the spec line, the shift amount and the operator-group rules stay out of the one line users copy.
**Concern:** A reader takes it to mean `x < 0.0` and does not expect `true` for `-0.0` or for a negative NaN. L4 must say this.

###### Q3a: help line on a bitwise operator on a Float; no suggestion on an integer
**Vote:** Yes.
**Reasoning:** The help line goes on an error that exists already, and the second item is default behavior. Both are cheap and point users to the correct primitive.
**Concern:** None from my seat.

###### Q3b: `-0.0` literal comparison warning and its `blink explain` text
**Vote:** Follow-up.
**Reasoning:** The trap is real, but a new warning code needs its own scope. Does it cover `x < -0.0`, a `match` arm on `-0.0`, or a const that holds `-0.0`? It also needs an `@allow` story. It does not depend on this decision, and `is_sign_negative` gives it a help target whenever it lands.
**Concern:** If no one owns the follow-up ticket, it gets dropped and the silent `x == -0.0` bug stays.

###### Q4: const evaluation of `from_bits`
**Vote:** No.
**Reasoning:** F2 is clear: method calls are not const expressions. I withdrew this in B1. `-0.0` covers the common constant, and the `const fn` work is the right place for it.
**Concern:** None. It is only a delay.

###### Q5: laws
- **L1: include.** It is the sentence that binds codegen: it stops a float load (x87) or an optimizer pass from quieting a signaling NaN. PLT is correct that my `from_bits(x.to_bits()) == x` is weaker than L1. Drop it.
- **L2: include.** It stops `to_bits` from being used as a stand-in for `==`, and it records that the Leibniz law fails.
- **L3: include.** x86 and ARM in default-NaN mode differ on payload propagation, so a promise here would not be portable.
- **L4: include.** Tests written from the old line will give a different answer, so the spec must say so.
- **L5: include.** L1 binds only the two methods. Without L5, an implementation may pass a Float through a path that quiets the bits between `from_bits` and `to_bits`, such as an x87 return register, a spill or an `@ffi` call, and the bits path breaks in silence.
- **L6: exclude as a new law.** The Float Text Form text already says it. The one-line pointer from Q6 is enough, and a second copy of the rule is a second place to keep in sync.

**Concern:** L5 written too loosely, so that it reads as a promise about arithmetic. It must name only copy, move, storage and `@ffi` passing.

###### Q6: placement
**Vote:** P.
**Reasoning:** The text is one paragraph, and it sits where the sign-test line sits today. A bold run-in name still gives tools a phrase to search for.
**Concern:** `blink llms --topic` has a weaker anchor than a heading would give it.

###### Q7: literal above `Int` max
**Vote:** S.
**Reasoning:** The feature works without the literal rule, because `to_bits()`, `|` and literals below `0x8000000000000000` build every example. A blocker would hold up a zero-cost primitive for a question about integer literals.
**Concern:** The first sign-mask line a user writes (`bits & 0x8000000000000000`) may fail with an unclear error until the separate ticket lands.

##### Web/Scripting

###### Web/Scripting seat: Phase C ballot

###### Q1: name of the read method
**Vote:** A (`to_bits()` plus the §3c.3 scope amendment). Preferred draft: PLT's (B1_plt V1).
**Reasoning:** Every Rust user, Kotlin user (`toRawBits`) and model types `to_bits()` first. A name that fails on the first try, with a help line as the fix, is a cost we would choose to pay forever. F5 shows that §3c.3 already reads as "`to_<Type>`", because `Char.to_digit` has no `From` impl. So the amendment writes down what the rule already means, and adds no exception. I prefer PLT's draft because it gives one positive example (`to_int`, `to_u64`) and one negative example (`Float.to_bits`), and readers learn rules from examples.
**Concern:** If the amendment text is vague, a later author may treat it as a loophole for `to_` methods that are conversions in disguise.

###### Q2: `is_sign_negative()`
**Vote:** Yes.
**Reasoning:** This is the 90% case of the ticket: "is this negative zero?" JS has `Object.is`, Python has `copysign`, and neither group would write `>> 63`. The method replaces a documented trick with a name that says what it does. It costs one table row per type.
**Concern:** Users may read it as `x < 0.0`. The examples must show that it is also `true` for `-0.0` and for a NaN with the sign bit set.

###### Q3a: help on a bitwise operator applied to a Float; no suggestion on an integer
**Vote:** Yes.
**Reasoning:** The error exists already, and a help line that names `to_bits()` turns a dead end into one step. A JS developer who tries `x & mask` on a number learns the right tool from the compiler, not from a search engine.
**Concern:** The help text must name the exact method spelling the panel picks in Q1, or it will teach the wrong name.

###### Q3b: `-0.0` literal warning and its explain text
**Vote:** Follow-up.
**Reasoning:** I want this warning: `x == -0.0` is the exact line a scripting developer writes. But Systems asks real scope questions (`x < -0.0`, match arms on `-0.0`, consts), and a new warning code deserves its own ticket and its own answers. The ticket should land before the next release, and its help line can point at `is_sign_negative()` once that exists.
**Concern:** A follow-up can sit in the backlog for a long time while users ship the silent bug.

###### Q4: const evaluation of `from_bits`
**Vote:** No (follow-up with the `const fn` work).
**Reasoning:** One magic const method creates a rule nobody can guess: "which methods work in a const?" `let NEG_ZERO = -0.0` already covers the common case.
**Concern:** Someone who needs a NaN-payload constant must compute it at run time until `const fn` lands. That is a small cost.

###### Q5: laws
- **L1:** include. This is the whole promise of the ticket.
- **L2:** include. It stops people from using bits as an equality test by accident.
- **L3:** include. It keeps users from depending on NaN payloads that differ across platforms.
- **L4:** include. Tests written from the old `1.0 / x` line will disagree otherwise.
- **L5:** include. It is short, and an `@ffi` user will ask exactly this question.
- **L6:** exclude. The Float Text Form already says it in one sentence. Saying it twice gives two texts to keep in sync.
**Reasoning:** Each law I include answers a question a user will ask in their first week. L6 answers nothing new.
**Concern:** Five laws in one paragraph can read as dense. Use a short list, not one long paragraph.

###### Q6: placement
**Vote:** H (a named sub-heading *Float Bits*).
**Reasoning:** People search for "float bits", and so do `blink llms --topic` and `blink explain`. A named heading gives them one stable place to land. A bold run-in paragraph inside *Float Total Ordering* is harder to find and harder to link to.
**Concern:** The heading may grow into a dumping ground for unrelated Float helpers later.

###### Q7: the literal-above-`Int`-max question
**Vote:** S (separate ticket; examples avoid such literals).
**Reasoning:** The feature does not depend on the literal rule, and its examples can build values with `to_bits()` or with small literals. Blocking this change on another ticket delays the part users need now.
**Concern:** Users will still type `x.to_bits() == 0x8000000000000000` on day one and get a confusing error, so the separate ticket must be high priority.

##### PLT

###### PLT seat — Phase C ballot

###### Q1 — name of the read method
**Vote:** A (`to_bits()` + §3c.3 scoped to `to_X` where `X` names a type). Preferred draft: PLT (B1_plt V1); Web's wording is the same rule and I accept it.
**Reasoning:** F5 settles this for me. `Char.to_digit` already stands outside the rule as written, so the sentence "A scalar has no `to_` method without such an impl" is false today. Scoping the rule to type-named suffixes repairs that existing defect and covers `to_bits` with no exception list. The reasoning "`to_X` with `X` a type implies `From`" stays mechanical. My draft also covers `to_X_checked` and says plainly that a non-type suffix has no `From` behind it.
**Concern:** If the amendment is dropped or worded as "except `to_bits`", the spec states a law with a growing list of holes. The amendment must land in the same change.

###### Q2 — `is_sign_negative()`
**Vote:** Yes.
**Reasoning:** IEEE 754 §5.7.2 requires `isSignMinus`, so it is a primitive of the type. It is the observer the spec's own sign test needs, and it is correct on NaN, where `1.0 / x` is not. One method, no siblings.
**Concern:** Readers may take it as `x < 0.0`; the spec sentence must say "sign bit" and name `-0.0` and negative NaN.

###### Q3a — help on bitwise-on-Float; no suggestion on integer `.to_bits()`
**Vote:** Yes.
**Reasoning:** Both touch only diagnostics text on errors that exist. They add no rule and no surface.
**Concern:** None from my seat.

###### Q3b — `-0.0` literal comparison warning + explain text
**Vote:** Follow-up. (I said "yes" in round 1; I change this.)
**Reasoning:** The check is sound, but its scope is not yet specified: `<` and `<=` against `-0.0`, a `match` arm on `-0.0`, and a named constant bound to `-0.0` each need a ruling. A warning code with unwritten coverage rules is spec text drafted in a hurry. Its help target (`is_sign_negative`) exists once Q2 passes, so nothing blocks the ticket.
**Concern:** The follow-up may drift; it should be filed with the cases above listed.

###### Q4 — const `from_bits`
**Vote:** No.
**Reasoning:** §2.21 has no method calls in const expressions (F2). Adding one method changes that rule and invites "which methods are const?" That belongs with `const fn`. `-0.0` already covers the named use.
**Concern:** None.

###### Q5 — laws
- **L1 include.** The round trip is the defining law; naming signaling NaNs binds codegen against quieting loads.
- **L2 include.** It states in plain words that `to_bits` is finer than `==`, which is the only soundness fact a user must know (the Leibniz law fails for Float).
- **L3 include.** Without it, x86 and ARM default-NaN behavior make programs disagree, and the spec would seem to promise otherwise.
- **L4 include.** Tests written from the old line will disagree on negative NaN; the spec must say so.
- **L5 include.** L1 alone binds only `from_bits`/`to_bits`. L5 binds the paths between them; without it a payload could change on a store and L1 would still hold vacuously at each call.
- **L6 exclude.** *Float Text Form* already says it. Stating it twice makes two texts to keep in sync; the one-line pointer is enough.
**Concern:** L5's `@ffi` clause must not read as a promise about what C code does to the value after the call.

###### Q6 — placement
**Vote:** P (bold run-in paragraph after *Float Total Ordering*, pointer from *Float Text Form*).
**Reasoning:** The laws sit next to the `==` rules they qualify, and that is where a reader of L2 looks. One paragraph does not need a heading. I accept H if the tooling seats need an anchor.
**Concern:** None from my seat.

###### Q7 — literals at or above `0x8000000000000000`
**Vote:** S (separate ticket; examples avoid such literals).
**Reasoning:** The literal typing rule for `U64` is a question about integer literals in general, not about Float. This feature is complete without it. The examples can build the sign-bit pattern from `(-0.0).to_bits()`.
**Concern:** A user's first sign-mask line may hit an unclear "literal too large" error; the ticket should go in the queue soon.

##### DevOps

###### DevOps/Tooling seat: Phase C ballot

###### Q1: name of the read method
**Vote: A** (`to_bits()` plus the scoped §3c.3 amendment). I prefer the **PLT draft** (B1_plt V1).
**Reasoning:** In round 1 I moved to `bits()` because I thought `to_bits` would be the first exception to a mechanical rule. F5 shows the rule already has one, `Char.to_digit`, and nobody wrote it down. A scoped amendment fixes that existing problem and also lets `to_bits` in. A tool can then check the rule with no list: does the suffix name a type? Under B, I would have to build a help line that fires on the first try of every Rust-trained user and model, to correct a name we chose ourselves. PLT's draft names `Float.to_bits` as the example and says "not a conversion and has no `From` impl". That is the text hover and `blink explain` can quote.
**Concern:** The amendment must also cover `to_X_checked`, and it must say which "types" count. If it does not, a later `to_json` or `to_list` on a scalar reopens the same question.

###### Q2: `is_sign_negative()`
**Vote: Yes.**
**Reasoning:** The spec's sign test is the line users copy, so it must compile with no import. A method is also the one-token fix that a help line and an LSP quick fix can insert. Shift-and-compare cannot be inserted that cleanly.
**Concern:** Users will read it as `x < 0.0`. The doc text and hover must say "the sign bit, so it is also true for `-0.0` and for a NaN with the sign bit set."

###### Q3a: help on a bitwise operator applied to a Float, and no suggestion on an integer
**Vote: Yes.**
**Reasoning:** (a) is one help line on an error that already exists, and it points to the exact fix. (c) costs no work, and it stops us from suggesting a cast that does not exist.
**Concern:** The help text must name the final method name from Q1. A wrong name in a help line is worse than no help.

###### Q3b: the `-0.0` literal warning and its explain page
**Vote: In.**
**Reasoning:** The decided `==` makes `x == -0.0` silently true for `0.0`. This change is when users first get a correct tool, so it is also when they most need to hear that the old pattern is wrong. Systems asked what it covers. My answer: `==`, `!=` and `ieee_eq`, where one operand is the literal `-0.0`, or `-0.0` written as a match pattern if Float literal patterns exist. Ordering operators are out, because `x < -0.0` means the same as `x < 0.0` and nobody writes it to test the sign.
**Concern:** If Follow-up wins, the ticket must ship before the next release. A trap with no warning, once it sits in a release, becomes something people rely on and stops being a bug.

###### Q4: const evaluation of `from_bits`
**Vote: No.**
**Reasoning:** F2 says method calls are not const expressions. One const method would make a rule that neither a user nor the LSP can predict. `-0.0` already covers the constant that people want.
**Concern:** Today the error for a method call in a top-level constant may not point to the rule. That message should name §2.21.

###### Q5: laws
- **L1: include.** It is the line that binds codegen and optimizers, and it is what a test suite checks.
- **L2: include.** `blink explain` needs this sentence when a user keys a `Map[U64, V]` by bits and is surprised.
- **L3: include.**
- **L4: include.** Tests written from the old `1.0 / x` line will fail on a negative NaN. The spec must say why.
- **L5: include.** Without it, a user who reads bits across `@ffi` has no guarantee to point to when a bug report comes in.
- **L6: exclude.** The *Float Text Form* text already says this. A second copy can drift from the first. The pointer from *Float Text Form* (Q6) is enough.

**Concern:** If L1 to L5 are written as five separate sentences, the paragraph gets long. Keep each one to one sentence.

###### Q6: placement
**Vote: H** (a named sub-heading, *Float Bits*).
**Reasoning:** A heading gives `blink llms --topic`, `blink explain` and help lines a stable anchor to link. A bold run-in paragraph has no anchor.
**Concern:** If P wins, the help lines and explain pages must link to *Float Total Ordering* and name the paragraph, and that link breaks when the section moves.

###### Q7: the literal-above-`Int`-max question (F4)
**Vote: S.**
**Reasoning:** The feature does not depend on how that question is answered, only the examples do. The examples can avoid such literals.
**Concern:** The first thing a user writes is a sign mask (`0x8000000000000000`). If that literal is rejected with "integer literal too large", the error hides the real question. That ticket needs priority, not a slot at the back of the backlog.

##### AI/ML

###### AI/ML seat, Phase C ballot

###### Q1 — name of the read method
**Vote:** A (`to_bits()` plus the scoped §3c.3 amendment). Preferred draft: PLT's (B1_plt V1), with one change: write "where `X` names a type", not "names a scalar type".
**Reasoning:** Every model and every Rust user writes `to_bits()` first. With `bits()`, each of them hits a help line on the first compile, in every new program. The scoped rule removes the conflict, and it does not add an exception: `Char.to_digit` (F5) already sits outside the rule as written. PLT's draft names `to_bits` as an example, which teaches the boundary. "A type" (not "a scalar type") also covers `Char.to_str`, which goes to `Str`, a type that is not a scalar.
**Concern:** If the amendment text is loose, a later author can read it as permission for any `to_` name. The example in the sentence must stay.

###### Q2 — `is_sign_negative()`
**Vote:** Yes.
**Reasoning:** It gives one named call with no import and no decision points, and it replaces a trick that a model cannot infer from intent. The name matches Rust and IEEE `isSignMinus`, so generation gets it right without the spec.
**Concern:** Models trained on `x < 0.0` habits may use it where they mean "less than zero" and get `true` for a negative NaN. L4 must be in the spec text, next to the method.

###### Q3a — help on a bitwise operator on Float; no suggestion on integers
**Vote:** Yes.
**Reasoning:** `x & 0x8000...` on a Float is a C habit that models carry over. A help line that names the method turns a dead-end error into a fix in one step, at the cost of one line.
**Concern:** None from my seat.

###### Q3b — `-0.0` literal comparison warning and explain text
**Vote:** In.
**Reasoning:** `x == -0.0` is the sign test a model writes before it reads the spec. Under the decided `==`, that code compiles and is silently wrong, which is the worst failure mode for generated code. The check is syntactic and cannot give a wrong warning. Systems' scope questions (`<`, match arms, consts) have short answers: the warning covers `==`, `!=` and `ieee_eq` with a literal operand, and nothing else.
**Concern:** If the scope stays undefined, the work can stall this change. If it does, ship it as a follow-up in the same release rather than hold the spec.

###### Q4 — const evaluation of `from_bits`
**Vote:** No.
**Reasoning:** One const method makes "which methods are const?" a question a model cannot answer from the rule. `-0.0` already covers the named constant.
**Concern:** None.

###### Q5 — laws
- **L1:** include. This is the law that makes the feature trustworthy. Naming signaling NaNs binds codegen.
- **L2:** include. This one sentence stops `to_bits` from being used as a stand-in for `==`.
- **L3:** include. Without it, tests that check NaN payloads after arithmetic pass on one target and fail on another.
- **L4:** include. Tests written from the old line will disagree with the new method on a negative NaN, so the spec must say so.
- **L5:** include. Bits that pass through `@ffi` are the main real use (numpy and Postgres buffers). The law must cover that path.
- **L6:** include, as a one-line pointer to the existing clause, not as a second copy of the rule.

**Reasoning:** Each law answers a question that a model or a test author will otherwise guess.
**Concern:** Six sentences can grow into a long paragraph. Keep each law to one sentence.

###### Q6 — placement
**Vote:** H (sub-heading *Float Bits*).
**Reasoning:** A named heading gives `blink llms --topic`, `blink explain` and help lines one stable anchor. A bold run-in paragraph inside *Float Total Ordering* is hard to retrieve on its own, and retrieval is how models read this spec.
**Concern:** None. P is acceptable.

###### Q7 — literal above `Int` max
**Vote:** S (separate ticket; examples avoid such literals).
**Reasoning:** The feature does not depend on the literal rule. Spec examples can build `-0.0` patterns with `(-0.0).to_bits()`. Blocking would hold a settled feature on an unrelated question.
**Concern:** The first sign-mask code a model writes (`b & 0x8000000000000000`) may fail with an error that names the literal, not the feature. Give that ticket high priority.

##### Minimalism

###### Minimalism seat: Phase C ballot

**Q1: A (`to_bits()` with the scoped §3c.3 amendment). Preferred draft: PLT (B1_plt V1).**
- Reasoning: In round 1 I backed `bits()` because I thought `to_bits` would add an exception to a clean rule. F5 shows the rule is not clean today: `Char.to_digit` already has no `From` impl behind it. So the scoped wording does not add an exception. It removes a contradiction that already exists and makes `to_digit` legal on paper. That is subtraction, which meets my bar, and it also removes the need for a help line that only fixes a name we chose. PLT's draft is the tightest of the four and names the rule's scope directly.
- Concern: someone may later read "suffix names no type" as permission for any `to_<word>` method, so reviewers must hold new `to_` names to a strict reading.

**Q2: Yes.**
- Reasoning: The spec states a sign test twice in core §3 text. A built-in removes the `1.0 / x` trick from that text and avoids an import in the line users copy most. IEEE 754 lists `isSignMinus` as a required operation (PLT), so it is a primitive of the type, not a utility. The limit to one sign method keeps the surface small.
- Concern: users may read `is_sign_negative` as `x < 0.0` and miss that it is `true` for `-0.0` and for a NaN with the sign bit set, so L4 must ship with it.

**Q3a: Yes.**
- Reasoning: (a) is one help line on an error that exists already, and (c) is the default behavior. Neither adds a code or a rule.
- Concern: the help text in (a) must name whatever Q1 decides, or it teaches a name that does not exist.

**Q3b: Follow-up.**
- Reasoning: A new warning code brings new surface: its own scope questions (`x < -0.0`, match arms, consts, as Systems listed), explain text and suppression. The spec decision does not depend on it. A separate ticket can settle that scope properly.
- Concern: the follow-up may sit unfiled or unranked, so the moderator should file it at once, with this panel's support recorded.

**Q4: No.**
- Reasoning: Method calls are not const expressions (§2.21). Making one method const opens the "which methods are const" question for every pure built-in method. `-0.0` already covers the named use case.
- Concern: none for this ticket, provided the `const fn` work records `from_bits` as an early candidate.

**Q5:**
- L1 include. This is the contract of the feature, and naming signaling NaNs binds the codegen.
- L2 include. One sentence that keeps users from treating bits as `==`.
- L3 include. Without it, portability arguments come back as bug reports.
- L4 include. It is the one place where the new test disagrees with the old one.
- L5 include. Without it, L1 does not hold through a `let` or an `@ffi` call. Keep it to one short clause.
- L6 exclude. *Float Text Form* already says a bit pattern is outside the rule. A second copy is text to keep in sync for no gain.
- Concern: five law sentences on four methods can grow into a sub-chapter. Each should stay to one sentence.

**Q6: P (bold run-in paragraph, with a pointer from *Float Text Form*).**
- Reasoning: The text is one paragraph. A named heading adds a section to keep in sync. Tools can anchor to the bold run-in, the same way they do for the other run-in rules in §3.
- Concern: if the paragraph grows past the laws above, a heading becomes justified, and the panel should allow that without a new vote.

**Q7: S (separate ticket; examples avoid literals at or above `0x8000000000000000`).**
- Reasoning: The literal rule is about all `U64` literals, not about Float. With `is_sign_negative` in place, no example in this change needs such a literal. Blocking would tie a settled decision to an open one.
- Concern: users will write `x.to_bits() == 0x8000000000000000` early, so the literal ticket should rank high.

#### Phase D — Round 2 on Q6

Facts given to the panel: F7, *Float Total Ordering* and *Integer Division* are `####` headings, and *Float Text Form* and *Sized Integer Types* are `#####` headings; F8, llms-full.md has a level-2 topic `## Float Methods`.

##### Debate

###### Systems

**Systems seat, Phase D (Q6 only)**

**Position: I move to H**, on the condition below.

Placement does not change codegen or run-time cost, so my seat has no stake here. My own Phase C concern was "`blink llms --topic` has a weaker anchor than a heading would give it." That is the tooling seats' argument, and retrieval and help-line links are their domain, not mine. I defer to them.

To DevOps: "that link breaks when the section moves." I agree. A help line that links to the middle of *Float Total Ordering* depends on where the paragraph happens to sit, and a heading does not.

To Web, on the "dumping ground" concern: I share it. The condition I attach is that *Float Bits* holds only the bits pair, `is_sign_negative` and the laws L1 to L5. Any other Float helper goes elsewhere or needs a new vote.

To Minimalism: "A named heading adds a section to keep in sync." Make it a sibling heading at the same level, directly after *Float Total Ordering*, with no new section number. That keeps the extra upkeep to one heading line. The pointer from *Float Text Form* stays.

To PLT: "I accept H if the tooling seats need an anchor." Three seats say they need one.

Stable, ready to vote.

###### Web/Scripting

**Web/Scripting seat: Phase D, Q6**

**Position: I change my vote to P.**

My H vote rested on this claim: "People search for 'float bits', and so do `blink llms --topic` and `blink explain`." I checked that claim, and it is wrong for `llms`. `print_sections_matching` in src/cli.bl splits `llms-full.md` on `"\n## "` and matches only those level-2 titles. It does not read sections/ at all. A level-5 *Float Bits* heading under *Float Total Ordering* would give `llms --topic` nothing. What reaches models and users is the llms reference text, and that text can say "Float bits" in its own words whatever the spec layout is.

What remains of the H case is a link anchor for help lines and explain pages. The spec already has 172 bold run-in rules in sections/03_types.md, and tools must handle that pattern anyway. One more run-in does not change that.

To DevOps: "that link breaks when the section moves." A heading anchor breaks when the heading is renamed, so neither option is safe. Help text that names the method (`to_bits()`, `is_sign_negative()`) helps a user more than a section link does.

To Minimalism: "if the paragraph grows past the laws above, a heading becomes justified." I agree, and I would add that rule to the record, so that a later heading needs no new vote.

Stable, ready to vote.

###### PLT

**PLT seat — Phase D, Q6**

**Position: I move to H** (a named sub-heading *Float Bits*, right after *Float Total Ordering*, with the pointer from *Float Text Form*).

In Phase C I wrote: "I accept H if the tooling seats need an anchor." Three seats said they do. DevOps: "help lines and explain pages must link to *Float Total Ordering* and name the paragraph, and that link breaks when the section moves." That is a concrete need. I see no soundness cost on the other side. My one reason for P was that L2 should sit next to the `==` rules it qualifies. H keeps it there if the heading comes directly after *Float Total Ordering*, so that reason holds under H too.

To Web: "The heading may grow into a dumping ground for unrelated Float helpers later." I agree that this is a risk. Bound it in the text: the heading covers the representation observers (`to_bits`, `from_bits`, `is_sign_negative`) and their laws. Numeric helpers such as `copysign` or `signum` go elsewhere if they ever ship. A heading whose scope is stated is easier to keep clean than a run-in paragraph, because the scope sentence gives reviewers something to point to.

To Minimalism: "A named heading adds a section to keep in sync." It is one heading line over the same paragraph. The text to keep in sync stays the same size.

**Stable, ready to vote.**

###### DevOps

**DevOps/Tooling seat, Phase D on Q6**

**Position: I move to P.**

I checked my own argument against the repo, and it was weaker than I said. I wrote: "A bold run-in paragraph has no anchor." In practice, the spec and the code cite rules by name, not by a URL anchor. They cite headings and run-ins the same way:
- A heading: `lib/std/num.bl:146` cites "§3.6 *Float Text Form*", and `src/typecheck.bl:21650` cites "Float Total Ordering".
- A run-in: §3c.3 cites "(§3.2, *Stdlib API surface: methods only*)", which is a bold run-in paragraph.

So a help line or an explain page can cite "§3 *Float bits*" just as well under P. My Phase C concern ("that link breaks when the section moves") applies to a heading too.

To sys, "`blink llms --topic` has a weaker anchor": that is true for topic splitting today. It is a tooling problem that I can fix in the tool, and not a reason to add a heading for one paragraph.

To min, "if the paragraph grows past the laws above, a heading becomes justified, and the panel should allow that without a new vote": I agree, and I ask that the decision record says so.

**Condition on my P vote:** the paragraph opens with the exact bold name **Float bits.**, and diagnostics and explain pages cite it by that name.

Stable, ready to vote.

###### AI/ML

**AI/ML seat, Phase D on Q6**

**Position: I move to P.**

I checked my own Phase C reason, and it does not hold. `blink llms --topic` does not read headings in sections/. Its topics come from the hand-written llms-full.md, which already has a "Float Methods" topic (`blink llms --list`). That topic is where a model will find `to_bits`, `from_bits` and `is_sign_negative`, whichever form the spec text takes. Retrieval for models depends on the llms-full.md entry, not on whether §3 has a sub-heading. So my seat has no stake in H.

To DevOps: "A bold run-in paragraph has no anchor." Diagnostics in src/ cite the spec by file and section number (`sections/02_syntax.md 2.12.1`), not by heading anchor. A help line can name "*Float bits*, after *Float Total Ordering*" just as it names other run-in rules today. If help or explain text comes to need a stable link, Minimalism's clause covers it: "if the paragraph grows ..., a heading becomes justified, and the panel should allow that without a new vote."

To PLT: "The laws sit next to the `==` rules they qualify." I agree. L2 reads as a remark on `==`, and a reader of *Float Total Ordering* should meet it there.

What my seat does need, as a condition, not a vote: the change must add the three methods to the "Float Methods" entry in llms-full.md, with the L4 NaN-sign sentence. Without that entry, neither P nor H reaches a model.

Stable, ready to vote.

###### Minimalism

**Minimalism seat: Phase D, Q6**

**Position: I move to H** (a `####` sub-heading *Float Bits* right after *Float Total Ordering*, with the pointer from *Float Text Form*).

**Why I move.** My only cost argument was "a heading adds a section to keep in sync." I checked §3, and that cost is close to zero here. The topics next to this one, *Float Total Ordering* and *Integer Division*, are short `####` headings already. So a heading follows the local pattern, and a bold run-in inside *Float Total Ordering* would be the odd shape. I also claimed "tools can anchor to the bold run-in." That is weaker than I said. DevOps is right: "that link breaks when the section moves." A heading is the one thing `blink llms --topic`, `blink explain` and help lines can name without depending on the text around it. Three seats need that anchor, and it costs one line.

**To Web's concern:** "The heading may grow into a dumping ground for unrelated Float helpers later." I share it. Keep the scope fixed: *Float Bits* holds the bits pair, `is_sign_negative` and laws L1–L5, nothing more. `copysign`, `signum` and other helpers go to `std.float` docs, not under this heading, unless a new vote says otherwise.

**To PLT:** "The laws sit next to the `==` rules they qualify." H keeps that. The heading sits directly after *Float Total Ordering*, so a reader of L2 still finds it next.

**Status:** stable, ready to vote.

##### Re-vote: H 4-2 (Web, PLT, DevOps, AI/ML for H; Systems *(dissent)*, Minimalism *(dissent)* for P)

In the debate, Sys, PLT and Min moved to H, and Web, DevOps and AI/ML moved to P. In the vote, Web, DevOps and AI/ML returned to H on F7, editor outlines and chunking; Sys and Min returned to P once the anchor claim was withdrawn.

###### Systems

**Systems seat: Phase D re-vote, Q6**

**Vote:** P.

**Reasoning:** In D1, I moved to H only because I deferred to the tooling seats on anchors. All three of them have now checked the repo and withdrawn that claim. Web and AI/ML showed that `blink llms --topic` reads only the level-2 topics of llms-full.md and never sections/. DevOps showed that code and spec cite a bold run-in by name as easily as a heading. With the anchor argument gone, the paragraph should sit where the sign-test line sits today and next to the `==` rules that L2 qualifies. Minimalism's point about local shape (F7) is true, but §3 already has many bold run-in rules, so it does not decide the question.

**Conditions I support for the record:**
- The paragraph opens with the exact bold name **Float bits.**, and help lines cite it by that name (DevOps).
- The change adds the three methods and the L4 NaN-sign sentence to the llms-full.md *Float Methods* topic (AI/ML).
- If the paragraph grows past the bits pair, `is_sign_negative` and L1 to L5, it may become a heading with no new vote (Minimalism, Web).

**Concern:** Tools that look only at headings miss the paragraph. The llms-full.md entry must ship in the same change to cover that.

###### Web/Scripting

**Web/Scripting seat: Phase D re-vote, Q6**

**Vote:** H (a `####` sibling heading *Float Bits* right after *Float Total Ordering*, with the pointer from *Float Text Form*). Its scope is fixed: the bits pair, `is_sign_negative` and laws L1–L5.

**Reasoning:** In D1 I dropped my H vote, but only because the `llms --topic` argument was false. Both sides now agree that tool anchors do not decide this question. Two things still differ between P and H, and both favor H.
- F7: the topics next to this one are short `####` headings, so H follows the local pattern.
- A reader who scans the table of contents sees headings and never sees run-ins. A user who wants "how do I get the bits of a float" finds *Float Bits* in the table of contents. Under P, they first have to guess that it sits inside *Float Total Ordering*.

**Concern:** Without the stated scope, the heading could collect Float helpers that do not belong there. So the scope sentence must go in the decision record.

###### PLT

**PLT seat — Phase D re-vote, Q6**

**Vote:** H (a `####` sibling heading *Float Bits* directly after *Float Total Ordering*, pointer from *Float Text Form*).

**Reasoning:** The anchor argument that moved me in D1 is gone. Web, DevOps and AI/ML showed that `llms --topic` reads llms-full.md and that diagnostics cite run-ins and headings by name in the same way, so I do not count it. What decides it for me is F7 and scope. The sibling rules of the same kind (*Float Total Ordering*, *Integer Division*) are short `####` headings, so a heading follows the local structure. A heading also states a scope boundary (the bits pair, `is_sign_negative`, L1–L5), and a reviewer can enforce that boundary. A run-in inside another rule's section has no such boundary. L2 still comes directly after the `==` rules it qualifies, so P's one merit holds under H too.

**Concern:** Without the stated scope, the heading can collect unrelated Float helpers. The record should say that anything beyond the bits pair, `is_sign_negative` and L1–L5 needs a new vote. I also support AI/ML's condition that the llms-full.md *Float Methods* entry gets the three methods and the L4 sentence.

###### DevOps

**DevOps/Tooling seat: Phase D re-vote on Q6**

**Vote: H**, a `####` sibling heading *Float Bits* directly after *Float Total Ordering*, with the pointer from *Float Text Form*. Its scope is stated: the bits pair, `is_sign_negative` and laws L1–L5.

**Reasoning:** My D1 point still holds: the anchor argument is equal for both options. Code and spec cite rules by name, and `llms --topic` reads llms-full.md, not sections/ (Web, AI/ML). Two facts decide it for me. First, F7 shows the topics next to this one (*Float Total Ordering*, *Integer Division*) are short `####` headings, so H follows the local shape. Second, Markdown outlines in editors and on the repo host list headings and skip bold run-ins, so a reader who scans the outline of §3 finds *Float Bits* only under H. PLT's scope sentence also gives reviewers a stated limit to point to, and that answers Web's "dumping ground" concern better than a run-in does.

**Concern:** Under either option, the change must also add `to_bits`, `from_bits` and `is_sign_negative`, with the NaN-sign sentence, to the *Float Methods* entry in llms-full.md (AI/ML's condition). Without that entry, neither P nor H reaches `blink llms`.

###### AI/ML

**AI/ML seat, Phase D re-vote on Q6**

**Vote:** H (a `####` sub-heading *Float Bits*, right after *Float Total Ordering*, holding only the bits pair, `is_sign_negative` and the laws, with the pointer from *Float Text Form*).

**Reasoning:** In D1 I dropped my `llms --topic` reason, and that still holds: neither option changes what `llms` serves. Two other points decide it for me.
- F7: the topics next to this one are short `####` headings, so H matches the local shape.
- Chunking. Tools that feed a spec to a model (RAG indexers, editor context) split Markdown at headings. Under P, the bits laws would land in the *Float Total Ordering* chunk, mixed into the `==` rules. Under H they form their own chunk, and that chunk can be found by its name.

The scope sentence that PLT and Systems ask for keeps the heading from growing.

**Concern:** The heading's scope rule must be written in the decision record, or later Float helpers will pile up under it.

**Condition (unchanged from D1):** the change adds the three methods and the L4 NaN-sign sentence to `## Float Methods` in llms-full.md.

###### Minimalism

**Minimalism seat: Phase D re-vote, Q6**

**Vote:** P (a bold run-in paragraph, **Float bits.**, right after *Float Total Ordering*, with a one-line pointer from *Float Text Form*).

**Reasoning:** I moved to H in D1 for one reason: DevOps's claim that a run-in link "breaks when the section moves." DevOps has now withdrawn that claim, and the evidence supports the withdrawal. Code and spec cite rules by name, run-ins included (§3c.3 cites *Stdlib API surface: methods only*). `blink llms --topic` reads only level-2 titles in llms-full.md, not sections/ (Web, AI/ML). sections/03_types.md already has 172 bold run-ins. With no tooling need left, the smaller form wins: one paragraph, no new heading.

**Concern:** a stale help line could cite "Float bits" after the paragraph is renamed. So the record should fix the bold name **Float bits.** (DevOps's condition), let the paragraph become a heading later with no new vote if it grows, keep the scope to the bits pair, `is_sign_negative` and L1–L5, and require the "Float Methods" entry in llms-full.md to list the three methods with the L4 sentence (AI/ML's condition).


### Final Spec

```blink
// Float: to_bits(self) -> U64, Float.from_bits(U64) -> Float, is_sign_negative(self) -> Bool
// F32:   to_bits(self) -> U32, F32.from_bits(U32) -> F32,     is_sign_negative(self) -> Bool
fn main() {
    let z = -0.0
    assert(z == 0.0)                         // == does not see the sign
    assert(z.is_sign_negative())
    assert(z.to_bits() != 0.0.to_bits())     // the bits do
    let nan = Float.from_bits(9221120237041090561) // a quiet NaN, payload 1
    assert(nan.to_bits() == 9221120237041090561) // the payload is kept
}
```

- Built-in methods, no import. `from_bits` is total and static.
- `to_bits` is not a conversion. §3c.3 covers `to_X` and `to_X_checked` only where `X` names a type; `Float.to_bits` and `Char.to_digit` fall outside it.
- Laws: round trip (signaling NaNs included); equal bits imply `==`, not the converse; arithmetic does not fix a NaN's sign or payload; `is_sign_negative` is the sign bit, NaN included; copy, move, storage and `@ffi` passing keep every bit (not what C code does with the value).
- A bitwise operator on a `Float` stays a type error; its help names `to_bits()`.
- No hex float text form, no NaN canonicalization, no const `from_bits`, no `copysign`/`signum`/`is_sign_positive`.
- Spec: §3.6 *Float Total Ordering*, *Float Bits*, *Float Text Form*; §3.2.1 *Parsing* (the `parse_float` NaN bullet); §3c.3 *The `to_` rule for scalars*; llms-full.md *Float Methods*.
- Follow-ups: the `-0.0` literal warning (before the next release); `U64` literals at or above `0x8000000000000000`; const `from_bits` with `const fn`.
