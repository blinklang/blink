// tokens.pact — Token type definitions for the self-hosting compiler
//
// Tagged-int approach: no enums in the C backend yet, so token kinds
// are plain Int constants. Ugly but bootstrappable.

// -- Keywords --
pub type TokenKind {
    Fn, Let, Mut, Const, Type, Trait, Impl, If, Else,
    Match, For, In, While, Loop, Break, Continue, Return,
    Pub, With, Handler, Self, Test, Import, As, Mod, Effect,
    Assert, AssertEq, AssertNe, Ident, Int, Float, StringStart, StringEnd,
    StringPart, InterpStart, InterpEnd, LParen, RParen, LBrace, RBrace, LBracket,
    RBracket, Colon, Comma, Dot, DotDot, DotDoteq, Arrow, FatArrow,
    At, Hash, Plus, Minus, Star, Slash, Percent, Equals, EqEq,
    NotEq, Less, Greater, LessEq, GreaterEq, And, Or, Bang,
    Question, DoubleQuestion, Pipe, PipeArrow, PlusEq, MinusEq, StarEq, SlashEq,
    DashDash,
    Newline, EOF,
    Comment, DocComment,
}

// -- Assertions --

// -- Literals and identifiers --

// -- String interpolation tokens --

// -- Delimiters --

// -- Punctuation --

// -- Operators --

// -- Compound assignment --

// -- Structural --

pub type Token {
    kind: Int
    value: Str
    line: Int
    col: Int
}

// Helper: create a token
fn make_token(kind: Int, value: Str, line: Int, col: Int) -> Token {
    Token { kind: kind, value: value, line: line, col: col }
}

// Helper: human-readable name for a token kind (for error messages)
fn token_kind_name(kind: TokenKind) -> Str {
    match kind {
        TokenKind.Fn => "fn"
        TokenKind.Let => "let"
        TokenKind.Mut => "mut"
        TokenKind.Const => "const"
        TokenKind.Type => "type"
        TokenKind.Trait => "trait"
        TokenKind.Impl => "impl"
        TokenKind.If => "if"
        TokenKind.Else => "else"
        TokenKind.Match => "match"
        TokenKind.For => "for"
        TokenKind.In => "in"
        TokenKind.While => "while"
        TokenKind.Loop => "loop"
        TokenKind.Break => "break"
        TokenKind.Continue => "continue"
        TokenKind.Return => "return"
        TokenKind.Pub => "pub"
        TokenKind.With => "with"
        TokenKind.Handler => "handler"
        TokenKind.Self => "self"
        TokenKind.Test => "test"
        TokenKind.Import => "import"
        TokenKind.As => "as"
        TokenKind.Mod => "mod"
        TokenKind.Effect => "effect"
        TokenKind.Assert => "assert"
        TokenKind.AssertEq => "assert_eq"
        TokenKind.AssertNe => "assert_ne"
        TokenKind.Ident => "IDENT"
        TokenKind.Int => "INT"
        TokenKind.Float => "FLOAT"
        TokenKind.StringStart => "STRING_START"
        TokenKind.StringEnd => "STRING_END"
        TokenKind.StringPart => "STRING_PART"
        TokenKind.InterpStart => "INTERP_START"
        TokenKind.InterpEnd => "INTERP_END"
        TokenKind.LParen => "("
        TokenKind.RParen => ")"
        TokenKind.LBrace => "\{"
        TokenKind.RBrace => "\}"
        TokenKind.LBracket => "["
        TokenKind.RBracket => "]"
        TokenKind.Colon => ":"
        TokenKind.Comma => ","
        TokenKind.Dot => "."
        TokenKind.DotDot => ".."
        TokenKind.DotDoteq => "..="
        TokenKind.Arrow => "->"
        TokenKind.FatArrow => "=>"
        TokenKind.At => "@"
        TokenKind.Hash => "#"
        TokenKind.Plus => "+"
        TokenKind.Minus => "-"
        TokenKind.Star => "*"
        TokenKind.Slash => "/"
        TokenKind.Percent => "%"
        TokenKind.Equals => "="
        TokenKind.EqEq => "=="
        TokenKind.NotEq => "!="
        TokenKind.Less => "<"
        TokenKind.Greater => ">"
        TokenKind.LessEq => "<="
        TokenKind.GreaterEq => ">="
        TokenKind.And => "&&"
        TokenKind.Or => "||"
        TokenKind.Bang => "!"
        TokenKind.Question => "?"
        TokenKind.DoubleQuestion => "??"
        TokenKind.Pipe => "|"
        TokenKind.PipeArrow => "|>"
        TokenKind.PlusEq => "+="
        TokenKind.MinusEq => "-="
        TokenKind.StarEq => "*="
        TokenKind.SlashEq => "/="
        TokenKind.DashDash => "--"
        TokenKind.Newline => "NEWLINE"
        TokenKind.EOF => "EOF"
        TokenKind.Comment => "COMMENT"
        TokenKind.DocComment => "DOC_COMMENT"
        _ => "UNKNOWN"
    }
}

// Helper: check if a token kind is a keyword
pub fn is_keyword(kind: TokenKind) -> Int {
    kind >= TokenKind.Fn && kind <= TokenKind.Effect
}

// Helper: look up a keyword from its string value, returns TokenKind.Ident if not a keyword
pub fn keyword_lookup(name: Str) -> TokenKind {
    match name {
        "fn" => TokenKind.Fn
        "let" => TokenKind.Let
        "mut" => TokenKind.Mut
        "const" => TokenKind.Const
        "type" => TokenKind.Type
        "trait" => TokenKind.Trait
        "impl" => TokenKind.Impl
        "if" => TokenKind.If
        "else" => TokenKind.Else
        "match" => TokenKind.Match
        "for" => TokenKind.For
        "in" => TokenKind.In
        "while" => TokenKind.While
        "loop" => TokenKind.Loop
        "break" => TokenKind.Break
        "continue" => TokenKind.Continue
        "return" => TokenKind.Return
        "pub" => TokenKind.Pub
        "with" => TokenKind.With
        "handler" => TokenKind.Handler
        "self" => TokenKind.Self
        "test" => TokenKind.Test
        "import" => TokenKind.Import
        "as" => TokenKind.As
        "mod" => TokenKind.Mod
        "effect" => TokenKind.Effect
        "assert" => TokenKind.Assert
        "assert_eq" => TokenKind.AssertEq
        "assert_ne" => TokenKind.AssertNe
        _ => TokenKind.Ident
    }
}
