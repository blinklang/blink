import pact.ast_nodes as ast
import pact.runtime as runtime


class EarlyReturn(Exception):
    def __init__(self, value):
        self.value = value


class Interpreter:
    def __init__(self, argv: list[str]):
        net_error_type = runtime.PactEnumType("NetError", {"ConnectionRefused": 1, "Timeout": 0})
        self.functions: dict[str, ast.FnDef] = {}
        self.enum_types: dict[str, runtime.PactEnumType] = {"NetError": net_error_type}
        self.struct_types: dict[str, list[str]] = {}
        self.methods: dict[tuple[str, str], ast.FnDef] = {}
        self.handler_stack: list[_HandlerValue] = []
        self.test_mode = False
        self.globals = {
            "io": runtime.IOHandle(),
            "env": runtime.EnvHandle(argv),
            "fs": runtime.FSHandle(),
            "db": runtime.DBHandle(),
            "net": runtime.NetHandle(),
            "json": runtime.JSONHandle(),
            "Map": _MapConstructorNamespace(),
            "Response": _ResponseConstructorNamespace(),
            "NetError": _EnumConstructorNamespace(net_error_type),
        }

    def run(self, program: ast.Program):
        self._register_program(program)
        return self.call_function("main", [])

    def run_tests(self, program: ast.Program):
        self._register_program(program)
        self.test_mode = True
        results = []
        for tb in program.tests:
            try:
                env = dict(self.globals)
                self.exec_block(tb.body, env)
                results.append((tb.name, True, None))
            except Exception as e:
                results.append((tb.name, False, str(e)))
        return results

    def _register_program(self, program: ast.Program):
        for td in program.types:
            self._register_type(td)
        for fn in program.functions:
            self.functions[fn.name] = fn
        for impl in program.impls:
            self._register_impl(impl)

    def _register_type(self, td: ast.TypeDef):
        if td.variants:
            variant_defs = {v.name: len(v.fields) for v in td.variants}
            enum_type = runtime.PactEnumType(td.name, variant_defs)
            self.enum_types[td.name] = enum_type
            self.globals[td.name] = _EnumConstructorNamespace(enum_type)
        elif td.fields:
            self.struct_types[td.name] = [f.name for f in td.fields]

    def _register_impl(self, impl: ast.ImplBlock):
        for method in impl.methods:
            self.methods[(impl.type_name, method.name)] = method

    def call_function(self, name: str, args: list):
        if name == "Ok":
            return runtime.PactOk(args[0] if args else None)
        if name == "Err":
            return runtime.PactErr(args[0] if args else None)
        if name == "assert":
            if not args[0]:
                raise AssertionError("assertion failed")
            return None
        if name == "assert_eq":
            if args[0] != args[1]:
                raise AssertionError(f"assert_eq failed: {args[0]!r} != {args[1]!r}")
            return None
        if name == "capture_log":
            return _CaptureLogHandler(args[0] if args else runtime.PactList([]))
        fn_def = self.functions[name]
        env = dict(self.globals)
        for param, arg in zip(fn_def.params, args):
            env[param.name] = arg
        try:
            return self.exec_block(fn_def.body, env)
        except EarlyReturn as ret:
            return ret.value

    def exec_block(self, block: ast.Block, env: dict):
        result = None
        for stmt in block.stmts:
            result = self.exec_stmt(stmt, env)
        return result

    def exec_stmt(self, stmt, env: dict):
        match stmt:
            case ast.LetBinding(name, value) if stmt.pattern is not None:
                val = self.eval_expr(value, env)
                self._destructure(stmt.pattern, val, env)
                return None
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
            case ast.IfExpr():
                return self.eval_if_expr(stmt, env)
            case ast.Assignment(target, value):
                val = self.eval_expr(value, env)
                if isinstance(target, ast.Ident):
                    env[target.name] = val
                return None
            case ast.ReturnExpr(value):
                raise EarlyReturn(self.eval_expr(value, env) if value else None)
            case ast.WithBlock(handlers, body):
                handler_vals = [self.eval_expr(h, env) for h in handlers]
                saved_io = env.get("io")
                for h in handler_vals:
                    if isinstance(h, _HandlerValue):
                        self.handler_stack.append(h)
                    elif isinstance(h, _CaptureLogHandler):
                        env["io"] = _SilentIOHandle(saved_io)
                try:
                    return self.exec_block(body, env)
                finally:
                    for h in handler_vals:
                        if isinstance(h, _HandlerValue) and h in self.handler_stack:
                            self.handler_stack.remove(h)
                    if saved_io:
                        env["io"] = saved_io
            case _:
                raise ValueError(f"Unknown statement: {stmt}")

    def eval_if_expr(self, expr: ast.IfExpr, env: dict):
        cond = self.eval_expr(expr.condition, env)
        if cond:
            return self.exec_block(expr.then_body, env)
        elif expr.else_body:
            return self.exec_block(expr.else_body, env)
        return None

    def eval_expr(self, expr, env: dict):
        match expr:
            case ast.Ident(name):
                if name in env:
                    return env[name]
                if name in self.functions:
                    return _FnRef(name)
                raise ValueError(f"undefined: {name}")
            case ast.IntLit(value):
                return value
            case ast.FloatLit(value):
                return value
            case ast.BoolLit(value):
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
                    if func.name in env and callable(env[func.name]):
                        return env[func.name](*evaluated_args)
                    return self.call_function(func.name, evaluated_args)
                target = self.eval_expr(func, env)
                if callable(target):
                    return target(*evaluated_args)
                raise ValueError(f"Cannot call: {func}")
            case ast.MethodCall(obj, method, args):
                target = self.eval_expr(obj, env)
                if isinstance(target, _EnumConstructorNamespace):
                    evaluated_args = [self.eval_expr(a, env) for a in args]
                    return target.enum_type.construct(method, evaluated_args)
                evaluated_args = [self.eval_expr(a, env) for a in args]
                handler_method = self._find_handler_method(obj, method)
                if handler_method:
                    return self._call_handler_method(handler_method, evaluated_args, env)
                impl_method = self._resolve_method(target, method)
                if impl_method:
                    return self._call_method(impl_method, target, evaluated_args)
                return getattr(target, method)(*evaluated_args)
            case ast.FieldAccess(obj, field):
                target = self.eval_expr(obj, env)
                if isinstance(target, _EnumConstructorNamespace):
                    variant_name = field
                    arity = target.enum_type.variant_defs.get(variant_name, 0)
                    if arity == 0:
                        return target.enum_type.construct(variant_name, [])
                    return _EnumVariantConstructor(target.enum_type, variant_name)
                return getattr(target, field)
            case ast.TupleLit(elements):
                return tuple(self.eval_expr(e, env) for e in elements)
            case ast.RangeLit(start, end):
                return range(self.eval_expr(start, env), self.eval_expr(end, env))
            case ast.ListLit(elements):
                return runtime.PactList([self.eval_expr(e, env) for e in elements])
            case ast.StructLit(type_name, fields):
                field_vals = [(f.name, self.eval_expr(f.value, env)) for f in fields]
                return runtime.PactStruct(type_name, field_vals)
            case ast.Closure(params, body):
                return _PactClosure(params, body, dict(env), self)
            case ast.HandlerExpr(effect, methods):
                return _HandlerValue(effect, methods, dict(env))
            case ast.MatchExpr(scrutinee, arms):
                value = self.eval_expr(scrutinee, env)
                for arm in arms:
                    bindings = self.match_pattern(arm.pattern, value)
                    if bindings is not None:
                        match_env = {**env, **bindings}
                        return self.eval_expr(arm.body, match_env)
                raise ValueError(f"No matching arm for: {value}")
            case ast.IfExpr():
                return self.eval_if_expr(expr, env)
            case ast.UnaryOp("-", operand):
                return -self.eval_expr(operand, env)
            case ast.UnaryOp("!", operand):
                return not self.eval_expr(operand, env)
            case ast.UnaryOp("?", operand):
                val = self.eval_expr(operand, env)
                if isinstance(val, runtime.PactOk):
                    return val.value
                if isinstance(val, runtime.PactErr):
                    raise EarlyReturn(val)
                if isinstance(val, runtime.PactSome):
                    return val.value
                if isinstance(val, runtime._PactNone):
                    raise EarlyReturn(runtime.NONE)
                return val
            case ast.BinOp(op, left, right):
                return self._eval_binop(op, left, right, env)
            case ast.Block(stmts):
                return self.exec_block(expr, env)
            case ast.ReturnExpr(value):
                raise EarlyReturn(self.eval_expr(value, env) if value else None)
            case _:
                raise ValueError(f"Unknown expression: {expr}")

    def _eval_binop(self, op, left, right, env):
        lv = self.eval_expr(left, env)
        if op == "&&":
            return lv and self.eval_expr(right, env)
        if op == "||":
            return lv or self.eval_expr(right, env)
        if op == "??":
            if isinstance(lv, runtime._PactNone):
                return self.eval_expr(right, env)
            if isinstance(lv, runtime.PactSome):
                return lv.value
            return lv
        rv = self.eval_expr(right, env)
        match op:
            case "+": return lv + rv
            case "-": return lv - rv
            case "*": return lv * rv
            case "/": return lv / rv
            case "%": return lv % rv
            case "==": return lv == rv
            case "!=": return lv != rv
            case "<": return lv < rv
            case ">": return lv > rv
            case "<=": return lv <= rv
            case ">=": return lv >= rv
        raise ValueError(f"Unknown operator: {op}")

    def match_pattern(self, pattern, value):
        match pattern:
            case ast.IntPattern(n):
                if value == n:
                    return {}
                return None
            case ast.WildcardPattern():
                return {}
            case ast.IdentPattern(name):
                if name == "None":
                    return {} if isinstance(value, runtime._PactNone) else None
                if isinstance(value, runtime.PactEnumVariant) and not value.fields:
                    if value.variant_name == name:
                        return {}
                    for et in self.enum_types.values():
                        if name in et.variant_defs:
                            return None
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
            case ast.EnumPattern(variant, fields):
                if variant == "Ok" and isinstance(value, runtime.PactOk):
                    if len(fields) == 1:
                        return self.match_pattern(fields[0], value.value)
                    return {} if not fields else None
                if variant == "Err" and isinstance(value, runtime.PactErr):
                    if len(fields) == 1:
                        return self.match_pattern(fields[0], value.value)
                    return {} if not fields else None
                if variant == "Some" and isinstance(value, runtime.PactSome):
                    if len(fields) == 1:
                        return self.match_pattern(fields[0], value.value)
                    return {} if not fields else None
                if variant in ("Ok", "Err", "Some"):
                    return None
                if not isinstance(value, runtime.PactEnumVariant):
                    return None
                full_variant = variant
                if "." in full_variant:
                    _, vname = full_variant.rsplit(".", 1)
                else:
                    vname = full_variant
                if value.variant_name != vname:
                    return None
                if len(fields) != len(value.fields):
                    return None
                bindings = {}
                for pat, val in zip(fields, value.fields):
                    result = self.match_pattern(pat, val)
                    if result is None:
                        return None
                    bindings.update(result)
                return bindings
            case _:
                raise ValueError(f"Unknown pattern: {pattern}")


    def _destructure(self, pattern, value, env):
        match pattern:
            case ast.TuplePattern(elements):
                if not isinstance(value, tuple):
                    raise ValueError(f"cannot destructure non-tuple: {value}")
                for pat, val in zip(elements, value):
                    self._destructure(pat, val, env)
            case ast.IdentPattern(name):
                env[name] = value
            case _:
                raise ValueError(f"cannot destructure with pattern: {pattern}")

    def _find_handler_method(self, obj_expr, method_name):
        if not isinstance(obj_expr, ast.Ident):
            return None
        obj_name = obj_expr.name
        for handler in reversed(self.handler_stack):
            effect_base = handler.effect.split(".")[0].lower()
            if obj_name == effect_base:
                for m in handler.methods:
                    if m.name == method_name:
                        return (handler, m)
        return None

    def _call_handler_method(self, handler_method, args, env):
        handler, fn_def = handler_method
        call_env = dict(handler.captured_env)
        call_env.update(self.globals)
        for param, arg in zip(fn_def.params, args):
            call_env[param.name] = arg
        try:
            return self.exec_block(fn_def.body, call_env)
        except EarlyReturn as ret:
            return ret.value

    def _resolve_method(self, target, method_name):
        if isinstance(target, runtime.PactStruct):
            key = (target._type_name, method_name)
            return self.methods.get(key)
        if isinstance(target, runtime.PactEnumVariant):
            key = (target.type_name, method_name)
            return self.methods.get(key)
        return None

    def _call_method(self, fn_def, target, args):
        env = dict(self.globals)
        params = fn_def.params
        if params and params[0].name == "self":
            env["self"] = target
            for param, arg in zip(params[1:], args):
                env[param.name] = arg
        else:
            for param, arg in zip(params, [target] + args):
                env[param.name] = arg
        try:
            return self.exec_block(fn_def.body, env)
        except EarlyReturn as ret:
            return ret.value


class _PactClosure:
    def __init__(self, params, body, captured_env, interp):
        self.params = params
        self.body = body
        self.captured_env = captured_env
        self.interp = interp

    def __call__(self, *args):
        env = dict(self.captured_env)
        for param, arg in zip(self.params, args):
            env[param.name] = arg
        try:
            return self.interp.exec_block(self.body, env)
        except EarlyReturn as ret:
            return ret.value


class _CaptureLogHandler:
    def __init__(self, log_list):
        self.log_list = log_list


class _SilentIOHandle:
    def __init__(self, real_io):
        self._real_io = real_io

    def println(self, value):
        self._real_io.println(value)

    def log(self, value):
        pass


class _HandlerValue:
    def __init__(self, effect, methods, captured_env):
        self.effect = effect
        self.methods = methods
        self.captured_env = captured_env


class _EnumConstructorNamespace:
    def __init__(self, enum_type):
        self.enum_type = enum_type


class _EnumVariantConstructor:
    def __init__(self, enum_type, variant_name):
        self.enum_type = enum_type
        self.variant_name = variant_name

    def __call__(self, *args):
        return self.enum_type.construct(self.variant_name, args)


class _FnRef:
    def __init__(self, name):
        self.name = name


class _MapConstructorNamespace:
    def of(self, pairs):
        if isinstance(pairs, runtime.PactList):
            return runtime.PactMap.of(list(pairs))
        return runtime.PactMap.of(pairs)


class _ResponseConstructorNamespace:
    def new(self, status, body):
        return runtime.PactResponse.new(status, body)

    def json(self, data):
        return runtime.PactResponseBuilder.json(data)

    def bad_request(self, msg):
        return runtime.PactResponseBuilder.bad_request(msg)

    def not_found(self, msg):
        return runtime.PactResponseBuilder.not_found(msg)

    def internal_error(self, msg):
        return runtime.PactResponseBuilder.internal_error(msg)
