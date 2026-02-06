import pact.tokens as tokens

KEYWORDS = {
    "fn": tokens.TokenType.FN,
    "let": tokens.TokenType.LET,
    "match": tokens.TokenType.MATCH,
    "for": tokens.TokenType.FOR,
    "in": tokens.TokenType.IN,
    "type": tokens.TokenType.TYPE,
    "trait": tokens.TokenType.TRAIT,
    "impl": tokens.TokenType.IMPL,
    "if": tokens.TokenType.IF,
    "else": tokens.TokenType.ELSE,
    "return": tokens.TokenType.RETURN,
    "mut": tokens.TokenType.MUT,
    "test": tokens.TokenType.TEST,
    "pub": tokens.TokenType.PUB,
    "with": tokens.TokenType.WITH,
    "handler": tokens.TokenType.HANDLER,
    "self": tokens.TokenType.SELF,
    "assert": tokens.TokenType.ASSERT,
    "assert_eq": tokens.TokenType.ASSERT_EQ,
}

SINGLE_CHAR_TOKENS = {
    "(": tokens.TokenType.LPAREN,
    ")": tokens.TokenType.RPAREN,
    ":": tokens.TokenType.COLON,
    ",": tokens.TokenType.COMMA,
    "%": tokens.TokenType.PERCENT,
    "+": tokens.TokenType.PLUS,
    "-": tokens.TokenType.MINUS,
    "*": tokens.TokenType.STAR,
    "/": tokens.TokenType.SLASH,
    "[": tokens.TokenType.LBRACKET,
    "]": tokens.TokenType.RBRACKET,
    "@": tokens.TokenType.AT,
}


class Lexer:
    def __init__(self, source: str):
        self.source = source
        self.pos = 0
        self.line = 1
        self.col = 1
        self.result: list[tokens.Token] = []
        # Stack of modes. Each entry is either ("normal", brace_depth) or ("string", buffer)
        self.mode_stack: list[tuple] = [("normal", 0)]

    def peek(self, offset: int = 0) -> str:
        i = self.pos + offset
        if i >= len(self.source):
            return "\0"
        return self.source[i]

    def advance(self) -> str:
        ch = self.source[self.pos]
        self.pos += 1
        if ch == "\n":
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return ch

    def emit(self, typ: tokens.TokenType, value: str, line: int, col: int):
        self.result.append(tokens.Token(type=typ, value=value, line=line, col=col))

    def last_token_type(self) -> tokens.TokenType | None:
        if self.result:
            return self.result[-1].type
        return None

    def at_end(self) -> bool:
        return self.pos >= len(self.source)

    def current_mode(self) -> tuple:
        return self.mode_stack[-1]

    def scan_normal(self):
        mode_kind, brace_depth = self.current_mode()

        while not self.at_end():
            mode_kind, brace_depth = self.current_mode()
            if mode_kind != "normal":
                return

            ch = self.peek()

            if ch in " \t":
                self.advance()
                continue

            if ch == "/" and self.peek(1) == "/":
                self.advance()
                self.advance()
                while not self.at_end() and self.peek() != "\n":
                    self.advance()
                # consume the newline itself but don't emit NEWLINE
                if not self.at_end() and self.peek() == "\n":
                    self.advance()
                continue

            if ch == "\n":
                line, col = self.line, self.col
                self.advance()
                if self.last_token_type() != tokens.TokenType.NEWLINE:
                    self.emit(tokens.TokenType.NEWLINE, "\\n", line, col)
                continue

            if ch == '"':
                line, col = self.line, self.col
                self.advance()
                self.emit(tokens.TokenType.STRING_START, '"', line, col)
                self.mode_stack.append(("string", ""))
                self.scan_string()
                continue

            if ch == "{":
                line, col = self.line, self.col
                self.advance()
                if brace_depth > 0:
                    self.mode_stack[-1] = ("normal", brace_depth + 1)
                    self.emit(tokens.TokenType.LBRACE, "{", line, col)
                else:
                    self.emit(tokens.TokenType.LBRACE, "{", line, col)
                continue

            if ch == "}":
                line, col = self.line, self.col
                self.advance()
                if brace_depth > 1:
                    self.mode_stack[-1] = ("normal", brace_depth - 1)
                    self.emit(tokens.TokenType.RBRACE, "}", line, col)
                elif brace_depth == 1:
                    self.mode_stack.pop()
                    self.emit(tokens.TokenType.INTERP_END, "}", line, col)
                    self.scan_string()
                    return
                else:
                    self.emit(tokens.TokenType.RBRACE, "}", line, col)
                continue

            if ch == "?":
                line, col = self.line, self.col
                self.advance()
                if not self.at_end() and self.peek() == "?":
                    self.advance()
                    self.emit(tokens.TokenType.DOUBLE_QUESTION, "??", line, col)
                else:
                    self.emit(tokens.TokenType.QUESTION, "?", line, col)
                continue

            if ch == "-" and self.peek(1) == ">":
                line, col = self.line, self.col
                self.advance()
                self.advance()
                self.emit(tokens.TokenType.ARROW, "->", line, col)
                continue

            if ch == "=":
                line, col = self.line, self.col
                self.advance()
                if not self.at_end() and self.peek() == ">":
                    self.advance()
                    self.emit(tokens.TokenType.FAT_ARROW, "=>", line, col)
                elif not self.at_end() and self.peek() == "=":
                    self.advance()
                    self.emit(tokens.TokenType.EQEQ, "==", line, col)
                else:
                    self.emit(tokens.TokenType.EQUALS, "=", line, col)
                continue

            if ch == "." and self.peek(1) == ".":
                line, col = self.line, self.col
                self.advance()
                self.advance()
                self.emit(tokens.TokenType.DOTDOT, "..", line, col)
                continue

            if ch == ".":
                line, col = self.line, self.col
                self.advance()
                self.emit(tokens.TokenType.DOT, ".", line, col)
                continue

            if ch == "!":
                line, col = self.line, self.col
                self.advance()
                if not self.at_end() and self.peek() == "=":
                    self.advance()
                    self.emit(tokens.TokenType.NOT_EQ, "!=", line, col)
                else:
                    self.emit(tokens.TokenType.BANG, "!", line, col)
                continue

            if ch == "<":
                line, col = self.line, self.col
                self.advance()
                if not self.at_end() and self.peek() == "=":
                    self.advance()
                    self.emit(tokens.TokenType.LESS_EQ, "<=", line, col)
                else:
                    self.emit(tokens.TokenType.LESS, "<", line, col)
                continue

            if ch == ">":
                line, col = self.line, self.col
                self.advance()
                if not self.at_end() and self.peek() == "=":
                    self.advance()
                    self.emit(tokens.TokenType.GREATER_EQ, ">=", line, col)
                else:
                    self.emit(tokens.TokenType.GREATER, ">", line, col)
                continue

            if ch == "&" and self.peek(1) == "&":
                line, col = self.line, self.col
                self.advance()
                self.advance()
                self.emit(tokens.TokenType.AND, "&&", line, col)
                continue

            if ch == "|" and self.peek(1) == "|":
                line, col = self.line, self.col
                self.advance()
                self.advance()
                self.emit(tokens.TokenType.OR, "||", line, col)
                continue

            if ch in SINGLE_CHAR_TOKENS:
                line, col = self.line, self.col
                self.advance()
                self.emit(SINGLE_CHAR_TOKENS[ch], ch, line, col)
                continue

            if ch.isalpha() or ch == "_":
                line, col = self.line, self.col
                start = self.pos
                while not self.at_end() and (self.peek().isalnum() or self.peek() == "_"):
                    self.advance()
                word = self.source[start:self.pos]
                if word in KEYWORDS:
                    self.emit(KEYWORDS[word], word, line, col)
                else:
                    self.emit(tokens.TokenType.IDENT, word, line, col)
                continue

            if ch.isdigit():
                line, col = self.line, self.col
                start = self.pos
                while not self.at_end() and self.peek().isdigit():
                    self.advance()
                if not self.at_end() and self.peek() == "." and self.peek(1).isdigit():
                    self.advance()
                    while not self.at_end() and self.peek().isdigit():
                        self.advance()
                    self.emit(tokens.TokenType.FLOAT, self.source[start:self.pos], line, col)
                else:
                    self.emit(tokens.TokenType.INT, self.source[start:self.pos], line, col)
                continue

            raise SyntaxError(
                f"unexpected character {ch!r} at line {self.line}, col {self.col}"
            )

    def scan_string(self):
        mode_kind, buf = self.current_mode()

        while not self.at_end():
            mode_kind, buf = self.current_mode()
            if mode_kind != "string":
                return

            ch = self.peek()

            if ch == "{":
                line, col = self.line, self.col
                self.advance()
                self.emit(tokens.TokenType.STRING_PART, buf, line, col)
                self.mode_stack[-1] = ("string", "")
                self.emit(tokens.TokenType.INTERP_START, "{", line, col)
                self.mode_stack.append(("normal", 1))
                self.scan_normal()
                continue

            if ch == '"':
                line, col = self.line, self.col
                self.advance()
                self.emit(tokens.TokenType.STRING_PART, buf, line, col)
                self.mode_stack[-1] = ("string", "")
                self.emit(tokens.TokenType.STRING_END, '"', line, col)
                self.mode_stack.pop()
                return

            if ch == "\\":
                self.advance()
                if self.at_end():
                    raise SyntaxError("unexpected end of string after backslash")
                esc = self.advance()
                ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "{": "{"}
                self.mode_stack[-1] = ("string", buf + ESCAPES.get(esc, "\\" + esc))
                continue

            self.advance()
            self.mode_stack[-1] = ("string", buf + ch)

    def tokenize(self) -> list[tokens.Token]:
        self.scan_normal()
        self.emit(tokens.TokenType.EOF, "", self.line, self.col)
        return self.result


def lex(source: str) -> list[tokens.Token]:
    return Lexer(source).tokenize()
