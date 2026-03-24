import tokens
import std.str

effect Lex {
    effect Tokenize
}

// lexer.pact — Self-hosting lexer for Blink, ported from Python
//
// Demonstrates: parallel arrays (workaround for no struct-in-list),
//               char_at / ASCII arithmetic, string interpolation scanning,
//               mode-stack-based string/normal interleaving.
//
// Constraints: C backend cannot store structs in List, so token output
// is 4 parallel lists (kinds, values, lines, cols). Mode stack is also
// parallel lists instead of tuples.

// ── Mode constants ───────────────────────────────────────────────────
let MODE_NORMAL = 0
let MODE_STRING = 1

// ── ASCII constants ──────────────────────────────────────────────────
let CH_TAB = 9
let CH_NEWLINE = 10
let CH_SPACE = 32
let CH_DQUOTE = 34
let CH_PERCENT = 37
let CH_LPAREN = 40
let CH_RPAREN = 41
let CH_STAR = 42
let CH_PLUS = 43
let CH_COMMA = 44
let CH_MINUS = 45
let CH_DOT = 46
let CH_SLASH = 47
let CH_0 = 48
let CH_9 = 57
let CH_COLON = 58
let CH_LESS = 60
let CH_EQUALS = 61
let CH_GREATER = 62
let CH_QUESTION = 63
let CH_AT = 64
let CH_A = 65
let CH_Z = 90
let CH_LBRACKET = 91
let CH_BACKSLASH = 92
let CH_RBRACKET = 93
let CH_UNDERSCORE = 95
let CH_a = 97
let CH_b = 98
let CH_f = 102
let CH_n = 110
let CH_r = 114
let CH_t = 116
let CH_Z_LOWER = 122
let CH_LBRACE = 123
let CH_PIPE = 124
let CH_RBRACE = 125
let CH_BANG = 33
let CH_HASH = 35
let CH_AMP = 38

// ── Character classification ─────────────────────────────────────────

fn is_alpha(c: Int) -> Int {
    (c >= CH_A && c <= CH_Z) || (c >= CH_a && c <= CH_Z_LOWER) || c == CH_UNDERSCORE
}

fn is_digit(c: Int) -> Int {
    c >= CH_0 && c <= CH_9
}

fn is_alnum(c: Int) -> Int {
    is_alpha(c) || is_digit(c)
}

fn is_whitespace(c: Int) -> Int {
    c == CH_SPACE || c == CH_TAB
}

// ── Peek helpers ─────────────────────────────────────────────────────

fn peek(source: Str, scan_pos: Int) -> Int {
    if scan_pos >= source.len() {
        0
    } else {
        source.char_at(scan_pos)
    }
}

fn peek_at(source: Str, scan_pos: Int, offset: Int) -> Int {
    peek(source, scan_pos + offset)
}

// ── Lexer output: module-level globals ────────────────────────────────
// Shared with parser and codegen via imports.

pub let mut tok_kinds: List[TokenKind] = []
pub let mut tok_values: List[Str] = []
pub let mut tok_lines: List[Int] = []
pub let mut tok_cols: List[Int] = []

// ── Main lexer ───────────────────────────────────────────────────────

pub fn lex(source: Str) ! Lex.Tokenize {
    if trace_mode != "" { trace("lex", "start ({source.len()} chars)") }
    // Reset output arrays
    tok_kinds.clear()
    tok_values.clear()
    tok_lines.clear()
    tok_cols.clear()

    // Scanner state
    let mut scan_pos = 0
    let mut line = 1
    let mut col = 1

    // Mode stack (parallel lists). Starts with one normal-mode entry.
    let mut mode_stack: List[Int] = []
    let mut brace_depth_stack: List[Int] = []
    let mut string_depth_stack: List[Int] = []
    mode_stack.push(MODE_NORMAL)
    brace_depth_stack.push(0)

    // String buffer for MODE_STRING
    let mut string_buf = StringBuilder.new()
    let mut _run_start = -1

    // Last emitted token kind (-1 means none)
    let mut _last_kind: TokenKind = -1

    // ── emit: push a token to all 4 output lists ──────────────────
    // Inlined as a block since we can't capture mut locals in closures.
    // We use a helper pattern: just push inline everywhere.
    // (Ugly, but the C backend doesn't support closures that capture.)

    // ── Main loop ─────────────────────────────────────────────────
    while scan_pos < source.len() {
        let mode = mode_stack.get(mode_stack.len() - 1).unwrap()

        if mode == MODE_NORMAL {
            // ── NORMAL MODE ───────────────────────────────────────
            let brace_depth = brace_depth_stack.get(brace_depth_stack.len() - 1).unwrap()
            let ch = peek(source, scan_pos)

            // Skip whitespace (not newline)
            if is_whitespace(ch) {
                scan_pos = scan_pos + 1
                col = col + 1
                continue
            }

            // Comments: // or ///
            if ch == CH_SLASH && peek_at(source, scan_pos, 1) == CH_SLASH {
                let t_line = line
                let t_col = col
                let is_doc = peek_at(source, scan_pos, 2) == CH_SLASH
                if is_doc {
                    scan_pos = scan_pos + 3
                    col = col + 3
                } else {
                    scan_pos = scan_pos + 2
                    col = col + 2
                }
                let text_start = scan_pos
                while scan_pos < source.len() && peek(source, scan_pos) != CH_NEWLINE {
                    scan_pos = scan_pos + 1
                    col = col + 1
                }
                let text = source.substring(text_start, scan_pos - text_start)
                if is_doc {
                    tok_kinds.push(TokenKind.DocComment)
                    tok_values.push(text)
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.DocComment
                } else {
                    tok_kinds.push(TokenKind.Comment)
                    tok_values.push(text)
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Comment
                }
                if scan_pos < source.len() && peek(source, scan_pos) == CH_NEWLINE {
                    scan_pos = scan_pos + 1
                    line = line + 1
                    col = 1
                }
                continue
            }

            // Slash or /=
            if ch == CH_SLASH {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.SlashEq)
                    tok_values.push("/=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.SlashEq
                } else {
                    tok_kinds.push(TokenKind.Slash)
                    tok_values.push("/")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Slash
                }
                continue
            }

            // Newline
            if ch == CH_NEWLINE {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                line = line + 1
                col = 1
                if _last_kind != TokenKind.Newline {
                    tok_kinds.push(TokenKind.Newline)
                    tok_values.push("\\n")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Newline
                }
                continue
            }

            // String start: "
            if ch == CH_DQUOTE {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.StringStart)
                tok_values.push("\"")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.StringStart
                mode_stack.push(MODE_STRING)
                brace_depth_stack.push(0)
                string_depth_stack.push(0)
                string_buf.clear()
                continue
            }

            // Left brace
            if ch == CH_LBRACE {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if brace_depth > 0 {
                    // Inside interpolation: track nested braces
                    brace_depth_stack.push(brace_depth + 1)
                    mode_stack.push(MODE_NORMAL)
                    // Replace top of stack by popping and re-pushing
                    // Actually we need to update the current entry.
                    // Since List has no set(), we pop and push.
                    // We just pushed, so undo and fix the original entry.
                    // Simpler: the brace_depth_stack top IS the one we
                    // just pushed. Pop it, pop the old, push updated old,
                    // then we don't push a new mode frame — we update in place.
                    //
                    // Let me reconsider the stack design:
                    // In Python, mode_stack[-1] = ("normal", brace_depth+1)
                    // means we UPDATE the current frame, not push a new one.
                    // So we should pop the extra push we just did, and update
                    // the existing top.
                    mode_stack.pop()
                    brace_depth_stack.pop()
                    // Now update the real top
                    brace_depth_stack.pop()
                    brace_depth_stack.push(brace_depth + 1)
                    tok_kinds.push(TokenKind.LBrace)
                    tok_values.push("\{")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.LBrace
                } else {
                    tok_kinds.push(TokenKind.LBrace)
                    tok_values.push("\{")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.LBrace
                }
                continue
            }

            // Right brace
            if ch == CH_RBRACE {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if brace_depth > 1 {
                    // Nested brace inside interpolation
                    brace_depth_stack.pop()
                    brace_depth_stack.push(brace_depth - 1)
                    tok_kinds.push(TokenKind.RBrace)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.RBrace
                } else if brace_depth == 1 {
                    // End of interpolation — pop back to string mode
                    mode_stack.pop()
                    brace_depth_stack.pop()
                    tok_kinds.push(TokenKind.InterpEnd)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.InterpEnd
                    // Continue in string mode (loop will pick it up)
                } else {
                    tok_kinds.push(TokenKind.RBrace)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.RBrace
                }
                continue
            }

            // Question mark: ? or ??
            if ch == CH_QUESTION {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_QUESTION {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.DoubleQuestion)
                    tok_values.push("??")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.DoubleQuestion
                } else {
                    tok_kinds.push(TokenKind.Question)
                    tok_values.push("?")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Question
                }
                continue
            }

            // Minus: -, ->, -=, --
            if ch == CH_MINUS {
                let t_line = line
                let t_col = col
                if peek_at(source, scan_pos, 1) == CH_GREATER {
                    scan_pos = scan_pos + 2
                    col = col + 2
                    tok_kinds.push(TokenKind.Arrow)
                    tok_values.push("->")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Arrow
                } else if peek_at(source, scan_pos, 1) == CH_EQUALS {
                    scan_pos = scan_pos + 2
                    col = col + 2
                    tok_kinds.push(TokenKind.MinusEq)
                    tok_values.push("-=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.MinusEq
                } else if peek_at(source, scan_pos, 1) == CH_MINUS {
                    scan_pos = scan_pos + 2
                    col = col + 2
                    tok_kinds.push(TokenKind.DashDash)
                    tok_values.push("--")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.DashDash
                } else {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.Minus)
                    tok_values.push("-")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Minus
                }
                continue
            }

            // Plus: +, +=
            if ch == CH_PLUS {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.PlusEq)
                    tok_values.push("+=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.PlusEq
                } else {
                    tok_kinds.push(TokenKind.Plus)
                    tok_values.push("+")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Plus
                }
                continue
            }

            // Star: *, *=
            if ch == CH_STAR {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.StarEq)
                    tok_values.push("*=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.StarEq
                } else {
                    tok_kinds.push(TokenKind.Star)
                    tok_values.push("*")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Star
                }
                continue
            }

            // Equals: =, ==, =>
            if ch == CH_EQUALS {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_GREATER {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.FatArrow)
                    tok_values.push("=>")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.FatArrow
                } else if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.EqEq)
                    tok_values.push("==")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.EqEq
                } else {
                    tok_kinds.push(TokenKind.Equals)
                    tok_values.push("=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Equals
                }
                continue
            }

            // Dot: ., .., ..=
            if ch == CH_DOT && peek_at(source, scan_pos, 1) == CH_DOT {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 2
                col = col + 2
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.DotDoteq)
                    tok_values.push("..=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.DotDoteq
                } else {
                    tok_kinds.push(TokenKind.DotDot)
                    tok_values.push("..")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.DotDot
                }
                continue
            }

            if ch == CH_DOT {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Dot)
                tok_values.push(".")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.Dot
                continue
            }

            // Bang: !, !=
            if ch == CH_BANG {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.NotEq)
                    tok_values.push("!=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.NotEq
                } else {
                    tok_kinds.push(TokenKind.Bang)
                    tok_values.push("!")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Bang
                }
                continue
            }

            // Less: <, <=
            if ch == CH_LESS {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.LessEq)
                    tok_values.push("<=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.LessEq
                } else {
                    tok_kinds.push(TokenKind.Less)
                    tok_values.push("<")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Less
                }
                continue
            }

            // Greater: >, >=
            if ch == CH_GREATER {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_EQUALS {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.GreaterEq)
                    tok_values.push(">=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.GreaterEq
                } else {
                    tok_kinds.push(TokenKind.Greater)
                    tok_values.push(">")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Greater
                }
                continue
            }

            // Ampersand: &&
            if ch == CH_AMP && peek_at(source, scan_pos, 1) == CH_AMP {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 2
                col = col + 2
                tok_kinds.push(TokenKind.And)
                tok_values.push("&&")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.And
                continue
            }

            // Pipe: |, ||, |>
            if ch == CH_PIPE {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos < source.len() && peek(source, scan_pos) == CH_PIPE {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.Or)
                    tok_values.push("||")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Or
                } else if scan_pos < source.len() && peek(source, scan_pos) == CH_GREATER {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.PipeArrow)
                    tok_values.push("|>")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.PipeArrow
                } else {
                    tok_kinds.push(TokenKind.Pipe)
                    tok_values.push("|")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Pipe
                }
                continue
            }

            // Single-char tokens: ( ) : , % [ ] @
            if ch == CH_LPAREN {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.LParen)
                tok_values.push("(")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.LParen
                continue
            }
            if ch == CH_RPAREN {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.RParen)
                tok_values.push(")")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.RParen
                continue
            }
            if ch == CH_COLON {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Colon)
                tok_values.push(":")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.Colon
                continue
            }
            if ch == CH_COMMA {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Comma)
                tok_values.push(",")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.Comma
                continue
            }
            if ch == CH_PERCENT {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Percent)
                tok_values.push("%")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.Percent
                continue
            }
            if ch == CH_LBRACKET {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.LBracket)
                tok_values.push("[")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.LBracket
                continue
            }
            if ch == CH_RBRACKET {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.RBracket)
                tok_values.push("]")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.RBracket
                continue
            }
            if ch == CH_AT {
                let t_line = line
                let t_col = col
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.At)
                tok_values.push("@")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.At
                continue
            }
            if ch == CH_HASH {
                let t_line = line
                let t_col = col
                // Count consecutive # chars
                let mut hash_count = 0
                while scan_pos + hash_count < source.len() && peek(source, scan_pos + hash_count) == CH_HASH {
                    hash_count = hash_count + 1
                }
                // Check if followed by " — extended string start
                if hash_count <= 3 && scan_pos + hash_count < source.len() && peek(source, scan_pos + hash_count) == CH_DQUOTE {
                    // Extended string: consume all # chars + the "
                    scan_pos = scan_pos + hash_count + 1
                    col = col + hash_count + 1
                    tok_kinds.push(TokenKind.StringStart)
                    tok_values.push("\"")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.StringStart
                    mode_stack.push(MODE_STRING)
                    brace_depth_stack.push(0)
                    string_depth_stack.push(hash_count)
                    string_buf.clear()
                    continue
                }
                // Not an extended string — emit Hash token (just one #)
                scan_pos = scan_pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Hash)
                tok_values.push("#")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = TokenKind.Hash
                continue
            }

            // Identifiers and keywords
            if is_alpha(ch) {
                let t_line = line
                let t_col = col
                let start = scan_pos
                while scan_pos < source.len() && is_alnum(peek(source, scan_pos)) {
                    scan_pos = scan_pos + 1
                    col = col + 1
                }
                let word = source.substring(start, scan_pos - start)
                let kind = keyword_lookup(word)
                tok_kinds.push(kind)
                tok_values.push(word)
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                _last_kind = kind
                continue
            }

            // Integer and float literals
            if is_digit(ch) {
                let t_line = line
                let t_col = col
                let start = scan_pos
                while scan_pos < source.len() && is_digit(peek(source, scan_pos)) {
                    scan_pos = scan_pos + 1
                    col = col + 1
                }
                if scan_pos < source.len() && peek(source, scan_pos) == CH_DOT && is_digit(peek_at(source, scan_pos, 1)) {
                    scan_pos = scan_pos + 1
                    col = col + 1
                    while scan_pos < source.len() && is_digit(peek(source, scan_pos)) {
                        scan_pos = scan_pos + 1
                        col = col + 1
                    }
                    tok_kinds.push(TokenKind.Float)
                    tok_values.push(source.substring(start, scan_pos - start))
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Float
                } else {
                    tok_kinds.push(TokenKind.Int)
                    tok_values.push(source.substring(start, scan_pos - start))
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.Int
                }
                continue
            }

            // Unknown character — skip with a warning
            // (No exceptions in the C backend)
            io.println("lexer error: unexpected character at line {line} col {col}")
            scan_pos = scan_pos + 1
            col = col + 1

        } else {
            // ── STRING MODE ───────────────────────────────────────
            let ch = peek(source, scan_pos)

            // Interpolation start: { (or #{...} for extended strings)
            if ch == CH_LBRACE {
                if _run_start != -1 {
                    string_buf.write(source.substring(_run_start, scan_pos - _run_start))
                    _run_start = -1
                }
                let t_line = line
                let t_col = col
                let sdepth = string_depth_stack.get(string_depth_stack.len() - 1).unwrap()
                if sdepth == 0 {
                    // Normal string: { starts interpolation
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.StringPart)
                    tok_values.push(string_buf.to_str())
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.StringPart
                    string_buf.clear()
                    tok_kinds.push(TokenKind.InterpStart)
                    tok_values.push("\{")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.InterpStart
                    mode_stack.push(MODE_NORMAL)
                    brace_depth_stack.push(1)
                    continue
                } else {
                    // Extended string: check if last sdepth chars in string_buf are all #
                    let buf_str = string_buf.to_str()
                    let buf_len = buf_str.len()
                    if buf_len >= sdepth {
                        let mut all_hash = 1
                        let mut ci = 0
                        while ci < sdepth {
                            if buf_str.char_at(buf_len - sdepth + ci) != CH_HASH {
                                all_hash = 0
                                break
                            }
                            ci = ci + 1
                        }
                        if all_hash == 1 {
                            // Remove trailing # chars from string_buf
                            let trimmed = buf_str.substring(0, buf_len - sdepth)
                            scan_pos = scan_pos + 1
                            col = col + 1
                            tok_kinds.push(TokenKind.StringPart)
                            tok_values.push(trimmed)
                            tok_lines.push(t_line)
                            tok_cols.push(t_col)
                            _last_kind = TokenKind.StringPart
                            string_buf.clear()
                            tok_kinds.push(TokenKind.InterpStart)
                            tok_values.push("\{")
                            tok_lines.push(t_line)
                            tok_cols.push(t_col)
                            _last_kind = TokenKind.InterpStart
                            mode_stack.push(MODE_NORMAL)
                            brace_depth_stack.push(1)
                            continue
                        }
                    }
                    // Not enough # before { — literal brace
                    string_buf.write("\{")
                    scan_pos = scan_pos + 1
                    col = col + 1
                    continue
                }
            }

            // String end: " (or "# / "## / "### for extended strings)
            if ch == CH_DQUOTE {
                if _run_start != -1 {
                    string_buf.write(source.substring(_run_start, scan_pos - _run_start))
                    _run_start = -1
                }
                let t_line = line
                let t_col = col
                let sdepth = string_depth_stack.get(string_depth_stack.len() - 1).unwrap()
                if sdepth == 0 {
                    // Normal string end
                    scan_pos = scan_pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.StringPart)
                    tok_values.push(string_buf.to_str())
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.StringPart
                    string_buf.clear()
                    tok_kinds.push(TokenKind.StringEnd)
                    tok_values.push("\"")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    _last_kind = TokenKind.StringEnd
                    mode_stack.pop()
                    brace_depth_stack.pop()
                    string_depth_stack.pop()
                    continue
                } else {
                    // Extended string: check for exactly sdepth # chars after "
                    let mut match_count = 0
                    while match_count < sdepth && scan_pos + 1 + match_count < source.len() && peek(source, scan_pos + 1 + match_count) == CH_HASH {
                        match_count = match_count + 1
                    }
                    let after_hashes = scan_pos + 1 + match_count
                    let next_is_brace = after_hashes < source.len() && peek(source, after_hashes) == CH_LBRACE
                    if match_count == sdepth && next_is_brace == false {
                        // End of extended string: consume " + all # chars
                        scan_pos = scan_pos + 1 + sdepth
                        col = col + 1 + sdepth
                        tok_kinds.push(TokenKind.StringPart)
                        tok_values.push(string_buf.to_str())
                        tok_lines.push(t_line)
                        tok_cols.push(t_col)
                        _last_kind = TokenKind.StringPart
                        string_buf.clear()
                        tok_kinds.push(TokenKind.StringEnd)
                        tok_values.push("\"")
                        tok_lines.push(t_line)
                        tok_cols.push(t_col)
                        _last_kind = TokenKind.StringEnd
                        mode_stack.pop()
                        brace_depth_stack.pop()
                        string_depth_stack.pop()
                        continue
                    } else {
                        // Not enough # — literal "
                        string_buf.write("\"")
                        scan_pos = scan_pos + 1
                        col = col + 1
                        continue
                    }
                }
            }

            // Escape sequences
            if ch == CH_BACKSLASH {
                if _run_start != -1 {
                    string_buf.write(source.substring(_run_start, scan_pos - _run_start))
                    _run_start = -1
                }
                let sdepth = string_depth_stack.get(string_depth_stack.len() - 1).unwrap()
                if sdepth > 0 {
                    // Extended string: backslash is literal
                    string_buf.write("\\")
                    scan_pos = scan_pos + 1
                    col = col + 1
                    continue
                }
                scan_pos = scan_pos + 1
                col = col + 1
                if scan_pos >= source.len() {
                    io.println("lexer error: unexpected end of string after backslash")
                    continue
                }
                let esc = peek(source, scan_pos)
                scan_pos = scan_pos + 1
                col = col + 1
                if esc == CH_n {
                    string_buf.write("\n")
                } else if esc == CH_r {
                    string_buf.write("\r")
                } else if esc == CH_t {
                    string_buf.write("\t")
                } else if esc == CH_BACKSLASH {
                    string_buf.write("\\")
                } else if esc == CH_b {
                    string_buf.write(Char.from_code_point(8))
                } else if esc == CH_f {
                    string_buf.write(Char.from_code_point(12))
                } else if esc == CH_DQUOTE {
                    string_buf.write("\"")
                } else if esc == CH_LBRACE {
                    string_buf.write("\{")
                } else if esc == CH_RBRACE {
                    string_buf.write("}")
                } else {
                    let esc_ch = source.substring(scan_pos - 1, 1)
                    io.eprintln("warning: unknown escape sequence '\\{esc_ch}' at line {line} col {col - 2}")
                    string_buf.write("\\")
                }
                continue
            }

            // Regular character — track run start for batch append
            if _run_start == -1 {
                _run_start = scan_pos
            }
            scan_pos = scan_pos + 1
            if ch == CH_NEWLINE {
                line = line + 1
                col = 1
            } else {
                col = col + 1
            }
        }
    }

    // Emit EOF
    tok_kinds.push(TokenKind.EOF)
    tok_values.push("")
    tok_lines.push(line)
    tok_cols.push(col)
    if trace_mode != "" { trace("lex", "done ({tok_kinds.len()} tokens)") }
}
