[< All Decisions](../DECISIONS.md)

# Unicode Escapes (`\u{H}`) and Char/Str Debug Output — Design Rationale

Resolves the deferral in [`Char` debug-form](char-debug-form.md) (6-0 Q2, "deferred, not rejected"): a `'\u{N}'` output form for non-printable scalars had to land together with `\u{...}` as input syntax. It also takes over the Unicode slice of the cancelled hex-escape task that [Char Literal Escapes](char-literal-escapes.md) deferred to.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Scope | Full package: `\u{H}` input in Char and Str; `Char.debug()` and `Str.debug()` both change | 6-0 |
| Q2 | Output escape class | Cc plus a frozen range list written in the spec | 6-0 |
| Q3 | Raw UTF-8 char literals (`'😀'`) | Separate lexer bug that blocks the implementation; round-trip test covers raw non-ASCII | 5-1 (AI/ML: same change) |
| Q4 | Str errors decided here | Malformed `\u{..}`, brace-less `\u`/`\U`, and `\x` are errors in Str too; other unknown Str escapes are not decided here | 6-0 |
| Q5 | `blink fmt` and hex spelling | fmt keeps the author's spelling | 5-1 (DevOps: canonicalize hex spelling) |
| Q6 | Str named-escape table | One shared table; Str gains `\b` and `\f` in the spec | 6-0 |
| Q7 | Diagnostics | Registered E11xx code per error via `diag_error_range`; implementer picks numbers; no new uncoded sites | 3-3 in Phase C → 6-0 in Phase D |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist wrote each submission to a file; the texts below are those files, verbatim.

#### Phase A — Independent proposals

##### Systems

> # Systems panelist, Phase A: `\u{N}` escapes (qvan6m)
>
> ## A finding the other panelists need first
>
> The ticket's invariant `parse(c.debug()) == c` for every scalar fails today for a second reason besides the missing `\u{...}`. The char-literal lexer reads **one byte** (`src/lexer.bl` ~L276: `codepoint = ch2`, then it requires `'`). `'😀'.debug()` already emits `'😀'` (raw UTF-8, per the ratified table), and that output does **not lex**. It fails with "char literal must contain exactly one character".
>
> So adding `\u{N}` alone does not close the round trip for the full codepoint space. The same change must also decode one UTF-8 scalar (2 to 4 bytes) in the char-literal lexer. That costs one bounded decode at compile time and nothing at runtime. If we skip it, the widened round-trip test fails on its first non-ASCII sample.
>
> ---
>
> ## SYS-1 (PRIMARY): `\u{H}` input for Char and Str, a fixed escape set for output, no Unicode tables
>
> ### Input (lexer)
>
> - Syntax is `\u{` then 1 to 6 hex digits then `}`. Upper and lower case are accepted. Underscores are not.
> - Lexer errors (not warnings, in Str as well) for: empty braces, more than 6 digits, a non-hex digit, a missing `}`, a surrogate (0xD800 to 0xDFFF), or a value above 0x10FFFF. These are the same rules as `Char.from_code_point`, so there is one validity rule.
> - In a Char literal the lexer stores the escape as the codepoint integer. In a Str literal it stores it as UTF-8 bytes. Both happen at lex time, so the **runtime cost is zero**.
> - In Str, `\u{0}` is a lexer error. A Str cannot hold NUL (C strings), and silent truncation is a lie.
> - `#"..."#` does not change. It has no escape processing.
> - The raw non-ASCII char literal `'😀'` lexes, as described above.
>
> ```blink
> let bel = '\u{7}'
> let esc = "\u{1b}[31mred\u{1b}[0m"   // covers the cancelled 19v5gb \x1b case
> let smile = '\u{1F600}'               // == '😀'
> let bad = '\u{D800}'                  // error: surrogate
> let nul = "\u{0}"                     // error: Str cannot hold NUL
> ```
>
> ### Output (Char.debug and Str.debug)
>
> The escape set is closed and stated in the spec, with no Unicode property tables:
>
> 1. Named escapes come first (Char: `\n \r \t \\ \b \f \0 \'`; Str: `\n \r \t \\ \" \{ \}`).
> 2. Then `\u{h}` (lowercase hex, fewest digits) for **C0 0x00–0x1F, DEL 0x7F, C1 0x80–0x9F** when no named escape covers the scalar.
> 3. Every other scalar is raw UTF-8, as today.
>
> ```blink
> io.println('\u{7}'.debug())     // '\u{7}'
> io.println('\n'.debug())        // '\n'        (named escape wins, never '\u{a}')
> io.println('\u{9b}'.debug())    // '\u{9b}'    (C1 CSI)
> io.println('😀'.debug())        // '😀'
> io.println("a\u{1b}b".debug())  // "a\u{1b}b"
> ```
>
> Each scalar has exactly one output form, so the output is canonical and injective.
>
> ### Why no Unicode tables (the core systems argument)
>
> - **Deterministic output.** "Printable" as defined by Unicode general category (Cc/Cf/Zl/Zp/unassigned) changes with each Unicode version. If debug output depends on a table, the same program prints different bytes under two compiler versions, and goldens and snapshot tests break on a toolchain bump. A fixed range list never changes.
> - **Cost.** The check is three range compares, and in Str.debug it is byte-level. C0 and DEL are single bytes. C1 is `0xC2` followed by `0x80–0x9F`, a two-byte check. There is no decode loop and no multi-KB table in every binary.
> - **Buffer.** The widest escape is `\u{1f}`, 6 bytes out for 1 byte in. Replace `n*2+3` in `blink_str_debug` with a two-pass exact size (count, then write). Do not allocate `n*6+3` for the rare case.
> - **Char.debug** gains one branch and a hex loop of at most 2 digits (C1 tops out at 0x9f). It needs no `snprintf`.
>
> ### Tradeoff
>
> Bidi overrides (U+202A–202E, U+2066–2069), U+2028/2029 and U+FEFF still print raw. They are faithful (they round-trip via raw UTF-8 once the lexer decodes it) but invisible. I accept that for v1. See SYS-3.
>
> ---
>
> ## SYS-2 (alternative): Char only, as the ticket scopes it
>
> This has the same input and output rules but touches only Char. Str keeps its raw-control gap.
>
> - **For:** it is the smallest change and matches the ticket's literal scope.
> - **Against:** the lexer then needs two escape decoders, or one decoder with a Char-only branch. `"\u{1b}"` stays illegal while `'\u{1b}'` is legal, which is an arbitrary split that AI generators will hit. The cost difference is about 20 lines and one extra runtime loop. **I reject it**, because splitting the grammar costs more over time than one shared decoder.
>
> ---
>
> ## SYS-3 (optional add-on, not my primary): escape a small fixed set of format characters
>
> Add U+200B–200F, U+2028–2029, U+202A–202E, U+2060–2064, U+2066–2069 and U+FEFF to output rule 2. The list is still fixed and small (a few range compares on 3-byte UTF-8 sequences), and it catches Trojan-Source bidi abuse in debug output.
>
> - **For:** these scalars are invisible and security-relevant.
> - **Against:** where does the list stop? Each addition changes debug output. I would vote it only as a frozen list written into the spec, never "Cf per Unicode vN".
>
> ---
>
> ## Explicitly rejected: `\x..`
>
> - In Str, `\xHH` is byte-level and can produce invalid UTF-8, which breaks the Str-is-UTF-8 invariant and needs a validation pass.
> - In Char it duplicates `\u{..}`, so there would be two ways to write the same scalar.
> - `\u{1b}` covers every ANSI use case the cancelled 19v5gb was after.
>
> ## Cross-language notes
>
> - **Rust:** same `\u{H}` input syntax (1–6 digits), and `char::escape_debug` emits `\u{7}`. But Rust's Debug uses the grapheme-extend and printable tables, so its output shifts across Rust versions. SYS-1 deliberately avoids that.
> - **Zig:** `\u{H}` syntax is the same, and `\xHH` exists. Zig's `\x` byte escape in strings is exactly the invalid-UTF-8 hazard described above.
> - **Go:** `%q` uses `unicode.IsPrint` (tables), and the output depends on the Go version.
> - **C:** the `\x` escape takes an unlimited number of digits, a classic footgun. The braces avoid it.
>
> ## Spec touchpoints
>
> - §02: add `\u{H}` to both escape tables; replace the "deferred; use from_code_point" sentence; state that a char literal accepts one raw UTF-8 scalar.
> - §3.6 "Scalar debug-forms": replace the v1-gap paragraph with the 3-rule order and state the full-codepoint round trip for both Char and Str (Str excluding NUL, which it cannot hold).
> - `decisions/char-debug-form.md` Q2: record the deferral as resolved. `decisions/char-literal-escapes.md`: record that `\x` is rejected.
>
> The two runtime functions in `bootstrap/runtime_core.h` change (`blink_char_debug` and `blink_str_debug`, near line 2262), as does the char-literal lexer in `src/lexer.bl` (about lines 238–290), where the byte-only read sits.

##### Web/Scripting

> Web/Scripting — Phase A submission (spec gap: `\u{N}` input and output)
>
> I split the gap into five sub-questions: (1) input grammar, (2) which scalars the debug escaper escapes, (3) the output spelling, (4) whether Str follows, (5) what happens to `\x..`.
>
> ---
>
> ### WEB-1 (PRIMARY): Add `\u{HEX}` as a Char *and* Str escape, and use it in both debug escapers for control characters only
>
> **Input (lexer).** Char and Str literals share one new escape: `\u{` followed by 1–6 hex digits and then `}`. Uppercase and lowercase digits are both accepted. The value must be a Unicode scalar: a surrogate, a value > 0x10FFFF or empty braces is a lexer error. In a Str, `\u{0}` is also an error, because a Str cannot hold NUL. The error should point to `'\0'` / Char.
>
> ```blink
> let bel = '\u{7}'
> let esc = '\u{1b}'
> let smile = '\u{1F600}'          // same Char as '😀'
> io.println("\u{1b}[31mred\u{1b}[0m")   // ANSI colour: the real reason 19v5gb existed
> ```
>
> **Output (debug).** The rule is one line: escape a scalar as `\u{N}` exactly when it is a Unicode control character (general category Cc) with no named escape. That covers U+0000–001F, U+007F and U+0080–009F. Named escapes (`\n \t \0` …) still win. Everything else stays raw UTF-8, as already decided.
>
> ```blink
> io.println('\u{7}'.debug())      // '\u{7}'
> io.println('\u{7f}'.debug())     // '\u{7f}'
> io.println('\n'.debug())         // '\n'        (named escape wins)
> io.println('😀'.debug())         // '😀'        (unchanged: printable → raw)
> io.println("a\u{1b}b".debug())   // "a\u{1b}b"
> io.println(['\u{0}', 'x'].debug()) // ['\0', 'x']
> ```
>
> Output spelling: lowercase hex, no leading zeros. This is byte-for-byte what Rust prints (`'\u{7}'`).
>
> **Why this is the 90% case:**
> - **Braced `\u{...}` is the one form a JS/TS/Rust/Swift dev already knows.** ES2015 `"\u{1F600}"`, Rust `'\u{1F600}'` and Swift `"\u{1F600}"` all use it. An LLM already writes it without being told. Python's `\x07` / `\u0007` / `\U0001F600` is the design I'd avoid: three spellings, and people ask on Stack Overflow which one to use.
> - **The Cc-only rule needs no Unicode table.** It is three numeric ranges, so the runtime cost is a range check. A dev can predict the output: "invisible control bytes get escaped, everything I can see prints as itself."
> - **Str must be in scope.** The brief shows `blink_str_debug` has the same raw-control gap. If `'\u{1b}'.debug()` is legible but `"\u{1b}".debug()` spews a raw ESC that repaints the dev's terminal, that is a real bug report on day one. Debugging ANSI-coloured log lines is *the* scripting use case for this feature. Doing Char and not Str makes users ask "why does List[Char] debug differently from Str?"
> - **Accepting uppercase input** avoids a pointless error on `'\u{1F600}'`, the spelling in most docs and most training data. Output stays canonical lowercase.
>
> **Tradeoffs.**
> - Two spellings reach the same Char (`'😀'` and `'\u{1F600}'`), which bends "one way". But the two do different jobs: typing a glyph vs naming an invisible scalar. Every mainstream language accepts this split.
> - Accepting both hex cases on input is a small "one way" violation. WEB-3 contains it.
> - Invisible non-Cc characters (U+200B zero-width space, U+FEFF BOM, bidi overrides) still print raw. That is a real pain point ("why are these two strings not equal?"), but escaping them needs Unicode property tables. I defer it on purpose; see WEB-2.
>
> **Hard prerequisite the panel must not skip:** today `'😀'` does not lex (the lexer reads bytes). The ratified debug table already promises `'😀'.debug()` → `'😀'`. If this change widens the round-trip property to "the full codepoint space" without fixing multi-byte char literals, the invariant is false for every non-ASCII printable scalar. The first property-test run will prove that. Multi-byte char literal lexing must land in the same change, or the widened round-trip claim must exclude non-ASCII. I strongly prefer fixing the lexer. A Python/JS dev who types `'é'` and gets "char literal must contain exactly one character" will think the compiler is broken, and they'd be right.
>
> ---
>
> ### WEB-2 (secondary, deferred): Also escape invisible format characters
>
> Extend the output rule from Cc to also cover Cf (format), Zl/Zp (line and paragraph separators), and every whitespace scalar except U+0020. The result is `"a\u{200b}b"`. This is what makes debug output useful for the "two strings look equal but aren't" bug, and Rust's `char::escape_debug` does roughly this. The cost is a grapheme-property table in the runtime and a larger test surface. I would not vote to block WEB-1 on it. Log it as follow-up friction.
>
> ---
>
> ### WEB-3 (formatter rider): Put canonical hex spelling in `blink fmt`, not the lexer
>
> The lexer accepts `\u{1F600}`, `\u{1f600}` and `\u{01f600}`. `blink fmt` rewrites all of them to `\u{1f600}`, the same spelling debug emits. Source then converges on one way without punishing the AI or the human at compile time. This is how gofmt/prettier handle cosmetic variance.
>
> ---
>
> ### Rejected: `\x..` (the cancelled 19v5gb title)
>
> I'd reject `\x1b` outright. It is two ways to say one thing. It is also ambiguous for anyone who knows Python (`\x` is a byte there, which in a UTF-8 Str is a lie above 0x7F). The lexer error should suggest the fix, e.g. "`\x1b` is not an escape; write `\u{1b}`", so a Python/C habit costs one error, not one Stack Overflow search. Today an unknown Str escape is only a warning and keeps the backslash. That means `"\x1b[31m"` silently prints a literal `\x1b`, which is the worst outcome for exactly the users who want ANSI codes. I'd make at least `\x` and `\u` without braces hard errors in Str as part of this change.
>
> ---
>
> **Cross-language summary.**
>
> | Language | Input spelling | Control-char debug output |
> |---|---|---|
> | Rust (closest match) | `'\u{7}'` | `'\u{7}'` |
> | JS | `"\u{7}"` accepted | JSON output uses `\u0007` |
> | Python | `\x07` / `\u0007` | `repr` uses `'\x07'` |
>
> Blink should copy Rust exactly. It is the only one with a single input spelling that equals its output spelling.

##### PLT

> # PLT panelist, Phase A: `\u{N}` input and output (qvan6m)
>
> The ticket looks like one feature, but there are five sub-questions:
>
> - **Q1:** the input syntax.
> - **Q2:** where the escape is legal.
> - **Q3:** which scalars `debug()` escapes.
> - **Q4:** the canonical spelling of the output.
> - **Q5:** what the round-trip property covers, and what it depends on.
>
> A proposal that answers only Q1 and Q3 leaves the Q5 property false. I show why below.
>
> ## PLT-1 (primary): `\u{H+}` in both literal forms, a fixed Cc output class, and a total round-trip
>
> **Q1. Lexing rule (one production shared by Char and Str):**
>
> ```
> escape_u := '\' 'u' '{' HEX{1,6} '}'     HEX = [0-9a-fA-F]
> ```
>
> - The value must be a Unicode scalar value, in `[0, 0xD7FF] ∪ [0xE000, 0x10FFFF]`. Any other value is a **lexer error**, not a runtime `Result`. The same bounds as `Char.from_code_point` apply statically.
> - These are lexer errors: `\u{}`, more than 6 digits, `_` separators, and `\u` without `{`.
> - `\u{` consumes its `{`, so that brace never opens an interpolation hole. This rule is essential. Today `"\u{41}"` lexes as `\u` (an unknown-escape warning that keeps the backslash) followed by the hole `{41}`, so the result is the Str `\u41`. The new rule silently changes the meaning of any existing literal of that shape. Before landing, grep the corpus for `\u{`. I expect zero hits.
>
> **Q2. Scope: both `'...'` and `"..."`, never `#"..."#`.**
>
> The argument is compositional. The Char escape set minus `\'` must remain a subset of the Str escape set. If `'\u{7}'` lexes but `"\u{7}"` means "backslash, u, hole", the two literal grammars diverge on one shared prefix. A model then learns two lexers. `#"..."#` does no escape processing by an earlier decision, so it stays literal there, and that is consistent.
>
> A Str cannot hold NUL, so `"\u{0}"` is a lexer error. This matches how the Str grammar already has no `\0`.
>
> **Q3. Output class: General_Category = Cc only.**
>
> These are U+0000–001F, U+007F, and U+0080–009F: 65 scalars. The reason is a PLT reason. Unicode's stability policy guarantees that the Cc set never changes. `debug()` then stays a **pure total function that does not depend on the Unicode version**. Rust's `is_printable` tables change with each Unicode release, so `c.debug()` output depends on the toolchain. Snapshot tests would fail on a compiler upgrade with no change in user code. That is not acceptable for a function that feeds `assert_eq` diffs.
>
> **Q4. Canonical output form:**
>
> - A named escape takes precedence.
> - Otherwise use lowercase hex with the fewest digits.
> - `Str.debug()` gets the same treatment, so the two stay parallel.
>
> The lexer accepts both hex cases and leading zeros. `debug()` is a *section* of the lexer: `lex ∘ debug = id` must hold, and `debug ∘ lex = id` need not.
>
> ```blink
> '\u{7}'.debug()       // "'\u{7}'"
> '\u{0}'.debug()       // "'\0'"        (named escape takes precedence)
> '\u{1F600}'.debug()   // "'😀'"        (not Cc: raw UTF-8)
> '\u{9b}'.debug()      // "'\u{9b}'"    (C1 control)
> "a\u{1b}[0m".debug()  // "\"a\u{1b}[0m\""
> '\u{D800}'            // lexer error: surrogate is not a Unicode scalar value
> "\u{0}"               // lexer error: Str cannot contain NUL
> ```
>
> **Q5. The property becomes total, but only with a precondition the ticket does not state.**
>
> ```
> ∀ c : Char.  lex_char(c.debug()) == c
> ∀ s : Str.   lex_str(s.debug())  == s
> ```
>
> Under PLT-1, `'😀'.debug()` emits raw `'😀'`. The brief notes that non-ASCII char literals **do not lex today**, because the lexer reads bytes. So the widened property is *false* for every non-ASCII scalar unless the same change makes the Char lexer decode UTF-8. That fix must be in this ticket's scope, or the invariant the ticket exists to establish does not hold.
>
> The domain is small (0x10F800 scalars), so the property test should enumerate **all** of it exhaustively, not sample it.
>
> **Cross-language:**
>
> - Rust has the same `\u{…}` syntax, lowercase Debug output, and a surrogate error at lex time. We copy its syntax but not its printable tables.
> - Swift has the same syntax.
> - JS `\u{…}` accepts lone surrogates, which is unsound for a scalar type. We reject them.
>
> ## PLT-2: reject `\x..` permanently
>
> `\x` has no well-typed meaning in a UTF-8 `Str`. `"\xFF"` would build an invalid Str unless we restrict it to ASCII as Rust does. At that point it is a second spelling of `\u{0}`–`\u{7f}`, which violates "one way to do everything".
>
> Close the cancelled 19v5gb scope explicitly: `\x` is a lexer error with a fix-it.
>
> ```blink
> "\x1b[0m"   // error: unknown escape `\x`; write `\u{1b}`
> ```
>
> **A connected issue I flag but do not propose to decide:** an unknown Str escape is only a warning that keeps the backslash. Once `\u` exists, that fallback is unsound, because a typo such as `\U{7}` silently produces text the author did not intend. It should become an error for parity with Char. This could be its own ballot question. The spec's Str table should also list `\b` and `\f`, which the lexer already accepts.
>
> ## PLT-3 (alternative, not primary): a larger frozen output class
>
> Output class = Cc ∪ a **list written out in the spec**: bidi controls U+202A–202E and U+2066–2069, zero-width characters U+200B–200F, U+2028/2029, and U+FEFF.
>
> It gains visibility of Trojan-Source bidi characters and invisible characters in debug diffs. It stays version-independent because the list is spelled out in the spec and does not follow a Unicode category. The cost is a second rule that people must learn and an arbitrary boundary: why these and not the other Cf characters?
>
> I prefer to ship PLT-1 now. PLT-3 is a strict superset, so it can come later without breaking the round-trip property. It only changes which scalars take the escaped branch, and both branches round-trip. This is the reason the Cc choice does not limit the language later.
>
> ## Tradeoffs (PLT view)
>
> - **For PLT-1:**
>   - Debug stays a total, pure, version-stable function.
>   - The round-trip property covers the whole Char/Str domain and a test can prove it exhaustively.
>   - There is one escape production for both literal grammars.
>   - Lexing rejects invalid scalars, which extends the checks of `Char.from_code_point` to compile time.
> - **Against PLT-1:**
>   - `'\u{0}'` and `'\0'` are two input spellings of one value. Output is canonical, so this is only a style question. It could get a lint later.
>   - Adding UTF-8 decoding to the Char lexer increases the ticket's scope.
>   - The change to `\u{` inside Str is technically a breaking change.
>
> **Vote intent:** PLT-1 plus PLT-2, landing together with the UTF-8 Char-lexing fix in the same change.

##### DevOps/Tooling

> # DevOps/Tooling — Phase A submission (qvan6m: `\u{N}` input + output)
>
> **My frame:** people read this feature in terminals, CI logs and test-failure diffs. An invisible byte in an `assert_eq` diff costs an hour to find. The design must give the same text on every compiler version, and every error it can produce must be clear.
>
> **Codebase facts that shape my votes:**
> - `rg` finds no `\u{` or `\x..` in `tests/`, `lib/` or `src/` `.bl` files. Adding the escape changes no existing program, so there is no fixture to migrate.
> - Escape errors in the lexer are bare `io.eprintln` strings with no code, and they point at the literal's start, not at the escape (`src/lexer.bl:254,270,943`).
> - An unknown Str escape is only a warning, and the lexer keeps the backslash. Today `"\u{1b}"` compiles with a warning to the 6 literal characters `\u{1b}`.
>
> ---
>
> ## DEV-1 (PRIMARY): `\u{H}` input in Char and Str literals, one canonical output form, a fixed escape set
>
> **Input (lexer), in both `'...'` and `"..."`:**
> - The form is `\u{` + 1 to 6 hex digits + `}`, in either case.
> - The value must be a Unicode scalar value: surrogates and anything over `0x10FFFF` are errors.
> - The check is the same as `Char.from_code_point`'s, so the two paths cannot disagree.
>
> **Output (`Char.debug()` and `blink_char_debug`):**
> - The canonical form is lowercase hex with no leading zeros: `'\u{7}'`, `'\u{7f}'`, `'\u{202e}'`.
> - It is the only way debug output ever spells a scalar. That is what makes golden files stable.
>
> ```blink
> fn main() {
>     let bel = '\u{7}'
>     io.println(bel.debug())              // '\u{7}'
>     io.println('\u{1F600}'.debug())      // '😀'   (printable: raw UTF-8, as ratified)
>     io.println('\u{41}'.debug())         // 'A'
>     io.println(Char.from_code_point(0x202E).unwrap().debug())  // '\u{202e}'
> }
> ```
>
> **The escape set is a fixed table of code-point ranges in the spec, not a Unicode-database lookup:**
> - Cc: `0x01–0x07`, `0x0B`, `0x0E–0x1F`, `0x7F`, `0x80–0x9F`. The named escapes keep priority, so `\n` stays `'\n'`.
> - The invisible and bidi format controls: `U+200B–U+200F`, `U+2028–U+2029`, `U+202A–U+202E`, `U+2060–U+2064`, `U+2066–U+2069`, `U+FEFF`.
>
> Why a fixed table:
> - **Stable output across versions.** If "printable" means "per Unicode's general category", then a Unicode data update changes `debug()` output. Every snapshot test in every user repo would then break on a compiler upgrade with no source change. Go's `strconv.IsPrint` follows the Unicode version, and Go users have hit this.
> - **Bidi overrides are a security matter, not a style choice.** A raw `U+202E` in a debug line reorders the rest of the terminal line and the CI log (Trojan Source, CVE-2021-42574). A zero-width space in a diff reads as "these two lines are equal". Rust's `char::escape_debug` escapes the grapheme-extend and bidi class for this reason.
>
> **Diagnostics.** Each gets a code and a span on the escape itself:
>
> ```
> error[E0110]: invalid unicode escape: 0xD800 is a surrogate, not a Unicode scalar value
>  --> app.bl:3:15
>   |
> 3 |     let c = '\u{D800}'
>   |              ^^^^^^^^ surrogates (0xD800–0xDFFF) cannot be a Char
> ```
>
> ```
> error[E0110]: invalid unicode escape: expected 1–6 hex digits inside \u{...}
>   |     let c = '\u41'
>   |              ^^^ help: write '\u{41}'
> ```
>
> ```
> error[E0111]: unknown escape '\x' in char literal
>   |     let esc = '\x1b'
>   |                ^^^^ help: Blink has one hex form: write '\u{1b}'
> ```
>
> Other cases give the same error with a different message: `\u{}`, more than 6 digits, a non-hex digit, and a value over `0x10FFFF`. The `\x` fix-it gives what cancelled task 19v5gb asked for (`\x1b` for ANSI) through a single syntax, which fits "one way to do everything".
>
> **`blink fmt`:** keep the author's case and digits. Do not rewrite `\u{41}` to `A` or `\u{0007}` to `\u{7}`. Changing source text is lint work, not formatter work (see DEV-3). Go precedent: gofmt normalised number-literal prefixes only from 1.13, behind a language-version gate, and it caused diff churn.
>
> **Tradeoff:** a 22-row range table in the spec and runtime, in exchange for output that never changes between versions. I take that trade.
>
> ---
>
> ## DEV-2 (co-requisite, same change): `Str.debug()` uses the same escaper
>
> `blink_str_debug` has the same raw-control gap, and `Str` shows up far more often than `Char` in failure diffs (`assert_eq(got, want)` on strings). If Char gets the fix and Str does not, users see inconsistent output.
>
> ```blink
> test "ansi output" {
>     assert_eq(render(), "\u{1b}[31mred\u{1b}[0m")
> }
> // failure diff:
> //   left:  "\u{1b}[31mred\u{1b}[0m\u{200b}"
> //   right: "\u{1b}[31mred\u{1b}[0m"
> ```
>
> Without DEV-2, the terminal would interpret those `ESC` bytes and paint the CI log red, and the zero-width space would be invisible.
>
> - **One owner.** A single C helper, `blink_scalar_escape`, used by both `blink_char_debug` and `blink_str_debug`.
> - **Invariant widens to Str:** `parse(s.debug()) == s`.
> - **Semantic change is safe.** Adding `\u{` to the Str lexer changes the meaning of text that today only produces a warning, and the corpus has zero uses of it.
>
> ---
>
> ## DEV-3 (secondary): the gate and tooling around it
>
> 1. **Two property tests in CI:**
>    - Every scalar `0..0x10FFFF` except surrogates: `Char.from_code_point(n)` → `.debug()` → lex → equal.
>    - A Str corpus test with the same property.
>
>    The first test is about 1.1M iterations, which takes seconds. It is also the only way to prove the "full codepoint space" claim in the ticket.
> 2. **Non-ASCII char literals must lex in the same change.** Today `'😀'` fails ("must contain exactly one character") because the lexer reads bytes. The ratified debug output `'😀'` therefore does not re-lex now, and it still will not after `\u{}` lands. Round-trip over the full space requires UTF-8 decoding in the Char lexer. Without it, the property test fails on U+0080 and up. I flag this as a hard prerequisite, not scope creep.
> 3. **Optional lint, W-level, `blink lint` only (not the compiler):** `\u{H}` for a printable scalar outside the escape table, for example `'\u{41}'`. Help: "write 'A'". This keeps the formatter from changing source text while still steering AI-written code to the one readable form.
> 4. **Separate friction ticket:** an unknown Str escape should be an error, as it is for Char, not a warning that keeps the backslash. I am not voting that here.
>
> **Cross-language notes:**
> - Rust's `{:?}` is the model here: `'\u{7}'`, lowercase, no padding, bidi escaped.
> - Python's `repr` shows `'\x07'`, which is two forms with `\u`/`\U`.
> - JSON's `\u0007` needs exactly 4 digits and surrogate pairs above the BMP. I reject it because the fixed width breaks down above `0xFFFF`.

##### AI/ML

> # AI/ML panelist, Phase A submission (spec gap: `\u{N}` input and Char debug output)
>
> I split the gap into five sub-questions: input syntax, `\x`, output set, output spelling, and Str parity. **AI-1 is my primary.** AI-2 and AI-3 are separate add-ons. Vote on each one by itself.
>
> ---
>
> ## AI-1 (PRIMARY): one `\u{H}` escape, in both input and output, for Char and Str
>
> **Input (lexer), same rule in `'...'` and `"..."`:**
> - Syntax is `\u{` followed by 1 to 6 hex digits, then `}`. Upper and lower case are both accepted.
> - Valid range is U+0000 to U+10FFFF, surrogates excluded. This is the same range check as `Char.from_code_point`.
> - There is no `\x..`, `\uXXXX` or `\U00XXXXXX`. All three are lexer errors, and each error names the exact rewrite.
> - The `{` after `\u` belongs to the escape and never starts interpolation.
> - `#"..."#` strings are unchanged: no escape processing at all.
>
> ```blink
> let bell = '\u{7}'
> let smile = '\u{1F600}'          // replaces Char.from_code_point(0x1F600) plus the Result
> let reset = "\u{1b}[0m"          // ANSI: the most common reason people want \x1b
> let raw = #"\u{41}"#             // 7 literal chars, no escape
> ```
>
> **Output (debug):** each scalar follows a three-step rule. The first step that matches wins.
> 1. If it has a named escape, emit that escape: `\n \r \t \\ \b \f \0`, plus `\'` for Char or `\"` `\{` `\}` for Str.
> 2. Else, if it is a control character (Unicode general category Cc: U+0000–U+001F or U+007F–U+009F), emit `\u{h}`. Use lowercase hex with no leading zeros.
> 3. Else, emit the raw UTF-8.
>
> ```blink
> io.println(Char.from_code_point(7).unwrap().debug())       // '\u{7}'
> io.println(Char.from_code_point(0x7F).unwrap().debug())    // '\u{7f}'
> io.println('\0'.debug())                                   // '\0'   (named escape wins)
> io.println('😀'.debug())                                   // '😀'   (printable, stays raw)
> io.println("\u{1b}[0m".debug())                            // "\u{1b}[0m"
> io.println(['a', '\u{7}'].debug())                         // ['a', '\u{7}']
> ```
>
> **The invariant becomes total:** `parse(c.debug()) == c` for every Char. Two things must land in the same change for this to hold:
> - The lexer must decode a raw UTF-8 char literal (`'😀'`). The spec table already promises it, and today it fails.
> - The round-trip property test must widen to the full scalar range.
>
> **Why this suits AI code generation:**
> - **One spelling.** Rust, Swift and ES6 JS all use `\u{...}`, so this matches the strongest prior in model training data. Every alternative adds a decision point with no gain: `\x` for bytes versus `\u` for scalars, or 4-digit versus braced forms.
> - **The output rule is a range check, not a table.** A model can predict `debug()` output from the spec alone. Rust's `escape_debug` uses internal Unicode printability tables, and no model can reproduce those exactly. A model that cannot predict debug output writes wrong `assert_eq` goldens.
> - **Canonical output.** Lowercase hex with no leading zeros matches Rust's `'\u{7}'` byte for byte. Input stays lenient on case and leading zeros, so generated code never fails on a cosmetic choice.
> - **Fewer tokens.** `'\u{1F600}'` is about 6 tokens and cannot fail. `Char.from_code_point(0x1F600).unwrap()` is about 12 tokens and adds an unwrap.
> - **Errors a model can act on.** Python, Java and JS models will write `\x1b`, `é` and `\U0001F600`. Each error names the one valid form:
>
> ```
> error: unknown escape '\x1b' in string literal
>   help: use '\u{1b}'
> error: '\u' escape needs braces: write '\u{e9}'
> error: '\u{D800}' is a surrogate, not a Unicode scalar value
> error: '\u{110000}' is out of range (max \u{10FFFF})
> error: '\u{name}': expected 1-6 hex digits
> ```
>
>   A model fixes each of these in one turn, with no guessing.
>
> **Str parity:** `blink_str_debug` has the same raw-control gap, so it gets the same rule, applied per decoded scalar instead of per byte. Because a Str cannot hold NUL, `"\u{0}"` and `"\0"` in a Str literal are lexer errors ("Str cannot contain NUL").
>
> **Cost:** the hex digits add some noise to Str debug output for ANSI-heavy strings. That is acceptable, because debug output is meant to be faithful, not pretty.
>
> ---
>
> ## AI-2 (add-on): also escape a fixed list of invisible format characters
>
> Add a step 2b with a closed list written out in the spec, so there is no reference to a Unicode table:
> - U+200B–U+200F (zero-width characters and LRM/RLM)
> - U+2028–U+202E (line and paragraph separators, bidi embeddings and overrides)
> - U+2060–U+2064
> - U+2066–U+2069 (bidi isolates)
> - U+FEFF (BOM)
>
> ```blink
> io.println("a\u{200b}b".debug())    // "a\u{200b}b"   (not "a​b", which looks like "ab")
> ```
>
> **Argument:** models read debug output in logs and test failures. An invisible U+200B or a bidi override makes `"ab" != "ab"` look impossible, and the model then guesses at the cause. Printing the character's code makes the failure diagnosable.
>
> **Cost:**
> - About 20 scalars to learn, as a written list.
> - It is less aligned with the Rust prior: Rust escapes some of these through its tables, not by a rule.
>
> I support AI-2 but would drop it before I weakened AI-1.
>
> ---
>
> ## AI-3 (coupled clean-up): one escape table, and unknown Str escapes become errors
>
> Today an unknown Str escape is only a warning, and the lexer keeps the backslash literally. A model trained on Python writes `"\x1b[31m"`. Today that compiles to the four literal characters `\x1b` with a warning, the colour never appears, and the model has no error to learn from. Once AI-1 exists, that warning path is a trap.
>
> - Make an unknown Str escape an error, consistent with Char.
> - Document one shared table: the common set `\n \r \t \\ \b \f \0 \u{H}`. Char adds `\'`. Str adds `\" \{ \}` and excludes NUL.
> - This also fixes a spec drift: the Str lexer accepts `\b` and `\f`, but §02 does not list them.
>
> Migration: `rg` the tests for backslash-literal reliance first. I expect near zero hits.
>
> ---
>
> ## Rejected options
>
> - **`\x..` as well as `\u{}`:** creates two spellings for U+001B. Blink Str holds scalars, not arbitrary bytes, so `\x` has no job of its own. This is a pure decision point.
> - **Uppercase or zero-padded output (`\u{0007}`):** departs from the Rust and Swift outputs that models already reproduce, and gains nothing.
> - **Escaping all non-ASCII:** breaks the ratified `'😀'` → `'😀'` rule.
>
> **Summary vote intent:** AI-1 (primary), AI-3 yes, AI-2 lean yes.

##### Minimalism

> # Minimalism submission: `\u{N}` escapes (qvan6m)
>
> The ticket looks like "add one Char output form". It carries four smaller questions:
>
> - **Q1.** Where does `\u{...}` exist as input?
> - **Q2.** What is its exact grammar?
> - **Q3.** Which scalars does `debug()` escape?
> - **Q4.** Does `Str.debug()` follow the same rule?
>
> My primary proposal is MIN-1. It answers all four with the smallest rule that is still correct.
>
> ---
>
> ## MIN-1 (PRIMARY): one `\u{hex}` escape everywhere; `debug()` escapes exactly Unicode category Cc
>
> **Q1. Input: add `\u{...}` to both Char and Str literals, and add no `\x..`.**
>
> An escape that works in `'...'` but not in `"..."` would add a new decision point. Both literal forms should get one escape table. `\x1b` covers a subset of what `\u{1b}` covers, so adding it would give two spellings for one thing (§1: "one way"). The cancelled 19v5gb asked for `\x1b` so users could write terminal colours. `\u{1b}` meets that need. Raw strings `#"..."#` do not change, because they do no escape processing.
>
> ```blink
> let bel = '\u{7}'
> let smile = '\u{1F600}'
> let red = "\u{1b}[31merror\u{1b}[0m"
> io.println(red)
> ```
>
> **Q2. Grammar: `\u{` + 1–6 hex digits + `}`.**
>
> - Hex digits may be upper or lower case.
> - There are no `_` separators and no sign.
> - The value must be a Unicode scalar value. Surrogates (0xD800–0xDFFF) and values above 0x10FFFF are lexer errors, which matches `Char.from_code_point`.
> - A malformed `\u` is always an error, in Str as well as Char. Today an unknown Str escape is only a warning that keeps the backslash. That leniency must not apply here: if `"\u{zz}"` quietly became the text `\u{zz}`, the typo would reach production.
>
> ```blink
> '\u{D800}'    // error: surrogate
> '\u{110000}'  // error: out of range
> '\u{}'        // error: empty
> "\u{1F600"    // error: unterminated
> ```
>
> **Q3. Output: named escape first, then `\u{N}` for Cc, then everything else raw.**
>
> "Non-printable" is where scope grows without limit. Rust's `is_printable` uses generated Unicode tables. Python's `repr` uses the full category database. We need neither. The Cc category is exactly two ranges, `0x00–0x1F` and `0x7F–0x9F`. It is defined by a standard, it will not change, and one range check tests it. It also includes the C1 controls, which really can damage a terminal (a raw `0x9B` is CSI). Format characters (Cf, such as ZWJ), unassigned code points and whitespace are printed raw, as they are today. If users need them escaped, that can be added later.
>
> The emitted form uses lowercase hex with no leading zeros, which matches Rust. Each scalar then has exactly one debug string.
>
> | Char | `debug()` |
> |---|---|
> | `'\n'` | `'\n'` (named escape wins) |
> | `'\0'` | `'\0'` (not `'\u{0}'`) |
> | `'\u{7}'` | `'\u{7}'` |
> | `'\u{1b}'` | `'\u{1b}'` |
> | `'\u{9b}'` | `'\u{9b}'` |
> | `'\u{7f}'` | `'\u{7f}'` |
> | `'😀'` | `'😀'` (raw, unchanged) |
> | `'\u{200d}'` | raw ZWJ (Cf, not escaped) |
>
> After this change the invariant covers every scalar: `parse(c.debug()) == c`. The round-trip property test can then enumerate all 1,112,064 scalars, or sample them with the ranges forced into the sample.
>
> **Q4. `Str.debug()` uses the same rule in the same change.**
>
> If Char escapes BEL and Str prints it raw, "debug output is re-readable" becomes two rules for two textual types. That breaks the §3.6 principle that the textual scalars render in their own literal syntax, escaped. One escaper can serve both, with a parameter for the delimiter (`'` or `"`) and one for which named-escape table applies. `blink_str_debug` already has the same gap with raw control bytes (brief fact 5), so this fixes a bug. It does not add a feature.
>
> ```blink
> io.println("a\u{7}b".debug())   // "a\u{7}b"
> io.println("x\ty".debug())      // "x\ty"
> ```
>
> One note on Str's named escapes: the §02 table omits `\b`/`\f` but the lexer accepts them. The spec and lexer must agree. The cheapest fix is to document the lexer behaviour, so Char and Str share the named set plus their own delimiter escapes. Whatever we pick, `Str.debug()` must emit only escapes that the Str lexer accepts.
>
> **Minimalism accounting.** This adds one escape form and removes two things: the hex escape idea from 19v5gb, and the permanent "v1 gap" paragraph in §3.6. The combinatorial cost is low. `\u{}` does not interact with interpolation (`{` after `\u` is part of the escape, not a hole), raw strings, or Template.
>
> Cross-language: Rust and Swift use `\u{N}` with 1–6 digits (Swift allows 1–8). JS added `\u{}` in ES6 because the fixed-width `\uXXXX` could not express astral code points. Take the modern form and none of the older ones.
>
> ---
>
> ## MIN-2 (fallback): Char input and output only; Str deferred
>
> This is the ticket as written: `\u{}` in Char literals plus Char debug output, with Str left alone. It is smaller today. I rank it second because it creates the exact Char/Str difference that §1 forbids. An AI that writes `'\u{1b}'` will then write `"\u{1b}"` and get a warning plus a literal backslash. Deferring it saves perhaps 30 lines and costs a known bug that users will hit. I support it only if the panel wants the smallest possible diff.
>
> ---
>
> ## MIN-3 (rejected, tabled for completeness): close the ticket, keep raw output
>
> Raw output works as a debug form, and BEL in a Char is rare. I reject this for two reasons:
>
> - The terminal-escape use case (`"\u{1b}[..."`) is common. Today it forces `Char.from_code_point(27).unwrap().to_str()` concatenation, which is noise that AI-written code will get wrong.
> - Raw C1 bytes in debug output can corrupt the terminal that shows a failing test.
>
> Either reason alone passes the burden of proof.
>
> ---
>
> ## Out of scope, but flag it
>
> `'😀'` does not lex today. The lexer reads bytes, and the §3.6 table's `'😀'` row is aspirational. `\u{1F600}` is **not** a fix for that, and shipping it must not close the issue. It is a separate `type:bug` (the §02 wording already says "one Unicode scalar value"). With MIN-1, a user can write a literal emoji either way, so both input paths must work, and the round-trip test should cover raw non-ASCII too.
>
> **Vote intent:** MIN-1 > MIN-2 >> MIN-3.

#### Phase A.5 — Mechanical dedupe (moderator)

> # Phase A.5 — deduped option-space (mechanical)
>
> Full Phase A texts of all six panelists are in the same directory: phaseA_{sys,web,plt,devops,aiml,min}.md. Read the others before replying.
>
> ## Core — proposed identically by all six (SYS-1, WEB-1, PLT-1+PLT-2, DEV-1+DEV-2, AI-1, MIN-1)
>
> - Input: `\u{` + 1–6 hex digits + `}`, upper or lower case accepted, in BOTH `'...'` and `"..."`. Not in `#"..."#`.
> - Value must be a Unicode scalar value (surrogates, > 0x10FFFF, empty braces, > 6 digits, non-hex → lexer error). Same bounds as `Char.from_code_point`.
> - `{` after `\u` belongs to the escape, never opens interpolation.
> - In a Str literal `\u{0}` is a lexer error (Str cannot hold NUL).
> - No `\x..` (lexer error with a fix-it naming `\u{..}`). No `\uXXXX` / `\U........`.
> - Debug output order: named escape first → `\u{h}` (lowercase hex, fewest digits) for the escape class → raw UTF-8 otherwise.
> - `Str.debug()` uses the same rule in the same change as `Char.debug()`.
> - Round-trip: `parse(c.debug()) == c` for every Char; `parse(s.debug()) == s` for every Str.
> - MIN-2 (Char-only, fallback) and SYS-2 (Char-only, proposer rejects it) exist as a narrower alternative. MIN-3 (close ticket, keep raw) was tabled and rejected by its own proposer.
>
> ## Variations flagged for debate
>
> **V1 — the output escape class.**
> - V1-a: Unicode general category Cc only — U+0000–001F, U+007F, U+0080–009F (primary of sys, web, plt, aiml, min).
> - V1-b: Cc plus a fixed range list written out in the spec (not a Unicode-version lookup): U+200B–200F, U+2028–2029, U+202A–202E, U+2060–2064, U+2066–2069, U+FEFF (primary of devops DEV-1; offered as optional add-on by sys SYS-3, plt PLT-3, aiml AI-2).
> - WEB-2: Cc plus Cf/Zl/Zp/non-U+0020 whitespace by Unicode property table — web defers it to a follow-up.
>
> **V2 — raw UTF-8 char literals (`'😀'`, which does not lex today).**
> - V2-a: must land in the same change as `\u{..}`, as a precondition of the widened round-trip (sys, web, plt, devops, aiml).
> - V2-b: a separate `type:bug`; `\u{1F600}` must not close it; the round-trip test should cover raw non-ASCII too (min).
> - Fact: the moderator has already filed that lexer defect as bug ticket rpgx9b ("Lexer rejects a non-ASCII char literal such as '😀' because it reads the literal by byte").
>
> **V3 — unknown/malformed escapes in Str literals** (today: warning, backslash kept).
> - Malformed `\u` is an error in Str as in Char (sys, plt, aiml, min, web, devops — all state this).
> - Whether EVERY unknown Str escape becomes an error in this decision: yes (aiml AI-3; web wants at least `\x` and brace-less `\u` as errors); flag but not decide here (plt); separate ticket, not voting it here (devops).
> - Fact: an open ticket py1ssk already covers "Lexer reports unknown escapes via eprintln: no code, exit 0, string escape drops the char".
>
> **V4 — `blink fmt` and hex spelling.**
> - WEB-3: `blink fmt` rewrites `\u{1F600}` / `\u{01f600}` to the canonical `\u{1f600}`.
> - DEV-1/DEV-3: `blink fmt` keeps the author's spelling; an optional `blink lint` warning for `\u{H}` naming a printable scalar outside the escape class (e.g. `'\u{41}'` → "write 'A'").
> - Others did not address it.
>
> **V5 — the Str named-escape table.**
> - The lexer accepts `\b` and `\f` in Str, but §02's Str table omits them (fact; moderator filed friction ticket hp33mm).
> - AI-3/MIN-1: document one shared table (common set `\n \r \t \\ \b \f` + `\u{H}`; Char adds `\0 \'`; Str adds `\" \{ \}`) so the spec matches the lexer. PLT: the Str table should list `\b` and `\f`. Others did not address it.
> - Consequence for output: with `\b`/`\f` in the Str table, `Str.debug()` emits `\b`/`\f` for U+0008/U+000C; without, those take the `\u{8}`/`\u{c}` form.
>
> **V6 — diagnostics.** DEV-1 proposes codes (e.g. E0110 invalid unicode escape, E0111 unknown escape) with a span on the escape and fix-it help. AI-1 proposes equivalent message texts. No one opposed.

#### Phase B — Debate, round 1 (final positions)

All six panelists sent "STABLE — ready to vote" after one round.

##### Systems

> # Systems — Phase B round 1
>
> **Core: I agree with every point.** One implementation note, not an objection: one shared C escaper serves both `blink_char_debug` and `blink_str_debug` (DevOps' `blink_scalar_escape`, MIN's delimiter parameter). Str.debug sizes its buffer in two passes (count, then write), not `n*6+3`.
>
> **V1 (escape class): V1-a first, V1-b second, WEB-2 rejected.**
> - WEB-2 is the one option I oppose outright. A Unicode property table makes the bytes of `debug()` depend on the Unicode version the compiler was built with, so snapshot tests break on a compiler upgrade. It also puts kilobytes of table in every binary.
> - V1-b has neither problem. It is a frozen list, and the check is 6 range compares, run only after a `0xE2` or `0xEF` lead byte.
> - DevOps' bidi/CI-log argument (CVE-2021-42574) is the strongest point for V1-b, and it applies to Str.debug more than to Char. It is not the only possible answer, though. MIN's worry about where the list stops is also real.
> - I vote V1-a. I accept V1-b if the spec states that the list is closed and will change only by a new panel decision, never by a Unicode update.
>
> **V2: V2-a, with MIN's split kept.**
> - rpgx9b can stay its own `type:bug`, and `\u{1F600}` must not close it (I agree with MIN).
> - qvan6m must depend on rpgx9b (`br dep`). The widened round-trip test must not land until rpgx9b does, or it fails at U+0080 on its first run.
> - Same change or same release. Separate commits are fine.
>
> **V3: decide only what this decision creates.**
> - Malformed `\u`, brace-less `\u41`, and `\x..` are errors in Str and Char, with a fix-it that names `\u{..}`.
> - `\x` belongs here because this decision rejects it. Today `"\x1b[31m"` silently prints a literal `\x1b` (WEB), which is exactly the output 19v5gb users would hit.
> - Making every other unknown Str escape an error stays with py1ssk. It changes the meaning of existing programs, and nobody here measured that.
>
> **V4: keep the author's spelling in `blink fmt` (DEV).**
> - A formatter that rewrites token text inside literals is a new class of formatter behavior, and the gain is cosmetic. Debug output is already canonical, and that is the form machines compare.
> - Neutral on the optional lint. It does not block.
>
> **V5: document `\b` and `\f` in the Str table (AI-3 / MIN-1 / PLT).**
> - The lexer already accepts them. Removing them would break source for no gain.
> - Consequence: Str.debug emits `\b` and `\f`, which are shorter than `\u{8}` and `\u{c}`.
> - One shared table: common escapes `\n \r \t \\ \b \f` plus `\u{H}`; Char adds `\0 \'`; Str adds `\" \{ \}`.
>
> **V6: specify the diagnostics, not the numbers.**
> - The spec should require that each error has a span on the escape itself and a fix-it (`\x1b` → `\u{1b}`, `\u41` → `\u{41}`).
> - Fact: no E01xx code exists and the lexer has no coded diagnostics. Picking E0110/E0111 here would set up a numbering range as a side effect of an escape decision.
> - Put the codes on py1ssk (lexer diagnostic infrastructure) and let this decision state only the messages and spans.
>
> STABLE — ready to vote

##### Web/Scripting

> Web/Scripting — Phase B round 1
>
> **Core:** I accept it as written. No objection.
>
> **V1 (escape class): I move from V1-a to V1-b.** DevOps changed my mind. My WEB-2 asked for Cf/Zl/Zp by Unicode property table. DevOps showed that choice is worse: a Unicode data update would change `debug()` output and break every user's snapshot tests after a compiler upgrade with no source change. That is exactly the kind of "it broke and I changed nothing" bug that fills Stack Overflow. A fixed range list written in the spec keeps what I wanted, without a property table and with stable output:
> - A zero-width space in an `assert_eq` diff shows as `\u{200b}`. It no longer reads as "these two strings are equal", which is the #1 invisible-character confusion for JS/Python devs.
> - A raw U+202E can no longer reorder a CI log line.
>
> The added cost is about 22 rows in one range check. I withdraw WEB-2 in favour of V1-b. I rank V1-a second; it is still a large improvement over raw.
>
> **V2 (raw `'😀'`): I join V2-b, with one condition.** rpgx9b now exists, so tracking it separately is fine. But rpgx9b must be a blocking dependency of this ticket, not a parallel "someday". The spec text that claims `parse(c.debug()) == c` for every Char must not ship before `'😀'` lexes, because the ratified table promises `'😀'` → `'😀'`. Min's point also stands: `\u{1F600}` does not close rpgx9b, and the property test must cover raw non-ASCII input as well as `\u{..}`. With that dependency, V2-a and V2-b are the same outcome.
>
> **V3 (unknown Str escapes): I concede the general case to py1ssk.** This decision only needs these errors:
> - malformed `\u` in both literals (core already says so);
> - `\x..` in both literals with the `\u{..}` fix-it (core already says so);
> - `\u` without braces (`"\u0007"`) in Str as a hard error with the fix-it `\u{7}`.
>
> The last one is the Python/Java/JSON habit, and those users will type it on day one. It sits inside `\u` handling, so it is in scope. It must not fall into the "warning, keep backslash" path. Making every other unknown Str escape an error belongs in py1ssk.
>
> **V4 (fmt): I concede WEB-3 to DevOps.** Keep the author's spelling in `blink fmt`. Rewriting escapes is lint work, and the churn is not worth it. I support the optional lint that flags a `\u{H}` for a printable scalar outside the escape class (`'\u{41}'` → "write 'A'"). That rule also steers AI output to the one readable form.
>
> **V5 (Str table): support AI-3/MIN-1.** Publish one shared table: the common set `\n \r \t \\ \b \f \u{H}`, plus `\0 \'` for Char and `\" \{ \}` for Str. The spec then matches the lexer. `Str.debug()` emits `\b`/`\f`, the same as Char, so `"\u{8}".debug()` and `'\u{8}'.debug()` agree. Two textual types with different debug output for the same scalar would get a bug report.
>
> **V6 (diagnostics): support.** Every `\u`/`\x` error needs a span on the escape itself and a fix-it that shows the corrected literal; for a JS/Python dev, that is most of the value. No E01xx codes exist today, so the implementer should pick the numbers and put them in the diagnostic registry. The panel should vote only on "coded, span on the escape, fix-it", not on specific numbers.
>
> STABLE — ready to vote

##### PLT

> # PLT — Phase B round 1
>
> **Core:** I accept the whole core as written. No objection.
>
> **V1 — I move from V1-a to V1-b.**
>
> My case for Cc rested on one property: `debug()` is a pure function that does not change between versions. DevOps shows that the same property argues against my "add PLT-3 later" point. If we widen the class later, the debug output of about 40 scalars changes once, with no change to the user's source. That is the snapshot churn we set out to prevent. The round-trip property holds under both options, because both branches round-trip. So soundness does not decide this; stability does. Stability says: fix the class once, now.
>
> V1-b is still a closed range list written in the spec. It is not a lookup that depends on the Unicode version. So it keeps every property I asked for. The Trojan-Source concern (U+202E reorders the terminal line) is concrete, not theoretical.
>
> I have two conditions:
> 1. The spec holds the table in one place, and one runtime helper owns it. Char and Str share that helper.
> 2. The table is frozen. Any change to it is a `type:spec` decision, not a patch.
>
> I reject WEB-2 (lookup by Unicode property), because its output changes between versions.
>
> **V2 — I support V2-a in substance, and I reconcile it with MIN.**
>
> rpgx9b can stay a separate bug ticket. But qvan6m must depend on it (`br dep`). The widened round-trip property, "for all c: Char", is false while `'😀'` does not lex. So qvan6m must not close, and the property test must not be scoped to the full scalar range, until both are fixed. MIN is correct that `\u{1F600}` does not close rpgx9b. The test must enumerate the raw non-ASCII path too.
>
> **V3 — I keep my position.**
>
> A malformed `\u`, and `\x`, are errors (core). The general rule that every unknown Str escape becomes an error is a separate soundness fix, and py1ssk already covers it. I support that fix, but not inside this ballot.
>
> **V4 — I side with DEV (fmt keeps the author's spelling).**
>
> The canonical form is a property of `debug()` output. Source text does not need it. `debug()` is a section of `lex`: `lex ∘ debug = id`. We only need `debug` to be deterministic, not `fmt ∘ lex`. A formatter that rewrites literal contents adds a second place that owns the escape table. The lint is optional and outside this decision.
>
> **V5 — I support the shared table.**
>
> - Common set: `\n \r \t \\ \b \f` and `\u{H}`.
> - Char adds: `\0` and `\'`.
> - Str adds: `\"`, `\{` and `\}`.
>
> This makes the spec match the lexer (hp33mm). It also means `'\u{8}'.debug()` and `"\u{8}".debug()` both give `\b`, with the same rule for both quote styles. Without it, U+0008 has a named escape in Char and a hex escape in Str. That is a gratuitous difference, and a model would learn it as a rule.
>
> **V6 — not a spec question.**
>
> The lexer emits no diagnostic codes today. Allocating an E01xx series is a design decision for the tooling and diagnostics area (py1ssk is a natural place for it). It is not a language rule. The spec should require:
> - a lexer error,
> - a span on the escape itself,
> - a fix-it for `\x` and for `\u` without braces.
>
> The code numbers can stay open. I don't object to the proposed E0110 and E0111 if the moderator wants to allocate them.
>
> STABLE — ready to vote

##### DevOps/Tooling

> # DevOps/Tooling — Phase B round 1
>
> **Core:** I agree with every core point. No objection.
>
> **V1 (escape class): I hold V1-b and accept V1-a as the fallback.**
> - **Correction to my Phase A:** the list is the Cc ranges plus 6 extra ranges. It is not "22 rows".
> - **On "where does the list stop" (sys, plt):** it stops where the spec says. The list is frozen. Only a panel vote can add a range, the same as for any change to the escape tables. That makes it as version-independent as Cc, which is the property plt and sys both care about.
> - **On "a second rule to learn" (plt):** for the user it is one rule: "escape when the scalar is in this table". They read the table in §3.6 and do not have to know Unicode categories.
> - **Why the cost is worth it:** the bug that V1-b catches is the most expensive one in my domain. That bug is `assert_eq("ab", "ab")` failing on an invisible U+200B, or a U+202E that reorders a CI log line. aiml says the same from the model side.
> - **Cost:** a few compares on 3-byte UTF-8 lead sequences, and no table in the binary.
> - If V1-a wins, file V1-b as a follow-up `type:spec`. Do not use WEB-2's property-table form.
>
> **V2 (raw UTF-8 char literals): V2-a in effect, whatever the ticket layout.**
> - rpgx9b can stay a separate bug, but it must block qvan6m (`br dep add`).
> - The widened round-trip test must cover raw non-ASCII. If it does not, the "full codepoint space" claim is false the day it ships.
> - min's point stands: `\u{1F600}` does not close rpgx9b.
>
> **V3 (unknown escapes in Str): I move toward web.**
> - In this change, make these hard errors in Str:
>   - a malformed `\u{..}`;
>   - `\u` without braces;
>   - `\x`.
>
>   web is right that `"\x1b[31m"` silently printing a literal `\x1b` is the worst result for exactly the users who asked for 19v5gb.
> - All other unknown Str escapes stay with py1ssk. Do not decide them here.
>
> **V4 (fmt): I concede to WEB-3, with one limit.**
> - My concern was diff churn. The corpus has zero `\u{` uses, so normalizing now costs nothing.
> - So `blink fmt` rewrites hex spelling to the debug spelling, `\u{1F600}` / `\u{01f600}` → `\u{1f600}`. It is idempotent and keeps semantics, like gofmt's `0X` → `0x`.
> - **The limit:** fmt never swaps between an escape and a raw character in either direction. `'\u{41}'` stays as written, and so does a raw BEL. That swap stays an optional `blink lint` warning. A formatter that changes which characters show on screen in a literal is a review hazard.
>
> **V5 (Str table): I support the shared table (AI-3/MIN-1).**
> - The spec must match the lexer, and the lexer already accepts `\b` and `\f` in Str.
> - A consequence: `Str.debug()` emits `\b` / `\f`, the same as `Char.debug()`. That is one output rule for both types, which is better for golden files.
>
> **V6 (diagnostics): keep the requirement, drop my numbers.**
> - There are no E01xx codes today, and the lexer emits no coded diagnostics. So the decision should not pick numbers.
> - It should require three things for each new lexer error:
>   1. a registered code, which the implementation assigns;
>   2. a span on the escape, not on the start of the literal;
>   3. fix-it help where one exists (`\x1b` → `\u{1b}`, `\u41` → `\u{41}`, Str `\u{0}` → "a Str cannot hold NUL").
> - This change must not add new uncoded `io.eprintln` sites. The existing ones stay with py1ssk.
>
> STABLE — ready to vote

##### AI/ML

> # AI/ML — Phase B round 1
>
> **Core: I agree with every point. I have no objection.**
>
> **V1 (escape class): I move from V1-a to V1-b, but only as a closed list.**
> DevOps is right about the failure mode. Models read debug output in CI logs and test diffs. A raw U+202E reorders the line, and a raw U+200B makes `"ab" != "ab"` look impossible. When that happens a model invents a cause and "fixes" code that was correct. That costs more than learning six ranges.
>
> The version-stability argument does not separate the two options. Unicode's stability policy freezes Cc, so V1-a is stable too. What matters is that V1-b is also stable, provided the spec states it as a literal range list that never tracks a Unicode version. I vote V1-b on that condition. I reject WEB-2 (a property-table lookup): no model can predict its output from the spec, and that is the property I care about most.
>
> **V2 (raw UTF-8 char literals): V2-a on substance; procedure is not important to me.**
> The widened round-trip test (`parse(c.debug()) == c` for all scalars) cannot pass until `'😀'` lexes. Min's V2-b is acceptable if rpgx9b stays its own bug and qvan6m is blocked by it (`br dep`). That keeps the bug separate and still stops the invariant from being claimed early. I agree with Min that `\u{1F600}` must not close rpgx9b.
>
> **V3 (unknown Str escapes): I withdraw AI-3's full change from this vote.**
> Making every unknown Str escape an error belongs to py1ssk. In this decision, three things must be errors in Str as well as Char:
> - malformed `\u{...}`
> - brace-less `\uXXXX` and `\U...`
> - `\x..`
>
> These are the exact mistakes that models trained on Python, JS or Java will make with the new feature. If `"\x1b[31m"` stays a warning that keeps the backslash, the colour silently never appears, and the model gets no error to learn from.
>
> **V4 (fmt): DEV spelling, against WEB-3.**
> Input accepts any case and leading zeros, and output is canonical. Nothing a model learns from depends on the formatter rewriting hex digits. A rewrite only adds diff churn. The lint for `'\u{41}'` → "write 'A'" is harmless, but it is optional and should not be part of this vote.
>
> **V5 (Str table): yes, one shared table.**
> - The common set is `\n \r \t \\ \b \f` plus `\u{H}`.
> - Char adds `\0` and `\'`.
> - Str adds `\"`, `\{` and `\}`.
> - `Str.debug()` emits `\b` and `\f` for U+0008 and U+000C.
>
> One table is one thing to learn. Making the spec match the lexer removes a hidden rule.
>
> **V6 (diagnostics): the spec should fix the content, not the code numbers.**
> The spec should require three things:
> - a span on the escape itself
> - a message that names the defect (surrogate, out of range, bad digits, missing braces, `\x`)
> - a help line that gives the exact `\u{..}` rewrite
>
> That help line is how a model corrects itself. The lexer emits no coded diagnostics today, so assigning E01xx codes belongs to py1ssk, or to the implementation, and should not block this decision.
>
> STABLE — ready to vote

##### Minimalism

> # Minimalism — Phase B round 1
>
> **Core:** I agree with every point. No objection.
>
> **V1 — escape class. I move from V1-a to V1-b.**
> PLT says V1-b can come later without harm, because both branches round-trip. That is true for the parser but false for users. Each scalar that moves into the escape class later changes `debug()` output, and every user's snapshot and golden file breaks on a compiler upgrade with no source change. That is the churn DevOps named. So "defer the superset" does cost something. We should fix the class once, now.
>
> V1-b is written out in the spec as six ranges with no Unicode lookup. That makes it as stable as Cc (Cc itself is fixed by Unicode's stability policy). The cost is a few range checks in one escaper. The benefit is concrete: a Trojan Source bidi override (CVE-2021-42574) cannot reorder a CI log line, and a zero-width space cannot hide inside an `assert_eq` diff. That clears the burden of proof.
>
> The objection "why these and not all Cf?" has an answer: the list is "characters that change or hide the text around them in a terminal". That is a closed purpose, not an open category.
>
> I reject WEB-2. Property tables follow the Unicode version, which is the churn we are avoiding.
>
> Vote: V1-b > V1-a >> WEB-2.
>
> **V2 — raw UTF-8 char literals. I concede to V2-a.**
> My Phase A position was procedural: keep the bug separate. But the ticket exists to establish `parse(c.debug()) == c` over the full space, and under that invariant the raw `'😀'` output is the common case, not the edge case. We cannot ratify an invariant that the first property-test run disproves. rpgx9b must land in the same change, or at least block this one. Keep the ticket and link it as a blocker.
>
> **V3 — unknown Str escapes.**
> A malformed `\u` and `\x` are errors, as the core already says. Making every other unknown Str escape an error is a separate change with a separate migration question, and py1ssk already owns it. Do not decide it here. YAGNI on scope, not on correctness.
>
> **V4 — fmt and hex spelling.** I support DEV-1: `blink fmt` keeps the author's spelling. A formatter that rewrites escape contents is a new behaviour with no stated need. The optional `blink lint` for `'\u{41}'` → `'A'` is not needed for this decision, so do not vote it here. Output is already canonical (lowercase, fewest digits), which is the only place where canonical form matters.
>
> **V5 — the Str named-escape table.**
> Document `\b` and `\f` in the §02 Str table, as the lexer already accepts them, and write one shared table:
> - Common: `\n \r \t \\ \b \f \u{H}`
> - Char only: `\0 \'`
> - Str only: `\" \{ \}`
>
> `Str.debug()` then emits `\b` and `\f`. Removing them from the Str lexer would be subtraction, but it would break code that compiles today, just to save two table rows. Not worth it.
>
> **V6 — diagnostics.**
> The spec should state each error condition, the span (on the escape, not on the literal), and the fix-it text. Do not assign E01xx numbers in this decision. No E01xx codes exist, and the lexer emits no coded diagnostics at all. Numbering them starts a lexer-diagnostic code family, which is infrastructure that belongs with py1ssk. Ratify the messages; assign codes when the lexer gets coded diagnostics.
>
> STABLE — ready to vote

#### Phase C — Silent vote

Fresh agents cast the vote, one per seat, with no shared room. The ballot:

> # Phase C ballot — qvan6m (`\u{N}` escapes; Char.debug / Str.debug output)
>
> Every option below comes from a panelist's own Phase A or Phase B text (label = originating panelist).
> Full texts: phaseA_*.md (proposals), phaseB_optionspace.md (dedupe), phaseB1_*.md (final positions).
> Pick ONE option per question.
>
> ## Q1 — Scope of the change
> - Q1-A: The core package from phaseB_optionspace.md, "Core" section (all six: SYS-1, WEB-1, PLT-1+2, DEV-1+2, AI-1, MIN-1). `\u{H}` (1–6 hex) input in Char and Str, not in `#"..."#`; scalar-validated; `{` after `\u` belongs to the escape; `"\u{0}"` is an error; no `\x`/`\uXXXX`/`\U`; output = named escape → `\u{h}` (lowercase, fewest digits) for the escape class → raw UTF-8; Str.debug follows in the same change; round-trip for every Char and every Str.
> - Q1-B: Char-only (MIN-2 / SYS-2): `\u{H}` in Char literals and Char.debug only; Str unchanged.
> - Q1-C: Close the ticket; keep raw output (MIN-3).
>
> ## Q2 — Output escape class (which scalars without a named escape print as `\u{h}`)
> - Q2-A (V1-a): Unicode general category Cc only: U+0000–001F, U+007F, U+0080–009F.
> - Q2-B (V1-b, DEV-1): Cc plus a fixed range list written in the spec: U+200B–200F, U+2028–2029, U+202A–202E, U+2060–2064, U+2066–2069, U+FEFF. The list is frozen; any change is a new type:spec decision, never a Unicode update (conditions from sys, plt, aiml, min).
> - Q2-C (WEB-2): Cc plus Cf/Zl/Zp by Unicode property table.
>
> ## Q3 — Raw UTF-8 char literals (`'😀'` does not lex today; bug rpgx9b)
> - Q3-A (V2-a): the raw-UTF-8 lexer fix lands in the same change as `\u{..}`.
> - Q3-B (V2-b as amended in round 1): rpgx9b stays a separate bug; qvan6m's implementation is blocked by it (`br dep`); the widened round-trip test covers raw non-ASCII and does not land before rpgx9b; `\u{1F600}` does not close rpgx9b.
>
> ## Q4 — Errors in Str literals decided here
> - Q4-A (round 1: sys, web, plt, devops, aiml, min): malformed `\u{..}`, `\u` without braces (`A`, `\U...`), and `\x..` are lexer errors in Str as in Char, each with a `\u{..}` fix-it. Every other unknown Str escape stays with py1ssk and is not decided here.
> - Q4-B (AI-3, Phase A): every unknown escape in a Str literal becomes a lexer error in this decision.
>
> ## Q5 — `blink fmt` and `\u{..}` spelling
> - Q5-A (DEV-1/DEV-3; sys, web, plt, aiml, min round 1): `blink fmt` keeps the author's spelling of `\u{..}`.
> - Q5-B (devops round 1, from WEB-3): `blink fmt` rewrites hex spelling to the debug spelling (`\u{1F600}` / `\u{01f600}` → `\u{1f600}`); it never swaps between an escape and a raw character in either direction.
> (An optional `blink lint` rule for `'\u{41}'` → "write 'A'" is outside this vote, per the panel.)
>
> ## Q6 — Str named-escape table
> - Q6-A (AI-3/MIN-1/PLT; all six round 1): one shared table in the spec. Common: `\n \r \t \\ \b \f \u{H}`. Char adds `\0 \'`. Str adds `\" \{ \}`. Str.debug emits `\b` / `\f` for U+0008 / U+000C.
> - Q6-B (status quo; no panelist proposed it): keep the §02 Str table as it is (no `\b`/`\f`); Str.debug emits `\u{8}` / `\u{c}`.
>
> ## Q7 — Diagnostics for the new lexer errors
> All positions require: a lexer error, a span on the escape itself (not the literal start), a message that names the defect, and a fix-it where one exists (`\x1b` → `\u{1b}`, `\u41` → `\u{41}`, Str `\u{0}` → "a Str cannot hold NUL"). The options differ on codes:
> - Q7-A (devops, web round 1): each new error has a registered diagnostic code, assigned by the implementation (not by this decision); this change adds no new uncoded `io.eprintln` sites.
> - Q7-B (sys, min round 1; plt and aiml leave codes open): this decision assigns no codes; the spec fixes content, span and fix-it; code numbering comes with lexer diagnostic infrastructure (py1ssk) or the implementer.
> - Q7-C (DEV-1, Phase A): allocate E0110 (invalid unicode escape) and E0111 (unknown escape) in this decision.

Tally:

- **Q1** Q1-A 6-0.
- **Q2** Q2-B 6-0.
- **Q3** Q3-B 5-1 — **AI/ML** *(dissent)*: Q3-A.
- **Q4** Q4-A 6-0.
- **Q5** Q5-A 5-1 — **DevOps** *(dissent)*: Q5-B.
- **Q6** Q6-A 6-0.
- **Q7** 3-3 — Q7-A: Web, DevOps, AI/ML; Q7-B: Systems, PLT, Minimalism. Tie → Phase D.

Q3 and Q5 (5-1) skip Phase D. The ballots, verbatim:

##### Systems

> # Systems — Phase C ballot
>
> ## Q1 — Scope
> **Vote:** Q1-A
> **Reasoning:** All `\u{H}` handling happens at lex time, so Char and Str literals cost nothing at runtime. One shared decoder and one shared C escaper cost less to maintain than a split grammar where `'\u{1b}'` is legal and `"\u{1b}"` is not. The Str.debug change needs only a byte-level check (C0/DEL single byte, C1 = `0xC2` + `0x80–0x9F`) and a two-pass exact buffer size.
> **Concern:** An implementer may size the `blink_str_debug` buffer as `n*6+3` for the worst case, which wastes 6x memory on every debug call; the spec notes or review must require a count-then-write pass.
>
> ## Q2 — Output escape class
> **Vote:** Q2-B
> **Reasoning:** I moved from V1-a. MIN and PLT showed that "add the ranges later" is not free: it changes debug bytes for existing programs on a compiler upgrade, which is the snapshot churn a fixed list exists to prevent. The runtime cost stays small: a few range compares, run only after a `0xE2` or `0xEF` lead byte, and no table in the binary. I vote it only because the ballot text freezes the list and forbids tracking a Unicode version.
> **Concern:** A later "just add one more range" patch that skips the panel would break the frozen-list promise and golden files with it; the spec must say the list changes only by a new type:spec decision.
>
> ## Q3 — Raw UTF-8 char literals
> **Vote:** Q3-B
> **Reasoning:** This is what I asked for in round 1: rpgx9b stays its own bug, qvan6m depends on it, and the widened round-trip test does not land until `'😀'` lexes. The fix is one bounded 2–4 byte decode at compile time and has no runtime cost. Separate commits are fine as long as the invariant is not claimed before both land.
> **Concern:** Someone closes qvan6m with a round-trip test scoped to ASCII plus `\u{..}` only, so the "full codepoint space" claim ships false; the test must enumerate raw non-ASCII input.
>
> ## Q4 — Errors in Str literals
> **Vote:** Q4-A
> **Reasoning:** `"\x1b[31m"` silently printing a literal `\x1b` is the exact failure 19v5gb users would hit, so `\x`, brace-less `\u` and malformed `\u{..}` must be errors now. Making every other unknown Str escape an error changes the meaning of existing programs, and nobody has measured that impact; py1ssk owns it.
> **Concern:** The "warning, keep backslash" path stays for other unknown escapes until py1ssk lands, so the Str escape grammar has two failure modes for a while.
>
> ## Q5 — `blink fmt` and `\u{..}` spelling
> **Vote:** Q5-A
> **Reasoning:** A formatter that rewrites token text inside literals is a new class of formatter behaviour for a cosmetic gain. Debug output is already canonical (lowercase, fewest digits), and that is the form machines compare.
> **Concern:** Source will hold mixed spellings (`\u{1F600}` and `\u{1f600}`), so a grep for one spelling misses the other.
>
> ## Q6 — Str named-escape table
> **Vote:** Q6-A
> **Reasoning:** The lexer already accepts `\b` and `\f` in Str, so the spec should match it. One table means one shared escaper in the runtime serves Char and Str, and `\b` is shorter output than `\u{8}`.
> **Concern:** None of substance; the only risk is that the spec table and the runtime escaper drift apart, so one runtime helper must own the table.
>
> ## Q7 — Diagnostics
> **Vote:** Q7-B
> **Reasoning:** The lexer emits no coded diagnostics today and no E01xx range exists. Assigning codes here, or requiring them, starts a lexer-diagnostic code family as a side effect of an escape decision; that infrastructure belongs to py1ssk. The spec should fix what users see: the error, a span on the escape, and the fix-it.
> **Concern:** If Q7-B wins, the implementation may add more uncoded `io.eprintln` sites that py1ssk must then find and convert.

##### Web/Scripting

> # Web/Scripting — Phase C ballot
>
> ## Q1 — Scope
> **Vote:** Q1-A
> **Reasoning:** The scripting use case for this feature is ANSI codes and control bytes in log lines, and those live in Str, not Char. If `'\u{1b}'.debug()` is legible but `"\u{1b}".debug()` dumps a raw ESC that repaints the terminal, users file a bug on day one. A List[Char] and a Str that debug the same scalar differently is a Stack Overflow question nobody should have to ask. One package, one rule, both types.
> **Concern:** Str.debug output changes for every existing Str with a control byte, so any user golden file that captured raw control bytes breaks once; the release notes must say so plainly.
>
> ## Q2 — Output escape class
> **Vote:** Q2-B
> **Reasoning:** The most common invisible-character confusion for JS/Python devs is `assert_eq("ab", "ab")` failing on a zero-width space; Cc-only does not catch it. A frozen range list in the spec catches it, and a dev can predict the output by reading one table, with no Unicode categories to learn. Unlike a property table, it never changes the output after a compiler upgrade with no source change.
> **Concern:** Users will ask "why is U+00AD (soft hyphen) not escaped when U+200B is?", so the spec must state the list's purpose (characters that hide or reorder the text around them) so the answer is one sentence.
>
> ## Q3 — Raw UTF-8 char literals
> **Vote:** Q3-B
> **Reasoning:** With a hard `br dep` block, Q3-B gives the same user-visible result as Q3-A: nobody gets a spec that claims `parse(c.debug()) == c` while `'é'` fails to lex. Keeping rpgx9b its own bug keeps the test and the fix easy to find. What matters to a Python/JS dev is that `'é'` works when the feature ships, and the block guarantees that.
> **Concern:** A dependency in a local tracker is easy to drop; if someone lands the `\u{..}` half alone, the spec's round-trip claim ships false and `'😀'` still reads as a broken compiler.
>
> ## Q4 — Str errors decided here
> **Vote:** Q4-A
> **Reasoning:** `"\x1b[31m"` and `"\u0007"` are the day-one habits of Python, JS, Java and JSON users, and today they silently print a literal backslash. Making exactly those hard errors with a `\u{..}` fix-it costs a newcomer one error message, not one search. The general unknown-escape rule changes existing programs and belongs in py1ssk.
> **Concern:** Until py1ssk lands, `"\q"` is still a warning that keeps the backslash while `"\x41"` is an error, and that split will confuse some users for a while.
>
> ## Q5 — `blink fmt` and hex spelling
> **Vote:** Q5-A
> **Reasoning:** I conceded WEB-3 in round 1. Debug output is already canonical, and that is the form people compare and paste. A formatter that rewrites the inside of literals surprises people more than mixed-case hex does.
> **Concern:** Without fmt or a lint, source will mix `\u{1F600}` and `\u{1f600}`, and AI-generated code will keep both spellings in the training data.
>
> ## Q6 — Str named-escape table
> **Vote:** Q6-A
> **Reasoning:** One shared table is one thing to learn and matches what the lexer already accepts. `'\u{8}'.debug()` and `"\u{8}".debug()` should give the same `\b`; two textual types with different output for the same scalar is a bug report waiting to happen.
> **Concern:** Few scripting devs know `\b` and `\f`, so debug output that shows `\b` may confuse some readers more than `\u{8}` would; the docs table must list them clearly.
>
> ## Q7 — Diagnostics codes
> **Vote:** Q7-A
> **Reasoning:** A registered code gives the user something to search for and gives tooling a stable key; an uncoded `eprintln` gives neither. The implementer picks the numbers, so this decision does not start a numbering scheme by accident. The span on the escape and the fix-it are the parts that save a JS/Python dev time, and all options keep them.
> **Concern:** If Q7-B wins, these errors ship uncoded and wait on py1ssk, which may be months away, so users get messages they cannot look up.

##### PLT

> # PLT ballot — qvan6m
>
> ## Q1 — Scope of the change
> **Vote:** Q1-A
> **Reasoning:** The ticket exists to make `lex ∘ debug = id` hold over the whole Char and Str domain. A Char-only change (Q1-B) splits one escape production across two literal grammars that share a prefix: `'\u{7}'` would lex as a scalar while `"\u{7}"` lexes as backslash, `u`, and a hole. That makes the grammar non-compositional. Q1-C leaves a debug form that is not re-readable, so the invariant stays false.
> **Concern:** The `{`-after-`\u` rule silently changes the meaning of any existing `"\u{...}"` Str literal. The implementation must grep the corpus and lib/ for `\u{` before landing and must not assume zero hits.
>
> ## Q2 — Output escape class
> **Vote:** Q2-B
> **Reasoning:** Both branches round-trip, so soundness does not decide this; stability does. A frozen range list written in the spec keeps `debug()` a pure total function that does not change between Unicode versions, as Cc does. Widening the class later would change output for the same input with no source change, so we fix it once now. Q2-C makes the output a function of the Unicode data version, and I reject it.
> **Concern:** The list has no category-level rule behind it. Unless one runtime helper owns it, with the spec table as the single source, Char.debug and Str.debug can drift apart, or a later patch can extend the list without a type:spec decision.
>
> ## Q3 — Raw UTF-8 char literals
> **Vote:** Q3-B
> **Reasoning:** The widened property `∀ c : Char. lex_char(c.debug()) == c` is false for every non-ASCII scalar while `'😀'` does not lex. So the property cannot be claimed or tested before rpgx9b lands. A hard `br dep` gives the same semantic result as Q3-A and keeps the bug's own identity. The property test must enumerate all 0x10F800 scalars, including the raw path, not only `\u{..}`.
> **Concern:** If the dependency is not wired, a partial landing can scope the property test down "for now". The spec then states an invariant that the implementation does not prove.
>
> ## Q4 — Errors in Str literals decided here
> **Vote:** Q4-A
> **Reasoning:** Every malformed form of the new production, plus `\x` (which this decision rejects), must be an error in both literal grammars. If not, the warn-and-keep-backslash fallback gives a typo such as `\U{7}` or `\x1b` a meaning the author did not write. General unknown-escape soundness is a real defect, but it is a separate rule with its own migration question, and py1ssk owns it.
> **Concern:** Until py1ssk lands, the Str grammar is still unsound for other unknown escapes (for example `\a`). Users can read the new errors as proof that every Str escape is now checked.
>
> ## Q5 — `blink fmt` and `\u{..}` spelling
> **Vote:** Q5-A
> **Reasoning:** The canonical form is a property of `debug()` output only: `debug` is a section of `lex`, and `lex ∘ debug = id` is the whole requirement. Nothing needs `debug ∘ lex = id` over source text. A formatter that rewrites literal contents is a second owner of the escape spelling rules, with no soundness gain.
> **Concern:** Source can hold several spellings of one scalar (`\u{1F600}`, `\u{01f600}`), so a textual grep for an escape in source is not reliable. That is a tooling cost, not a semantic one.
>
> ## Q6 — Str named-escape table
> **Vote:** Q6-A
> **Reasoning:** One shared table makes the Char escape set minus `\'` and `\0` a subset of the Str set. This is the compositional property I asked for. It also gives one output rule per scalar across both quote styles, so `'\u{8}'.debug()` and `"\u{8}".debug()` both emit `\b`. The spec then matches the lexer, which already accepts `\b` and `\f`.
> **Concern:** None on soundness. The only risk is that the spec's shared table and the one runtime escaper are not changed together and drift apart.
>
> ## Q7 — Diagnostics for the new lexer errors
> **Vote:** Q7-B
> **Reasoning:** The language rule is that these forms are rejected at lex time, with a span on the escape and a fix-it. That is what the spec must fix. Code numbering is tooling infrastructure, and the lexer has no coded diagnostics today. A language decision should not start a code range as a side effect.
> **Concern:** If no one owns the codes, the new errors ship as uncoded `io.eprintln` sites and add to the py1ssk debt. The implementation note should link them to py1ssk.

##### DevOps/Tooling

> # DevOps/Tooling — Phase C ballot (qvan6m)
>
> ## Q1 — Scope
> **Vote:** Q1-A
> **Reasoning:** In test-failure diffs, users see Str far more often than Char. If only Char escapes, `assert_eq` on strings still lets raw ESC bytes paint the CI log and lets U+200B hide in a diff. One shared escaper and one round-trip rule for both types keeps golden output consistent. Q1-B leaves `"\u{1b}"` as a warning that keeps the backslash, which is a silent trap.
> **Concern:** The Str.debug change alters existing golden output that contains raw control bytes. The implementer must sweep `tests/` for expected outputs that hold raw C0/C1 bytes and update them in the same change.
>
> ## Q2 — Output escape class
> **Vote:** Q2-B
> **Reasoning:** The most expensive debug bug in my domain is `assert_eq("ab", "ab")` failing on an invisible U+200B, or a U+202E reordering a CI log line (CVE-2021-42574). A frozen range list written in the spec is as version-stable as Cc, so snapshot tests do not change on a compiler upgrade. The cost is a few range compares after a `0xE2`/`0xEF` lead byte.
> **Concern:** If the spec text does not say "frozen; changes only by type:spec", a later patch will "helpfully" add ranges, and every user's snapshots will churn with no source change.
>
> ## Q3 — Raw UTF-8 char literals
> **Vote:** Q3-B
> **Reasoning:** The outcome I need is that the widened round-trip test covers raw non-ASCII and cannot land before `'😀'` lexes. Q3-B gives that through a `br dep` blocker and keeps the bug history clean. For the gate, Q3-A and Q3-B are the same.
> **Concern:** Someone closes qvan6m with the round-trip test scoped to `0..0x7F` "for now", and the full-codepoint claim ships false. The dependency must be wired before work starts.
>
> ## Q4 — Str errors decided here
> **Vote:** Q4-A
> **Reasoning:** `"\x1b[31m"` and `"\u0007"` are the day-one mistakes of Python/JS/JSON users. Today they compile with a warning to the wrong text, and the colour never shows. Those must be hard errors with a `\u{..}` fix-it. Every other unknown Str escape changes existing programs, which nobody measured, so it stays with py1ssk.
> **Concern:** py1ssk stalls, and the leftover "warning, keep the backslash" path for other typos (`"\q"`) stays a trap for a long time.
>
> ## Q5 — `blink fmt` and `\u{..}` spelling
> **Vote:** Q5-B
> **Reasoning:** The corpus has zero `\u{` uses, so normalizing now costs no diff churn. Starting canonical means source and debug output use one spelling, and grep and review see one form. This is the gofmt `0X` → `0x` model: idempotent and safe for meaning. The limit stays: fmt never swaps between an escape and a raw character.
> **Concern:** If Q5-A wins, mixed `\u{1F600}` / `\u{1f600}` / `\u{01f600}` spellings spread through user code, and a later normalization becomes the diff-churn event that Q5-A was meant to avoid.
>
> ## Q6 — Str named-escape table
> **Vote:** Q6-A
> **Reasoning:** The spec must match the lexer, and the lexer already accepts `\b`/`\f` in Str. One table gives one output rule: `'\u{8}'.debug()` and `"\u{8}".debug()` both give `\b`. That keeps golden files the same across the two textual types.
> **Concern:** The implementer updates the spec table but not `blink_str_debug`, so Str.debug still emits `\u{8}`. The round-trip test passes either way and does not catch it. The test must also assert the canonical spelling.
>
> ## Q7 — Diagnostics
> **Vote:** Q7-A
> **Reasoning:** A diagnostic without a code cannot be looked up with `blink explain`, suppressed, or matched by an LSP quick-fix. The escape errors are exactly the ones with mechanical fix-its. Letting this change add more uncoded `io.eprintln` sites grows the debt py1ssk must pay later. The implementer picks the numbers, so the decision allocates no range.
> **Concern:** If Q7-B wins, the new errors ship as bare strings pointing at the literal's start, and the span and fix-it requirements become aspirational because no diagnostic plumbing carries them.

##### AI/ML

> # Phase C ballot — AI/ML
>
> ## Q1 — Scope
> **Vote:** Q1-A
> **Reasoning:** One `\u{H}` spelling in both literal kinds matches the Rust/Swift/ES6 prior in model training data, so generated code is right on the first try. Char-only (Q1-B) creates a decision point: a model must remember that `'\u{1b}'` works but `"\u{1b}[0m"` does not, and the ANSI string is the most common reason anyone reaches for the escape. Q1-C leaves the round-trip invariant partial and leaves no valid way to write a control scalar in a Str.
> **Concern:** Str.debug output changes for every existing Str that holds a control byte, so any golden files that captured raw control bytes break once; the implementer must sweep the corpus for them.
>
> ## Q2 — Output escape class
> **Vote:** Q2-B
> **Reasoning:** Models read debug output in CI logs and test diffs; a raw U+200B makes `"ab" != "ab"` look impossible, and a raw U+202E reorders the line, so the model invents a cause and "fixes" correct code. A closed range list in the spec stays predictable from the spec alone, which is the property I need most: a model must be able to write the `debug()` golden without a Unicode table. Q2-C fails that test.
> **Concern:** A model may over-generalise the list to "all invisible characters" (e.g. U+00AD soft hyphen, U+034F) and write wrong goldens; the spec must print the ranges as an explicit table, not as prose.
>
> ## Q3 — Raw UTF-8 char literals
> **Vote:** Q3-A
> **Reasoning:** The spec already promises `'😀'` → `'😀'`, and models will write raw emoji literals because every peer language accepts them. The full-space round-trip claim is false until that lexes, so the two must ship as one unit. Q3-B reaches the same end state through `br dep`; I prefer the version where there is no window in which the spec and compiler disagree.
> **Concern:** If Q3-B wins and the dependency is not wired, the spec text can ship before `'😀'` lexes, and models trained on that spec will generate code that fails.
>
> ## Q4 — Errors in Str literals
> **Vote:** Q4-A
> **Reasoning:** It covers the exact mistakes models trained on Python, JS and Java make with this feature: `\x1b`, `A`, `\U0001F600`. Each becomes a hard error with a one-step fix, so the model corrects in one turn instead of shipping a string where the colour silently never appears. The general unknown-escape rule is a real trap too, but it has its own migration question and py1ssk owns it.
> **Concern:** Until py1ssk lands, other Python-isms such as `"\a"` or `"\v"` still compile with a warning and keep the backslash, so models get no hard signal for those.
>
> ## Q5 — `blink fmt` and `\u{..}` spelling
> **Vote:** Q5-A
> **Reasoning:** Input accepts any case and leading zeros, and debug output is already canonical, which is the form that goldens compare. Nothing a model learns depends on fmt rewriting hex digits, and a rewrite only adds diff noise when a model edits a file and then runs fmt.
> **Concern:** Source files in the wild will mix `\u{1B}` and `\u{1b}`, so models see two spellings in training data; low cost, since both are valid and output is the same.
>
> ## Q6 — Str named-escape table
> **Vote:** Q6-A
> **Reasoning:** One shared table is one thing to learn, and it makes the spec match what the lexer already accepts. Without it U+0008 prints as `\b` in Char and `\u{8}` in Str, a gratuitous split that a model would have to memorise as a special case.
> **Concern:** `\0` differs between the two (valid in Char, error in Str), and models will write `"\0"` by habit; the NUL error message must say why and point to Bytes.
>
> ## Q7 — Diagnostics
> **Vote:** Q7-A
> **Reasoning:** A registered code gives a model a stable key to look up (`blink explain`) and to match in tool output, which is more reliable than matching message text that may change. Q7-A still leaves the numbers to the implementation, so it does not start a code family inside an escape decision. The key rule is "no new uncoded sites": new errors should not add to the unstructured-output debt.
> **Concern:** If the lexer has no coded-diagnostic path yet, the implementer may have to build part of py1ssk's infrastructure inside this change, which widens the slice.

##### Minimalism

> # Minimalism — Phase C ballot (qvan6m)
>
> ## Q1 — Q1-A
> **Reasoning:** One `\u{H}` escape with one grammar for both literal forms adds one rule and removes two things: the `\x` idea from 19v5gb and the "v1 gap" paragraph in §3.6. Q1-B makes `'\u{1b}'` legal and `"\u{1b}"` a warning plus a literal backslash, which is a decision point §1 forbids, and it saves perhaps 30 lines. Q1-C fails the burden of proof: terminal colour codes are a common need, and raw C1 bytes can break the terminal that shows a failing test.
> **Concern:** The core forbids `"\u{0}"` in Str, which makes a small Char/Str difference inside the one rule; the spec must state it next to the table, or users will read it as a bug.
>
> ## Q2 — Q2-B
> **Reasoning:** Each scalar that moves into the escape class later changes `debug()` output, so every snapshot and golden file breaks on a compiler upgrade with no source change. That makes "Cc now, more later" costly, so we should fix the class once. V1-b is six literal ranges in the spec with no Unicode lookup, as stable as Cc, and the purpose that bounds it is closed: characters that change or hide the text around them in a terminal. Q2-C ties output to the Unicode version and is the churn we want to prevent.
> **Concern:** "Frozen" holds only while the panel is strict; a later "just add U+180E" request will test that promise, and each yes costs a round of snapshot churn.
>
> ## Q3 — Q3-B
> **Reasoning:** The outcome matches Q3-A, because rpgx9b blocks qvan6m and the widened test cannot land before it. A separate bug keeps each change to one purpose and keeps `\u{1F600}` from being taken as the fix for the raw literal. It also keeps the byte-to-scalar lexer change reviewable by itself.
> **Concern:** If Q3-A wins, the combined change grows large, and a lexer regression in the raw-UTF-8 path can hold back the smaller `\u{..}` work that has no dependency on it.
>
> ## Q4 — Q4-A
> **Reasoning:** Decide only the errors this decision creates. Malformed `\u`, brace-less `\u41`, and `\x` are the errors users of the new feature will make, so they belong here. Making every unknown Str escape an error changes the meaning of existing programs, needs its own migration question, and py1ssk already owns it.
> **Concern:** Str escape handling will have three states for a while (valid, hard error for `\u`/`\x`, warning for other unknowns); py1ssk must not stall, or that middle state becomes permanent.
>
> ## Q5 — Q5-A
> **Reasoning:** A formatter that rewrites the contents of literals is a new kind of fmt behaviour with no stated need. `debug()` output is already canonical, and that is the only place where machines compare the spelling. Keeping the author's text means one owner of the escape table, not two.
> **Concern:** Mixed-case and zero-padded spellings will stay in source, so grep for a scalar will need a case-insensitive pattern.
>
> ## Q6 — Q6-A
> **Reasoning:** The lexer already accepts `\b` and `\f` in Str, so the cheapest correct fix is to document it, not to break working code. One shared table is one thing to learn, and `'\u{8}'.debug()` and `"\u{8}".debug()` then give the same escape.
> **Concern:** `\b` and `\f` are rare, and naming them in the common table invites requests for more named escapes (`\a`, `\e`, `\v`); the answer to those must be `\u{..}`.
>
> ## Q7 — Q7-B
> **Reasoning:** No E01xx codes exist, and the lexer emits no coded diagnostics. Numbering them here starts a lexer diagnostic code family as a side effect of an escape decision. The spec should fix what the user sees (content, span, fix-it) and leave the numbering to py1ssk or the implementer.
> **Concern:** If py1ssk is slow, these errors ship without codes; that is acceptable only if the implementer does not add ad hoc numbers that py1ssk must then renumber.

*Note: in the AI/ML Q4 reasoning, "`A`" is verbatim; the ballot meant a brace-less `\u0041`, which lost its escape on the way to the file.*

#### Phase D — Round 2 on Q7

The moderator sent the panel every Phase C Q7 entry and one codebase fact. The digest, verbatim:

> # Phase D — focused round on Q7 only (all other questions are decided)
>
> Phase C result on Q7 (diagnostics): 3-3. Q7-A: web, devops, aiml. Q7-B: sys, plt, min.
> Ballot text for Q7 is in ballot.md. Every Phase C Q7 entry, verbatim, follows.
>
> ## Fact from the codebase (fact, not a vote)
> - src/lexer.bl line 2: `import diagnostics.{Diag, diag_error_range, UNEXPECTED_CHARACTER}`.
> - src/lexer.bl line 770: `diag_error_range("UnexpectedCharacter", UNEXPECTED_CHARACTER, "unexpected character `{bad_ch}`", line, col, col + 1, hint)`.
> - src/diagnostics.bl line 199: `pub const UNEXPECTED_CHARACTER    = "E1113"`.
> - src/diagnostics.bl provides `diag_error_range(name, code, message, line, col, end_col, help)` (span + help line).
> - The char-literal errors (lexer.bl 245, 254, 270, 279) and the unknown Str escape warning (943) use `io.eprintln` with no code.
>
> ## sys — Phase C Q7 (verbatim)
> ## Q7 — Diagnostics
> **Vote:** Q7-B
> **Reasoning:** The lexer emits no coded diagnostics today and no E01xx range exists. Assigning codes here, or requiring them, starts a lexer-diagnostic code family as a side effect of an escape decision; that infrastructure belongs to py1ssk. The spec should fix what users see: the error, a span on the escape, and the fix-it.
> **Concern:** If Q7-B wins, the implementation may add more uncoded `io.eprintln` sites that py1ssk must then find and convert.
>
> ## web — Phase C Q7 (verbatim)
> ## Q7 — Diagnostics codes
> **Vote:** Q7-A
> **Reasoning:** A registered code gives the user something to search for and gives tooling a stable key; an uncoded `eprintln` gives neither. The implementer picks the numbers, so this decision does not start a numbering scheme by accident. The span on the escape and the fix-it are the parts that save a JS/Python dev time, and all options keep them.
> **Concern:** If Q7-B wins, these errors ship uncoded and wait on py1ssk, which may be months away, so users get messages they cannot look up.
>
> ## plt — Phase C Q7 (verbatim)
> ## Q7 — Diagnostics for the new lexer errors
> **Vote:** Q7-B
> **Reasoning:** The language rule is that these forms are rejected at lex time, with a span on the escape and a fix-it. That is what the spec must fix. Code numbering is tooling infrastructure, and the lexer has no coded diagnostics today. A language decision should not start a code range as a side effect.
> **Concern:** If no one owns the codes, the new errors ship as uncoded `io.eprintln` sites and add to the py1ssk debt. The implementation note should link them to py1ssk.
>
> ## devops — Phase C Q7 (verbatim)
> ## Q7 — Diagnostics
> **Vote:** Q7-A
> **Reasoning:** A diagnostic without a code cannot be looked up with `blink explain`, suppressed, or matched by an LSP quick-fix. The escape errors are exactly the ones with mechanical fix-its. Letting this change add more uncoded `io.eprintln` sites grows the debt py1ssk must pay later. The implementer picks the numbers, so the decision allocates no range.
> **Concern:** If Q7-B wins, the new errors ship as bare strings pointing at the literal's start, and the span and fix-it requirements become aspirational because no diagnostic plumbing carries them.
>
> ## aiml — Phase C Q7 (verbatim)
> ## Q7 — Diagnostics
> **Vote:** Q7-A
> **Reasoning:** A registered code gives a model a stable key to look up (`blink explain`) and to match in tool output, which is more reliable than matching message text that may change. Q7-A still leaves the numbers to the implementation, so it does not start a code family inside an escape decision. The key rule is "no new uncoded sites": new errors should not add to the unstructured-output debt.
> **Concern:** If the lexer has no coded-diagnostic path yet, the implementer may have to build part of py1ssk's infrastructure inside this change, which widens the slice.
>
> ## min — Phase C Q7 (verbatim)
> ## Q7 — Q7-B
> **Reasoning:** No E01xx codes exist, and the lexer emits no coded diagnostics. Numbering them here starts a lexer diagnostic code family as a side effect of an escape decision. The spec should fix what the user sees (content, span, fix-it) and leave the numbering to py1ssk or the implementer.
> **Concern:** If py1ssk is slow, these errors ship without codes; that is acceptable only if the implementer does not add ad hoc numbers that py1ssk must then renumber.

Debate replies:

##### Systems

> # Systems — Phase D, Q7
>
> **I change my vote to Q7-A.**
>
> My Phase C reasoning rested on one fact: "the lexer emits no coded diagnostics today". That fact is false, and it was my premise, not a side point.
>
> - `src/lexer.bl:2` already imports `diag_error_range`.
> - `src/lexer.bl:770` already emits `E1113 UnexpectedCharacter` through it, with a span (`col, col + 1`) and a help line.
> - `src/diagnostics.bl` holds a live parser/lexer code family (E1100–E1113), each with a `blink explain` text.
>
> What this changes:
>
> 1. **No new infrastructure and no new code family.** Q7-A asks the implementer to add a few constants after E1113, each with an explain entry, and to call the function the lexer already uses. This is not py1ssk's work leaking into this slice (AI/ML's concern). The path exists and has one caller already.
> 2. **Span and fix-it need `diag_error_range`.** DevOps is right: the uncoded `io.eprintln` sites point at the literal's start and have no help line. All options require a span on the escape and a fix-it. Under Q7-B, the cheapest way to meet that is still `diag_error_range`, which takes a code argument. Q7-B would therefore either pass a placeholder code or build a second uncoded span path. Both are worse than Q7-A.
> 3. **The numbering concern is resolved.** Q7-A leaves the numbers to the implementation, inside the existing E11xx family. This decision allocates nothing, which was the only thing I objected to. I still reject Q7-C: E0110/E0111 would open a new range beside the one that already exists.
>
> **Cost:** about 3 constants, 3 explain texts, and replacing the new `io.eprintln` sites with `diag_error_range` calls. It has no runtime cost and no effect on codegen.
>
> **Scope note (not a condition of my vote):** converting the older uncoded char-literal sites (lexer.bl 245, 254, 270, 279) and the Str unknown-escape warning (943) stays with py1ssk. Q7-A only forbids adding new uncoded sites. The implementer may convert the old sites in the same change if they touch those lines anyway.
>
> **Position: Q7-A.**

##### Web/Scripting

> ## Web/Scripting — Phase D on Q7
>
> **Position: I hold Q7-A.**
>
> **The codebase fact removes the premise behind all three Q7-B votes.** Sys, PLT and Min each voted B because "the lexer emits no coded diagnostics today", so coding these errors would "start a lexer-diagnostic code family as a side effect". That premise is false:
>
> - `src/lexer.bl:2` already imports `diag_error_range` and a code constant.
> - `src/lexer.bl:770` already emits `E1113 UnexpectedCharacter` through `diag_error_range`, which carries a span and a help line.
> - `src/diagnostics.bl:199` registers `E1113`.
>
> The lexer already has a coded family (E11xx), a registry, and a call that takes exactly the fields Q7 requires (span start and end, message, help). Q7-A therefore starts nothing. The new errors get new constants beside `UNEXPECTED_CHARACTER`, and each site calls `diag_error_range` in place of `io.eprintln`. No E01xx range is needed. The earlier "E01xx" talk came from DevOps's Phase A examples, and nobody is bound to those numbers.
>
> **Rebutting AI/ML's concern (widening the slice):** the plumbing already exists, so nothing from py1ssk has to be built here. py1ssk remains the ticket that converts the *old* uncoded sites (lexer.bl 245, 254, 270, 279, 943).
>
> **Why this still matters for my domain:**
> - DevOps's point is decisive for me. The span on the escape and the fix-it are the parts every panelist agreed save a JS/Python dev time, and `diag_error_range` is the only path in the lexer that carries a span and a help line. Under Q7-B the implementer can meet the letter of the vote with a bare `io.eprintln` that points at the literal's start with no fix-it, which is today's behaviour. B's own spec text becomes aspirational.
> - A code is what the user searches for and what `blink explain` or an LSP quick-fix keys on. "error: invalid escape" has no key; "error[E11xx]" has one.
> - Min's condition for B was "acceptable only if the implementer does not add ad hoc numbers that py1ssk must then renumber". Numbers in the existing E11xx lexer block, next to E1113, are not ad hoc, and py1ssk has no reason to renumber them.
>
> **A bridge offer for the B voters.** I would accept this wording as Q7-A:
>
> > The new `\u`/`\x` lexer errors are emitted through the existing coded lexer path (`diag_error_range`, E11xx block, next to E1113), each with a span on the escape and a fix-it help line. The implementer picks the numbers. No new `io.eprintln` escape-error sites. Converting the existing uncoded sites stays with py1ssk.
>
> This gives Sys and PLT what they asked for: the spec fixes content, span and fix-it; no new code family; numbering stays with the implementer. It also gives Min's condition, that nothing needs renumbering. It only closes the gap where B allows more uncoded sites, the concern that Sys, PLT and Min all listed.
>
> **Holding: Q7-A** (with the bridge wording above).

##### PLT

> # PLT — Phase D, Q7
>
> **I now hold Q7-A. I am changing my vote.**
>
> My Phase C reasoning rested on a factual premise: "the lexer has no coded diagnostics today", so requiring codes would "start a code range as a side effect". The codebase fact in the digest shows that premise is false:
>
> - `src/lexer.bl:2` already imports `diagnostics.{Diag, diag_error_range, UNEXPECTED_CHARACTER}`.
> - `src/lexer.bl:770` emits `E1113` through `diag_error_range(name, code, message, line, col, end_col, help)`.
> - That helper already carries the two things Q7-B itself requires: a span (`col..end_col`) and a help line (the fix-it).
>
> So Q7-A does not create a new code family or new plumbing. It uses an existing lexer path, and codes go in the existing registry in `src/diagnostics.bl`. The implementer picks the numbers, so this decision allocates no range. Sys's and Min's concern about starting a family as a side effect does not apply, and neither does AI/ML's concern about building py1ssk's infrastructure inside this change. py1ssk's remaining job is to convert the old `io.eprintln` sites (lexer.bl 245, 254, 270, 279, 943). It is not blocked, and this change adds nothing to its debt.
>
> DevOps's argument now carries weight on my own terms. Under Q7-B the spec requires a span on the escape and a fix-it, but it lets the implementer add more `io.eprintln` sites. Those print a bare string, so the span requirement is a rule the lexer has no means to meet. When a rule the spec states cannot be carried by the output channel, the spec is unsound in the plain sense: it promises what the implementation cannot deliver. Q7-A makes the requirement one that can be carried.
>
> The language rule stays the same under both options: these forms are rejected at lex time. The only difference is whether the new rejections go through the lexer's existing structured path or add to the uncoded path. Given the fact, "no new uncoded sites" is the principled choice, and it costs almost nothing.
>
> **Condition (a note to the implementer, not a new ballot item):** use `diag_error_range` with a span on the escape itself (not the start of the literal) and a help line for the `\x` and brace-less `\u` fix-its. Register the codes in `src/diagnostics.bl` next to `E1113`. Use no ad hoc numbers outside that registry, which is Min's concern.
>
> **Position: Q7-A.**

##### DevOps/Tooling

> # DevOps/Tooling — Phase D, Q7
>
> **Position: I hold Q7-A.**
>
> ## The new fact removes the main Q7-B argument
>
> All three Q7-B votes (sys, plt, min) rest on one premise: "the lexer emits no coded diagnostics, so requiring codes starts a lexer code family as a side effect." I said the same in Phase B, and the codebase shows it is false:
>
> - `src/lexer.bl:2` already imports `diag_error_range` and `UNEXPECTED_CHARACTER`.
> - `src/lexer.bl:770` already emits a coded lexer error, E1113, with a span and a help line.
> - `src/diagnostics.bl:186-199` holds an existing E11xx family of syntax-level codes, E1100–E1113. That is where lexer and parser errors already live.
>
> So Q7-A starts no family and allocates no new range. It builds no py1ssk infrastructure either. The implementer adds constants such as `INVALID_UNICODE_ESCAPE = "E1114"` next to E1113 and calls the same `diag_error_range` that line 770 calls. That is the same cost as an `io.eprintln` call, and it is the only path that carries the span and fix-it every option requires.
>
> ## Replies to the Q7-B concerns
>
> - **min:** "acceptable only if the implementer does not add ad hoc numbers that py1ssk must then renumber." They would not be ad hoc. They are the next free slots in the existing family, and py1ssk would renumber nothing. py1ssk's job is to convert the *old* `io.eprintln` sites at lines 245, 254, 270, 279 and 943. Q7-A stops that list from growing. Q7-B lets it grow and hands py1ssk more work.
> - **sys and plt:** "The spec should fix what users see: the error, a span on the escape, and the fix-it." Agreed. But `io.eprintln` can deliver none of them in the standard form: no `-->` location, no underline span, no `help:` line, and no nonzero exit through the diagnostic count. The only way to meet the Q7-B text is `diag_error_range`, and that call takes a code argument. Q7-B therefore either produces a coded diagnostic anyway, which is Q7-A, or produces an uncoded one that fails its own span and fix-it text.
> - **aiml's concern (a wider slice):** the fact above answers it. The plumbing exists, so the slice does not widen.
>
> ## What Q7-A must say, so no one has cause to object
>
> - Each new error in this decision uses the existing coded-diagnostic path (`diag_error_range`), with a code in the existing E11xx syntax family. The implementer assigns the number.
> - The span covers the escape, and each error has a fix-it help line where one exists.
> - The change adds no new uncoded `io.eprintln` sites. Converting the existing ones stays with py1ssk.
>
> The spec text names no numbers, so the language decision still does not fix tooling numbers. That was the core Q7-B objection, and it is met.
>
> **Holding: Q7-A.**

##### AI/ML

> # AI/ML — Phase D, Q7
>
> **Position: I hold Q7-A.**
>
> **The new codebase fact removes the premise of Q7-B.** All three Q7-B entries (sys, plt, min) rest on the claim that "the lexer emits no coded diagnostics". That claim is false:
>
> - `src/lexer.bl:2` already imports `diag_error_range`.
> - `src/lexer.bl:770` already emits `E1113 UnexpectedCharacter`, with a span and a help line.
>
> So the lexer already has a coded diagnostic path and a code family (E11xx). Q7-A does not start a code range, and it does not build py1ssk's infrastructure. It uses a call that sits in the same file.
>
> My own Phase C concern was: "the implementer may have to build part of py1ssk's infrastructure inside this change". The same fact removes that concern, and I withdraw it.
>
> **Q7-B cannot deliver what it agrees to require.** All six panelists want a span on the escape and a fix-it help line. In this lexer, the only thing that carries a span and a help line is `diag_error_range(name, code, message, line, col, end_col, help)`, and its `code` argument is required. An `io.eprintln` site cannot point at the escape. The existing char-literal errors report the literal's start, which is the defect DevOps pointed out. In practice, then:
>
> - Q7-B done correctly means calling `diag_error_range`, which needs a code, which is Q7-A.
> - Q7-B done as `eprintln` does not meet the span and fix-it requirement that Q7-B itself states.
>
> **Domain argument, restated.** A model that fixes its own code works best from a stable key plus a machine-readable fix-it. A code gives it the stable key: it can search for `E11xx` and call `blink explain`. The structured help field gives it the fix-it. Matching message text is fragile.
>
> This change adds five or six new error sites, and each one has a mechanical fix-it. Those are exactly the errors that should be structured from the start. They should not be added to py1ssk's list of sites to convert later. Both sys and plt name that growth of debt as their own concern under Q7-B.
>
> **Proposed wording for the tally** (this is Q7-A, with Q7-B's concern answered):
>
> > The new escape errors use the existing `diag_error_range` path, with a span on the escape and a fix-it help line. Codes come from the lexer's existing E11xx family, and the implementer allocates the numbers in `src/diagnostics.bl`. This decision creates no new range. Converting the existing uncoded char-literal and Str-escape sites stays with py1ssk.
>
> This meets min's condition ("no ad hoc numbers that py1ssk must renumber"), because the numbers sit in the registry family the lexer already uses. It also meets plt's request to link the work to py1ssk.
>
> **Q7-A**

##### Minimalism

> # Minimalism — Phase D, Q7
>
> **I change my vote to Q7-A.**
>
> My Phase C vote rested on one premise: "the lexer emits no coded diagnostics", so a code would start a new code family. The codebase fact shows that premise is false.
>
> - The lexer already emits a coded, spanned diagnostic: `diag_error_range("UnexpectedCharacter", UNEXPECTED_CHARACTER, ...)` at src/lexer.bl:770, which is `E1113`.
> - The E11xx syntax family already exists (E1100–E1113 in src/diagnostics.bl), and it is where lexer and parser errors live.
> - `diag_error_range` already carries a span and a help line.
>
> So Q7-A starts no family and builds no infrastructure. The implementer adds two or three constants next to E1113 and calls a function the lexer already imports. That is the minimal change. My concern, "ad hoc numbers that py1ssk must then renumber", does not apply either: numbers placed in E11xx beside E1113 are where py1ssk would put them anyway.
>
> **Q7-B now costs more.**
>
> The decided parts of the ruling (a span on the escape, a fix-it line) need a Diag with a range and help. `io.eprintln` can carry neither. Under Q7-B the implementer must either:
> - use `diag_error_range` anyway, which gives a coded error, i.e. Q7-A in practice; or
> - use `io.eprintln`, which fails the span and fix-it rule we already ratified.
>
> DevOps said this in Phase C: without the plumbing, the span requirement is only aspirational. Q7-B leaves the spec at odds with the one mechanism that meets it. Q7-A removes that gap and adds nothing new. The subtraction lens favours the path with one diagnostic mechanism, not two.
>
> **Condition I attach (implementation note, not a new ballot item):**
> - New escape errors use `diag_error_range` with codes in the existing E11xx range, next to E1113. Do not use a new E01xx range.
> - Do not add new `io.eprintln` sites.
> - Converting the existing uncoded char-literal errors (lexer.bl 245, 254, 270, 279) and the Str unknown-escape warning (943) stays with py1ssk. This change should convert only the sites it touches anyway.
>
> **Position: Q7-A.**

Re-vote ballot:

> # Phase D re-vote — Q7 only (Q1–Q6 are decided)
>
> Read first: ballot.md (Q7 section), phaseD_q7_digest.md (Phase C Q7 entries + codebase fact), and phaseD_{sys,web,plt,devops,aiml,min}.md (Phase D debate replies).
>
> ## Q7 — Diagnostics for the new lexer errors
> Common to all options: a lexer error, a span on the escape itself, a message that names the defect, a fix-it where one exists.
> - Q7-A (devops, web Phase C; amended text from devops/aiml/min Phase D): each new error is reported through `diag_error_range` with a registered code in the existing E11xx family (next to E1113); the implementer picks the numbers; the change adds no new uncoded `io.eprintln` sites; converting the existing uncoded lexer sites stays with py1ssk.
> - Q7-B (sys, plt, min Phase C): this decision assigns and requires no codes; the spec fixes content, span and fix-it; code numbering comes with py1ssk or the implementer.
> - Q7-C (DEV-1 Phase A): allocate E0110 and E0111 in this decision.

**Q7 re-vote: Q7-A 6-0.** Systems, PLT and Minimalism changed from Q7-B; each named the false premise ("the lexer emits no coded diagnostics") as the reason. Re-vote ballots, verbatim:

##### Systems

> # Systems — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** My Phase C vote for Q7-B rested on the claim that the lexer has no coded diagnostics. That claim is false: `src/lexer.bl:770` emits E1113 through `diag_error_range`, and the E11xx family already exists. Q7-A therefore adds about three constants, their explain texts, and calls to a function the lexer already imports. It has no runtime or codegen cost, and it is the only path that carries the span and fix-it that every option requires. Q7-C stays rejected because E0110/E0111 would open a second range beside E11xx.
>
> **Concern:** The implementer may put the span on the literal start instead of on the escape itself, so the diagnostic gets a code but still points at the wrong column; a test must assert the column range.

##### Web/Scripting

> # Web/Scripting — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** The lexer already emits a coded, spanned error (E1113 through `diag_error_range` at src/lexer.bl:770), so Q7-A adds a few constants next to E1113 and starts no new code family. That call is the only lexer path that puts a span on the escape and prints a `help:` fix-it, and those two things save a JS/Python developer the most time. A code such as `error[E1114]` also gives the user a key to search and to pass to `blink explain`. Under Q7-B, a bare `io.eprintln` that points at the start of the literal would meet the letter of the vote and repeat today's behavior.
>
> **Concern:** The implementer may treat "no new uncoded sites" as permission to leave the old char-literal errors (lexer.bl 245, 254, 270, 279) uncoded next to the new coded ones. The user then sees two diagnostic styles for escape errors in the same literal until py1ssk lands.

##### PLT

> # PLT — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** My Phase C vote for Q7-B rested on the claim that the lexer has no coded diagnostics. That claim is false: src/lexer.bl:770 already emits E1113 through `diag_error_range`, and that call is the only lexer path that carries a span and a help line. Under Q7-B the spec requires a span on the escape and a fix-it, but it allows an output channel (`io.eprintln`) that cannot carry either. A spec rule that the implementation has no means to meet is unsound. Q7-A creates no new code range and allocates no numbers. It only routes the new rejections through the structured path that already exists.
>
> **Concern:** The implementer could reuse one generic code for all the escape errors, or put the span on the literal's start. Both would keep the letter of Q7-A but lose the distinct, spanned fix-its the panel agreed on.

##### DevOps/Tooling

> # DevOps/Tooling — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** `blink explain`, suppression and an LSP quick-fix all need a stable code to key on. The lexer already has a coded path: `diag_error_range` emits E1113 at src/lexer.bl:770, and the E11xx family already exists. So Q7-A starts no new range and builds no new infrastructure. `diag_error_range` is also the only lexer path that carries a span on the escape and a `help:` fix-it line, so Q7-A is the only option that can meet the span and fix-it rule every option shares. "No new uncoded `io.eprintln` sites" keeps py1ssk's list from growing, and py1ssk keeps the old sites (245, 254, 270, 279, 943).
>
> **Concern:** The implementer may register the new E11xx constants without `blink explain` texts, or set the span to the literal's start and not to the escape, which gives a code with no content behind it. The implementation must check both in the typecheck/diagnostic suite.

##### AI/ML

> # AI/ML — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** A model that repairs its own code works best from a stable key and a structured fix-it. A registered code gives the key: the model can match `error[E11xx]` and run `blink explain`, and does not have to match message text that can change. `diag_error_range` already exists in the lexer (E1113 at src/lexer.bl:770) and is the only path that carries the span and help line all options require, so Q7-A adds no infrastructure. These new errors each have a mechanical fix-it, so they must be structured from the start, not added to the uncoded sites py1ssk must convert.
>
> **Concern:** The implementer may read "fix-it where one exists" loosely and emit a coded error with a vague help line, so the ruling must state the exact fix-it text (`\x1b` → `\u{1b}`, `\u41` → `\u{41}`) for tests to check.

##### Minimalism

> # Minimalism — Q7 re-vote
>
> **Vote:** Q7-A
>
> **Reasoning:** I voted B in Phase C because I believed the lexer had no coded diagnostics. That was false: `diag_error_range` and E1113 already exist in src/lexer.bl, so Q7-A adds only a few constants next to E1113 and calls a function the lexer already imports. Q7-B would let a second, uncoded path grow, and that path cannot carry the span and fix-it we already require. One diagnostic path costs less than two, so A is the smaller language surface.
>
> **Concern:** The implementer may take "convert only what you touch" as licence to rewrite all the old uncoded lexer sites (245, 254, 270, 279, 943) in this change, which widens the slice into py1ssk's work.

### AI-First Review

Scored 5/5 pass. Learnability: one escape form (`\u{H}`), one shared table, and one ordered debug rule, all in the spec. Consistency: Char and Str use the same table and the same output rule; the new errors reuse the existing `diag_error_range` path. Generability: `\u{H}` matches the Rust, Swift and ES2015 prior, and the habits from other languages (`\x1b`, `\u0041`) become errors that show the fix. Debuggability: each error has a code, a span on the escape and an exact fix-it; debug output no longer hides controls or bidi overrides. Token efficiency: `\u{1b}` is 6 characters; printable scalars stay raw.

### Final Spec

```blink
fn main() {
    let red = "\u{1b}[31m"            // ESC [ 3 1 m — the { after \u never opens a hole
    let smile = '\u{1F600}'           // same Char as '😀'
    io.println('\u{7}'.debug())       // '\u{7}'
    io.println('\u{8}'.debug())       // '\b'
    io.println('\u{41}'.debug())      // 'A'
    io.println('\u{202E}'.debug())    // '\u{202e}'
    io.println("a\u{200B}b".debug())  // "a\u{200b}b"
    io.println("é\u{1F600}".debug())  // "é😀"
}
// Errors (each: own E11xx code, span on the escape, fix-it):
//   "\x1b"    -> write \u{1b}
//   "\u0041"  -> write \u{41}
//   '\u{d800}' -> surrogate is not a Unicode scalar value
//   "\u{0}"   -> a Str cannot hold NUL
```

Locked design points:

- **Input.** `\u{H}`, 1–6 hex digits in either case, leading zeros allowed, in `"..."` and `'...'`, not in `#"..."#`. The value must be a Unicode scalar value (same bounds as `Char.from_code_point`). The `{` after `\u` belongs to the escape. `"\u{0}"` is an error; `'\u{0}'` equals `'\0'`.
- **No other numeric escape.** `\x..`, `\uXXXX` and `\U...` are errors in both literal kinds, with a `\u{..}` fix-it.
- **Shared escape table.** Common: `\n \r \t \\ \b \f \u{H}`. Char adds `\0 \'`. Str adds `\" \{ \}`.
- **One debug rule for Char and Str.** Named escape first; else `\u{h}` (lowercase hex, no leading zeros) for the escape class; else raw UTF-8.
- **Escape class, frozen.** Cc (U+0000–001F, U+007F, U+0080–009F) plus U+200B–200F, U+2028–2029, U+202A–202E, U+2060–2064, U+2066–2069, U+FEFF. It does not follow Unicode updates; only a new spec decision changes it. One runtime helper owns it for both types.
- **Round-trip.** `parse(c.debug()) == c` for every `Char`, `parse(s.debug()) == s` for every `Str`. The property test covers the full scalar range, including the raw non-ASCII path, and does not land before raw UTF-8 char literals lex.
- **Raw UTF-8 char literals** (`'😀'`) are a separate lexer bug that blocks the implementation. `'\u{1F600}'` does not fix that bug.
- **Diagnostics.** Each error kind has its own registered code in the E11xx syntax family, reported through `diag_error_range` with the span on the escape and a help line. The implementation adds no new uncoded `io.eprintln` sites. Converting the existing uncoded lexer sites, and the rule for other unknown Str escapes, stay with the separate lexer-diagnostics task.
- **`blink fmt`** keeps the author's spelling of `\u{..}`. An optional lint for `'\u{41}'` → `'A'` is outside this decision.
