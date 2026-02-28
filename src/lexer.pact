import tokens

effect Lex {
    effect Tokenize
}

// lexer.pact — Self-hosting lexer for Pact, ported from Python
//
// Demonstrates: parallel arrays (workaround for no struct-in-list),
//               char_at / ASCII arithmetic, string interpolation scanning,
//               mode-stack-based string/normal interleaving.
//
// Constraints: C backend cannot store structs in List, so token output
// is 4 parallel lists (kinds, values, lines, cols). Mode stack is also
// parallel lists instead of tuples.

// ── Mode constants ───────────────────────────────────────────────────
pub let MODE_NORMAL = 0
pub let MODE_STRING = 1

// ── ASCII constants ──────────────────────────────────────────────────
pub let CH_TAB = 9
pub let CH_NEWLINE = 10
pub let CH_SPACE = 32
pub let CH_DQUOTE = 34
pub let CH_PERCENT = 37
pub let CH_LPAREN = 40
pub let CH_RPAREN = 41
pub let CH_STAR = 42
pub let CH_PLUS = 43
pub let CH_COMMA = 44
pub let CH_MINUS = 45
pub let CH_DOT = 46
pub let CH_SLASH = 47
pub let CH_0 = 48
pub let CH_9 = 57
pub let CH_COLON = 58
pub let CH_LESS = 60
pub let CH_EQUALS = 61
pub let CH_GREATER = 62
pub let CH_QUESTION = 63
pub let CH_AT = 64
pub let CH_A = 65
pub let CH_Z = 90
pub let CH_LBRACKET = 91
pub let CH_BACKSLASH = 92
pub let CH_RBRACKET = 93
pub let CH_UNDERSCORE = 95
pub let CH_a = 97
pub let CH_b = 98
pub let CH_f = 102
pub let CH_n = 110
pub let CH_r = 114
pub let CH_t = 116
pub let CH_Z_LOWER = 122
pub let CH_LBRACE = 123
pub let CH_PIPE = 124
pub let CH_RBRACE = 125
pub let CH_BANG = 33
pub let CH_HASH = 35
pub let CH_AMP = 38

// ── Character classification ─────────────────────────────────────────

pub fn is_alpha(c: Int) -> Int {
    (c >= CH_A && c <= CH_Z) || (c >= CH_a && c <= CH_Z_LOWER) || c == CH_UNDERSCORE
}

pub fn is_digit(c: Int) -> Int {
    c >= CH_0 && c <= CH_9
}

pub fn is_alnum(c: Int) -> Int {
    is_alpha(c) || is_digit(c)
}

pub fn is_whitespace(c: Int) -> Int {
    c == CH_SPACE || c == CH_TAB
}

// ── Peek helpers ─────────────────────────────────────────────────────

pub fn peek(source: Str, pos: Int) -> Int {
    if pos >= source.len() {
        0
    } else {
        source.char_at(pos)
    }
}

pub fn peek_at(source: Str, pos: Int, offset: Int) -> Int {
    peek(source, pos + offset)
}

// ── Lexer output: module-level globals ────────────────────────────────
// Shared with parser and codegen via imports.

pub let mut tok_kinds: List[Int] = []
pub let mut tok_values: List[Str] = []
pub let mut tok_lines: List[Int] = []
pub let mut tok_cols: List[Int] = []

// ── Main lexer ───────────────────────────────────────────────────────

pub fn lex(source: Str) ! Lex.Tokenize {
    // Reset output arrays
    tok_kinds = []
    tok_values = []
    tok_lines = []
    tok_cols = []

    // Scanner state
    let mut pos = 0
    let mut line = 1
    let mut col = 1

    // Mode stack (parallel lists). Starts with one normal-mode entry.
    let mut mode_stack: List[Int] = []
    let mut brace_depth_stack: List[Int] = []
    mode_stack.push(MODE_NORMAL)
    brace_depth_stack.push(0)

    // String buffer for MODE_STRING
    let mut string_buf: Str = ""

    // Last emitted token kind (-1 means none)
    let mut last_kind = -1

    // ── emit: push a token to all 4 output lists ──────────────────
    // Inlined as a block since we can't capture mut locals in closures.
    // We use a helper pattern: just push inline everywhere.
    // (Ugly, but the C backend doesn't support closures that capture.)

    // ── Main loop ─────────────────────────────────────────────────
    while pos < source.len() {
        let mode = mode_stack.get(mode_stack.len() - 1).unwrap()

        if mode == MODE_NORMAL {
            // ── NORMAL MODE ───────────────────────────────────────
            let brace_depth = brace_depth_stack.get(brace_depth_stack.len() - 1).unwrap()
            let ch = peek(source, pos)

            // Skip whitespace (not newline)
            if is_whitespace(ch) {
                pos = pos + 1
                col = col + 1
                continue
            }

            // Comments: // or ///
            if ch == CH_SLASH && peek_at(source, pos, 1) == CH_SLASH {
                let t_line = line
                let t_col = col
                let is_doc = peek_at(source, pos, 2) == CH_SLASH
                if is_doc {
                    pos = pos + 3
                    col = col + 3
                } else {
                    pos = pos + 2
                    col = col + 2
                }
                let text_start = pos
                while pos < source.len() && peek(source, pos) != CH_NEWLINE {
                    pos = pos + 1
                    col = col + 1
                }
                let text = source.substring(text_start, pos - text_start)
                if is_doc {
                    tok_kinds.push(TokenKind.DocComment)
                    tok_values.push(text)
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.DocComment
                } else {
                    tok_kinds.push(TokenKind.Comment)
                    tok_values.push(text)
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Comment
                }
                if pos < source.len() && peek(source, pos) == CH_NEWLINE {
                    pos = pos + 1
                    line = line + 1
                    col = 1
                }
                continue
            }

            // Slash or /=
            if ch == CH_SLASH {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.SlashEq)
                    tok_values.push("/=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.SlashEq
                } else {
                    tok_kinds.push(TokenKind.Slash)
                    tok_values.push("/")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Slash
                }
                continue
            }

            // Newline
            if ch == CH_NEWLINE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                line = line + 1
                col = 1
                if last_kind != TokenKind.Newline {
                    tok_kinds.push(TokenKind.Newline)
                    tok_values.push("\\n")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Newline
                }
                continue
            }

            // String start: "
            if ch == CH_DQUOTE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.StringStart)
                tok_values.push("\"")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.StringStart
                mode_stack.push(MODE_STRING)
                brace_depth_stack.push(0)
                string_buf = ""
                continue
            }

            // Left brace
            if ch == CH_LBRACE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if brace_depth > 0 {
                    // Inside interpolation: track nested braces
                    brace_depth_stack.push(brace_depth + 1)
                    mode_stack.push(MODE_NORMAL)
                    // Replace top of stack by popping and re-pushing
                    // Actually we need to update the current entry.
                    // Since List has no set(), we pop and push.
                    let mlen = mode_stack.len()
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
                    last_kind = TokenKind.LBrace
                } else {
                    tok_kinds.push(TokenKind.LBrace)
                    tok_values.push("\{")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.LBrace
                }
                continue
            }

            // Right brace
            if ch == CH_RBRACE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if brace_depth > 1 {
                    // Nested brace inside interpolation
                    brace_depth_stack.pop()
                    brace_depth_stack.push(brace_depth - 1)
                    tok_kinds.push(TokenKind.RBrace)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.RBrace
                } else if brace_depth == 1 {
                    // End of interpolation — pop back to string mode
                    mode_stack.pop()
                    brace_depth_stack.pop()
                    tok_kinds.push(TokenKind.InterpEnd)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.InterpEnd
                    // Continue in string mode (loop will pick it up)
                } else {
                    tok_kinds.push(TokenKind.RBrace)
                    tok_values.push("\}")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.RBrace
                }
                continue
            }

            // Question mark: ? or ??
            if ch == CH_QUESTION {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_QUESTION {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.DoubleQuestion)
                    tok_values.push("??")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.DoubleQuestion
                } else {
                    tok_kinds.push(TokenKind.Question)
                    tok_values.push("?")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Question
                }
                continue
            }

            // Minus: -, ->, -=
            if ch == CH_MINUS {
                let t_line = line
                let t_col = col
                if peek_at(source, pos, 1) == CH_GREATER {
                    pos = pos + 2
                    col = col + 2
                    tok_kinds.push(TokenKind.Arrow)
                    tok_values.push("->")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Arrow
                } else if peek_at(source, pos, 1) == CH_EQUALS {
                    pos = pos + 2
                    col = col + 2
                    tok_kinds.push(TokenKind.MinusEq)
                    tok_values.push("-=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.MinusEq
                } else {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.Minus)
                    tok_values.push("-")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Minus
                }
                continue
            }

            // Plus: +, +=
            if ch == CH_PLUS {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.PlusEq)
                    tok_values.push("+=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.PlusEq
                } else {
                    tok_kinds.push(TokenKind.Plus)
                    tok_values.push("+")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Plus
                }
                continue
            }

            // Star: *, *=
            if ch == CH_STAR {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.StarEq)
                    tok_values.push("*=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.StarEq
                } else {
                    tok_kinds.push(TokenKind.Star)
                    tok_values.push("*")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Star
                }
                continue
            }

            // Equals: =, ==, =>
            if ch == CH_EQUALS {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_GREATER {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.FatArrow)
                    tok_values.push("=>")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.FatArrow
                } else if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.EqEq)
                    tok_values.push("==")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.EqEq
                } else {
                    tok_kinds.push(TokenKind.Equals)
                    tok_values.push("=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Equals
                }
                continue
            }

            // Dot: ., .., ..=
            if ch == CH_DOT && peek_at(source, pos, 1) == CH_DOT {
                let t_line = line
                let t_col = col
                pos = pos + 2
                col = col + 2
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.DotDoteq)
                    tok_values.push("..=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.DotDoteq
                } else {
                    tok_kinds.push(TokenKind.DotDot)
                    tok_values.push("..")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.DotDot
                }
                continue
            }

            if ch == CH_DOT {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Dot)
                tok_values.push(".")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.Dot
                continue
            }

            // Bang: !, !=
            if ch == CH_BANG {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.NotEq)
                    tok_values.push("!=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.NotEq
                } else {
                    tok_kinds.push(TokenKind.Bang)
                    tok_values.push("!")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Bang
                }
                continue
            }

            // Less: <, <=
            if ch == CH_LESS {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.LessEq)
                    tok_values.push("<=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.LessEq
                } else {
                    tok_kinds.push(TokenKind.Less)
                    tok_values.push("<")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Less
                }
                continue
            }

            // Greater: >, >=
            if ch == CH_GREATER {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_EQUALS {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.GreaterEq)
                    tok_values.push(">=")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.GreaterEq
                } else {
                    tok_kinds.push(TokenKind.Greater)
                    tok_values.push(">")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Greater
                }
                continue
            }

            // Ampersand: &&
            if ch == CH_AMP && peek_at(source, pos, 1) == CH_AMP {
                let t_line = line
                let t_col = col
                pos = pos + 2
                col = col + 2
                tok_kinds.push(TokenKind.And)
                tok_values.push("&&")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.And
                continue
            }

            // Pipe: |, ||, |>
            if ch == CH_PIPE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                if pos < source.len() && peek(source, pos) == CH_PIPE {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.Or)
                    tok_values.push("||")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Or
                } else if pos < source.len() && peek(source, pos) == CH_GREATER {
                    pos = pos + 1
                    col = col + 1
                    tok_kinds.push(TokenKind.PipeArrow)
                    tok_values.push("|>")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.PipeArrow
                } else {
                    tok_kinds.push(TokenKind.Pipe)
                    tok_values.push("|")
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Pipe
                }
                continue
            }

            // Single-char tokens: ( ) : , % [ ] @
            if ch == CH_LPAREN {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.LParen)
                tok_values.push("(")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.LParen
                continue
            }
            if ch == CH_RPAREN {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.RParen)
                tok_values.push(")")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.RParen
                continue
            }
            if ch == CH_COLON {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Colon)
                tok_values.push(":")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.Colon
                continue
            }
            if ch == CH_COMMA {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Comma)
                tok_values.push(",")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.Comma
                continue
            }
            if ch == CH_PERCENT {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Percent)
                tok_values.push("%")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.Percent
                continue
            }
            if ch == CH_LBRACKET {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.LBracket)
                tok_values.push("[")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.LBracket
                continue
            }
            if ch == CH_RBRACKET {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.RBracket)
                tok_values.push("]")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.RBracket
                continue
            }
            if ch == CH_AT {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.At)
                tok_values.push("@")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.At
                continue
            }
            if ch == CH_HASH {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.Hash)
                tok_values.push("#")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.Hash
                continue
            }

            // Identifiers and keywords
            if is_alpha(ch) {
                let t_line = line
                let t_col = col
                let start = pos
                while pos < source.len() && is_alnum(peek(source, pos)) {
                    pos = pos + 1
                    col = col + 1
                }
                let word = source.substring(start, pos - start)
                let kind = keyword_lookup(word)
                tok_kinds.push(kind)
                tok_values.push(word)
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = kind
                continue
            }

            // Integer and float literals
            if is_digit(ch) {
                let t_line = line
                let t_col = col
                let start = pos
                while pos < source.len() && is_digit(peek(source, pos)) {
                    pos = pos + 1
                    col = col + 1
                }
                if pos < source.len() && peek(source, pos) == CH_DOT && is_digit(peek_at(source, pos, 1)) {
                    pos = pos + 1
                    col = col + 1
                    while pos < source.len() && is_digit(peek(source, pos)) {
                        pos = pos + 1
                        col = col + 1
                    }
                    tok_kinds.push(TokenKind.Float)
                    tok_values.push(source.substring(start, pos - start))
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Float
                } else {
                    tok_kinds.push(TokenKind.Int)
                    tok_values.push(source.substring(start, pos - start))
                    tok_lines.push(t_line)
                    tok_cols.push(t_col)
                    last_kind = TokenKind.Int
                }
                continue
            }

            // Unknown character — skip with a warning
            // (No exceptions in the C backend)
            io.println("lexer error: unexpected character at line {line} col {col}")
            pos = pos + 1
            col = col + 1

        } else {
            // ── STRING MODE ───────────────────────────────────────
            let ch = peek(source, pos)

            // Interpolation start: {
            if ch == CH_LBRACE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.StringPart)
                tok_values.push(string_buf)
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.StringPart
                string_buf = ""
                tok_kinds.push(TokenKind.InterpStart)
                tok_values.push("\{")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.InterpStart
                mode_stack.push(MODE_NORMAL)
                brace_depth_stack.push(1)
                continue
            }

            // String end: "
            if ch == CH_DQUOTE {
                let t_line = line
                let t_col = col
                pos = pos + 1
                col = col + 1
                tok_kinds.push(TokenKind.StringPart)
                tok_values.push(string_buf)
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.StringPart
                string_buf = ""
                tok_kinds.push(TokenKind.StringEnd)
                tok_values.push("\"")
                tok_lines.push(t_line)
                tok_cols.push(t_col)
                last_kind = TokenKind.StringEnd
                mode_stack.pop()
                brace_depth_stack.pop()
                continue
            }

            // Escape sequences
            if ch == CH_BACKSLASH {
                pos = pos + 1
                col = col + 1
                if pos >= source.len() {
                    io.println("lexer error: unexpected end of string after backslash")
                    continue
                }
                let esc = peek(source, pos)
                pos = pos + 1
                col = col + 1
                if esc == CH_n {
                    string_buf = string_buf.concat("\n")
                } else if esc == CH_r {
                    string_buf = string_buf.concat("\r")
                } else if esc == CH_t {
                    string_buf = string_buf.concat("\t")
                } else if esc == CH_BACKSLASH {
                    string_buf = string_buf.concat("\\")
                } else if esc == CH_b {
                    string_buf = string_buf.concat(Char.from_code_point(8))
                } else if esc == CH_f {
                    string_buf = string_buf.concat(Char.from_code_point(12))
                } else if esc == CH_DQUOTE {
                    string_buf = string_buf.concat("\"")
                } else if esc == CH_LBRACE {
                    string_buf = string_buf.concat("\{")
                } else if esc == CH_RBRACE {
                    string_buf = string_buf.concat("}")
                } else {
                    let esc_ch = source.substring(pos - 1, 1)
                    io.eprintln("warning: unknown escape sequence '\\{esc_ch}' at line {line} col {col - 2}")
                    string_buf = string_buf.concat("\\")
                }
                continue
            }

            // Regular character — append to buffer
            // char_at returns int; substring(pos, 1) gets the char as string
            string_buf = string_buf.concat(source.substring(pos, 1))
            pos = pos + 1
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
}
