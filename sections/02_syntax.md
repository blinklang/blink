## 2. Syntax

Blink's syntax optimizes for three things in priority order: unambiguous parsing, token efficiency, and human readability. Every syntactic choice was resolved by independent expert vote (5 panelists: systems, web, PLT, DevOps, AI/ML). Contested decisions are explained in subsections below.

### 2.1 Hello World

```blink
fn main() {
    io.println("Hello, world!")
}
```

Three lines. No imports. No effect annotation on `main` (it's implicit). No ceremony.

With CLI arguments:

```blink
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
}
```

`env.args()` returns the argument list. `.get(1)` returns `Str?` (i.e. `Option[Str]`). The `??` operator supplies a default when `None`. The `greet` function declares `! IO` because it prints; `main` doesn't need to because its effects are implicit.

### 2.2 Locked Syntax Decisions

All decided through independent design and cross-team voting. None are revisitable.

| Element | Choice | Rationale |
|---------|--------|-----------|
| Function keyword | `fn` | 2 chars, 1 token. Unambiguous start-of-declaration. Rust/Zig normalized it. Sigils (`~`/`+`) were rejected 5-0 — they conflate visibility with declaration and are unfamiliar to both humans and LLM training data. |
| Entry point | `fn main()` | Convention-based. Compiler looks for `main`. No decorator, no annotation, no magic. |
| Blocks | `{ }` braces | Unambiguous nesting. LLMs produce brace errors far less often than indentation errors. Enables incremental parsing of broken code. See [2.3](#23-contested-braces-vs-indentation). |
| Statement terminator | Newline | No semicolons. Canonical formatting makes them redundant. Saves 1 token per line across every file. See [2.5](#25-contested-no-semicolons). |
| String delimiter | `"double quotes"` only | One string syntax. No single quotes, no backticks, no raw strings. Zero style debates. A prefix (`#`, `t`) changes how the content is read, never the delimiter. See [2.4.3](#243-template-literals-t). |
| String interpolation | `"Hello, {name}!"` | Universal — every string supports `{expr}`. No `f"..."` prefix needed. Literal brace via `\{`. A `t` prefix makes a template literal (§2.4.3). See [2.4](#24-contested-universal-interpolation). |
| Bindings | `let` / `let mut` | Immutable by default. `let mut` is a deliberate speed bump that says "this will change." `:=` was rejected 5-0 — it's ambiguous about mutability. Parameters follow the same rule: `mut name: T` (§3.6 *Mutable Parameters*). In a pattern, `mut` goes before each name that changes: `let (mut x, y) = pair` (§3.5 *Mutable Binders*). |
| Pattern matching | `match val { P => e }` | Expression-based. `=>` for arms (not `->`, which means return type). |
| Match arm separator | Newline | No commas between arms. Consistent with the newline-terminated philosophy. |
| Generic syntax | `List[Str]` | Square brackets. Zero parsing ambiguity with comparison operators. See [2.6](#26-contested-square-bracket-generics). |
| Type annotations | `name: Type` | Colon after identifier. Same syntax everywhere: params, let bindings, struct fields. |
| Return type | `-> Type` | Arrow after param list. Visually distinct from `:`. `::` was rejected 4-1 — conflicts with Haskell's type-of convention. Omit when returning `()`. |
| Effect annotation | `! Effect` | Bang after return type. Single character. Universal "danger/impurity" signal. |
| Comments | `//` line, `///` doc | No block comments. `///` produces structured data the compiler can query. |
| Expression-oriented | Last expr is return value | No `return` needed for the final expression. `return` exists only for early exit. |
| Keyword args | `fn f(a: T, -- b: U)` | Declaration-site `--` separator. Positional before, keyword after. Author decides — caller has no choice. Principle 2 preserved. |
| Option sugar | `T?` for `Option[T]` | `Str?` means `Option[Str]`. Short in type position, universally understood. |
| Option defaulting | `??` | `val ?? default` desugars to match on `Some`/`None`. Borrowed from Swift's nil-coalescing. |
| Type names | `Str`, `Int`, `Bool`, `Float` | Short PascalCase. One casing rule for builtins and user types. Token-efficient — `Str` saves 3 chars over `String`, thousands of times per codebase. |
| If/else | Expression, no parens | Always an expression. No parentheses around condition. Else mandatory when value is used. No `if let`. See [2.9](#29-ifelse-expressions). |
| While/loop | `while` and `loop` | `while cond { }` for conditional, `loop { }` for unconditional. Plain `break`/`continue`. No labels, no `while let`. See [2.11](#211-whileloop). |
| Visibility | `pub` keyword | Public items use `pub`. Everything else is module-private. See [2.12](#212-visibility). |
| Scoped resources | `with expr as name { }` | Deterministic resource cleanup. `Closeable` trait + LIFO close order. Reuses `with` from effect handlers; `as` disambiguates. 3-0 over `defer`. |
| Constants | `const NAME = expr` | Compile-time constants. Distinct from `let` (runtime). Literals + arithmetic + boolean ops + references to other consts. See [2.21](#221-const-declarations). |
| Tests | `test "name" { }` | First-class syntax. Pure by default (no implicit effects). Four built-in assertions. `panic()`, `todo()` and `unreachable()` diverge. Module-scoped tests access private items. `@tags(...)` for filtering. See [2.20](#220-test-blocks). |
| Spread/rest operator | `..` | General spread/rest sigil. Patterns: `{ name, .. }`, `[first, ..]` (ignore rest). Construction: `{ field: val, ..source }` (copy rest), `[..list1, ..list2]` (list spread). See [2.16](#216-spread--rest-operator-). |

**Local bindings.** These forms bind a name in a local scope:

- a parameter of a named function or of a closure (§2.8);
- `let` and `let mut`, and each name in a destructuring `let` pattern;
- each name in a `match` arm pattern;
- each name in a `for` loop pattern (§2.10);
- the name after `as` in `with expr as name { }`.

Each of these is immutable unless it is declared `mut`. In a pattern, `mut` goes directly before the name: `let (mut x, y) = pair`, `for (k, mut v) in pairs`, `Some(mut n) =>` (§3.5 *Mutable Binders*). The name after `as` in `with` is never `mut` (§2.18).

A local binding hides a module qualifier of the same name for its scope (§10.1 *Qualified Access*).

### 2.3 Contested: Braces vs Indentation

**Winner: braces (5-0)**

The claim that "indentation is trivial for AI" is empirically false. LLMs produce indentation errors 3-5x more often than brace errors, and the gap widens at 3+ nesting levels. Consequences:

- **Brace errors** are rare and produce clear, localized compiler diagnostics. A missing `}` points to exactly one block.
- **Indentation errors** can be silent. A mis-indented line may still parse — as part of the wrong block. The resulting program is syntactically valid but semantically wrong. This is the worst kind of bug.
- **Copy-paste** across chat, docs, web, and AI output frequently mangles whitespace. Tabs-vs-spaces is a solved non-problem with braces.
- **Incremental parsing** benefits directly. The compiler can identify block boundaries in broken code by scanning for `{}`  — critical for IDE features and the compiler-as-service architecture.

Spec 2 argued that "AI operates on the AST, not text." This is circular: if perfect AST tooling existed, surface syntax wouldn't matter. It doesn't exist yet. The syntax must be robust to text-level manipulation.

### 2.4 Contested: Universal Interpolation

**Winner: universal (voted as locked decision)**

Two string types (`"plain"` vs `f"interpolated"`) create problems:

1. The AI picks the wrong one — generating `"Hello, {name}"` without the `f` prefix, producing a literal `{name}` string. This is Python's most common string-related bug.
2. The formatter must handle two syntaxes for the same concept.
3. Developers forget the prefix, get no error, and ship broken output.

With universal interpolation, `"Hello, {name}!"` just works. When no `{expr}` is present, the literal is a plain `Str`. Literal braces use `\{`, which is rare enough (JSON templates, regex) to be acceptable. The trade is a one-character escape in edge cases vs eliminating an entire class of bugs in the common case.

Holes evaluate left to right, and each hole's value is appended before the next hole starts: `"{next()} {next()}"` calls the first `next()` first (§2.22).

**Escape sequences.** Strings support the following backslash escapes:

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\b` | backspace (U+0008) |
| `\f` | form feed (U+000C) |
| `\u{H}` | the Unicode scalar value with hex code `H` (see *Unicode escapes* below) |
| `\"` | literal `"` |
| `\{` | literal `{` (suppresses interpolation) |
| `\}` | literal `}` |

**Char literal escape sequences.** Char literals (`'x'`) share the common escapes with strings (`\n \r \t \\ \b \f \u{H}`). They do not accept `\{`, `\}` or `\"`, and they add `\0` and `\'`:

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\b` | backspace |
| `\f` | form feed |
| `\0` | NUL byte |
| `\u{H}` | the Unicode scalar value with hex code `H` (see *Unicode escapes* below) |
| `\'` | literal `'` |

A char literal must contain exactly one Unicode scalar value, written as one raw UTF-8 character (`'é'`, `'😀'`) or as one escape. Surrogate code points (0xD800–0xDFFF) are rejected. A char literal cannot span lines: its text runs from the opening `'` to the next `'` on the same line, or to the end of the line if there is none. The lexer counts the scalar values in that text:

| Text | Code | Help |
|------|------|------|
| `''` | `EmptyCharLiteral` (E1124) | write one character between the quotes, such as `' '`; an empty `Str` is `""` |
| `'ab'` | `MultiCharLiteral` (E1125) | a char literal holds one character; use double quotes for a `Str`: `"ab"` |
| `'hello` with no closing `'` on the line | `MultiCharLiteral` (E1125) | same as above |
| `'` or `'a` with no closing `'` on the line | `UnterminatedLiteral` (E1126) | close the literal with `'` |

The span covers the literal's text, from the opening quote. `UnterminatedLiteral` follows the rule for unclosed literals below.

**Unicode escapes (`\u{H}`).** Both `"..."` and `'...'` accept `\u{H}`, which produces the Unicode scalar value with hex code `H`:

```blink
let esc = '\u{1b}'
let red = "\u{1b}[31m"            // ESC [ 3 1 m — no interpolation hole
let smile = "\u{1F600}"           // same Str as "😀"
let zwsp = "a\u{200b}b"           // three scalars
```

- `H` is 1 to 6 hex digits, upper or lower case. Leading zeros are allowed: `\u{41}`, `\u{041}` and `\u{0041}` are the same escape.
- The value must be a Unicode scalar value: 0x0–0xD7FF or 0xE000–0x10FFFF. These are the same bounds as `Char.from_code_point(n)` (§3c.3).
- The `{` after `\u` is part of the escape. It never starts an interpolation hole.
- A `Str` cannot hold NUL, so `"\u{0}"` is an error. In a char literal, `'\u{0}'` is the same `Char` as `'\0'`.
- `#"..."#` strings do no escape processing: in `#"\u{41}"#`, `\u{41}` is six characters.
- `\u{H}` is the only numeric escape. `\x..`, `\uXXXX` (no braces) and `\UXXXXXXXX` are errors in both literal kinds.
- `blink fmt` keeps the author's spelling of `H`. Debug output always uses one spelling: lowercase hex, no leading zeros (§3.6, *Scalar debug-forms*).

Each malformed escape is a lexer error in both literal kinds. Each error kind has its own registered code in the syntax diagnostic family. Its span covers the escape itself, not the start of the literal, and its help line shows the fix:

| Source | Code | Error | Help |
|--------|------|-------|------|
| `\u{}` | `EmptyUnicodeEscape` (E1114) | empty Unicode escape | write 1 to 6 hex digits: `\u{41}` |
| `\u{1234567}` | `UnicodeEscapeTooLong` (E1115) | more than 6 hex digits | write at most 6 hex digits |
| `\u{12g}` | `InvalidUnicodeEscapeDigit` (E1116) | `g` is not a hex digit | use only `0-9`, `a-f`, `A-F` |
| `\u{41` | `UnterminatedUnicodeEscape` (E1117) | unterminated Unicode escape | close the escape with `}`: `\u{41}` |
| `\u{d800}` | `SurrogateEscape` (E1118) | surrogate code point is not a Unicode scalar value | surrogates 0xD800–0xDFFF cannot appear in a `Char` or `Str` |
| `\u{110000}` | `UnicodeEscapeOutOfRange` (E1119) | value is above 0x10FFFF | the largest Unicode scalar value is `\u{10ffff}` |
| `\u0041`, `\U0001F600` | `UnicodeEscapeNeedsBraces` (E1120) | Unicode escape needs braces | write `\u{41}`, `\u{1f600}` |
| `\x1b` | `HexEscapeNotSupported` (E1121) | Blink has no `\x` escape | write `\u{1b}` |
| `"\u{0}"`, `"\0"` | `NulInStr` (E1122) | a `Str` cannot hold NUL | use `Bytes` for data that contains NUL |
| `"\q"`, `'\"'`, `"\'"` | `UnknownEscape` (E1123) | the escape is not valid in this literal kind | see below |

An escape that is not in the escape table for its literal kind, and that no other row covers, is `UnknownEscape`. One code serves both literal kinds. The help line lists the valid escapes for that literal kind. Where the escape has a known meaning in another language, the help gives the Blink fix first. For example, `"\d"` gets the raw string `#"\d"#`, `"\e"` gets `\u{1b}`, and `"\'"` gets a plain `'`. These examples are not normative: ERROR_CATALOG.md and `blink explain` list the cases covered, and the implementation sets the wording.

**Unclosed literals.** A `"..."`, `t"..."` or `#"..."#` literal with no closer before the end of the file is `UnterminatedLiteral` (E1126). The char-literal rule above uses the same code. One code serves every literal kind. The lexer reports it, and the parser does not report an error at the end of the file for it. The primary span is the opening delimiter, with its `t` or `#` prefix. A `note:` marks where the literal ran out: the end of the file for a string, the end of the line for a char. The help line names the exact closer to write: `'`, `"`, or `"` followed by as many `#` as the opening delimiter has.

**Recovery.** A lexer error is an error, so no `@allow` or `[lints]` entry reaches it (§4.16.8), and `--strict` does not change it. After an error the lexer still emits the literal's token: it drops a malformed escape, and a bad char literal becomes U+FFFD. Then it keeps lexing, so one run reports every lexer error in the file, and the compiler exits non-zero. Recovery must not cause a follow-on diagnostic: one bad literal gives exactly one diagnostic, and a dropped escape or a U+FFFD `Char` never causes a type error. Errors elsewhere in the file are still reported.

**Template literals.** A `t` before a string literal makes a template literal: in `db.query_one(t"SELECT * FROM users WHERE id = {id}")`, the compiler keeps `{id}` apart from the text as a bound value and does not concatenate it. A plain `"..."` literal is always a `Str`, whatever type the site expects. See §2.4.3 and §3b.5.

**Backticks are literal.** Backtick characters (`` ` ``) have **no special meaning** inside `"..."` or `#"..."#`. They are ordinary characters, even when used in markdown-style code spans inside test names or docstrings. Interpolation rules apply uniformly — a `{` inside a backtick-quoted region of a string still triggers interpolation. For strings that contain code snippets with literal `{` characters, write either:

```blink
// Short inline span — use \{ to escape the brace:
test "pool usage: `with pool.scoped() \{ pg.query(...) }`" {
    assert(true)
}

// Prose-heavy span — use #"..."# (extended delimiter), where { is literal:
test #"pool usage: `with pool.scoped() { pg.query(...) }`"# {
    assert(true)
}
```

When the compiler fails to parse an interpolation expression inside `"..."`, the diagnostic suggests both `\{` and `#"..."#` as alternatives. **Panel vote: 6-0** to reject backtick-suppression (would break `Template[C]` hole-bijection and add unbounded-distance lexer state). **3-2-1 soft consensus** on docs + targeted diagnostic over docs-only or docs + lint warning. See [DECISIONS.md](../DECISIONS.md).

#### 2.4.1 Compile-Time Intrinsics (`#`)

Blink uses the `#` prefix for **compile-time intrinsics** — expressions evaluated by the compiler during compilation, not at runtime. The `#` sigil visually distinguishes compile-time evaluation from runtime function calls, following Swift's precedent (`#file`, `#line`, `#embed`).

##### `#embed` — File Inclusion

For embedding large text content (documentation, templates, SQL, test fixtures), use `#embed` to include file contents at compile time:

```blink
const EMAIL_TEMPLATE: Str = #embed("templates/email.html")
const SCHEMA: Str = #embed("sql/schema.sql")
```

Rules:
- Path resolved relative to source file's directory
- File read at compile time; contents become a `Str` literal in the binary
- No interpolation, no escape processing on file contents
- Type is `Str`. Works everywhere `Str` works
- Compile error E1108 if file not found
- Argument must be a string literal (no variables, no interpolation)

When to use `#embed` vs inline strings:
- **Inline**: short strings, strings needing interpolation
- **`#embed`**: large text blobs, content with many special characters, templates

```blink
fn print_help() ! IO {
    const HELP_TEXT: Str = #embed("docs/help.txt")
    io.println(HELP_TEXT)
}
```

##### Future Intrinsics (v2+)

The `#` prefix is reserved for additional compile-time intrinsics:

| Intrinsic | Type | Purpose |
|-----------|------|---------|
| `#embed("path")` | `Str` | File contents (v1) |
| `#env("VAR")` | `Str` | Build-time environment variable |
| `#version()` | `Str` | Package version from blink.toml |
| `#target()` | `Str` | Compilation target (OS/arch) |
| `#file()` | `Str` | Current source file path |
| `#line()` | `Int` | Current source line number |

All `#` intrinsics share the same rules: evaluated at compile time, arguments must be literals, results are baked into the binary.

**Panel vote: 5-0** for compile-time file inclusion (resolving the raw/uninterpolated string gap). **5-0** for `#` sigil as compile-time intrinsic category (over `$` and unsigiled builtins). No new string syntax — the locked "one string syntax" decision is preserved. See [DECISIONS.md](../DECISIONS.md).

#### 2.4.2 Extended Delimiter Strings (`#"..."#`)

For inline strings containing many `"` or `\` characters — code generation, JSON literals, regex — Blink supports **extended delimiter strings** using the `#` prefix:

```blink
let json = #"{"name":"Alice","age":30}"#
let c_code = #"printf("hello \"world\"\n");"#
```

Inside `#"..."#`:
- `"` is a literal character (does not terminate the string)
- `\` is a literal character (no escape sequences — `\n` is two characters, not a newline)
- `#{expr}` is interpolation (same semantics as `{expr}` in regular strings)
- `{expr}` is literal text (NOT interpolation — the `#` prefix is required)

```blink
let name = "Alice"
let json = #"{"name":"#{name}","active":true}"#
// Result: {"name":"Alice","active":true}
```

**Adjustable depth.** If the string content contains `"#`, increase the `#` count on both ends. Interpolation prefix matches the delimiter depth:

| Delimiter | Terminator | Interpolation | Use when content contains |
|-----------|------------|---------------|--------------------------|
| `#"..."#` | `"#` | `#{expr}` | `"` and `\` |
| `##"..."##` | `"##` | `##{expr}` | `"#` |
| `###"..."###` | `"###` | `###{expr}` | `"##` |

Maximum depth is 3. Beyond that, use `#embed("path")` for file inclusion.

```blink
// Building a regex with interpolation — a main use case:
let pattern = #"^\s*#{name}\s*=\s*"(.*)"$"#
// With name = "port": ^\s*port\s*=\s*"(.*)"$

// Without extended delimiters, this would be:
let pattern = "^\\s*{name}\\s*=\\s*\"(.*)\"$"
```

Rules:
- Type is `Str`. Works everywhere regular strings work
- No escape sequences — `\n`, `\t`, `\\`, `\"` are all literal characters
- Interpolation via `#{expr}` (depth 1), `##{expr}` (depth 2), etc.
- `{expr}` without `#` prefix is literal text inside extended strings
- Multi-line: extended strings can span multiple lines (newlines are literal)
- Compile error E1110 if delimiter depth exceeds 3
- Compile warning W1111 if `{identifier}` appears inside `#"..."#` without `#` prefix (likely forgotten interpolation)

When to use which string form:
- **`"..."`**: most strings — short text, strings needing `\n`/`\t` escapes, simple interpolation
- **`#"..."#`**: strings with many `"` or `\` — JSON, code generation, regex, C string emission
- **`#embed("path")`**: large text blobs — templates, documentation, SQL schemas

**Panel vote: 5-0** for extended delimiter strings. Parametric extension of existing string syntax (same `"` delimiter, same `Str` type), not a second string syntax. Locked "one string syntax" decision preserved. See [DECISIONS.md](../DECISIONS.md).

#### 2.4.3 Template Literals (`t"..."`)

A `t` prefix on a string literal makes a **template literal**. The compiler keeps its text and its holes apart: each `{expr}` becomes a value that the receiver binds as a parameter, and never text that the compiler concatenates. Database, shell and HTML APIs take a `Template[C]` (§3b.5), so their arguments are template literals:

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
}
```

**One delimiter, optional prefixes.** Blink has one string delimiter, `"`. A prefix changes how the compiler reads the content, never the delimiter: `#` changes which characters are literal (§2.4.2), and `t` changes what the literal builds. Each new prefix needs a panel vote. There is no tag for each context, such as `sql"..."` or `html"..."`: the type `Template[C]` gives the context, not the literal.

**`t` composes with every literal form.** It also goes before an extended delimiter, at depths 1 to 3:

| Form | Hole | Literal `{` |
|------|------|-------------|
| `t"..."` | `{expr}` | `\{` |
| `t#"..."#` | `#{expr}` | `{` |
| `t##"..."##` | `##{expr}` | `{` |
| `t###"..."###` | `###{expr}` | `{` |

```blink
fn active_docs(owner: Int) -> List[Row] ! DB.Read {
    db.query(t#"SELECT * FROM docs WHERE meta @> '{"active": true}' AND owner = #{owner}"#)
}
```

Rules:
- The `t` must come directly before the `"` or the first `#`, with no space between. A `t` followed by anything else is an ordinary identifier.
- Escapes, holes, line breaks and delimiter depth follow the same rules as the form without `t` (§2.4, §2.4.2).
- W1111 fires inside `t#"..."#` as it does inside `#"..."#`: there, `{owner}` is literal text, and only `#{owner}` is a hole.

**Type.** A template literal has type `Template[α]`, where α is a new type variable. The type that the site expects solves α, by the same bidirectional check as for any other expression. A later use in the same definition can also solve it, as for `[]` and `None` (§3.4 *Under-Determined Types*):

```blink
fn get_user(id: Int) -> User? ! DB.Read {
    let q = t"SELECT * FROM users WHERE id = {id}"   // Template[α]
    db.query_one(q)                                  // α = DB
}
```

If α is not solved at the end of inference for the definition, the literal is `error[CannotInferType]` (E0301), and the span points at the `t"..."` literal. Each hole must have a Template value type, or be a `Raw[Str]`, which folds its text into the parts and raises `RawBypassesParam` (§3b.5).

**A plain literal is always a `Str`.** A `"..."` literal never becomes a template, whatever type the site expects. A plain literal where `Template[C]` is expected, and a template literal where `Str` is expected, are each `error[TemplateMismatch]` (E0310). The `help:` adds or removes the `t`, and a tool can apply it (§3b.5 *Compile Errors for `Str` and `Template` Mismatch*).

A forgotten `t` is a compile error, not a silent bug. That is the difference from the `f"..."` prefix that §2.4 rejects: there, a missing `f` compiles and gives the wrong output with no error.

**Panel vote: 6-0** on all nine questions. See [DECISIONS.md](../DECISIONS.md) and the [rationale](../decisions/template-literal-prefix.md).

### 2.5 Contested: No Semicolons

**Winner: newlines (voted as locked decision)**

If there is exactly one way to format code (canonical formatting enforced by `blink fmt`), newlines are unambiguous statement separators. Semicolons carry zero additional information — they are noise tokens. Over a codebase, removing them saves thousands of tokens from AI context windows.

Multi-line expression continuation is handled by deterministic rules (see [2.7](#27-multi-line-continuation)).

### 2.6 Contested: Square Bracket Generics

**Winner: square brackets (5-0)**

Angle brackets `<>` create genuine parsing ambiguity with comparison operators:

```
// Is this a generic call or two comparisons?
f(a<b, c>d)
```

C++, Java, and TypeScript all have heuristics and special cases to disambiguate. These heuristics make parsers slower, error messages worse, and incremental compilation harder. Square brackets have zero ambiguity:

```blink
let users: List[User] = fetch_users()
let map: Map[Str, List[Int]] = build_index()
fn first[T](items: List[T]) -> T? { items.get(0) }
```

`List[Str]` can never be confused with indexing (Blink uses `.get()` for element access) or comparison. A bracket suffix that holds a value, such as `xs[1]`, is `error[NoIndexOperator]` (E0313, §3.4 *Postfix Brackets That Are Not a Type Application*). This directly serves the compiler-as-service goal: a simpler parser means faster incremental compilation, better error recovery, and easier tooling.

### 2.7 Multi-line Continuation

Blink uses deterministic continuation rules. A statement continues to the next line when the current line ends with:

- An **infix operator**: `+`, `-`, `*`, `/`, `|>`, `&&`, `||`, `==`, `!=`, `?`, etc.
- An **opening delimiter**: `(`, `{`, `[`
- A **comma** (inside argument lists, collection literals, etc.)
- The `=>` of a match arm (body continues on next line)

A statement also continues when the next line starts with:

- A **dot**: `.method()` chaining
- A **closing delimiter**: `)`, `}`, `]`
- An **infix operator** (alternative to trailing operator style)

```blink
// Trailing operator — line ends with |>, continues
let result = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()

// Method chaining — next line starts with dot
let name = user
    .get_profile()
    .display_name()
    .to_uppercase()

// Open delimiter — continues until matching close
let config = Config(
    host: "localhost"
    port: 8080
    debug: true
)

// Match arm body
match status {
    Ok(value) =>
        process(value)
    Err(e) =>
        log_error(e)
}
```

These rules are **deterministic and context-free** — no lookahead heuristics, no ambiguity. The formatter enforces canonical indentation for continued lines (one level deeper than the starting line).

### 2.8 Closures (Anonymous Functions)

Closures use the `fn` keyword — the same keyword as named functions. There is no alternate short form.

```blink
let evens = numbers.filter(fn(x) { x % 2 == 0 })

let doubled = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()

async.spawn(fn() { fetch_user(user_id) })

let add = fn(a: Int, b: Int) -> Int { a + b }
```

**Why no `|x|` syntax:** Blink has a pipe operator `|>`. Having `|x|` closures and `|>` pipes in the same expression creates visual ambiguity. More fundamentally, Principle 2 (one way to do everything) means one syntax for function abstraction: `fn`. The AI never has to choose between two closure forms. The formatter has one rule. Tutorials teach one pattern.

**Panel vote: 5-0** for `fn(params) { body }`. See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 1.1.

#### Capture Semantics

Closures capture variables from enclosing scope by **shared reference**. All captures — immutable (`let`) and mutable (`let mut`) — share the original binding. "Shared reference" means the closure and the enclosing scope see the same binding. No explicit capture syntax is needed. No `move` keyword, no capture lists.

```blink
let threshold = 10
let above = items.filter(fn(x) { x > threshold })  // captures threshold

let mut count = 0
items.for_each(fn(x) {
    if x > threshold { count += 1 }
})
io.println("Found {count}")  // prints the actual count, not 0
```

**Immutable captures.** For a `let` binding, shared reference and by-value copy differ only when the value reaches a shared cell (§3.6 *Shared cells*). A change made to that cell through another name shows through the capture too. A value that reaches no shared cell never changes, so there is no difference.

**Mutable captures.** For `let mut` bindings, mutations through the closure are visible in the enclosing scope and vice versa.

```blink
let mut total = 0
let mut errors = 0
results.for_each(fn(r) {
    match r {
        Ok(v) => total += v
        Err(_) => errors += 1
    }
})
io.println("Total: {total}, Errors: {errors}")  // both reflect actual values
```

**Snapshot idiom.** When you want a copy independent of future mutations, bind a value type to a new `let`:

```blink
let mut count = 0
let snapshot = count  // explicit copy
let f = fn() { snapshot }  // captures immutable snapshot
count = 42
// f() == 0, count == 42
```

For a shared cell, a new `let` is a second name for the same cell, not a copy. `let snap = xs` does not copy the list `xs`. `xs.slice(0, xs.len())` makes a new list, but it copies one level only: a list of lists still shares the inner lists.

**Capture does not affect the function type.** A closure `fn(Int) -> Bool` that captures mutable variables has the same type as one that captures nothing. Captures are part of the closure's *value*, not its *type*. Higher-order functions, trait implementations, and type inference are unaffected by captures.

#### Closures and `async.spawn`

Closures passed to `async.spawn` **cannot capture `let mut` bindings**. Mutable captures would create data races between the spawned task and the enclosing scope. This is a compile error:

```blink
let mut count = 0
async.spawn(fn() { count += 1 })  // COMPILE ERROR E0650
```

```
error[MutableCaptureInSpawn]: mutable binding captured in spawned task
 --> app.bl:3:18
  |
1 | let mut count = 0
  |         ----- mutable binding declared here
3 | async.spawn(fn() { count += 1 })
  |             ^^^    ^^^^^ mutable capture not permitted in spawn
  |
  = note: spawned tasks cannot share mutable state — data race risk
  = note: binding a List does not copy it (§3.6)
  = help: compute the value inside the task, or send results through a channel
  = help: for a scalar, copy it into a `let` before the spawn:
  |
  | let snapshot = count
  | async.spawn(fn() { use(snapshot) })
  |
  = help: for a List, `xs.slice(0, xs.len())` makes a new list (one level only)
```

An immutable capture of a value that reaches no shared cell is safe. The value cannot change while the task runs:

```blink
let limit = config.max_items
async.spawn(fn() {
    process(limit)  // OK: an Int never changes
})
```

**Shared cells in a spawned task.** An immutable capture can still reach a shared cell (§3.6 *Shared cells*), at any depth. Another name can change that cell: a `let mut` alias, a `mut` parameter, or a struct field. So `async.spawn` freezes it:

- From `async.spawn` until the spawner joins the task, each shared cell that the closure's captures reach is read-only. The spawner joins the task with `h.await`, or when the enclosing `async.scope` exits.
- A write to a frozen cell, through any name and from any task, panics. A cell that more than one task reaches stays frozen until each of those tasks is joined.
- Reads do not change.

The freeze ends in the spawner's program order, so a write panics or succeeds at the same line on every run. It never depends on thread timing. To change a cell that a task reads, await the task first:

```blink
fn main() {
    let xs = [1, 2, 3]
    let mut ys = xs                // ys and xs share one list (§3.6)
    async.scope {
        let h = async.spawn(fn() { xs.len() })
        ys.push(4)                 // PANIC: the task can still read xs
        let n = h.await
        ys.push(n)                 // OK: the task is joined
    }
}
```

The panic message names the write site, the `async.spawn` site, and the captured binding that reaches the cell. Other wording is not specified:

```
panic: write to a List that a spawned task can read
 --> app.bl:6:9
  |
6 |         ys.push(4)
  |         ^^ this List is frozen until the task is joined
  |
5 |         let h = async.spawn(fn() { xs.len() })
  |                 ----------- the task captured `xs`, which reaches this List
  |
  = help: await the task before this write
```

A synchronized object (§3.6 *Synchronized objects*) is not frozen. A task and its spawner may both use a captured `Channel`.

**Lint.** `warning[SpawnCaptureMutAlias]` fires on a write through a `let mut` that directly aliases a captured `let` (for example `let mut ys = xs`), when the write is inside the `async.scope` after the spawn and before the `h.await`. The check is not complete. It does not see an alias made through a call result (`id(xs)`), a struct literal (`W { xs: xs }`) or a `mut` parameter. A clean `blink check` does not prove that no write panics. The freeze is the guarantee.

For inter-task communication with mutable state, use channels:

```blink
let ch = channel.new[Int](buffer: 10)
async.spawn(fn() {
    ch.send(compute_result())  // explicit communication, no shared mutation
})
```

`ch.send` copies each shared cell the sent value reaches, so the receiver gets its own (§4.13 *Channel operations*).

**Handlers in a spawned task.** A task performs effect operations with the handlers in force at its `async.spawn` site (§4.13). A handler in force there is not a capture, so the freeze does not cover it. A handler in force at an `async.spawn` site whose captures reach a shared cell (§3.6 *Shared cells*) is *homed*:

- Its ops run on the task that ran its `with`, the *home task*. An op from another task waits until the home task runs it, then returns its result to that task.
- The home task runs waiting ops whenever it blocks in a blocking operation that the runtime provides: `.await`, `recv`, `send`, the exit of an `async.scope`, `time.sleep`, and blocking I/O such as a read or an accept. A foreign call (`@ffi`) does not run them.
- While an op of a homed handler runs on the home task, the waiting ops of that same handler do not run. Waiting ops of other homed handlers may run. So each op sees its handler's state as the last op left it.

The state of a homed handler is only ever changed by its home task, so a read of that state in the home task gives the same result on every run:

```blink
import std.testing.{capture_log}

fn main() {
    let msgs: List[Str] = []
    with capture_log(msgs) {       // capture_log reaches msgs, so it is homed on main's task
        async.scope {
            let h = async.spawn(fn() {
                io.log("task started")
                21 * 2
            })
            let n = h.await        // main's task runs the waiting log op here
            io.log("got {n}")
        }
    }
    io.println("{msgs.len()}")     // 2, on every run
}
```

A home task that computes for a long time, or that blocks in a foreign call, delays each waiting op until it next blocks in the runtime.

An op body that blocks can wait on a task that waits on an op of the same handler. If the op body waits with `.await` on a task, or exits an `async.scope` that joins it, and that task (directly, or through the tasks it awaits) has an op of the same handler waiting, the runtime panics. The message names the `with` site of the handler, the op, and the `async.spawn` site of the task. Other wording is not specified.

A cycle through a channel has no task to name. If the op body blocks in `recv` or `send`, and only a task that waits on an op of the same handler would end that wait, the two deadlock. The runtime does not detect every such cycle.

#### Closures and Scoped Resources

Closure captures compose with `Closeable` and arena escape rules. A closure that captures a `Closeable` binding cannot escape the `with...as` scope — this is already enforced by E0601:

```blink
with fs.open("data.txt")? as file {
    // OK: closure used synchronously, does not escape scope
    let lines = items.map(fn(item) { format_with(item, file) })

    // ERROR E0601: closure escapes, taking `file` with it
    return fn() { fs.read(file) }
}
```

Same logic applies to arena-allocated values — closures capturing arena bindings cannot escape the arena scope (E0700).

#### Capture Rules Summary

- All captures are **shared reference** (the closure and the enclosing scope see one binding)
- `let` captures: immutable. Equivalent to a copy, except that a change to a shared cell (§3.6) through another name shows through the capture
- `let mut` captures: mutations visible across closure boundary
- No explicit capture syntax (no `move`, no capture lists)
- `async.spawn` closures: immutable captures only. A capture of a `let mut` binding or a `mut` pattern binder (§3.5 *Mutable Binders*) is compile error E0650
- A function value passed to `async.spawn` whose row contains `State`, closure or named function, is compile error E0651 (§4.16.6)
- `async.spawn` freezes each shared cell its captures reach until the spawner joins the task; a write to a frozen cell panics
- A handler in force at an `async.spawn` site whose captures reach a shared cell is homed: its ops run on the task that ran its `with`
- `Closeable`/arena captures: existing escape rules (E0601/E0700) apply transitively through closures
- Capture mode is not part of the function type

**Panel vote:** Shared reference 3-2 (PLT/AI/DevOps for shared; Sys/Web for by-value). No explicit syntax 4-1 (DevOps dissented for `move`). Spawn restriction 3-2 (PLT/DevOps/AI for compile error; Sys/Web for auto-copy). See [DECISIONS.md](../DECISIONS.md). Shared cells in a spawned task: freeze until join 4-2 (Web/AI for a copy at spawn); `SpawnCaptureMutAlias` warning 4-2 (Sys/DevOps for an error); copy at `ch.send` 5-1; E0650 help 5-1. See [decisions/spawn-shared-cell-freeze.md](../decisions/spawn-shared-cell-freeze.md). `Channel[T]` and `Handle[T]` are synchronized objects 6-0; homed handlers 6-0; an await-shape cycle on a homed handler panics 3-3, user tiebreak (PLT/Min/AI for a stated deadlock). See [decisions/channel-handle-synchronized-objects.md](../decisions/channel-handle-synchronized-objects.md).

### 2.9 If/Else Expressions

`if`/`else` is an expression — it evaluates to a value, like `match` and `with...as`. No parentheses around the condition (consistent with `for` loops). Braces required.

```blink
// Expression — both branches must return the same type
let status = if user.active { "online" } else { "offline" }

// Statement — value discarded, type is (), else optional
if amount <= 0 {
    return Err(AccountError.InvalidAmount)
}

// Else-if chains
let tier = if score >= 90 { "gold" }
    else if score >= 70 { "silver" }
    else { "bronze" }

// As the last expression in a function (implicit return)
fn abs(n: Int) -> Int {
    if n < 0 { -n } else { n }
}

// Inside match arms
match expr {
    Div(l, r) => {
        let divisor = eval(r)?
        if divisor == 0.0 {
            Err(CalcError.DivisionByZero)
        } else {
            Ok(eval(l)? / divisor)
        }
    }
}
```

#### Rules

- **Expression context** (let binding, return, argument): `else` is required. Both branches must unify to the same type. Missing `else` is a compile error.
- **Statement context** (value discarded): `else` is optional. The expression type is `()`. If `else` is present, both branches must be `()`.
- **No parentheses** around the condition. The condition is delimited by `if` and `{`. Sub-expression grouping with `()` inside the condition is normal expression syntax, not part of `if`.
- **No truthiness.** The condition must be `Bool`. `if 0 { }` and `if items { }` are compile errors. See [2.19](#219-operator-precedence--semantics).
- **No `if let`** for v1. Use `match` for pattern-based control flow, `??` for Option defaulting. Revisitable in v2 if `match` with single-arm + wildcard proves painful in practice.

**Panel vote: 5-0 unanimous** on all four sub-questions — if/else as expression, else required in expression context, no if-let for v1, parentheses forbidden. See [DECISIONS.md](../DECISIONS.md) for full deliberation.

### 2.10 For-Loops

```blink
for x in collection {
    process(x)
}
```

Iterates over any type implementing `IntoIterator` (§3c.1). No parentheses around the header. Braces required.

The compiler desugars `for x in expr { body }` to:

```blink
let mut __iter = expr.into_iter()
loop {
    match __iter.next() {
        Some(x) => { body }
        None => break
    }
}
```

`break` exits the loop. `continue` skips to the next `__iter.next()` call.

The loop pattern is a `match` arm pattern, so each name in it is immutable unless it is declared `mut` (§3.5 *Mutable Binders*):

```blink
for (name, mut score) in scores {
    score += bonus
    io.println("{name}: {score}")
}
```

**Ranges:**

```blink
for i in 0..100 { }      // exclusive: 0 to 99
for n in 1..=100 { }     // inclusive: 1 to 100
```

`..` is exclusive upper bound, `..=` is inclusive. Ranges are lazy iterables of type `Range[T: Ord]` which implements `IntoIterator`.

No comprehensions in v1 — `for` loops and method chaining (`.map()`, `.filter()`, `.collect()`) cover the same use cases. See §3c.1 for the full iterator protocol.

**Panel vote: 5-0 ratified.** See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 2.3, 2.4.

### 2.11 While/Loop

Two loop constructs for two distinct intents. `while` for conditional looping — keep going until the condition is false. `loop` for unconditional looping — run forever unless explicitly broken out of. No parentheses around the condition (consistent with `if` and `for`). Braces required.

```blink
// Conditional loop — checks before each iteration
while queue.has_next() {
    let item = queue.pop()?
    process(item)
}

// Retry with backoff
let mut attempts = 0
while attempts < max_retries {
    match try_connect(host) {
        Ok(conn) => return Ok(conn)
        Err(_) => {
            attempts += 1
            async.sleep(backoff(attempts))
        }
    }
}

// Infinite loop — event loop, server accept, REPL
loop {
    let event = events.next()
    match event {
        Event.Shutdown => break
        Event.Request(req) => handle(req)
    }
}

// Polling until a condition
let mut result = None
loop {
    let status = check_status()?
    if status.is_ready() {
        result = Some(status)
        break
    }
    async.sleep(poll_interval)
}
```

#### `break` and `continue`

`break` exits the innermost loop. `continue` skips to the next iteration. Both are statements — no break-with-value for v1.

```blink
for item in items {
    if item.is_skip() {
        continue
    }
    if item.is_done() {
        break
    }
    process(item)
}
```

`break` and `continue` work identically in `for`, `while`, and `loop`.

#### Rules

- **No parentheses** around the `while` condition. Delimited by `while` and `{`.
- **No truthiness.** The condition must be `Bool`. `while 1 { }` is a compile error.
- **Statement semantics.** Both `while` and `loop` evaluate to `()`. They are not expressions — you cannot `let x = while ... { }` or `let x = loop { }`. This is consistent with `for` loops.
- **No break-with-value** for v1. Use `let mut` + assign + `break` pattern. Revisitable in v2 if expression-oriented loops prove necessary.
- **No labeled breaks.** Nested loop exit uses extracted functions with early `return`. Labels are a backward-compatible addition if demand materializes.
- **No `while let`.** Consistent with `if let` rejection (5-0). Use `loop { match ... { P => body, _ => break } }` for pattern-based looping.
- **Linter recommendation:** `while true { }` should be written as `loop { }`. The linter warns and auto-fixes.

**Panel vote:** Both constructs 3-2. Plain break/continue 3-2. No labels 4-1. No while-let 5-0. See [DECISIONS.md](../DECISIONS.md).

#### Loop typing and divergence

Both `while` and `loop` are statements that evaluate to `()` (above). One refinement
makes value-returning functions sound: a `loop { }` that **no `break` targets** never
exits, so it has type `Never` (§3.2) rather than `()`, and may stand as the tail of a
function returning any type.

```blink
// `loop` with no reachable break diverges — a valid tail for -> Int
fn run() -> Int {
    loop {
        let ev = poll()
        if ev.is_quit() { return ev.code() }
    }
}
```

- **Only `loop` diverges.** A `while` or `for` can always finish — the condition may be
  false on entry, the iterable may be empty — so both are always `()`, never `Never`,
  even as the tail of a value-returning function. A `while`/`for` tail in a non-`()`
  function is `error[MissingReturn]` (E0311, §3.3).
- **`while true` is not special.** The type checker does not fold the condition;
  `while true { }` has type `()` like any other `while`. Write `loop { }` for an
  intentional infinite loop — the linter warns and auto-fixes `while true` → `loop`
  (above), which is also the form that type-checks as a diverging tail. Blessing
  `while true` as `Never` would force the checker to answer how far condition-folding
  extends (`while 1 < 2`? a `const`?) — a fuzzy boundary the single `loop` form avoids.
- **`break` targeting.** A `loop` diverges only when no `break` names it. The search does
  not cross into a nested loop (whose `break` targets that inner loop) or a closure body;
  `continue` does not stop divergence.

**Panel vote:** Reject-unless-diverges 6-0. One general body-completeness rule (not a
loop-only carve-out) 6-0. `while true` not special (loop-only divergence) 5-1. See
[loop-tail-fallthrough](../decisions/loop-tail-fallthrough.md).

### 2.12 Visibility

All items (functions, types, constants, modules) are **private by default**. The `pub` keyword makes an item visible outside its module.

```blink
// Private — only accessible within this module
fn hash_password(pwd: Str) -> Str ! Crypto {
    crypto.hash(pwd)
}

// Public — part of the module's API
pub fn login(email: Str, pwd: Str) -> Result[User, AuthError] ! DB, Crypto {
    let user = find_user(email)?
    let hashed = hash_password(pwd)
    verify(user, hashed)
}

// Public type
pub type AuthError {
    BadCredentials
    AccountLocked
    RateLimited
}

// Private type — implementation detail
type HashedPassword {
    value: Str
    algorithm: Str
}
```

**Why default private:** Locality of reasoning. A private function can be changed without considering external callers. The public surface of a module is explicitly opted-into, making API boundaries clear to both humans and AI agents. An AI scanning a module's API only needs to read `pub` items — everything else is implementation detail it can skip, saving context window space.

### 2.12.1 Module-Level Bindings

Module-level `let` and `let mut` declare module-scoped bindings. These follow different rules from function-local bindings:

**Duplicate names are a compile error.** Module scope has two namespaces. The value namespace holds `let`, `let mut`, `const` and `fn`. The type namespace holds `type`, type alias, `trait` and `effect`. Each bare name has at most one declaration in each namespace. Module scope is a flat namespace: there is no inner scope for shadowing to inhabit, so a second declaration of a name has no defined meaning. The kinds of the two declarations do not matter: two `let`s, two `fn`s, a `let` and a `fn`, two `type`s, or a `type` and a `trait`, all collide. A `type` and a `fn` of one name do not collide, because they are in different namespaces.

Blink has no function overloading, so two `fn` declarations of one name are an error whatever their signatures. Neither one wins.

The compiler reports `DuplicateModuleBinding` (E1016). Two other codes report the same rule for other pairs: `AmbiguousImport` (E1005) when two imports bind one name, and `DuplicateSymbol` (E1012) when an import and a declaration bind one name (§10.5 *Imported and Declared Names*). The code tells which pair collided; the rule is the same.

```blink
// Valid — each name is unique in its namespace
let max_retries = 3
let mut request_count = 0

// INVALID — compile error E1016
let x = 1
let x = 2                    // error[E1016]: `x` is declared twice in module `main`

fn f() -> Int { 1 }
fn f(n: Int) -> Int { n }    // error[E1016]: `f` is declared twice in module `main`
```

```
error[E1016]: `f` is declared twice in module `main`
 --> src/main.bl:2:4
  |
1 | fn f() -> Int { 1 }
  |    - first declared here
2 | fn f(n: Int) -> Int { n }
  |    ^ declared again here
  |
  = help: rename one of the two declarations
```

The primary span is on the later declaration in source order, and a label marks the first. N declarations of one name give N-1 diagnostics, each one pointing at the first declaration. The fix is a suggestion only, never machine-applicable: the compiler cannot know which declaration to rename. The program does not compile. To check the rest of the module after the error, the compiler binds the name to the first declaration. This is error recovery only; it does not make the first declaration the winner.

**A value must not take a variant's name.** A variant is not in the value namespace. It lives in the `T.` namespace of its type (§2.12.3), and §3.4 *Variant Construction* resolves its bare spelling. But a bare name has one meaning at each site (§3.4), so a module-scope `let`, `let mut`, `const` or `fn` collides with:

- a variant of any enum that a module of the same package declares, and
- a variant of any prelude type (§10.6 *Prelude Types*). The variants of a prelude enum count as declared in every module.

The compiler reports this collision as E1016 too. The reach is the package, not the module: a `fn Leaf` in one module and a variant `Leaf` in another module of the package collide. Two enums that each have a variant `Pending` do not collide with each other (§3.4). The check does not cover a variant of a dependency enum. There, a bare use finds the module-scope value first (§3.4), and W1011 marks the value when an import entry names the variant's type (§10.6 *Shadowing Rules*). A local binding with a variant's name is legal, and gets W1011.

```blink
// src/paint/colors.bl
type Color { Red, Green }

// src/paint/mix.bl
fn Red() -> Int { 1 }        // error[E1016]: `Red` collides with variant `Color.Red`
let Ok = 5                   // error[E1016]: `Ok` collides with variant `Result.Ok`
```

```
error[E1016]: `Red` collides with variant `Color.Red` (module `paint.colors`)
 --> src/paint/mix.bl:1:4
  |
1 | fn Red() -> Int { 1 }
  |    ^^^ module-scope value has the name of a variant
  |
  = note: variant `Color.Red` is declared at src/paint/colors.bl:1:14
  = help: rename the value; a bare `Red` in this package must have one meaning
```

```
error[E1016]: `Ok` collides with variant `Result.Ok` (prelude)
 --> src/paint/mix.bl:2:5
  |
2 | let Ok = 5
  |     ^^ `Ok` is a variant of the prelude type `Result`
  |
  = note: the variants of a prelude enum count as declared in every module
  = help: rename the value
```

The primary span is always on the value declaration, whatever the source order. The message names the variant's type and the module that declares it, and a `note:` gives the variant's location; when both are in one file, a secondary label marks the variant instead. A prelude variant has no source span, so the message says which prelude type has it. Each value declaration with a variant's name gives one diagnostic. As above, the fix is a suggestion only.

**`pub let` exports immutable bindings.** A module-level `let` (without `mut`) can be marked `pub` to make it importable by other modules. For compile-time constants, prefer `const` (see [2.21](#221-const-declarations)) — `let` at module level is for runtime-initialized values.

**`pub let mut` is forbidden.** Mutable module-level state must not be directly exposed to other modules. The compiler reports `PubLetMutForbidden` (E1013) for `pub let mut`.

```blink
// Compile-time constants — prefer const (§2.21)
pub const api_version = "2.0"
pub const default_timeout = 30

// Runtime module state — use let
let mut connection_count = 0

// INVALID — compile error E1013
pub let mut shared_counter = 0  // error[PubLetMutForbidden]: `pub let mut` is forbidden
                                // help: expose mutable state through functions that declare `! State` (§4.16)
```

**Function-local shadowing is unaffected.** Within function bodies, `let` shadowing remains allowed (§2.2). This distinction reflects different scoping models: function bodies use sequential lexical scoping (each `let` opens a new scope), while modules use a flat namespace (all bindings coexist).

```blink
let x = 1  // module-level

fn transform(x: Int) -> Int {
    let x = x * 2    // OK — function-local shadowing
    let x = x + 1    // OK — sequential lexical scope
    x
}
```

### 2.12.2 Opaque Types

`pub type T { ... }` exports the name `T` and its body: its fields or its variants. Code in any module can build a `T`, match on it, and read its fields. `pub opaque type T { ... }` exports only the name. The body is visible only in the module that declares `T`.

```blink
@module("clock")

pub opaque type Stamp {
    nanos: Int
}

pub const Stamp.ZERO = Stamp { nanos: 0 }

pub fn Stamp.from_secs(s: Int) -> Stamp {
    Stamp { nanos: s * 1000000000 }
}
```

Outside the module `clock`:

```blink
import clock.{Stamp}

fn demo(s: Stamp) {
    let a = Stamp.ZERO                 // OK: a `pub` constant (§2.12.3)
    let b = Stamp.from_secs(5)         // OK: a `pub` type-scoped fn (§2.12.3)
    let c = Stamp { nanos: 5 }         // error[E1003]: the body of `Stamp` is private to `clock`
    let n = s.nanos                    // error[E1003]
    match s {
        Stamp { .. } => {}             // error[E1003]: no pattern on an opaque type
    }
}
```

**What the rule hides.** Outside the declaring module, code cannot:

- build a value with a struct literal, a spread (§2.16) or a variant;
- read or write a field;
- match a pattern on the type. This includes `T { .. }`, which names no field. Bind the value to a name, or use `_`.

Everything else works the same as for any type. Code can hold, pass, return and store a value, call trait methods on it, and use the `pub` constants and type-scoped functions of the type (§2.12.3).

**Enums.** An opaque enum hides all of its variants. Outside the declaring module, code cannot build a variant or match on one. No outside `match` on the type can exist, so no exhaustiveness question comes up.

**Where the rule applies.** The check uses the module of the source text:

- Generic code in the declaring module can use the body, wherever mono instantiates it. Generic code in another module cannot.
- A type alias does not open the type. `type Moment = Stamp` in another module is opaque there too.
- In a const expression (§2.21) outside the declaring module, `==`, `!=`, `<`, `>`, `<=` and `>=` on an opaque type are errors. At run time these operators call the type's `Eq` and `Ord` impls. Const evaluation compares the representation directly, which would read the hidden body.

**Value semantics do not change.** `opaque` changes visibility only. A value of an opaque type is copied, passed and stored like a value of any other type. An opaque type is not an `@ffi.opaque` handle (§9.1.4), which stands for a C type that has no layout on the Blink side.

**`opaque` is on the type, not on fields.** There is no per-field `pub`. A type with public fields is a plain `pub type`. A type that has an invariant to protect is a `pub opaque type`. A private type (no `pub`) needs no `opaque`: no other module can name it.

**Derived impls.** A derived impl runs in the declaring module, so it can use the body. *Note (informative):* `@derive(Debug)` on an opaque type works as on any type, and its output shows the hidden fields. To hide a field, such as a secret, write `impl Debug` by hand.

**Diagnostic.** A use of the body outside the declaring module is `PrivateItemAccess` (E1003), the same code as a use of an item that is not `pub`. The message names the type and its module, not a hidden field. The help names the public way in, such as a constant or a type-scoped function.

```
error[E1003]: the body of `Stamp` is private to module `clock`
 --> src/main.bl:5:13
  |
5 |     let c = Stamp { nanos: 5 }
  |             ^^^^^ `Stamp` is an opaque type
  |
  = help: build a `Stamp` with a `pub` constant or function of `Stamp`, such as `Stamp.from_secs`
```

`opaque` is a contextual word. It has this meaning only between `pub` and `type` (§2.23).

### 2.12.3 Type-Scoped Declarations

A module can declare a constant or a function in the scope of a type that the module declares. The name has the form `T.name`, and code reaches it as `T.name`:

```blink
pub opaque type MsgFlags {
    bits: Int
}

pub const MsgFlags.NONE = MsgFlags { bits: 0 }
pub const MsgFlags.PEEK = MsgFlags { bits: 1 }

pub type Duration {
    nanos: Int
}

pub fn Duration.ms(n: Int) -> Duration {
    Duration { nanos: n * 1000000 }
}

fn read(-- flags: MsgFlags = MsgFlags.NONE) { /* ... */ }

let d = Duration.ms(100)
```

**Constants.** `const T.NAME = <expr>` follows every rule of a plain `const` (§2.21). The right side must be a const expression. A type annotation is optional, with the same rule as a plain `const`. `T.NAME` is a const reference, so it is legal in every place that requires a const expression, such as a keyword default.

**Functions.** `fn T.name(params) -> R` is an ordinary function that has no receiver. A `self` parameter is a compile error: a method belongs to a trait (§3c.4 *No Inherent Methods*). Method syntax `x.name()` never reaches a type-scoped function. Only `T.name(...)` calls it.

**Rules for both kinds:**

- **Only the declaring module.** `T` must be a type that the same module declares. `const Other.X` or `fn Other.f()` for a type from another module is a compile error, and the message names the module that declares `Other`. The constants of a builtin type, such as `Float.INF`, belong to the prelude, which declares `Float`.
- **Visibility.** `pub` exports the name. Without `pub`, the name is private to the module, as for any item (§2.12). An opaque type uses this to give the outside its way in.
- **Use from another module.** Import the type, then write `T.name`. The form `mod.T.name` is E1007.
- **No constants on generic types for now.** `T` in `const T.NAME` must not take type parameters.
- **One `T.` namespace.** The variants of `T`, its type-scoped constants and functions, and the associated functions that trait impls give `T` (§3c.4) all share the names after `T.`. Two of them with one name are `DuplicateModuleBinding` (E1016). The check covers the whole package, because a trait impl can live in any module of the package (§3.6). When the trait impl is in another package, the declaration site cannot see it, so the clash is an ambiguity at the use site (E0522). Name the trait's function with an impl-qualified call: `(Trait for T).name()` (§3c.4).

**Why a top-level declaration, not a declaration in the type body.** The type body holds only the representation, fields or variants. For an opaque type, the body is the hidden part, and an API inside it would mix the two. The declaration text is also the same as the use text, so a search for `MsgFlags.NONE` finds both.

### 2.13 Declaration-Site Keyword Arguments

Functions use a `--` separator to divide positional parameters from keyword parameters. Positional params come before `--`, keyword params come after. The function author decides which params are keyword — the caller has no choice. Principle 2 preserved.

#### Syntax

```blink
// Positional only (simple fns, 1-2 params) — no change
fn add(a: Int, b: Int) -> Int { a + b }
add(1, 2)

// Mixed: positional before --, keyword after --
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError] {
    // ...
}
transfer(300, from: alice, to: bob)

// All keyword (config-heavy)
fn start_server(-- host: Str = "0.0.0.0", port: Port = 8080, debug: Bool = false) ! Net {
    // ...
}
start_server(port: 3000)

// Keyword args are order-independent at call site
transfer(300, to: bob, from: alice)  // valid, binds the same way; `bob` is evaluated before `alice`
```

#### Rules

- Params before `--` are **positional**: order matters, no labels at call site
- Params after `--` are **keyword-required**: labels required, order-independent at call site. Arguments evaluate in written order, not declaration order, and bind to their parameters after all of them are evaluated (§2.22)
- Default values only allowed on keyword params (after `--`)
- Default values must be const expressions (see [2.21](#221-const-declarations))
- Labels are **call-site sugar** — the function type is `fn(Int, Account, Account)` regardless of `--`. Closures, trait impls, and higher-order functions are unaffected. See [3.3](#33-type-inference).
- The formatter never reorders arguments, struct-literal fields or list elements. Their written order is their evaluation order (§2.22), so a reorder would change what the program does

**Both rules are enforced by `blink check`.** A label written on a positional parameter is rejected, and a keyword parameter supplied without its label is rejected. Neither rule is a style preference, and neither is left to the formatter. The separator exists to make the swap in `transfer(300, bob, alice)` impossible; a rule the checker does not enforce makes nothing impossible, and a normative sentence the compiler does not hold up teaches a calling discipline that does not exist.

**Where a label resolves.** A call-site label resolves in the callee's **keyword-parameter namespace** — the parameters declared after `--`, and nothing else. This rule governs calls to functions and to methods. A label in a variant-payload application or a struct literal names a **field**, not a parameter, and is outside this rule; the rule governing those labels is stated separately.

**Extent of enforcement.** The rule is stated for every call against a declared `fn` signature, **method calls included**. A rule that held for `f(x: 1)` and not for `b.f(x: 1)` would select two behaviours by the receiver's spelling.

#### Call-Site Diagnostics

Five codes divide the call-site label rules. Each names a distinct mistake, and each has a distinct repair — which is why they are five codes and not one (§3.1 *Diagnostic Discipline*: diagnostics converge on a code when they converge on a repair).

| Code | Fires when | First repair |
|------|-----------|--------------|
| `MissingKeywordArg` (E0510) | A keyword parameter received no argument at all | Supply the argument, labelled |
| `UnlabeledKeywordArg` (E0529) | A keyword parameter received its argument **positionally** | Label the argument already written |
| `InvalidKeywordArg` (E0511) | A label names no keyword parameter of the callee | Correct the label to one the signature declares |
| `PositionalAfterKeyword` (E0527) | A positional argument follows a labelled one | Move it before the first label |
| `DuplicateKeywordArg` (E0528) | The same label appears twice in one call | Delete the repeated argument |

```blink
fn transfer(amount: Int, -- from: Account, to: Account) -> Int { amount }

// intentional-error examples -- each line is rejected, under the code named
transfer(300, alice, bob)                       // error[UnlabeledKeywordArg]: `from` and `to` are
                                                //   keyword parameters
                                                // help: label the arguments:
                                                //   `transfer(300, from: alice, to: bob)`

transfer(300, frm: alice, to: bob)              // error[InvalidKeywordArg]: `frm` names no keyword
                                                //   parameter of `transfer`
                                                // help: the keyword parameters are `from` and `to`

transfer(300, from: alice, bob)                 // error[PositionalAfterKeyword]

transfer(300, from: alice, from: bob)           // error[DuplicateKeywordArg]

transfer(amount: 300, from: alice, to: bob)     // error[InvalidKeywordArg]: `amount` is positional
                                                //   help: pass it without a label
```

`UnlabeledKeywordArg` and `MissingKeywordArg` fire on opposite conditions and must not be confused: the first means *the value is present and unlabelled*, the second means *the value is absent*. `MissingKeywordArg`'s repair inserts an argument; `UnlabeledKeywordArg`'s repair annotates one that is already written, which makes it the only code of the five whose fix is machine-applicable — the parameter names and their positions are both known, and the edit needs nothing from the author's intent.

**Panel vote: `--` separator won 3-1-1** (3 for `--`, 1 for `;`, 1 for `*`). Labels as call-site sugar (not part of type signature): **5-0 unanimous**. See [DECISIONS.md](../DECISIONS.md).

#### Why `--`

The separator marks a safety boundary between positional and named parameters. It should be visually loud and unmissable. `--` is the most distinctive option — hard to confuse with any other Blink syntax. `;` was rejected because Blink already rejected semicolons as statement terminators; reusing `;` as a param separator would confuse AI models into generating statement-terminator patterns. `*` (Python precedent) was considered too subtle.

#### Why Declaration-Site Control

If the *caller* decides whether to use labels (Python/Kotlin-style optional naming), every call site becomes a style decision: name or don't? This violates Principle 2. With declaration-site control, the function signature determines everything. The AI never chooses between two forms — it reads the signature and generates the one correct form.

#### The Problem This Solves

Positional-only args are safe for 1-2 parameters. At 3+ parameters of the same type, they become error-prone:

```blink
// Without keyword args — which is from, which is to?
transfer(300, alice, bob)   // correct
transfer(300, bob, alice)   // compiles, wrong, silent bug

// With keyword args — swap is impossible
transfer(300, from: alice, to: bob)   // correct
transfer(300, from: bob, to: alice)   // still explicit, reviewer sees intent
```

LLMs swap same-typed positional args at measurable rates (3-8% per call site with 3+ same-typed params). Keyword labels eliminate this class of bug structurally.

### 2.14 Struct Field Defaults

Struct fields can declare default values. When constructing a struct, fields with defaults may be omitted — the default is used.

```blink
type ServerConfig {
    host: Str = "0.0.0.0"
    port: Port = 8080
    debug: Bool = false
    max_connections: Int = 100
}

// Only specify what differs from defaults
let config = ServerConfig { port: 3000, debug: true }
// host defaults to "0.0.0.0", max_connections defaults to 100
```

#### Rules

- Default values must be const expressions (see [2.21](#221-const-declarations))
- Fields without defaults are always required at construction
- An omitted field takes its default value
- Struct field defaults do not interact with the type system: `ServerConfig` is the same type regardless of which fields were explicitly provided

#### Why Struct Defaults, Not Function Param Defaults

Function parameter defaults interact with closures (does `fn(Int) -> Int` match a function with a defaulted second param?), higher-order functions, and partial application. Struct field defaults are simpler — a struct is always fully constructed before a function sees it. The complexity stays at the construction site, not in the type system.

Struct defaults also serve as the primary **API evolution mechanism**: adding a new field with a default is always backwards-compatible. Existing construction sites continue to compile unchanged.

### 2.15 Struct Construction Shorthand

When a function takes a single struct argument, the type name can be omitted at the call site. The compiler infers it from the parameter type.

```blink
fn start_server(config: ServerConfig) ! Net {
    // ...
}

// Full form (always valid)
start_server(ServerConfig { port: 3000 })

// Shorthand — compiler infers ServerConfig from parameter type
start_server({ port: 3000 })
```

This reduces boilerplate for config-struct patterns without introducing a new calling convention. The function still takes exactly one positional argument — a struct. The shorthand is purely syntactic sugar at the call site.

The shorthand applies only when:
- The function has exactly one parameter at the relevant position
- That parameter's type is a struct (product type)
- The call site uses `{ field: value }` syntax without a type name

When the type is ambiguous (e.g., the parameter is a trait object or generic), the full form is required.

### 2.16 Spread / Rest Operator (`..`)

`..` is Blink's spread/rest operator. It means "the elements I didn't name" — in patterns it ignores them, in construction it copies them from a source.

#### v1 Contexts

| Context | Syntax | Meaning |
|---------|--------|---------|
| Struct pattern rest | `User { name, .. }` | Ignore remaining fields |
| List pattern rest | `[first, ..]` | Match remaining elements |
| Struct copy-update | `Account { balance: new_val, ..acct }` | Copy remaining fields from source |
| List literal spread | `[..list1, extra, ..list2]` | Expand elements into list |
| Range (infix) | `0..100`, `1..=100` | Exclusive/inclusive range |

Pattern rest and construction spread are duals: patterns discard "the rest," construction copies "the rest" from a source.

#### Struct Copy-Update

When constructing a struct, `..source` at the end of the field list copies all unspecified fields from an existing value of the same type:

```blink
let updated = Account { balance: acct.balance + amount, ..acct }

// Multiple overrides — only changed fields are listed
let patched = Node { kind: NodeKind.Call, args: new_args, ..node }

// Works in any expression position
fn deposit(acct: Account, amount: Int) -> Account {
    Account { balance: acct.balance + amount, ..acct }
}
```

This is purely syntactic sugar. The compiler desugars `T { f1: e1, ..src }` to `T { f1: e1, f2: src.f2, f3: src.f3, ... }` at typecheck time.

**Rules:**

- The source must be the **same nominal type** as the struct being constructed. Cross-type spread is not supported (Blink uses nominal typing).
- `..source` must appear **last** in the field list. This is a hard parse rule — `{ ..src, field: val }` is a parse error.
- At most **one** `..source` per literal. Multiple spread sources are not supported.
- Explicitly provided fields **shadow** same-named fields from the source.
- Source field values take precedence over field defaults (§2.14) for non-explicit fields.

Copy-update composes with the construction shorthand (§2.15):

```blink
fn reconfigure(config: ServerConfig) -> ServerConfig {
    { debug: true, ..config }
}
```

#### List Literal Spread

Inside a list literal, `..expr` expands all elements from the source list:

```blink
let copy = [..original]
let combined = [..list1, ..list2]
let prepended = [first_item, ..rest]
let interleaved = [..heads, separator, ..tails]
```

**Rules:**

- The spread source must be a `List[T]` with the same element type as the list being constructed. Type mismatches are compile errors.
- **Multiple** `..source` spreads are allowed per literal (unlike struct copy-update which allows only one).
- Spreads can appear at **any position** (unlike struct `..source` which must be last) — lists are ordered sequences with no key conflicts.
- Spreads evaluate **left-to-right** and produce a new list (eager copy, not lazy view). `[..a, ..a]` copies `a` twice. Spreads and plain elements evaluate together in written order (§2.22).
- Runtime cost: O(n) per spread source — same as any eager list construction.

**Panel vote: 5-0** for including list spread in v1. The pattern/construction duality (`[first, ..]` deconstructs, `[..list, extra]` constructs) and absence of `.clone()` on lists made this essential. See [DECISIONS.md](../DECISIONS.md).

#### Future Contexts

`..` is a general concept. Future versions may extend it to additional contexts (e.g., tuple spread). Each new context requires its own panel deliberation — the shared sigil is a surface-syntax decision, not a guarantee of uniform semantics across all contexts.

**v1 explicitly does not support:** tuple spread, function call spread. Using `..` in those positions is a parse error.

#### Panel Votes

- **Spread/rest as unified concept**: 5-0. See [DECISIONS.md](../DECISIONS.md).
- **`..` as rest sigil in patterns** (unifying struct `..` and list `..`, dropping `...`): 4-1 (PLT dissented for `*`).
- **`..source` for struct copy-update**: 4-1 (AI/ML dissented for `copy` keyword).
- **List literal spread in v1**: 5-0.

### 2.17 Annotations

Annotations use the `@` prefix and are **compiler-checked** — they are not comments, not decorators, not optional metadata. They participate in type checking, verification, and optimization.

| Annotation | Purpose | Checked |
|------------|---------|---------|
| `@requires(expr)` | Precondition. Must hold when function is called. | Compile-time (SMT) or runtime assertion |
| `@ensures(expr)` | Postcondition. Must hold when function returns. | Compile-time (SMT) or runtime assertion |
| `@where(expr)` | Type-level constraint on generics or refinements. | Compile-time |
| `@perf(constraint)` | Performance contract. Checked by `blink bench`. | Benchmark runner in CI |
| `@capabilities(list)` | Required runtime capabilities (permissions). | Compile-time capability checking |

#### `@requires` and `@ensures` — Contracts

Preconditions and postconditions form verifiable contracts on function behavior. The compiler attempts static proof via SMT solver. Three outcomes: proven (no runtime check), disproven (compile error with counterexample), or unknown (runtime assertion inserted, warning emitted).

```blink
@requires(list.len() > 0)
@ensures(result <= list.len() - 1)
fn binary_search[T: Ord](list: List[T], target: T) -> Int? {
    // ...
}
```

The `@ensures` clause can reference `result` (the return value) and any parameter. Contract violations produce structured diagnostics the AI can act on directly.

#### `@where` — Type Constraints

Constrains generic parameters or refines types beyond what trait bounds express.

```blink
@where(N > 0)
fn chunks[T](list: List[T], n: Int) -> List[List[T]] {
    // compiler knows n > 0 — no division-by-zero possible
}
```

#### `@perf` — Performance Contracts

Declares performance expectations checked by the benchmark runner.

```blink
@perf(p99 < 200ms)
@perf(memory < 50mb)
pub fn process_batch(items: List[Item]) -> Summary ! DB, IO {
    // ...
}
```

`blink bench --check-contracts` runs benchmarks and fails if any `@perf` constraint is violated. This integrates into CI — performance regressions are caught the same way type errors are.

#### `@capabilities` — Runtime Permissions

Declares what system capabilities a function (or module) requires. The compiler verifies that callers have the necessary capabilities.

```blink
@capabilities(net, fs.read)
pub fn download_file(url: Str, dest: Str) -> Result[(), IOError] ! IO, Net {
    // ...
}
```

This enables sandboxing and least-privilege enforcement at the language level. A module declared with `@capabilities(net)` cannot perform filesystem operations, even if it has `! IO` in scope.

#### Annotation Placement

Annotations attach to the item immediately following them. Multiple annotations stack.

```blink
@capabilities(db, crypto)
@requires(email.len() > 0)
@ensures(result.is_ok() => result.unwrap().token.is_valid())
@perf(p99 < 200ms)
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The canonical ordering enforced by `blink fmt` is: `@capabilities` first (permissions), then `@requires`/`@ensures` (contracts), then `@where` (type constraints), then `@perf` (performance). See section 11.1 for the complete ordering across all 13 annotation types.

### 2.18 Scoped Resources (`with...as`)

The `with...as` construct binds a `Closeable` value to a name and guarantees cleanup when the block exits — whether by normal completion, `?` early return, or any other exit path.

```blink
// Single resource
with fs.open("data.txt")? as file {
    let data = fs.read(file)?
    transform(data)
}

// Multiple resources — LIFO cleanup order
with fs.open("in.txt")? as src, fs.create("out.txt")? as dst {
    let data = fs.read(src)?
    fs.write(dst, data)?
}
```

`with...as` is an expression. The block's value is its last expression, same as any other block.

```blink
let data = with fs.open("cache.dat")? as f {
    fs.read(f)?
}
```

#### Disambiguation with effect handlers

The `with` keyword serves two roles. The compiler distinguishes them by the presence of `as`:

| Form | Meaning |
|------|---------|
| `with handler_expr { }` | Effect handler — no `as`, expression type is `Handler[E]` |
| `with expr as name { }` | Scoped resource — has `as`, expression type implements `Closeable` |

Both forms compose in the same `with` statement via comma:

```blink
with mock_db(fixtures), fs.open("data.txt")? as f {
    let data = fs.read(f)?
    process(data)
}
```

Here `mock_db(fixtures)` is an effect handler (no `as`) and `f` is a scoped `Closeable` resource.

#### Rules

- The `?` in `with expr? as name` propagates BEFORE the scope — if acquisition fails, no cleanup needed
- `Closeable` bindings cannot escape the `with` block (compile error E0601)
- `Closeable` bindings cannot be stored in fields or collections within the block (compile error E0602)
- Multiple resources clean up in LIFO order (reverse declaration order)
- Partial acquisition: if `expr2` fails via `?`, only resources from earlier bindings are cleaned up
- The name after `as` is a plain name, never `mut`. Cleanup runs `close()` on the value that `with` acquired, and an assignment to the name would make it close a different value. `with expr as mut f` is `error[E0613] MutOnPattern`; the help says to remove `mut`. A method that writes to a file or a socket takes plain `self` (§3.6 *What `mut self` covers*), so the name needs no `mut` for such calls

---

### 2.19 Operator Precedence & Semantics

#### Precedence Table

From lowest to highest binding:

| Precedence | Operators | Associativity | Category |
|:----------:|-----------|:-------------:|----------|
| 1 (lowest) | `\|>` | left | pipe |
| 2 | `??` | right | coalesce |
| 3 | `\|\|` | left | logical or (short-circuit) |
| 4 | `&&` | left | logical and (short-circuit) |
| 5 | `==` `!=` | left | equality |
| 6 | `<` `>` `<=` `>=` | left | comparison |
| 7 | `+` `-` `*` `/` `%` `<<` `>>` `&` `^` `\|` | left | integer operator groups (see below) |
| 8 | `-` `!` `~` | right | unary prefix |
| 9 | `?` | left | postfix unwrap |
| 10 (highest) | `.` `()` | left | member access, call |

**Non-chaining comparisons.** `a < b < c` is a compile error. The compiler suggests `a < b && b < c`. Chained comparisons introduce context-sensitive operator semantics that contradict Blink's unambiguous-parsing priority. (Vote: 4-1)

#### Integer Operator Groups

Level 7 is a partial order, not one level. It holds five groups:

| Group | Operators | Inside the group |
|-------|-----------|------------------|
| arithmetic | `+` `-` `*` `/` `%` | `*` `/` `%` bind tighter than `+` `-`; each chains left |
| shift | `<<` `>>` | chains left |
| bitwise and | `&` | chains left |
| bitwise xor | `^` | chains left |
| bitwise or | `\|` | chains left |

Each group binds tighter than comparison and equality (levels 5 and 6), and looser than unary prefix (level 8). The five groups have no order among them. An operand of an operator in one group cannot be a bare operator expression of a different group. Write parentheses. If you do not, the compiler gives the parse error `MixedOperatorPrecedence` (E1127):

```blink
fn pack(hi: U32, lo: U32) -> U32 {
    (hi << 16) | lo                // OK: parentheses group the shift
}

let a = x << 1 >> 2                // OK: (x << 1) >> 2, one group
let b = x | y | z                  // OK: one group
let c = a + b * w                  // OK: one group, * binds tighter
let m = ~x & y                     // OK: unary binds tighter, (~x) & y

let e = x << n + 1                 // error[MixedOperatorPrecedence]: `<<` and `+`
let f = v << 24 | v << 16          // error[MixedOperatorPrecedence]: `|` and `<<`
let g = x | y & 3                  // error[MixedOperatorPrecedence]: `|` and `&`
let k = h * 31 ^ x                 // error[MixedOperatorPrecedence]: `^` and `*`
```

The `help:` line of `MixedOperatorPrecedence` shows both groupings, for example `(x << n) + 1` and `x << (n + 1)`. The language server offers both as rewrites. Neither rewrite is machine-applicable, because the compiler cannot know which one the author meant.

An expression of any group can be a bare operand of a comparison or equality operator:

```blink
let low_clear = flags & 0x0F == 0  // (flags & 0x0F) == 0
let fits = x << 1 < limit          // (x << 1) < limit
let same = a + b == c              // (a + b) == c
```

`blink fmt` (§8.8) prints parentheses around a bitwise or shift operand of a comparison or equality operator. Thus `flags & 0x0F == 0` and `(flags & 0x0F) == 0` both format to `(flags & 0x0F) == 0`. The formatter does not add parentheses around an arithmetic operand.

**Why a partial order.** Languages do not agree on these levels. C and Rust put shifts below `+`. Go puts `<<` and `&` on the level of `*`, so `a & b << c` is `(a & b) << c` in Go and `a & (b << c)` in C and Rust. All operands are integers, so a reader who expects the wrong order gets a wrong value and no error. A parse error removes each mix where two languages give different values. The comparison edge stays ordered because the other grouping never type-checks: in `flags & 0x0F == 0`, the C grouping `flags & (0x0F == 0)` applies `&` to a `Bool`. (Votes: shift with arithmetic 6-0; two bitwise operators 6-0; bitwise with arithmetic 6-0; shift with bitwise 6-0 R2, was 4-2; bitwise above comparison 6-0 R2, was 3-2-1; shift as a bare comparison operand 5-1; formatter parentheses 5-1; diagnostic 5-1; unary `~` 6-0.)

#### Operator Desugaring

All operators either desugar to trait method calls or are language primitives.

**Arithmetic** — `+`, `-`, `*`, `/`, `%`, and unary `-` desugar to trait methods (Add, Sub, Mul, Div, Rem, Neg). Arithmetic traits are sealed — only built-in numeric types implement them. Full trait definitions in §3.6.

```blink
// x + y  desugars to  Add.add(x, y)
// x - y  desugars to  Sub.sub(x, y)
// x * y  desugars to  Mul.mul(x, y)
// x / y  desugars to  Div.div(x, y)
// x % y  desugars to  Rem.rem(x, y)
// -x     desugars to  Neg.neg(x)
```

The left operand evaluates before the right one, and both before the trait method is called (§2.22).

Operands must be the same type. Mixed-type arithmetic (`Int + Float`) is a compile error — use explicit conversion: `x.to_float() + y`. (Vote: 5-0)

**Equality** — `==` and `!=` desugar to `Eq.eq` and `Eq.ne`. Any type can implement `Eq`. See §3.6.

**Comparison** — `<`, `>`, `<=`, `>=` desugar via `Ord.cmp` returning `Ordering`. Any type can implement `Ord`. See §3.6.

**Boolean operators** — `&&`, `||`, `!` are language primitives, not trait-dispatched. They require `Bool` operands. Short-circuit: the right operand of `&&` is only evaluated when the left is `true`; the right operand of `||` is only evaluated when the left is `false`. (Vote: 5-0)

```blink
if user.is_admin() || expensive_check(user) {
    grant_access()
}
```

**`?` and `??`** are language primitives for `Result`/`Option`. Already specified in §3.5.

**`|>`** is the pipe operator. Already specified in §2.10.

#### No Truthiness

Only `true` and `false` are `Bool` values. There is no implicit conversion to `Bool`.

```blink
if 0 { }           // compile error: expected Bool, got Int
if items { }       // compile error: expected Bool, got List[T]

if items.len() > 0 { }    // correct: explicit Bool expression
if name.is_empty() { }    // correct: method returns Bool
```

The rule covers every place that takes a condition: `if`, `while`, match guards, and the operands of `&&`, `||` and `!`. An `Int` is never a condition, so `while 1 { }`, `!n` and `ready && n` (with `n: Int`) are compile errors; write `n != 0`. `Bool` and `Int` are different types in every other position too, including `==` between them (§3.4 *`Bool` Is Distinct from `Int`*).

Every language defines truthiness differently — Python, JS, and Ruby all disagree on what's falsy. LLMs cross-contaminate these rules at high rates. Requiring explicit `Bool` eliminates the bug class. (Vote: 5-0)

#### Assignment Operators

`+=`, `-=`, `*=`, `/=`, `%=` are syntactic sugar for reassignment with the corresponding operator:

```blink
let mut count = 0
count += 1       // desugars to: count = count + 1
count *= 2       // desugars to: count = count * 2
```

Only valid on `let mut` bindings. For a bare variable, `x += rhs` means `x = x + rhs`: `x` is read before `rhs` runs. (Vote: 5-0)

For a field path, `s.f op= rhs` reads `s.f`, evaluates `rhs`, applies `op`, and stores the result to `s.f`. A place has no sub-expressions that have effects, so this is the same as `s.f = s.f op rhs`. An index is not a place: `xs[i] += 1` is `error[NoIndexOperator]` (E0313, §3.4). See §2.22 *Assignment places*. (Vote: 6-0)

#### String Concatenation

`+` does **not** work on `Str`. Use interpolation or `.concat()`.

```blink
let full = first + " " + last   // compile error: Str does not implement Add

let full = "{first} {last}"              // interpolation (preferred)
let full = first.concat(" ").concat(last) // .concat() for dynamic cases
```

String `+` encourages O(n²) loops, creates ambiguity with numeric `+`, and violates Principle 2 when interpolation already exists. (Vote: 5-0)

### 2.20 Test Blocks

Tests are first-class syntax — `test` blocks are part of the grammar, understood by the parser, type-checked by the compiler, and run by the built-in test runner. No test framework to import.

```blink
test "add returns sum" {
    assert_eq(add(1, 2), 3)
    assert_eq(add(-1, 1), 0)
    assert_eq(add(0, 0), 0)
}

test "add is commutative" {
    prop_check(fn(a: Int, b: Int) {
        assert_eq(add(a, b), add(b, a))
    })
}
```

#### Syntax

```
test "description string" { body }
```

- `test` is a keyword. The description is a `Str` literal (no interpolation — must be a static string for test discovery).
- The body is a block expression evaluated by the test runner.
- `test` blocks are top-level declarations (peers of `fn`, `type`, etc.). They see all items in their file's module (§10.1).
- Test names must be unique within their module scope. Duplicate names are a compile error.
- Tests are stripped from release builds. They exist only when compiled with `blink test`.

#### Effect Model: Pure by Default

Test blocks have **no implicit effects**, with one exception: like `main`, a test block holds `State` (§4.16.1), so it can read and write module-level `let mut` bindings. A test that calls an effectful function without a handler is a compile error — the same rule as any other function with an empty effect row. Effect handlers within the body introduce effects locally.

```blink
// Pure test — no effects needed
test "deposit increases balance" {
    let acct = open_account(1, "Test")
    let result = deposit(acct, 500)
    assert(result.is_ok())
    assert_eq(result.unwrap().balance, 500)
}

// Effectful test — handlers provide effects explicitly
test "fetch with mock" {
    with mock_net(responses) {
        let result = fetch_data("https://example.com")
        assert_eq(result.unwrap(), "ok")
    }
}

// Multiple effect handlers compose via with
test "integration test with shared environment" {
    with mock_db(fixtures), capture_log([]) {
        run_migration()
        assert_eq(get_user(1).unwrap().name, "Alice")
    }
}
```

This is consistent with Blink's effect system design — effects are explicit, never hidden. The compiler produces actionable errors when a test calls effectful code without a handler:

```
error[UnhandledEffect]: unhandled effect `Net` in test "fetch data"
  --> src/api.bl:45:9
   |
45 |     let result = fetch_data(url)
   |                  ^^^^^^^^^^ `fetch_data` requires `! Net`
   |
   = hint: wrap in `with mock_net(...) { ... }` to provide a handler
```

This is `UnhandledEffect` (E0539). `main` is the other root, and the same code reports a user-declared effect that `main` does not discharge (§4.6 *Unhandled user effects*).

Pure-by-default enables the compiler to safely parallelize test execution — a test whose row is empty, with no effect handlers and no `State`, is guaranteed side-effect-free.

**Panel vote: 5-0 unanimous** for pure by default. See [DECISIONS.md](../DECISIONS.md).

#### Error Propagation: `?` in Test Bodies

A test body may use the `?` operator on `Result[T, E]` or `Option[T]` without an explicit return-type annotation. When `?` appears anywhere in the body, the compiler implicitly elaborates the test body's return type to `Result[(), TestError]`. The surface form (`test "name" { body }`) is unchanged — no annotation is written, none is permitted (see [DECISIONS.md](../DECISIONS.md)).

```blink
test "connect and query" {
    let conn = pg.connect(url)?
    let row = pg.query(conn, "SELECT 1")?
    assert_eq(row.get_int(0), 1)
}
```

`TestError` is a sealed stdlib type carrying a rendered error message plus diagnostic context:

```blink
pub type TestError {
    message: Str,
    error_type: Str,
    origin: SourceLocation,
}
```

`TestError` is an opaque type (§2.12.2) — user code cannot pattern-match on it or construct it, and it cannot be extended. The runner is its sole consumer.

**Lowering.** At each `?` site inside a test body, the `Err(e)` arm of the desugar (§3c.2 Rule 2) is rewritten to invoke `Display.display(e)` and return `Err(TestError { ... })`. For an operand of type `Result[T, E]`, the lowering is:

```blink
// expr? where expr : Result[T, E] inside a test body desugars to:
match expr {
    Ok(val) => val
    Err(e) => return Err(TestError {
        message: Display.display(e),
        error_type: "<static name of E>",
        origin: <span of `?`>,
    })
}
```

For `Option[T]` operands, the lowering is identical except the `None` arm produces a `TestError` whose `message` is `"None"` and `error_type` is `"Option"`.

**`Display` is required at each `?` site.** If `E` does not implement `Display`, the test fails to compile with E0514 pointing at the `?` site. This is the same rule the compiler uses for `?` outside tests under the exact-structural-match constraint (§3c.2 Rule 4): the test author must guarantee the error type can be rendered. The diagnostic suggests implementing `Display` for `E`, or deriving `Debug` for `E` and calling `.unwrap()`, which needs only `Debug` (§7.5).

**Hygiene.** The elaborated return type is internal to the test grammar form. User code cannot name it, dot into it, or observe it from outside. The runner is the sole caller of a test body and consumes the elaborated `Result[(), TestError]` directly.

**Composition with HOFs.** Ordinary higher-order functions are *not* a test grammar form. A closure passed to `for_each` or any user-callable HOF follows the normal `?` rules from §3c.2 — the closure's own return type governs whether `?` is valid inside it, **not** the enclosing test body. A closure that uses `?` must itself return `Result[T, E]` or `Option[T]`:

```blink
test "all rows parse" {
    for_each([("a", "1"), ("b", "2")], fn(case) {
        let (label, raw) = case
        // E0508: `?` inside a closure returning `()`.
        // Fix: change closure return to Result, or call .unwrap() / match.
        let n = parse_int(raw)?
        assert_eq(n.display().len(), 1, label)
    })
}
```

The fix is to lift fallible work out of the closure or change the closure's return type. Test-body elaboration does **not** propagate inward into nested closures.

**`?` inside a `prop_check` property closure.** The property closure passed as the **direct syntactic argument** of the `prop_check` intrinsic (§2.20 *Property-Based Testing*) is the one exception, and it is not a propagation of the enclosing test body's elaboration — it is the *same* closed-surface elaboration applied on its own account. `prop_check` is a compiler intrinsic, not an ordinary HOF: the runner is the sole caller of the property closure and the user can never name or invoke it. When that closure contains `?`, its body is implicitly elaborated to `Result[(), TestError]` exactly as a test body is — no annotation, no trailing `Ok(())`:

```blink
fn parse_port(s: Str) -> Result[Int, ParseError] { /* ... */ }

test "port strings round-trip" {
    prop_check(fn(p: Int) {
        let s = p.display()
        let back = parse_port(s)?           // Err here = property failed for this input
        assert_eq(back, p)
    })
}
```

The trigger is **syntactic**: elaboration applies only when the closure literally appears as the argument in the `prop_check(...)` call. A closure bound to a `let` and then passed in is a first-class value that has already been type-checked against its own written return type, so it obeys plain §3c.2 Rules 2 and 3 (and `?` in it requires it to return `Result`/`Option`):

```blink
test "let-bound property closure is not elaborated" {
    // E0508: `?` inside a closure returning `()` — `prop` is a value, not
    // the direct argument of `prop_check`, so it is not elaborated.
    // Fix: inline the closure into the prop_check(...) call.
    let prop = fn(p: Int) {
        let back = parse_port(p.display())?
        assert_eq(back, p)
    }
    prop_check(prop)
}
```

Each `?` site inside an elaborated property closure renders via `Display[E]` and stamps `TestError.error_type` with the static name of `E` **at that site** — distinct `?` sites in one property may produce distinct `error_type` values (something a single declared error type could not express, since `?` performs no implicit conversion, §3c.2 Rule 4). `?` on an `Option[T]` operand is covered by the same elaboration: the `None` arm yields `TestError { message: "None", error_type: "Option", origin: <span> }`, identical to the test-body lowering. A returned `Err(TestError { ... })` is treated as "property failed for this input": the shrinker minimizes the generated input exactly as it does for an assertion failure, and the failure block prints the rendered error beneath the same `shrunk input:` line (see §8.10 Runner Output). This elaboration applies in both `blink check` and `blink test`.

**Composition with `with`, `skip()`, panics, assertions.** `?` propagating an `Err` is one of the **catchable unwinds** of §4.7.2 — it runs `BlockHandler.exit(false)` and `Closeable.close()` on the way out, identical to assertion failure and `skip()`. Doc-tests are compiled as ordinary tests and obey the same rule.

**Validation symmetry.** `blink check` and `blink test` apply the same elaboration rule — `?` is valid in a test body iff the body would type-check after the implicit `Result[(), TestError]` elaboration. The two pipelines never disagree.

**Failure rendering.** A test that returns `Err(TestError { ... })` produces NDJSON `status: "failed"` with a new `cause` discriminator field (see §8.10 Runner Output). The `cause` enum is closed: `"assertion" | "propagated_error"`. Power-assert introspection is not applied to `?`-propagated errors (there is no source `assert(...)` to decompose); the `TestError.message` field provides the rendered context.

**Panel vote: 6-0 (Q1, Q2, Q3, Q4, Q6), 5-1 (Q5: aiml dissent on rejecting the annotation form).** See [decisions/test-block-question-mark.md](../decisions/test-block-question-mark.md).

#### Built-in Assertions

Four assertion functions are compiler built-ins, available in any test block without import:

| Function | Signature | On failure |
|----------|-----------|------------|
| `assert(expr)` | `fn assert(cond: Bool, msg: Str = "")` | Panics with source location and sub-expression values |
| `assert_eq(a, b)` | `fn assert_eq[T: Eq + Debug](left: T, right: T, msg: Str = "")` | Panics with both values rendered by `debug()` |
| `assert_ne(a, b)` | `fn assert_ne[T: Eq + Debug](left: T, right: T, msg: Str = "")` | Panics with the duplicated value rendered by `debug()` |
| `assert_matches(expr, pat)` | `fn assert_matches[T: Debug](expr: T, pattern)` | Panics with the actual value rendered by `debug()` and the expected pattern |

All assertions accept an optional trailing message for additional context. The message is a regular `Str` — Blink's universal string interpolation applies:

```blink
test "assertions demo" {
    assert(user.is_active())
    assert_eq(account.balance, 500, "after depositing {amount}")
    assert_ne(token_a, token_b)
    assert_matches(withdraw(acct, 9999), Err(BankError.InsufficientFunds))
}
```

`assert_eq` and `assert_ne` enforce their `T: Eq` bound with the same check as `==` (§3.6 *Container Equality*), and they compare with `==`. A type that `==` rejects, `assert_eq` rejects too (`E0306 TraitBoundNotSatisfied`); add `@derive(Eq)` to the type.

The failure output shows the values, so `assert_eq`, `assert_ne` and `assert_matches` also require `T: Debug`, and they render each value with `debug()` (§3.6.1 *Debug vs Display*). They do not use `Display`. `Debug` quotes strings, so `"1"` and `1`, or `"a "` and `"a"`, never print the same. Every type that is `Eq` through *Container Equality* is also `Debug` when its parts are `Debug` (§3.6.1 *Container Debug Rendering*), so `assert_eq(p.parse(""), Ok([]))` compiles as written. A user type needs `@derive(Debug)` or an `impl Debug`. There is no placeholder: a `T` with no `Debug` does not compile.

A missing `Debug` at an assertion call is `E0306 TraitBoundNotSatisfied`, the same code as a missing `Eq`. When `T` lacks both traits, one diagnostic names both. When `T` is a container, a note names the innermost type that has no `Debug`, found by the same walk that `E0520` uses for `@derive(Debug)`:

```
error[E0306]: trait bound not satisfied
 --> tests/inventory_test.bl:12:5
   |
12 |     assert_eq(stock, expected)
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^ `List[Item]` does not implement `Debug`
   |
   = note: `Item` does not implement `Debug` (element of `List[Item]`)
   = help: add `@derive(Debug)` to `Item`
```

**Note:** `assert_matches` is a compiler intrinsic whose second argument is a **pattern** (same syntax as `match` arms), not an expression. It cannot be passed as a higher-order function.

Assertion failure panics — unwinding to the test runner, which marks the test as failed and continues running other tests. This is the one context where Blink uses panic semantics, since tests are controlled environments where unwinding is safe. The test runner's per-test frame is a **runtime catch boundary** in the sense of §4.7.2, so `BlockHandler.exit(false)` and `Closeable.close()` run during the unwind — `with db.transaction() { assert_eq(...) }` rolls back the transaction on assertion failure.

**Panel vote: 4-1** for three built-ins (original §2.20 vote). PLT dissented (assert_ne is `assert(a != b)` — Principle 2 violation). See [DECISIONS.md](../DECISIONS.md). Testing framework deliberation added `assert_matches` (4-1, AI/ML dissented) and optional messages (3-2). See [DECISIONS.md](../DECISIONS.md).

#### `panic()` Function

`panic(msg: Str) -> Never` is a built-in available in all code — not just tests. It triggers an unwind with the given message. In test blocks, the test runner catches the unwind and marks the test as failed. In production code, panic terminates the process with a stack trace.

```blink
fn divide(a: Int, b: Int) -> Int {
    if b == 0 { panic("division by zero") }
    a / b
}
```

`panic` returns `Never` (§3.2), the bottom type. `Never` has no values and is a subtype of every type, so a call to `panic` fits in any expression position. Panic is *not* an algebraic effect — it is untracked divergence, like integer division by zero or array bounds violations. It cannot be caught or handled in normal code (only the test runner catches it).

**Use `Result[T, E]` for recoverable errors.** `panic` is reserved for programmer errors, violated invariants, and genuinely unreachable states. In a library package, `PanicInLibrary` (W0705, below) warns on each `panic`. It does not fire on `todo()` or `unreachable()`.

**Panel vote: 5-0 unanimous.** See [DECISIONS.md](../DECISIONS.md).

#### `todo()` and `unreachable()`

Two more built-ins diverge the same way as `panic`. Each has two forms:

```
todo() -> Never
todo(msg: Str) -> Never
unreachable() -> Never
unreachable(msg: Str) -> Never
```

Both are available in all code. At run time each one is a `panic` (above): untracked divergence, caught by the test runner in a test block, process termination in production code. Neither is an effect, and neither adds a typing rule: each call has type `Never`, so it diverges by the rule in §3.3 *Divergence and Body Completeness*.

The two forms are a property of these built-ins only. A user function has one signature, and a positional parameter cannot have a default value (§2.13). Writing `msg: Str = ""` for these built-ins would show a signature that no user can write, so the spec lists both forms.

**Which one to use.**

| Situation | Write |
|---|---|
| Code that is not written yet | `todo()` or `todo("what is missing")` |
| A path that the author states can never run | `unreachable()` or `unreachable("why it cannot run")` |
| An error the caller can handle | `Result[T, E]` |
| Any other programmer error | `panic(msg)` |

```blink
fn refund(order: Order) -> Int {
    match order.status {
        Pending => 0
        Shipped => order.total
        Cancelled => todo("refund rules for cancelled orders")
    }
}

fn weekday_name(day: Int) -> Str {
    // `day` comes from `day_of_week()`, which returns 0 through 6
    match day {
        0 => "Sun"
        1 => "Mon"
        2 => "Tue"
        3 => "Wed"
        4 => "Thu"
        5 => "Fri"
        6 => "Sat"
        _ => unreachable("day_of_week returns 0 through 6")
    }
}
```

**`unreachable()` is a checked panic in every build mode. It is never undefined behavior.** No build mode, optimization level or flag lets the compiler assume that an `unreachable()` call does not run, or remove the call. If the author's claim is false, the program panics; it does not continue in an undefined state.

**Messages.** The panic message of `todo` contains the text `not yet implemented`. The panic message of `unreachable` contains the text `entered unreachable code`. When the call has a `msg`, the panic message also contains `msg`. These two substrings are stable: a test can match them with `assert_panics(matching: "not yet implemented")`. The rest of the message text is not specified here.

**`TodoInCode` (W0703).** Each call that resolves to the built-in `todo` gets this warning, in every context, test blocks included. A `todo` marks unfinished code, so CI can find each one before release. In a test, the `help:` line names `@skip("reason")` (*Skipping Tests*, below), which is the tool for a test that is not finished. Suppress the warning with `@allow(TodoInCode)`, or set its level with `W0703` under `[lints]` (§4.16.8).

```
warning[TodoInCode]: `todo()` left in code
 --> order.bl:5:22
  |
5 |         Cancelled => todo("refund rules for cancelled orders")
  |                      ^^^^ this panics if it runs
  |
  = help: write the missing code
  = note: upgrade to error in blink.toml: [lints] W0703 = "error"
```

`unreachable` has no warning. It states a claim about the program, not unfinished work.

**`PanicInLibrary` (W0705).** A library returns errors to its caller. It does not end the caller's program. This lint warns on `panic` in a library package.

- **Scope.** A package is a *library package* when its entry module `src/<name>.bl` (§10.1 *Package Entry Resolution*) declares no `fn main`. A package whose entry module declares `fn main` is an application, also when it exports `pub` items and also when the `main` is only a demo. A file outside a package is never library code. If Blink adds a separate library target to a package, this rule applies to that target.
- **What fires.** In each module of a library package, outside test blocks, each reference that resolves to the built-in `panic` gets the warning. Private functions are included. A call fires, and so does a use of `panic` as a value (`let f = panic`); the span is on the reference, and a later call through `f` does not fire again. A call to a user function that panics does not fire; the lint checks that function's own body. The exemption is the same as for `todo` and `unreachable` above: it applies only to a reference that resolves to the built-in, so a user function named `panic`, `todo` or `unreachable` gets no special treatment.
- **Exemptions.** Neither `todo` nor `unreachable` triggers the lint. `todo` already has its own warning. `unreachable` is the form that the paragraph on `panic` allows for states that cannot occur.
- **Level.** The lint is a warning by default. Suppress it with `@allow(PanicInLibrary)` on the function, or set its level with `W0705 = "off"` or `W0705 = "error"` under `[lints]` (§4.16.8). A function-level `@allow` overrides `[lints]`. `@trusted(audit: K)` does not suppress it. The diagnostic has no machine-applicable fix, because each repair changes the function's interface.

```blink
pub fn average(total: Int, count: Int) -> Int {
    if count == 0 { panic("count is zero") }
    total / count
}
```

```
warning[PanicInLibrary]: `panic()` in a library package
 --> src/stats.bl:2:21
  |
2 |     if count == 0 { panic("count is zero") }
  |                     ^^^^^ this ends the caller's program
  |
  = help: return `Result[Int, E]` and return `Err(...)` for this error
  = note: package `stats` is a library: `src/stats.bl` declares no `fn main`
  = note: if this path can never run, use `unreachable()`
  = note: to keep this panic, add `@allow(PanicInLibrary)` to the function
```

The repair that the `help:` line names:

```blink
pub fn average(total: Int, count: Int) -> Result[Int, Str] {
    if count == 0 { return Err("count is zero") }
    Ok(total / count)
}
```

**The `help:` line.** There is one `help:` line, and it names `Result`. The type in it comes from the return type of the nearest enclosing function or closure:

| Return type | `help:` line |
|---|---|
| A concrete type, such as `Int` | ``return `Result[Int, E]` and return `Err(...)` for this error`` |
| `()` | ``return `Result[(), E]` and return `Err(...)` for this error`` |
| A type parameter, or `Never` | ``return `Result[T, E]` and return `Err(...)` for this error`` |
| Already `Result[R, E]` | ``return `Err(...)` for this error`` |

The diagnostic has three `note:` lines, in this order:

1. The scope fact: the package name and the entry file path that the compiler resolved. This note states the fact only. It never suggests adding a `fn main`.
2. `unreachable()`, only for a path that can never run.
3. `@allow(PanicInLibrary)`, to keep the panic.

The output never proposes changing `panic` to `unreachable` as the repair by itself, never names `Option`, and never names `@requires`. A `fn main` added to the entry module only to stop the warning is not a repair: it makes the package an application, and the `panic` still ends the caller's program.

**`blink explain W0705`.** The explain text names the repairs in this order. First, return `Result`. Second, for a condition that each caller must meet, state it with `@requires(...)` (§3b.2) and remove the check, so that no `panic` remains. Third, `unreachable()` for a path that can never run. Fourth, `@allow(PanicInLibrary)`. It says that adding `@requires` and changing the `panic` to `unreachable` is not a repair.

#### `assert_panics` — Asserting Expected Panics

`assert_panics` verifies that a block of code panics. It is the fifth test assertion, in the same family as `assert_matches`: a **compiler-recognized block**, not a function and not a closure value.

```blink
test "division by zero panics" {
    assert_panics {
        let _ = 10 / 0
    }
}

test "unwrap on empty list panics with the expected message" {
    assert_panics(matching: "unwrap called on None") {
        let xs: [Int] = []
        let _ = xs.get(0).unwrap()
    }
}
```

The literal `10 / 0` in the first test gives no warning: `DivisionByLiteralZero` (W0704, §3.6 *Integer Division*) does not fire inside an `assert_panics` body.

**Form.** The body is a `{ ... }` block, *not* a `fn() { }` closure. It can appear only as the operand of `assert_panics` — it cannot be bound to a variable, passed as a higher-order argument, returned, or stored. This is the same syntactic discipline as the pattern argument of `assert_matches`: the construct is operand-only, so no first-class panic-catching handle ever exists. `assert_panics` itself yields no value (its type is `()`); you cannot write `let x = assert_panics { ... }`. There is no `PanicInfo` binding, no `Result`, no `Bool` — the only observable outcome is whether the surrounding test passes or fails.

**Optional `matching:`.** The optional `matching:` keyword argument takes a `Str` and is a **literal substring test**, not a pattern or regular-expression language. The assertion passes only if the panic message *contains* that substring. Substring (rather than exact) matching is deliberate: panic messages carry a volatile ` at file:line` suffix, and a substring matches the stable part (`"unwrap called on None"`, §7.5) while ignoring the location. There is no anchoring, glob, or regex syntax — `matching:` is a plain substring and will not grow metacharacter semantics. String interpolation in the `matching:` argument follows the standard rules.

**Test-only.** `assert_panics` is rejected outside a test block at the parser/typecheck layer (**E0833** `AssertPanicsOutsideTest`), exactly like `skip()`. It is privileged test syntax, not a general-purpose primitive — there is no way to reach it from `main()`, a library function, or any production code.

**No nesting.** An `assert_panics` block lexically nested inside another `assert_panics` block is a compile error (**E0834** `AssertPanicsNestedExpectPanic`). The outer matcher would swallow the inner's mechanism, making "which panic is *the* expected panic" ambiguous.

**Failure modes.** Two runtime diagnostics, both reported through the test runner:

- **E0831** `AssertPanicsBodyReturned` — the body returned normally without panicking. A `?`-propagated `Err` that exits the body without panicking is *also* a body-returned failure, not the expected panic.
- **E0832** `AssertPanicsMessageMismatch` — the body panicked, but the panic message did not contain the `matching:` substring. The failure output renders the expected substring, the **full actual panic message**, and the source location where the panic fired, so the author can correct either the pattern or the message.

**Pass semantics.** A passing `assert_panics` *consumes* the expected panic: the test's status is `"passed"`, **not** `"panicked"`. The top-level `"panicked"` status is reserved for an *unexpected* panic that escapes a test body. See §8.10 for runner output.

**Resource cleanup on the expected panic.** A panic caught by `assert_panics` is a **catchable unwind** in the sense of §4.7.2: in-scope `with`/`Closeable` resources opened *inside* the block run `BlockHandler.exit(false)` / `Closeable.close()` during the unwind, before the runner records the pass.

```blink
test "rolls back on the expected panic" {
    assert_panics(matching: "insufficient funds") {
        with db.transaction() {
            force_withdraw(acct, 9999)   // panics
        }   // transaction.exit(ok=false) runs → rollback, then the panic is consumed
    }
}
```

This is the one place in the language where a `panic` unwind runs cleanup. An *unexpected* panic (outside any `assert_panics` body) still terminates the process and bypasses cleanup, exactly as before. See §4.7.2 for the catchable-unwind set and the fence amendment.

**Why a block, not a closure.** A closure (`fn() { ... }`) is a first-class value: a user could bind it (`let g = ...`) and hold a value whose invocation is panic-catchable, leaking panic recovery into ordinary code. The only guarantee the compiler enforces is about where a catch frame is **created**: a catch frame can only be created by code written lexically inside a `test { ... }` block (**E0833**). A recognized block is never a value, so no expression in the language has a panic-catching type, and `panic: Never` stays sound in the narrow sense that no signature can promise recovery. A closure written inside a test may still *contain* an `assert_panics` block. Nothing confines the resulting function value after that. It may be passed to ordinary code, stored in module-level mutable state, and invoked later from a plain `fn` with no test on the call stack. The block form also keeps the surface familiar: like `pytest.raises(...)` / Rust `#[should_panic(expected = "...")]`, you wrap the region and optionally assert the message.

**Panel vote: 6-0** (all four questions). Resolved the deferred `assert_panics` question from the std.testing deliberation. See [DECISIONS.md](../DECISIONS.md) and [decisions/assert-panics-semantics.md](../decisions/assert-panics-semantics.md).

**`assert_panics` inside a closure written in a test body.** The `assert_panics` fence is **lexical**: the compiler checks where the construct is *written*, not where it runs. A closure written inside a `test` block may therefore contain `assert_panics`, whether it is passed directly as an argument — the `testing.for_each` shape below — or bound with `let` first. Both forms are accepted, and accepting them is deliberate.

**The closure must not outlive the `test` block that creates it.** Do not assign it to module-level state or store it in a field. Passing it directly as an argument rather than binding it with `let` does not by itself satisfy this: an argument is bound to the callee's parameter, and a parameter's type does not say whether the callee keeps the value. **The compiler does not check this**, so nothing will report it when it is violated. If the assertion inside an escaped closure fails when it is called from outside a running test, the behaviour is undefined.

Recommended shape: write the closure where it is consumed, and let the consumer call it within the test, as `testing.for_each` does.

```blink
import std.testing

fn nth(xs: List[Int], i: Int) -> Int {
    xs.get(i).unwrap()
}

test "nth rejects out-of-range indices" {
    let xs: List[Int] = [10, 20, 30]
    testing.for_each([
        ("negative", -1),
        ("past end",  3),
    ], fn(case: Int) {
        assert_panics {
            let _ = nth(xs, case)
        }
    })
}
```

**Panel vote: 5-1** on the paragraph text (Minimalism preferred a shorter rung), **6-0** on striking a non-expressible escape route from the enumeration, **5-1** on scoping the undefined behaviour to the failing assertion (Systems preferred the wider wording). **6-0** that no new language surface is added and the fence stays lexical. See [DECISIONS.md](../DECISIONS.md) and [decisions/assert-panics-closure-fence.md](../decisions/assert-panics-closure-fence.md).

#### Sub-tests and Parameterized Tests

Blink does **not** ship a `subtest` block, a `subtest(label, fn)` HOF, or any other "test-within-a-test" primitive. The test toolbox is intentionally two primitives — `test "..." { }` (§2.20) and `testing.for_each(cases, body)` (§8.10.2) — plus ordinary `fn` helpers for shared setup. Three patterns cover the parameterized-test design space:

**Pattern 1 — homogeneous parametric cases: `for_each`.** When the same assertions run against many inputs of the same shape, use `for_each` with explicit `(label, value)` pairs:

```blink
test "add handles signs" {
    testing.for_each([
        ("zero",     (0, 0, 0)),
        ("positive", (1, 2, 3)),
        ("negative", (-1, -2, -3)),
    ], fn(case: (Int, Int, Int)) {
        let (a, b, expected) = case
        assert_eq(add(a, b), expected)
    })
}
```

**Pattern 2 — heterogeneous phases: multiple `test` blocks with shared setup.** When phases of a workflow exercise different assertions and don't share an iteration shape, write each phase as its own top-level `test` block and factor the shared construction into a helper `fn`:

```blink
fn fresh_parser() -> Parser {
    Parser.new(default_config())
}

test "parser handles empty input" {
    let p = fresh_parser()
    assert_eq(p.parse(""), Ok([]))
}

test "parser handles whitespace-only input" {
    let p = fresh_parser()
    assert_eq(p.parse("   \n\t"), Ok([]))
}

test "parser handles unmatched delimiters" {
    let p = fresh_parser()
    assert(p.parse("(foo").is_err())
}
```

This is the canonical idiom for what other ecosystems use `subtest` / `t.Run` / `describe` for. Three flat tests give the runner three independent failures, each with its own name and stack frame, instead of one composite failure that masks which phase broke.

**Pattern 3 — shared effectful resources: `with` handlers around the body.** When all phases need the same effectful setup (database, mocked network, temp directory), put the `with` block inside each `test`, or factor it into a wrapper `fn` that takes the test body as a closure:

```blink
test "deposit then withdraw" {
    with mock_db(fixtures), capture_log([]) {
        let acct = open_account(1, "Test")
        assert_eq(deposit(acct, 500).unwrap().balance, 500)
        assert_eq(withdraw(acct, 200).unwrap().balance, 300)
    }
}
```

`with` handlers run their `exit(false)` on assertion failure (§4.7.2 / `BlockHandler` catchable-unwind), so transactional rollback, log capture, and temp-path cleanup all behave correctly across the unwind.

**Why no `subtest` primitive.** Adding `subtest` as either a stdlib HOF or a compiler-recognized block was deliberated and rejected. The shapes that go beyond `for_each` + flat `test` blocks all require either (a) a second catch-site for `panic` inside `test` (so siblings could continue after one fails), which would contradict §2.20's "panic is untracked divergence; only the test runner catches it" and §4.7.2's deferral of recoverable panics, or (b) sugar that adds language surface without expressivity gain. Future evidence-driven re-evaluation may reopen the question; the current evidence (no shipped feature missing it, `for_each` covers parametric, helper `fn` covers heterogeneous) is that the gap is documentation-shaped, not syntax-shaped.

**Panel vote: 5-1** (sys dissent for compiler builtin with static enumerability). See [DECISIONS.md](../DECISIONS.md) and [decisions/sub-tests.md](../decisions/sub-tests.md).

#### Assertion Failure Output

Assertion failures use **expression introspection** (Power Assert style). The compiler captures the source text, file/line/col, and decomposes sub-expressions to show their values:

```
assertion failed: assert(account.balance > minimum)
  account.balance = 450
  minimum = 500
  --> src/bank.bl:43:5
```

For `assert_eq` and `assert_ne`, the output uses left/right labels, and each value is rendered by `debug()`:

```
assertion failed: assert_eq(result, Ok(500))
  left:  Err(InsufficientFunds { deficit: 499 })
  right: Ok(500)
  --> src/bank.bl:44:5
```

For `assert_matches`, the output shows the actual value, rendered by `debug()`, and the expected pattern:

```
assertion failed: assert_matches(result, Err(BankError.InsufficientFunds))
  value:   Ok(500)
  pattern: Err(BankError.InsufficientFunds)
  --> src/bank.bl:45:5
```

When a custom message is provided, it appears as additional context:

```
assertion failed: assert_eq(result, Ok(500))
  message: after depositing 1000 into account A-42
  left:  Err(InsufficientFunds { deficit: 499 })
  right: Ok(500)
  --> src/bank.bl:44:5
```

The message expression is evaluated only on failure.

##### Sub-expression Values

For `assert(expr)`, the shape of `expr` sets which sub-expressions get a value line. The list of shapes is closed. Introspection goes one level deep: the compiler does not decompose an operand further.

| Shape of `expr` | Value lines |
|-----------------|-------------|
| Comparison: `a == b`, `a != b`, `a < b`, `a <= b`, `a > b`, `a >= b` | `a`, then `b` |
| Method call: `r.m(x, y)` | the receiver `r`, then each argument |
| Function call: `f(x, y)` | each argument |
| `!e` | the lines that `e` gets |
| `a && b`, `a \|\| b` at the top level | one `Bool` line for each operand that ran; the operands are not decomposed |
| Any other shape | no lines |

Arithmetic has no row of its own. In `assert(a + b == c)` the lines are `a + b` and `c`. A field access such as `account.balance` is one operand.

Each line is `<source text> = <value>`, and the value is rendered by `debug()` (§3.6.1 *Debug vs Display*). `Debug` quotes strings, so a `Str` value and an `Int` value never print the same. The lines come in source order. Each operand is evaluated once, left to right, as in the plain expression, and a line shows the value that the operator or the call received. The lines do not change what the program does.

```
assertion failed: assert(users.contains(name))
  users = ["ana", "bo"]
  name = "cy"
  --> tests/test_users.bl:8:5
```

```
assertion failed: assert(cart.is_open() && cart.total() > 0)
  cart.is_open() = true
  cart.total() > 0 = false
  --> tests/test_cart.bl:14:5
```

**Literal operands get no line.** A literal is one of these tokens: an `Int`, `Float`, `Char` or `Bool` literal, a `Str` literal with no interpolation, or a number literal with a unary `-`. The list is closed. A composite form, such as `[1, 2]`, `Point { x: 0, y: 0 }` or `Ok(500)`, is not a literal and keeps its line:

```
assertion failed: assert(account.balance > 500)
  account.balance = 450
  --> src/bank.bl:43:5
```

```
assertion failed: assert(result == Ok(500))
  result = Err(InsufficientFunds { deficit: 499 })
  Ok(500) = Ok(500)
  --> src/bank.bl:46:5
```

**An operand bound to a `mut` parameter gets no line.** This applies to the receiver of a mutating method (§3.2.2 *Construction and Mutability*) and to an argument bound to a `mut` parameter. The compiler does not bind that operand to a temporary. The call runs on the original place, as written. The callee signature decides this at compile time. The other operands of the call keep their lines:

```blink
trait Enqueue {
    fn try_push(mut self, job: Job) -> Bool
}

impl Enqueue for Queue {
    fn try_push(mut self, job: Job) -> Bool {
        // ...
    }
}

test "queue accepts the job" {
    let mut queue = Queue.new()
    let job = Job { id: 1 }
    assert(queue.try_push(job))     // a line for `job`; no line for `queue`
}
```

**An operand whose type has no `Debug` gets no value line.** The compiler decides this at typecheck, from the static type of the operand as written at the `assert` site and the bounds in scope. It never decides per instantiation. In `fn check[T: Eq](a: T, b: T) { assert(a == b) }`, `a` and `b` get no line, also when `T` is `Int`. There is no placeholder value and no compile error. In its place, the output shows one `note:` line for each such operand, after the value lines and before `-->`. The note text is fixed at compile time and has one of three forms:

| Static type of the operand | Note |
|----------------------------|------|
| A struct or enum that the package of the asserting module defines (the same test as the orphan rule, §3.6 *Trait Coherence*) | `note: <expr> not shown: <Type> has no Debug (add @derive(Debug))` |
| A type parameter | `note: <expr> not shown: <T> has no Debug bound` |
| Any other type: a type from another package, a function type, an opaque or FFI type, or a container whose element has no `Debug` | `note: <expr> not shown: <Type> has no Debug` |

`<Type>` and `<T>` are the static type as written at the `assert` site. A type parameter stays `T`. The derive hint appears only in the first form, where the type to change is the type that the note names.

```
assertion failed: assert(order.total.covers(limit))
  limit = 500
  note: order.total not shown: Money has no Debug (add @derive(Debug))
  --> src/shop.bl:21:5
```

```
assertion failed: assert(stock.contains(item))
  note: stock not shown: List[Item] has no Debug
  note: item not shown: Item has no Debug (add @derive(Debug))
  --> tests/test_inventory.bl:30:5
```

Which lines appear is decided at compile time from the source shape and static types; no runtime value changes the set of lines, except that a `&&`/`||` operand that did not run has no line. The `mut` rule and the `Debug` rule are static rules of this kind. They are not runtime exceptions.

**JSON output.** In `blink test --json`, the record for a failed `assert*` call carries these two fields, in addition to its other fields (§8.10 *Built-in Test Runner*):

- `introspection`: a list of `{"expr": <source text>, "value": <debug string>}`, one entry for each value line, in the same order. An operand with no line has no entry, not `null` and not a placeholder.
- `omitted`: a list of `{"expr": <source text>, "type": <static type as written>}`, one entry for each `note:` line, in the same order.

Both fields are always present. Each is `[]` when it has no entries.

```json
{"record": "test", "file": "src/shop.bl", "name": "order covers limit", "status": "failed", "cause": "assertion", "assertion": "assert(order.total.covers(limit))", "introspection": [{"expr": "limit", "value": "500"}], "omitted": [{"expr": "order.total", "type": "Money"}], "span": {"file": "src/shop.bl", "line": 21, "col": 5}}
```

**Panel vote:** Debug rendering, omission decided at typecheck, the fixed-set rule, the literal rule and the JSON fields 6-0. The `note:` line 5-1 (Minimalism dissented: a note is a stand-in one level up). The shape table 5-1 (Minimalism dissented: call rows make partial output the normal case). The note forms 6-0 after a 3-3 first round. See [decisions/power-assert-debug-rendering.md](../decisions/power-assert-debug-rendering.md).

The test runner distinguishes assertion failures (`"status": "failed"`) from unexpected panics (`"status": "panicked"`) in structured output, enabling CI to categorize "test found a bug" vs "test itself is broken."

**Panel vote: 4-1** for expression introspection. PLT dissented (left/right is structurally honest; introspection is ad-hoc compiler analysis). Majority: sub-expression values greatly improve debugging. See [DECISIONS.md](../DECISIONS.md).

#### Property-Based Testing

`prop_check` is a built-in for property-based testing. It generates random inputs based on the closure's parameter types and runs the body repeatedly.

```blink
test "sort is idempotent" {
    prop_check(fn(list: List[Int]) {
        assert_eq(sort(sort(list)), sort(list))
    })
}
```

`prop_check` is available in test blocks without import. The compiler infers generator strategies from parameter types. Run property tests specifically with `blink test --prop`.

A property body may use `?` directly — a fallible call inside the property is a first-class way to express "this must succeed for the property to hold." Because the property closure given as the direct argument of `prop_check` is elaborated like a test body (see *Error Propagation: `?` in Test Bodies* above), a propagated `Err` is reported as a property failure with the shrunk counterexample, not as a panic:

```blink
test "decoded bytes round-trip" {
    prop_check(fn(raw: [U8]) {
        let decoded = decode(encode(raw))?
        assert_eq(decoded, raw)
    })
}
```

#### Test Scope

Test blocks are top-level declarations in the same file as the code they test. Since one file = one module (§10.1), tests see **all items** in their module — both `pub` and private. No special scoping mechanism needed.

```blink
// auth/token.bl

fn hash_password(pwd: Str) -> Str {
    // private implementation detail
}

pub fn verify(pwd: Str, hash: Str) -> Bool {
    hash_password(pwd) == hash
}

// Test in the same file — can access private hash_password
test "hash_password produces consistent output" {
    let h1 = hash_password("secret")
    let h2 = hash_password("secret")
    assert_eq(h1, h2)
}

test "verify rejects wrong password" {
    assert(!verify("wrong", "expected_hash"))
}
```

The scoping rule is simple: a `test` block in a file sees everything in that file's module, same as any `fn` in the file. No special visibility modifiers needed. To test private internals, put the test in the same file as the implementation.

#### Discovery & Filtering

Tests are discovered at compile time — the compiler knows every `test` block's name, module path, file location, and tags.

```blink
@tags("slow", "integration")
test "full order flow" {
    with mock_db(fixtures), mock_payment() {
        let result = place_order(sample_order())
        assert(result.is_ok())
    }
}
```

The `@tags(...)` annotation attaches string tags to a test block for structured filtering. Tags are compile-time metadata — stripped with test bodies in release builds.

**CLI filtering:**

```sh
blink test                           # run all tests
blink test --filter "deposit"        # name substring match
blink test auth/                     # run tests in auth/ module path
blink test --tag unit                # run tests tagged "unit"
blink test --tag slow --exclude      # run all tests EXCEPT tagged "slow"
blink test --prop                    # run property tests only
blink test --json                    # structured JSON output
```

**Panel vote: 4-1** for annotation tags. AI/ML dissented (tags are metadata LLMs forget; name conventions suffice). Majority: structured tag filtering is day-one CI infrastructure; without it, teams hack naming conventions. See [DECISIONS.md](../DECISIONS.md).

#### Skipping Tests

Blink provides two skip mechanisms for two fundamentally different use cases: compile-time unconditional skip via annotation, and runtime conditional skip via built-in function.

**`@skip` annotation — unconditional, compile-time:**

```blink
@skip
test "not implemented yet" {
    assert_eq(unimplemented_feature(), 42)
}

@skip("waiting on async support")
test "async test" {
    // ...
}
```

`@skip` takes an optional reason string. The compiler still type-checks the test body (catching errors in skipped tests during refactors), but the test runner does not execute it. Skipped tests appear in output with status `"skipped"`.

When both `@tags` and `@skip` are present, `@tags` comes first:

```blink
@tags("integration")
@skip("DB migration pending")
test "full order flow" {
    // ...
}
```

**`skip()` function — conditional, runtime:**

```blink
test "platform specific" {
    if !is_linux() {
        skip("only runs on Linux")
    }
    assert(check_platform_feature())
}
```

`skip(reason: Str) -> Never` is a built-in available in test blocks. It unwinds to the test runner (same machinery as assertion failure panics) and marks the test as `"skipped"` with the given reason. Use `skip()` for decisions that depend on runtime state: platform detection, environment variables, feature flags. Like assertion failure, `skip()` is a catchable unwind in the sense of §4.7.2 — `Closeable.close()` and `BlockHandler.exit(false)` run for any in-scope resources before the test runner records the skip. A test that allocates a temp directory and then `skip()`s on platform mismatch will release the temp directory.

**When to use which:**

| Situation | Mechanism |
|-----------|-----------|
| WIP / not yet implemented | `@skip("reason")` |
| Broken, will fix later | `@skip("reason")` |
| Platform-specific | `skip()` with condition |
| Requires specific environment | `skip()` with condition |

**JSON output for skipped tests:**

```json
{"record": "test", "file": "tests/test_async.bl", "name": "async test", "status": "skipped", "reason": "waiting on async support"}
```

Both `@skip` and `skip()` produce the same `"skipped"` status in JSON output. The `"skipped"` count in the summary reflects both.

**Panel vote: 3-2** for both mechanisms. PLT and AI/ML dissented (wanted `@skip` only — Principle 2 concern). Majority: compile-time and runtime skips are fundamentally different evaluation times; conflating them forces either losing static skipping at compile time or losing runtime conditional skipping. See [DECISIONS.md](../DECISIONS.md).

#### Doc-Tests

Code examples in `///` doc comments are compiled and run as tests:

```blink
/// Parses a string to an integer.
///
/// ```
/// assert_eq(parse_int("42"), Ok(42))
/// assert_eq(parse_int("nope"), Err(ParseError))
/// ```
fn parse_int(s: Str) -> Result[Int, ParseError] {
    // ...
}
```

Doc-tests verify that documentation stays in sync with implementation. They are run by `blink test` alongside regular test blocks.

#### Rules Summary

- `test` is a keyword — first-class syntax, not a macro or library
- Test names are static `Str` literals (no interpolation)
- Pure by default — no implicit effects. Use `with` handlers for effectful tests
- `?` operator is valid inside a test body — the body is implicitly elaborated to `Result[(), TestError]`. `TestError` is sealed; `Display[E]` is required at each `?` site. No annotation form (`test "name" -> Result[...] { }`) exists or will be added
- Four built-in assertions: `assert`, `assert_eq`, `assert_ne`, `assert_matches`
- All assertions accept an optional trailing `Str` message for context
- `assert_matches` takes a pattern (not an expression) as its second argument
- `assert_panics { ... }` (optional `matching: Str` substring) asserts the block panics — a compiler-recognized block, test-only, valueless, non-nestable
- Assertion failure panics (unwind to test runner, expression introspection on failure)
- `panic(msg: Str) -> Never` available everywhere — untracked divergence, not an effect
- Test runner distinguishes assertion failures from unexpected panics in JSON output
- `prop_check` built-in for property-based testing
- Tests in a file see all items (pub and private) in that file's module
- `@tags(...)` annotation for structured filtering
- `@skip` annotation for unconditional compile-time skip (body still type-checked)
- `skip(reason: Str) -> Never` built-in for conditional runtime skip
- Stripped from release builds
- JSON structured output via `blink test --json`

### 2.21 Const Declarations

The `const` keyword declares compile-time constants. Unlike `let` (runtime-initialized, immutable), `const` bindings are evaluated by the compiler during compilation and their values are fixed at compile time. The right-hand side must be a **const expression**.

```blink
const MAX_RETRIES = 5
const TIMEOUT_MS = 30 * 1000
const API_VERSION = "2.1.0"
const DEFAULT_HOST = "0.0.0.0"
const MAX_PAYLOAD = 1024 * 1024 * 10
const DEBUG = false
```

#### Const Expressions

A **const expression** is built from a closed set of operations that the compiler can evaluate without executing the program:

| Category | What's Allowed | Examples |
|----------|---------------|----------|
| Scalar literals | `Int`, `Float`, `Str`, `Bool`, `Char`, `None` | `42`, `3.14`, `"hello"`, `true`, `'x'`, `None` |
| Arithmetic | `+`, `-`, `*`, `/`, `%`, unary `-` | `1024 * 64`, `TIMEOUT / 3` |
| Boolean | `&&`, `\|\|`, `!` | `true && !DEBUG` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` | `MAX > 0` |
| Const references | Other `const` bindings by name, and type-scoped constants (§2.12.3) | `MAX_PAYLOAD * 2`, `MsgFlags.NONE` |
| Struct literals | Struct construction with all-const fields | `ServerConfig { port: 8080 }` |
| Enum variants | Variant construction with const payloads | `LogLevel.Info`, `Some(42)` |

What is **not** a const expression:

- Function calls: `some_fn()` — even pure functions
- Method calls: `"hello".len()` — methods are function calls
- `let` bindings: referencing a `let` variable is not const
- Collection constructors: `List.new()`, `Map.new()` — these allocate
- Mutable state: anything involving `let mut`
- An operator on a user type: `MsgFlags.PEEK | MsgFlags.WAITALL`. The operator is a call to a trait impl (§3.6), so §2.21 does not admit it. To use a combination as a default, declare it as its own constant.

```blink
// Valid const expressions
const BUFFER_SIZE = 1024 * 64
const ENABLED = true && !DEBUG
const HALF_TIMEOUT = TIMEOUT_MS / 2

// NOT valid — compile errors
// const BAD1 = "hello".len()       // error[NonConstExpr]: method calls not allowed
// const BAD2 = compute_max()       // error[NonConstExpr]: function calls not allowed
// const BAD3 = some_let_binding    // error[NonConstExpr]: `let` bindings are not const
```

**Purity does not imply constness.** A pure function (no `!` annotation) is effect-free at runtime, but is not const-evaluable. Const evaluation is a separate, narrower concept — it means "the compiler can compute this during compilation using a fixed set of total operations." Extending to `const fn` is a potential v2 feature; v1 keeps the boundary syntactically obvious.

#### Struct and Enum Constants

Struct literal syntax and enum variant construction are const-eligible when all field values are themselves const expressions. Struct field defaults from the type definition are used for omitted fields (those defaults are already required to be const).

```blink
type LogLevel {
    Debug
    Info
    Warn
    Error
}

const DEFAULT_LOG_LEVEL = LogLevel.Info

type ServerConfig {
    host: Str = "0.0.0.0"
    port: Int = 8080
    max_retries: Int = MAX_RETRIES
    debug: Bool = false
}

// All fields are const — valid
const DEFAULT_CONFIG = ServerConfig {
    host: "localhost"
    port: 3000
    debug: true
}

// Omitted fields use their (const) defaults — also valid
const PROD_CONFIG = ServerConfig {
    host: "0.0.0.0"
    port: 443
}
```

Only struct **literal** syntax (`Type { field: value }`) is const. Constructor functions like `Type.new()` are function calls and are not const, even if they return the same value.

#### Where Const Expressions Are Required

Const expressions are required in four contexts:

1. **`const` declarations** — the RHS must be a const expression
2. **Struct field defaults** — `type Foo { x: Int = <const> }`
3. **Keyword argument defaults** — `fn f(-- x: Int = <const>)`
4. **Range pattern bounds** — `match n { 1..=MAX => ... }`

```blink
// Struct field defaults — const expressions
type RetryConfig {
    max_retries: Int = MAX_RETRIES
    backoff_ms: Int = TIMEOUT_MS / MAX_RETRIES
    timeout_ms: Int = 60 * 1000
}

// Keyword arg defaults — const expressions
fn connect(url: Str, -- timeout: Int = TIMEOUT_MS, retries: Int = MAX_RETRIES) ! Net.Connect {
    // ...
}

// Range pattern bounds — const expressions
fn classify(code: Int) -> Str {
    match code {
        0 => "zero"
        1..=MAX_RETRIES => "retry range"
        200..=299 => "success"
        _ => "other"
    }
}
```

#### Const Evaluation Must Succeed

The compiler evaluates each const expression in the four contexts above. If an operation in that evaluation would panic at run time, the program does not compile, and the error is `ConstEvalPanic` (E0546). This covers integer `/` and `%` by zero (§3.6, *Integer Division*), signed `MIN / -1`, and integer overflow (§3.2, *Overflow behavior*). The rule is the same in each context. An `assert_panics` body (§2.20) does not change it, because a compile error is not a run-time panic.

```blink
const SHARDS = 0
const PER_SHARD = 1024 / SHARDS                // error[ConstEvalPanic]: division by zero
const TOO_BIG = 9223372036854775807 + 1         // error[ConstEvalPanic]: Int overflow

type Pool {
    size: Int = 64 % SHARDS                     // error[ConstEvalPanic]: division by zero
}
```

The error points at the subexpression that fails. It has one `note:` for each `const` reference that leads to the failing value, so the reader can find the const that holds the 0:

```
error[ConstEvalPanic]: this const expression panics when the compiler evaluates it
  --> config.bl:2:19
   |
 2 | const PER_SHARD = 1024 / SHARDS
   |                   ^^^^^^^^^^^^^ division by zero
   |
note: `SHARDS` is 0
  --> config.bl:1:7
   |
 1 | const SHARDS = 0
   |       ^^^^^^
```

Outside the four contexts, a zero divisor is not a compile error: `let a = 10 / 0` compiles and panics at run time. §3.6 *Integer Division* gives the warning for a literal zero divisor.

#### Visibility

`const` declarations support `pub` for export, same as `let`:

```blink
pub const API_VERSION = "2.0"
pub const DEFAULT_PORT = 8080

const INTERNAL_LIMIT = 1000  // private to module
```

There is no `const mut` — constants are inherently immutable. `const mut` is a compile error (E1102).

#### Module-Level `let` vs `const`

`const` and `let` at module level serve different purposes:

| | `const` | `let` |
|-|---------|-------|
| Evaluation | Compile time | Program initialization |
| RHS | Must be const expression | Any expression (runtime) |
| Mutability | Never | `let mut` allowed |
| `pub` export | Yes | Yes (immutable only) |

Module-level `let` remains valid for runtime-initialized module state:

```blink
// Compile-time constant
const MAX_RETRIES = 5

// Runtime: initialized when the module loads
let mut request_count = 0
```

The compiler folds const expressions at compile time. Arithmetic like `1024 * 64` gives `65536`, and struct consts have all fields resolved.

#### Error Codes

| Name | Code | Description |
|------|------|-------------|
| `NonConstExpr` | E1101 | Expression is not a compile-time constant |
| `ConstMutForbidden` | E1102 | `const` binding cannot be `mut` |
| `NonConstStructDefault` | E1103 | Struct field default is not a const expression |
| `NonConstKeywordDefault` | E1104 | Keyword argument default is not a const expression |
| `NonConstRangeBound` | E1105 | Range pattern bound is not a const expression |
| `ConstEvalPanic` | E0546 | Evaluation of a const expression would panic: integer `/` or `%` by zero, signed `MIN / -1`, or overflow |

```
error[NonConstExpr]: expression is not a compile-time constant
  --> server.bl:5:15
   |
 5 | const BAD = compute_max()
   |             ^^^^^^^^^^^^^ function calls are not allowed in const expressions
   |
   = help: const expressions allow: literals, arithmetic, boolean ops, comparisons,
           references to other `const` bindings, struct literals, and enum variants
```

**Panel vote:** Const expression scope (literals + arithmetic) 5-0 unanimous. `const` keyword required 3-2 (PLT/DevOps/AI for `const`; Sys/Web for inferred `let`). Struct literals with const fields 3-1-1 (PLT/DevOps/AI for struct literals; Web for nested structs; Sys for scalars-only). Compiler-evaluated emit literals 5-0 unanimous. See [DECISIONS.md](../DECISIONS.md).

### 2.22 Evaluation Order

An expression evaluates its operand sub-expressions exactly once, one at a time, left to right in written order. A read of a variable is an evaluation at its written position. Each operand finishes, side effects and panics included, before the next starts. If one exits early through `?` or a panic, the operands after it are not evaluated, and the expression does not perform its operation. Otherwise the expression then performs its own operation.

The forms whose semantics decide which sub-expressions run evaluate only the parts their sections select, and in the same relative order. The list is closed:

- `&&` and `||` (§2.19): the right operand runs only as short-circuit selects it.
- `??` (§3.5): the default runs only when the left side is `None`.
- `if` (§2.9) and `match` (§3.5), arms and guards: the condition or scrutinee runs first; then only the selected arm, and the guards tried before it, in written order.
- Loops, `while`, `loop` and `for` (§2.10, §2.11): the condition and the body run zero or more times. Each run follows this rule again.

A closure literal is a value. Making it does not run its body; the body runs at each call, under this rule at that call. A block expression is an ordinary operand: in `f({ tick(1) }, tick(2))` the block runs first.

An implementation may evaluate in another order only when no program can observe the difference. Observable means output, the value of any binding (including a `let mut` binding written through a closure, §2.8), which panic occurs, and whether evaluation terminates. An empty effect row is not enough to reorder: effect rows do not record writes to captured `let mut` bindings or overflow panics (§3).

#### What each form evaluates

These follow from the rule. They are not extra rules.

- **Call:** the callee, when it is an expression, then the receiver of a method call, then the arguments as written. Keyword arguments run in written order, not declaration order, and bind to their parameters after all of them are evaluated. Omitted keyword arguments take const defaults (§2.21), so their placement cannot be observed.
- **Operator:** left operand, then right operand, then the trait method. `x + y` is `Add.add(x, y)` (§2.19), so the call rule covers it.
- **Literal:** list elements and spreads (§2.16), tuple elements, struct-literal fields and variant payloads, as written. Struct-literal fields run in written order, not declaration order.
- **Interpolation:** holes left to right. Each hole's value is appended before the next hole starts. In a template literal `t"..."` (§2.4.3) the values list is built in the same order.
- **`with` items:** left to right, as §4.7 *Disambiguation rules* states.
- **Assignment `place = rhs`:** see *Assignment places* below.

```blink
fn f(-- a: Int, b: Int) -> Int { a + b }

fn tick(n: Int) -> Int {
    io.println("{n}")
    n
}

fn main() {
    let _ = f(b: tick(2), a: tick(1))   // prints 2, then 1: written order
    let _ = tick(3) + tick(4)           // prints 3, then 4
    io.println("{tick(5)} {tick(6)}")   // prints 5, 6, then "5 6"

    let mut n = 0
    let bump = fn() -> Int {
        n = n + 1
        n
    }
    io.println("{bump() + n * 100}")    // 101: n is read after bump() returns
    io.println("{bump()} {bump()}")     // "2 3"
}
```

An element write is a method call, so the call rule orders it. The arguments run before the method, and the method checks bounds when it runs:

```blink
fn fill() -> Int {
    io.println("fill")
    7
}

fn main() {
    let mut xs = [1, 2, 3]
    xs.set(10, fill())   // prints "fill", then panics: `set` runs after its arguments
}
```

#### Assignment places

A place is a `let mut` binding, or a field path `s.f.g` whose root is a `let mut` binding. Each step of a field path names a struct field (`s.f`) or a tuple field (`t.0`), so a path such as `s.f.0` has no sub-expressions that have effects or can fail. No step goes through a `Ptr`: for `p: Ptr[S]`, `p.f = v` is not an assignment to a place, and the help names `p.f.write(v)` (§9.1.3, *Writes that are not to a place* below). `place = rhs` evaluates `rhs`, then reads the root binding, then stores. So a write that `rhs` makes to the same binding, through a closure, is not lost. Storage the compiler shares between values is never a place. A feature that adds places must keep that rule (§3.6.1 *Clone Semantics*). A store to a place is rule 1 of E0601 (§9.1.1 *Scope tags*).

```blink
type Stats {
    count: Int
    total: Int
}

fn main() {
    let mut s = Stats { count: 0, total: 0 }
    let record = fn() -> Int {
        s.count = s.count + 1
        5
    }
    s.total = record()
    io.println("{s.count} {s.total}")   // "1 5": the store reads s after record() returns
}
```

An index is not a place. Blink has no index operator (§2.6), so `xs[i] = v` and `xs[i] += v` are `error[NoIndexOperator]` (E0313, §3.4 *Postfix Brackets That Are Not a Type Application*). An element write is a method call: `List.set`, `Bytes.set` or `Map.insert`. The call rule orders it, as the `xs.set(10, fill())` example under *What each form evaluates* shows.

Compound assignment `place op= rhs` reads the place's current value, then evaluates `rhs`, applies `op`, and stores the result to the same place (§2.19).

```blink
fn main() {
    let mut n = 1
    let bump = fn() -> Int {
        n = n + 10
        0
    }
    n += bump()
    io.println("{n}")     // 1: n is read (1) before bump() runs, then 1 + 0 is stored
}
```

The formatter never reorders arguments, struct-literal fields or list elements, because their written order is their evaluation order (§2.13).

**Why not "unspecified".** C leaves argument order unspecified, and the C compilers Blink targets differ. An unspecified order would give one Blink program different output under gcc, clang and zig cc. No diagnostic can find the order-sensitive cases, because effect rows do not record writes to captured `let mut` bindings or overflow panics. That is under-determined behaviour with no error, which Blink rejects (§3.4, `E0301`).

**Panel vote: 6-0** on each point: written order everywhere, the closed list, compound assignment, the formatter rule, and assignment places. See [decisions/argument-evaluation-order.md](../decisions/argument-evaluation-order.md).

#### Writes that are not to a place

The left side of `=` or `op=` must be a place. When it is not, the compiler checks four cases in this order and reports only the first that applies. So the help is always the last fix the line needs:

1. **A step goes through a `Ptr`.** `error[NotAPlace]` (E0611). The `Ptr` can be the root (`p.f = v` for `p: Ptr[S]`) or a field in the middle of the path (`s.p.f = v` for `s.p: Ptr[S]`). The root kind does not matter: a `let`, a `let mut` and a parameter all give E0611.
2. **The root is a temporary**, such as a call result: `mk().x = 5`. `error[NotAPlace]` (E0611). No name reaches the value, so the store is lost.
3. **The root is a parameter**, `self` included. `error[ParamAssign]` (E0612, §3.6 *Mutable Parameters*).
4. **The root is an immutable binding.** `error[MutationRequiresMut]` (E0610, §3.2.2 *Construction and Mutability*).

When two cases apply, the first one in the list wins. For `mk().p.f = v` case 1 wins, and the help is `mk().p.f.write(v)`. For `fn f(p: Ptr[S]) { p.f = 1 }` case 1 wins over case 3. A `Ptr` write is legal through a plain `let`, a parameter or a temporary (§3.6 *What `mut self` covers*), so "add `mut`" or "copy it to a new name" would not fix the line.

**A write through a `Ptr`.** The fix calls `write` on the same path (§9.1.3 *Field access on `Ptr[@ffi.struct T]`*). `place = rhs` runs `rhs` and then reads the root, but a method call reads its receiver before its arguments (*What each form evaluates*). So `p.f.write(rhs)` reads `p` before `rhs` runs, and when `rhs` changes `p` through a closure, the two forms store to different memory. The fix keeps the order of `place = rhs`:

- **`rhs` is inert:** a literal, a name, or a field path of names (`cfg.limit`). It has no operator, call or other sub-expression, so it cannot run code. The machine-applicable fix writes `p.f.write(rhs)`.
- **Any other `rhs`, when the assignment is a statement in a block:** the machine-applicable fix binds `rhs` to a new name on the line before, and then writes the name: `let v = rhs` and `p.f.write(v)`. The name is one that is not in scope at that line.
- **Otherwise**, for example the body of a match arm with no braces: help only. The help shows the two-line form.

`p.f op= rhs` through a `Ptr` gets help only, in every case: `p.f.write(p.f.read() op rhs)`. A note says this is a read and then a write, not one atomic step.

```
error[NotAPlace]: cannot assign through a `Ptr`
 --> poll.bl:7:5
  |
7 |     p.events = next_events()
  |     ^^^^^^^^ `p` is a `Ptr[PollFd]`
  |
  = note: a field behind a `Ptr` is not a place; write it with `.write()`
  = note: the right side runs before `p` is read, so the fix keeps it on its own line
  = help: `let events = next_events()`, then `p.events.write(events)`
```

```
error[NotAPlace]: cannot assign through a `Ptr`
 --> stats.bl:9:5
  |
9 |     c.hits += 1
  |     ^^^^^^ `c` is a `Ptr[Counter]`
  |
  = note: this is a read and then a write, not one atomic step
  = help: `c.hits.write(c.hits.read() + 1)`
```

**A temporary root.** The help says to bind the value first. There is no machine-applicable fix:

```
error[NotAPlace]: cannot assign to a temporary value
 --> cfg.bl:4:5
  |
4 |     mk().x = 5
  |     ^^^^ no name holds this value, so the store is lost
  |
  = help: bind it first: `let mut c = mk()`, then `c.x = 5`
```

**An immutable root.** `x = v`, `x op= v` and `s.f = v` on a plain `let` root, or on a pattern binder with no `mut` (§3.5 *Mutable Binders*), are E0610, the same error as a mutating method call on that root. The fix depends on how the root is declared (§3.2.2). An assignment inside a closure to a captured binding gets the same error. A label marks the capture, and the fix goes at the `let`:

```
error[MutationRequiresMut]: cannot assign to `total`, which is not `mut`
 --> sum.bl:4:9
  |
2 |     let total = 0
  |         ----- declared here
3 |     let add = fn(n: Int) {
4 |         total = total + n
  |         ^^^^^ captured here
  |
  = help: declare it `let mut total`
```

**Rollout.** NotAPlace (E0611) and E0610 on an assignment are errors from the first release that has them. None of these programs had a meaning under this section. The same holds for E0610 on a pattern binder and for MutOnPattern (E0613, §3.5). ParamAssign (E0612) keeps the rollout of §3.6 *Mutable Parameters*.

**Panel vote: 6-0** on each point: E0610 for an immutable root, NotAPlace for a `Ptr` step and a temporary root, a code for ParamAssign, the order of the four cases, the `Ptr` fix rules, help only for a module-level `let`, and errors at once. The `Ptr` fix rules passed 6-0 in a second round. See [decisions/assignment-place-diagnostics.md](../decisions/assignment-place-diagnostics.md).

### 2.23 Reserved Words

#### The Keyword Table

These words are **keywords**. The lexer reads each one as a keyword token in every position:

| Keyword | Note |
|---|---|
| `fn`, `let`, `mut`, `const`, `type`, `trait`, `impl`, `pub`, `import`, `as`, `self`, `effect`, `handler`, `with`, `test` | declarations, bindings and handlers |
| `if`, `else`, `match`, `for`, `in`, `while`, `loop`, `break`, `continue`, `return` | control flow |
| `assert`, `assert_eq`, `assert_ne`, `assert_panics` | built-in assertions (§2.20 *Built-in Assertions*) |
| `mod` | reserved, unused. Blink has no `mod name { }` block (§10.1.1 *No Inline Modules*). The parser keeps the word so that a `mod` block written from Rust habit gets a targeted error, not a parse error. |

`true` and `false` are literals of type `Bool` (§10.6). They are not names, and no position accepts them as a name.

`async` is **not** a keyword. It is an ordinary identifier, the namespace of `async.spawn` and `async.scope` (§4).

`opaque` is **not** a keyword. It is a contextual word: it has meaning only between `pub` and `type` (§2.12.2). In every other position it is an ordinary identifier.

This table is the one list of keywords. §10.6 and the `blink explain E1103` text refer to it. A CI test fails if the set of words in this table is not exactly the set the lexer reads as keywords.

#### Members and Bindings

**A keyword may name a member. A keyword may never name a binding.**

A **member name** is a name that a program reaches only through a type or a value: after `.`, or as a field label. These are the member-name positions, and the list is closed:

1. A field declaration in a `type` body: `handler: fn(Request) -> Response`.
2. A field label in a struct literal, written with `:`: `Route { handler: f }`.
3. The name after `.`: field access `r.handler`, method call `r.match(path)`, and a qualified name `m.x`.
4. A field label in a struct pattern, written with `:`: `Route { handler: h, .. }`.
5. A method name declared in an `impl` or `trait` body: `fn match(self, path: Str) -> Bool`. A caller reaches the method only through `.`.
6. The name after `T.` in a type-scoped declaration (§2.12.3): `const T.NAME` or `fn T.name`. A caller reaches it only through `T.`.

In grammar terms, each of these positions takes a `MEMBER_NAME`, and every other name position takes an `IDENT`:

```
MEMBER_NAME ::= IDENT | KEYWORD      // KEYWORD = any word in the table above
```

Every other position that takes a name is a **binding** position, and a keyword there is `error[KeywordAsIdentifier]` (E1103). The binding positions include:

- `let` and `for` names, and pattern bindings
- function and closure parameters
- keyword-parameter names (§2.13), and so call-site labels too. A label names a parameter, and a parameter is a local of the function body. A body can never refer to a local named `type`, so a call-site label `type:` can never match a parameter.
- top-level names: `fn`, `type`, `trait`, `effect`, `const` and module-level `let`
- operation names declared in an `effect` body. A handler and the effect's own module can call an operation by its bare name, so the name is not a member name.

```blink
@derive(Serialize, Deserialize)
type Event {
    type: Str
    id: Int
}

type Route {
    method: Str
    pattern: Str
    handler: fn(Request) -> Response
}

trait Matcher {
    fn match(self, path: Str) -> Bool
}

impl Matcher for Route {
    fn match(self, path: Str) -> Bool {
        path == self.pattern
    }
}

fn dispatch(r: Route, req: Request, fallback: Route) -> Response {
    let h = if r.match(req.path) { r.handler } else { fallback.handler }
    h(req)
}

fn kind(e: Event) -> Str {
    match e {
        Event { type: t, .. } => t
    }
}
```

`Event` derives `Serialize` with the JSON key `"type"`. Blink has no `@json("name")` field rename (see [JsonValue derive signatures](../decisions/json-value-derive-and-str-backed-enums.md)), so a derived type can model a JSON key only when the field can have the same name. This rule is what lets a field have the name of a keyword.

**Field punning cannot name a keyword field.** Punning `{ name }` in a struct pattern means `{ name: name }`, and the second `name` is a binding (§3.5). So the punned form is legal only when the field name is also a legal binding name:

```
error[KeywordAsIdentifier]: field `type` cannot use the short form because `type` is a keyword
  --> app.bl:22:17
   |
22 |         Event { type, .. } => type
   |                 ^^^^ the short form binds a local named `type`
   = help: write `type: <name>`, for example `Event { type: t, .. }`
```

The E1103 message names the position. At a binding it says that a keyword cannot name a variable or a parameter and that keywords are legal only as member names. At a call-site label it says that keywords cannot name parameters.

#### Soft Keywords

A **soft keyword** is a word that the parser reads as a keyword only in one position, and as an ordinary identifier everywhere else. In v1 there is one soft keyword: `final`, as a modifier on a default method in a trait body (§3.6 *The `final` Modifier*). An edition may promote a soft keyword to a keyword (§8.16.1 *Editions*).

The member-name rule above does **not** make any keyword soft. A keyword in a member-name position is still a keyword token. The positions accept it as a name, and the word stays reserved in every binding position. A keyword never becomes legal as a binding.

**Panel vote: 6-0** on each point: keywords as member names, method names included, labels and effect operations reserved, `mod` reserved with its reason, the soft-keyword definition, and the CI check against the lexer. See [decisions/keywords-as-member-names.md](../decisions/keywords-as-member-names.md).
