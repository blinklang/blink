import pathlib

import pact.lexer as lexer
import pact.parser as parser
import pact.interpreter as interpreter
import pact.runtime as runtime


EXAMPLES_DIR = pathlib.Path(__file__).resolve().parent.parent / "examples"


def run_pact(source, capsys, argv=None):
    tokens = lexer.lex(source)
    program = parser.parse(tokens)
    interp = interpreter.Interpreter(argv or [])
    interp.run(program)
    return capsys.readouterr().out


def run_pact_file(path, capsys, argv=None):
    source = pathlib.Path(path).read_text()
    return run_pact(source, capsys, argv)


def test_println(capsys):
    out = run_pact('fn main() {\nio.println("hello")\n}', capsys)
    assert out == "hello\n"


def test_let_binding_and_interpolation(capsys):
    src = 'fn main() {\nlet x = "world"\nio.println("hello {x}")\n}'
    out = run_pact(src, capsys)
    assert out == "hello world\n"


def test_user_defined_fn(capsys):
    src = 'fn greet(name) {\nio.println("hi {name}")\n}\nfn main() {\ngreet("bob")\n}'
    out = run_pact(src, capsys)
    assert out == "hi bob\n"


def test_match_int_literal(capsys):
    src = 'fn main() {\nmatch 1 {\n1 => io.println("one")\n_ => io.println("other")\n}\n}'
    out = run_pact(src, capsys)
    assert out == "one\n"


def test_match_wildcard(capsys):
    src = 'fn main() {\nmatch 99 {\n1 => io.println("one")\n_ => io.println("other")\n}\n}'
    out = run_pact(src, capsys)
    assert out == "other\n"


def test_match_ident_binding(capsys):
    src = 'fn main() {\nmatch 42 {\nn => io.println("{n}")\n}\n}'
    out = run_pact(src, capsys)
    assert out == "42\n"


def test_match_tuple(capsys):
    src = 'fn main() {\nmatch (1, 2) {\n(1, 2) => io.println("yes")\n_ => io.println("no")\n}\n}'
    out = run_pact(src, capsys)
    assert out == "yes\n"


def test_for_in_range(capsys):
    src = 'fn main() {\nfor n in 1..4 {\nio.println("{n}")\n}\n}'
    out = run_pact(src, capsys)
    assert out == "1\n2\n3\n"


def test_modulo(capsys):
    src = 'fn main() {\nio.println("{10 % 3}")\n}'
    out = run_pact(src, capsys)
    assert out == "1\n"


def test_coalesce_default(capsys):
    src = 'fn main() {\nlet val = env.args().get(1) ?? "default"\nio.println(val)\n}'
    out = run_pact(src, capsys, argv=[])
    assert out == "default\n"


def test_e2e_hello(capsys):
    out = run_pact_file(EXAMPLES_DIR / "hello.pact", capsys)
    assert out == "Hello, world!\nWelcome to Pact.\n"


def test_e2e_fizzbuzz(capsys):
    out = run_pact_file(EXAMPLES_DIR / "fizzbuzz.pact", capsys)
    lines = out.strip().split("\n")
    expected_first_15 = [
        "1", "2", "Fizz", "4", "Buzz",
        "Fizz", "7", "8", "Fizz", "Buzz",
        "11", "Fizz", "13", "14", "FizzBuzz",
    ]
    assert lines[:15] == expected_first_15
