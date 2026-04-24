[< All Decisions](../DECISIONS.md)

# Char Literal Escape Sequences — Design Rationale

### Panel Deliberation

Five panelists voted on one question. Resolves gap: "char-literal escape set not defined in spec".

**Q: What escape sequences should the lexer accept inside `'...'` char literals? (4-1 for Option A)**

- **Systems:** Option A. Common control codes (`\n`, `\t`, `\0`) must resolve at parse time to a clean uint32_t constant; forcing `Char.from_code_point(10)` for a newline turns a compile-time constant into a function call.
- **Web/Scripting:** Option A. Every scripting language developers use (Python, Ruby, Rust, Go) accepts `\n`-style escapes in character literals; diverging buys nothing but surprise.
- **PLT:** Option A. Consistency with string-literal escapes is Principle of Least Astonishment; swap `\"` for `\'`, drop `\{` `\}` (interpolation inapplicable to scalars), add `\0` (NUL genuinely useful).
- **DevOps:** Option A. `'\t'` and `'\n'` need to Just Work in config parsers, CSV tooling, CLI flag handling without importing Char methods; deferring unicode escapes alongside task 19v5gb keeps the escape story coherent across both literal kinds.
- **AI/ML:** Option C (dissent). Tokenizer and vocab code leans on emoji and non-BMP codepoints; `'\u{1F600}'` reads better than `Char.from_code_point(0x1F600)`. Concede deferring with hex-escape work is defensible.

### Decision

Char literals accept: `\n \r \t \\ \b \f \0 \'` — same as string escapes swapping `\"` for `\'` and dropping `\{ \}`. Unicode/hex escapes deferred alongside string hex escapes (task 19v5gb); non-ASCII chars use `Char.from_code_point(...)` until then.

### Spec Amendment

Add to `sections/02_syntax.md` after the string escape table:

Char literals (`'x'`) accept: `\n` (newline), `\r` (carriage return), `\t` (tab), `\\` (backslash), `\b` (backspace), `\f` (form feed), `\0` (NUL), `\'` (single quote). Any other escape is a lexer error. `\u{...}` and `\x..` are deferred (task 19v5gb). A char literal must contain exactly one Unicode scalar value; `''` and `'ab'` are errors. Surrogate codepoints (0xD800–0xDFFF) are invalid.
