import pathlib

import pytest

import pact.lexer as lexer
import pact.parser as parser
import pact.ast_nodes as ast

EXAMPLES_DIR = pathlib.Path(__file__).parent.parent / "examples"


def parse_src(source):
    return parser.parse(lexer.lex(source))


def test_fn_no_params():
    prog = parse_src('fn foo() { io.println("hi")\n}')
    assert len(prog.functions) == 1
    fn = prog.functions[0]
    assert fn.name == "foo"
    assert fn.params == []
    assert len(fn.body.stmts) == 1


def test_fn_with_typed_param():
    prog = parse_src('fn greet(name: Str) { io.println(name)\n}')
    fn = prog.functions[0]
    assert fn.params == [ast.Param("name", "Str")]


def test_fn_with_return_type():
    prog = parse_src('fn add(a: Int, b: Int) -> Int { a\n}')
    fn = prog.functions[0]
    assert fn.name == "add"
    assert fn.params == [ast.Param("a", "Int"), ast.Param("b", "Int")]
    assert isinstance(fn.body, ast.Block)


def test_fn_with_effects():
    prog = parse_src('fn greet(name: Str) ! IO { io.println(name)\n}')
    fn = prog.functions[0]
    assert fn.name == "greet"
    assert fn.params == [ast.Param("name", "Str")]
    assert len(fn.body.stmts) == 1


def test_let_binding():
    prog = parse_src('fn main() { let x = 42\n}')
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.LetBinding)
    assert stmt.name == "x"
    assert stmt.value == ast.IntLit(42)


def test_expr_stmt():
    prog = parse_src('fn main() { io.println("hi")\n}')
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.ExprStmt)
    assert isinstance(stmt.expr, ast.MethodCall)


def test_int_lit():
    prog = parse_src('fn main() { 42\n}')
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.ExprStmt)
    assert stmt.expr == ast.IntLit(42)


def test_interp_string():
    prog = parse_src('fn main() { "hello {name}"\n}')
    stmt = prog.functions[0].body.stmts[0]
    s = stmt.expr
    assert isinstance(s, ast.InterpString)
    assert s.parts[0] == "hello "
    assert s.parts[1] == ast.Ident("name")
    assert s.parts[2] == ""


def test_tuple_lit():
    prog = parse_src('fn main() { (1, 2, 3)\n}')
    stmt = prog.functions[0].body.stmts[0]
    t = stmt.expr
    assert isinstance(t, ast.TupleLit)
    assert t.elements == [ast.IntLit(1), ast.IntLit(2), ast.IntLit(3)]


def test_range_lit():
    prog = parse_src('fn main() { 1..10\n}')
    stmt = prog.functions[0].body.stmts[0]
    r = stmt.expr
    assert isinstance(r, ast.RangeLit)
    assert r.start == ast.IntLit(1)
    assert r.end == ast.IntLit(10)


def test_call():
    prog = parse_src('fn main() { foo(1, 2)\n}')
    stmt = prog.functions[0].body.stmts[0]
    c = stmt.expr
    assert isinstance(c, ast.Call)
    assert c.func == ast.Ident("foo")
    assert c.args == [ast.IntLit(1), ast.IntLit(2)]


def test_method_call():
    prog = parse_src('fn main() { io.println("hi")\n}')
    stmt = prog.functions[0].body.stmts[0]
    mc = stmt.expr
    assert isinstance(mc, ast.MethodCall)
    assert mc.obj == ast.Ident("io")
    assert mc.method == "println"
    assert len(mc.args) == 1
    assert isinstance(mc.args[0], ast.InterpString)


def test_binop_modulo():
    prog = parse_src('fn main() { n % 3\n}')
    stmt = prog.functions[0].body.stmts[0]
    b = stmt.expr
    assert isinstance(b, ast.BinOp)
    assert b.op == "%"
    assert b.left == ast.Ident("n")
    assert b.right == ast.IntLit(3)


def test_binop_double_question():
    prog = parse_src('fn main() { x ?? "default"\n}')
    stmt = prog.functions[0].body.stmts[0]
    b = stmt.expr
    assert isinstance(b, ast.BinOp)
    assert b.op == "??"
    assert b.left == ast.Ident("x")
    assert isinstance(b.right, ast.InterpString)


def test_match_expr():
    src = """fn main() {
    match (n % 3, n % 5) {
        (0, 0) => "FizzBuzz"
        (0, _) => "Fizz"
        (_, 0) => "Buzz"
        _ => "{n}"
    }
}"""
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    m = stmt.expr
    assert isinstance(m, ast.MatchExpr)
    assert isinstance(m.scrutinee, ast.TupleLit)
    assert len(m.arms) == 4

    assert m.arms[0].pattern == ast.TuplePattern([ast.IntPattern(0), ast.IntPattern(0)])
    assert isinstance(m.arms[0].body, ast.InterpString)

    assert m.arms[1].pattern == ast.TuplePattern([ast.IntPattern(0), ast.WildcardPattern()])

    assert m.arms[2].pattern == ast.TuplePattern([ast.WildcardPattern(), ast.IntPattern(0)])

    assert isinstance(m.arms[3].pattern, ast.WildcardPattern)
    assert isinstance(m.arms[3].body, ast.InterpString)


def test_for_in():
    src = """fn main() {
    for n in 1..101 {
        io.println(n)
    }
}"""
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.ForIn)
    assert stmt.var_name == "n"
    assert isinstance(stmt.iterable, ast.RangeLit)
    assert stmt.iterable.start == ast.IntLit(1)
    assert stmt.iterable.end == ast.IntLit(101)
    assert len(stmt.body.stmts) == 1


def test_full_hello():
    src = """\
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
    io.println("Welcome to Pact.")
}
"""
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)
    assert len(prog.functions) == 2
    assert prog.functions[0].name == "greet"
    assert prog.functions[1].name == "main"
    assert len(prog.functions[1].body.stmts) == 3


def test_full_fizzbuzz():
    src = """\
fn fizzbuzz(n: Int) -> Str {
    match (n % 3, n % 5) {
        (0, 0) => "FizzBuzz"
        (0, _) => "Fizz"
        (_, 0) => "Buzz"
        _ => "{n}"
    }
}

fn main() {
    for n in 1..101 {
        io.println(fizzbuzz(n))
    }
}
"""
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)
    assert len(prog.functions) == 2
    assert prog.functions[0].name == "fizzbuzz"
    assert prog.functions[1].name == "main"

    match_stmt = prog.functions[0].body.stmts[0]
    assert isinstance(match_stmt, ast.ExprStmt)
    assert isinstance(match_stmt.expr, ast.MatchExpr)
    assert len(match_stmt.expr.arms) == 4

    for_stmt = prog.functions[1].body.stmts[0]
    assert isinstance(for_stmt, ast.ForIn)


# --- Type system ---

def test_type_def_struct():
    prog = parse_src("type Foo {\n    x: Int\n    y: Str\n}")
    td = prog.types[0]
    assert isinstance(td, ast.TypeDef)
    assert td.name == "Foo"
    assert len(td.fields) == 2
    assert td.fields[0] == ast.TypeField("x", ast.TypeAnnotation("Int", []))
    assert td.fields[1] == ast.TypeField("y", ast.TypeAnnotation("Str", []))
    assert td.variants == []


def test_type_def_enum():
    prog = parse_src("type Status {\n    Open\n    Done\n}")
    td = prog.types[0]
    assert td.name == "Status"
    assert td.fields == []
    assert len(td.variants) == 2
    assert td.variants[0] == ast.TypeVariant("Open", [])
    assert td.variants[1] == ast.TypeVariant("Done", [])


def test_type_def_enum_with_data():
    prog = parse_src("type Err {\n    NotFound(id: Int)\n}")
    td = prog.types[0]
    assert len(td.variants) == 1
    v = td.variants[0]
    assert v.name == "NotFound"
    assert len(v.fields) == 1
    assert v.fields[0] == ast.TypeField("id", ast.TypeAnnotation("Int", []))


def test_type_alias_with_where():
    prog = parse_src("type NonZero = Int @where(self != 0)")
    td = prog.types[0]
    assert td.name == "NonZero"
    assert td.fields == []
    assert td.variants == []
    assert len(td.annotations) == 1
    assert td.annotations[0].name == "where"


# --- Trait / Impl / Test ---

def test_trait_def():
    src = "trait Display {\n    fn display(self) -> Str\n}"
    prog = parse_src(src)
    tr = prog.traits[0]
    assert isinstance(tr, ast.TraitDef)
    assert tr.name == "Display"
    assert len(tr.methods) == 1
    assert tr.methods[0].name == "display"
    assert tr.methods[0].params == [ast.Param("self")]


def test_impl_block():
    src = """impl Display for Foo {
    fn display(self) -> Str {
        "foo"
    }
}"""
    prog = parse_src(src)
    impl = prog.impls[0]
    assert isinstance(impl, ast.ImplBlock)
    assert impl.trait_name == "Display"
    assert impl.type_name == "Foo"
    assert len(impl.methods) == 1
    assert impl.methods[0].name == "display"


def test_test_block():
    src = 'test "it works" {\n    assert(true)\n}'
    prog = parse_src(src)
    tb = prog.tests[0]
    assert isinstance(tb, ast.TestBlock)
    assert tb.name == "it works"
    assert len(tb.body.stmts) == 1


# --- Annotations ---

def test_annotation_no_args():
    prog = parse_src("@deprecated\nfn foo() {\n    42\n}")
    fn = prog.functions[0]
    assert len(fn.annotations) == 1
    assert fn.annotations[0] == ast.Annotation("deprecated", [])


def test_annotation_with_args():
    prog = parse_src("@requires(x > 0)\nfn foo(x: Int) {\n    x\n}")
    fn = prog.functions[0]
    assert len(fn.annotations) == 1
    ann = fn.annotations[0]
    assert ann.name == "requires"
    assert len(ann.args) > 0


def test_multiple_annotations():
    prog = parse_src("@requires(x > 0)\n@ensures(result > 0)\nfn foo(x: Int) {\n    x\n}")
    fn = prog.functions[0]
    assert len(fn.annotations) == 2
    assert fn.annotations[0].name == "requires"
    assert fn.annotations[1].name == "ensures"


def test_annotation_capabilities():
    prog = parse_src("@capabilities(DB.Read, IO)\ntype Foo {\n    x: Int\n}")
    td = prog.types[0]
    assert len(td.annotations) == 1
    assert td.annotations[0].name == "capabilities"


# --- Expressions ---

def test_if_expr():
    src = "fn main() {\n    if x > 0 { x\n } else { -x\n }\n}"
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.IfExpr)
    assert isinstance(stmt.condition, ast.BinOp)
    assert isinstance(stmt.then_body, ast.Block)
    assert isinstance(stmt.else_body, ast.Block)


def test_if_no_else():
    src = "fn main() {\n    if x > 0 { x\n }\n}"
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.IfExpr)
    assert stmt.else_body is None


def test_return_expr():
    src = "fn main() {\n    return x\n}"
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.ReturnExpr)
    assert stmt.value == ast.Ident("x")


def test_return_bare():
    src = "fn main() {\n    return\n}"
    prog = parse_src(src)
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.ReturnExpr)
    assert stmt.value is None


def test_list_lit():
    prog = parse_src("fn main() { [1, 2, 3]\n}")
    stmt = prog.functions[0].body.stmts[0]
    ll = stmt.expr
    assert isinstance(ll, ast.ListLit)
    assert ll.elements == [ast.IntLit(1), ast.IntLit(2), ast.IntLit(3)]


def test_struct_lit():
    prog = parse_src("fn main() { Foo { x: 1, y: 2 }\n}")
    stmt = prog.functions[0].body.stmts[0]
    sl = stmt.expr
    assert isinstance(sl, ast.StructLit)
    assert sl.type_name == "Foo"
    assert len(sl.fields) == 2
    assert sl.fields[0] == ast.StructLitField("x", ast.IntLit(1))
    assert sl.fields[1] == ast.StructLitField("y", ast.IntLit(2))


def test_field_access():
    prog = parse_src("fn main() { foo.bar\n}")
    stmt = prog.functions[0].body.stmts[0]
    fa = stmt.expr
    assert isinstance(fa, ast.FieldAccess)
    assert fa.obj == ast.Ident("foo")
    assert fa.field == "bar"


def test_float_lit():
    prog = parse_src("fn main() { 3.14\n}")
    stmt = prog.functions[0].body.stmts[0]
    assert stmt.expr == ast.FloatLit(3.14)


def test_bool_lit():
    prog = parse_src("fn main() { true\n}")
    stmt = prog.functions[0].body.stmts[0]
    assert stmt.expr == ast.BoolLit(True)

    prog2 = parse_src("fn main() { false\n}")
    stmt2 = prog2.functions[0].body.stmts[0]
    assert stmt2.expr == ast.BoolLit(False)


def test_unary_neg():
    prog = parse_src("fn main() { -x\n}")
    stmt = prog.functions[0].body.stmts[0]
    u = stmt.expr
    assert isinstance(u, ast.UnaryOp)
    assert u.op == "-"
    assert u.operand == ast.Ident("x")


def test_unary_not():
    prog = parse_src("fn main() { !done\n}")
    stmt = prog.functions[0].body.stmts[0]
    u = stmt.expr
    assert isinstance(u, ast.UnaryOp)
    assert u.op == "!"
    assert u.operand == ast.Ident("done")


def test_unary_question():
    prog = parse_src("fn main() { x?\n}")
    stmt = prog.functions[0].body.stmts[0]
    u = stmt.expr
    assert isinstance(u, ast.UnaryOp)
    assert u.op == "?"
    assert u.operand == ast.Ident("x")


def test_assignment():
    prog = parse_src("fn main() { x = 42\n}")
    stmt = prog.functions[0].body.stmts[0]
    assert isinstance(stmt, ast.Assignment)
    assert stmt.target == ast.Ident("x")
    assert stmt.value == ast.IntLit(42)


def test_closure():
    prog = parse_src("fn main() { fn(x) { x + 1\n }\n}")
    stmt = prog.functions[0].body.stmts[0]
    c = stmt.expr
    assert isinstance(c, ast.Closure)
    assert c.params == [ast.Param("x")]
    assert len(c.body.stmts) == 1


# --- Patterns ---

def test_enum_pattern():
    src = """fn main() {
    match x {
        Some(v) => v
        None => 0
    }
}"""
    prog = parse_src(src)
    m = prog.functions[0].body.stmts[0].expr
    assert isinstance(m, ast.MatchExpr)
    assert isinstance(m.arms[0].pattern, ast.EnumPattern)
    assert m.arms[0].pattern.variant == "Some"
    assert len(m.arms[0].pattern.fields) == 1
    assert isinstance(m.arms[1].pattern, ast.IdentPattern)
    assert m.arms[1].pattern.name == "None"


def test_qualified_enum_pattern():
    src = """fn main() {
    match x {
        Err.NotFound(id) => id
        _ => 0
    }
}"""
    prog = parse_src(src)
    m = prog.functions[0].body.stmts[0].expr
    p = m.arms[0].pattern
    assert isinstance(p, ast.EnumPattern)
    assert p.variant == "Err.NotFound"
    assert len(p.fields) == 1


# --- Precedence ---

def test_precedence_mul_over_add():
    prog = parse_src("fn main() { a + b * c\n}")
    e = prog.functions[0].body.stmts[0].expr
    assert isinstance(e, ast.BinOp)
    assert e.op == "+"
    assert e.left == ast.Ident("a")
    assert isinstance(e.right, ast.BinOp)
    assert e.right.op == "*"


def test_precedence_comparison():
    prog = parse_src("fn main() { a > b && c < d\n}")
    e = prog.functions[0].body.stmts[0].expr
    assert isinstance(e, ast.BinOp)
    assert e.op == "&&"
    assert isinstance(e.left, ast.BinOp)
    assert e.left.op == ">"
    assert isinstance(e.right, ast.BinOp)
    assert e.right.op == "<"


def test_precedence_or_and():
    prog = parse_src("fn main() { a || b && c\n}")
    e = prog.functions[0].body.stmts[0].expr
    assert isinstance(e, ast.BinOp)
    assert e.op == "||"
    assert e.left == ast.Ident("a")
    assert isinstance(e.right, ast.BinOp)
    assert e.right.op == "&&"


# --- Type annotations ---

def test_generic_type_annotation():
    prog = parse_src("fn foo(x: List[Int]) {\n    x\n}")
    fn = prog.functions[0]
    assert fn.params[0].name == "x"
    assert fn.params[0].type_name == "List"


def test_tuple_type_annotation():
    prog = parse_src("fn foo() -> (Int, Str) {\n    (1, \"hi\")\n}")
    fn = prog.functions[0]
    assert fn.return_type is not None
    assert isinstance(fn.return_type, ast.TypeAnnotation)
    assert fn.return_type.name == "Tuple"
    assert len(fn.return_type.params) == 2


# --- Smoke tests (parse all example files) ---

def test_smoke_hello():
    src = (EXAMPLES_DIR / "hello.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


def test_smoke_fizzbuzz():
    src = (EXAMPLES_DIR / "fizzbuzz.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


def test_smoke_todo():
    src = (EXAMPLES_DIR / "todo.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


def test_smoke_calculator():
    src = (EXAMPLES_DIR / "calculator.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


def test_smoke_fetch():
    src = (EXAMPLES_DIR / "fetch.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


@pytest.mark.xfail(reason="parser doesn't support named arg separator (--) yet")
def test_smoke_bank():
    src = (EXAMPLES_DIR / "bank.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)


@pytest.mark.xfail(reason="parser doesn't support field defaults yet")
def test_smoke_web_api():
    src = (EXAMPLES_DIR / "web_api.pact").read_text()
    prog = parse_src(src)
    assert isinstance(prog, ast.Program)
