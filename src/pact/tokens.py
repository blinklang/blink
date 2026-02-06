import enum
import dataclasses


class TokenType(enum.Enum):
    FN = "fn"
    LET = "let"
    IDENT = "IDENT"
    INT = "INT"
    FLOAT = "FLOAT"
    STRING_START = "STRING_START"
    STRING_END = "STRING_END"
    STRING_PART = "STRING_PART"
    INTERP_START = "INTERP_START"
    INTERP_END = "INTERP_END"
    LPAREN = "("
    RPAREN = ")"
    LBRACE = "{"
    RBRACE = "}"
    COLON = ":"
    BANG = "!"
    EQUALS = "="
    DOUBLE_QUESTION = "??"
    DOT = "."
    COMMA = ","
    ARROW = "->"
    MATCH = "match"
    FOR = "for"
    IN = "in"
    PERCENT = "%"
    FAT_ARROW = "=>"
    DOTDOT = ".."
    NEWLINE = "NEWLINE"
    EOF = "EOF"

    # Keywords (Phase 1a)
    TYPE = "type"
    TRAIT = "trait"
    IMPL = "impl"
    IF = "if"
    ELSE = "else"
    RETURN = "return"
    MUT = "mut"
    TEST = "test"
    PUB = "pub"
    WITH = "with"
    HANDLER = "handler"
    SELF = "self"
    ASSERT = "assert"
    ASSERT_EQ = "assert_eq"

    # Operators (Phase 1a)
    PLUS = "+"
    MINUS = "-"
    STAR = "*"
    SLASH = "/"
    EQEQ = "=="
    NOT_EQ = "!="
    LESS = "<"
    GREATER = ">"
    LESS_EQ = "<="
    GREATER_EQ = ">="
    AND = "&&"
    OR = "||"
    QUESTION = "?"

    # Punctuation (Phase 1a)
    LBRACKET = "["
    RBRACKET = "]"
    AT = "@"


@dataclasses.dataclass
class Token:
    type: TokenType
    value: str
    line: int
    col: int
