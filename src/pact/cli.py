import sys

import pact.lexer as lexer
import pact.parser as parser
import pact.interpreter as interpreter


def main():
    args = sys.argv[1:]

    if len(args) < 2 or args[0] != "run":
        print("Usage: pact run <file.pact> [args...]", file=sys.stderr)
        sys.exit(1)

    filepath = args[1]
    script_args = args[1:]

    try:
        with open(filepath) as f:
            source = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    tokens = lexer.lex(source)
    program = parser.parse(tokens)
    interp = interpreter.Interpreter(script_args)
    interp.run(program)
