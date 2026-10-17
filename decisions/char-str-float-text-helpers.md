[< All Decisions](../DECISIONS.md)

# Char Classification, Str Trim/Pad/Repeat and Float Text Helpers — Design Rationale

Two stdlib gaps were resolved together. The first: `Char` had no classification methods, and `Str` had no trim by a set of codepoints, no `repeat` and no padding. The second: Blink had no way to pad a number, to write a `Float` with a fixed count of decimal places, or to round a `Float`. Programs wrote these by hand, often wrong (sign before zeros, ties, `-0.00`). A math module was out of scope.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

Panelist text below is quoted verbatim, each reply whole. Option labels are in the Phase C ballot summary.

#### Phase A — Independent proposals

##### Systems

SYSTEMS (Sys) — Phase A proposal

Guiding rule: a method name must tell you its cost and its character set. Every method below compiles to a known small loop or a single instruction, with one allocation sized before the copy.

P1. Char predicates — on Char, ASCII-explicit names, Unicode only where it is cheap

Methods in a sealed CharOps trait (like the integer table abs/min/max), not std.char free functions. They are pure compares; as methods they inline to 1–2 `cmp`/`sub+cmp` instructions after `cc -O2`. Implement in Blink in lib/std; no runtime intrinsic needed.

    fn is_ascii(self) -> Bool              // cp < 128
    fn is_ascii_digit(self) -> Bool        // '0'..='9'
    fn is_ascii_alpha(self) -> Bool        // 'a'..='z' | 'A'..='Z'
    fn is_ascii_alphanumeric(self) -> Bool
    fn is_ascii_upper(self) -> Bool
    fn is_ascii_lower(self) -> Bool
    fn is_ascii_whitespace(self) -> Bool   // exactly the set trim() strips
    fn is_whitespace(self) -> Bool         // Unicode White_Space: 25 fixed codepoints
    fn to_digit(self, radix: Int) -> Option[Int]  // radix 2..=36, else panic

    let n = if c.is_ascii_digit() { c.to_digit(10).unwrap() } else { 0 }

Why not bare `is_digit`/`is_alpha`: the reader cannot tell ASCII from Unicode, and Unicode `is_alphabetic` needs ~4–8 KB of range tables and a binary search — a different cost class that must not hide behind a short name. White_Space is a fixed 25-codepoint set (a switch), so it gets the plain name. Unicode alpha/upper/lower go in a later std.unicode module with the tables.

Edges: `'é'.is_ascii_alpha()` is false. `'٣'.to_digit(10)` is None. The spec must pin `trim`'s set (today {U+0020, \t, \n, \r}, lib/std/str.bl) and name it as `is_ascii_whitespace` — one definition, not two.

Related honesty fix (separate chore): spec says `to_upper`/`to_lower` are "Unicode-aware"; code maps only ASCII. Fix the text or ship the tables; do not leave the gap.

Cross-language: Rust uses this exact split (`is_ascii_digit` vs `is_alphabetic`). Go's `unicode.IsDigit` hides a table lookup behind a short name.

P2. Trim by set — Str-of-codepoints, not a closure; no new names for whitespace trim

    fn trim_chars(self, set: Str) -> Str
    fn trim_left_chars(self, set: Str) -> Str
    fn trim_right_chars(self, set: Str) -> Str
    fn strip_prefix(self, prefix: Str) -> Option[Str]
    fn strip_suffix(self, suffix: Str) -> Option[Str]

    "xxabcxx".trim_chars("x")          // "abc"
    "v1.2".strip_prefix("v")           // Some("1.2")
    "1.2".strip_prefix("v")            // None

`set` is a set of codepoints; order and repeats do not matter; empty set is a no-op. Typical sets hold 1–4 chars and sit in L1, so a linear scan per codepoint beats any hash. A closure `fn(Char) -> Bool` costs an indirect call per codepoint unless closures monomorphize; add `trim_left_while(f)` later if friction shows a need.

Reject `trim_start`/`trim_end`: they duplicate `trim_left`/`trim_right` (spec forbids two names for one operation). Reject `strip(chars)`: reads as `strip_prefix`.

`strip_*` returns Option because the caller must know whether the prefix was there; it is one byte compare plus a slice, O(len(prefix)). When nothing is trimmed the result may share the input's bytes (no copy).

P3. repeat and pad — one exact-size allocation

    fn repeat(self, n: Int) -> Str
    fn pad_left(self, width: Int, fill: Char) -> Str
    fn pad_right(self, width: Int, fill: Char) -> Str

    "ab".repeat(3)            // "ababab"
    "7".pad_left(3, '0')      // "007"
    "héllo".pad_left(3, ' ')  // "héllo" (unchanged, never truncates)

- `repeat`: n < 0 panics (a negative count is a bug, same class as division by zero); n == 0 gives "". Panics before allocating if `byte_len * n` overflows.
- `pad_*`: `width` counts codepoints, same as `len()`. width <= len returns self unchanged; negative width is the same no-op.
- `fill` is a Char, not a Str: removes the multi-codepoint-fill question at the type level, and the output size is `byte_len + (width - len) * fill.utf8_len`, known before the copy.
- Document that codepoints are not display columns: East Asian wide chars and combining marks will misalign. Terminal-width layout is out of scope.

P4. Float rounding — Float -> Float, one instruction each, never panics

    fn floor(self) -> Float
    fn ceil(self) -> Float
    fn round(self) -> Float   // ties away from zero: 2.5 -> 3.0, -2.5 -> -3.0

Lower to C `floor`/`ceil`/`round` = `roundsd` on SSE4.1, `frintm`/`frintp`/`frinta` on AArch64. NaN, ±inf, ±0.0 pass through. For an Int, chain the existing call: `x.floor().truncate()` (panics on NaN/Inf as specified). No `trunc`: one letter from `truncate` (Float->Int) with a different job.

Reject `round(digits)`. Binary floats cannot hold most decimal results; Python's `round(2.675, 2) == 2.67` surprises people every week. Rounding to decimal places is a rendering question (P5); exact money is `Decimal`'s job.

Sits beside the future math module without overlap: rounding = Float methods; transcendental = the module. No `math.floor`.

P5. Fixed-decimal rendering — `display_fixed`, a named Float text form

    fn display_fixed(self, digits: Int) -> Str

    3.14159.display_fixed(2)   // "3.14"
    2.5.display_fixed(0)       // "2"   (exact tie -> even)
    0.125.display_fixed(2)     // "0.12"
    2.675.display_fixed(2)     // "2.67" (true binary value is 2.67499...)
    -0.001.display_fixed(2)    // "-0.00"
    (1.0 / 0.0).display_fixed(2) // same text as Display for inf

Name: `to_fixed` breaks the `to_` = From rule (fact 5); the `display` prefix marks it as a rendering, the "named different form" fact 6 allows.

Semantics:
- Rounds the exact binary value, ties to even (glibc/musl `printf("%.*f")` behaviour).
- digits < 0 panics.
- NaN/±inf render as Display renders them.
- A negative value keeps its sign even when all shown digits are zero ("-0.00") — honest; the spec must say it.
- Output never depends on locale. The runtime must not call snprintf under a locale it cannot control; on targets whose libc is not exact (MSVC CRT) it ships its own exact algorithm (Ryu-printf).

Optional, for the integer half of Gap 2: `fn display_zero_padded(self, width: Int) -> Str` on integer types, sign first: `(-7).display_zero_padded(3)` gives "-07", where `"{n}".pad_left(3, '0')` would give "0-7".

Interpolation stays free of format specs. Agree with the existing decision: method calls inside `{}` cover the cases, and each call's cost is visible.

Cost summary: every method above is O(n) in its output with one allocation, or one machine instruction. No hidden tables, no hidden closure calls, no heap-allocated format parser.

##### Web/Scripting

Web/Scripting panelist: proposal for both gaps

Guiding rule: a JS, Python or Kotlin developer should guess the name, the argument order and the edge-case behaviour without opening the docs. Where those languages disagree, I pick the one that creates fewer Stack Overflow questions.

**P1. Char predicates as methods on Char, not in `std.char`**

```
let c = 'a'
c.is_digit()          // ASCII '0'..'9' only
c.is_alpha()          // Unicode Alphabetic
c.is_alphanumeric()   // is_alpha() || is_digit()
c.is_whitespace()     // Unicode White_Space
c.is_upper()          // Unicode Uppercase
c.is_lower()          // Unicode Lowercase
c.is_ascii()          // code point < 128
c.to_digit()          // Option[Int]: '7' -> Some(7), 'x' -> None
```

The signatures are `fn is_digit(self) -> Bool` and so on, with `fn to_digit(self) -> Option[Int]`. They go in a sealed `CharOps` table, in the same way that `StrOps` holds the Str methods. `lib/std/char.bl` keeps only the impls.

- **Location.** People type `c.` and read the autocomplete list. Nobody guesses `char.is_digit(c)`. A module would bring back the "where does this function live" question that the Str methods already answer.
- **ASCII or Unicode.** I use a split rule, chosen per predicate:
  - `is_digit` is ASCII only. Python's `"²".isdigit()` returns True, and then `int()` fails on the same text. That gap generates SO questions. A digit test must agree with `parse_int` and with `to_digit`.
  - `is_whitespace`, `is_alpha`, `is_upper` and `is_lower` are Unicode-aware. If a tokenizer treats `é` as not a letter, or NBSP as not whitespace, that is a bug report from the first user outside the US.
  - A program that wants ASCII only writes `c.is_ascii() && c.is_alpha()`. That gives one extra method, not six `is_ascii_*` copies of the others.
- **`to_digit` is base 10 only.** Hex scanning is the rare 10% case and `parse_int` covers it. A radix argument would make every user pass `10`.
- **Consistency note.** The spec already says `to_upper` is "Unicode-aware", and the stdlib maps ASCII only. That is an implementation bug and needs a ticket. These predicates must not copy the bug.

**P2. Str: rename the trim methods, then add trim-by-set, strip, repeat and pad**

```
fn trim_start(self) -> Str                   // renames trim_left
fn trim_end(self) -> Str                     // renames trim_right
fn trim_chars(self, set: Str) -> Str         // both ends, any codepoint in set
fn strip_prefix(self, prefix: Str) -> Option[Str]
fn strip_suffix(self, suffix: Str) -> Option[Str]
fn repeat(self, n: Int) -> Str
fn pad_start(self, width: Int, fill: Char) -> Str
fn pad_end(self, width: Int, fill: Char) -> Str
```

- **Rename, not an alias.** JS deprecated `trimLeft` for `trimStart`, and Rust deprecated `trim_left` for `trim_start`, because "left" is wrong for RTL text. The spec forbids two names for one operation, so this is a 3-step rename, not an addition. `pad_start`/`pad_end` then follow the same naming axis, as JS and Kotlin `padStart` do. If we have `trim_start` beside `pad_left`, we will get SO questions about the mismatch.
- **`trim_chars(set: Str)`, not `trim_matches` or `strip(chars)`.** Python's `"report.txt".strip(".txt")` returns `"report"` and strips the `t` as well. That is a famous footgun, and it happens because the name does not say "set". `trim_chars` says it.
  - An empty `set` returns `self` unchanged.
  - A predicate overload (`fn(Char) -> Bool`) waits for friction. Leading zeros, the main one-sided case, already go through `parse_int`.
- **`strip_prefix`/`strip_suffix` return `Option[Str]`.** This makes them a check and a remove in one call, which is the shape tokenizers use:

  ```
  match arg.strip_prefix("--") {
      Some(name) => parse_flag(name)
      None => parse_positional(arg)
  }
  ```

  Scripts that just want "remove it if present" write `.unwrap_or(s)`. With Python's `removeprefix`, which returns the string unchanged, you cannot tell whether a prefix was removed.
- **`repeat(n)`.** `n <= 0` returns `""`. Python does this; JS throws instead. Negative counts come from width arithmetic, and the user expects a no-op. `"ab".repeat(3)` returns `"ababab"`.
- **`pad_start` and `pad_end`:**
  - `width` counts codepoints, the same as `len()`.
  - If `width <= self.len()`, including a negative width, the call returns `self` unchanged. It never truncates. JS, Python and Kotlin all agree on this.
  - `fill` is a `Char`, so a multi-codepoint fill is a type error, not an open question about how to truncate it. JS takes a string fill and cycles it. Almost nobody uses that, and it makes width a puzzle.
  - The method makes no claim about terminal display width (CJK or emoji). The doc must state this in one line.

  ```
  let row = "{name.pad_end(12, ' ')}{qty.display().pad_start(6, ' ')}"
  ```

**P3. Float rounding: `round`, `floor` and `ceil` with no digits argument**

```
fn round(self) -> Float   // ties away from zero: 2.5 -> 3.0, -2.5 -> -3.0
fn floor(self) -> Float
fn ceil(self) -> Float
```

- **Ties.** Python 3 rounds half to even (`round(2.5) == 2`) and JS rounds half toward +inf (`Math.round(-2.5) == -2`). Both are classic SO surprises. Half away from zero is what school teaches and what C `round` and Rust do.
- **Return `Float`.** NaN and ±inf pass through, so there is no panic in arithmetic code. To get an Int, write `f.round().truncate()`. The spec already has `truncate` and `to_int_checked`.
- **Naming flag.** `truncate()` returns Int and panics, while `round()` returns Float. That asymmetry will confuse people, and the panel should record it. I would not rename `truncate` in this round.
- **I reject `round(digits)`.** `round(2.675, 2) == 2.67` is one of Python's most-asked questions. Rounding to decimal digits on a binary float is display work dressed up as math. That job belongs to `fixed`, and exact money belongs to `Decimal`.

**P4. `Float.fixed(digits) -> Str` as the one named text form**

```
fn fixed(self, digits: Int) -> Str
3.14159.fixed(2)   // "3.14"
3.5.fixed(2)       // "3.50"
2.0.fixed(0)       // "2"
```

- **Name.** The name is `fixed`, not `to_fixed`. The spec reserves `to_` for From/TryFrom sugar, and no `From[Float] for Str` exists. JS developers will still find it next to `toFixed`.
- **Spec position.** This is the "different form named by this spec" that the Float Text Form section already allows.
- **Edge cases:**
  - `digits` outside `0..=20` panics, through a `requires` contract. JS throws a RangeError here.
  - Rounding uses the exact binary value, ties away from zero. So `2.675.fixed(2)` is `"2.67"`, the same as JS, Python and C. The doc must say this and point to `Decimal` for money.
  - NaN and ±inf render the same as `Display` does.
  - A result that would be all zeros drops the sign: `(-0.001).fixed(2)` is `"0.00"`, not `"-0.00"`. A `-0.00` in a money report is a bug report.

**P5. No format specs in interpolation, and no Int padding method**

- Keep the existing decision of no `:modifier` syntax. P2 and P4 cover the benchmark reports.
- Zero padding becomes `"{n}".pad_start(3, '0')`. Its one gotcha is that negative numbers give `"0-7"`. IDs, times and counters are almost always non-negative, so I would wait for friction before adding `Int.zero_pad`. The `pad_start` doc must show this case.

**Placement and order**

- All of this goes in the sealed `StrOps`, `CharOps` and Float method tables. None of it belongs in the future math module. `sqrt` and the trig functions can go there, but `round`, `floor` and `ceil` stay methods, because people type `f.` first.
- Ship `Str.chars()` first. Without it, the Char predicates have nothing to iterate over.

**Cross-language summary**

| Blink proposal | Follows | Departs from |
|---|---|---|
| Rounding ties away from zero | C, Rust | Python (half to even), JS (half toward +inf) |
| `trim_start` / `trim_end` / `pad_start` | JS, Kotlin, Rust | none |
| `trim_chars` set argument | Python `strip`, with a name that makes the set explicit | none |
| `strip_prefix` returns `Option` | Rust | Python `removeprefix` (returns the string unchanged) |
| `fixed` | JS `toFixed`, without the `to_` prefix | none |

##### PLT

PLT proposal: Char classification, Str trim/pad/repeat, Float rounding and fixed text

My guiding rule is that every new method is a total function with a stated law that ties it to methods the spec already has. A method that has no law becomes a second, subtly different definition of the same concept, and I reject those.

**P1. Char predicates go on Char, in the sealed `CharOps` table, not in `std.char`.**

Classification is part of what a Char is, the same way `.len()` is part of a Str, so it belongs on the type and not in a module of free functions. `lib/std/char.bl` keeps only the TryFrom impl.

    fn is_ascii_digit(self) -> Bool          // '0'..='9'
    fn is_ascii_alpha(self) -> Bool          // 'a'..='z' | 'A'..='Z'
    fn is_ascii_alphanumeric(self) -> Bool
    fn is_ascii_upper(self) -> Bool
    fn is_ascii_lower(self) -> Bool
    fn is_whitespace(self) -> Bool           // see law W
    fn to_digit(self, radix: Int) -> Option[Int]

- **ASCII predicates carry `ascii` in the name.** A predicate whose name says "digit" but whose set is unstated can't be reasoned about. The `to_upper` "Unicode-aware" claim is already false in lib/std/str.bl. I would rather the name tell the truth than add a second spec/implementation mismatch.
- **Unprefixed names are reserved for Unicode general-category predicates.** `is_alphabetic` and `is_numeric` would be defined against a Unicode version that the spec pins. Without a pinned version, the result of a pure function changes with the toolchain. They are not in v1.
- **Law W (one whitespace).** `c.is_whitespace()` is true exactly for the set that `trim` removes. The spec must list that set once and both definitions must point to it. Two whitespace definitions would make `s.trim()` and `s.trim_by(fn(c) { c.is_whitespace() })` differ, which is unsound.
- **`to_digit`** returns `Some(v)` with `0 <= v < radix` for `0-9a-zA-Z`, and `None` otherwise. A radix outside `2..=36` is a contract violation and panics. It does not return `None`, because `None` must mean "not a digit" and nothing else.

    fn main() {
        let c = 'f'
        let v = c.to_digit(16)       // Some(15)
        let d = 'f'.to_digit(10)     // None
        let ok = '7'.is_ascii_digit()
    }

**P2. Trim by set: one predicate form.**

    fn trim_by(self, keep_out: fn(Char) -> Bool) -> Str
    fn trim_left_by(self, keep_out: fn(Char) -> Bool) -> Str
    fn trim_right_by(self, keep_out: fn(Char) -> Bool) -> Str

- The predicate is the general form: a set of characters is just its membership test. The caller writes the set case as `s.trim_by(fn(c) { c == 'a' || c == 'b' })`.
- I reject a `trim_matches(Str)` overload, and a Rust-style `Pattern` trait even more. Either one adds ad-hoc overloading on the argument type, and the typing rule for it is worse than the problem it solves.
- **Effects:** `trim_by` is effect-polymorphic in its closure, the same as `List.map`. It adds no effect of its own.
- **Laws:**
  - `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`
  - `s.trim_by(p) == s.trim_left_by(p).trim_right_by(p)`
- **Naming:** keep `left`/`right` because they already exist. Don't add `trim_start`/`trim_end` as aliases (background fact 2). If the panel wants start/end, which is the correct logical-order name for right-to-left text, it should rename the whole family through the 3-step protocol as a separate vote, never as an alias.

**P3. Prefix and suffix removal returns Option.**

    fn strip_prefix(self, p: Str) -> Option[Str]
    fn strip_suffix(self, p: Str) -> Option[Str]

- `None` means the prefix is absent. `Some(rest)` means it was removed.
- Python's `removeprefix` returns the input unchanged on a miss, so the caller can't tell whether the prefix was there. The Option type keeps that information, and `.unwrap_or(s)` gives the Python behaviour back.
- An empty `p` gives `Some(self)`.
- **Law:** `s.strip_prefix(p) == Some(r)` exactly when `p ++ r == s`, written as `"{p}{r}" == s`.

**P4. `repeat` and padding: fill is a Char, so the type removes the edge case.**

    fn repeat(self, n: Int) -> Str
    fn pad_left(self, width: Int, fill: Char) -> Str
    fn pad_right(self, width: Int, fill: Char) -> Str

- **`repeat`:** `n <= 0` gives `""` and does not panic. This follows the `with_capacity` `n <= 0` rule (4-2) so the stdlib has one convention for non-positive counts. Law: `s.repeat(n).len() == s.len() * max(n, 0)`.
- **Padding:**
  - `width` counts codepoints, the same unit as `len()`.
  - When `width <= s.len()`, the string comes back unchanged. Padding never truncates, so the result length is `max(width, s.len())`.
  - A Char `fill` rules out a multi-codepoint fill by its type, so there is no rule to write about partial fill units.
- **Required fill, no default.** Blink has no default parameters, and `' '` versus `'0'` is a choice the caller should see.
- **Documented limit:** padding counts codepoints, not terminal columns. Wide CJK text and combining marks will misalign. Column-aware width is a Unicode-version question for a later library.

    fn main() {
        let row = "{name.pad_right(12, ' ')}{qty.display().pad_left(5, ' ')}"
        let rule = "-".repeat(17)
    }

**P5. Float rounding is Float to Float, with ties stated.**

    fn floor(self) -> Float
    fn ceil(self) -> Float
    fn round(self) -> Float      // ties away from zero: 2.5 -> 3.0, -2.5 -> -3.0

- **Total:** NaN, ±inf and ±0.0 map to themselves, and the sign of zero is kept, as in IEEE 754 roundToIntegral.
- **They return Float, not Int.** Float to Int is partial, and the spec already routes that through `truncate()` and `to_int_checked()`. Folding a partial conversion into `round` would hide a panic.
- **No `trunc`.** `truncate()` already exists and returns Int. A Float-returning `trunc` next to it would be two names for nearly one operation, with different types.
- **Ties away from zero** matches C `round`, Rust and Swift. Python's ties-to-even `round()` is a known source of surprise. Anyone who needs banker's rounding for money should use `Decimal`.

**P6. Reject `round(digits)`; add a rendering form instead.**

`x.round(2)` can't be sound in binary64. The value `2.675` is really 2.67499999…, and no Float equals 2.68 exactly. The only sound definition of "round to n decimals" is in the text domain, so I propose:

    fn display_fixed(self, digits: Int) -> Str

- **Name:** it is a rendering, not a conversion, so per background fact 5 it gets no `to_` name. The `display_` prefix marks it as the spec's named "different form" (background fact 6).
- **Digits:** take the exact decimal value of the binary64 number and round it to `digits` places, ties to even. A tie can occur only when the exact value is a tie, for example `0.125.display_fixed(2) == "0.12"` and `2.675.display_fixed(2) == "2.67"`. The result does not depend on the C library or the locale.
- **Format:**
  - Write `-` only when the rounded text has a non-zero digit, so `(-0.001).display_fixed(2) == "0.00"`. This matches Display's rule that `-0.0` renders as `0.0`.
  - `digits == 0` gives no `.`.
  - `digits < 0` panics because it is a contract violation.
  - NaN and ±inf render as `NaN`, `inf` and `-inf`, the same as Display.
- **No format specs in interpolation.** `"{price.display_fixed(2)}"` composes because Str implements Display. That proves the existing no-format-spec decision is enough, and I would reaffirm it.

**P7. Zero-padding a signed Int needs its own operation (optional sub-vote).**

`"{n}".pad_left(3, '0')` gives `"0-7"` for `-7`. You can't build sign-aware zero padding from textual padding, and the `abs()` workaround overflows at the type's MIN. I propose:

    fn display_padded(self, width: Int) -> Str   // on Int: (-7).display_padded(3) == "-07"

- Zeros go after the sign.
- `width` counts the sign.
- When the value is already at least `width` long, it is not truncated.

If the panel calls this YAGNI, the spec must at least state the `"0-7"` hazard next to `pad_left`.

**How this sits next to the math module.** `floor`, `ceil` and `round` are sealed methods on Float, the same tier as `abs` on Int. The future math module holds the transcendental functions and constants, and must not re-export these three under a second name.

**Cross-language notes.**
- **Rust:** `is_ascii_digit`, `to_digit(radix)` and `strip_prefix -> Option` match. I reject its `Pattern` trait.
- **Haskell:** `Data.Char` is likewise split into ASCII and Unicode-category predicates. Its `isSpace` follows a law like W.
- **OCaml:** `Float.round` rounds ties away from zero.
- **Python:** I copy neither its ties-to-even `round()` nor its `removeprefix`, which can't report a miss.

##### DevOps

DEVOPS/TOOLING PROPOSAL: Char and Str helpers, Float rounding, fixed decimals

I review each name by the diagnostic it makes, how it shows in autocomplete, and whether a wrong call fails at compile time or gives silently wrong output.

**Proposal A: Char classification goes on Char as methods, with the scope in the name**

These go in a sealed `CharOps` prelude trait, in the same pattern as `StrOps`. I reject a `std.char` module of free functions because the LSP cannot offer them after `c.`. Users type `c.is_` and expect the list to appear.

    fn is_ascii_digit(self) -> Bool          // '0'..'9'
    fn is_ascii_alpha(self) -> Bool          // a-z A-Z
    fn is_ascii_alphanumeric(self) -> Bool
    fn is_ascii_upper(self) -> Bool
    fn is_ascii_lower(self) -> Bool
    fn is_ascii_whitespace(self) -> Bool     // space \t \n \r \x0C
    fn is_whitespace(self) -> Bool           // Unicode White_Space (25 code points)
    fn to_digit(self, radix: Int) -> Option[Int]   // radix outside 2..36 panics

    fn scan_int(s: Str) -> Int {
        let mut n = 0
        for c in s.chars() {
            match c.to_digit(10) {
                Some(d) => { n = n * 10 + d }
                None => { return n }
            }
        }
        n
    }

Why put "ascii" in the name: a bare `is_digit` or `is_alpha` makes the reader guess the scope. Bare names also repeat fact 4, where the table calls `to_upper` "Unicode-aware" but the code is ASCII only. A name that says its scope cannot drift away from its implementation. `is_whitespace` has no `ascii_` because the Unicode White_Space set is small and fixed, so we can do it correctly at low cost. Full Unicode alpha, digit and case classes need large tables, so they wait for a real request.

The compiler adds hint rows to UnresolvedMethod. They are hints, not aliases, so the API still has one name for each operation:

    error[UnresolvedMethod]: no method `is_digit` on `Char`
      = help: did you mean `is_ascii_digit`? Blink has no Unicode digit class

Cross-language: Rust has both forms. The panel's stance against duplicates says we ship one.

**Proposal B: Str helpers**

    fn trim_start(self) -> Str                              // replaces trim_left
    fn trim_end(self) -> Str                                // replaces trim_right
    fn trim_by(self, pred: Fn(Char) -> Bool) -> Str
    fn trim_start_by(self, pred: Fn(Char) -> Bool) -> Str
    fn trim_end_by(self, pred: Fn(Char) -> Bool) -> Str
    fn strip_prefix(self, prefix: Str) -> Option[Str]
    fn strip_suffix(self, suffix: Str) -> Option[Str]
    fn repeat(self, n: Int) -> Str                          // n == 0 gives ""; n < 0 panics
    fn pad_start(self, width: Int, fill: Char) -> Str
    fn pad_end(self, width: Int, fill: Char) -> Str

    let id = "0042".trim_start_by(fn(c) { c == '0' })        // "42"
    let path = url.strip_prefix("https://") ?? url
    let cell = name.pad_end(12, ' ')

- **Rename trim_left and trim_right with the 3-step dance.** Step 1 adds `trim_start` and `trim_end`. Step 2 makes the old names a deprecation warning with a machine-applicable fix (`blink fix` rewrites them). Step 3 removes them and keeps a hint row. "Left" is wrong for right-to-left text. It also breaks pairing: if pad is `pad_start`, trim must be `trim_start`, or autocomplete splits the family.
- **Use a predicate, not `trim_matches(Str)`.** A Str argument is ambiguous. Python's `strip("ab")` treats it as a set of chars. Rust's `trim_matches("ab")` treats it as a substring. Users from each language get silently wrong output, and no diagnostic can catch that. A closure has one meaning, and it composes with Proposal A: `s.trim_by(fn(c) { c.is_ascii_digit() })`.
- **strip_prefix returns Option.** Python's `lstrip("https://")` trap removes a set of chars, not the prefix. Rust and Python 3.9's `removeprefix` both keep "did it match?" visible. Option lets the typechecker make the caller handle "no match".
- **fill is Char, not Str.** A multi-codepoint fill is then a compile-time type error, not a runtime panic or a quiet choice about truncation:

      error[TypeMismatch]: expected `Char`, found `Str`
        = help: use a single-quoted char literal: `'0'`

- **pad width counts codepoints, the same as `len`.** When `width <= len()`, the result is `self` unchanged. It never truncates, because a cut-off value in a report is a silent data bug. A negative width does the same as zero. The spec must say that width is not terminal columns (CJK text and combining marks differ). A `display_width` helper belongs to `std.term` later, not here.
- **Hint rows** cover `strip` and `lstrip` (to `trim_by` or `strip_prefix`), `ljust`, `rjust`, `padStart` and `pad_left` (to `pad_start` or `pad_end`), and `trim_matches` (to `trim_by`).

**Proposal C: Float rounding and fixed decimals**

    fn round(self) -> Float      // ties away from zero (C round, Rust f64::round)
    fn round_even(self) -> Float // ties to even (banker's rounding)
    fn floor(self) -> Float
    fn ceil(self) -> Float
    fn trunc(self) -> Float
    fn display_fixed(self, digits: Int) -> Str

    let total = 3.14159
    println("total: {total.display_fixed(2)}")        // "total: 3.14"
    let pct = (ratio * 100.0).round().truncate()       // Int via existing truncate

- **All five rounding methods return Float.** NaN and ±inf pass through unchanged, so nothing panics. The step to Int stays explicit, through `truncate()` or `to_int_checked()`.
- **Reject `round(digits)`.** `2.675.round(2)` cannot equal 2.68 in binary floating point. A method that looks decimal-exact and is not leads to bug reports nobody can fix. Rounding to a number of decimal digits is a text operation (`display_fixed`) or a money operation (`Decimal`, fact 10).
- **Name it `display_fixed`, not `to_fixed`.** Fact 5 says a `to_` method is only sugar over `From`, and rendering is not a conversion. In autocomplete, `display_fixed` sits next to `display()`, which is where people look for a text form. A hint row maps `to_fixed`, `toFixed`, `format` and `round(n)` to it. Interpolation stays free of format specs: `"{x.display_fixed(2)}"` works now because `Str: Display`.
- **display_fixed semantics.** The spec names this form as "a different form for that place" under the Float Text Form rule (fact 6).
  - It rounds the exact binary value to nearest, ties to even, the same as C `%.*f`. So `2.675.display_fixed(2)` is "2.67", and the spec states that example on purpose.
  - It never uses exponent notation: `1e20.display_fixed(1)` is "100000000000000000000.0".
  - `digits` must be in `0..=17`. Outside that range it panics and names the value.
  - NaN, inf and -inf render as "NaN", "Infinity" and "-Infinity", the same as Display.
  - A result whose digits are all zero has no sign: `(-0.001).display_fixed(2)` is "0.00", not "-0.00". This follows the Display rule that -0.0 renders as "0.0". A "-0.00" in a money column is a classic report bug.

**Proposal D (separate vote): zero-padding an Int**

`(-7).display().pad_start(4, '0')` gives "00-7". That output is silently wrong, and no lint can catch it because the sign is only known at run time. I propose:

    fn display_padded(self, width: Int) -> Str   // on Int: (-7).display_padded(4) == "-007"

The sign goes first, the zeros follow, and the result never truncates. If the panel rejects D, the Str `pad_start` doc must show this trap.

**Tooling summary**

- `blink fmt` needs no change, because every addition is a plain method call.
- Every addition is a method on its receiver type, so autocomplete covers it.
- Each wrong-language name gets a hint row, and the API itself stays at one name for each operation.
- The math module (sqrt, log, trig) stays separate. It should hold free functions, because the rounding methods above are the only Float operations a user expects after `x.`.

##### AI/ML

AI/ML panelist — Phase A proposal

Lens: can a model learn the surface from the spec alone, and does each name mean in Blink what it most often means in training data? If a name means one thing in Rust and another in Python, models will guess, and they will guess wrong at a steady rate.

P1. Char predicates are methods on Char, in a sealed `CharOps` prelude trait

    fn is_digit(self) -> Bool          // ASCII '0'..'9' only
    fn is_alpha(self) -> Bool          // Unicode Alphabetic
    fn is_alphanumeric(self) -> Bool   // is_alpha() || is_digit()
    fn is_whitespace(self) -> Bool     // Unicode White_Space
    fn is_upper(self) -> Bool          // Unicode Uppercase
    fn is_lower(self) -> Bool          // Unicode Lowercase
    fn is_ascii(self) -> Bool          // code point < 128
    fn to_digit(self, radix: Int) -> Option[Int]   // radix 2..36, else panic

- Method, not a `std.char` module. `c.is_digit()` is the main form in Rust, Kotlin, Swift and Python (`c.isdigit()`). A free function `char.is_digit(c)` is the Go shape. It also forces one more decision: whether to import. lib/std/char.bl keeps only the TryFrom impl.
- Only `is_digit` is ASCII. That keeps it in step with `to_digit(10)` and with `parse_int`. A tokenizer that accepts Arabic-Indic digits and then fails in `parse_int` is a latent bug. The other predicates follow Unicode, as the spec already promises for `to_upper`/`to_lower`. The spec is the target; the ASCII-only lib today is an impl gap.
- ASCII letters compose. `c.is_ascii() && c.is_alpha()` gives them. This avoids a second `is_ascii_*` family, which would double the surface and add a choice at every call.
- The radix trap. Rust writes `c.is_digit(10)`, so models will emit that. The compiler must answer with a fix-it: "`is_digit` takes no radix; use `c.to_digit(10).is_some()`".
- Invariant for the spec: `s.trim() == s.trim_matches(fn(c) { c.is_whitespace() })`. One definition of whitespace everywhere.

    fn scan_int(src: Str, start: Int) -> Int {
        let mut i = start
        while src.char_at(i).map(fn(c) { c.is_digit() }).unwrap_or(false) {
            i = i + 1
        }
        i
    }

P2. One naming axis: start/end. Rename `trim_left`/`trim_right` and do not add pad_left/pad_right

- Rust deprecated `trim_left` for `trim_start`, and JS deprecated `trimLeft` for `trimStart`. Recent training data says start/end, and the name stays correct for right-to-left text.
- The spec bans two names for one operation, so we rename; we do not alias. It is a 3-step migration: add `trim_start`/`trim_end`, migrate src and lib, then remove the old names.
- After removal, `trim_left` gets "did you mean `trim_start`".
- Padding uses the same axis: `pad_start`/`pad_end`, as in JS `padStart` and Kotlin `padStart`. With `trim_start` beside `pad_left`, the model has to remember which of two words goes with each verb. That is exactly where it guesses.

P3. Pad, repeat, prefix and suffix

    fn pad_start(self, width: Int, fill: Char) -> Str
    fn pad_end(self, width: Int, fill: Char) -> Str
    fn repeat(self, count: Int) -> Str
    fn strip_prefix(self, prefix: Str) -> Option[Str]
    fn strip_suffix(self, suffix: Str) -> Option[Str]

Pad:
- `fill` is required. Blink has no default arguments, and a fixed arity means one less choice to make.
- `fill` is a `Char`, not a `Str`. This removes the JS multi-codepoint fill case (truncated fill strings) completely.
- Width counts codepoints, like `len()`. It is not terminal display width; the spec must say that CJK and emoji columns can misalign.
- When `width <= self.len()`, which includes a negative width, the string comes back unchanged. Pad never truncates.

Repeat: `count == 0` gives `""`. `count < 0` panics with the count in the message. That matches checked-by-default, though it is not Python's quiet `""`.

Prefix and suffix:
- The names and the `Option` return are the same as Rust's. That gives check-and-take in one call, the main tokenizer pattern: `match arg.strip_prefix("--") { Some(name) => ..., None => ... }`.
- Python's `removeprefix` behaviour is `s.strip_prefix(p).unwrap_or(s)`.

    io.println("{name.pad_end(12, ' ')}{qty.display().pad_start(6, ' ')}")

P4. Trim by a closure. Reject a character set passed as `Str`

    fn trim_matches(self, pred: fn(Char) -> Bool) -> Str
    fn trim_start_matches(self, pred: fn(Char) -> Bool) -> Str
    fn trim_end_matches(self, pred: fn(Char) -> Bool) -> Str

- Why not a `Str` set. The same call means two things in training data. Python `"xxaxx".strip("ax")` treats the argument as a set of characters. Rust `s.trim_matches("ax")` treats it as a substring. Whichever meaning Blink picks, about half of the generated code is quietly wrong. A closure has one meaning.
- A set still costs one line: `s.trim_matches(fn(c) { "-_".contains(c.to_str()) })`.
- Reject `strip(chars)`. It is the Python name with the Python set meaning; it adds a second spelling and brings back the ambiguity.

P5. Float rounding: `round`, `floor`, `ceil` with no argument, all returning `Float`

    fn round(self) -> Float   // nearest; ties away from zero (C/Rust): 2.5 -> 3.0, -2.5 -> -3.0
    fn floor(self) -> Float
    fn ceil(self) -> Float

- NaN, `inf` and `-inf` come back unchanged, and `-0.0` stays `-0.0`. These functions are total.
- To get an `Int`, write `x.floor().truncate()`. `truncate` already exists and panics on NaN/inf.
- The `-> Float` vs `truncate() -> Int` asymmetry is a known trap. Passing `x.round()` where an `Int` is expected must trigger a type-error hint naming `.truncate()`. That is a compile-time catch, so it costs little.
- I reject `round(digits)`. Rounding a binary float to decimal places gives a value that still cannot be shown exactly, which is the classic `round(2.675, 2) == 2.67` surprise. The only real use is display, and P6 covers that. Money goes to `Decimal`.
- Math module ticket: these three are inherent Float methods, like the Int `abs`/`min`/`max` table. A later `math` module (sqrt, trig, constants) sits next to them and should not repeat them.

P6. Fixed-decimal text: `fixed(digits)`. Interpolation stays without format specs

    fn fixed(self, digits: Int) -> Str

    let price = 3.5
    io.println("total: {price.fixed(2)}")   // total: 3.50

- Name. `to_fixed` (JS `toFixed`) would collide with the rule that `to_` means From/TryFrom sugar. Models will emit `to_fixed` often, so the compiler must reply "Blink spells this `.fixed(2)`". That one hint pays for the deviation.
- Spec placement. This is the "named different form" the Float Text Form rule allows. The spec must list it there.

Semantics:
- The result is correctly rounded from the exact binary value, with ties away from zero. This is the same rule as `round()`, so `x.fixed(0)` shows the same digits as `x.round()`. One rounding rule to learn, not two.
- It never uses exponent form. JS switches to `1e+21`; Blink prints every digit.
- `digits < 0` panics. Very large `digits` give exact expansions.
- NaN, `inf` and `-inf` render as in Display. `-0.0` renders as `0.00`, matching Display's no-sign zero; a report must not print `-0.00`.
- For a value that rounds to zero, I propose dropping the sign: `(-0.001).fixed(2)` gives `0.00`. JS and Python print `-0.00` here, so this goes against training data. My reason is that a sign on a zero in an aligned money column always looks like a bug to the reader. The panel should confirm or overturn this.

No Int padding method. `"{n}".pad_start(3, '0')` works for n >= 0. A negative n gives `"0-7"`. The spec example must show that caveat; I would not add `zero_pad` until friction asks for it.

Token and decision count. All of this adds 8 Char methods, a net 10 Str methods (12 added, 2 removed), and 4 Float methods. It adds no new syntax and no format mini-language.

At each place where Blink differs from the most-trained spelling (`to_fixed`, `is_digit(10)`, `trim_left`, `round` used as an `Int`), the compiler names the fix. So the spec alone, plus the diagnostics, is enough for a model to learn the API.

##### Minimalism

Min (minimalism): proposal

Position: add what Blink cannot express today. Reject what is only shorter to type. Every name below either fixes a correctness trap or does a job user code cannot do well. Everything else waits for friction logs, as decisions/string-methods.md Q2 intended.

**P1. Char predicates: ASCII only, and the name says so**

```blink
impl Char {
    fn is_ascii_digit(self) -> Bool         // '0'..='9'
    fn is_ascii_alpha(self) -> Bool         // 'a'..='z', 'A'..='Z'
    fn is_ascii_alphanumeric(self) -> Bool
    fn is_whitespace(self) -> Bool          // exactly the set trim() strips
}
```

```blink
let mut i = 0
while i < src.len() && src.char_at(i).unwrap().is_ascii_digit() {
    i = i + 1
}
```

- These are methods on Char, not functions in `std.char`. A tokenizer should not need an import to ask "is this a digit". Str methods also live on the type.
- Why ASCII with honest names: fact 4 shows the risk. The spec says `to_upper` is "Unicode-aware" but the code is ASCII only. If we add `is_alpha` now and implement it in ASCII, we repeat that bug. If we add it now and make it Unicode-correct, we take on Unicode category tables before any user has asked for them. Tokenizers and number scanners want ASCII. A Unicode `0`–`9` lookalike (for example `'٣'`) passing `is_digit` and then failing `parse_int` is a real bug. If someone needs Unicode `is_alpha` later, we can add it without breaking anything. Removing a wrong one later would break code.
- `is_whitespace` has no `ascii_` prefix. It must mean the same set `trim` uses, so one definition covers both methods. The spec must write that set down.
- Rejected: `is_upper`, `is_lower` (no friction shows a need), `to_digit` (`c.to_int() - '0'.to_int()` after `is_ascii_digit` is one line and clear).
- Cross-language: Rust has both the `is_ascii_*` and Unicode families. Go puts Unicode in a separate package. We ship the half that is needed.

**P2. Str: five methods, no set-trim, no new trim names**

```blink
fn repeat(self, n: Int) -> Str              // n < 0 panics; n == 0 gives ""
fn pad_left(self, width: Int, fill: Char) -> Str
fn pad_right(self, width: Int, fill: Char) -> Str
fn strip_prefix(self, prefix: Str) -> Option[Str]
fn strip_suffix(self, suffix: Str) -> Option[Str]
```

```blink
let row = "{name.pad_right(12, ' ')}{"{qty}".pad_left(5, ' ')}"
match line.strip_prefix("# ") {
    Some(title) => print(title)
    None => {}
}
```

- `fill` is a `Char`, not a `Str`, so a multi-codepoint fill cannot happen. You cannot pass one.
- `width` counts codepoints, the same unit as `len`. When `width <= self.len()`, the result is `self` unchanged. Padding never truncates. Negative width behaves like 0, because `width - s.len()` arithmetic goes below zero in normal use.
- `repeat` panics on negative `n`, as Go does. Padding already handles the clamped case, so a negative count passed to `repeat` is a bug.
- Known edge: `"{-7}".pad_left(3, '0')` gives `"0-7"`. The spec must state this. Signed zero-padding is not worth an `Int` method.
- `strip_prefix`/`strip_suffix` return `Option`. Today the user writes a check, then a slice, and must get the codepoint offset right. A wrong offset is a silent bug, not a missing convenience, so these earn their place.
- Rejected: `trim_start`/`trim_end`. `trim_left`/`trim_right` already exist, and the spec opposes two names for one operation.
- Rejected: `trim_matches(Str)`, `strip(chars)` and a predicate form. A predicate version needs three methods (both ends, start, end) and adds closure-taking APIs to StrOps. The cases the tickets name are covered by `trim_right` (newlines), `strip_prefix`/`strip_suffix` (quotes, markers) and a `char_at` loop with P1 predicates (tokenizers). Revisit when a friction log shows a case none of these cover.

**P3. Float: three rounding operations, Float to Float, and no `round(digits)`**

```blink
fn round(self) -> Float   // halves go away from zero: 2.5 -> 3.0, -2.5 -> -3.0
fn floor(self) -> Float
fn ceil(self) -> Float
```

- These are foundational. Today `floor` of a negative number needs `truncate()` plus a sign fix, and it panics on NaN.
- They return `Float`, so they are total. NaN, inf and -0.0 come back unchanged. They add no new panic paths. To get an Int, write `x.floor().truncate()`. Two existing pieces combine, and the conversion stays in one place.
- Ties go away from zero, as in C `round` and Rust `f64::round`. Python uses half-to-even. Whichever rule the panel picks, the spec must state it.
- Rejected: `round(digits)`. On binary floats it does not do what people expect: `2.675.round(2)` gives `2.67`. Anyone who needs decimal digits wants P4 (for display) or `Decimal` (for money, fact 10).
- I flag one wart and do not fix it here: `truncate()` returns an Int, unlike these three. That is a naming question for the conversion audit.
- This does not overlap with the math module ticket. `sqrt`, `log` and trig stay there. These three are methods on the value, the same way Rust and JS `Math` split it.

**P4. One fixed-decimal display form**

```blink
fn fixed(self, digits: Int) -> Str
```

```blink
print("total: {price.fixed(2)}")   // "total: 3.50"
```

- This is the one case where user code cannot do it right. Correct fixed output needs the exact binary-to-decimal expansion. A hand-written loop gets ties wrong.
- The rounding is correct for the exact stored value, with ties to even on that value. This matches `printf("%.*f")`, Rust `{:.2}` and Python `f"{:.2f}"`. So `2.675.fixed(2)` gives `"2.67"`, because the stored value is below the half. The spec must give this example so nobody files it as a bug.
- `digits < 0` panics. `digits == 0` gives no decimal point (`"4"`).
- The sign follows the sign bit: `(-0.001).fixed(2)` gives `"-0.00"`. C, Rust, Python and JS all do the same.
- NaN and inf use the same spelling as Display.
- The name is `fixed`, not `to_fixed`. Fact 5 reserves `to_` for From/TryFrom sugar, and rendering is not a conversion. Under fact 6 this is the named second text form. The spec says so in one sentence in "Float Text Form".
- Interpolation stays free of format specs. `"{x.fixed(2)}"` works because Str is Display. This keeps the existing decision.
- Rejected: Int padding methods. `"{n}".pad_left(3, '0')` covers `007`.

**Budget**

- Added: 13 names (4 Char, 5 Str, 4 Float).
- Rejected: 11 names asked for in the tickets (`is_alpha`, `is_upper`, `is_lower`, `to_digit`, `trim_matches`, `strip`, `trim_start`, `trim_end`, `round(digits)`, `to_fixed`, Int pad).
- Each addition either replaces a hand-written loop that is easy to get wrong or does something Blink cannot express today. Each rejection is a shortcut we can add later without breaking anything, if the friction logs ask for it. When unsure, skip it.

#### Phase B — Debate (round 1)

The moderator grouped the Phase A proposals into seven points of agreement (U1–U7: Char methods not a `std.char` module; `strip_prefix`/`strip_suffix` returning `Option[Str]`; pad with a required `Char` fill, codepoint width, never truncating; `round`/`floor`/`ceil` returning `Float` with ties away from zero; no `round(digits)`; a fixed-decimal renderer named as the Float Text Form's different form; no interpolation format specs) and eleven contested questions. All six panelists signalled "STABLE, READY TO VOTE" after one round.

##### Systems

SYSTEMS (Sys) — Phase B round 1

U-points: no objection to any of U1–U7.

Q1. Hold 1A with a merged whitespace rule.
Set: is_ascii_digit, is_ascii_alpha, is_ascii_alphanumeric, is_ascii_upper, is_ascii_lower (PLT's set), plus is_ascii (cheap and useful; I will not fight for it). I drop is_ascii_whitespace.
Merged whitespace rule (1A'): `is_whitespace` is Unicode White_Space (25 codepoints), AND `trim`/`trim_left`/`trim_right` strip exactly `is_whitespace`. This keeps PLT's law W (one whitespace definition) and gives Web/AI-ML the Unicode set they want for NBSP. It is the Rust model. Cost: the ASCII path is one compare plus a 6-entry check; non-ASCII is a switch on a fixed set — no table. Behaviour change: trim then also strips \v, \f, U+0085, NBSP, U+3000; today's 4-char impl becomes a bug against the spec, fixed in the same change.
Against Web/AI-ML (1B, "`c.is_ascii() && c.is_alpha()` composes, avoids a second family"): the composition is fine, but 1B mixes sets under one naming pattern — `is_digit` ASCII, `is_alpha` Unicode, so `is_alphanumeric` is half and half and its name gives no clue. Unicode `is_alpha`/`is_upper`/`is_lower` also need range tables tied to a pinned Unicode version (PLT); that is a separate std.unicode decision, not v1. 1A leaves the plain names free for it.

Q2. Hold 2A (`to_digit(radix)`, radix outside 2..=36 panics).
Against Web ("every user passes 10"): a literal 10 constant-folds; the range check vanishes at -O2. Zero runtime cost, one token of typing. Against Min ("`c.to_int() - '0'.to_int()` is one line"): true for base 10; hex needs three ranges, and that is where hand-written scanners get it wrong.

Q3. Change position: 3A -> 3B, PLT's names `trim_by` / `trim_left_by` / `trim_right_by` (axis follows Q4).
DevOps and AI-ML are right: a Str set means "set" in Python and "substring" in Rust, and the wrong guess is silent. My own cost objection was weak: trim calls the predicate only on removed codepoints plus one per end, so an indirect call there is noise. Against Min ("no closure APIs in StrOps"): List already takes closures; the user-side alternative is a `char_at` loop with a manual codepoint offset — the same silent-bug class Min accepts strip_prefix to fix.

Q4. Hold 4A, low conviction.
Systems has no stake in the spelling. I accept PLT's condition: start/end only as a whole-family rename (trim and pad together, 3-step, no alias), voted on its own. Either way, trim, trim_*_by and pad must share one axis.

Q5. Change position: 5A -> 5B (`n <= 0` gives "").
Two of our own decisions already clamp non-positive counts: `with_capacity` (F4) and padding's negative width (U3, all six). If `repeat` panics, `"-".repeat(width - s.len())` panics where the same arithmetic in `pad_left` does not. One stdlib rule for non-positive counts beats my "negative count is a bug". Overflow of `byte_len * n` still panics.

Q6. Hold 6A.
Against DevOps (round_even, trunc): ties-to-even is for money, and money is Decimal's job (fact 10). C `roundeven` is C23 and missing from older libm, so it would need a runtime fallback. `trunc` (Float) beside `truncate` (Int) is two names one letter apart with different types.

Q7. Hold 7A `display_fixed`.
Against Web/Min/AI-ML (`fixed` is short, near JS toFixed): `fixed` reads as an adjective or state ("is it fixed?"), and nothing in it says it returns Str. `display_` sorts next to `display()` in autocomplete and names the family (Q11's `display_padded` joins it). Five extra characters to type. A hint row maps `to_fixed`/`fixed` to it.

Q8. Hold 8A (ties to even on the exact value).
Against AI-ML ("one rounding rule with round()"): the rules differ only on exact binary ties (0.125, 2.5). 8A matches printf, Rust `{:.2}`, and Python — every reference a user diffs a report against. It also makes the conformance test trivial: compare against `%.*f` from glibc/musl on millions of random doubles. 8B has no reference to test against.

Q9. Concede: 9A ("0.00").
Display renders -0.0 as "0.0" (sections/03_types.md, Float Text Form, "Zero"). My "-0.00" would make the named second form disagree with the main one on the sign of zero. PLT's precise rule: write "-" only when the rounded text has a non-zero digit.

Q10. Hold: digits < 0 panics; no upper bound; never exponent form; digits == 0 gives no ".".
Against Web (0..=20) and DevOps (0..=17): a cap is an extra panic path with no reason behind it. 17 confuses significant digits with decimal places — 1e-20.display_fixed(25) is a legitimate request beyond 17. An exact algorithm (Ryu-printf) handles any digits; output size is at most 310 + digits bytes, known before the allocation, so the cost is in the caller's hands.

Q11. Hold 11A, and take PLT/DevOps's name: Int `display_padded(width) -> Str`, sign first, width counts the sign, never truncates.
Against Min/Web/AI-ML ("document the 0-7 trap"): the correct user-side code must branch on sign, and the `abs()` route overflows at MIN (PLT). That is silent wrong output in a report column, not a missing convenience. It is one method, written in Blink, one allocation.

STABLE, READY TO VOTE

##### Web/Scripting

Web/Scripting, Phase B round 1

No objection to U1 to U7. I accept PLT's U2 addition: an empty argument gives `Some(self)`.

**Q1. Char names: I move from 1B to 1A, and I propose a merged rule for whitespace (1C).**
- Sys and Min argued that a bare `is_alpha` must either ship Unicode tables now or repeat the false `to_upper` claim (fact 4). I accept that. For a JS dev, `is_ascii_digit` is no harder to read than `is_digit`, and the name answers the "is `é` a letter?" question before anyone asks it on Stack Overflow.
- The one surprise I feared, a bare `is_alpha` that rejects `é`, cannot happen when the name says ASCII.
- Members: `is_ascii`, `is_ascii_digit`, `is_ascii_alpha`, `is_ascii_alphanumeric`, `is_ascii_upper`, `is_ascii_lower`. This is the Sys/PLT list.
- **Whitespace merge (1C).** I take PLT's law W, one whitespace, and give it the Unicode White_Space set (25 codepoints) that Sys and DevOps chose for `is_whitespace`:
  - `is_whitespace` is Unicode White_Space.
  - `trim`, `trim_start`/`trim_left` and `trim_end`/`trim_right` strip exactly that set.
  - So `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })` holds.
- **Why.** JS `trim()` and Python `strip()` both remove NBSP and the other Unicode spaces, so a web dev expects this. Today's set of 4 does not even remove form feed (F2). Sys says White_Space is a fixed switch, so it costs almost nothing.
- **What this removes.** With one set, `is_ascii_whitespace` is not needed. Two whitespace definitions is the duplicate PLT warns about.
- **Cost.** This widens what `trim` removes. The spec never listed the set, so I call it a fix that pins the set, not a break.

**Q2. `to_digit`: I concede to 2A, `to_digit(radix)`.**
- Sys, PLT, DevOps and AI/ML want this form, and Rust users write `c.to_digit(10)` from memory. My worry, that every caller must pass `10`, is a small price.
- Min (2C) proposed `c.to_int() - '0'.to_int()` instead. That is exactly the byte arithmetic the ticket was filed to remove.

**Q3. Trim by set: I concede to 3B, the predicate form.**
- AI/ML and DevOps showed that a Str argument means a set in Python and a substring in Rust. No name I pick, including `trim_chars`, stops a Rust user from passing `"ab"` and expecting the substring meaning.
- A closure has one meaning, and it composes with Q1: `s.trim_by(fn(c) { c.is_ascii_digit() })`.
- Name: `trim_by`. AI/ML's `trim_matches` is a false friend, because Rust's `trim_matches` takes a pattern, not only a predicate. The one-sided names follow Q4.
- Against Min's 3C: stripping leading zeros, quotes and dashes is everyday work in scripts. A hand loop over `char_at` for that is the friction the ticket reports.

**Q4. Naming axis: I hold 4B, start/end, by the 3-step rename.**
- Sys and Min said start/end duplicates left/right. That was true of my Phase A wording only if it added an alias. 4B removes the old names, so one operation keeps one name.
- PLT's condition is right: this is a whole-family rename and needs its own vote.
- JS (`trimStart`), Rust (`trim_start`) and Kotlin (`padStart`) all moved to start/end. Blink is pre-1.0, and DevOps's `blink fix` rewrite makes the migration cheap.
- If 4B loses, pad must be `pad_left`/`pad_right`, so the family never mixes axes.

**Q5. `repeat` with negative n: I hold 5B, n <= 0 gives "".**
- Min has the strongest argument: padding now covers the width-arithmetic case, so a negative `repeat` count is likely a bug.
- But F4 is a recorded vote: `with_capacity` treats `n <= 0` as empty and states that rule for counts. Two count rules in one stdlib is the bigger trap. I agree with PLT.
- This is low stakes for me, and I will not block on it.

**Q6. Rounding: I hold 6A, only round, floor and ceil.**
- DevOps's `round_even` is for money, and money goes to `Decimal`.
- `trunc` (returns Float) beside `truncate` (returns Int) would cause confusion, as Sys and PLT say.

**Q7. Renderer name: I move to 7A, `display_fixed`.**
- DevOps's autocomplete argument wins. A user who wants text types `x.display` and sees `display_fixed` next to it. A bare `fixed` reads like an adjective or the verb "fix".
- It also names a family, `display_*` for rendering, if Q11 ever adds an Int method.
- A hint row for `to_fixed` and `toFixed` covers the JS reflex.

**Q8. Ties in the renderer: I hold 8B, ties away from zero.**
- Sys and Min cite C `printf` and Python. JS goes the other way: `toFixed` picks the larger n on a tie, applied to the magnitude, so `(2.5).toFixed(0)` is "3" and `(0.125).toFixed(2)` is "0.13". The C family does not decide this.
- The deciding case is inside Blink. Under 8A, `2.5.display_fixed(0)` is "2" while `2.5.round()` is 3.0. Two rounding rules in one type will generate the question "why does display_fixed disagree with round?"
- The C argument also gives no free implementation. Sys already requires our own exact algorithm, not the libc one, so either tie rule costs the same.

**Q9. Sign on an all-zero result: I hold 9A, "0.00".**
- PLT gave the best argument: Display already renders `-0.0` as `0.0`. Keeping a sign in `display_fixed` would put two zero rules in one spec.
- Sys and Min say C and Python print "-0.00". That is true, and it is the bug report every report generator gets.

**Q10. Digits range: I concede to no upper bound.**
- `digits < 0` panics. Any `digits >= 0` is valid, and large values give the exact expansion followed by zeros (AI/ML).
- Output never uses exponent form (DevOps, AI/ML).
- `digits == 0` gives no `.`.
- I copied my cap of 20 from JS without a reason. DevOps's 17 would reject `0.1.display_fixed(20)`, which a user may want in order to see the stored value.

**Q11. Int zero padding: I hold 11B.**
- DevOps and PLT note that the trap fails silently at run time. True, but IDs, clock times and counters are non-negative in the 90% case.
- Signed money uses Float or `Decimal`, not Int.
- The pad doc shows `"0-7"`. If friction appears, `display_padded` fits the 7A family without a break.

STABLE, READY TO VOTE. Request: put the 1C merge (Unicode White_Space for both `trim` and `is_whitespace`) on the ballot, next to the PLT and Sys variants.

##### PLT

PLT, Phase B round 1

I accept U1 to U7.

**Q1: I hold 1A, and I propose a merged rule for whitespace.**

- Members: digit, alpha, alphanumeric, upper and lower. I accept Sys's `is_ascii`.
- 1B, the Web/AI/ML position, is not a rule. Its strongest argument, from AI/ML, is that "the spec already promises Unicode for `to_upper`, so the spec is the target." But 1B makes `is_digit` ASCII and `is_alpha` Unicode. The name then no longer tells the reader the set, and `is_alphanumeric = is_alpha || is_digit` becomes Unicode letters plus ASCII digits. That union has no meaning in Unicode and none in ASCII. Unicode `is_alpha` also brings in a Unicode version that the spec must pin, and Min is right that we can add it later without breaking anything.
- Whitespace: Sys and DevOps add both `is_whitespace` (Unicode White_Space) and `is_ascii_whitespace` (= trim's set). That satisfies my law W by naming the two sets. F2 shows the spec never listed trim's set, so we can do better.
- **Merged option 1A-W:** the spec defines `trim`, `trim_left` and `trim_right` to strip exactly `is_whitespace`, which is Unicode White_Space (a fixed set of 25 codepoints, no table). There is no `is_ascii_whitespace`.
  - That gives one predicate and one set, and law W holds: `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`.
  - Rust, JS and Python 3 all trim White_Space, so NBSP no longer survives `trim`.
  - Cost: a change in behaviour for `\x0B`, `\x0C`, NBSP and similar codepoints, which today survive `trim`. That is a fix to an unspecified gap, not a break of the spec.

**Q2: I hold 2A.**

Web says "every user passes 10." That costs one token, and in return hex and octal scanners don't need hand-rolled tables. Min's `c.to_int() - '0'.to_int()` is right for base 10 only, and it repeats the byte arithmetic the ticket complains about.

**Q3: I hold 3B.**

- Sys argues cost: an indirect call for each codepoint. That is a codegen question. A closure literal at the call site can be inlined, and a typing rule should not bend to fit today's codegen.
- On generality: a Str set is a special case of a predicate (`fn(c) { set.contains(c.to_str()) }`), but a predicate can't be written as a Str set. If we ship `trim_chars` now and a predicate form later, Blink has two methods for one job, which is the duplicate the audit forbids.
- DevOps and AI/ML make the decisive point: a Str argument means a set in Python and a substring in Rust, so the same code goes silently wrong for one group.
- Min says no friction shows a need. The ticket itself is that friction, since it names `trim_matches` and `strip(chars)`.
- **Suffix:** I prefer `_by` over AI/ML's `_matches`. In Rust, `_matches` takes a pattern that can be a Str, so the name invites `trim_matches("x")`. `_by` is the ML/Haskell mark for a function argument (`sortBy`). The axis word follows Q4.

**Q4: I change to 4B, on the condition I stated in Phase A.**

- The condition: it is a whole-family 3-step rename with no lasting alias. Steps 1 and 2 have both names only as long as the migration lasts. Step 3 removes `trim_left` and `trim_right`, and a hint row stays.
- Why I change: Web, DevOps and AI/ML are right that "left" is false for right-to-left text, because `trim_left` strips the logical start, which shows on the right. Blink is codepoint-oriented, so its operations work in logical order, and the name should say so. One axis for trim and pad is required in any case.
- Sys and Min say the rename adds a second name. It doesn't, if step 3 is part of the vote.

**Q5: I concede to 5A, so `n < 0` panics.**

- Sys and Min convinced me, and on the record F4 doesn't carry over to `repeat`. Capacity is a hint, where `n <= 0` has a natural meaning ("no reservation"). A repeat count has no negative meaning, so clamping it would hide a bug.
- The law becomes: for `n >= 0`, `s.repeat(n).len() == s.len() * n`.
- Padding stays consistent with this. `width` is a lower bound, `result.len() == max(width, s.len())`, so a negative width has a meaning and is trivially met.

**Q6: I hold 6A.**

- DevOps's `round_even` is banker's rounding, which belongs to money, and money goes to `Decimal`.
- A `trunc` returning Float next to `truncate` returning Int is two names one letter apart, with different types.

**Q7: I hold 7A, `display_fixed`.**

- `x.fixed(2)` sits beside `round` and `floor` in autocomplete and reads as a Float-to-Float operation, because "fixed" is an adjective about the value. The `display_` prefix states a fact about the type: the result is a rendering, from the same family as `display()`.
- Web's point about JS discoverability is met by DevOps's hint row (`to_fixed` and `toFixed` point to `display_fixed`).

**Q8: I change to 8B, ties away from zero.**

- AI/ML has the stronger argument, and it is a law: `x.display_fixed(0) == x.round().display_fixed(0)` for every finite `x`. Ties to even breaks it, because 2.5 renders as "2" but rounds to 3.0. A text form that disagrees with the language's own `round` is an incoherence inside Blink. Matching printf only buys agreement outside it.
- The spec fixes output, not algorithm, so Sys's printf concern is an implementation note. Ryu-printf does either rule.
- General rule: round the exact binary value to `digits` places, with the tie rule of `round`. Ties occur only on exact values such as 0.125 or 2.5, and `2.675` still gives "2.67".

**Q9: I hold 9A, no sign on an all-zero result.**

- Min and Sys say C, Rust, Python and JS print "-0.00". But Blink's Float Text Form already renders `-0.0` as `0.0`, so dropping the sign follows Blink's own rule for zero. Following C here would give Blink two rules for the sign of zero.
- The shown digits do not support a sign. Under 8B and 9A both, the Q8 law holds for -0.4: both sides give "0".

**Q10: `digits < 0` panics, with no upper bound.**

- The exact expansion of any binary64 value is finite (at most 1074 fraction digits), so every `digits` has a defined result. Large values only add exact digits or zeros.
- DevOps's cap at 17 makes `1e-20.display_fixed(20)` panic for no reason. Web's 20 is just as arbitrary.
- The form never uses an exponent, and `digits == 0` gives no `.`.
- NaN and ±inf render as Display does: `NaN`, `inf` and `-inf` (F3 corrects DevOps).

**Q11: I hold 11A, and I take Sys's name `display_zero_padded(width)`, which states the fill.**

- Web and AI/ML say IDs are rarely negative. "Rarely" is the problem: `"{n}".pad_left(3, '0')` is a composition that gives silently wrong output for part of the type's domain. A doc note doesn't make an unsound composition sound.
- The rules: zeros go after the sign, `width` counts the sign, and the result never truncates.

STABLE, READY TO VOTE. Please put my merged option 1A-W (trim's set is defined as `is_whitespace` = Unicode White_Space, with no `is_ascii_whitespace`) on the ballot beside the Sys/DevOps two-predicate form and the Min form, where `is_whitespace` is trim's ASCII set.

##### DevOps

DevOps, Phase B round 1

First, a correction to my own Phase A text (F3): the fixed renderer writes NaN, inf and -inf exactly as Display writes them. My "Infinity" text was wrong.

I agree with U1 to U7. I propose one addition, U8. Every place where Blink's spelling differs from the most common foreign spelling gets a hint row on UnresolvedMethod or TypeMismatch. The rows cover: `to_fixed`/`toFixed`, `c.is_digit(10)`, `is_digit`/`is_alpha`, `strip`/`lstrip`/`ljust`/`rjust`/`padStart`, `trim_matches("..")`, `round(2)`, and `x.round()` used where Int is expected (hint: `.truncate()`). AI/ML asked for the same thing. These are hints, not aliases, so the API keeps one name for each operation.

**Q1: 1A. Members as Sys proposes, including `is_ascii` and `is_ascii_whitespace`.**
Web and AI/ML say that `is_ascii() && is_alpha()` avoids a second family. Their 1B gives `is_digit` ASCII scope and `is_alpha` Unicode scope. Nothing in either name tells the reader which is which, and only a hover in the LSP would show it. That is the `to_upper` "Unicode-aware" problem again (fact 4), only built in from the start. 1B also requires Unicode tables and a pinned Unicode version, which PLT pointed out, before anyone has asked for them.
On whitespace I side with Sys, not PLT's law W. A name that says "whitespace" but holds only 4 ASCII codepoints is a false name. Law W still holds under an honest name: `s.trim() == s.trim_by(fn(c) { c.is_ascii_whitespace() })`. The spec lists that set once, and both definitions point to it.

**Q2: 2A, radix argument.**
Web says every caller will pass `10`. It is two visible characters, and hex digits are real tokenizer work (JSON `\u` escapes, color codes). Min's alternative, `c.to_int() - '0'.to_int()`, works only after a separate check, and nothing ties the check to the arithmetic. With `Option[Int]`, the check and the value come from one call, the same shape as `strip_prefix`.

**Q3: 3B, predicate form. My names follow the Q4 outcome (`trim_by` / `trim_{start,left}_by` / `trim_{end,right}_by`).**
Against 3A, Web says `trim_chars` puts "set" in the name. The name helps, but the call site `s.trim_chars("ab")` reads the same as Rust's substring `trim_matches("ab")`. A user who misreads it gets wrong output and no diagnostic. A closure cannot be misread that way.
Sys's cost argument (one indirect call per codepoint) applies only at the trimmed edges, not to the whole string.
Min's 3C leaves the "0042" and `"-_"` cases from the ticket as hand-written `char_at` loops, and those loops have off-by-one bugs.
I rank AI/ML's `trim_matches` name second. With a closure-only argument, `s.trim_matches("ab")` gives a clear TypeMismatch, so it is safe, but `_by` says "predicate" on its face.

**Q4: 4B, rename to start/end by the 3-step protocol.**
PLT and Min call this churn. It is one step that `blink fix` can apply mechanically, followed by a permanent hint row. A rename is not a second name for the same operation, because the old name goes away.
My hard line is no mixed family. `trim_left` next to `pad_start` splits autocomplete and makes every user guess which axis a verb uses. If the panel picks 4A, I accept 4A over any mixed result. Both pad and the predicate trims then use left/right.

**Q5: I concede to 5B (`n <= 0` gives "").**
PLT's F4 argument wins on consistency: the stdlib then has one rule for non-positive counts. The main use is also the deciding case: `"-".repeat(width - s.len())` goes negative in normal use, the same reason pad clamps a negative width. One rule is easier to document than "pad clamps but repeat panics".

**Q6: I concede to 6A.**
Sys and PLT are right, and the argument comes from my own domain: `trunc` (to Float) and `truncate` (to Int) side by side in autocomplete is a trap I would reject anywhere else. `round_even` waits for a request. Money already goes to `Decimal`.

**Q7: 7A, `display_fixed`.**
Web, AI/ML and Min say `fixed` is shorter. As a bare word, `fixed` can read as a predicate ("is it fixed?") or as a fixed-point conversion. `display_fixed` sits next to `display()` in the completion list, which is where people look for text forms, and it says "this is rendering", as fact 5 asks. The hint row catches `to_fixed` either way, so the shorter name gains nothing at the diagnostic layer.

**Q8: 8A, ties to even on the exact value.**
AI/ML wants one rounding rule. In practice, though, people diff report output against Python, Rust or C (`printf %.2f`) in golden tests. With 8B, Blink disagrees with all three on `0.125` to 2 places. A golden-test difference on exact ties takes a long time to track down. The mismatch with `round()` shows only on exact ties, and the spec can state it in one sentence.

**Q9: 9A, no sign on an all-zero result, but held weakly.**
Min and Sys say that every major language prints "-0.00", and that is true. Blink's Display already breaks with C on zero, because it renders -0.0 as "0.0". 9A carries that rule forward, so the two text forms agree with each other. I would accept 9B if the panel prefers to match training data. Either way, the spec must give the example.

**Q10: I drop my 0..=17 cap.**
`digits < 0` panics and there is no upper bound, as Sys, PLT and Min propose. A cap is an arbitrary number that users would then file bugs against. The spec must state two things explicitly: the output never uses exponent form (`1e21.display_fixed(0)` prints all 22 digits), and `digits == 0` writes no `.`.

**Q11: 11A as an optional sub-vote; 11B is my fallback.**
Its strongest support is PLT's point that the `abs()` workaround overflows at MIN, so even a careful user gets it wrong for one value. "0-7" is silently wrong output, and no lint can see the sign at compile time. If 11B wins, the pad doc must show the "0-7" case.

STABLE, READY TO VOTE

##### AI/ML

AI/ML — Phase B round 1

No objection to U1–U7.

Q1. I move from 1B to 1A.
Sys, PLT, DevOps and Min win this. Under 1B a model must learn a split rule: `is_digit` is ASCII, and `is_alpha` is Unicode. Neither name shows which one it is. That is a pure memorisation point, and it is the same kind of hidden scope that already broke `to_upper`. With `is_ascii_*`, the name carries the rule. Rust-trained code already writes `is_ascii_digit` in tokenizers. Python-trained `is_digit` gets DevOps's hint row.
- Members: digit, alpha, alphanumeric, upper, lower. I drop my `is_ascii`; `c.to_int() < 128` covers it.
- On plain `is_whitespace`, I propose a merged option, W-U:
  - `is_whitespace` is Unicode White_Space (the fixed 25 codepoints, as Sys and DevOps propose).
  - `trim`, `trim_left`/`trim_start` and `trim_right`/`trim_end` strip exactly that set. That keeps PLT's law W: `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`.
  - No `is_ascii_whitespace`.
- Why W-U and not "is_whitespace = trim's 4-char ASCII set" (PLT, Min): that would put an ASCII set behind a plain name, which is the very thing I just conceded against.
- Why not Sys's two sets: then `trim` and `is_whitespace` disagree, and a model must learn which one `trim` uses.
- Training data backs W-U. JS `trim()`, Python `strip()` and Rust `trim()` all strip Unicode whitespace, NBSP included. Code generated from those languages expects NBSP to go.
- Today's 4-char set (F2) is unstated in the spec, so widening it breaks no spec promise.
- Sys's cost objection does not apply here. White_Space is a switch, not a table.

Q2. 2A, `to_digit(radix)`.
- Web says every caller passes 10. True, but in training data `to_digit(10)` is the only spelling (Rust). A base-10-only `to_digit()` makes Rust-trained output a compile error on every call.
- Min's `c.to_int() - '0'.to_int()` costs more tokens and has an off-by-range risk. That is what the ticket complains about.

Q3. 3B, and I take the `_by` names (PLT, DevOps). I withdraw `trim_matches`.
- A Rust-trained model reads `trim_matches` as also taking a Str with substring meaning. `trim_by` has no prior meaning, so the spec alone defines it.
- Sys and Web argue for a Str set, saying `trim_chars` names the set clearly. That is the strongest counter. Even so, a Str argument invites `trim_chars(".txt")`, written with a suffix in mind. A predicate cannot be read that way.
- The set case is one line with the Q1 methods or `==`.
- Sys's indirect-call cost is a codegen matter (inlining or monomorphising closures), not a spec matter.
- Min's 3C leaves the ticket's tokenizer case as a hand loop. Reject.

Q4. 4B, start/end. Rename `trim_*` by the 3-step protocol, as one whole-family vote, as PLT asks.
- Sys, PLT and Min point to the no-duplicates rule. A rename is not a duplicate: after step 3, one name exists.
- The churn is mechanical (DevOps: `blink fix`) and cheapest before 1.0.
- Second preference: 4A over any mix. The one outcome I vote against is a mixed axis (`trim_left` beside `pad_start`).

Q5. I move to 5B: `n <= 0` gives "".
- PLT's F4 argument wins on my own axis. The stdlib then has one rule for non-positive counts. I dissented on `with_capacity`, but a second, different rule is worse than the one I lost.
- Web's point is decisive for generated code. The common Python-trained pattern is `" ".repeat(width - s.len())`, which must not panic when the text is already wide.
- Law: `s.repeat(n).len() == s.len() * max(n, 0)`.

Q6. 6A.
- `trunc` (Float) beside `truncate` (Int) is a near-duplicate that models will mix up at a steady rate.
- Banker's rounding is `Decimal`'s job.

Q7. I move to 7A, `display_fixed`.
- DevOps and PLT are right. The `display_` prefix tells a reader, and a model, that the result is a Str rendering. It also sits next to `display()` in autocomplete.
- Bare `fixed` reads as an adjective or a predicate.
- One extra token; `to_fixed`/`toFixed` get a hint row either way.

Q8. I move to 8A, ties to even.
- Oracle argument (Sys, PLT, Min): when a model writes a test for this method, it computes the expected string with C `%.*f`, Rust `{:.2}` or Python `f"{:.2f}"`. All three give `0.125` to 2 places as "0.12". 8B would make those generated tests fail.
- My "one rule with `round()`" argument loses, because exact ties are rare and the spec can state the difference: `2.5.round()` gives 3.0, but `2.5.display_fixed(0)` gives "2".

Q9. 9A, no sign: "0.00".
- Sys and Min have the oracle argument here too, so this is the weaker of my holds.
- But Blink's own Display already drops the sign of zero (`-0.0` renders as "0.0"). Within Blink, one zero rule beats matching C.
- The spec gives `(-0.001).display_fixed(2) == "0.00"` as an example.

Q10. `digits < 0` panics. No upper bound. Never uses exponent form. `digits == 0` gives no ".".
- `0..=17` (DevOps) and `0..=20` (Web) are magic numbers that a model must memorise and that the spec must justify. The exact expansion is defined for every `digits`.
- NaN, `inf` and `-inf` render as in Display (F3). DevOps's "Infinity" is wrong.

Q11. 11B, with a weak hold.
- PLT and DevOps make a fair point that `abs()` fails at MIN.
- Zero-padded negatives are rare in the benchmark tasks, and the `pad_start` doc must show the "0-7" trap.
- If 11A passes, use PLT's `display_padded`, to match `display_fixed`.

STABLE, READY TO VOTE. One condition: the Q1 ballot must list W-U (plain `is_whitespace` is Unicode White_Space, and `trim` strips exactly that set) beside "trim's ASCII set" and "two sets".

##### Minimalism

Min (minimalism): Phase B round 1

I accept U1 to U7.

**Q1. Character set and names: I hold 1A and propose a merged form for whitespace.**
- Members: digit, alpha and alphanumeric. I do not object to PLT's `is_ascii_upper` and `is_ascii_lower`. They are cheap and honest, but no friction asks for them. I vote against `is_ascii` (Sys, Web), because `c.to_int() < 128` already says it.
- Web and AI/ML want plain names with Unicode meaning. Their strongest argument: "a tokenizer that treats é as not a letter is a bug report." My answer: today a plain Unicode `is_alpha` means either category tables (Sys: 4–8 KB plus a pinned Unicode version, as PLT says) or a second mismatch between spec and code like `to_upper` (fact 4). Adding Unicode names later breaks nothing. Changing what a plain name means later does.
- Whitespace, merged option 1A′: Sys and DevOps are right that a plain `is_whitespace` meaning {space, tab, LF, CR} would be a dishonest name. That is my own Phase A argument turned back on me. PLT is right that two whitespace sets break law W. So ship one set under one honest name: `is_ascii_whitespace` is exactly the set `trim` removes (F2, listed in the spec). No plain `is_whitespace` until the Unicode tier exists. That gives one definition and no lie. Note: DevOps adds `\x0C`, and F2 shows trim does not strip it. The spec must pick one set for both.

**Q2. `to_digit`: I concede to 2A (`to_digit(self, radix: Int) -> Option[Int]`).**
Sys and PLT convinced me. My `c.to_int() - '0'.to_int()` idiom works for base 10 only. Hex and other bases then need three branches that are easy to get wrong, and that is the kind of loop I said additions may replace. Radix panics outside 2..=36, per PLT: `None` means only "not a digit".

**Q3. Trim by set: I hold 3C. My fallback is 3B with PLT's names.**
- Strongest case for adding it: DevOps's `"0042".trim_start_by(...)`. But `parse_int` handles leading zeros, `trim_right` handles newlines, `strip_*` handles quotes and markers, and scanners use a `char_at` loop with predicates. No benchmark case in either ticket needs set-trim that these do not already cover.
- If the panel adds it anyway, I side with DevOps and AI/ML against a `Str` set (3A). Python reads `"ab"` as a set and Rust reads it as a substring, so whichever meaning we pick gives silently wrong output. A predicate has one meaning. Use PLT's names (`trim_by`, `trim_left_by`, `trim_right_by`), which follow Q4.

**Q4. Naming axis: I hold 4A.**
Web, DevOps and AI/ML make a fair case for right-to-left text and for matching training data. But this round fills a gap, and a rename is a separate change that breaks every program that calls `trim_left` today. I agree with PLT: if start/end is wanted, it is its own vote on the whole family, done by the 3-step protocol, and pad follows whichever side wins. Do not let pad set the trim name by the back door.

**Q5. `repeat` with a negative count: I hold 5A (panic), but not firmly.**
PLT cites F4. The `with_capacity` rule covers a capacity hint, which has no output you can see. `repeat`'s count IS the output. Web's argument was that negative counts come from width arithmetic, and padding now removes that arithmetic. The negative counts that remain are bugs, and a silent `""` hides them. I will not block on this.

**Q6. More rounding methods: I hold 6A.**
DevOps's `round_even` is for banker's rounding, and money belongs to `Decimal` (fact 10). `trunc` next to `truncate` gives two names one letter apart with different return types. Sys and PLT already reject it.

**Q7. Renderer name: I concede to 7A, `display_fixed`.**
Sys, PLT and DevOps are right. A `display_` prefix puts it next to `display()` in autocomplete and makes "rendering, not conversion" a naming rule, not something each user has to learn. That is one convention, not a new concept. It also gives the name for Q11 if that passes.

**Q8. Tie rule: I hold 8A (ties to even on the exact value).**
AI/ML's argument is "one rounding rule: `x.fixed(0)` should match `x.round()`." My answer: the two rules differ only on exact binary ties (`2.5`, `0.125`). Every formatter users will compare against (C `%.*f`, Rust `{:.2}`, Python `f"{:.2f}"`) uses ties to even. So 8A matches training data, and we can test it against glibc output. It is also the rule exact-printf algorithms (Ryu-printf) already use, so we need no special-case code.

**Q9. Sign on an all-zero result: I concede to 9A ("0.00").**
I was wrong in Phase A. sections/03_types.md:4165 says Display renders `-0.0` as `0.0`. If the fixed form kept the sign, it would be a second sign rule next to Display. PLT's rule: write `-` only when a non-zero digit is shown.

**Q10. Digits range and exponent form**
- `digits < 0` panics, and there is no upper bound. The 0..=17 bound (DevOps) is wrong: `0.1.display_fixed(20)` is a legitimate exact expansion. A 0..=20 bound (Web) is a JS limit, not a rule we need. A cap is one more number for users to learn.
- Never exponent form: I agree with DevOps and AI/ML. `digits == 0` gives no `.`.
- NaN and the infinities are spelled as Display spells them, `NaN`, `inf` and `-inf` (F3). DevOps's "Infinity" is a slip.

**Q11. Int zero padding: I hold 11B.**
- Strongest argument against me, from PLT: "the `abs()` workaround overflows at MIN, so it cannot be built." That is true. But the reports in the benchmarks pad money and counts with spaces, and `pad_left(n, ' ')` is correct for negative numbers too. Zero-padding a negative number is rare. The doc must show the `"0-7"` case.
- If the panel adds it, the name must be `display_padded`, to match Q7.

STABLE, READY TO VOTE

#### Phase C — Silent vote

Ballot options:

- **Q1a** 1A-W: `is_ascii_*` names; plain `is_whitespace` = Unicode White_Space (25 codepoints); `trim` strips exactly `is_whitespace`; no `is_ascii_whitespace`. 1A-2P: also `is_ascii_whitespace` = trim's old set, and `trim` keeps that set. 1A-Min: only `is_ascii_whitespace`. 1B: plain names.
- **Q1b** `is_ascii_upper`/`is_ascii_lower`: Yes / No. **Q1c** `is_ascii()` (0..=127): Yes / No.
- **Q2** 2A `to_digit(self, radix: Int) -> Option[Int]`, radix outside 2..=36 panics; 2B base 10 only; 2C no `to_digit`.
- **Q3a** 3A a Str of codepoints as a set; 3B a predicate `fn(Char) -> Bool`; 3C none now. **Q3b** suffix `_by` / `_matches`.
- **Q4** 4A keep `trim_left`/`trim_right`, `pad_left`/`pad_right`; 4B whole-family rename to `start`/`end` by the 3-step protocol, step 3 removes `trim_left`/`trim_right`, no lasting alias.
- **Q5** `repeat`: 5A `n < 0` panics; 5B `n <= 0` gives `""`.
- **Q6** 6A `round`, `floor`, `ceil` only; 6B also `round_even` and `trunc`.
- **Q7** 7A `display_fixed(self, digits: Int) -> Str`; 7B `fixed`.
- **Q8** tie rule on the exact binary value: 8A ties to even; 8B ties away from zero.
- **Q9** `(-0.001)` to 2 places: 9A `"0.00"`; 9B `"-0.00"`.
- **Q10** Confirm / Object: `digits < 0` panics; no upper bound; never exponent form; `digits == 0` writes no `.`; NaN, `inf`, `-inf` as Display.
- **Q11a** 11A an Int method, zeros after the sign, width counts the sign; 11B no method. **Q11b** name `display_padded` / `display_zero_padded`.
- **Q12** hint rows for foreign spellings, hints only: Yes / No.

Phase C tally:

| Question | Result | Tally |
|----------|--------|-------|
| Q1a | 1A-W | 6-0 |
| Q1b | Yes | 5-1 (Minimalism no) |
| Q1c | Yes | 4-2 (AI/ML, Minimalism no) → Phase D |
| Q2 | 2A | 6-0 |
| Q3a | 3B | 5-1 (Minimalism 3C) |
| Q3b | `_by` | 6-0 |
| Q4 | 4B | 4-2 (Systems, Minimalism 4A) → Phase D |
| Q5 | 5B | 4-2 (PLT, Minimalism 5A) → Phase D |
| Q6 | 6A | 6-0 |
| Q7 | 7A | 6-0 |
| Q8 | 8A | 4-2 (Web/Scripting, PLT 8B) → Phase D |
| Q9 | 9A | 6-0 |
| Q10 | Confirm | 6-0 |
| Q11a | — | 3-3 (11A Systems, PLT, DevOps; 11B Web/Scripting, AI/ML, Minimalism) → Phase D |
| Q11b | `display_zero_padded` | 6-0 |
| Q12 | Yes | 5-1 (Minimalism no) |

##### Systems

SYSTEMS (Sys) — Phase C ballot

Q1a. Vote: 1A-W
Reasoning: One whitespace set for both the predicate and trim, so there is one definition and one code path. Unicode White_Space is a fixed 25-codepoint set: one compare on the ASCII path, a switch on the rest, no table. The `is_ascii_*` names state their set and cost, and they leave the plain names free for a later table-backed Unicode tier.
Concern: trim changes behaviour (it also strips \v, \f, U+0085, NBSP, U+3000), so the spec and the stdlib fix must land in the same change with a corpus test, or the 4-char implementation keeps drifting from the spec.

Q1b. Vote: Yes
Reasoning: Each is one range compare that inlines to two instructions, and case tests are common in tokenizers and identifier rules. Leaving them out pushes users to `c.to_int()` arithmetic, which is the friction the ticket reports.
Concern: users may expect `'É'.is_ascii_upper()` to be true; the doc must give that example.

Q1c. Vote: Yes
Reasoning: `cp < 128` is one compare, and it is the guard a byte-oriented fast path needs before it takes the ASCII branch.
Concern: none of weight; it is the smallest method in the set.

Q2. Vote: 2A
Reasoning: A literal radix constant-folds, so `to_digit(10)` costs the same as a base-10-only method. Hex and octal scanners need the radix, and a hand-written three-range hex check is where scanners go wrong.
Concern: Rust's `is_digit(10)` habit will appear in generated code; Q12's hint row must catch it.

Q3a. Vote: 3B
Reasoning: Trim calls the predicate only on the removed codepoints plus one per end, so an indirect call costs almost nothing. A Str set has two meanings (Python set vs Rust substring), and the wrong guess gives silent wrong output.
Concern: if closures in stdlib calls allocate an environment on each call, a hot loop of `trim_by` calls allocates; the implementation must keep a capture-free closure allocation-free.

Q3b. Vote: _by
Reasoning: `_by` follows the `sort_by`/`max_by` pattern for "takes a function", and it does not borrow Rust's `trim_matches`, which takes a substring there.
Concern: none of weight.

Q4. Vote: 4A
Reasoning: Systems has no stake in the spelling; I vote for the option that costs no migration. A 3-step rename across src, lib and the corpus costs real work and buys only a name.
Concern: models trained on Rust and JS will write `trim_start`/`pad_start`; the hint rows (Q12) must cover them if 4A wins.

Q5. Vote: 5B
Reasoning: `with_capacity` (F4) and negative pad width (U3) already clamp non-positive counts. One stdlib rule for non-positive counts is more important than my original "a negative count is a bug". Overflow of `byte_len * n` still panics before allocation.
Concern: a real negative-count bug gives "" silently; the doc must state the clamp.

Q6. Vote: 6A
Reasoning: Each of the three maps to one instruction (roundsd / frintm / frintp / frinta). `roundeven` is C23 and absent from older libm, so it needs a fallback, and money belongs to Decimal. `trunc` next to `truncate` gives two names one letter apart with different types.
Concern: someone will ask for banker's rounding on Float; the answer must point to Decimal.

Q7. Vote: 7A
Reasoning: `display_` says the result is a rendering to Str, and it groups with `display()` and `display_zero_padded` in autocomplete. `fixed` reads as an adjective or state, and nothing in it says it allocates a Str.
Concern: JS users will type `toFixed`/`to_fixed`; Q12's hint rows must cover them.

Q8. Vote: 8A
Reasoning: It matches glibc and musl `%.*f`, Rust and Python, so we can test conformance against `%.*f` on millions of random doubles. 8B has no reference implementation to diff against, and its law with `round()` matters only on exact binary ties.
Concern: a user who checks `2.5.display_fixed(0)` against `2.5.round()` will see "2" vs 3.0 and file a bug; the spec must show the example.

Q9. Vote: 9A
Reasoning: Display renders -0.0 as "0.0" (Float Text Form, "Zero"); the named second form must agree with the main form on the sign of zero. Rule: write "-" only when the rounded text has a non-zero digit.
Concern: this differs from printf, so the 8A conformance test must special-case all-zero results.

Q10. Vote: Confirm
Reasoning: The output is at most about 310 + digits bytes, known before the allocation, so no cap is needed for safety. An exact algorithm (Ryu-printf style) handles any digits, and a cap adds a panic path with no reason.
Concern: the runtime must not delegate to the host snprintf (locale, and inexact CRTs such as MSVC); it needs its own exact routine on every target.

Q11a. Vote: 11A
Reasoning: Correct user code must branch on the sign, and the `abs()` route overflows at the type's MIN. That is silent wrong output in a report column. One method, written in Blink, one allocation.
Concern: users will want a fill other than '0'; the answer is `pad_left` for unsigned cases.

Q11b. Vote: display_zero_padded(width)
Reasoning: The method takes no fill argument, so the name must state the fill. `display_padded` suggests a space pad or a missing fill parameter, and it would block a later general `display_padded(width, fill)`. I change from my round-1 choice for this reason.
Concern: a longer name; acceptable for a rare call.

Q12. Vote: Yes
Reasoning: Hints cost compile time only on an error path and add zero runtime cost and no API surface. They are the cheap answer to every place we chose a spelling that differs from Rust, JS or Python.
Concern: the hint table can grow without review; each row must point to exactly one Blink method.

##### Web/Scripting

Web/Scripting, Phase C ballot

**Q1a. Vote: 1A-W**
- Reasoning: A JS or Python dev expects `trim()` to remove NBSP and the other Unicode spaces, because `String.trim()` and `str.strip()` do. One whitespace set for `trim` and `is_whitespace` means that `s.trim()` and `s.trim_by(fn(c) { c.is_whitespace() })` can never disagree. Two whitespace predicates (1A-2P) would cause the question "which whitespace do I use?" every time.
- Concern: Pinning trim to 25 codepoints changes the output of existing code that relied on trim leaving NBSP or form feed in place, so the change needs a release note.

**Q1b. Vote: Yes**
- Reasoning: Case tests are as common as digit tests in tokenizers and identifier checks, for example "starts with a capital, so it is a type name". Leaving them out sends people back to `to_int()` range checks, which is the friction the ticket reports.
- Concern: Users may expect `'É'.is_ascii_upper()` to be true; the name says ASCII, but the doc should show that example.

**Q1c. Vote: Yes**
- Reasoning: One cheap predicate covers "is this plain ASCII" input validation, which comes up often in web input handling. It also lets a Unicode tier compose with it later.
- Concern: None worth stating; it is a single compare.

**Q2. Vote: 2A**
- Reasoning: Rust users write `c.to_digit(10)` from memory, and the radix makes hex scanning (colour codes, escapes) a one-liner. An explicit `10` costs little.
- Concern: A model or a Python dev will write `c.is_digit(10)`. Without the Q12 hint, that is a confusing error.

**Q3a. Vote: 3B**
- Reasoning: A Str argument means a set in Python and a substring in Rust. Whichever meaning we pick, half the users get silently wrong output. A closure has one meaning and composes with the Q1 predicates.
- Concern: The common case `s.trim_by(fn(c) { c == '0' })` is wordier than Python's `lstrip("0")`, and some users will find that annoying.

**Q3b. Vote: _by**
- Reasoning: `trim_matches` is a false friend. In Rust it takes a pattern, including a `&str`, so Rust users would try to pass `"ab"`. `_by` matches the `sort_by` / `max_by` convention most devs know.
- Concern: None significant.

**Q4. Vote: 4B**
- Reasoning: JS (`trimStart`, `padStart`), Rust (`trim_start`) and Kotlin (`padStart`) all settled on start/end, and Blink is pre-1.0, so a rename costs the least now. "Left" is also wrong for right-to-left text.
- Concern: The 3-step migration touches src and lib, and a skipped step breaks the bootstrap. A `blink fix` rewrite should land with step 1.

**Q5. Vote: 5B**
- Reasoning: F4 already fixed the stdlib rule for counts: `with_capacity` treats `n <= 0` as empty. Two count rules in one stdlib is the bigger trap. Python returns "" here too.
- Concern: A negative count from a real bug passes silently. Padding covers the common width case, so the risk is small.

**Q6. Vote: 6A**
- Reasoning: Banker's rounding is a money tool, and money goes to `Decimal`. `trunc` beside `truncate` is two near-identical names with different return types, and it will cause questions.
- Concern: Users porting Python `round()` code will get different results on ties; the doc must state the tie rule with an example.

**Q7. Vote: 7A**
- Reasoning: People who want text type `x.display` and see `display_fixed` next to it in autocomplete. A bare `fixed` reads like an adjective or the verb "fix".
- Concern: JS devs search for `toFixed` first; the Q12 hint has to catch them.

**Q8. Vote: 8B**
- Reasoning: In JS, `(2.5).toFixed(0)` is "3" and `(0.125).toFixed(2)` is "0.13", so the familiar-languages argument splits. Inside Blink, if `display_fixed(0)` and `round()` disagree on 2.5, that disagreement becomes the top Stack Overflow question about this method. Sys already requires our own exact algorithm, so the C tie rule saves no work.
- Concern: Output differs from C `printf` and Python on exact ties, so cross-language tests may disagree on a few values.

**Q9. Vote: 9A**
- Reasoning: Display already renders `-0.0` as `0.0`, so a sign here would put a second zero rule in the spec. "-0.00" in a report or invoice is a bug report waiting to happen.
- Concern: A user who wants to see that a value was slightly negative loses that information. They can still check `x < 0.0`.

**Q10. Vote: Confirm**
- Reasoning: Every rule is predictable and matches what the user sees from Display.
- Concern: A very large `digits` builds a large string; the doc should say the expansion is exact, not padded noise.

**Q11a. Vote: 11B**
- Reasoning: IDs, clock times and counters, the 90% case for zero padding, are non-negative. Signed money uses Float or `Decimal`, not Int. If friction appears, the method fits the `display_*` family later without a break.
- Concern: A negative Int padded with `'0'` gives "0-7" silently at run time, and only the doc warns about it.

**Q11b. Vote: display_zero_padded(width)**
- Reasoning: If 11A wins, the name must say the fill is zero. `display_padded` makes readers ask "padded with what?" because the Str pad methods take a fill argument.
- Concern: It is long, but it is clear.

**Q12. Vote: Yes**
- Reasoning: Each deviation from the JS, Python or Rust spelling costs one confused search, unless the compiler names the fix at once. Hints only, with no aliases, keep one name for each operation and still give newcomers a 5-minute path.
- Concern: The hint table must stay in sync with renames (Q4 step 3); a stale hint that points to a removed name is worse than none.

##### PLT

PLT ballot

**Q1a. Vote: 1A-W**
- Reasoning: this option has one predicate, one set and one law: `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`. Each name states its set: `ascii` when the set is ASCII, and the pinned White_Space set when the name is plain. 1A-2P puts two whitespace sets in the language next to a trim that the spec never defined. 1B lets the name hide the set, so `is_alphanumeric` mixes Unicode letters with ASCII digits.
- Concern: code that relies on today's `trim` keeping NBSP or `\x0C` changes behaviour. The spec must list the 25 codepoints, and the change needs a corpus check.

**Q1b. Vote: Yes**
- Reasoning: they are total, ASCII-scoped predicates, and their sets are obvious from the names. Leaving them out forces `c.to_int()` range arithmetic, which is exactly the friction the ticket reports.
- Concern: users may expect them to compose with Unicode `to_upper`. The doc must say they test ASCII only.

**Q1c. Vote: Yes**
- Reasoning: it is the domain predicate for the whole `is_ascii_*` family: each `is_ascii_x` implies `is_ascii`. It costs one compare, and it is the guard that makes byte-oriented reasoning sound.
- Concern: low. Someone may read it as "is ASCII text" on a Str, but it exists only on Char.

**Q2. Vote: 2A**
- Reasoning: `None` means "not a digit in this radix" and nothing else. A bad radix breaks the contract, so it panics. The radix makes the function total over every base a scanner needs, and base 10 costs one token.
- Concern: Rust users will write `c.is_digit(10)`. The Q12 hint must catch that.

**Q3a. Vote: 3B**
- Reasoning: a set of codepoints is the special case of a predicate, but a predicate can't be written as a set, so only 3B avoids adding a second method later. A Str argument means a set in Python and a substring in Rust, so code goes silently wrong for one group. A closure has one meaning, and it composes with the Q1 predicates.
- Concern: per-codepoint closure calls may cost more until the closure is inlined. That is a codegen matter, not a spec flaw.

**Q3b. Vote: _by**
- Reasoning: `_by` is the standard mark for "this takes a function" (`sortBy`, `maxBy`). In Rust, `_matches` invites a Str argument, so it imports exactly the ambiguity that 3B removes.
- Concern: users who know Rust will type `trim_matches` first. A hint row covers that.

**Q4. Vote: 4B**
- Reasoning: Blink strings are codepoint-oriented, so trim works in logical order, and "left" is false for right-to-left text. The rename is the whole family through the 3-step protocol, with removal in step 3, so no lasting alias appears.
- Concern: step 3 may never happen, which would leave two names. The decision record must make removal part of the vote, not a later chore.

**Q5. Vote: 5A**
- Reasoning: a repeat count has no negative meaning, so clamping a negative count turns a bug into a silent `""`. The panic is a stated precondition, and for `n >= 0` the law `s.repeat(n).len() == s.len() * n` holds. Pad width differs because it is a lower bound, so a negative width has a real meaning.
- Concern: people who come from Python expect `""`. The panic message must name the count.

**Q6. Vote: 6A**
- Reasoning: three total, Float-to-Float operations with one stated tie rule. A Float-returning `trunc` beside an Int-returning `truncate` is two near-identical names with different types. Banker's rounding belongs to `Decimal`.
- Concern: the type of `truncate` (Int) next to `round` (Float) stays uneven. That belongs to the conversion audit.

**Q7. Vote: 7A**
- Reasoning: the `display_` prefix tells the reader the result is a rendering from the `display()` family, not a Float operation like `round`. `fixed` is an adjective that reads as a transform of the value.
- Concern: JS users look for `toFixed`. The Q12 hint row covers it.

**Q8. Vote: 8B**
- Reasoning: the law `x.display_fixed(0) == x.round().display_fixed(0)` makes the text form agree with the language's own rounding. Matching printf is only agreement outside Blink. Ties occur only on exact binary values, so `2.675` still gives "2.67".
- Concern: people who compare output against C or Python see "0.13" where printf gives "0.12" for `0.125`. The spec must show that example.

**Q9. Vote: 9A**
- Reasoning: the Float Text Form already renders `-0.0` as `0.0`. One rule for the sign of zero across every text form beats copying C, and the shown digits don't support a sign.
- Concern: a user who checks the sign through text loses it, but `x < 0.0` is the right test anyway.

**Q10. Vote: Confirm**
- Reasoning: the exact expansion of every binary64 value is finite, so every `digits >= 0` has a defined result. A cap would be arbitrary.
- Concern: a huge `digits` allocates a huge string. That is the caller's choice, the same as for `repeat`.

**Q11a. Vote: 11A**
- Reasoning: `"{n}".pad_left(3, '0')` gives wrong output on part of Int's domain, and you can't build the correct form from the existing methods without an overflow hazard at MIN. A doc note doesn't make that composition sound.
- Concern: this adds one more method to the Int table, which Min will count against the budget.

**Q11b. Vote: display_zero_padded(width)**
- Reasoning: the name states the fill, and the fill is the operation's whole meaning. `display_padded` suggests a space fill, like `pad_left`.
- Concern: the name is long, but the call is rare.

**Q12. Vote: Yes**
- Reasoning: hints cost no surface, since they add no aliases and no second name. They turn foreign spellings into compile-time redirects. The type-mismatch hint for `x.round()` where an Int is expected guards the one known trap in the Float/Int split.
- Concern: the hint list can grow without end. Keep it to the spellings this record names.

##### DevOps

DevOps, Phase C ballot

**Q1a. Vote: 1A-W**
Reasoning: I move from 1A-2P to 1A-W. 1A-W gives one whitespace definition behind one honest name, and `trim` is defined by it. That makes `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })` hold with the name users will actually type. 1A-2P puts two whitespace predicates in autocomplete, and users must then pick between two sets that differ in a way most of them cannot see. 1B gives `is_digit` and `is_alpha` different scopes with nothing in the names to show it.
Concern: `trim` will now also strip NBSP, U+2028 and the other Unicode spaces. Existing code changes behaviour without a diagnostic, so the release notes must state it and the spec must list the 25 codepoints.

**Q1b. Vote: Yes**
Reasoning: case tests are common in tokenizers (identifier rules, hex parsing), and these are two cheap compares. If the family is missing members, users go looking for `is_upper` and land on the hint row anyway.
Concern: users will expect a Unicode `is_upper` next to it and file it as missing. The hint for `is_upper` must say that only the ASCII form exists.

**Q1c. Vote: Yes**
Reasoning: it lets a user build any ASCII-only test from the scoped predicates, and it is one compare.
Concern: some users will read `is_ascii` as "is printable ASCII". The doc must say 0..=127.

**Q2. Vote: 2A**
Reasoning: one call gives both the check and the value as `Option[Int]`, and hex is real tokenizer work. A radix outside 2..=36 is a contract bug, so it should panic and name the value.
Concern: Rust users will write `c.is_digit(10)`. That is the hint row in Q12.

**Q3a. Vote: 3B**
Reasoning: a Str-set argument reads the same as Rust's substring `trim_matches("ab")`, so a misread gives silently wrong output that no diagnostic can catch. A predicate has one meaning, and it composes with the Q1 predicates.
Concern: the one-off set case is longer to write (`fn(c) { c == '-' || c == '_' }`), and some users will ask for a set form later.

**Q3b. Vote: _by**
Reasoning: `_by` says "takes a function" on its face. `_matches` carries Rust's pattern meaning, so Rust users will expect the substring meaning.
Concern: none of note. The hint row maps `trim_matches` to `trim_by`.

**Q4. Vote: 4B**
Reasoning: start/end is correct for right-to-left text, and it matches current Rust, JS and Kotlin. Migration is one `blink fix` rewrite, followed by a permanent hint row on `trim_left`/`trim_right`. One axis across trim, trim_by and pad keeps the completion list in one family.
Concern: the 3-step dance touches src/ and lib/. If step 3 slips, a lasting alias is the duplicate-API problem we are trying to avoid.

**Q5. Vote: 5B**
Reasoning: the stdlib then has one rule for non-positive counts, the same as `with_capacity` (F4) and the negative pad width. Width arithmetic in normal use goes negative.
Concern: a real bug that computes a negative count prints nothing, not a panic. That is quieter, but I accept it for consistency.

**Q6. Vote: 6A**
Reasoning: `trunc` (to Float) next to `truncate` (to Int) is an autocomplete trap. `round_even` has no request behind it, and money goes to `Decimal`.
Concern: `round()` returns Float while `truncate()` returns Int, and users will be confused by that. The hint for "Float where Int expected" must name `.truncate()`.

**Q7. Vote: 7A**
Reasoning: `display_fixed` sits next to `display()` in completion, and the name says "rendering", as fact 5 asks. A bare `fixed` can read as a predicate.
Concern: it is longer to type. The hint row for `to_fixed`/`fixed`/`toFixed` makes sure people find it.

**Q8. Vote: 8A**
Reasoning: report output gets diffed against C, Rust and Python in golden tests. Ties to even matches all three, and 8B differs from them on exact ties such as `0.125`.
Concern: `x.display_fixed(0)` and `x.round()` disagree on exact ties such as `2.5`. The spec must give that example.

**Q9. Vote: 9A**
Reasoning: it is the same rule as Display, which renders -0.0 as "0.0", so the two Float text forms agree. A "-0.00" in a money column reads as a bug.
Concern: it differs from every major language, so ports that are diffed against Python output will show a difference here.

**Q10. Vote: Confirm**
Reasoning: no arbitrary cap means no bug reports against a magic number, and never using exponent form is what a fixed renderer promises.
Concern: a very large `digits` gives very long strings (up to ~1100 digits for subnormals). That is acceptable but should be documented.

**Q11a. Vote: 11A**
Reasoning: "0-7" is silently wrong output that no lint can catch, and the `abs()` workaround overflows at MIN.
Concern: it adds surface that only signed values need, so most callers with non-negative values will never see a difference.

**Q11b. Vote: display_zero_padded(width)**
Reasoning: the name states the fill, so nobody has to check the docs or a hover to learn whether it pads with spaces or zeros.
Concern: it is long, but it is rare and self-documenting.

**Q12. Vote: Yes**
Reasoning: the panel deliberately differs from the common foreign spellings in several places. Each difference costs a user one compile cycle unless the error names the Blink spelling. Making it part of the decision ensures the implementation ships the hints with the methods, not later.
Concern: the hint table has to be maintained, and a hint that names a method later renamed becomes a wrong hint. The table needs a test that every target exists.

##### AI/ML

AI/ML — Phase C ballot

Q1a. Vote: 1A-W
Reasoning: Each name says its scope, so a model learns one rule: `ascii` in the name means ASCII, and a plain name means Unicode. There is only one whitespace set. `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })` holds, and that matches JS `trim`, Python `strip` and Rust `trim`, which generated code already expects to strip NBSP.
Concern: Widening `trim` from {space, \t, \n, \r} to all of White_Space changes the output of existing programs that hold NBSP or U+0085. The implementation ticket must state this as a behaviour change.

Q1b. Vote: Yes
Reasoning: Upper and lower are the classes that case-handling code most often asks about, and Rust gives them under these names. Leaving out two members of a regular family makes models emit `is_ascii_upper` and get UnresolvedMethod. A complete family is cheaper to learn than a partial one.
Concern: It adds two names before any friction log asked for them.

Q1c. Vote: No
Reasoning: `c.to_int() < 128` is short and plain. Without the prefix family from 1B, `is_ascii` has no job to do.
Concern: Rust-trained code emits `c.is_ascii()`. That call needs a hint row.

Q2. Vote: 2A
Reasoning: `to_digit(10)` is the spelling in training data (Rust), so 2B turns every generated call into a compile error. A radix outside 2..=36 panics, so `None` keeps one meaning: "not a digit".
Concern: Scripting users must type `10` on every call, which costs a few tokens in the commonest case.

Q3a. Vote: 3B
Reasoning: A predicate has one meaning. A Str set does not: Python reads it as a set of characters and Rust reads it as a substring, and a call like `trim_chars(".txt")` invites the suffix misreading. The set case is still one line.
Concern: The closure form costs more tokens than `trim_chars("-_")` for the commonest set case.

Q3b. Vote: _by
Reasoning: `trim_matches` brings Rust's dual meaning (Str or closure), so Rust-trained code would pass a Str. `_by` has no prior meaning, so the spec alone defines it.
Concern: `trim_by` is rare in training data, so models depend on the spec and the hint row at first.

Q4. Vote: 4B
Reasoning: Rust and JS both moved to start/end, so recent training data uses those names. One axis across trim, trim_by and pad removes the "which word goes with which verb" guess.
Concern: The 3-step rename touches every `trim_left`/`trim_right` call in src, lib and user code. If step 3 lags, the language has two names for one operation in the meantime.

Q5. Vote: 5B
Reasoning: It follows the existing `with_capacity` `n <= 0` rule, so the stdlib has one convention to learn. The common generated pattern `" ".repeat(width - s.len())` must not panic when the text is already wide.
Concern: A real bug that produces a negative count now gives "" with no error.

Q6. Vote: 6A
Reasoning: A Float-returning `trunc` beside an Int-returning `truncate` is a near-duplicate that models will confuse at a steady rate. Banker's rounding belongs to `Decimal`.
Concern: The `round() -> Float` vs `truncate() -> Int` asymmetry stays, and only diagnostics cover it.

Q7. Vote: 7A
Reasoning: The `display_` prefix tells the reader, and the model, that the result is a Str rendering. It also sits next to `display()` in autocomplete. Bare `fixed` reads as an adjective or a predicate.
Concern: Training data says `toFixed` and `to_fixed`, so the hint row is required, not optional.

Q8. Vote: 8A
Reasoning: Tests that models write compute the expected string with C `%.*f`, Rust `{:.N}` or Python `f"{:.Nf}"`, and all three give `0.125` to 2 places as "0.12". Ties away from zero would make those generated tests fail.
Concern: `2.5.round()` gives 3.0, but `2.5.display_fixed(0)` gives "2". The spec must give this example next to both methods.

Q9. Vote: 9A
Reasoning: Blink's Display already drops the sign of zero (`-0.0` renders as "0.0"). Inside Blink, one zero rule beats matching C, and "-0.00" in a money column reads as a bug.
Concern: It differs from every foreign oracle, so generated tests will expect "-0.00". The spec example must be prominent.

Q10. Vote: Confirm
Reasoning: No magic upper bound for a model to memorise. The exact expansion is defined for every `digits`, and output never switches to exponent form at a size threshold, as JS does.
Concern: A huge `digits` (say 10^6) allocates a large string with no early error.

Q11a. Vote: 11B
Reasoning: Zero-padded negatives are rare in the benchmark tasks, and the "0-7" result can be documented next to `pad_start`. I hold this weakly; PLT's point that `abs()` fails at MIN is fair.
Concern: The output is silently wrong, not a compile error, and a doc note does not stop it.

Q11b. Vote: display_zero_padded
Reasoning: If the method exists, its name must say what fills it. With `display_padded`, a model must guess between space and zero, and it guesses wrong in roughly half the cases.
Concern: It is a long name, though it is rare enough that the token cost does not matter.

Q12. Vote: Yes
Reasoning: This is what lets a model learn the API from the spec plus the compiler. Each place where Blink departs from the most-trained spelling must name the fix, or the departures cost repeated failed compiles. Hints keep one name for each operation, with no aliases.
Concern: The hint table must be kept current as the API changes, or a stale hint points to a name that no longer exists.

##### Minimalism

Min (minimalism): Phase C ballot

**Q1a. Vote: 1A-W**
- Reasoning: In round 1 I asked for one whitespace set under one honest name. 1A-W gives that, and it does not need a Unicode tier first. The 25-codepoint White_Space set is fixed and small, so the plain name is not a lie. `trim` then has exactly one definition to point to. 1A-2P adds a second whitespace concept, which is the surface I want to avoid. 1A-W reaches what my 1A-Min aimed for, with the same name count, so I drop 1A-Min.
- Concern: This changes how `trim` behaves. NBSP and U+2028 are now stripped. The spec must list the 25 codepoints, and the migration note must say that `trim` output changes for non-ASCII input.

**Q1b. Vote: No**
- Reasoning: No friction log or benchmark asks for upper or lower classification. Adding a name later breaks nothing.
- Concern: If they are left out, the first case-folding tokenizer writes `c >= 'A' && ...` by hand. That loop is small and correct, and it is the price of waiting.

**Q1c. Vote: No**
- Reasoning: `c.to_int() < 128` already says this, in one comparison, with no new name.
- Concern: Web and AI/ML wanted `c.is_ascii() && c.is_alpha()` composition. With `is_ascii_*` names winning, that use goes away.

**Q2. Vote: 2A**
- Reasoning: I conceded this in round 1. The digit-value idiom works for base 10 only. Other bases need a branchy hand-written loop that is easy to get wrong, which is what an addition should replace. A radix outside 2..=36 panics, so `None` keeps one meaning.
- Concern: Some users will write `c.to_digit(10).is_some()` where `is_ascii_digit` is meant. Both are correct, so this is two ways to ask one question. The cost is low.

**Q3a. Vote: 3C**
- Reasoning: Neither ticket names a case that existing methods cannot cover: `parse_int` for leading zeros, `trim_right` for newlines, `strip_*` for quotes, a `char_at` loop for scanners. Three closure-taking methods are a lot of surface for a need nobody has shown.
- Concern: If 3B wins, it adds three methods at once. Their law against `trim` (`s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`) must be in the spec.

**Q3b. Vote: _by**
- Reasoning: `_matches` means a substring or Pattern match in Rust, so that name brings back the ambiguity the predicate form was chosen to remove.
- Concern: None that matters.

**Q4. Vote: 4A**
- Reasoning: This round fills a gap. Renaming methods that already exist breaks every program that calls `trim_left` today, and buys only a name. The spec can define "left" as the start of the string in logical order in one sentence.
- Concern: Models trained on Rust and JS will write `trim_start` and `pad_start`. A diagnostic hint covers that at no cost to the language.

**Q5. Vote: 5A**
- Reasoning: The count is the output size. Padding removes the width arithmetic that produced negative counts, so a negative count that remains is a bug, and a silent `""` would hide it. The `with_capacity` rule (F4) covers a capacity hint, which you cannot see in the output.
- Concern: Two non-positive-count conventions in the stdlib (panic here, no-op in `with_capacity`). The spec must say why they differ.

**Q6. Vote: 6A**
- Reasoning: Banker's rounding is a money concern, and money is `Decimal`'s job. `trunc` next to `truncate` would be two names one letter apart, with different return types.
- Concern: None.

**Q7. Vote: 7A**
- Reasoning: The `display_` prefix makes "rendering, not conversion" a naming rule that users learn once, and it groups the method with `display()` in autocomplete.
- Concern: It is longer to type, which is a small cost.

**Q8. Vote: 8A**
- Reasoning: Every formatter users will check us against uses ties to even on the exact value: C `%.*f`, Rust `{:.N}`, Python `f"{:.2f}"`. So does the exact-printf algorithm we would use. We can test our output directly against glibc.
- Concern: `2.5.display_fixed(0)` gives "2" while `2.5.round()` gives 3.0. The spec must give that example next to both methods.

**Q9. Vote: 9A**
- Reasoning: Display already prints `-0.0` as `0.0` (sections/03_types.md:4165). A second sign rule for the fixed form would be a second concept.
- Concern: Code that needs the sign of a value that rounds to zero must check `x < 0.0` itself. That is rare.

**Q10. Vote: Confirm**
- Reasoning: Each rule is the one with the fewest exceptions. In particular, an upper bound would be a magic number for users to learn.
- Concern: A very large `digits` allocates a very large Str. That is the same class of risk as a large `repeat`, and it is acceptable.

**Q11a. Vote: 11B**
- Reasoning: The benchmark reports pad with spaces, and space padding is correct for negative numbers. Zero-padding a negative number is rare, and a doc line covers the trap.
- Concern: The `"0-7"` result is silently wrong output, and some user will ship it. If friction shows that, add 11A then. Adding it later breaks nothing.

**Q11b. Vote: display_zero_padded(width)**
- Reasoning: The fill is fixed, so the name should say what it is. A bare `display_padded` makes the reader ask "padded with what?"
- Concern: It is a long name for a rare operation, which is fitting.

**Q12. Vote: No**
- Reasoning: Hint rows are tooling, not language surface. An open-ended list of foreign spellings in a spec decision is scope creep that someone then has to maintain. The implementation ticket can add the hints it finds useful, without a vote.
- Concern: If no decision records them, the hints may never be built. The implementation ticket should list the top few.

#### Phase D — Round 2 (Q1c, Q4, Q5, Q8, Q11a)

| Question | Result | Tally |
|----------|--------|-------|
| Q1c | Yes | 5-1 (Minimalism dissent; AI/ML changed from No) |
| Q4 | 4B | 6-0 (Systems and Minimalism changed from 4A). Removal of `trim_left`/`trim_right` in step 3 is part of the vote. Minimalism and PLT required the step-3 removal ticket to exist before step 1 lands. |
| Q5 | — | 3-3 (5A PLT, DevOps, Minimalism; 5B Systems, Web/Scripting, AI/ML; DevOps changed from 5B) |
| Q8 | 8A | 5-1 (PLT dissent: ties away from zero; Web/Scripting changed from 8B) |
| Q11a | 11A | 4-2 (Web/Scripting, Minimalism dissent: no method; AI/ML changed from 11B) |

Moderator note on Q11a: AI/ML moved to 11A on the view that the sign-aware result needs `abs()`. In the same round, Minimalism and Web/Scripting showed a workaround with `strip_prefix`:

```blink
match "{n}".strip_prefix("-") {
    Some(digits) => "-{digits.pad_left(width - 1, '0')}"
    None => "{n}".pad_left(width, '0')
}
```

##### Systems

SYSTEMS (Sys) — Phase D

Q1c. Answer to AI/ML and Min ("`c.to_int() < 128` is short; without 1B, `is_ascii` has no job"): it still has a job. It is the domain predicate of the `is_ascii_*` family (PLT): each `is_ascii_x` implies it, and a byte-oriented scanner tests it first to pick the fast branch. `c.to_int() < 128` compiles to the same compare, but it makes the reader check a magic number, and Rust-trained code will call `c.is_ascii()` anyway.
Vote: Yes
Reasoning: One compare, inlined; zero runtime cost over the hand-written form. It names the guard that every ASCII fast path needs, and it completes the family that 1A-W created.
Concern: users may read it as "printable ASCII"; the doc must say 0..=127.

Q4. Answer to my own side (Min: "renaming breaks every program that calls `trim_left`"): Blink is pre-1.0, the 3-step protocol is routine in this repo, and a `blink fix` rewrite makes the migration mechanical. My only argument for 4A was migration cost, and that cost is small and paid once. The other side has two arguments that last: logical order is correct for right-to-left text, and one axis matches Rust, JS and Kotlin.
Vote: 4B (changed from 4A)
Reasoning: The cost I weighed is one-time and mechanical; the naming benefit lasts. Trim, trim_by and pad on one start/end axis give one completion family.
Concern: step 3 (removal of `trim_left`/`trim_right`) must be part of this decision, not a later chore, or the language keeps two names for one operation.

Q5. Answer to PLT and Min ("a repeat count is the output size, so a negative count is a bug; pad width is a lower bound; `with_capacity` is an invisible hint"): that is a fair answer to my consistency argument, and I withdraw consistency as the main reason. What stays: `n <= 0` gives "" is a total, lawful function (`s.repeat(n).len() == s.len() * max(n, 0)`), and under Q10 we rejected adding a panic path with no need. A generated `" ".repeat(width - s.len())` that crashes in production on wide input is worse than a short row.
Vote: 5B
Reasoning: Clamping costs one compare and removes a failure path; the result has a stated law. `byte_len * n` overflow still panics before the allocation, which is the only case where no correct result exists.
Concern: a real negative-count bug prints nothing; the doc must state the clamp next to the law.

Q8. Answer to Web and PLT ("we ship our own exact algorithm, so the C rule saves no work; the law with `round()` keeps Blink consistent with itself"): the work it saves is in verification, not in the implementation. With 8A, glibc `%.*f` is a test oracle on millions of random doubles; 8B has no oracle anywhere. The `round()` law matters only on exact binary ties, while golden-test diffs against C, Rust and Python affect every report.
Vote: 8A
Reasoning: Same rule as every formatter users compare against, and a free conformance oracle. Disagreement with `round()` is limited to exact ties and can be documented.
Concern: `2.5.display_fixed(0)` gives "2" while `2.5.round()` gives 3.0; the spec must show it next to both methods.

Q11a. Answer to Web, AI/ML and Min ("zero-padded negatives are rare; IDs and counters are non-negative; add it later if friction shows"): signed zero-padded Ints are not rare in system output. UTC offsets ("-05" in "-05:00"), temperatures and signed deltas in log columns are all of that kind. The user-side fix must branch on the sign, and the `abs()` route overflows at MIN, so the doc note documents a trap that has no easy workaround.
Vote: 11A
Reasoning: Correct output on the whole Int domain needs this method, and the user cannot write it safely from existing parts. One method, written in Blink, one allocation of known size.
Concern: it adds one method to the Int table that most callers will never need.

##### Web/Scripting

Web/Scripting, Phase D

**Q1c. `is_ascii()`**
- Reply to AI/ML and Min ("`c.to_int() < 128` already says this"): it does, but only to a reader who knows the number 128. `c.is_ascii()` reads as intent. It is the name Rust users type, and it covers the "plain ASCII input" check that web validation code does all the time. A one-compare method with no ambiguity is the cheapest kind of surface.
- **Vote: Yes**
- Reasoning: The name says what the check means, and it does not depend on a magic number. It is the domain guard for the `is_ascii_*` family that won 1A-W.
- Concern: Some users will read it as "printable ASCII". The doc must say 0..=127.

**Q4. Side naming**
- Reply to Min ("breaks every program that calls `trim_left` today"): Blink is pre-1.0, and DevOps's `blink fix` makes the migration one mechanical command. Under 4A, every new user, and every model, types `trim_start`/`pad_start` and hits a hint first. That cost is paid forever, not once. A spec sentence that says "left means logical start" is the kind of definition that generates Stack Overflow questions.
- **Vote: 4B**
- Reasoning: Start/end is the current spelling in JS, Rust and Kotlin, and it is correct for right-to-left text. One axis across trim, trim_by and pad.
- Concern: Step 3, removal, must be part of this decision, not a later chore, or we end up with two names.

**Q5. `repeat` with negative n**
- Reply to PLT ("pad width is a lower bound, so a negative width means something; a count does not"): that is the strongest point, and it is fair. But `with_capacity` is also a count with no negative meaning, and the panel still chose to clamp it. Users will not learn "counts clamp, except this one". Sys moved to 5B on the same grounds.
- **Vote: 5B**
- Reasoning: One stdlib rule for non-positive counts, the same as `with_capacity` (F4). It also matches Python, and the generated pattern `" ".repeat(width - s.len())` does not crash.
- Concern: A real bug that computes a negative count prints nothing; the doc must state the clamp.

**Q8. Fixed tie rule: I change my vote to 8A.**
- Reply to Sys, DevOps and AI/ML (a conformance oracle against glibc, Rust and Python, plus tests that people and models write against `%.*f` or `f"{:.2f}"`): this beats my argument. The disagreement with `round()` on exact ties is one documented example. A formatter that disagrees with Python and C on `0.125` breaks golden tests in every cross-language port, and a test failure from that is a worse first experience than a doc note. JS takes the other side, but Python is the scripting reference that most report code is checked against.
- **Vote: 8A**
- Reasoning: Ties to even on the exact value matches C, Rust and Python. It gives us a test oracle, and it keeps hand-written expected strings correct.
- Concern: `2.5.display_fixed(0)` gives "2" while `2.5.round()` gives 3.0; the spec must show this pair next to both methods.

**Q11a. Int zero padding**
- Reply to Sys, PLT and DevOps ("you can't build the correct form without the `abs()` overflow at MIN"): you can, with no overflow, using methods this round adds:

      let t = "{n}"
      let s = match t.strip_prefix("-") {
          Some(d) => "-{d.pad_start(w - 1, '0')}"
          None => t.pad_start(w, '0')
      }

  So the composition is sound, just wordy. JS `padStart` has the same `"0-7"` trap, and JS devs live with it. The benchmark reports pad with spaces, which is correct for negatives. Adding the method later breaks nothing.
- **Vote: 11B**
- Reasoning: The 90% case (IDs, clock times, counters) is non-negative. A sound composition exists, so the doc can show it next to the `"0-7"` trap rather than add a method now.
- Concern: Users who skip the doc will ship "0-7"; if friction logs show that, add `display_zero_padded` as already named.

##### PLT

PLT, Phase D

**Q1c**

Answer to Min: `c.to_int() < 128` is the exact byte-arithmetic workaround the ticket names as friction. It also asks the reader to know that ASCII is the codepoints 0 to 127. A named predicate states the set and ties the `is_ascii_*` family together: `c.is_ascii_digit()` implies `c.is_ascii()`.

- **Vote: Yes**
- **Reasoning:** it is the domain predicate of a family we have already adopted 6-0. It is total and costs one compare. With it, the doc for each `is_ascii_x` can say "a subset of `is_ascii`" instead of repeating a numeric range.
- **Concern:** a user may expect a Str form. The doc should say it exists on Char only.

**Q4**

Answer to Min: if the spec defines "left" as the logical start, the name becomes false for every right-to-left string, and the reader must learn a definition that contradicts the plain word. Answer to Sys: the migration cost is one `blink fix` rewrite, and Blink is pre-1.0. A rename is never cheaper than it is now.

- **Vote: 4B**
- **Reasoning:** trim and pad work in logical codepoint order, so start/end is the true name and left/right is not. One axis covers trim, trim_by and pad. Removal in step 3 is part of the vote, so no lasting alias appears.
- **Concern:** if step 3 slips, two names stay. The decision record must file step 3 as blocking, not optional.

**Q5**

Answer to Sys, DevOps and AI/ML: the consistency they cite is not a real one.
- `with_capacity`'s `n` is a hint that no output shows.
- Pad's `width` is a lower bound (`result.len() == max(width, s.len())`), so a negative width is met.
- `repeat`'s `n` is an exact count of the output's units. A negative exact count has no meaning, so the honest result is a precondition failure, not a value.
- AI/ML's pattern `" ".repeat(width - s.len())` is the code that `pad_left`/`pad_start` now replaces, so it is no longer the common case.

Min states the remaining point exactly: a negative count left after padding is a bug, and `""` hides it.

- **Vote: 5A**
- **Reasoning:** for `n >= 0` the law `s.repeat(n).len() == s.len() * n` holds exactly, and outside that domain the method reports the contract violation. Clamping would make `repeat` total only by giving a wrong answer silently.
- **Concern:** if 5B wins, the spec must still state the clamp as a law (`max(n, 0)`) so that the silent case is at least documented.

**Q8**

Answer to Sys: testability does not favour 8A. Rounding the exact binary value is exact rational arithmetic, and a test oracle in big integers is about 20 lines, independent of glibc. Answer to AI/ML and DevOps: their tests compare against C and Python, but those languages also round `2.5` to nothing consistent between `round` and `printf`. Blink is free to be consistent with itself.

- **Vote: 8B**
- **Reasoning:** with 8B the language has one tie rule. `round()` and `display_fixed` share it, and the law `x.display_fixed(0) == x.round().display_fixed(0)` holds. 8A gives two tie rules inside one language, and the spec then has to apologize for them with an example. As Web notes, JS `toFixed` agrees with 8B, so the argument from outside the language is split.
- **Concern:** if 8A wins, the spec must show `2.5.round() == 3.0` beside `2.5.display_fixed(0) == "2"`, and must state that the two rules differ on purpose.

**Q11a**

Answer to Min ("adding later breaks nothing"): that holds for a missing convenience, but here the obvious composition already exists and gives wrong output silently. YAGNI defers features. It does not cover a correctness gap. Answer to Web ("signed money is Float or Decimal"): Int cents are common, and a negative balance is ordinary data, not a corner case. AI/ML grants that the `abs()` failure at MIN is fair, and that failure means no short correct user-side form exists.

- **Vote: 11A**
- **Reasoning:** sign-aware zero padding can't be built soundly from the existing methods. The textual form is wrong for negatives, and the `abs()` form overflows at MIN. One total method, `display_zero_padded`, closes that gap.
- **Concern:** if 11B wins, the doc warning is the only guard, and it must show `"{n}".pad_start(3, '0')` giving `"0-7"`.

##### DevOps

DevOps, Phase D

**Q1c**
Min and AI/ML: "`c.to_int() < 128` says this already, with no new name." That is true, but the comparison makes every reader confirm that 128 is the right limit and that `<` is the right operator. The named form also makes Rust-trained `c.is_ascii()` compile, so it needs no hint row.
Vote: Yes
Reasoning: one compare with a name that states its intent, and it is the domain predicate for the `is_ascii_*` family. It removes a magic number from user code, and the hint table loses one row.
Concern: users may expect a `Str.is_ascii` too. The UnresolvedMethod hint on Str must point to the per-Char form.

**Q4**
Min: "renaming breaks every program that calls `trim_left` today." Blink is pre-1.0. Step 2 of the dance gives a deprecation warning with a machine-applicable `blink fix`, and after step 3 a permanent hint names the new spelling. No program breaks without a diagnostic that tells the user the exact edit. The cost Min names is real, but it is paid once, and the cost only grows after 1.0.
Vote: 4B
Reasoning: one start/end axis across trim, trim_by and pad keeps completion in one family. It is correct for right-to-left text and matches current Rust, JS and Kotlin.
Concern: step 3 must be part of this decision, not a chore that can slip, or we ship two names.

**Q5**
I change my vote. Min's argument settles it for me: `pad_start` and `pad_end` now absorb the width arithmetic that produced negative counts, so a negative count that remains is most likely a bug. Min also draws a sound line against F4: a capacity hint cannot be seen in the output, while a repeat count is the output. From my domain, a silent `""` is the worst diagnostic outcome, and a panic that names the count is the best one available at run time.
Vote: 5A
Reasoning: `n < 0` panics with the count in the message, and `n == 0` gives "". Pad width stays a clamped lower bound, as PLT says, because a negative width has a meaning and a negative count does not. The spec states the difference from `with_capacity` in one sentence.
Concern: Python-trained code that writes `" ".repeat(w - s.len())` will panic where Python returns "". The panic message should suggest `pad_start`/`pad_end`.

**Q8**
Web: "JS `toFixed` gives "3" and "0.13", so the familiar-languages argument splits." True for JS. But C, Rust and Python agree on ties to even, and glibc `%.*f` gives a reference that Sys and Min can diff against on millions of random doubles. 8B has no reference implementation, so its conformance tests would need a second implementation that we write ourselves. PLT's law is elegant, but it applies only on exact binary ties.
Vote: 8A
Reasoning: it matches the formatters that users will diff golden output against, and it can be tested directly against glibc. The `round()` mismatch occurs only on exact ties, and an example in the spec covers it.
Concern: `2.5.display_fixed(0)` gives "2" while `2.5.round()` gives 3.0. Bug reports will come unless the spec shows that example next to both methods.

**Q11a**
Web and Min: "rare, add it later, nothing breaks." Adding it later does break nothing. But the failure mode is "0-7" in a shipped report: no compile error, no panic, and no lint can see the sign. "Wait for friction" assumes the friction will be visible, and silently wrong output is exactly the case where it is not. Web says signed money uses Float or `Decimal`. Then signed Int columns (deltas, offsets, temperatures) are the users left with no correct path, because `abs()` overflows at MIN.
Vote: 11A
Reasoning: `display_zero_padded(width)`, with the sign first and never truncating. It is the only correct composition, and the name states its fill.
Concern: it is one more Int method that most callers never need. Min will count it against the budget, and that is fair.

##### AI/ML

AI/ML — Phase D

Q1c. is_ascii()
Strongest other side: PLT says `is_ascii` is the domain predicate of the `is_ascii_*` family (each `is_ascii_x` implies it), and Sys says it is the guard for byte fast paths. My own Phase C concern also argues against me: Rust-trained code emits `c.is_ascii()`. That would cost a hint row to redirect a call that has an obvious right answer.
Vote: Yes (changed from No)
Reasoning: The name is the most-trained spelling and it completes the family in a way models can guess. One compare is not a budget question. `c.to_int() < 128` stays legal, but it is the less likely form in generated code.
Concern: Readers may take it as "printable ASCII". The doc must say 0..=127.

Q4. Side naming
Strongest other side: Min says the rename breaks every `trim_left` call and buys only a name, and a hint row covers models that write `trim_start`.
Answer: A hint row turns each generated `trim_start`/`pad_start` into a failed compile and a retry, for the life of the language. The rename is a one-time cost, before 1.0, with a `blink fix` rewrite. It also removes the false word "left" for right-to-left text (PLT). Removal in step 3 must be part of this vote, as PLT asks.
Vote: 4B
Reasoning: Rust, JS and Kotlin all use start/end, so it is the spelling models emit. One axis across trim, trim_by and pad removes a guess per call.
Concern: If step 3 slips, two names exist. The decision record must name removal as part of this decision.

Q5. repeat with negative n
Strongest other side: Min says padding now removes the width arithmetic, so a negative count that remains is a bug. PLT adds that a count has no negative meaning, unlike a pad width.
Answer: Padding gives the methods, but generated code still writes the Python idiom `" " * (w - len)`, which becomes `" ".repeat(w - s.len())`. That code must not panic when the text is already wide. One clamp rule across `with_capacity`, pad width and `repeat` is also easier to learn than a stated exception.
Vote: 5B
Reasoning: One stdlib convention for non-positive counts. Matches Python, the largest source of this pattern.
Concern: A real negative-count bug prints nothing. The doc must state the clamp.

Q8. Tie rule
Strongest other side: Web says the familiar-language argument splits: JS `toFixed` gives `(0.125).toFixed(2)` as "0.13" and `(2.5).toFixed(0)` as "3". PLT adds that agreement with `round()` inside Blink matters more than agreement with printf.
Answer: The split is real. But the oracles that tests and golden files are made from are mostly C `%.*f`, Python and Rust. Sys's point also stands: 8A can be checked against glibc on millions of random doubles, and 8B has no reference implementation to diff against. Exact ties are rare, so the internal law covers few values. A spec example shows the gap.
Vote: 8A
Reasoning: It agrees with the three most common oracles and with a testable reference.
Concern: `2.5.display_fixed(0)` gives "2" while `2.5.round()` gives 3.0. The example must sit next to both methods.

Q11a. Int zero padding
Strongest other side: PLT and DevOps say no sound composition exists. `"{n}".pad_start(3, '0')` is wrong on part of Int's domain, and the `abs()` route overflows at MIN.
Answer: This moves me. The JS idiom `String(n).padStart(3, "0")` is exactly what models will emit, and it gives silently wrong output, not a compile error. A doc note does not change generated code. A named method gives the spec, and the `pad_start` doc, a correct thing to point to. Web says signed IDs are rare; that is why the method stays out of the way of the common path. The project's rule that latent bugs will be found by users weighs more than one table entry.
Vote: 11A (changed from 11B)
Reasoning: It is the only correct way to zero-pad a signed Int, and the name `display_zero_padded` tells a model the fill. The `pad_start` doc then points to it for numbers.
Concern: Models will still write `"{n}".pad_start(w, '0')` out of habit. The doc and examples must show `display_zero_padded` as the numeric form.

##### Minimalism

Min (minimalism): Phase D

**Q1c**

Answer to PLT: PLT says this is "the domain predicate for the whole family". Every `is_ascii_x` already implies codepoint < 128 by its own definition. No law needs a named predicate to hold. A byte fast path (Sys) checks the byte, not a Char.

- Vote: No
- Reasoning: `c.to_int() < 128` says the same thing in one compare, with no new name. The use case Web and AI/ML gave, combining `is_ascii()` with plain Unicode predicates, went away when 1A-W won.
- Concern: Rust-trained code will write `c.is_ascii()`. The Q12 hint row covers that.

**Q4**

Answer to Web, PLT, DevOps and AI/ML: the strongest point is that Blink is pre-1.0, so a rename is cheapest now. Waiting makes it cost more, because this round adds `pad_*` and `trim_*_by` on whichever axis wins. That point beats my "this round fills a gap": choosing 4A now fixes `left`/`right` on five more names. A rename that removes the old names adds no surface, so it does not cost what I guard against.

- Vote: 4B (I change my vote)
- Reasoning: The method count stays the same and the names stay correct for right-to-left text. The decision is cheapest now, before the new methods ship on the old axis. I vote 4B only on PLT's condition: step 3 removal is part of this vote, not a later chore.
- Concern: If step 3 slips, the language has two names for one operation. The ticket for step 3 must exist before step 1 lands.

**Q5**

Answer to Sys, Web, DevOps and AI/ML: the strongest point is "one stdlib rule for non-positive counts". There is no such single rule, as PLT showed. A pad width is a lower bound, so a negative width has a real meaning. A `with_capacity` count is a hint you cannot see in the output. A `repeat` count is the exact output size. AI/ML's example `" ".repeat(width - s.len())` is the code that `pad_left` now replaces. A clamp for that pattern makes the bug path quiet in order to support code we just made unneeded.

- Vote: 5A
- Reasoning: The law `s.repeat(n).len() == s.len() * n` holds with no `max`. A negative count that remains is a bug, and a panic that names the count shows it. Each of the three count rules matches what its count means.
- Concern: Users coming from Python expect `""`. The panic message and the doc must say "use `pad_left` for width arithmetic".

**Q8**

Answer to Web and PLT: the strongest point is PLT's law `x.display_fixed(0) == x.round().display_fixed(0)`. That law holds only on exact binary ties, and those are rare in real data. The cost of 8B falls on every conformance test and every generated golden test that checks us against C, Rust or Python (Sys, DevOps, AI/ML). JS, which Web cites, is the only formatter that rounds ties upward. Matching one outlier in exchange for a law that rarely applies is a bad trade.

- Vote: 8A
- Reasoning: We can diff our output against glibc `%.*f` on random doubles. That is the cheapest strong test this feature can have.
- Concern: The spec must show `2.5.display_fixed(0) == "2"` next to `2.5.round() == 3.0`.

**Q11a**

Answer to PLT, Sys and DevOps: the strongest point is that "you can't build the correct form from the existing methods without an overflow hazard at MIN". With `strip_prefix`, which passed 6-0, you can. It works on the rendered text, so no `abs()` is needed and MIN is not a problem:

```blink
// pad_left or pad_start, whichever Q4 picks
fn zero_pad(n: Int, width: Int) -> Str {
    match "{n}".strip_prefix("-") {
        Some(digits) => "-{digits.pad_left(width - 1, '0')}"
        None => "{n}".pad_left(width, '0')
    }
}
```

So the correct form is four lines of user code built from methods that already passed. A missing method is not the gap here. The only issue is that the wrong one-liner is easy to write. A doc example plus this snippet in the `pad_left` doc closes that.

- Vote: 11B
- Reasoning: Signed zero-padding can be written correctly with no new name. The benchmarks pad with spaces. The `display_zero_padded` name already passed 6-0, so if friction appears later we add it without breaking anything and without a new vote on its shape.
- Concern: Users who skip the doc still write `"{n}".pad_left(3, '0')` and get "0-7". This needs a lint-free warning in the doc example itself.

#### Phase D2 — Focused round on Q5

Q5 was still tied 3-3 after Phase D. The user, asked for the deciding vote, chose one more focused round on Q5 instead. Each panelist answered the strongest argument on the other side and voted again.

Result: **5A, 4-2.** Systems changed from 5B to 5A. Web/Scripting and AI/ML dissent; they want `n <= 0` to give `""`, because `" ".repeat(width - s.len())` on text wider than the column then panics in production.

##### Systems

SYSTEMS (Sys) — Phase D2, Q5

Answer to PLT and Min ("a repeat count is the exact output size; a negative exact count has no meaning; the width pattern is now `pad_left`'s job"): this argument beats mine, and it beats it with my own criterion. In Phase D I kept the panic on `byte_len * n` overflow "because that is the only case where no correct result exists". A negative count is a second such case: no string has a negative number of copies, so "" is not a correct result, only a chosen one. My Q10 analogy does not carry over. A large `digits` has a correct, exact answer, so a cap there would be a panic with no reason. A negative count has no answer, so the panic has a reason. AI/ML's `" ".repeat(width - s.len())` is the pattern `pad_left`/`pad_start` exists to replace. Clamping to keep it from crashing makes the bug path quiet in order to support code we just made unneeded.

Systems precedent agrees. Go's `strings.Repeat` panics on a negative count. Rust and Zig take an unsigned count, so a negative count cannot reach the function at all. A checked-by-default language should not be quieter than those.

Vote: 5A (changed from 5B)
Reasoning: One rule covers both panics: `repeat` panics exactly when no correct result exists (`n < 0`, or `byte_len * n` overflows). For `n >= 0` the law `s.repeat(n).len() == s.len() * n` holds with no `max`. The check is one compare, which costs the same as the clamp.
Concern: Python-trained code will panic where Python returns ""; the panic message must name the count and point to `pad_start`/`pad_end`, and Q12's hint table should carry the same advice.

##### Web/Scripting

Web/Scripting, Phase D2 (Q5)

Answer to PLT and Min ("the three counts mean different things, so there is no single rule to be consistent with; `pad_start` replaces `" ".repeat(width - s.len())`"): I concede the consistency point. A pad width is a lower bound, a capacity is a hint, and a repeat count is the exact output size. My Phase D argument from F4 does not hold.

What decides it for me is Sys's point: when the panic fires. `repeat(width - s.len())` goes negative only when the data is wider than the developer expected. That happens on the long customer name in production, not on the sample data in the test. Python taught a generation of script writers that `" " * (w - len(s))` is safe, and `pad_start` will not erase that habit quickly. The panic message would tell them to use `pad_start`, but it tells them in a crashed nightly job. For a report or a CLI table, one misaligned row is a bug report; a dead job is an outage.

- **Vote: 5B**
- **Reasoning:** `repeat` is total, with the stated law `s.repeat(n).len() == s.len() * max(n, 0)`. It also matches Python, where this idiom comes from. The only failure that appears depends on the data, and it hits users in production rather than in tests, so a quiet `""` is the lesser harm. `byte_len * n` overflow still panics, because no correct result exists there.
- **Concern:** A real negative-count bug prints nothing. The doc must state the clamp law, and must point to `pad_start`/`pad_end` for width arithmetic.

##### PLT

PLT, Phase D2 (Q5)

The strongest argument against my vote is Sys's: with the clamp, `repeat` is total with a stated law (`s.repeat(n).len() == s.len() * max(n, 0)`), and in the idiom `" ".repeat(width - s.len())`, `""` is the result the caller wanted. A clamp there is not a wrong answer.

My answer:
- `repeat` is the monoid power `s^n`. It is defined on the naturals, and Str has no inverses, so a negative `n` has no meaning. `max(n, 0)` is one of several extensions you could choose for negative `n`, none of them natural. Rounding up to `""` is a policy choice dressed as a law.
- Blink has no `Nat` type, so the honest typing is `Int` with the precondition `n >= 0`. This is the same pattern as `to_digit`'s radix (2A, 6-0) and `display_fixed`'s `digits < 0` (Q10, 6-0). The panel has already chosen "a value outside the domain panics" twice in this deliberation, so 5A is the consistent rule here, not 5B.
- The idiom Sys protects is the one `pad_start`/`pad_end` exist to replace. A panic message that names `pad_start` turns the crash into a one-line fix.
- Web's point that `with_capacity` is also a count: its count is a hint with no visible output, so clamping it can't produce a wrong visible result. `repeat`'s count is the output.

- **Vote: 5A**
- **Reasoning:** the precondition `n >= 0` matches the operation's true domain, and the law `s.repeat(n).len() == s.len() * n` holds with no `max`. It follows the domain rule the panel already applied to radix and digits. A panic that names the count turns a quiet bug into a visible one.
- **Concern:** Python-trained code will hit the panic. The message must name the count and suggest `pad_start`/`pad_end`.

##### DevOps

DevOps, Phase D2 (Q5)

The strongest argument on the other side is from Sys: "`" ".repeat(width - s.len())` crashing in production on wide input is worse than a short row." Sys also leans on Q10, but Q10 (6-0) points the other way. Under Q10, `display_fixed` panics when `digits < 0`. `digits` is a count with no negative meaning, which is the same class as `repeat`'s `n`, and the panel unanimously chose a panic for it. If `repeat` clamps instead, then "counts clamp, except this one" becomes true in the opposite direction from the one Web fears. The rule Q10 already set is: a lower bound clamps (pad width), a hint clamps (`with_capacity`), and an exact count that cannot be negative panics (`digits`, `n`).

As for "a crash is worse than a short row": the crash message names the count and the call site, so the user fixes it in one step. A short row in a shipped report gets no diagnostic at all, and someone finds it weeks later in the output. In my domain, a quiet wrong result is the failure we never accept when a loud one is available. The idiom that prompts the crash, `" ".repeat(w - s.len())`, now has a correct replacement, and the panic message can name it.

Vote: 5A

Reasoning: `n < 0` panics, the message names the count and suggests `pad_start`/`pad_end`, and `n == 0` gives "". This matches the `digits < 0` rule from Q10, so the stdlib has one rule for exact counts. The law `s.repeat(n).len() == s.len() * n` holds with no `max`.

Concern: Python-trained and model-generated code will hit this panic. The panic text must name the pad methods, or the first experience is a crash with no way forward.

##### AI/ML

AI/ML — Phase D2 (Q5)

Strongest other side: PLT and Min say the three counts mean three different things. A pad width is a lower bound, a capacity is an invisible hint, and a repeat count is the exact output size. They also say `pad_start` now replaces the `" ".repeat(width - s.len())` pattern I cited, so a negative count that remains is a bug, and `""` hides it.

Answer: I accept that the three counts differ, and I drop consistency as my reason. But "pad replaces the pattern" holds for the spec, not for generated code. Models emit the Python habit `" " * (w - len)` long after a better method exists, and for that code `""` is the intended answer, not a wrong one. The negative case arrives only on input wider than the column. Generated tests rarely cover that, so 5A turns correct-intent code into a production panic on the first long name. The "hidden bug" case that 5A protects is real but rarer. The over-wide-input case is the common one, and 5B gives it the right output.

Vote: 5B
Reasoning: For the dominant way this method gets called with a negative count, the clamp produces the result the author meant, and it states a law: `s.repeat(n).len() == s.len() * max(n, 0)`. A panic that teaches `pad_start` is good for debugging only when it fires in development. On over-wide input it fires in production. Overflow of `byte_len * n` still panics, because no correct result exists there.
Concern: A real bug that computes a negative count prints nothing. The doc must state the clamp law next to `repeat`, and show `pad_start` as the preferred form for width arithmetic.

##### Minimalism

Min (minimalism): Phase D2, Q5

**Answer to Sys, Web and AI/ML**

Sys makes the strongest argument: "under Q10 we rejected adding a panic path with no need", and "a crash in production on wide input is worse than a short row".

Q10 points the other way. The panel confirmed 6-0 that `display_fixed` panics when `digits < 0`. `digits` is an exact count of output units, the same kind of count as `repeat`'s `n`. Our own closed decision already says a negative exact count panics and is not clamped. With 5B, `repeat` becomes the one exception, and that breaks the "one rule" argument Web and AI/ML use.

On "a crash is worse than a short row": a short row in a report is silently wrong output, which is exactly what this panel called a defect in Q11. A panic that names the count and says "use pad" tells the user where the bug is.

The generated `" ".repeat(w - s.len())` from AI/ML is the one real cost. The Q12 hint rows and the panic message cover it, and `pad_*` is the idiom the spec will teach.

**Vote: 5A**

**Reasoning:** A `repeat` count is an exact output size, like `display_fixed`'s `digits`, and the panel already ruled that a negative exact count panics. For `n >= 0` the law `s.repeat(n).len() == s.len() * n` holds with no `max`. Only the lower-bound width (pad) clamps, because a negative width has a meaning.

**Concern:** Python-trained code that does width arithmetic through `repeat` will panic. The message must name the count and point to `pad_start`/`pad_end`.

#### User sign-off

The user approved the full tally ("Approve all").

### Final Spec

```blink
// Char
fn is_ascii(self) -> Bool              // 0..=127
fn is_ascii_digit(self) -> Bool
fn is_ascii_alpha(self) -> Bool
fn is_ascii_alphanumeric(self) -> Bool
fn is_ascii_upper(self) -> Bool
fn is_ascii_lower(self) -> Bool
fn is_whitespace(self) -> Bool         // 25 Unicode White_Space codepoints
fn to_digit(self, radix: Int) -> Option[Int]

// Str
fn trim(self) -> Str
fn trim_start(self) -> Str
fn trim_end(self) -> Str
fn trim_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
fn trim_start_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
fn trim_end_by(self, pred: fn(Char) -> Bool ! _) -> Str ! _
fn strip_prefix(self, prefix: Str) -> Option[Str]
fn strip_suffix(self, suffix: Str) -> Option[Str]
fn pad_start(self, width: Int, fill: Char) -> Str
fn pad_end(self, width: Int, fill: Char) -> Str
fn repeat(self, n: Int) -> Str

// Float
fn round(self) -> Float
fn floor(self) -> Float
fn ceil(self) -> Float
fn display_fixed(self, digits: Int) -> Str

// Int
fn display_zero_padded(self, width: Int) -> Str
```

- `is_whitespace` is the 25 Unicode `White_Space` codepoints. `trim`, `trim_start` and `trim_end` strip exactly that set, which is wider than the old {space, `\t`, `\n`, `\r`}. Law: `s.trim() == s.trim_by(fn(c) { c.is_whitespace() })`. No `is_ascii_whitespace`.
- `is_ascii_*` is false above 127: `'É'.is_ascii_upper()` is `false`. `is_ascii` is `0..=127`.
- `to_digit`: a radix outside `2..=36` panics.
- Side names are `start`/`end` for the whole family. `trim_left`/`trim_right` go by the 3-step protocol, with no lasting alias and a permanent hint.
- `strip_prefix`/`strip_suffix`: an empty argument gives `Some(self)`.
- Pad: `fill` is a required `Char`; `width` counts codepoints, not terminal columns; never truncates; `width <= len` (negative included) gives `self`; `result.len() == max(width, s.len())`; `"-7".pad_start(3, '0')` is `"0-7"`.
- `repeat`: `n == 0` gives `""`; `n < 0` panics, naming the count, with help naming `pad_start`/`pad_end`; `byte_len * n` overflow panics.
- `round`/`floor`/`ceil`: no argument, return `Float`; NaN, ±inf and ±0.0 pass through; `round` ties away from zero. No `round_even`, `trunc` or `round(digits)`.
- `display_fixed`: ties to even on the exact binary64 value (`2.675` gives `"2.67"`; `2.5.display_fixed(0)` is `"2"` while `2.5.round()` is `3.0`); `-` only when a shown digit is non-zero (`(-0.001).display_fixed(2)` is `"0.00"`); `digits < 0` panics, no upper bound; never exponent form; `digits == 0` writes no `.`; NaN/`inf`/`-inf` as Display; an exact algorithm, independent of locale and the C library. glibc `%.*f` is a test oracle except for the sign rule.
- `display_zero_padded`: zeros after the sign, `width` counts the sign, never truncates: `(-7).display_zero_padded(3)` is `"-07"`.
- Interpolation keeps no format specs.
- Foreign spellings get help lines only, never aliases.
- Spec: sections/03_types.md §3.2.1 *Trim, Strip, Pad and Repeat*, §3.2.4 *Char Methods*, §3.2.5 *Float Rounding*, §3.6.1 *Fixed-Decimal and Zero-Padded Forms* and *Foreign spellings of the text helpers*; sections/03c_protocols.md *Char Conversions*.

### AI-First Review

4 of 5 pass. Consistency fails: there are two tie rules (`round` away from zero, `display_fixed` to even), and `repeat` (panics on `n < 0`) and pad (clamps `width`) treat a negative count in different ways. The panel chose both on purpose, and the spec states each contrast where it applies.
