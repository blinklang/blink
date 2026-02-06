import pytest

import pact.lexer as lexer
import pact.tokens as tokens

TT = tokens.TokenType


def types(source: str) -> list[TT]:
    return [t.type for t in lexer.lex(source)]


def values(source: str) -> list[str]:
    return [t.value for t in lexer.lex(source)]


# --- Keywords ---

@pytest.mark.parametrize("keyword, expected", [
    ("fn", TT.FN),
    ("let", TT.LET),
    ("match", TT.MATCH),
    ("for", TT.FOR),
    ("in", TT.IN),
    ("type", TT.TYPE),
    ("trait", TT.TRAIT),
    ("impl", TT.IMPL),
    ("if", TT.IF),
    ("else", TT.ELSE),
    ("return", TT.RETURN),
    ("mut", TT.MUT),
    ("test", TT.TEST),
    ("pub", TT.PUB),
    ("with", TT.WITH),
    ("handler", TT.HANDLER),
    ("self", TT.SELF),
    ("assert", TT.ASSERT),
    ("assert_eq", TT.ASSERT_EQ),
])
def test_keywords(keyword, expected):
    toks = lexer.lex(keyword)
    assert toks[0].type == expected
    assert toks[0].value == keyword


def test_keyword_prefix_is_ident():
    assert types("letter") == [TT.IDENT, TT.EOF]
    assert types("format") == [TT.IDENT, TT.EOF]
    assert types("inner") == [TT.IDENT, TT.EOF]


# --- Operators ---

@pytest.mark.parametrize("src, expected_type", [
    ("=", TT.EQUALS),
    ("=>", TT.FAT_ARROW),
    ("->", TT.ARROW),
    ("??", TT.DOUBLE_QUESTION),
    ("..", TT.DOTDOT),
    (".", TT.DOT),
    ("%", TT.PERCENT),
    ("!", TT.BANG),
    (",", TT.COMMA),
    (":", TT.COLON),
    ("+", TT.PLUS),
    ("-", TT.MINUS),
    ("*", TT.STAR),
    ("/", TT.SLASH),
    ("==", TT.EQEQ),
    ("!=", TT.NOT_EQ),
    ("<", TT.LESS),
    (">", TT.GREATER),
    ("<=", TT.LESS_EQ),
    (">=", TT.GREATER_EQ),
    ("&&", TT.AND),
    ("||", TT.OR),
    ("?", TT.QUESTION),
])
def test_operators(src, expected_type):
    toks = lexer.lex(src)
    assert toks[0].type == expected_type
    assert toks[0].value == src


def test_equals_vs_fat_arrow():
    assert types("= =>") == [TT.EQUALS, TT.FAT_ARROW, TT.EOF]


def test_dot_vs_dotdot():
    assert types(". ..") == [TT.DOT, TT.DOTDOT, TT.EOF]


# --- Braces and Parens ---

def test_braces():
    assert types("{ }") == [TT.LBRACE, TT.RBRACE, TT.EOF]


def test_parens():
    assert types("( )") == [TT.LPAREN, TT.RPAREN, TT.EOF]


def test_nested_braces():
    assert types("{ { } }") == [TT.LBRACE, TT.LBRACE, TT.RBRACE, TT.RBRACE, TT.EOF]


def test_brackets():
    assert types("[ ]") == [TT.LBRACKET, TT.RBRACKET, TT.EOF]


def test_at():
    assert types("@") == [TT.AT, TT.EOF]


def test_generic_syntax():
    assert types("List[T]") == [TT.IDENT, TT.LBRACKET, TT.IDENT, TT.RBRACKET, TT.EOF]


# --- Int Literals ---

def test_int_literal():
    toks = lexer.lex("42")
    assert toks[0].type == TT.INT
    assert toks[0].value == "42"


def test_multi_digit_int():
    toks = lexer.lex("12345")
    assert toks[0].type == TT.INT
    assert toks[0].value == "12345"


def test_zero():
    toks = lexer.lex("0")
    assert toks[0].type == TT.INT
    assert toks[0].value == "0"


def test_int_followed_by_ident():
    assert types("42 x") == [TT.INT, TT.IDENT, TT.EOF]


# --- Float Literals ---

def test_float_literal():
    toks = lexer.lex("2.0")
    assert toks[0].type == TT.FLOAT
    assert toks[0].value == "2.0"


def test_float_pi():
    toks = lexer.lex("3.14")
    assert toks[0].type == TT.FLOAT
    assert toks[0].value == "3.14"


def test_int_dot_not_float():
    """42. followed by non-digit should be INT then DOT, not FLOAT."""
    assert types("42.foo") == [TT.INT, TT.DOT, TT.IDENT, TT.EOF]


# --- Plain String ---

def test_plain_string():
    assert types('"hello"') == [
        TT.STRING_START, TT.STRING_PART, TT.STRING_END, TT.EOF
    ]
    toks = lexer.lex('"hello"')
    assert toks[1].value == "hello"


def test_empty_string():
    assert types('""') == [
        TT.STRING_START, TT.STRING_PART, TT.STRING_END, TT.EOF
    ]
    toks = lexer.lex('""')
    assert toks[1].value == ""


# --- String Interpolation ---

def test_string_interpolation():
    toks = lexer.lex('"hi {name}"')
    tt = [t.type for t in toks]
    assert tt == [
        TT.STRING_START,
        TT.STRING_PART,    # "hi "
        TT.INTERP_START,
        TT.IDENT,          # name
        TT.INTERP_END,
        TT.STRING_PART,    # ""
        TT.STRING_END,
        TT.EOF,
    ]
    assert toks[1].value == "hi "
    assert toks[3].value == "name"
    assert toks[5].value == ""


def test_string_interpolation_at_start():
    toks = lexer.lex('"{x} done"')
    tt = [t.type for t in toks]
    assert tt == [
        TT.STRING_START,
        TT.STRING_PART,    # ""
        TT.INTERP_START,
        TT.IDENT,
        TT.INTERP_END,
        TT.STRING_PART,    # " done"
        TT.STRING_END,
        TT.EOF,
    ]
    assert toks[1].value == ""
    assert toks[5].value == " done"


def test_multiple_interpolations():
    toks = lexer.lex('"{a} and {b}"')
    tt = [t.type for t in toks]
    assert tt == [
        TT.STRING_START,
        TT.STRING_PART,    # ""
        TT.INTERP_START,
        TT.IDENT,          # a
        TT.INTERP_END,
        TT.STRING_PART,    # " and "
        TT.INTERP_START,
        TT.IDENT,          # b
        TT.INTERP_END,
        TT.STRING_PART,    # ""
        TT.STRING_END,
        TT.EOF,
    ]


# --- Comments ---

def test_comment_skipped():
    assert types("// ignored\nfn") == [TT.FN, TT.EOF]


def test_comment_only():
    assert types("// just a comment") == [TT.EOF]


def test_comment_after_code():
    assert types("fn // comment\nlet") == [TT.FN, TT.LET, TT.EOF]


def test_doc_comment_skipped():
    assert types("/// doc comment\nfn") == [TT.FN, TT.EOF]


def test_triple_slash_with_content_skipped():
    assert types("/// @requires x > 0\nfn") == [TT.FN, TT.EOF]


# --- Multi-char Operator Disambiguation ---

def test_eq_vs_eqeq_vs_fat_arrow():
    assert types("= == =>") == [TT.EQUALS, TT.EQEQ, TT.FAT_ARROW, TT.EOF]


def test_bang_vs_not_eq():
    assert types("! !=") == [TT.BANG, TT.NOT_EQ, TT.EOF]


def test_less_vs_less_eq():
    assert types("< <=") == [TT.LESS, TT.LESS_EQ, TT.EOF]


def test_greater_vs_greater_eq():
    assert types("> >=") == [TT.GREATER, TT.GREATER_EQ, TT.EOF]


def test_question_vs_double_question():
    assert types("? ??") == [TT.QUESTION, TT.DOUBLE_QUESTION, TT.EOF]


def test_minus_vs_arrow():
    assert types("- ->") == [TT.MINUS, TT.ARROW, TT.EOF]


def test_and_or():
    assert types("&& ||") == [TT.AND, TT.OR, TT.EOF]


# --- Newline Coalescing ---

def test_single_newline():
    assert types("fn\nlet") == [TT.FN, TT.NEWLINE, TT.LET, TT.EOF]


def test_multiple_newlines_coalesce():
    assert types("fn\n\n\nlet") == [TT.FN, TT.NEWLINE, TT.LET, TT.EOF]


def test_leading_newlines_emitted():
    assert types("\n\nfn") == [TT.NEWLINE, TT.FN, TT.EOF]


def test_trailing_newline():
    assert types("fn\n") == [TT.FN, TT.NEWLINE, TT.EOF]


def test_trailing_multiple_newlines():
    assert types("fn\n\n\n") == [TT.FN, TT.NEWLINE, TT.EOF]


# --- Line/Col Tracking ---

def test_line_col_first_token():
    toks = lexer.lex("fn")
    assert toks[0].line == 1
    assert toks[0].col == 1


def test_line_col_after_newline():
    toks = lexer.lex("fn\nlet")
    let_tok = [t for t in toks if t.type == TT.LET][0]
    assert let_tok.line == 2
    assert let_tok.col == 1


# --- Hello.pact Smoke Test ---

HELLO_PACT = """\
// hello.pact — Hello World + CLI arguments
//
// Demonstrates: fn main, io.println, string interpolation,
//               env.args(), ?? default operator

/// Greet someone by name.
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
    io.println("Welcome to Pact.")
}
"""


def test_hello_pact_smoke():
    toks = lexer.lex(HELLO_PACT)
    tt = [t.type for t in toks]

    assert tt[-1] == TT.EOF
    assert tt.count(TT.FN) == 2
    assert tt.count(TT.LET) == 1
    assert TT.DOUBLE_QUESTION in tt
    assert TT.BANG in tt
    assert TT.STRING_START in tt
    assert TT.INTERP_START in tt
    assert 40 < len(toks) < 120


def test_hello_pact_no_errors():
    lexer.lex(HELLO_PACT)


# --- Edge Cases ---

def test_unexpected_char_raises():
    with pytest.raises(SyntaxError):
        lexer.lex("~")


def test_identifier_with_underscore():
    toks = lexer.lex("_foo bar_baz")
    assert toks[0].type == TT.IDENT
    assert toks[0].value == "_foo"
    assert toks[1].type == TT.IDENT
    assert toks[1].value == "bar_baz"


def test_empty_source():
    assert types("") == [TT.EOF]


def test_whitespace_only():
    assert types("   \t  ") == [TT.EOF]


def test_combined_expression():
    assert types("fn foo(x: Int) -> Int") == [
        TT.FN, TT.IDENT, TT.LPAREN, TT.IDENT, TT.COLON, TT.IDENT,
        TT.RPAREN, TT.ARROW, TT.IDENT, TT.EOF,
    ]


# --- Example File Smoke Tests ---

import pathlib

EXAMPLES_DIR = pathlib.Path(__file__).parent.parent / "examples"

EXAMPLE_FILES = [
    "hello.pact",
    "fizzbuzz.pact",
    "todo.pact",
    "calculator.pact",
    "fetch.pact",
    "bank.pact",
    "web_api.pact",
]


@pytest.mark.parametrize("filename", EXAMPLE_FILES)
def test_example_file_lexes_without_error(filename):
    source = (EXAMPLES_DIR / filename).read_text()
    toks = lexer.lex(source)
    assert toks[-1].type == TT.EOF
    assert len(toks) > 5
