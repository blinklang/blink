import pact.ast_nodes as ast
import pact.runtime as runtime


class Interpreter:
    def __init__(self, argv: list[str]):
        self.globals = {
            "io": runtime.IOHandle(),
            "env": runtime.EnvHandle(argv),
        }
        self.functions: dict[str, ast.FnDef] = {}

    def run(self, program: ast.Program):
        for fn in program.functions:
            self.functions[fn.name] = fn
        return self.call_function("main", [])

    def call_function(self, name: str, args: list):
        fn_def = self.functions[name]
        env = dict(self.globals)
        for param, arg in zip(fn_def.params, args):
            env[param.name] = arg
        return self.exec_block(fn_def.body, env)

    def exec_block(self, block: ast.Block, env: dict):
        result = None
        for stmt in block.stmts:
            result = self.exec_stmt(stmt, env)
        return result

    def exec_stmt(self, stmt, env: dict):
        match stmt:
            case ast.LetBinding(name, value):
                env[name] = self.eval_expr(value, env)
                return None
            case ast.ExprStmt(expr):
                return self.eval_expr(expr, env)
            case ast.ForIn(var_name, iterable, body):
                items = self.eval_expr(iterable, env)
                for item in items:
                    env[var_name] = item
                    self.exec_block(body, env)
                return None
            case _:
                raise ValueError(f"Unknown statement: {stmt}")

    def eval_expr(self, expr, env: dict):
        match expr:
            case ast.Ident(name):
                return env[name]
            case ast.IntLit(value):
                return value
            case ast.InterpString(parts):
                pieces = []
                for part in parts:
                    if isinstance(part, str):
                        pieces.append(part)
                    else:
                        pieces.append(str(self.eval_expr(part, env)))
                return "".join(pieces)
            case ast.Call(func, args):
                evaluated_args = [self.eval_expr(a, env) for a in args]
                if isinstance(func, ast.Ident):
                    return self.call_function(func.name, evaluated_args)
                raise ValueError(f"Cannot call: {func}")
            case ast.MethodCall(obj, method, args):
                target = self.eval_expr(obj, env)
                evaluated_args = [self.eval_expr(a, env) for a in args]
                return getattr(target, method)(*evaluated_args)
            case ast.TupleLit(elements):
                return tuple(self.eval_expr(e, env) for e in elements)
            case ast.RangeLit(start, end):
                return range(self.eval_expr(start, env), self.eval_expr(end, env))
            case ast.MatchExpr(scrutinee, arms):
                value = self.eval_expr(scrutinee, env)
                for arm in arms:
                    bindings = self.match_pattern(arm.pattern, value)
                    if bindings is not None:
                        match_env = {**env, **bindings}
                        return self.eval_expr(arm.body, match_env)
                raise ValueError(f"No matching arm for: {value}")
            case ast.BinOp("%", left, right):
                return self.eval_expr(left, env) % self.eval_expr(right, env)
            case ast.BinOp("??", left, right):
                result = self.eval_expr(left, env)
                if isinstance(result, runtime._PactNone):
                    return self.eval_expr(right, env)
                if isinstance(result, runtime.PactSome):
                    return result.value
                return result
            case _:
                raise ValueError(f"Unknown expression: {expr}")

    def match_pattern(self, pattern, value):
        match pattern:
            case ast.IntPattern(n):
                if value == n:
                    return {}
                return None
            case ast.WildcardPattern():
                return {}
            case ast.IdentPattern(name):
                return {name: value}
            case ast.TuplePattern(elements):
                if not isinstance(value, tuple) or len(value) != len(elements):
                    return None
                bindings = {}
                for pat, val in zip(elements, value):
                    result = self.match_pattern(pat, val)
                    if result is None:
                        return None
                    bindings.update(result)
                return bindings
            case _:
                raise ValueError(f"Unknown pattern: {pattern}")
