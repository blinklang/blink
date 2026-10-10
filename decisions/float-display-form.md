[< All Decisions](../DECISIONS.md)

# Float Text Form — Design Rationale

## Gap

The spec did not fix the text that `Float.display()` writes. The runtime used C `%g`, which loses data and depends on the C library:

```blink
fn main() {
    io.println((0.1 + 0.2).display())   // printed 0.3, a different Float
    io.println(1.0.display())           // printed 1, which reads as an Int
    io.println((0.0 / 0.0).display())   // printed -nan on glibc
}
```

The question: which text must every `Float` render as, so that the text parses back to the same value? The ticket also asked how `-0.0` and NaN render, and whether the §3.6.1 *Debug vs Display* Float exception can go.

## Result

| Question | Result | Vote |
|---|---|---|
| Q1 (+Q6) `-0.0` and the round-trip equality | **1b**: `-0.0` renders as `0.0`; delete the §3.6.1 Float exception; the round-trip law uses Blink `==` | 5-1 (Systems dissent) |
| Q2 Exponent cut-offs | **2b**: Python `repr` cut-offs; plain form when −4 ≤ k < 16 | 6-0 |
| Q3 One-digit mantissa | **3a**: `1.0e16`, `5.0e-324`; every finite output contains `.` | 6-0 |
| Q4 NaN spelling | **4a**: `NaN` | 6-0 |
| Q5 Infinity spelling | **5a**: `inf` / `-inf` | 6-0 |
| Q7 F32 | **7a**: whenever an F32 renders as text, it uses the same rule with binary32 shortest digits; no Display impl added | 6-0 |
| Q8 `parse_float` input grammar | **8a**: only "accepts every display output, rounds correctly"; the rest is a separate ticket | 5-1 (DevOps dissent) |
| Q9 Exponent float literals | **9b**: separate type:spec ticket; the spec records that every output matches `DIGITS '.' DIGITS ('e' '-'? DIGITS)?` with an optional `-` | 6-0 |
| Q10 "One form everywhere" | **10a-wide**, W-plt wording | Phase C 4-1-1; Phase D 6-0 (wording 4-2 over W-devops) |
| Q11 Locale | **11a**: decimal mark is always `.`; neither display nor `parse_float` depends on the locale | 6-0 |
| Q12 One text per value | **12a**: §3.6 states "`x == y` exactly when `x.display() == y.display()`" | 6-0 |

Common to all six proposals (C1–C6): the fewest digits that round-trip, then the nearest, then an even last digit; `.0` on an integer value; one NaN text; `debug()` equals `display()`; `parse_float` accepts every display output; lowercase `e`, no `+`, no leading zeros in the exponent.

Phase D ran on Q10 only. AI-first review: 5/5 pass. The user approved the tally (Q1 and Q8 split 5-1).

This decision replaces Q3 of [Map Debug Entry Order](map-debug-entry-order.md), which named Float as the one built-in exception to the Debug/Eq law.

**Spec wording note.** The W-plt wording ends "How JSON encodes NaN and the infinities is decided in §3.6.2." §3.6.2 does not decide that yet, so the spec text says that the question "belongs to §3.6.2, not to this rule". A follow-up ticket decides it. As aiml, web and min asked, the spec follows the W-plt sentence with W-min's list of places.

**Dissents.**
- **Systems (Q1):** "Display text leaves Blink. Under Q10 it is also how JSON writes numbers, and the Python, numpy and Postgres programs that read it tell −0.0 from 0.0 (`atan2`, `copysign`). With 1b, a value silently changes on its way out, and with no `to_bits` today, no Blink program can print the sign at all."
- **DevOps (Q8):** "Display output alone does not cover what a tool must read. A parser that accepts only display output could reject `1E5` or `1e+5`, which come from JSON, Python and C output that Blink programs must ingest."

Both dissents have follow-up tickets: a bit-exact `to_bits` path, and the `parse_float` input grammar.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Every panelist text below is verbatim.

#### Phase A — Independent proposals

Each seat proposed alone. The moderator's mechanical dedupe of these proposals produced Q1–Q10; Q11 and Q12 came from points the panel raised in Phase B.

**Systems:**

> SYS Phase A proposal (wqv5yd): spec the Float output down to the byte as shortest-closest digits, always with ".0", JS exponent thresholds, "-0.0", "NaN", "inf".
>
> ## P1 — Digits: shortest, then closest, then even (normative)
> Rule text: "For a finite nonzero x, `x.display()` picks the decimal D = d1.d2…dn × 10^k (d1 ≠ 0) with the smallest n such that IEEE-754 round-half-to-even parsing of D gives x. If more than one D has that n, pick the one nearest the exact value of x. If two are equally near, pick the one whose dn is even."
> This picks one output for each x, so Ryu, Schubfach, Dragonbox and Grisu-with-fallback all give the same bytes. The spec names the output and leaves the algorithm open.
>
> ## P2 — Layout (normative)
> With n and k from P1:
> - 0 ≤ k ≤ 20: the digits d1…d(k+1) (right-padded with zeros if n ≤ k), then ".", then the remaining digits, or "0" if no digits remain.
> - −6 ≤ k < 0: "0." followed by (−k−1) zeros, then d1…dn.
> - Other k: d1 "." (d2…dn, or "0") "e" k. The exponent has no "+" and no leading zeros, and "-" only when k < 0.
> - A negative x gets a "-" prefix. Zero is "0.0". Negative zero is "-0.0".
> - NaN is "NaN" (one spelling: no sign, no payload). The infinities are "inf" and "-inf".
> - The output never depends on locale. The decimal mark is always "." whatever LC_NUMERIC says.
> - `Float.debug()` is the same as `display()` (already decided).
>
> ## P3 — Round-trip law (normative)
> `x.display().parse_float() == Ok(x)` for every Float x, under Blink `==`, so NaN is covered. `parse_float` must accept every string P2 can produce, with no locale dependence. For finite values and both zeros the bits match too: "-0.0" parses to −0.0. Beyond that set, which input `parse_float` accepts is a separate ticket.
>
> ## P4 — F32
> Use P1 with F32 precision and P2 unchanged. `F32.from(0.1)` renders "0.1", not "0.10000000149011612".
>
> ## P5 — −0.0 and the §3.6.1 exception
> Keep the sign: "-0.0". Change the §3.6.1 wording from "may render differently" to "renders differently: `(-0.0).display()` is `\"-0.0\"`, `(0.0).display()` is `\"0.0\"`". The exception stays, now as a fixed rule.
>
> ## Example
> ```
> fn main() {
>     io.println(0.1.display())              // 0.1
>     io.println((0.1 + 0.2).display())      // 0.30000000000000004
>     io.println(1.0.display())              // 1.0
>     io.println((1.0 / 3.0).display())      // 0.3333333333333333
>     io.println(123456789.0.display())      // 123456789.0
>     io.println(9007199254740993.0.display()) // 9007199254740992.0
>     io.println(0.000001.display())         // 0.000001
>     io.println((0.000001 / 10.0).display()) // 1.0e-7
>     io.println((100000000000000000000.0 * 10.0).display()) // 1.0e21
>     io.println(0.0.display())              // 0.0
>     io.println((-1.0 * 0.0).display())     // -0.0
>     io.println((0.0 / 0.0).display())      // NaN
>     io.println(Float.INF.display())        // inf
>     io.println((0.0 - Float.INF).display()) // -inf
>     let p = (0.1 + 0.2).display().parse_float()?
>     assert p == 0.1 + 0.2                  // passes; today's "%g" output "0.3" fails it
> }
> ```
>
> ## Tradeoffs (systems)
> - **Cost:** shortest-digit printing (Ryu/Schubfach) takes about 20–50 ns per double, with no heap use. glibc `snprintf("%g")` takes hundreds of ns, parses a format string, and reads locale. So the change is faster than today's code. Ryu's full tables are about 10 KB; the small-table version is under 1 KB. The output is at most 25 bytes ("-0.0000012345678901234567"; the exponent form tops out at 24), so the runtime can write it from a fixed stack buffer straight into the StringBuilder.
> - **Locale is a real bug today.** An FFI call to `setlocale` turns `%g` output into "1,5". A language whose only path from a scalar to Str is Display cannot let libc state change that output. The same applies to `strtod` in `parse_float`.
> - **Why always ".0":** debug() equals display(), so power-assert and Debug text must tell `1.0` apart from `1`. It also keeps JSON types: §3.6.2 parses "1" as `JsonValue.Int`, so a Float field written as "1" comes back as an Int. "1.0" comes back as a Float, and is also a valid Blink literal.
> - **Why the JS thresholds (−6 ≤ k ≤ 20), not "never exponent" (Rust):** with no exponent, `1.0e300` prints 300+ digits and the output length has no bound. With bounded output, every caller can use a fixed buffer. The form "1.0e21" (always a "."; no "+") is valid JSON, and a future exponent-literal grammar can use it unchanged.
> - **Why "-0.0":** Display is the ONLY path from a scalar to Str. If it drops the sign, a program can show the sign only through `1.0 / x`. A serializer that writes −0.0 as "0.0" changes `atan2` and `1/x` results downstream, and breaks bit-exact round-trips (checkpoint files, golden tests). The Debug/Eq exception costs almost nothing: `assert_eq` prints debug text only when `a != b`, and in that case no −0/+0 pair can show up. Float cannot be a Map key (no Hash), so key sort order is not affected either. The only visible case is two equal containers whose Float values differ only in the sign of zero. That is a real bit difference that the user may want to see.
> - **NaN:** Blink has one NaN under `==`, so it gets one spelling. Glibc's "-nan" today is a libc leak.
> - **Same routine everywhere:** the power-assert intro, the layout.bl printf table, and the test-runner `duration_ms` must call this routine, not `%g`. That is an implementation chore and needs no spec text.
>
> ## Cross-language
> Digits match JS, Python repr, Rust, Go `'g', -1`, and Java 19+; all use shortest round-trip. The thresholds come from ECMA-262. The ".0" matches Python and Rust Debug. "-0.0" matches Python and Java (JS prints "0"). "NaN" matches JS, Rust, and Java; "inf" matches Rust and Python. C `%g` (6 digits, locale-dependent) is what we drop.
>
> Vote preference: P1+P2+P3+P5 as one package. P4 as an option, decoupled if the panel wants it.
>
> (Erratum applied: example line replaced with `0.0.display()`; last sentence of -0.0 tradeoff reworded per sys.)

**Web/Scripting:**

> ## Web/Scripting proposal for wqv5yd: how `Float` renders as text
>
> **What decides it for me:** in 5 minutes, a JS or Python developer must be able to predict what `io.println(x)` prints. They should never see `-nan`, `1e-07` or `1.23457e+08`, and two equal values should never render differently. The spec already depends on this behaviour: §3.6 shows `Point { x: 1.0, y: 2.5 }` and `"{2.5}"` as `2.5`. Today's `%g` output (`1`) contradicts the spec's own example.
>
> ### Proposal W1: the rule to write into §3.6 (Float Display)
>
> **Digits.** Pick the decimal digit string with the fewest significant digits that parses back to the same Float, using round-to-nearest-even. If several strings of that length qualify, pick the one nearest to the exact binary value. If two are equally near, pick the one whose last digit is even. Ryu, Grisu with fallback, Dragonbox and Schubfach all give these digits, as do Python `repr`, JS and Java 19+.
>
> **Layout.** Write the value as `d.ddd × 10^k` with `d ≠ 0`.
> - **Fixed form** when `-4 <= k < 16`:
>   - Write the digits with a decimal point. Add zeros as needed.
>   - Always write at least one digit on each side of the point: `1.0`, `100.0`, `0.5`, `0.0001`.
>   - Never write trailing zeros past the first fractional digit.
> - **Exponent form** when `k < -4` or `k >= 16`:
>   - The mantissa is `d` when there is one digit, else `d.ddd`.
>   - Then write `e`, then `-` if `k < 0`, then `k` in decimal with no `+` and no leading zeros: `1e16`, `1.5e-7`, `5e-324`.
> - A negative value gets a leading `-`.
>
> **Special values.**
> - Every NaN renders `NaN`, whatever its sign or payload bits.
> - Positive infinity renders `inf`, and negative infinity renders `-inf`.
> - **`-0.0` renders `0.0`.**
>
> **Debug.** `Float.debug()` equals `display()`, which §3.6.1 already requires.
>
> **Remove the §3.6.1 exception.** With these rules, every pair of `==`-equal Floats renders the same text. That holds for NaN==NaN and for -0.0==0.0. Delete the "Float is the one built-in exception" paragraph.
>
> **F32.** Use the same rules, but the digits are the shortest string that parses back to the same **F32**. `0.1` as F32 renders `0.1`, not `0.10000000149011612`.
>
> **Round-trip law.** For every Float `x`, `x.display().parse_float()` is `Ok(y)` with `y == x`, using Blink `==`. This also fixes the minimum that `parse_float` must accept:
>
> ```
> -?digits(.digits)?(e-?digits)? | NaN | inf | -inf
> ```
>
> It must round correctly, half to even. The panel can decide separately whether to accept more input, such as `+`, `e+5`, or `Infinity`.
>
> **One form everywhere.** Every place the language or toolchain renders a Float uses this form. That includes interpolation, power-assert, and test-runner output.
>
> ```blink
> io.println(0.1)                  // 0.1
> io.println(0.1 + 0.2)            // 0.30000000000000004
> io.println(1.0)                  // 1.0
> io.println(100.0)                // 100.0
> io.println(1.0 / 3.0)            // 0.3333333333333333
> io.println(123456789.0)          // 123456789.0
> io.println(9007199254740993.0)   // 9007199254740992.0
> io.println(10000000000000000.0)  // 1e16
> io.println(0.0001)               // 0.0001
> io.println(0.00001)              // 1e-5
> io.println(1.0 / 0.0)            // inf
> io.println(-1.0 / 0.0)           // -inf
> io.println(0.0 / 0.0)            // NaN
> io.println(-0.0)                 // 0.0
> io.println([1, 2].debug())       // [1, 2]
> io.println([1.0, 2.0].debug())   // [1.0, 2.0]
>
> let x = 0.1 + 0.2
> assert(x.display().parse_float().unwrap() == x)
> ```
>
> ### Tradeoffs from the web/scripting seat
>
> 1. **Always write `.0`.** This is the right choice because Debug equals Display for Float. Without `.0`, `[1, 2]` and `[1.0, 2.0]` would print the same text. That is a "why does my list look like Ints?" question waiting to happen. Python developers already expect `1.0`. JS developers lose `1`, but JS has only one number type, so it has no Int to confuse it with. Rust needs a second form (`{:?}`) to get `1.0`. We have one form, so it must be the clear one.
>
> 2.
>  **`-0.0` renders as `0.0`.** "Why does my total say `-0.0`?" is a long-running Python Stack Overflow question. It comes from rounding small negative values for display. JS avoids it: `String(-0)` is `"0"`. This also fits Blink's own `==`, which already says the two are equal. Two values that `==` calls equal should look equal, and it closes the last gap in the Debug/Eq law.
>    - **The cost:** Display no longer shows the sign bit. People doing numeric work already have the spec's `1.0 / x < 0.0` test. The `ieee_eq` decision already said no Float equality tells -0.0 from 0.0, and printing follows that.
>    - Round-trip still holds under Blink `==`.
>    - I expect the systems seat to want `-0.0` for a bit-exact round trip. If the panel goes that way, keep the §3.6.1 exception. Don't render it as `-0`.
>
> 3. **Exponent thresholds come from Python `repr`.** Exponent form starts at `1e-5` and at `1e16` and beyond. Above 2^53, a fixed integer like `100000000000000000000.0` falsely suggests the digits are exact. JS's `1e21` cut-off is arbitrary. Python is the largest audience reading this output.
>
> 4. **`1e16`, not `1e+16` or `1e+016`.** It is the shortest form, it is valid JSON, and it matches Rust's `{:e}`. The C-style `e-07` padding we print today is noise.
>
> 5. **Special values: `NaN` / `inf`.**
>    - `NaN` is the spelling every audience recognises.
>    - `inf` matches Python, Rust and the prelude's `Float.INF`.
>    - JS's `Infinity` is wordier, and JSON accepts neither spelling anyway.
>    - Fixing the text kills libc's `-nan` and makes output the same on every platform.
>
> 6. **Float literals.** Fixed-form output is always a valid Blink literal today. Exponent-form output is not, because the lexer has no exponent form. I recommend a separate friction or spec ticket for exponent literals (`1e16`). This decision doesn't depend on it, because `parse_float` gives the round trip.
>
> ### Cross-language summary
>
> | Value | Proposed | Python repr | JS | Rust Display | Today |
> |---|---|---|---|---|---|
> | 0.1 + 0.2 | 0.30000000000000004 | same | same | same | 0.3 |
> | 1.0 | 1.0 | 1.0 | 1 | 1 | 1 |
> | 1e16 | 1e16 | 1e+16 | 10000000000000000 | 10000000000000000 | 1e+16 |
> | -0.0 | 0.0 | -0.0 | 0 | -0 | -0 |
> | NaN | NaN | nan | NaN | NaN | -nan |
>
> The proposal is Python's `repr`, with JS's handling of `-0`, Rust's exponent spelling and the common `NaN` spelling. It needs no new concept for anyone to learn.

**PLT:**

> ## PLT seat: Phase A proposal (wqv5yd, Float rendering)
>
> My aim is to define Float text through **laws** and then pick the one layout those laws allow. "Shortest round-trip" alone does not fix the bytes. JS, Python and Rust all satisfy it and still give three different outputs.
>
> ### Proposal A: the laws (normative, §3.6 Display Format Protocol)
>
> For all `x, y: Float`:
>
> - **L1 Round-trip:** `x.display().parse_float() == Ok(x)`, using Blink's `==`.
> - **L2 Canonical:** `x == y` exactly when `x.display() == y.display()`. The text is a function on the Eq classes, and different classes give different text.
> - **L3 Shortest:** no text with fewer significant digits satisfies L1.
> - **L4 Float-visible:** every finite output contains `.`.
>
> L2 decides the -0.0 and NaN questions. Blink's `Eq` treats `-0.0` and `0.0` as one class, and all NaNs as one class. Rendering must therefore not split either class:
>
> - `-0.0` and `0.0` both render as `0.0`.
> - Every NaN renders as `NaN`, whatever its sign or payload bits.
>
> Because `debug()` equals `display()` for Float, L2 makes the §3.6.1 Debug/Eq law hold for Float with no exception. **I propose that we delete the exception text from §3.6.1.** The sign of zero stays observable through `1.0 / x < 0.0`, which the spec already gives.
>
> ### The exact algorithm (byte-identical output)
>
> 1. **NaN** gives `NaN`. **+∞** gives `inf`, and **−∞** gives `-inf`. **±0** gives `0.0`.
> 2. **Other finite x:** emit `-` if x < 0, then format |x| as follows.
>    - Choose decimal digits d₁…dₙ (with d₁ ≠ 0 and dₙ ≠ 0) and an integer k so that the value is d₁.d₂…dₙ × 10ᵏ.
>    - n is the smallest count for which some n-digit decimal rounds to x under IEEE binary64 round-half-even.
>    - If more than one n-digit decimal qualifies, take the one nearest the exact value of x. If two are equally near, take the one whose last digit is even. This is the ECMA-262 Number::toString digit rule, and Ryu, Schubfach and Dragonbox all compute it.
> 3. **Positional layout when −4 ≤ k < 16.**
>    - Write the digits with the decimal point placed by k.
>    - Pad with zeros so there is at least one digit on each side of `.`.
>    - No trailing zeros after `.`, except the one needed when the fraction is empty.
> 4. **Scientific layout otherwise.**
>    - Write `d₁.d₂…dₙ`. When n = 1, write `d₁.0`.
>    - Then `e`, then `-` if k < 0, then k without leading zeros. Never write `+`.
> 5. **`parse_float` must:**
>    - Accept every string that rule 1–4 can produce.
>    - Round correctly (round-half-even). L1 depends on this.
>    - Also accept the grammar `-? DIGITS ('.' DIGITS)? ([eE] [-+]? DIGITS)?`. Whether it takes more (a leading `+`, `nan`) is a separate parse question, but it must take at least this.
>
> ### F32
>
> `F32` uses the same rules with binary32 as the target format.
>
> - `F32` 0.1 renders as `0.1`.
> - `(0.1 as F32).to_float()` renders as `0.10000000149011612`. That is correct, because they are different values.
>
> ### Example
>
> ```blink
> fn main() {
>     io.println(0.1.display())                 // 0.1
>     io.println((0.1 + 0.2).display())         // 0.30000000000000004
>     io.println(1.0.display())                 // 1.0
>     io.println((1.0 / 3.0).display())         // 0.3333333333333333
>     io.println(123456789.0.display())         // 123456789.0
>     io.println(9007199254740993.0.display())  // 9007199254740992.0
>     io.println(10000000000000000.0.display()) // 1.0e16
>     io.println(0.0001.display())              // 0.0001
>     io.println(0.00001.display())             // 1.0e-5
>     io.println((-0.0).display())              // 0.0
>     io.println((0.0 / 0.0).display())         // NaN
>     io.println((-1.0 / 0.0).display())        // -inf
>     io.println([1.0, 2.5].debug())            // [1.0, 2.5]
>     let x = 0.1 + 0.2
>     assert(x.display().parse_float() == Ok(x))
> }
> ```
>
> ### Proposal B: coupled literal grammar (recommended)
>
> Fix `FLOAT_LIT = DIGITS '.' DIGITS ('e' '-'? DIGITS)?`. With this, every finite rendered value, read back with a leading unary `-`, is also a valid B
>
> (PLT re-sent remainder in plain text; PLT notes "same in substance but not word-for-word")
> (Proposal B, continued) ...is also a valid Blink literal. Debug output then reads back as source, which is the stated aim of the §3.6.1 textual forms. This is also why scientific output keeps `1.0e16` and not `1e16`: the mantissa stays inside the `DIGITS '.' DIGITS` form. If the panel rejects B, Proposal A still stands, and scientific output then parses back only through `parse_float`.
>
> Tradeoffs (PLT):
> - Composition with JSON. `json.parse` sorts numbers by syntax: `20` gives Int, `20.0` gives Float. If Display wrote `1` for 1.0 (as JS and Rust do), Float -> text -> `json.parse` would come back as JsonValue.Int, and the encoder and decoder would disagree on the type. L4 stops this. `1.0e16` is also valid JSON. For the same reason, Debug of `[1, 2]` vs `[1.0, 2.0]` must show which type it holds.
> - Cost of L2. `-0.0` loses its sign in text, so bit-exact serialization needs another route, such as a future `to_bits`. I accept that. Text that splits an Eq class makes Display unsound with respect to `==`. Haskell has this flaw: `show (-0.0)` is "-0.0" but `-0.0 == 0.0`, so Show does not respect Eq. JS does what I propose: `String(-0)` is "0".
> - The thresholds -4 and 16 are the same as Python `repr`. Because positional layout covers k < 16, every integer up to 2^53 prints as all its digits. Values outside that range stay short, so you never get 300 digits.
> - No `+` in the exponent and no leading zeros give one spelling for each exponent, which L2 needs. Python's `1e+16` and C's `1e-07` are both spellings that parse to the same value as another spelling, so they are not canonical.
>
> Cross-language:
> - Python repr: same digit rule and same thresholds, but writes `e+16` and renders -0.0 as "-0.0".
> - JS: same digits, but 1.0 renders as `1`.
> - Rust: same digits, but Display of 1.0 is `1` and -0.0 is `-0`.
> Only the combination proposed here satisfies L1-L4 together.

**DevOps:**

> **DevOps/Tooling seat: Phase A proposal (wqv5yd, Float rendering)**
>
> My test for this gap: Float text goes into logs, golden snapshots, CSV, JSON, test-runner output and diagnostics. Other tools have to parse it, and CI has to get the same bytes on glibc, musl and macOS. The `%g` output we have today fails on all of that: it loses precision, its text depends on libc (`-nan`), and `1e-07` is not portable.
>
> ---
>
> ### Proposal 1: One canonical Float text, used by both Display and Debug
>
> **Spec rule (new §3.6 paragraph "Float text"):**
>
> 1. **Digits.** Pick the decimal with the fewest significant digits that converts back to exactly `x` under IEEE round-half-even. If more than one decimal of that length does this, pick the one nearest the exact binary value. If two are equally near, pick the one whose last digit is even. (This is what Ryu, Schubfach and Dragonbox compute.) No implementation may use the C library's printf for this.
> 2. **Layout.** Write the digits as `d1.d2…dn × 10^e`.
>    - If `-4 <= e <= 15`, use plain decimal form. The text always has a `.` and at least one digit after it, so `1.0` stays `1.0` and does not become `1`.
>    - If not, use scientific form: `d1`, then `.d2…dn` only when n > 1, then `e`, then the exponent. A negative exponent gets `-`; a positive one gets no sign. The exponent has no leading zeros.
>    - A negative value gets a leading `-`.
> 3. **Specials.** Every NaN renders as `NaN`, whatever its sign or payload. Positive infinity renders as `Infinity` and negative infinity as `-Infinity`.
> 4. **Zero.** Both `0.0` and `-0.0` render as `0.0`. Remove the Float exception from §3.6.1. The Debug/Eq law then holds for all built-in types with no exception.
> 5. **Round-trip law.** For every Float `x`, `x.display().parse_float() == Ok(x)`. This uses Blink `==`, so it holds for NaN and for -0.0 too.
> 6. **One formatter.** Display, Debug, power-assert values, JSON number output and the test runner's machine output all use this one routine. `F32` uses the same rule with its own shortest-digit search, so an `F32` of 0.1 renders as `0.1`.
>
> **Example:**
>
> ```blink
> fn main() {
>     io.println("{0.1}")                           // 0.1
>     io.println("{0.1 + 0.2}")                     // 0.30000000000000004
>     io.println("{1.0}")                           // 1.0
>     io.println("{123456789.0}")                   // 123456789.0
>     io.println("{1.0 / 3.0}")                     // 0.3333333333333333
>     io.println("{9007199254740993.0}")            // 9007199254740992.0
>     io.println("{10000000000000000.0}")           // 1e16
>     io.println("{100000000000000000000.0}")       // 1e20
>     io.println("{0.0001}")                        // 0.0001
>     io.println("{0.000015}")                      // 1.5e-5
>     io.println("{-0.0}")                          // 0.0
>     io.println("{0.0 / 0.0}")                     // NaN
>     io.println("{-1.0 / 0.0}")                    // -Infinity
>     let m = {1: -0.0}
>     io.println(m.debug() == {1: 0.0}.debug())     // true
> }
> ```
>
> **Tradeoffs, from the tooling side:**
>
> - **Byte-identical on every target.** Golden tests and `task ci` snapshots stop depending on which libc the machine has. That alone is reason enough to do this.
> - **`1.0`, not `1`.** Debug equals Display for Float (already decided). If `1.0` rendered as `1`, the Debug output of a struct with a Float field would look like an Int, both to a reader and to a diff tool. Also, §3.6.2 says `json.parse` gives `JsonValue.Int` for `20` and `JsonValue.Float` for `20.0`. If JSON output used `20`, a Float would come back as Int, and the round trip would change the variant.
> - **`e16`, not `e+16` or `e+016`.** All of these are valid JSON numbers. `float()` in Python, `Number()` in JS, `strconv.ParseFloat` in Go, `f64::from_str` in Rust, jq and Postgres all accept it. Leaving out the `+` and the zero padding removes the libc difference between `e+07` and `e+7`.
> - **`Infinity`, not `inf`.** `rg inf` in a log also matches `info`, `infer` and `config`; `I
> `Infinity` gives no false matches. `NaN` and `Infinity` are what JS and JSON5 write, and all four parsers above accept them. There is a single NaN text, because two NaNs are `==` in Blink, so the Debug/Eq law requires one rendering.
> - **-0.0 renders as `0.0`.** The text loses the sign bit, but there is no loss under Blink's own equality, because no Blink `==` tells the two apart. This removes the only exception to the Debug/Eq law, so a Map snapshot cannot change because a computation gave -0.0 in one place. Code that needs the sign already has the documented `1.0 / x < 0.0`.
> - **Longer text.** `0.30000000000000004` is longer than `0.3`, but it is the truth. When a log shows `0.3` and `assert x == 0.3` fails, the user cannot debug it. For short output, users can call `round`, or use `Decimal`, or a formatting API later. That is a separate ticket and I do not propose it here.
>
> **Cross-language:** The digit rule matches JS, Python repr, Rust, Go `'g', -1` and Java 19+. The layout and the `-4..15` limits match Python repr, which keeps `.0` and switches to scientific form at 1e16. The specials match JS. Python and Rust keep `-0.0`; we differ there on purpose, because our `==` is total.
>
> ---
>
> ### Proposal 2: Specify what `parse_float` accepts (needed for the round-trip law)
>
> **Spec rule (§3.1, after the `parse_float` row):**
>
> `parse_float` accepts exactly this, with no space before or after:
> `[+-]? DIGITS ("." DIGITS)? ([eE] [+-]? DIGITS)?`, plus `NaN`, `Infinity`, `+Infinity` and `-Infinity`. The specials are case-sensitive.
>
> It rounds to nearest, ties to even. A finite input whose value is too large for a Float gives `Err(ConversionError)`; it does not give Infinity. All other text gives `Err(ConversionError)`, including `inf`, `nan`, `.5` and `1.`.
>
> ```blink
> "1.5e-5".parse_float()     // Ok(0.000015)
> "1E20".parse_float()       // Ok(100000000000000000000.0)
> "Infinity".parse_float()   // Ok(Float.INF)
> "inf".parse_float()        // Err(ConversionError)
> " 1.0".parse_float()       // Err(ConversionError)
> "1e999".parse_float()      // Err(ConversionError)
> ```
>
> **Tradeoffs:** Accepting `e`/`E` and an optional `+` lets Blink read Float text from JSON, Python, Go and C output without any work. A strict set of specials avoids the current bug, where `"inf"` and `"nan"` silently give 0. A permissive set would also be hard to make identical across implementations. Overflow gives an error because a config value of `1e999` is almost always a mistake, and silently turning it into Infinity hides that.
>
> ---
>
> ### Notes for implementers (not spec text)
>
> - File separate chores for each place that uses `%g`: the power-assert intro, the printf table in `layout.bl`, and `duration_ms` in the test runner's JSON. `duration_ms` has to stay valid JSON.
> - JSON output of a NaN or an Infinity cannot use this text, because JSON has no such values. §3.6.2 has to say what happens there (an error or `null`). That needs its own ticket.
> - Float literals with an exponent (`1e20`) are a lexer and spec gap. Display does not depend on it, but it would make the examples in this proposal shorter. File it as type:spec.
>
> **My preferred vote:** Proposal 1 and Proposal 2 together. The round-trip law in rule 5 means nothing if we do not say what `parse_float` accepts.

**AI/ML:**

> # Float Display: AI/ML Seat, Phase A Proposal
>
> ## Proposal 1 (primary): one fixed format, shortest digits, always a Float-looking token
>
> **Spec rule (§3.6, new "Float Display Form"; `debug()` equals `display()` as today):**
>
> 1. **NaN.** Every NaN renders `nan`. The output never shows a sign or a payload. All NaNs are `==`, so a single form keeps the Debug/Eq law.
> 2. **Infinities.** `inf` and `-inf`.
> 3. **Zero.** `0.0` and `-0.0`.
> 4. **Digits for finite non-zero x.** Take the decimal digit string d₁…dₖ and exponent e (value = 0.d₁…dₖ × 10^e) with the fewest digits k such that correctly-rounded parsing (round-half-even) gives back exactly x.
>    - If more than one k-digit string does this, pick the one nearest the exact value of x.
>    - If two are equally near, pick the one with an even last digit.
>    - This is the Steele-White/Ryu/Schubfach output, so any correct implementation gives the same bytes.
> 5. **Layout.** Let n = e − 1 (the scientific exponent).
>    - **Positional when −7 ≤ n < 21.** Write the digits with the decimal point placed by e. Pad with zeros as needed. There is always at least one digit on each side of the point: `1.0`, `100.0`, `0.1`, `0.000001`.
>    - **Exponent form otherwise.** Write d₁ `.` d₂…dₖ (or d₁`.0` when k = 1), then `e`, then the exponent: `-` only when negative, never `+`, no leading zeros. Examples: `1.0e21`, `1.5e-8`, `1.7976931348623157e308`, `5.0e-324`.
> 6. **Sign.** A leading `-` appears iff the sign bit is set and the value is not NaN.
> 7. **Round-trip law.** For every Float x, `x.display().parse_float()` is `Ok(y)` and:
>    - if x is NaN, y is NaN;
>    - otherwise y has the same bits as x.
>
>    `parse_float` must accept every string this rule produces. The rest of its grammar is a separate ticket.
> 8. **F32.** Same rule with F32 precision in step 4, so `0.1` as F32 renders `0.1`.
> 9. **§3.6.1 exception.** Replace "may render differently" with "render differently: `0.0` and `-0.0`". Keep the exception, but make it exact.
> 10. **Follow-on ticket.** Add the exponent literal form (`1.0e21`, `1.5e-8`) to the lexer and spec. Every Float's debug text is then a valid Blink literal (with `nan`/`inf` as the only non-literals). §3.6.1 already says Debug output should be "re-readable … in its own source-literal syntax".
>
> **Example:**
> ```blink
> fn main() {
>     io.println(0.1.display())               // 0.1
>     io.println((0.1 + 0.2).display())       // 0.30000000000000004
>     io.println(1.0.display())               // 1.0
>     io.println(100.0.display())             // 100.0
>     io.println((1.0 / 3.0).display())       // 0.3333333333333333
>     io.println(123456789.0.display())       // 123456789.0
>     io.println(9007199254740993.0.display()) // 9007199254740992.0
>     io.println(0.000001.display())          // 0.000001
>     io.println((0.000001 / 10.0).display()) // 1.0e-7
>     io.println((-0.0).display())            // -0.0
>     io.println((0.0 / 0.0).display())       // nan
>     io.println((1.0 / 0.0).display())       // inf
>     io.println(Float.INF.debug())           // inf
>     let xs = [1.0, 2.5]
>     io.println(xs.debug())                  // [1.0, 2.5]
>     assert((0.1 + 0.2).display().parse_float() == Ok(0.1 + 0.2))
> }
> ```
>
> **Tradeoffs from my seat:**
> - **Always `1.0`, never `1`.** This is my strongest point. Debug equals Display for Float, so if Display drops the `.0`, then `[1.0, 2.0].debug()` gives `[1, 2]`, which reads as `List[Int]`.
>   - Power-assert output would then lie about the type.
>   - An LLM reading test failures or logs would infer the wrong type.
>   - Rust gets around this by splitting Display (`1`) from Debug (`1.0`). Blink has already merged them, so the merged form must carry the type.
>   - JSON agrees: `json.parse` treats `20.0` as Float and `20` as Int, so an encoder writing `1.0` keeps the type across a round trip.
> - **Fewer decision points.** There is one layout rule with two fixed thresholds, and no locale, precision or mode argument. An LLM can predict the output of any literal it wrote. The only case it must compute is a value derived by arithmetic, and shortest-digit output is what Python and JS already print there. Those are the two largest float corpora in training data, so `0.30000000000000004` is a string models already expect.
> - **Threshold 21 (JavaScript's).** Every Float that holds an integer in Int's range prints positionally. Python's 1e16 cutoff would print `9007199254740992.0` as `9.007199254740992e+15` at the exact point where Int/Float conversion bugs show up.
> - **Low end −7** (JS uses −7 too). It keeps common small values like `0.000001` readable.
> - **Lowercase `nan`/`inf`.** This matches C, Python, `%g` (so today's `inf` output stays the same) and most training text. Rust's `NaN` is the outlier.
> - **The `-0.0` choice.** Hiding the sign would remove the §3.6.1 exception, but it would break bit round-trip. It would also hide the very fact a failing `assert(1.0 / x < 0.0)` needs to show. Python prints `-0.0`, so models expect it. The cost, a Map Debug edge case, is small and now stated exactly.
> - **Cost.** The implementation needs a shortest-digit routine; `%.17g` is not enough. Ryu and Schubfach are small, public-domain, C-ready code.
>
> **Cross-language:**
> - Python repr matches this rule except for its `1e+16` threshold and `+` exponent sign.
> - JavaScript matches the thresholds and digits, but prints `1` and `Infinity`.
> - Rust Debug matches `1.0`, but never uses an exponent and prints `NaN`.
> - Go `'g', -1` and Java's `Double.toString` use the same digits with different layout.
>
> ## Proposal 2 (fallback if the panel wants no `-0.0` exception)
>
> The rule is the same, except −0.0 renders `0.0`. §3.6.1 then drops its Float exception, and the round-trip law becomes "y == x" (Float Eq) instead of bit-identical. I rank this second: it makes the Eq law simpler, but it hides a fact that tests and logs need.
>
> ## What I would reject
>
> - Keeping `%g`: it is lossy, so the ticket's MVCE fails.
> - Rust-style "never exponent": `1e300` would print 301 characters, which wastes tokens and reads badly.
> - Any per-call precision argument on `display()`: that belongs in a separate formatting API, not a decision point on the default.

**Minimalism:**

> **MINIMALISM (Min): Phase A proposal**
>
> My test: the fewest rules that two implementers can follow to the same bytes, and that delete spec text where they can. The ticket needs one property, round-trip. My proposal makes that property the rule and keeps the format rules few.
>
> ---
>
> ### Proposal M1: one form, round-trip under Blink `==`, no exponent, and the -0.0 exception removed
>
> **Spec text (§3.6, built-in Display impls, Float):**
>
> > `Float.display()` returns the text below. `Float.debug()` returns the same text (§3.6.1).
> >
> > 1. **NaN** renders as `NaN`. Every NaN renders the same way: sign and payload are not shown.
> > 2. **Infinity** renders as `inf` and `-inf`.
> > 3. **Zero** renders as `0.0`, and `-0.0` also renders as `0.0`.
> > 4. **Any other finite x:** choose the decimal value D = m × 10^k (m a positive integer) with the **fewest significant digits** that parses back to exactly x under round-to-nearest-even. If two such values have that digit count, take the one nearest to x's exact value. If they are still tied, take the one whose last digit is even. Write D in plain positional notation:
> >    - `-` if x < 0
> >    - the integer part, with no leading zeros (`0` when |D| < 1)
> >    - `.`
> >    - the fraction part, with no trailing zeros, or `0` when D is an integer
> >
> >    The text never uses an exponent. It contains only ASCII `-`, `0`–`9` and `.`.
> >
> > **Round-trip law.** For every `Float` x, `x.display().parse_float() == Ok(x)`, using Blink `==` (*Float Total Ordering*). `Str.parse_float` must accept every string this rule produces, including `NaN`, `inf` and `-inf`.
>
> **§3.6.1 edit:** delete the paragraph "`Float` is the one built-in exception… may render differently…". With rule 3, Float obeys the Debug/Eq law like every other built-in type, and the law then has no exceptions.
>
> **Example**
>
> ```blink
> fn main() {
>     io.println(0.1.display())            // 0.1
>     io.println((0.1 + 0.2).display())    // 0.30000000000000004
>     io.println(1.0.display())            // 1.0
>     io.println(100.0.display())          // 100.0
>     io.println((1.0 / 3.0).display())    // 0.3333333333333333
>     io.println(123456789.0.display())    // 123456789.0
>     io.println(9007199254740993.0.display()) // 9007199254740992.0
>     io.println(100000000000000000000.0.display()) // 100000000000000000000.0
>     io.println(0.0000001.display())      // 0.0000001
>     io.println((0.0 - 0.0).display())    // 0.0
>     io.println((-0.0).display())         // 0.0
>     io.println((0.0 / 0.0).display())    // NaN
>     io.println((1.0 / 0.0).display())    // inf
>     io.println((-1.0 / 0.0).display())   // -inf
>     let xs = [1.0, 2.5]
>     io.println(xs.debug())               // [1.0, 2.5]
>     assert((0.1 + 0.2).display().parse_float() == Ok(0.1 + 0.2))
> }
> ```
>
> **Why each choice is the smallest one**
>
> - **Shortest round-trip digits.** This is not optional. `%g` loses data today (`0.1+0.2` prints `0.3`). Defining the output as "the shortest digits that round-trip, nearest, then even" fixes one byte string per value. Ryu, Dragonbox and Schubfach all produce it, so we do not name an algorithm.
> - **No exponent.** Every exponent rule brings a threshold (JS uses 1e21 and 1e-6, Python 1e16 and 1e-4), and the panel would have to vote on the numbers and on the format (`e+20`, `e20` or `E20`). Plain notation needs no threshold. The output is then always a valid Blink float literal, because the lexer has no exponent form, and always a valid JSON number. The cost is length at the extremes: the worst case is about 327 bytes (`5e-324`, and `f64::MAX` takes 311). That length is bounded and the values are rare. Rust Display makes the same choice.
> - **Always `.0`.** Debug already equals Display for scalars, and that is decided. So a single form must serve both users and debugging. `[1.0, 2.5]` must not read as `[1, 2.5]`, and a power-assert line must show that a Float is a Float. Python `repr` does this.
> - **`-0.0` → `0.0`, one NaN form.** Blink already says that no Float equality tells `-0
> `-0.0` from `0.0`, and that `NaN == NaN`. If Display shows a difference that `==` does not, we need the exception paragraph in §3.6.1. Rendering by `==` deletes that paragraph, and the round-trip law then holds exactly under Blink `==`. A user who needs the sign of zero already has the documented idiom `1.0 / x < 0.0`. Display is not where a type should expose bits that its own `Eq` hides.
> - `NaN` / `inf` / `-inf`: we have to choose a spelling. These match Rust, and `inf` matches C and Python. I do not care much about the casing, provided we pick one spelling and `parse_float` accepts it.
>
> WHAT I WOULD NOT ADD (YAGNI)
> - No format options in this ticket (precision, `{x:.2}`, scientific). Format specs are a separate feature. Users who need fixed decimals today have `Decimal`.
> - No F32 rule. The built-in Display list is closed (Str, Int, Float, Bool, Char), so F32 has no Display impl, and templates widen it to Float. If F32 gains Display later, the same rule applies with "parses back to the F32". We do not need to write that now.
> - No full `parse_float` grammar here. Whether it accepts `1e5`, `+1` or `.5` is a real gap, but it is a different ticket. This ticket requires only that `parse_float` accepts everything `display` produces. File the input grammar on its own so that we do not vote on it under this one.
> - No exception text for -0.0 in Map Debug. Rule 3 makes it unnecessary.
>
> TRADEOFFS (honest)
> - Losing -0.0 in printed output hurts some numeric debugging, for example a sign-of-zero bug in a branch cut. I accept that, because Blink already gave up telling the two zeros apart through `==`. Keeping the difference visible only in Display would bring back the inconsistency we voted to remove.
> - No exponent means 1e300 prints as 301 digits plus ".0". Scientific users will see this. A future format spec can add `{x:e}`. The default does not need it.
> - Fixed ".0" means `"{price}"` with price = 5.0 prints `5.0`, not `5`. Web users who expect JS behavior may object. My answer: Float is not money, and a user who wants `5` should format on purpose.
>
> CROSS-LANGUAGE
> | Choice | Python repr | JS | Rust Display | Rust Debug | M1 |
> | shortest round-trip | yes | yes | yes | yes | yes |
> | 1.0 | 1.0 | 1 | 1 | 1.0 | 1.0 |
> | exponent | >=1e16 | >=1e21 | never | large/small | never |
> | -0.0 | -0.0 | 0 | -0 | -0.0 | 0.0 |
> JS also prints -0 as 0, so M1 is not alone in dropping the sign. M1 is close to Python repr, without the exponent and without the signed zero. In total it is four numbered rules and one law, and it deletes one paragraph from §3.6.1.

#### Phase B — Debate (round 1)

All six seats reported stable after one round. 8c (an exact, closed `parse_float` grammar) lost its only backer when DevOps withdrew it.

**Systems:**

> SYS Phase B round 1. I change my position on Q2, Q7 and Q10. I keep 1a, 3a, 4a, 5a, 8a and 9b.
>
> **Missed point (add to C-common):** the output never depends on locale, and neither does `parse_float`. Today `%g` and `strtod` both read LC_NUMERIC, and one `setlocale` call through FFI turns the output into `1,5`. Nobody opposed this, so I propose it as common text, not as an option.
>
> **Q1, keep 1a (`-0.0`).** PLT's L2 is the strongest argument against me, and inside Blink it holds. But Display text leaves Blink: it goes into JSON, CSV and logs, which Python, numpy and Postgres then read, and those readers DO tell −0.0 from 0.0 (`atan2`, `copysign`, `1/x`). Under 1b, Blink silently changes a value on its way out to every other consumer. "No Blink `==` tells them apart" is true and does not matter there. 1b also leaves no way to print the sign at all: Display is the only scalar→Str path, and no `to_bits` exists. The §3.6.1 cost is small and now exact. `assert_eq` prints debug text only when the values are not `==`, and Float cannot be a Map key. If 1b wins, I ask that the same vote file a ticket for a bit-exact path (`to_bits`, or a lossless encoder flag).
>
> **Q2, CHANGE 2a → 2b (Python, −4 ≤ k < 16).** Web and PLT convinced me. At k ≥ 16, a positional form writes trailing zeros that are padding, not digits. `1e23` would print as `100000000000000000000000.0`, but the stored value is 99999999999999991611392. The text claims an exactness the value does not have. AI/ML's point about Int-range values is about values above 2^53, which are already inexact as Floats. The systems cost is the same either way: output is at most 24–25 bytes, in a fixed buffer.
> Reconcile note, in case 2a survives: the correct ECMA cut-off is positional for −6 ≤ k ≤ 20. AI/ML's text "−7 ≤ n < 21" contradicts its own `1.0e-7` example.
> Against 2c (never use an exponent): output length has no useful limit (about 327 bytes for `5e-324`), a fixed buffer no longer works, and 300 digits are useless in a log.
>
> **Q3, keep 3a (`1.0e16`).** With this, every finite output contains `.`, and a one-byte scan tells a Float token from an Int. It is also inside PLT's literal grammar if Q9 goes that way later. `1e16` saves 2 bytes and loses both properties.
>
> **Q4 4a (`NaN`), Q5 5a (`inf`).** DevOps' grep problem has a fix: `rg -w inf`. `inf` matches `Float.INF` and what we print today.
>
> **Q6:** follows from Q1. With 1a, the law is Blink `==`, plus the same bits for every non-NaN value, which is 6b in effect. With 1b, it is plain 6a.
>
> **Q7, CHANGE → drop it from this ticket and file a separate one.** Min is right: the built-in Display list is closed and F32 is not on it, so a "same rule at binary32" text describes an impl that does not exist. The real systems problem is that a template widens F32 to Float, so `"{f}"` with `f = F32.from(0.1)` prints `0.10000000149011612`. That needs its own decision (add F32 to the list, or do not widen for display), so it should not ride along here.
>
> **Q8, keep 8a.** 8c bundles real input-policy choices, such as overflow giving `Err` vs `inf` and case of the specials, into a display ticket. Those choices deserve their own vote. `parse_float` must accept every display output and round correctly, and that is all the round-trip law needs.
>
> **Q9, 9b.** This is a lexer change with its own grammar questions (`1e5` with no `.`? `E`?). 3a keeps the door open.
>
> **Q10, CHANGE → 10a, narrowed.** I now accept spec text, because two Float texts in one toolchain will diverge. Proposed text: "Every place the language renders a finite Float as text (Display, Debug, interpolation, power-assert, and JSON number output) uses this form." Leave non-finite JSON output to DevOps' separate ticket, and leave test-runner timing out, because that is tool output and not language.
>
> STABLE: ready to vote

**Web/Scripting:**

> WEB, Phase B round 1. Changes: Q3 to 3a, Q8 to 8a, Q7 reworded.
>
> Q1 -0.0: HOLD 1b (0.0).
> - vs sys "serializers lose bits": Display is not a serializer. Bit-exact checkpoints need `to_bits`, not text. JS ships `String(-0) == "0"`, and nobody uses JS number text for bit-exact storage.
> - vs aiml "hides the fact a failing assert(1.0 / x < 0.0) needs": power-assert prints the sub-expression `1.0 / x` as `-inf`, which shows the sign. The idiom works in exactly the case aiml names.
> - vs "Python prints -0.0": the most-asked version of that Python question is "why does my rounded total print -0.0?" That is the 90% user, and they lose. With 1b, Blink text agrees with Blink `==` everywhere, and §3.6.1 loses its only exception.
>
> Q2 cut-offs: HOLD 2b (Python, -4 <= k < 16). 2a is my second choice.
> - aiml's argument is factually wrong. 2^53 = 9007199254740992 has k = 15, so 2b prints it positionally as `9007199254740992.0`. Every exactly representable consecutive integer prints in full.
> - Above 1e16, positional text like `100000000000000000000.0` (2a) suggests 21 exact digits. Most of them are invented zeros.
> - vs 2c (min): `5e-324` as about 327 characters of `0.000…` is worse UX than an exponent. It also has the unbounded-feel problem sys raised.
>
> Q3 mantissa: CHANGE to 3a (`1.0e16`, `5.0e-324`). PLT's L4 persuades me: "every finite Float text contains a `.`" is one rule a user learns in 5 seconds, and it extends the `.0` rule already agreed in C2. It also keeps the door open for the literal grammar in Q9. It costs two characters on rare values.
>
> Q4: HOLD 4a `NaN`. Every audience recognises it (JS, Rust, Java, pandas output, and Python devs see it in pandas). Lower-case `nan` only matches Python's repr.
>
> Q5: HOLD 5a `inf`/`-inf`.
> - vs devops's grep argument: `rg -w inf` solves it. `Infinity` is 8 characters, and it spells differently from the prelude's `Float.INF`.
> - C, Python, Rust and today's runtime all print `inf`, so 5a changes nothing users already see.
>
> Q6: 6a (Blink `==`). This follows from Q1. If Q1 goes 1a, I accept sys's wording: `==`, plus the bits stay the same for finite values.
>
> Q7 F32: 7a, reworded to meet min's objection: "WHENEVER an F32 renders as text, it uses the same rule with binary32 shortest digits." This adds no Display impl to the closed list. Separately, file a ticket on F32 interpolation. If `"{f}"` widens to Float, then F32 0.1 prints `0.10000000149011612`, and that will be a Stack Overflow question.
>
> Q8 parse_float grammar: CHANGE to 8a. The law plus "accepts every Display output and rounds correctly" can be tested and is enough for this ticket. The full input grammar deserves its own vote, with devops's 8c as the starting draft. Against 8c inside this ticket: it rejects `inf`. If Q5 picks `inf`, 8c breaks the round-trip law, which shows the two questions are coupled and should not be voted blind here.
>
> Q9 literal exponent: HOLD 9b (separate ticket). It changes the lexer, so it needs its own decision. If Q3 passes as 3a, PLT's `DIGITS '.' DIGITS ('e' '-'? DIGITS)?` becomes the obvious draft for that ticket. File it now, as type:spec.
>
> Q10: HOLD 10a, as one sentence: "Every place the language or toolchain renders a finite Float as text uses this form." Power-assert lines and test-runner output are user-visible, so they are spec, not a chore. If they stay unspecified, an implementation can keep `%g` there and pass the spec.
> - vs sys: no extra wording is needed. JSON NaN/inf remains devops's separate ticket.
>
> Points the dedupe missed:
> - ADD sys's locale rule as common text: "the output never depends on locale; the decimal mark is always `.`". This is a real bug today (setlocale gives `1,5`). I support it as normative.
> - File follow-up tickets: parse_float grammar (Q8), exponent literal (Q9), F32 interpolation (Q7), and JSON encode of NaN/inf.
>
> STABLE: ready to vote

**PLT:**

> PLT, round 1. Positions on Q1 to Q10:
>
> Q1 (-0.0): HOLD 1b, which renders it as "0.0" and deletes the §3.6.1 exception. My argument is consistency.
> - 1a already accepts that text hides bits `==` hides: no proposal shows the NaN sign or payload. -0.0 is the same case, a bit pattern that Blink `==` merges into one class. 1a draws the line in two places for one reason.
> - sys and aiml argue that Display is the only path from a Float to Str. True, but Display is the user-facing text of a value as `==` defines it. It is not a serialization of bits. Bit-exact output (checkpoint files, golden tests) needs a separate, explicit API such as `to_bits` or a hex form. File that as its own ticket. Do not load it onto Display.
> - With 1b, round-trip (L1) and "equal values give equal text" (L2) hold with no exception. Since L1 holds and parsing is a function, L2's converse also holds: different classes give different text.
>
> Q2 (exponent cut-offs): HOLD 2b (Python), but this is not a soundness question and 2a is acceptable. aiml's point that every Int-range Float stays positional under 2a is fair. My counter: above 2^53, positional digits suggest a precision the value does not have. I reject 2c because its output length has no small bound (about 327 bytes). Its one benefit, every output being a literal, is better got through Q9. If 2a wins, the panel must fix the lower bound exactly; sys and aiml are one apart.
>
> Q3: HOLD 3a ("1.0e16"). Then L4 is one rule with no exceptions: every finite output contains ".". The mantissa also stays in the same DIGITS "." DIGITS form as any other literal, so a future exponent literal needs only one new suffix. JSON is not affected either way: "1e16" parses as Float because it has an exponent.
>
> Q4: "NaN". Q5: "inf"/"-inf". This matches the prelude's `Float.INF`. The grep problem with "inf" is real but small next to keeping to the existing name. I reject devops's "Infinity".
>
> Q6: 6a follows from Q1. Under 1b, bit equality is the wrong law, because it would make Display respect something that `Eq` does not.
>
> Q7: CHANGE to a split. min is right on the letter of the spec: the built-in Display list is closed, so this ticket cannot give F32 an impl. Proposed wording: "If F32 text exists (Display, Debug of an F32 field), the digits are the shortest that round-trip at binary32 precision, with the same layout." Whether F32 gets Display at all goes to a separate ticket. Note that derived Debug on a struct with an F32 field already needs F32 text, so that ticket is not hypothetical.
>
> Q8: CHANGE to 8a, with 8b as an informative note. L1 already obliges `parse_float` to accept every output and to round correctly, and that is all this ticket needs. I reject 8c here because it settles real open questions under the wrong ticket: overflow giving Err vs inf, "Infinity" vs "inf", leading "+". Those belong in the separate parse_float grammar ticket, which should test them against JSON's grammar.
>
> Q9: CHANGE to 9b, a separate ticket. A literal-grammar change is a language change in its own right and deserves its own vote. Condition: the spec text records that the exponent form ("1.0e16", "5.0e-324") was chosen to fit DIGITS "." DIGITS "e" "-"? DIGITS, so the follow-up ticket inherits that shape.
>
> Q10: 10a, scoped narrowly. Every toolchain place that shows a Float to a user (interpolation, Debug, power-assert, test-runner human output) uses this form. Exclude JSON encoding: NaN and inf have no JSON text, which devops already flagged as its own ticket. "Same value, same text everywhere" is a user-visible property, so it belongs in the spec and not only in an implementation chore.
>
> Points the dedupe missed:
> (a) Adopt sys's locale rule as normative: the decimal mark is always ".", and neither display nor parse_float depends on locale.
> (b) Write L2 as a law in §3.6: `x == y` exactly when `x.display() == y.display()`. That one sentence is what lets us delete the §3.6.1 paragraph, and it is a property implementers can test.
> (c) If 1a wins, L2 fails, and the §3.6.1 text must say exactly which pairs differ: only ±0. "May" is not acceptable.
>
> STABLE: ready to vote

**DevOps:**

> DEVOPS Phase B round 1: I keep 1b, 2b and 10a, and I change Q3 to 3a, Q5 to 5a and Q8 to 8b.
>
> Q1, 1b (`0.0`), no change. Against sys's point that assert_eq prints debug only when a != b: golden and snapshot tests compare debug TEXT, not `==`. Under 1a, a snapshot of a Map or struct flips when a refactor makes -0.0 instead of 0.0, and the values stay `==`. CI flakes over a difference the language says is not there. On bit-exact checkpoint files: Display is not a serialization format. Exact bits need a `to_bits` API, which is a separate ticket, the same as PLT says. Sys and aiml also say a failing `1.0 / x < 0.0` "needs to see the sign". That test already prints its own Bool, and power-assert shows `1.0 / x` as `-inf`, so the sign is still visible.
>
> Q2, 2b (Python cut-offs), no change. aiml's main argument for 21 is wrong on the facts. 2^53 = 9007199254740992 has k = 15, so 2b prints it positionally as `9007199254740992.0`. Python repr also prints `9007199254740992.0`, not `9.007199254740992e+15`. Every integer that a Float holds exactly prints positionally under 2b. Past 1e16, positional digits look exact when they are not. Against 2c: outputs up to ~327 bytes break log line limits, column alignment and fixed-size buffers. The "always a valid literal" gain goes away once exponent literals exist.
>
> Q3, I change to 3a (`1.0e16`). It gives every finite output a `.`, the same as PLT's L4. Tools and LLMs can then tell a Float token from an Int token with one simple test (has `.` → Float), with no need to check for `e`. JSON and all the major parsers accept both forms, so 3a costs nothing. I take 3a whatever happens with Q9.
>
> Q4, 4a (`NaN`).
>
> Q5, I give up `Infinity` and take 5a (`inf`). `rg -w inf` handles my grep concern, and `inf` matches the `Float.INF` prelude name. The gate is that `parse_float` accepts it.
>
> Q6, 6a (Blink `==`). It follows from 1b.
>
> Q7, 7a, but worded as "whenever F32 renders as text". Min is right that the closed Display list has no F32. So this decision must not quietly add a Display impl. It fixes only the digits for any place F32 text appears (Debug, power-assert, a later Display). Whether F32 gets Display is a separate question.
>
> Q8, I change to 8b. My closed grammar (8c) is the right end state, but leading `+`, overflow → Err, and case belong in their own ticket, as min says. What this ticket must fix is the minimum: PLT's `-? DIGITS ('.' DIGITS)? ([eE] [-+]? DIGITS)?` plus the Q4 and Q5 specials, with correct rounding. Web's minimum leaves out `E` and `e+`, and that would reject JSON and Python output we have to read. 8a is too weak, because "accepts display output" alone lets a parser reject `1E5` from a JSON file.
>
> Q9, 9b (separate ticket). A lexer change also touches fmt, the LSP tokenizer and syntax highlighting. It needs its own ticket and its own test surface. Q3 no longer depends on it.
>
> Q10, 10a, as one sentence: "Every place this spec renders a Float as text uses this form." Power-assert and Debug are covered already. The sentence is there so that machine-readable outputs (the test-runner JSON `duration_ms`, any future `--json` diagnostics) cannot go back to `%g`. Tools read those outputs, so that is a contract, not a chore. The work itself stays a chore.
>
> Points the dedupe missed:
> - (a) Add sys's "never depends on locale" as spec text. `setlocale` through FFI turns output into `1,5` and breaks every log parser. That makes it a contract.
> - (b) JSON encoding of NaN and inf. Display can now produce them, and JSON cannot hold them. §3.6.2 must say what happens (Err or null). I suggest a follow-up ticket, not a vote here.
>
> STABLE: ready to vote

**AI/ML:**

> AI/ML Phase B round 1: I change Q1, Q4 and Q6, change Q2 to Python cut-offs, and correct my lower-bound text.
>
> Q1 — CHANGE to 1b (`-0.0` renders `0.0`, delete the §3.6.1 exception). PLT's L2 settles it for me: "equal values print equal text" is one rule an AI learns once, and it removes an exception paragraph. My Phase A argument for keeping the sign was that a failing `assert(1.0 / x < 0.0)` needs it. That argument fails on a closer look: power-assert also shows `1.0 / x`, which prints `-inf` or `inf`, so the sign is still visible where it matters. Bit-exact serialization needs a bits API (`to_bits`), not Display. I would file that as a separate ticket rather than make Display carry it.
>
> Q2 — CHANGE to 2b (Python: positional for −4 ≤ k < 16).
> - Erratum: my Phase A bound "−7 ≤ n" was off by one against my own example; JS is −6 ≤ n < 21, as sys wrote. That no longer matters, since I now choose 2b.
> - Python `repr` is the most common Float text in training data. With 2b, a model predicts Blink output from Python output by one learned difference (no `+` in the exponent). JS's 21 is a second model to learn.
> - I accept web's point: `100000000000000000000.0` suggests digits that are not exact.
> - Against 2c (never exponent): models (and people) miscount long zero runs. `0.0000000000001` vs `0.00000000000001` is a token-level hazard. `5e-324` as 327 bytes costs about 100 tokens in every log or diff that holds it. The exponent form is the one an AI reads and writes correctly.
>
> Q3 — STAY 3a (`1.0e16`). The spec can then say "every finite output contains `.`" (PLT's L4) with no exception. "Has `.` except in a one-digit exponent form" is an extra decision point. It also keeps the mantissa inside the literal grammar if Q9 lands. The cost is two bytes.
>
> Q4 — CHANGE to 4a (`NaN`). Five seats want it, and `NaN` with `inf` is Rust's exact pair, so it is a known combination, not a mix. I do not care about the case, only that there is one spelling.
>
> Q5 — STAY 5a (`inf`/`-inf`). It matches `Float.INF`, Python, Rust and C. Devops's grep concern has a one-flag fix (`rg -w inf`). `Infinity` is 8 characters where 3 do the job, and JSON accepts neither, so it gains nothing for JSON.
>
> Q6 — CHANGE to 6a (Blink `==`). This follows from Q1.
>
> Q7 — STAY 7a, and I raise a point the dedupe missed. Min is right that F32 has no built-in Display and that templates widen F32 to Float. So `"{f}"` for an F32 0.1 would print `0.10000000149011612`, which surprises every reader. A 7a rule that never applies does not help. I propose to split this out: a separate ticket for "how F32 renders in a template". Here, vote 7a only as the rule for when F32 renders directly.
>
> Q8 — STAY 8a. The ticket needs only "accepts every display output, rounds correctly". Devops and PLT already disagree on the parse grammar (`inf` vs `Infinity`, `+`, overflow → Err), which shows it needs its own vote. Mixing it in here adds decision points to this ballot.
>
> Q9 — 9b (separate ticket), and I ask that the panel file it now as type:spec. Models will write `1e-9` in Blink source on the first try because every other language accepts it, and today the lexer rejects it. With 3a, display output and that future literal agree.
>
> Q10 — 10a, one line of spec text: "Every place the language or toolchain renders a Float as text uses this form." This removes a decision point: a model never has to ask which formatter a given tool uses. The exception is NaN and infinity in JSON output, which devops correctly sends to its own ticket.
>
> Merge suggestion: Q6 is decided by Q1. Vote them as one question.
>
> STABLE: ready to vote

**Minimalism:**

> Min, Phase B round 1. Two changes: Q2 (2c to 2b) and Q3 (now 3a).
>
> Q1: 1b, `0.0`. Firm. sys says Display is the only route from a scalar to text, so dropping the sign loses bits. But Blink already decided that no Float equality tells the zeros apart, so bit-exact serialization is a separate need (a future `to_bits`, which PLT also names). Display should not quietly carry it. 1a keeps an exception in a law that otherwise has none. 1b deletes a paragraph and makes PLT's L2 (equal means same text) true. aiml says a failing `assert(1.0 / x < 0.0)` needs to show the sign. It does not: power-assert shows the sub-expression `1.0 / x` as `-inf`, and that tells the user the sign.
>
> Q2: CHANGED, 2c to 2b (Python cut-offs, positional for -4 <= k < 16). I give up "never exponent". The length argument was weak (sys calls it unbounded; the worst case is 327 bytes). The argument that moved me is web's: `1e23` would print as `100000000000000000000000.0`, while the exact binary value is 99999999999999991611392. Positional output above 2^53 implies an accuracy the value does not have. Of the two, 2b is better: every integer up to 2^53 (k = 15) is exact and prints positionally, and exponent form starts where integers stop being exact. aiml's claim is not correct: 9007199254740992.0 has k = 15, so 2b prints it positionally. The JS top limit of 21 keeps 19 to 21 digits of positional text that is not exact. For the low end I take -4 from the same source, so the rule has one origin and no mixed thresholds. This also settles the sys/aiml off-by-one, because the question goes away.
>
> Q3: now 3a (`1.0e16`, `5.0e-324`). This is the minimal rule: "every finite output has a `.` with at least one digit on each side." That one sentence covers both layouts (PLT L4), and it keeps the mantissa inside a `DIGITS '.' DIGITS` literal form if we add exponent literals later. With 3b we need two rules for where the `.` goes.
>
> Q4: 4a, `NaN`. Five seats agree. Lowercase `nan` gains nothing.
>
> Q5: 5a, `inf` / `-inf`. It matches the prelude name `Float.INF` and Python/Rust. devops's grep point is real but small. `Infinity` is not JSON either, so it gets no interop benefit.
>
> Q6: follows from Q1, so 6a (Blink `==`). I suggest the panel merge Q6 into Q1.
>
> Q7: 7b in scope, with a conditional sentence I now accept. A finding: §3.6 says the five built-in Display impls (Str, Int, Float, Bool, Char) form a closed list. §3.6.1 says the sized integers have `display()`. F32 is in neither list. Whether F32 has Display is an existing gap that this ticket does not own. I accept one conditional line: "If F32 has Display, it uses this rule with binary32 precision." I object to any text that gives F32 an impl as a side effect. File the closed-list and sized-type inconsistency as its own ticket.
>
> Q8: 8a. devops says the law "means nothing" without a grammar. That is wrong: the law needs only "accepts every display output and rounds correctly". 8c's choices (overflow gives Err, `inf` rejected, `+Infinity`) are a full parsing design, and none of them affect output bytes. A separate ticket can decide them on their own merits. 8b states a minimum and does no harm, but it decides half of 8c without the debate.
>
> Q9: 9b, separate ticket. Q3a keeps that ticket open at no cost.
>
> Q10: 10b. Power-assert already renders through Debug (decided), so it gets this form for free. Test-runner `duration_ms` is tool output, not language. How JSON encodes a Float (and NaN/inf) belongs to §3.6.2 as its own ticket, which devops also asks for. A spec sentence "everything uses this one form" would cover outputs we have not designed (JSON NaN).
>
> Missed point: sys's locale rule (the decimal mark is always `.`) should go into the spec text. It costs nothing and it is a real bug today.
>
> Package I would vote for: 1b + 2b + 3a + 4a + 5a + 6a + 7 (conditional line only) + 8a + 9b + 10b + locale sentence.
>
> STABLE: ready to vote

#### Phase C — Silent vote

Each seat voted alone on Q1–Q12 (Q6 merged into Q1).

**Systems:**

> SYS Phase C ballot: 1a, 2b, 3a, 4a, 5a, 7a (I change from 7c), 8a, 9b, 10a-lang, 11a, 12a.
>
> **Q1: 1a**
> - Reasoning: Display text leaves Blink. Under Q10 it is also how JSON writes numbers, and the Python, numpy and Postgres programs that read it tell −0.0 from 0.0 (`atan2`, `copysign`). With 1b, a value silently changes on its way out, and with no `to_bits` today, no Blink program can print the sign at all. The exception costs little: it is now one exact pair, Float cannot be a Map key, and `assert_eq` prints debug text only when the values are not `==`.
> - Concern: DevOps is right that snapshot tests compare debug text. Under 1a, a refactor that yields −0.0 instead of 0.0 changes a golden file while the values stay `==`.
>
> **Q2: 2b**
> - Reasoning: at k ≥ 16, positional output writes padding zeros that look like exact digits (`1e23` prints as `100000000000000000000000.0`, but the stored value is 99999999999999991611392). Every integer up to 2^53 still prints positionally. Output stays at 25 bytes or less, so a fixed buffer still works.
> - Concern: JS readers will see `1e16` where their own runtime prints `10000000000000000`.
>
> **Q3: 3a**
> - Reasoning: every finite output contains `.`, so one byte tells a Float token from an Int. The mantissa stays inside the `DIGITS '.' DIGITS` literal shape for the follow-up ticket. The cost is 2 bytes on rare values.
> - Concern: `1.0e16` matches no major language's exact output, so copy-paste diffs against Python or Rust text will not match byte for byte.
>
> **Q4: 4a**
> - Reasoning: Blink has one NaN under `==`, so it gets one spelling. `NaN` is the most widely known spelling, and it removes glibc's `-nan`.
> - Concern: Python and C users who grep for lowercase `nan` will miss it.
>
> **Q5: 5a**
> - Reasoning: it matches `Float.INF`, C, Python, Rust and what we print today. `strtod` accepts it.
> - Concern: a plain `rg inf` matches `info`. The fix (`rg -w`) is one flag, but it is a trap.
>
> **Q7: 7a (CHANGE from 7c)**
> - Reasoning: PLT's point moved me. Derived Debug of a struct with an F32 field already needs F32 text, so the digits must be fixed now. 7a adds no Display impl to the closed list. A binary32 shortest-digit routine (Ryu f2s) is small and cheap.
> - Concern: until the F32-template ticket lands, `"{f}"` still widens to Float and prints `0.10000000149011612`.
>
> **Q8: 8a**
> - Reasoning: the round-trip law needs only "accepts every display output and rounds correctly". Overflow giving Err vs inf, `+`, and the case of the specials are separate policy choices that deserve their own vote.
> - Concern: until that ticket lands, a conforming `parse_float` may reject `1E5` or `e+5` from JSON input.
>
> **Q9: 9b**
> - Reasoning: this is a lexer change with its own surface (fmt, LSP, highlighting, `1e5` with no `.`). 3a keeps the shape ready for it.
> - Concern: users will write `1e-9` in source and hit a lexer error until that ticket lands.
>
> **Q10: 10a-lang**
> - Reasoning: two Float formatters in one toolchain will diverge, so the spec must bind every language-level output, JSON numbers included. Test-runner timing is tool output, not language.
> - Concern: an unspecified tool output (a future `--json` diagnostic) could go back to `%g` without breaking the spec.
>
> **Q11: 11a**
> - Reasoning: today `%g` and `strtod` read LC_NUMERIC, so one `setlocale` call through FFI makes output `1,5` and breaks the round-trip law. A locale-free formatter is also faster and allocation-free.
> - Concern: users who want localized numbers have no tool for it until a formatting API exists.
>
> **Q12: 12a (applies only if 1b wins)**
> - Reasoning: if the panel drops the sign, it should say why in one law that implementers can test. Stated, L2 alone justifies deleting the §3.6.1 paragraph.
> - Concern: L2 binds Display to Eq for good, so any future Float Eq change also changes text output.

**Web/Scripting:**

> WEB, Phase C ballot.
>
> Q1 (with Q6): 1b
> Reasoning: The 90% user meets -0.0 as "why does my rounded total print -0.0?" They never meet it as a sign bit they wanted. JS prints `0`, and nobody asks about it. Under 1b, Blink text agrees with Blink `==`, and §3.6.1 loses its only exception, so there is one fewer thing to learn. The sign stays visible where it matters: power-assert shows `1.0 / x` as `-inf`.
> Concern: Users who send Display text to numpy or Postgres and need the sign bit get no lossless path until a `to_bits` ticket lands. I back sys's request to file it in the same decision.
>
> Q2: 2b
> Reasoning: Python repr is the Float text most users already read, and every integer up to 2^53 still prints in full. Past 1e16, positional text such as `100000000000000000000.0` shows zeros that look exact and are not. That causes confusion, and confusion becomes Stack Overflow questions.
> Concern: JS users will see `1.0e16` where JS prints `10000000000000000`. That is a small surprise.
>
> Q3: 3a
> Reasoning: "Every finite Float has a `.`" is one rule a user learns in seconds. It extends the agreed `1.0` rule and keeps the mantissa ready for a future literal grammar.
> Concern: It differs from Python, JS and Rust (`1e16` / `1e+16`), so a few users will think it is a typo.
>
> Q4: 4a
> Reasoning: `NaN` is the spelling every audience knows: JS, Rust, Java, and pandas output that Python users see daily.
> Concern: Python users who type `"nan".parse_float()` get an error, unless the parse ticket accepts it.
>
> Q5: 5a
> Reasoning: It matches `Float.INF`, Python, Rust, C and today's runtime output, so nothing users already see changes. `rg -w inf` solves the grep issue.
> Concern: JS users expect `Infinity`, and a hand-written JSON5 file that holds `Infinity` will not parse unless the parse ticket adds it.
>
> Q7: 7a
> Reasoning: Derived Debug of a struct with an F32 field already prints F32 text. Users must see `0.1` there, not `0.10000000149011612`. The "whenever it renders" wording adds no Display impl to the closed list.
> Concern: The template-widening case (`"{f}"`) still prints the long form until the separate F32 ticket lands, and that gap will produce questions.
>
> Q8: 8a
> Reasoning: "Accepts every display output, rounds correctly" is testable and enough for the round-trip law. The other input choices (`+`, `E`, overflow, `Infinity`) should get their own vote instead of riding along here.
> Concern: Until the parse ticket lands, an implementation may reject `1E5` from a JSON or Python source, which users will hit when they read data files.
>
> Q9: 9b
> Reasoning: A lexer change touches fmt, the LSP and highlighting, so it needs its own decision. File it now, because users will type `1e-9` on day one.
> Concern: Users who copy `1.0e16` from Display output into source get a lex error until that ticket lands.
>
> Q10: 10a-wide
> Reasoning: If power-assert and test-runner output can keep `%g`, then a test log shows `0.3` while Display shows `0.30000000000000004`. That is the exact confusion this ticket exists to kill. Everything a user sees should use one form. JSON NaN/inf goes to its own ticket.
> Concern: "toolchain" is broad, and an implementer may argue about whether a given tool output counts.
>
> Q11: 11a
> Reasoning: A `setlocale` call through FFI turning output into `1,5` is a real bug today, and no user would expect a library call to change how a number prints. One sentence closes it.
> Concern: None of substance. Users who want locale-aware formatting need a separate API later.
>
> Q12: 12a
> Reasoning: "Equal values print equal text, and different values print different text" is the plainest statement of what users already expect. It is also the sentence that justifies deleting the §3.6.1 paragraph. Implementers can test it directly.
> Concern: If 1a wins, this law is false and must not be written in.

**PLT:**

> PLT ballot, Phase C.
>
> Q1 (with Q6): 1b
> Reasoning: Blink's `Eq` puts -0.0 and 0.0 in one class, and all NaNs in one class. Text that splits a class makes Display a function on bit patterns, not on values, and that breaks the §3.6.1 Debug/Eq law. Every seat already accepts that text hides the NaN sign and payload. Treating ±0 the same way is the same principle applied once more, not a new one. Under 1b the round-trip law (L1) and the "equal values give equal text" law (L2) both hold with no exceptions. Bit-exact output belongs to a separate, explicit API (`to_bits`).
> Concern: until `to_bits` exists, a Blink program that writes text for a numpy or Postgres reader that does care about the sign of zero has no way to keep that sign. That is sys's point, and it is real.
>
> Q2: 2b
> Reasoning: The cut-off is a convention, not a law. 2b keeps every integer up to 2^53 positional, and those are exactly the integers a Float holds exactly. It switches to an exponent where positional digits would claim exactness the value does not have. Output length also has a small bound.
> Concern: values in Int range above 1e16, such as large IDs converted to Float, print in exponent form, and that will surprise some readers.
>
> Q3: 3a
> Reasoning: It makes L4 ("every finite output contains `.`") a law with no exceptions. A one-character test then tells a Float token from an Int token. The mantissa also stays in DIGITS '.' DIGITS form, so the future exponent-literal grammar needs only a suffix.
> Concern: `1.0e16` is not Python's `1e+16`, so a reader who knows Python must learn one more difference.
>
> Q4: 4a
> Reasoning: One spelling for the one NaN class. It matches the existing spec text and Rust, and casing has no soundness weight.
> Concern: Python users may type `nan` into parse_float. The separate parse-grammar ticket must decide whether to accept it.
>
> Q5: 5a
> Reasoning: It uses the same name as the prelude's `Float.INF`, so text and source spell the value the same way.
> Concern: a plain `inf` search in logs also matches words like `info`. `rg -w` fixes this, but not every user will know that.
>
> Q7: 7a
> Reasoning: F32 text already exists in practice: derived Debug of an F32 field needs it. The rule must say which binary format the "shortest round-trip" refers to, or that phrase is ambiguous. 7a fixes the digits without adding a Display impl to the closed list.
> Concern: a reader may take 7a to imply that F32 has Display, so the separate F32 ticket must answer that question promptly.
>
> Q8: 8a
> Reasoning: L1 already obliges parse_float to accept every display output and round correctly. That is all the law needs. Overflow behavior, `Infinity`, a leading `+` and case are real design choices, and they need their own vote.
> Concern: until that ticket lands, a parser that rejects `1E5` or `e+5` from JSON input still meets this spec.
>
> Q9: 9b
> Reasoning: A literal-grammar change touches the lexer, fmt and the LSP, and it deserves its own vote. Under 3a the display form already fits the obvious draft, `DIGITS '.' DIGITS ('e' '-'? DIGITS)?`.
> Concern: until it lands, Debug output in exponent form does not read back as Blink source.
>
> Q10: 10a-wide
> Reasoning: I move from my 10a-user to 10a-wide. My own composition argument (JSON classes Int vs Float by syntax) needs finite JSON number output to use this form, and 10a-wide covers that. Test-runner output is in it too. The one sound exception, NaN and inf in JSON, already goes to its own ticket. One value, one text is a property users can see, so it belongs in the spec.
> Concern: "every place" is broad, and a future tool with a real need for another format, such as fixed precision, will need a stated exception and not a quiet break.
>
> Q11: 11a
> Reasoning: A function from values to text cannot depend on hidden process state. If `setlocale` can change Display output, both L1 and L2 fail. That makes locale-independence a requirement for soundness, not a nicety.
> Concern: an implementation that uses libc `strtod`/`snprintf` must prove it does not read LC_NUMERIC. That is easy to get wrong in the parse direction.
>
> Q12: 12a
> Reasoning: L2 is the property that lets us delete the §3.6.1 exception. Implementers can test it directly, and with L1 it says text is a one-to-one map from Eq classes. A law that the deletion depends on, but that the spec never states, would be lost the next time someone edits the text.
> Concern: if Q1 goes to 1a, 12a must not be adopted in this form. It would be false for ±0.

**DevOps:**

> DEVOPS Phase C ballot: 1b, 2b, 3a, 4a, 5a, 7a, 8b, 9b, 10a-wide, 11a, 12a.
>
> Q1: 1b
> Reasoning: Snapshot and golden tests compare debug text. Under 1a, a snapshot flips when a refactor produces -0.0 where it produced 0.0, while the values stay `==`, and CI fails over a difference the language says does not exist. Bit-exact export is a job for a `to_bits` or lossless-encoder API, not Display. Sys's point that outside readers can tell the zeros apart is real, which is why that ticket should be filed in the same decision.
> Concern: Until `to_bits` exists, a Blink program that writes CSV or JSON for numpy or Postgres silently drops the sign of zero, and there is no way to keep it.
>
> Q2: 2b
> Reasoning: Every integer a Float holds exactly (up to 2^53, k = 15) prints in full, and the exponent form starts where digits stop being exact. Python repr is the Float text that most log readers and tools already parse. Output has a small fixed bound, which matters for log line limits and column alignment.
> Concern: Values from 1e16 to 1e21 that JS users expect as plain digits print as `1.0e16`. That can surprise people who compare Blink output with JS output.
>
> Q3: 3a
> Reasoning: "Every finite output contains `.`" gives log parsers, LLMs and lint tools a one-byte test for a Float token versus an Int token. JSON and every major parser accept `1.0e16`. It costs two bytes on rare values.
> Concern: A tool that strips a trailing `.0` to "normalize" numbers could produce `1e16` or a broken `1.e16`. That is a downstream risk only.
>
> Q4: 4a
> Reasoning: `NaN` is the spelling in JS, Rust, Java and pandas output, so most log tooling already matches it. It also has no false matches in a grep.
> Concern: Python-trained regexes that look for lowercase `nan` will miss it, so the regex must be case-insensitive.
>
> Q5: 5a
> Reasoning: It matches `Float.INF`, C, Python, Rust and today's output, so existing log greps keep working. My grep concern has a fix: `rg -w inf`.
> Concern: Naive substring greps for `inf` also match `info` and `config` lines.
>
> Q7: 7a
> Reasoning: Wherever F32 text appears (Debug of an F32 field, power-assert, a later Display), its digits must be fixed or two implementations will differ. The wording adds no Display impl. The separate F32 ticket handles template widening, where an F32 0.1 prints as `0.10000000149011612`.
> Concern: Readers may take "whenever F32 renders" as a promise that F32 has Display today. The spec text must point to the open ticket.
>
> Q8: 8b
> Reasoning: Display output alone does not cover what a tool must read. A parser that accepts only display output could reject `1E5` or `1e+5`, which come from JSON, Python and C output that Blink programs must ingest. The stated minimum costs nothing, decides none of the contested points (leading `+`, overflow, case), and leaves those to the parse ticket.
> Concern: If the parse ticket later wants a stricter grammar, this minimum blocks it, but only for forms that JSON itself uses.
>
> Q9: 9b
> Reasoning: A lexer change also touches fmt, the LSP tokenizer, syntax highlighting and error recovery. It needs its own ticket and test surface. 3a already keeps the `DIGITS '.' DIGITS 'e' '-'? DIGITS` shape open.
> Concern: Until that ticket lands, the output `1.0e16` is not valid source, so pasting Debug output back into code fails with a lexer error.
>
> Q10: 10a-wide
> Reasoning: Machine-readable outputs (the test-runner JSON `duration_ms`, any future `--json` diagnostics) are contracts that CI tools parse. If the spec says nothing, an implementation can keep `%g` there and still conform. One sentence stops two Float formatters from ever drifting apart in one toolchain. JSON NaN/inf stays with its own ticket.
> Concern: "Toolchain" is wider than the language spec usually governs, so the text must not read as constraining third-party tools.
>
> Q11: 11a
> Reasoning: One `setlocale` call through FFI turns output into `1,5` and breaks every log parser, CSV reader and JSON consumer. Any output a tool depends on must not depend on process state.
> Concern: Implementations can no longer call libc `strtod` or `snprintf` directly, so they need their own parse and format code. That is a real but bounded cost.
>
> Q12: 12a
> Reasoning: The law "equal values give equal text" is a property tools can test, and snapshot stability rests on it. Stating it once removes the §3.6.1 exception and gives implementers a fuzzable invariant.
> Concern: If Q1 goes 1a, this law is false and must not be stated. The ballot already ties it to 1b.

**AI/ML:**

> AI/ML Phase C ballot: 1b, 2b, 3a, 4a, 5a, 7a, 8a, 9b, 10a-wide, 11a, 12a.
>
> Q1 (with Q6): 1b
> Reasoning: "Equal values print equal text" is one rule a model learns once, and it deletes the only exception to the Debug/Eq law. That leaves one fewer decision point to read in §3.6.1. The sign stays visible where a test needs it, because power-assert shows `1.0 / x` as `-inf`. Bit-exact output belongs to a separate bits API, not Display.
> Concern: Display text that leaves Blink (CSV, JSON read by numpy or Postgres) loses the sign of zero until a `to_bits` path exists, so that ticket must be filed with this decision.
>
> Q2: 2b
> Reasoning: Python `repr` is the most common Float text in training data. With 2b, a model predicts Blink output from Python output with one small change (no `+` in the exponent). Every integer that a Float holds exactly (up to 2^53, k = 15) prints positionally, and exponent form starts where digits stop being exact. 2c would produce long zero runs that models and people miscount.
> Concern: JS developers will see `1e16` where they expect `10000000000000000`, which is a small mismatch for that audience.
>
> Q3: 3a
> Reasoning: "Every finite Float text contains a `.`" is a single rule with no exception. A model or tool tells a Float token from an Int token by that rule alone. It also fits a future `DIGITS '.' DIGITS 'e' ...` literal.
> Concern: Python and JS habits make models write `1e16` by reflex, so expected-output text in tests may be off by `.0` until the rule is learned.
>
> Q4: 4a
> Reasoning: `NaN` is what JS, Rust, Java and pandas print, so it is the spelling most often seen. With `inf` it is Rust's exact pair, which is a known combination. One spelling is what matters.
> Concern: Python-trained output predicts `nan`, so some generated expected strings will use the wrong case.
>
> Q5: 5a
> Reasoning: It matches the prelude name `Float.INF`, Python, Rust, C and what the runtime prints today. That is the least new text to learn. `Infinity` costs more tokens and gains nothing for JSON.
> Concern: Plain-text grep for `inf` also matches `info`; users must know `rg -w`.
>
> Q7: 7a
> Reasoning: One rule for every place F32 text appears (Debug of an F32 field, power-assert, any later Display) means a model never has to guess F32 digits. It does not add a Display impl to the closed list.
> Concern: Template widening still prints F32 0.1 as `0.10000000149011612` until the separate F32 ticket lands, and that is the case users hit first.
>
> Q8: 8a
> Reasoning: The round-trip law needs only "accepts every display output, rounds correctly". The rest of the parse grammar (case, `+`, overflow, `Infinity`) is a separate set of choices and deserves its own vote. Bundling it here adds decision points voted without debate.
> Concern: Until the grammar ticket lands, a conforming `parse_float` may reject `1E5` from JSON or Python output.
>
> Q9: 9b
> Reasoning: A lexer change touches fmt, the LSP and highlighting, so it needs its own decision. File it now as type:spec, because models will write `1e-9` in Blink source on the first try.
> Concern: If that ticket stalls, generated code keeps hitting a lex error on exponent literals.
>
> Q10: 10a-wide
> Reasoning: One sentence covering every place Blink or its tools render a Float means a model never has to ask which formatter a given output uses. One rule is easier to learn and to check than a scoped list. JSON NaN/inf stays in its own ticket.
> Concern: The wide wording could be read as covering JSON encoding of NaN/inf before that ticket decides it, so the spec text must exclude non-finite JSON explicitly.
>
> Q11: 11a
> Reasoning: Output that changes with a hidden libc state is not predictable from the spec alone. It costs one sentence and fixes a real bug today (`1,5` after an FFI `setlocale`).
> Concern: An implementer may still call `strtod` in `parse_float` and miss the locale leak, so tests must run with a non-`.` locale set.
>
> Q12: 12a
> Reasoning: A stated law is a testable property, and it is the reason the §3.6.1 paragraph can be deleted. A model reasoning about Debug text of containers can rely on it directly.
> Concern: If 1a wins, this law is false and must not be written.

**Minimalism:**

> Min, Phase C ballot.
>
> Q1: 1b
> Reasoning: Blink `==` already merges the two zeros, and every proposal already hides the NaN sign and payload, so 1b puts the line in one place for one reason. It deletes a paragraph from §3.6.1, and the Debug/Eq law then has no exceptions. Bit-exact output is a separate need (`to_bits`), and Display should not carry it implicitly.
> Concern: Blink text read by an outside consumer (numpy, Postgres) loses the sign of zero, so the bits-API ticket that sys asked for must be filed with this decision.
>
> Q2: 2b
> Reasoning: Exponent form starts at the point where the integers a Float holds stop being exact (k = 16, just above 2^53), so positional text never shows padded zeros as if they were digits. Both cut-offs come from one source (Python repr), so there is one origin and no mixed thresholds. I withdrew 2c: its output is bounded, but it shows a precision the value does not have.
> Concern: JS-trained users will see `1.0e16` where they expect `10000000000000000`.
>
> Q3: 3a
> Reasoning: One sentence ("every finite output has a `.` with a digit on each side") covers both layouts. 3b needs a second rule for where the `.` goes. It also keeps the mantissa in the `DIGITS '.' DIGITS` shape for a future exponent literal.
> Concern: Two extra bytes on rare values, and this output differs from Python's `1e+16`.
>
> Q4: 4a
> Reasoning: We need one spelling, and five seats already agree on this one. Choosing lowercase gains nothing.
> Concern: Python users who grep for `nan` will miss it.
>
> Q5: 5a
> Reasoning: It matches the existing prelude name `Float.INF`, so we add no new word. `Infinity` gets no JSON benefit, because JSON accepts neither spelling.
> Concern: A substring grep for `inf` matches `info`. `rg -w` fixes that.
>
> Q7: 7a (changed from 7b)
> Reasoning: PLT showed a case my conditional line misses: derived Debug on a struct with an F32 field already needs F32 text, whether or not F32 gets Display. "Whenever an F32 renders as text" fixes the digits and adds no impl to the closed list, which was my only objection.
> Concern: `"{f}"` still widens to Float and prints `0.10000000149011612` until the separate F32 ticket decides.
>
> Q8: 8a
> Reasoning: The round-trip law needs only "accepts every display output and rounds correctly". Any further grammar sets input policy (`E`, `+`, overflow) that does not change output bytes, and that policy deserves its own vote.
> Concern: Until the grammar ticket lands, an implementation may reject `1E5` from a JSON file and still conform.
>
> Q9: 9b
> Reasoning: A lexer change touches fmt, LSP and highlighting, and it has its own questions (`1e5` with no `.`?). 3a keeps that ticket open at no cost.
> Concern: People who write `1e-9` in source still get a lex error until that ticket ships.
>
> Q10: 10b
> Reasoning: Power-assert and interpolation already go through Debug/Display, so they get this form with no new text. JSON number output belongs in §3.6.2, which also has to decide NaN/inf, and test-runner timing is tool output, not language. A sentence that covers everything would cover outputs we have not designed.
> Concern: Without the sentence, the JSON encoder could keep `%g` and still conform until the §3.6.2 ticket fixes it.
>
> Q11: 11a
> Reasoning: One sentence fixes a real bug today (`setlocale` through FFI turns `1.5` into `1,5`). Display is the only path from a scalar to text, so locale must not change it.
> Concern: None I can see. It costs one sentence.
>
> Q12: 12a
> Reasoning: It is the one law that replaces the deleted §3.6.1 exception, and implementers can test it. It is one sentence, and it makes 1b's intent explicit, not implied.
> Concern: If a future Float mode (formatting options) breaks it, someone must remember that the law covers only default Display.

#### Phase D — Focused debate on Q10

Q10 split 4-1-1 in Phase C (Systems 10a-lang, Minimalism 10b), so the panel debated Q10 alone. Each seat proposed a wording.

**Systems:**

> SYS Phase D Q10: I change from 10a-lang to 10a-wide, provided the sentence carries the two exclusions below.
>
> Why I changed: the concern in my own Phase C ballot is the argument against 10a-lang. A future `--json` diagnostic, or the test-runner's `duration_ms`, could go back to `%g` and still conform. DevOps is right that CI tools parse those outputs. On the systems side, the cost of 10a-wide is zero: the toolchain uses one formatter routine, a fixed 25-byte buffer, and no locale. That is less code than keeping `%g` alive beside it.
>
> Against 10b: Min's own concern decides it. Without the sentence, the JSON encoder can keep `%g` and conform, and today it loses precision (`0.3`). Power-assert also has a `%g` intro path in the code today that bypasses Debug.
>
> Against 10a-user: it excludes JSON. PLT has dropped it, and JSON number output is exactly where the type matters (`1` parses as Int, `1.0` as Float).
>
> Wording I want:
> "Every place Blink or its toolchain renders a Float as text uses this form, unless the program asks for another form through an explicit formatting API. JSON output of NaN and infinity is not covered: §3.6.2 decides it."
>
> Why each part:
> - "Blink or its toolchain" answers DevOps' concern: it binds only our own tools, not third-party ones.
> - "unless the program asks for another form through an explicit formatting API" answers PLT's concern. A future precision API (`{x:.2}`) is then a stated exception, not a quiet break.
> - The last sentence answers AI/ML's concern: non-finite JSON is excluded by name.

**Web/Scripting:**

> WEB, Phase D, Q10: I hold 10a-wide, with tighter wording that meets every concern raised.
>
> Proposed sentence:
> "Every place that Blink or its own toolchain (compiler diagnostics, the `blink` CLI, the test runner) renders a finite Float as text uses this form, unless this spec states another form for that place. How JSON encodes NaN and the infinities is decided in §3.6.2."
>
> How this answers each concern:
> - Third-party tools (devops): the sentence names only Blink's own toolchain, so it binds nothing outside it.
> - A future fixed-precision format (plt): "unless this spec states another form" makes any exception explicit. A tool can't quietly break the rule, and a later format API (`{x:.2}`) only has to state its own form.
> - JSON NaN/inf (aiml, min): "finite", plus the pointer to §3.6.2, keeps them out of this rule.
>
> Against 10a-lang (sys): sys's own concern defeats it. A future `--json` diagnostic, or test-runner output, could go back to `%g` and still conform. To a user, a test log showing `0.3` next to a Display of `0.30000000000000004` is one toolchain contradicting itself. Users don't separate "language output" from "tool output". They see text from `blink`.
>
> Against 10a-user (plt): plt has moved off it. It leaves out machine-readable output, which is where drift breaks CI parsers.
>
> Against 10b (min): min names the gap: the JSON encoder can keep `%g` and still conform. "Power-assert goes through Debug" is true only if the implementation routes it that way. Today it does not, because the power-assert intro still uses `%g`. "Covers outputs we have not designed" is exactly what the default should do. A new output gets the one form unless someone decides otherwise on purpose, and the "unless this spec states" clause allows for that.
>
> No change of position.

**PLT:**

> PLT, Phase D, Q10: I hold 10a-wide, with tighter wording that answers the concerns raised.
>
> Against 10b: min concedes that without the sentence the JSON encoder could keep `%g` and still conform. That is a concrete composition bug, not a style point. Under `%g`, the Float 20.0 encodes as `20`, and §3.6.2 makes `json.parse("20")` give `JsonValue.Int`. A derived Float field's encode-then-decode would then change the JSON variant. A spec that permits that has failed to compose its own two rules. "A future ticket will fix it" leaves a known bug conforming in the meantime.
>
> Against 10a-lang: sys's own concern names its gap. A test-runner or future `--json` output could go back to `%g` and still conform, and those outputs are machine-parsed contracts. Drawing a line between "language" and "tool" output adds a classification question and gains nothing.
>
> Against 10a-user (my earlier position): it leaves out finite JSON numbers, which my composition argument needs.
>
> Proposed exact wording:
> "Every place that Blink, its standard library or the `blink` toolchain writes a finite Float as decimal text uses this form, unless this spec names a different form for that place. How JSON encodes NaN and the infinities is decided in §3.6.2."
>
> Why each part:
> - "finite" keeps the open NaN/inf JSON question out of scope (aiml's concern).
> - "Blink, its standard library or the `blink` toolchain" names the bound set, so third-party tools are not constrained (devops's concern).
> - "unless this spec names a different form" means a future fixed-precision formatter needs a stated exception, not a quiet divergence (my concern).
>
> No change of position.

**DevOps:**

> DEVOPS Phase D, Q10: I hold 10a-wide, and I propose wording that answers each seat's concern.
>
> Against 10a-lang: sys's own concern is the argument against it. With 10a-lang, a future `--json` diagnostic or the test-runner JSON can go back to `%g` and still conform. Tools parse those outputs in CI, which makes them the most contract-like Float text we ship, so they are the last place to leave out.
>
> Against 10a-user: it covers human output and leaves out machine output. That is backwards from a tooling view. A person can read `0.3`; a parser that compares values cannot.
>
> Against 10b: min's own concern shows the hole. Until the §3.6.2 ticket lands, the JSON encoder can keep `%g` and conform. On "covers outputs we have not designed": the sentence binds only the finite-value text, and its exception clause leaves room for a format the spec states on purpose.
>
> Wording, built from the concerns of plt, aiml and devops:
>
> > "Every place where the Blink language, its standard library, or the `blink` toolchain renders a finite `Float` (or `F32`) as text uses this form, unless the spec states another format for that place. How JSON output represents NaN and the infinities is decided in §3.6.2."
>
> - "finite" and the last sentence keep the NaN/inf JSON ticket open, which answers aiml.
> - "unless the spec states another format" lets a future fixed-precision formatter or `{x:.2}` exist as a stated exception, not a quiet break, which answers plt.
> - "the `blink` toolchain" covers our tools only, not third-party tools, which answers my own concern.
> - "standard library" covers the JSON encoder and log helpers, which answers sys's concern and the gap min names.
>
> No change of position.

**AI/ML:**

> AI/ML Phase D, Q10: I stay with 10a-wide, and I propose exact wording that answers the concerns raised.
>
> Against 10b (min): min's own concern decides it. Without the sentence, the JSON encoder can keep `%g` and still conform. For an AI that learns from the spec alone, "Display uses form X" says nothing about JSON or test-runner text, so a model must guess. Guessing is the decision point this ticket exists to remove.
>
> Against 10a-lang (sys): sys's own concern applies. A future `--json` diagnostic could go back to `%g`. The line between "language output" and "tool output" is one a reader cannot see in the text itself. A reader sees a Float in a test log and expects the same form as Display.
>
> Against 10a-user (plt has moved off it): it excludes JSON, and JSON is where the Int/Float syntax split (`20` vs `20.0`) matters most.
>
> The concerns about "toolchain" are fair: it is too broad, it might seem to bind third-party tools, and it gives no way out for a real need. My wording handles all three:
>
> "Every place where Blink or its own toolchain (the `blink` commands, the test runner, diagnostics) writes a finite Float as text uses this form. JSON output of a NaN or an infinity follows §3.6.2. Any other output that needs a different form, such as a fixed precision, states that form in this spec."
>
> - "Its own" leaves third-party tools out (devops).
> - "Finite" plus the §3.6.2 pointer leaves non-finite JSON to its ticket (aiml, sys, devops).
> - The last sentence turns a future fixed-precision need into a stated exception, not a quiet break (plt).
> - The list in brackets bounds "toolchain" (web).
>
> No change of position.

**Minimalism:**

> Min, Phase D, Q10: I CHANGE from 10b to 10a-wide, with tight wording.
>
> Why I moved: my own Phase C concern defeats 10b. Without the sentence, the JSON encoder can keep `%g` and still conform, and PLT's argument shows why that matters: JSON tells Int from Float by syntax, so a finite Float written as `1` comes back as an Int. A spec hole that changes a value's type is not something minimalism should defend. Web's point also stands: a test log that shows `0.3` while Display shows `0.30000000000000004` is the exact bug this ticket fixes.
>
> Against 10a-lang: it leaves out test-runner output, which users read next to assert failures, and sys's own concern (a future `--json` diagnostic going back to `%g`) shows the gap. Against 10a-user: it leaves out JSON numbers, and PLT has dropped it.
>
> My minimalist condition is that the sentence binds only what Blink ships, and names the one exception, so it does not read as a format we have not designed. Proposed wording:
>
> "Every place the language, its standard library, or the `blink` toolchain renders a finite `Float` as text uses this form. This includes Display, Debug, interpolation, power-assert, JSON number output, and test-runner output. How JSON encodes NaN and the infinities is decided in §3.6.2. Third-party tools are not bound."
>
> This answers devops's concern (third-party tools) and aiml's (non-finite JSON). PLT's future fixed-precision tool would be an explicit new format option, not a silent break. That is a separate feature, and this sentence does not block it.
>
> STABLE: ready to re-vote 10a-wide.

#### Phase D — Q10 re-vote

Result: 10a-wide 6-0. Wording: W-plt 4 (PLT, Minimalism, AI/ML, Web), W-devops 2.

**Systems:**

> SYS Q10 re-vote: 10a-wide. First choice W-devops, second choice W-plt.
>
> Reasoning: W-devops says outright that the standard library is bound. That covers the JSON encoder, which is where `%g` would most likely survive. It also names F32, which fits the 7a result, so F32 text cannot fall back to a second formatter. "Unless the spec states another format for that place" is better than my own "explicit formatting API" clause. Every exception then has to be written into the spec, so none can come in through an API that was never voted on.
>
> Concern: "(or `F32`)" could be read as F32 using binary64 digits. The F32 text from 7a must make clear that "this form" means the same layout with binary32 shortest digits.

**Web/Scripting:**

> WEB, Q10 re-vote.
>
> 1. Vote: 10a-wide, wording W-plt. Second choice: W-devops.
>
> 2. Reasoning:
> - W-plt covers the standard library, which my own wording left out. To a user, a Float in std output (json, log helpers) is the same as one in the CLI's output, and both must print the same text.
> - "Decimal text" leaves clean room for a future bit-exact or hex form, such as the `to_bits` follow-up, without needing an exception.
> - "Unless this spec names a different form" makes any exception, such as fixed precision, a stated choice and not a quiet break.
> - I rank it above W-min because W-min's closed list of places has no exception clause, so a future `{x:.2}` format API would contradict it.
>
> 3. Concern: "Writes a finite Float as decimal text" doesn't name concrete places, so an implementer may not see that power-assert and test-runner output are covered. The spec example or rationale should list them, as W-min does.

**PLT:**

> PLT, Q10 re-vote.
>
> 1. Vote: 10a-wide. First choice W-plt, second choice W-devops.
>
> 2. Reasoning: The wording needs three properties.
> - The set it binds is named and closed: Blink, its standard library and the `blink` toolchain.
> - Only finite values are in scope, so the open JSON NaN/inf question stays out of this rule.
> - Any exception must be stated in the spec, which is what "unless this spec names a different form" does.
>
> W-devops has all three; its F32 mention is consistent with Q7. W-sys falls short because its exception is "an explicit formatting API", which is not a spec-named exception. W-min falls short because it has no exception clause at all.
>
> 3. Concern: "decimal text" in W-plt could be read as excluding a future explicitly specified hex-float output. That is the intended reading, but the editor should confirm it.

**DevOps:**

> DEVOPS Q10 re-vote: 10a-wide. First choice W-devops, second choice W-plt.
>
> Reasoning: The sentence must bind the standard library (the JSON encoder) and the `blink` toolchain (test-runner JSON, `--json` diagnostics). W-devops and W-plt both do. The exception must also be one the spec states, not any formatting API a library adds, because only a stated exception gives tools a fixed contract. That rules out W-sys's "explicit formatting API". W-devops also names F32, so it matches the 7a result. W-plt's "decimal text" is a useful narrowing that keeps a future hex `to_bits` form out of scope, and I would accept that word added to W-devops.
>
> Concern: A tool output written before the spec names its exception (such as a fixed-precision timing column) will not conform until someone writes the exception into the spec.

**AI/ML:**

> AI/ML Q10 re-vote: 10a-wide, wording W-plt first, W-min second.
>
> Reasoning: W-plt names the standard library, which my own wording left out. A model writing stdlib code would otherwise have to guess whether the rule applies there. Its "unless this spec names a different form for that place" makes every exception a lookup in the spec, not a guess, and it covers a future explicit formatting API. "Decimal text" is exact about what is bound. W-min's concrete list of places is the most learnable, but it has no exception clause, so a later formatting API would contradict it.
>
> Concern: W-plt has no example list, so a reader may not see at once that power-assert and test-runner output are covered. The spec text should follow it with W-min's list as examples.

**Minimalism:**

> Min, Q10 re-vote.
>
> 1. Vote: 10a-wide, wording W-plt (first choice). Second choice: W-min.
>
> 2. Reasoning: W-plt is the shortest wording that binds what Blink ships (language, stdlib, `blink` toolchain) and nothing else. Its exception, "unless this spec names a different form", means a future fixed-precision tool or a `to_bits` hex form must be written into the spec, and cannot come back as a silent break. Its words "as decimal text" also leave a future bit-exact hex form open, which matters because 1b drops the sign of zero. I prefer it to W-sys, whose "explicit formatting API" refers to a feature that does not exist, and to W-devops, which repeats the F32 rule already decided in Q7.
>
> 3. Concern: W-plt does not list the places it covers, so an implementer could argue that a given output (for example test-runner timing) is not "toolchain"; W-min's explicit list would close that, so it is my fallback.

### Final Spec

```blink
fn main() {
    let big = 10000000000000000.0
    let tiny = 0.00001
    io.println(0.1.display())                // 0.1
    io.println((0.1 + 0.2).display())        // 0.30000000000000004
    io.println(1.0.display())                // 1.0
    io.println(9007199254740993.0.display()) // 9007199254740992.0
    io.println(big.display())                // 1.0e16
    io.println(0.0001.display())             // 0.0001
    io.println(tiny.display())               // 1.0e-5
    io.println((-0.0).display())             // 0.0
    io.println((0.0 / 0.0).display())        // NaN
    io.println((-1.0 / 0.0).display())       // -inf
    io.println([1.0, 2.5].debug())           // [1.0, 2.5]
}
```

- Digits: the fewest significant digits that convert back to the same Float under binary64 round-to-nearest, ties-to-even; then the one nearest the exact value; then an even last digit. The spec fixes the output, not the algorithm.
- Layout: plain form when −4 ≤ k < 16; otherwise `d₁.d₂…dₙ` (or `d₁.0`), `e`, `-` when k < 0, then k with no `+` and no leading zeros. Every finite output contains `.` and matches `-? DIGITS '.' DIGITS ('e' '-'? DIGITS)?`.
- Specials: every NaN renders `NaN`; `inf` and `-inf`; `-0.0` renders `0.0`.
- `debug()` returns the same text as `display()`. The §3.6.1 Float exception to the Debug/Eq law is gone, which replaces Map Debug Q3.
- Laws: `x.display().parse_float() == Ok(x)` under Blink `==`; `x == y` exactly when `x.display() == y.display()`.
- The decimal mark is always `.`; neither `display()` nor `parse_float` depends on the locale or the C library.
- Scope: every place Blink, its standard library or the `blink` toolchain writes a finite Float as decimal text uses this form unless the spec names another form for that place (`display()`, `debug()`, interpolation, power-assert, JSON number output, test-runner output). A form that is not decimal text is outside the rule. JSON NaN/inf belongs to §3.6.2.
- F32 text uses the same layout with binary32 shortest digits. No F32 Display impl is added.
- `parse_float` must accept every display output and round correctly; the rest of its input grammar is a separate ticket.
- Separate tickets: a bit-exact bits path, JSON NaN/inf, the `parse_float` input grammar, exponent float literals, and the closed Display list vs sized integers and F32.
