import ast
import parser

effect Format {
    effect Emit
}

// formatter.pact — AST pretty-printer emitting canonical Pact source
//
// Walks the parallel-array AST and emits canonically formatted Pact.
// Follows the same pattern as codegen but outputs Pact source instead of C.
//
// Canonical rules: 4-space indent, K&R braces, no semicolons,
// double quotes, max 1 blank line, trailing whitespace stripped.
// Lines wrap at 100 characters at logical break points.

pub let mut fmt_lines: List[Str] = []
pub let mut fmt_indent: Int = 0
pub let fmt_max_line: Int = 100

pub fn fmt_emit(line: Str) ! Format.Emit {
    if line == "" {
        fmt_lines.push("")
    } else {
        let mut pad = ""
        let mut i = 0
        while i < fmt_indent {
            pad = pad.concat("    ")
            i = i + 1
        }
        fmt_lines.push(pad.concat(line))
    }
}

pub fn fmt_emit_raw(line: Str) ! Format.Emit {
    fmt_lines.push(line)
}

pub fn fmt_line_len(line: Str) -> Int {
    fmt_indent * 4 + line.len()
}

pub fn fmt_needs_wrap(line: Str) -> Int {
    if fmt_line_len(line) > fmt_max_line {
        return 1
    }
    0
}

pub fn fmt_join() -> Str {
    fmt_lines.join("\n")
}

// ── Type annotation formatting ──────────────────────────────────────

pub fn format_type_ann(node: Int) -> Str {
    if node == -1 {
        return ""
    }
    let kind = np_kind.get(node).unwrap()
    if kind != NodeKind.TypeAnn {
        return np_name.get(node).unwrap()
    }
    let name = np_name.get(node).unwrap()
    let elems_sl = np_elements.get(node).unwrap()
    if name == "Fn" {
        let mut result = "fn("
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_type_ann(sublist_get(elems_sl, i)))
                i = i + 1
            }
        }
        result = result.concat(")")
        let ret = np_return_type.get(node).unwrap()
        if ret != "" && ret != "Void" {
            result = result.concat(" -> ").concat(ret)
        }
        return result
    }
    if elems_sl != -1 && sublist_length(elems_sl) > 0 {
        let mut result = name.concat("[")
        let mut i = 0
        while i < sublist_length(elems_sl) {
            if i > 0 {
                result = result.concat(", ")
            }
            result = result.concat(format_type_ann(sublist_get(elems_sl, i)))
            i = i + 1
        }
        result = result.concat("]")
        return result
    }
    name
}

// ── Pattern formatting ──────────────────────────────────────────────

pub fn format_pattern(node: Int) -> Str {
    if node == -1 {
        return "_"
    }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.WildcardPattern {
        return "_"
    }
    if kind == NodeKind.IntPattern {
        return np_str_val.get(node).unwrap()
    }
    if kind == NodeKind.StringPattern {
        return "\"".concat(fmt_escape_str_literal(np_str_val.get(node).unwrap())).concat("\"")
    }
    if kind == NodeKind.IdentPattern {
        return np_name.get(node).unwrap()
    }
    if kind == NodeKind.Ident {
        return np_name.get(node).unwrap()
    }
    if kind == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(node).unwrap()
        let mut result = "("
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_pattern(sublist_get(elems_sl, i)))
                i = i + 1
            }
        }
        return result.concat(")")
    }
    if kind == NodeKind.OrPattern {
        let alts_sl = np_elements.get(node).unwrap()
        let mut result = ""
        if alts_sl != -1 {
            let mut i = 0
            while i < sublist_length(alts_sl) {
                if i > 0 {
                    result = result.concat(" | ")
                }
                result = result.concat(format_pattern(sublist_get(alts_sl, i)))
                i = i + 1
            }
        }
        return result
    }
    if kind == NodeKind.RangePattern {
        let lo = np_str_val.get(node).unwrap()
        let hi = np_name.get(node).unwrap()
        if np_inclusive.get(node).unwrap() != 0 {
            return "{lo}..={hi}"
        }
        return "{lo}..{hi}"
    }
    if kind == NodeKind.EnumPattern {
        let ename = np_name.get(node).unwrap()
        let vname = np_type_name.get(node).unwrap()
        let flds_sl = np_fields.get(node).unwrap()
        let mut result = ""
        if vname != "" {
            result = "{ename}.{vname}"
        } else {
            result = ename
        }
        if flds_sl != -1 {
            result = result.concat("(")
            let mut i = 0
            while i < sublist_length(flds_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_pattern(sublist_get(flds_sl, i)))
                i = i + 1
            }
            result = result.concat(")")
        }
        return result
    }
    if kind == NodeKind.StructPattern {
        let sname = np_type_name.get(node).unwrap()
        let flds_sl = np_fields.get(node).unwrap()
        let has_rest = np_inclusive.get(node).unwrap()
        let mut result = "{sname} \{"
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                let fld = sublist_get(flds_sl, i)
                let fname = np_name.get(fld).unwrap()
                let fpat = np_pattern.get(fld).unwrap()
                if fpat != -1 {
                    result = result.concat(fname).concat(": ").concat(format_pattern(fpat))
                } else {
                    result = result.concat(fname)
                }
                i = i + 1
            }
        }
        if has_rest != 0 {
            if flds_sl != -1 && sublist_length(flds_sl) > 0 {
                result = result.concat(", ")
            }
            result = result.concat("..")
        }
        return result.concat("}")
    }
    if kind == NodeKind.AsPattern {
        let name = np_name.get(node).unwrap()
        let inner = np_pattern.get(node).unwrap()
        return "{name} as ".concat(format_pattern(inner))
    }
    if kind == NodeKind.ListPattern {
        let elems_sl = np_elements.get(node).unwrap()
        let has_rest = np_inclusive.get(node).unwrap()
        let mut result = "["
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_pattern(sublist_get(elems_sl, i)))
                i = i + 1
            }
        }
        if has_rest != 0 {
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                result = result.concat(", ")
            }
            result = result.concat("...")
        }
        return result.concat("]")
    }
    "_"
}

// ── Expression formatting ───────────────────────────────────────────

fn op_precedence(op: Str) -> Int {
    if op == "||" { return 1 }
    if op == "&&" { return 2 }
    if op == "==" || op == "!=" { return 3 }
    if op == "<" || op == ">" || op == "<=" || op == ">=" { return 4 }
    if op == "??" { return 5 }
    if op == "+" || op == "-" { return 6 }
    if op == "*" || op == "/" || op == "%" { return 7 }
    0
}

fn needs_parens(child: Int, parent_op: Str, is_right: Int) -> Int {
    let kind = np_kind.get(child).unwrap()
    if kind != NodeKind.BinOp {
        return 0
    }
    let child_op = np_op.get(child).unwrap()
    let parent_prec = op_precedence(parent_op)
    let child_prec = op_precedence(child_op)
    if child_prec < parent_prec {
        return 1
    }
    if child_prec == parent_prec && is_right != 0 {
        return 1
    }
    0
}

pub fn format_expr(node: Int) -> Str {
    if node == -1 {
        return ""
    }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.IntLit {
        let s = np_str_val.get(node).unwrap()
        if s != "" {
            return s
        }
        return "{np_int_val.get(node).unwrap()}"
    }

    if kind == NodeKind.FloatLit {
        return np_str_val.get(node).unwrap()
    }

    if kind == NodeKind.BoolLit {
        if np_int_val.get(node).unwrap() != 0 {
            return "true"
        }
        return "false"
    }

    if kind == NodeKind.Ident {
        return np_name.get(node).unwrap()
    }

    if kind == NodeKind.InterpString {
        return format_interp_string(node)
    }

    if kind == NodeKind.BinOp {
        let op = np_op.get(node).unwrap()
        let left = np_left.get(node).unwrap()
        let right = np_right.get(node).unwrap()
        let mut left_str = format_expr(left)
        let mut right_str = format_expr(right)
        if needs_parens(left, op, 0) != 0 {
            left_str = "(".concat(left_str).concat(")")
        }
        if needs_parens(right, op, 1) != 0 {
            right_str = "(".concat(right_str).concat(")")
        }
        return "{left_str} {op} {right_str}"
    }

    if kind == NodeKind.UnaryOp {
        let op = np_op.get(node).unwrap()
        let operand = np_left.get(node).unwrap()
        if op == "?" {
            return format_expr(operand).concat("?")
        }
        let inner = format_expr(operand)
        let inner_kind = np_kind.get(operand).unwrap()
        if inner_kind == NodeKind.BinOp {
            return "{op}(".concat(inner).concat(")")
        }
        return op.concat(inner)
    }

    if kind == NodeKind.Call {
        let func = np_left.get(node).unwrap()
        let args_sl = np_args.get(node).unwrap()
        let func_str = format_expr(func)
        let mut result = func_str.concat("(")
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_expr(sublist_get(args_sl, i)))
                i = i + 1
            }
        }
        return result.concat(")")
    }

    if kind == NodeKind.MethodCall {
        let obj = np_obj.get(node).unwrap()
        let method = np_method.get(node).unwrap()
        let args_sl = np_args.get(node).unwrap()
        let obj_str = format_expr(obj)
        let mut result = "{obj_str}.{method}("
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_expr(sublist_get(args_sl, i)))
                i = i + 1
            }
        }
        return result.concat(")")
    }

    if kind == NodeKind.FieldAccess {
        let obj = np_obj.get(node).unwrap()
        let field = np_name.get(node).unwrap()
        return "{format_expr(obj)}.{field}"
    }

    if kind == NodeKind.IndexExpr {
        let obj = np_obj.get(node).unwrap()
        let idx = np_index.get(node).unwrap()
        return "{format_expr(obj)}[{format_expr(idx)}]"
    }

    if kind == NodeKind.TupleLit {
        let elems_sl = np_elements.get(node).unwrap()
        let mut result = "("
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_expr(sublist_get(elems_sl, i)))
                i = i + 1
            }
        }
        return result.concat(")")
    }

    if kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node).unwrap()
        let mut result = "["
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_expr(sublist_get(elems_sl, i)))
                i = i + 1
            }
        }
        return result.concat("]")
    }

    if kind == NodeKind.StructLit {
        let tname = np_type_name.get(node).unwrap()
        let flds_sl = np_fields.get(node).unwrap()
        let mut result = "{tname} \{ "
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                let fld = sublist_get(flds_sl, i)
                let fname = np_name.get(fld).unwrap()
                let fval = np_value.get(fld).unwrap()
                result = result.concat("{fname}: {format_expr(fval)}")
                i = i + 1
            }
        }
        return result.concat(" }")
    }

    if kind == NodeKind.RangeLit {
        let start = np_start.get(node).unwrap()
        let end = np_end.get(node).unwrap()
        if np_inclusive.get(node).unwrap() != 0 {
            return "{format_expr(start)}..={format_expr(end)}"
        }
        return "{format_expr(start)}..{format_expr(end)}"
    }

    if kind == NodeKind.Closure {
        return format_closure_inline(node)
    }

    if kind == NodeKind.IfExpr {
        return format_if_inline(node)
    }

    if kind == NodeKind.MatchExpr {
        return format_match_inline(node)
    }

    if kind == NodeKind.Block {
        return format_block_inline(node)
    }

    if kind == NodeKind.AsyncScope {
        return "async.scope ".concat(format_block_inline(np_body.get(node).unwrap()))
    }

    if kind == NodeKind.AsyncSpawn {
        return "async.spawn ".concat(format_block_inline(np_body.get(node).unwrap()))
    }

    if kind == NodeKind.AwaitExpr {
        return format_expr(np_obj.get(node).unwrap()).concat(".await")
    }

    if kind == NodeKind.ChannelNew {
        let tparams = np_type_params.get(node).unwrap()
        let args_sl = np_args.get(node).unwrap()
        let mut result = "channel.new"
        if tparams != -1 && sublist_length(tparams) > 0 {
            result = result.concat("[")
            let mut i = 0
            while i < sublist_length(tparams) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(np_name.get(sublist_get(tparams, i)).unwrap())
                i = i + 1
            }
            result = result.concat("]")
        }
        result = result.concat("(")
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(format_expr(sublist_get(args_sl, i)))
                i = i + 1
            }
        }
        return result.concat(")")
    }

    if kind == NodeKind.HandlerExpr {
        return format_handler_inline(node)
    }

    if kind == NodeKind.EmbedExpr {
        let path = np_str_val.get(node).unwrap()
        return "#embed(\"{path}\")"
    }

    if kind == NodeKind.NamedArg {
        let label = np_name.get(node).unwrap()
        let inner = np_value.get(node).unwrap()
        return "{label}: {format_expr(inner)}"
    }

    ""
}

pub fn fmt_escape_str_literal(s: Str) -> Str {
    let bs = "\\"
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let ch = s.char_at(i)
        if ch == 92 {
            result = result.concat(bs).concat(bs)
        } else if ch == 34 {
            result = result.concat(bs).concat("\"")
        } else if ch == 10 {
            result = result.concat(bs).concat("n")
        } else if ch == 9 {
            result = result.concat(bs).concat("t")
        } else if ch == 123 {
            result = result.concat(bs).concat("\{")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

pub fn format_interp_string(node: Int) -> Str {
    let parts_sl = np_elements.get(node).unwrap()
    if parts_sl == -1 {
        return "\"\""
    }
    let mut result = "\""
    let mut i = 0
    while i < sublist_length(parts_sl) {
        let part = sublist_get(parts_sl, i)
        let pk = np_kind.get(part).unwrap()
        if pk == NodeKind.Ident && np_str_val.get(part).unwrap() == np_name.get(part).unwrap() {
            result = result.concat(fmt_escape_str_literal(np_str_val.get(part).unwrap()))
        } else {
            result = result.concat("\{").concat(format_expr(part)).concat("}")
        }
        i = i + 1
    }
    result.concat("\"")
}

pub fn format_closure_inline(node: Int) -> Str {
    let params_sl = np_params.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    let ret = np_return_type.get(node).unwrap()
    let mut result = "fn("
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            if i > 0 {
                result = result.concat(", ")
            }
            result = result.concat(format_param(sublist_get(params_sl, i)))
            i = i + 1
        }
    }
    result = result.concat(")")
    if ret != "" {
        result = result.concat(" -> ").concat(ret)
    }
    result = result.concat(" ").concat(format_block_inline(body))
    result
}

pub fn format_param(node: Int) -> Str {
    let name = np_name.get(node).unwrap()
    let type_name = np_type_name.get(node).unwrap()
    let is_mut = np_is_mut.get(node).unwrap()
    let type_ann = np_type_ann.get(node).unwrap()
    let mut result = ""
    if is_mut != 0 {
        result = "mut "
    }
    result = result.concat(name)
    if type_ann != -1 {
        result = result.concat(": ").concat(format_type_ann(type_ann))
    } else if type_name != "" {
        result = result.concat(": ").concat(type_name)
    }
    result
}

pub fn format_block_inline(node: Int) -> Str {
    if node == -1 {
        return "\{ }"
    }
    let stmts_sl = np_stmts.get(node).unwrap()
    if stmts_sl == -1 || sublist_length(stmts_sl) == 0 {
        return "\{ }"
    }
    if sublist_length(stmts_sl) == 1 {
        let stmt = sublist_get(stmts_sl, 0)
        let sk = np_kind.get(stmt).unwrap()
        if sk == NodeKind.ExprStmt {
            let inner = np_value.get(stmt).unwrap()
            return "\{ ".concat(format_expr(inner)).concat(" }")
        }
        if sk == NodeKind.Return {
            let val = np_value.get(stmt).unwrap()
            if val != -1 {
                return "\{ return ".concat(format_expr(val)).concat(" }")
            }
            return "\{ return }"
        }
        if is_simple_expr_kind(sk) {
            return "\{ ".concat(format_expr(stmt)).concat(" }")
        }
    }
    "\{ ... }"
}

pub fn is_simple_expr_kind(kind: Int) -> Int {
    if kind == NodeKind.IntLit { return 1 }
    if kind == NodeKind.FloatLit { return 1 }
    if kind == NodeKind.BoolLit { return 1 }
    if kind == NodeKind.Ident { return 1 }
    if kind == NodeKind.BinOp { return 1 }
    if kind == NodeKind.UnaryOp { return 1 }
    if kind == NodeKind.Call { return 1 }
    if kind == NodeKind.MethodCall { return 1 }
    if kind == NodeKind.FieldAccess { return 1 }
    if kind == NodeKind.InterpString { return 1 }
    0
}

pub fn format_if_inline(node: Int) -> Str {
    let cond = np_condition.get(node).unwrap()
    let then_b = np_then_body.get(node).unwrap()
    let else_b = np_else_body.get(node).unwrap()
    let mut result = "if ".concat(format_expr(cond)).concat(" ").concat(format_block_inline(then_b))
    if else_b != -1 {
        let else_stmts = np_stmts.get(else_b).unwrap()
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner).unwrap() == NodeKind.IfExpr {
                result = result.concat(" else ").concat(format_if_inline(inner))
                return result
            }
        }
        result = result.concat(" else ").concat(format_block_inline(else_b))
    }
    result
}

pub fn format_match_inline(node: Int) -> Str {
    return "match ".concat(format_expr(np_scrutinee.get(node).unwrap())).concat(" \{ ... }")
}

pub fn format_handler_inline(node: Int) -> Str {
    let name = np_name.get(node).unwrap()
    return "handler {name} \{ ... }"
}

// ── Wrapped emission helpers ────────────────────────────────────────

pub fn emit_call_wrapped(node: Int, prefix: Str) ! Format.Emit {
    let kind = np_kind.get(node).unwrap()
    if kind == NodeKind.Call {
        let func = np_left.get(node).unwrap()
        let args_sl = np_args.get(node).unwrap()
        let func_str = format_expr(func)
        let open = prefix.concat(func_str).concat("(")
        if args_sl == -1 || sublist_length(args_sl) == 0 {
            fmt_emit(open.concat(")"))
            return
        }
        fmt_emit(open)
        fmt_indent = fmt_indent + 1
        let mut i = 0
        while i < sublist_length(args_sl) {
            let arg_str = format_expr(sublist_get(args_sl, i))
            if i < sublist_length(args_sl) - 1 {
                fmt_emit(arg_str.concat(","))
            } else {
                fmt_emit(arg_str)
            }
            i = i + 1
        }
        fmt_indent = fmt_indent - 1
        fmt_emit(")")
        return
    }
    if kind == NodeKind.MethodCall {
        let obj = np_obj.get(node).unwrap()
        let method = np_method.get(node).unwrap()
        let args_sl = np_args.get(node).unwrap()
        let obj_str = format_expr(obj)
        let open = prefix.concat(obj_str).concat(".").concat(method).concat("(")
        if args_sl == -1 || sublist_length(args_sl) == 0 {
            fmt_emit(open.concat(")"))
            return
        }
        fmt_emit(open)
        fmt_indent = fmt_indent + 1
        let mut i = 0
        while i < sublist_length(args_sl) {
            let arg_str = format_expr(sublist_get(args_sl, i))
            if i < sublist_length(args_sl) - 1 {
                fmt_emit(arg_str.concat(","))
            } else {
                fmt_emit(arg_str)
            }
            i = i + 1
        }
        fmt_indent = fmt_indent - 1
        fmt_emit(")")
        return
    }
    fmt_emit(prefix.concat(format_expr(node)))
}

pub fn emit_list_wrapped(node: Int, prefix: Str) ! Format.Emit {
    let elems_sl = np_elements.get(node).unwrap()
    if elems_sl == -1 || sublist_length(elems_sl) == 0 {
        fmt_emit(prefix.concat("[]"))
        return
    }
    fmt_emit(prefix.concat("["))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < sublist_length(elems_sl) {
        let elem_str = format_expr(sublist_get(elems_sl, i))
        if i < sublist_length(elems_sl) - 1 {
            fmt_emit(elem_str.concat(","))
        } else {
            fmt_emit(elem_str)
        }
        i = i + 1
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("]")
}

pub fn emit_struct_lit_wrapped(node: Int, prefix: Str) ! Format.Emit {
    let tname = np_type_name.get(node).unwrap()
    let flds_sl = np_fields.get(node).unwrap()
    if flds_sl == -1 || sublist_length(flds_sl) == 0 {
        fmt_emit(prefix.concat(tname).concat(" \{ }"))
        return
    }
    fmt_emit(prefix.concat(tname).concat(" \{"))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let fld = sublist_get(flds_sl, i)
        let fname = np_name.get(fld).unwrap()
        let fval = np_value.get(fld).unwrap()
        let fld_str = "{fname}: {format_expr(fval)}"
        if i < sublist_length(flds_sl) - 1 {
            fmt_emit(fld_str.concat(","))
        } else {
            fmt_emit(fld_str)
        }
        i = i + 1
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub let mut binop_parts: List[Str] = []
pub let mut binop_ops: List[Str] = []

pub fn emit_binop_wrapped(node: Int, prefix: Str) ! Format.Emit {
    binop_parts = []
    binop_ops = []
    flatten_binop_chain(node)
    if binop_parts.len() == 0 {
        fmt_emit(prefix.concat(format_expr(node)))
        return
    }
    fmt_emit(prefix.concat(binop_parts.get(0).unwrap()))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < binop_ops.len() {
        fmt_emit("{binop_ops.get(i).unwrap()} {binop_parts.get(i + 1).unwrap()}")
        i = i + 1
    }
    fmt_indent = fmt_indent - 1
}

fn flatten_binop_chain(node: Int) {
    let kind = np_kind.get(node).unwrap()
    if kind != NodeKind.BinOp {
        binop_parts.push(format_expr(node))
        return
    }
    let op = np_op.get(node).unwrap()
    let left = np_left.get(node).unwrap()
    let right = np_right.get(node).unwrap()
    let left_kind = np_kind.get(left).unwrap()
    if left_kind == NodeKind.BinOp && np_op.get(left).unwrap() == op {
        flatten_binop_chain(left)
    } else {
        let mut left_str = format_expr(left)
        if needs_parens(left, op, 0) != 0 {
            left_str = "(".concat(left_str).concat(")")
        }
        binop_parts.push(left_str)
    }
    binop_ops.push(op)
    let mut right_str = format_expr(right)
    if needs_parens(right, op, 1) != 0 {
        right_str = "(".concat(right_str).concat(")")
    }
    binop_parts.push(right_str)
}

pub fn emit_method_chain_wrapped(node: Int, prefix: Str) ! Format.Emit {
    let mut chain: List[Int] = []
    let mut cur = node
    while np_kind.get(cur).unwrap() == NodeKind.MethodCall {
        chain.push(cur)
        cur = np_obj.get(cur).unwrap()
    }
    let base_str = format_expr(cur)
    fmt_emit(prefix.concat(base_str))
    fmt_indent = fmt_indent + 1
    let mut i = chain.len() - 1
    while i >= 0 {
        let mc = chain.get(i).unwrap()
        let method = np_method.get(mc).unwrap()
        let args_sl = np_args.get(mc).unwrap()
        let mut call_str = ".".concat(method).concat("(")
        if args_sl != -1 {
            let mut j = 0
            while j < sublist_length(args_sl) {
                if j > 0 {
                    call_str = call_str.concat(", ")
                }
                call_str = call_str.concat(format_expr(sublist_get(args_sl, j)))
                j = j + 1
            }
        }
        call_str = call_str.concat(")")
        fmt_emit(call_str)
        i = i - 1
    }
    fmt_indent = fmt_indent - 1
}

pub fn is_method_chain(node: Int) -> Int {
    if np_kind.get(node).unwrap() != NodeKind.MethodCall {
        return 0
    }
    let obj = np_obj.get(node).unwrap()
    if np_kind.get(obj).unwrap() == NodeKind.MethodCall {
        return 1
    }
    0
}

pub fn chain_depth(node: Int) -> Int {
    let mut depth = 0
    let mut cur = node
    while np_kind.get(cur).unwrap() == NodeKind.MethodCall {
        depth = depth + 1
        cur = np_obj.get(cur).unwrap()
    }
    depth
}

pub fn emit_expr_wrapped(node: Int, prefix: Str, suffix: Str) ! Format.Emit {
    let expr_str = format_expr(node)
    let full = prefix.concat(expr_str).concat(suffix)
    if fmt_needs_wrap(full) == 0 {
        fmt_emit(full)
        return
    }
    let kind = np_kind.get(node).unwrap()
    if kind == NodeKind.Call || kind == NodeKind.MethodCall {
        if is_method_chain(node) != 0 && chain_depth(node) >= 2 {
            if suffix != "" {
                emit_method_chain_wrapped(node, prefix)
                return
            }
            emit_method_chain_wrapped(node, prefix)
            return
        }
        if suffix != "" {
            let inner = format_expr(node)
            let with_suffix = prefix.concat(inner).concat(suffix)
            if fmt_needs_wrap(with_suffix) == 0 {
                fmt_emit(with_suffix)
                return
            }
        }
        emit_call_wrapped(node, prefix)
        return
    }
    if kind == NodeKind.ListLit {
        emit_list_wrapped(node, prefix)
        return
    }
    if kind == NodeKind.StructLit {
        emit_struct_lit_wrapped(node, prefix)
        return
    }
    if kind == NodeKind.BinOp {
        if suffix != "" {
            fmt_emit(full)
            return
        }
        emit_binop_wrapped(node, prefix)
        return
    }
    fmt_emit(full)
}

// ── Statement formatting ────────────────────────────────────────────

pub fn emit_comments(node: Int) ! Format.Emit {
    let doc = np_doc_comment.get(node).unwrap()
    if doc != "" {
        let mut i = 0
        let mut line_start = 0
        while i <= doc.len() {
            if i == doc.len() || doc.char_at(i) == 10 {
                let line = doc.substring(line_start, i - line_start)
                fmt_emit("///".concat(line))
                line_start = i + 1
            }
            i = i + 1
        }
    }
    let leading = np_leading_comments.get(node).unwrap()
    if leading != "" {
        let mut i = 0
        let mut line_start = 0
        while i <= leading.len() {
            if i == leading.len() || leading.char_at(i) == 10 {
                let line = leading.substring(line_start, i - line_start)
                fmt_emit("//".concat(line))
                line_start = i + 1
            }
            i = i + 1
        }
    }
}

pub fn emit_trailing_comment(node: Int) ! Format.Emit {
    let trailing = np_trailing_comments.get(node).unwrap()
    if trailing != "" {
        let last_idx = fmt_lines.len() - 1
        if last_idx >= 0 {
            let last_line = fmt_lines.get(last_idx).unwrap()
            fmt_lines.set(last_idx, last_line.concat(" //").concat(trailing))
        }
    }
}

pub fn emit_trailing_comments_block(node: Int) ! Format.Emit {
    let trailing = np_trailing_comments.get(node).unwrap()
    if trailing != "" {
        let mut i = 0
        let mut line_start = 0
        while i <= trailing.len() {
            if i == trailing.len() || trailing.char_at(i) == 10 {
                let line = trailing.substring(line_start, i - line_start)
                fmt_emit("//".concat(line))
                line_start = i + 1
            }
            i = i + 1
        }
    }
}

pub fn format_stmt(node: Int) ! Format.Emit {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node).unwrap()

    emit_comments(node)

    if kind == NodeKind.LetBinding {
        let name = np_name.get(node).unwrap()
        let is_mut = np_is_mut.get(node).unwrap()
        let is_pub = np_is_pub.get(node).unwrap()
        let is_const = np_is_const.get(node).unwrap()
        let val = np_value.get(node).unwrap()
        let type_ann = np_target.get(node).unwrap()
        let mut prefix = ""
        if is_pub != 0 {
            prefix = "pub "
        }
        if is_const != 0 {
            prefix = prefix.concat("const ")
        } else {
            prefix = prefix.concat("let ")
            if is_mut != 0 {
                prefix = prefix.concat("mut ")
            }
        }
        let let_fmt_pat = np_elements.get(node).unwrap()
        if let_fmt_pat != -1 {
            prefix = prefix.concat(format_pattern(let_fmt_pat))
        } else {
            prefix = prefix.concat(name)
        }
        if type_ann != -1 {
            prefix = prefix.concat(": ").concat(format_type_ann(type_ann))
        }
        prefix = prefix.concat(" = ")
        emit_expr_wrapped(val, prefix, "")
        return
    }

    if kind == NodeKind.Assignment {
        let target = np_target.get(node).unwrap()
        let val = np_value.get(node).unwrap()
        let assign_prefix = format_expr(target).concat(" = ")
        emit_expr_wrapped(val, assign_prefix, "")
        return
    }

    if kind == NodeKind.CompoundAssign {
        let op = np_op.get(node).unwrap()
        let target = np_target.get(node).unwrap()
        let val = np_value.get(node).unwrap()
        let comp_prefix = "{format_expr(target)} {op}= "
        emit_expr_wrapped(val, comp_prefix, "")
        return
    }

    if kind == NodeKind.ExprStmt {
        let val = np_value.get(node).unwrap()
        let val_kind = np_kind.get(val).unwrap()
        if val_kind == NodeKind.IfExpr {
            format_if_stmt(val)
            return
        }
        if val_kind == NodeKind.MatchExpr {
            format_match_stmt(val)
            return
        }
        emit_expr_wrapped(val, "", "")
        return
    }

    if kind == NodeKind.Return {
        let val = np_value.get(node).unwrap()
        if val != -1 {
            emit_expr_wrapped(val, "return ", "")
        } else {
            fmt_emit("return")
        }
        return
    }

    if kind == NodeKind.Break {
        let val = np_value.get(node).unwrap()
        if val != -1 {
            fmt_emit("break {format_expr(val)}")
        } else {
            fmt_emit("break")
        }
        return
    }

    if kind == NodeKind.Continue {
        fmt_emit("continue")
        return
    }

    if kind == NodeKind.IfExpr {
        format_if_stmt(node)
        return
    }

    if kind == NodeKind.MatchExpr {
        format_match_stmt(node)
        return
    }

    if kind == NodeKind.ForIn {
        let var_name = np_var_name.get(node).unwrap()
        let iterable = np_iterable.get(node).unwrap()
        let body = np_body.get(node).unwrap()
        let for_fmt_pat = np_elements.get(node).unwrap()
        let mut for_var_str = var_name
        if for_fmt_pat != -1 {
            for_var_str = format_pattern(for_fmt_pat)
        }
        let for_line = "for {for_var_str} in {format_expr(iterable)} \{"
        if fmt_needs_wrap(for_line) != 0 {
            emit_expr_wrapped(iterable, "for {for_var_str} in ", " \{")
        } else {
            fmt_emit(for_line)
        }
        fmt_indent = fmt_indent + 1
        format_block_body(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
        return
    }

    if kind == NodeKind.WhileLoop {
        let cond = np_condition.get(node).unwrap()
        let body = np_body.get(node).unwrap()
        let while_line = "while {format_expr(cond)} \{"
        if fmt_needs_wrap(while_line) != 0 && np_kind.get(cond).unwrap() == NodeKind.BinOp {
            fmt_emit("while")
            fmt_indent = fmt_indent + 1
            emit_binop_wrapped(cond, "")
            fmt_indent = fmt_indent - 1
            fmt_emit("\{")
        } else {
            fmt_emit(while_line)
        }
        fmt_indent = fmt_indent + 1
        format_block_body(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
        return
    }

    if kind == NodeKind.LoopExpr {
        let body = np_body.get(node).unwrap()
        fmt_emit("loop \{")
        fmt_indent = fmt_indent + 1
        format_block_body(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
        return
    }

    if kind == NodeKind.WithBlock {
        format_with_block(node)
        return
    }

    if kind == NodeKind.Block {
        format_block_body(node)
        return
    }

    // Fallback: treat as expression
    fmt_emit(format_expr(node))
}

pub fn format_if_stmt(node: Int) ! Format.Emit {
    format_if_chain(node, "if")
}

pub fn format_if_chain(node: Int, prefix: Str) ! Format.Emit {
    let cond = np_condition.get(node).unwrap()
    let then_b = np_then_body.get(node).unwrap()
    let else_b = np_else_body.get(node).unwrap()
    let cond_str = format_expr(cond)
    let if_line = "{prefix} {cond_str} \{"
    if fmt_needs_wrap(if_line) != 0 && np_kind.get(cond).unwrap() == NodeKind.BinOp {
        fmt_emit("{prefix}")
        fmt_indent = fmt_indent + 1
        emit_binop_wrapped(cond, "")
        fmt_indent = fmt_indent - 1
        fmt_emit("\{")
    } else {
        fmt_emit(if_line)
    }
    fmt_indent = fmt_indent + 1
    format_block_body(then_b)
    fmt_indent = fmt_indent - 1
    if else_b != -1 {
        let else_stmts = np_stmts.get(else_b).unwrap()
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner).unwrap() == NodeKind.IfExpr {
                format_if_chain(inner, "} else if")
                return
            }
        }
        fmt_emit("} else \{")
        fmt_indent = fmt_indent + 1
        format_block_body(else_b)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else {
        fmt_emit("}")
    }
}

pub fn format_else_if(_node: Int) -> Str {
    ""
}

pub fn format_match_stmt(node: Int) ! Format.Emit {
    let scrut = np_scrutinee.get(node).unwrap()
    let arms_sl = np_arms.get(node).unwrap()
    fmt_emit("match {format_expr(scrut)} \{")
    fmt_indent = fmt_indent + 1
    if arms_sl != -1 {
        let mut i = 0
        while i < sublist_length(arms_sl) {
            format_match_arm(sublist_get(arms_sl, i))
            i = i + 1
        }
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_match_arm(node: Int) ! Format.Emit {
    let pat = np_pattern.get(node).unwrap()
    let guard = np_guard.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    let mut line = format_pattern(pat)
    if guard != -1 {
        line = line.concat(" if ").concat(format_expr(guard))
    }
    line = line.concat(" => ")
    let body_kind = np_kind.get(body).unwrap()
    if body_kind == NodeKind.Block {
        let stmts_sl = np_stmts.get(body).unwrap()
        if stmts_sl != -1 && sublist_length(stmts_sl) == 1 {
            let inner = sublist_get(stmts_sl, 0)
            let ik = np_kind.get(inner).unwrap()
            if ik == NodeKind.ExprStmt {
                fmt_emit(line.concat(format_expr(np_value.get(inner).unwrap())))
                return
            }
            if is_simple_expr_kind(ik) {
                fmt_emit(line.concat(format_expr(inner)))
                return
            }
        }
        fmt_emit(line.concat("\{"))
        fmt_indent = fmt_indent + 1
        format_block_body(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else if body_kind == NodeKind.ExprStmt {
        fmt_emit(line.concat(format_expr(np_value.get(body).unwrap())))
    } else if is_simple_expr_kind(body_kind) {
        fmt_emit(line.concat(format_expr(body)))
    } else {
        fmt_emit(line.concat("\{"))
        fmt_indent = fmt_indent + 1
        format_stmt(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    }
}

pub fn format_with_block(node: Int) ! Format.Emit {
    let handlers_sl = np_handlers.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    let mut line = "with "
    if handlers_sl != -1 {
        let mut i = 0
        while i < sublist_length(handlers_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            let h = sublist_get(handlers_sl, i)
            let hk = np_kind.get(h).unwrap()
            if hk == NodeKind.WithResource {
                let val = np_value.get(h).unwrap()
                let binding = np_name.get(h).unwrap()
                line = line.concat(format_expr(val)).concat(" as ").concat(binding)
            } else {
                line = line.concat(format_expr(h))
            }
            i = i + 1
        }
    }
    fmt_emit(line.concat(" \{"))
    fmt_indent = fmt_indent + 1
    format_block_body(body)
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_block_body(node: Int) ! Format.Emit {
    if node == -1 {
        return
    }
    let stmts_sl = np_stmts.get(node).unwrap()
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        let stmt = sublist_get(stmts_sl, i)
        format_stmt(stmt)
        emit_trailing_comment(stmt)
        i = i + 1
    }
    emit_trailing_comments_block(node)
}

// ── Top-level formatting ────────────────────────────────────────────

pub fn format_fn_sig_suffix(ret: Str, ret_ann: Int, effects_sl: Int) -> Str {
    let mut suffix = ""
    if ret != "" {
        if ret_ann != -1 {
            suffix = suffix.concat(" -> ").concat(format_type_ann(ret_ann))
        } else {
            suffix = suffix.concat(" -> ").concat(ret)
        }
    }
    if effects_sl != -1 && sublist_length(effects_sl) > 0 {
        suffix = suffix.concat(" ! ")
        let mut i = 0
        while i < sublist_length(effects_sl) {
            if i > 0 {
                suffix = suffix.concat(", ")
            }
            suffix = suffix.concat(np_name.get(sublist_get(effects_sl, i)).unwrap())
            i = i + 1
        }
    }
    suffix
}

pub fn format_fn_def(node: Int) ! Format.Emit {
    emit_comments(node)
    let fn_anns_sl = np_handlers.get(node).unwrap()
    if fn_anns_sl != -1 && sublist_length(fn_anns_sl) > 0 {
        let fn_ann_count = sublist_length(fn_anns_sl)
        let mut fn_sorted: List[Int] = []
        let mut fai = 0
        while fai < fn_ann_count {
            fn_sorted.push(sublist_get(fn_anns_sl, fai))
            fai = fai + 1
        }
        let mut fsi = 0
        while fsi < fn_ann_count - 1 {
            let mut fmin = fsi
            let mut fsj = fsi + 1
            while fsj < fn_ann_count {
                if annotation_order(np_name.get(fn_sorted.get(fsj).unwrap()).unwrap()) < annotation_order(np_name.get(fn_sorted.get(fmin).unwrap()).unwrap()) {
                    fmin = fsj
                }
                fsj = fsj + 1
            }
            if fmin != fsi {
                let ftmp = fn_sorted.get(fsi).unwrap()
                fn_sorted.set(fsi, fn_sorted.get(fmin).unwrap())
                fn_sorted.set(fmin, ftmp)
            }
            fsi = fsi + 1
        }
        fai = 0
        while fai < fn_ann_count {
            format_annotation(fn_sorted.get(fai).unwrap())
            fai = fai + 1
        }
    }
    let name = np_name.get(node).unwrap()
    let is_pub = np_is_pub.get(node).unwrap()
    let params_sl = np_params.get(node).unwrap()
    let ret = np_return_type.get(node).unwrap()
    let ret_ann = np_type_ann.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    let effects_sl = np_effects.get(node).unwrap()
    let tparams = np_type_params.get(node).unwrap()

    let mut line = ""
    if is_pub != 0 {
        line = "pub "
    }
    line = line.concat("fn ").concat(name)
    if tparams != -1 && sublist_length(tparams) > 0 {
        line = line.concat("[")
        let mut i = 0
        while i < sublist_length(tparams) {
            if i > 0 {
                line = line.concat(", ")
            }
            let tp = sublist_get(tparams, i)
            line = line.concat(np_name.get(tp).unwrap())
            i = i + 1
        }
        line = line.concat("]")
    }
    line = line.concat("(")
    if params_sl != -1 {
        let mut i = 0
        let mut emitted_dashdash = 0
        while i < sublist_length(params_sl) {
            let pi = sublist_get(params_sl, i)
            let is_kw = np_int_val.get(pi).unwrap()
            if is_kw != 0 && emitted_dashdash == 0 {
                if i > 0 {
                    line = line.concat(", ")
                }
                line = line.concat("-- ")
                emitted_dashdash = 1
            } else if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(format_param(pi))
            i = i + 1
        }
    }
    line = line.concat(")")
    let suffix = format_fn_sig_suffix(ret, ret_ann, effects_sl)
    line = line.concat(suffix)
    if body != -1 {
        let full_line = line.concat(" \{")
        if fmt_needs_wrap(full_line) != 0 && params_sl != -1 && sublist_length(params_sl) > 0 {
            let mut fn_prefix = ""
            if is_pub != 0 {
                fn_prefix = "pub "
            }
            fn_prefix = fn_prefix.concat("fn ").concat(name)
            if tparams != -1 && sublist_length(tparams) > 0 {
                fn_prefix = fn_prefix.concat("[")
                let mut ti = 0
                while ti < sublist_length(tparams) {
                    if ti > 0 {
                        fn_prefix = fn_prefix.concat(", ")
                    }
                    fn_prefix = fn_prefix.concat(np_name.get(sublist_get(tparams, ti)).unwrap())
                    ti = ti + 1
                }
                fn_prefix = fn_prefix.concat("]")
            }
            fmt_emit(fn_prefix.concat("("))
            fmt_indent = fmt_indent + 1
            let mut pi = 0
            let mut wrap_emitted_dd = 0
            while pi < sublist_length(params_sl) {
                let wrap_pn = sublist_get(params_sl, pi)
                let wrap_is_kw = np_int_val.get(wrap_pn).unwrap()
                let mut p_str = ""
                if wrap_is_kw != 0 && wrap_emitted_dd == 0 {
                    p_str = "-- ".concat(format_param(wrap_pn))
                    wrap_emitted_dd = 1
                } else {
                    p_str = format_param(wrap_pn)
                }
                if pi < sublist_length(params_sl) - 1 {
                    fmt_emit(p_str.concat(","))
                } else {
                    fmt_emit(p_str)
                }
                pi = pi + 1
            }
            fmt_indent = fmt_indent - 1
            fmt_emit(")".concat(suffix).concat(" \{"))
        } else {
            fmt_emit(full_line)
        }
        fmt_indent = fmt_indent + 1
        format_block_body(body)
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else {
        if fmt_needs_wrap(line) != 0 && params_sl != -1 && sublist_length(params_sl) > 0 {
            let mut fn_prefix = ""
            if is_pub != 0 {
                fn_prefix = "pub "
            }
            fn_prefix = fn_prefix.concat("fn ").concat(name)
            if tparams != -1 && sublist_length(tparams) > 0 {
                fn_prefix = fn_prefix.concat("[")
                let mut ti = 0
                while ti < sublist_length(tparams) {
                    if ti > 0 {
                        fn_prefix = fn_prefix.concat(", ")
                    }
                    fn_prefix = fn_prefix.concat(np_name.get(sublist_get(tparams, ti)).unwrap())
                    ti = ti + 1
                }
                fn_prefix = fn_prefix.concat("]")
            }
            fmt_emit(fn_prefix.concat("("))
            fmt_indent = fmt_indent + 1
            let mut pi = 0
            let mut wrap2_emitted_dd = 0
            while pi < sublist_length(params_sl) {
                let wrap2_pn = sublist_get(params_sl, pi)
                let wrap2_is_kw = np_int_val.get(wrap2_pn).unwrap()
                let mut p_str = ""
                if wrap2_is_kw != 0 && wrap2_emitted_dd == 0 {
                    p_str = "-- ".concat(format_param(wrap2_pn))
                    wrap2_emitted_dd = 1
                } else {
                    p_str = format_param(wrap2_pn)
                }
                if pi < sublist_length(params_sl) - 1 {
                    fmt_emit(p_str.concat(","))
                } else {
                    fmt_emit(p_str)
                }
                pi = pi + 1
            }
            fmt_indent = fmt_indent - 1
            fmt_emit(")".concat(suffix))
        } else {
            fmt_emit(line)
        }
    }
}

pub fn format_type_def(node: Int) ! Format.Emit {
    emit_comments(node)
    let td_anns_sl = np_handlers.get(node).unwrap()
    if td_anns_sl != -1 && sublist_length(td_anns_sl) > 0 {
        let td_ann_count = sublist_length(td_anns_sl)
        let mut td_sorted: List[Int] = []
        let mut tai = 0
        while tai < td_ann_count {
            td_sorted.push(sublist_get(td_anns_sl, tai))
            tai = tai + 1
        }
        let mut tsi = 0
        while tsi < td_ann_count - 1 {
            let mut tmin = tsi
            let mut tsj = tsi + 1
            while tsj < td_ann_count {
                if annotation_order(np_name.get(td_sorted.get(tsj).unwrap()).unwrap()) < annotation_order(np_name.get(td_sorted.get(tmin).unwrap()).unwrap()) {
                    tmin = tsj
                }
                tsj = tsj + 1
            }
            if tmin != tsi {
                let ttmp = td_sorted.get(tsi).unwrap()
                td_sorted.set(tsi, td_sorted.get(tmin).unwrap())
                td_sorted.set(tmin, ttmp)
            }
            tsi = tsi + 1
        }
        tai = 0
        while tai < td_ann_count {
            format_annotation(td_sorted.get(tai).unwrap())
            tai = tai + 1
        }
    }
    let name = np_name.get(node).unwrap()
    let is_pub = np_is_pub.get(node).unwrap()
    let flds_sl = np_fields.get(node).unwrap()
    let tparams = np_type_params.get(node).unwrap()

    let mut line = ""
    if is_pub != 0 {
        line = "pub "
    }
    line = line.concat("type ").concat(name)
    if tparams != -1 && sublist_length(tparams) > 0 {
        line = line.concat("[")
        let mut i = 0
        while i < sublist_length(tparams) {
            if i > 0 {
                line = line.concat(", ")
            }
            let tp = sublist_get(tparams, i)
            line = line.concat(np_name.get(tp).unwrap())
            i = i + 1
        }
        line = line.concat("]")
    }

    if flds_sl == -1 || sublist_length(flds_sl) == 0 {
        fmt_emit(line)
        return
    }

    let first = sublist_get(flds_sl, 0)
    let first_kind = np_kind.get(first).unwrap()

    if first_kind == NodeKind.TypeVariant {
        fmt_emit(line.concat(" \{"))
        fmt_indent = fmt_indent + 1
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v).unwrap()
            let vflds_sl = np_fields.get(v).unwrap()
            if vflds_sl != -1 && sublist_length(vflds_sl) > 0 {
                let mut vline = vname.concat("(")
                let mut j = 0
                while j < sublist_length(vflds_sl) {
                    if j > 0 {
                        vline = vline.concat(", ")
                    }
                    let vf = sublist_get(vflds_sl, j)
                    let vfn = np_name.get(vf).unwrap()
                    let vft = np_value.get(vf).unwrap()
                    vline = vline.concat(vfn).concat(": ").concat(format_type_ann(vft))
                    j = j + 1
                }
                vline = vline.concat(")")
                if i < sublist_length(flds_sl) - 1 {
                    vline = vline.concat(",")
                }
                fmt_emit(vline)
            } else {
                let mut vline = vname
                if i < sublist_length(flds_sl) - 1 {
                    vline = vline.concat(",")
                }
                fmt_emit(vline)
            }
            i = i + 1
        }
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else if first_kind == NodeKind.TypeField {
        fmt_emit(line.concat(" \{"))
        fmt_indent = fmt_indent + 1
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let f = sublist_get(flds_sl, i)
            let fname = np_name.get(f).unwrap()
            let ftype = np_value.get(f).unwrap()
            let fdefault = np_condition.get(f).unwrap()
            if fdefault != -1 {
                fmt_emit("{fname}: {format_type_ann(ftype)} = {format_expr(fdefault)}")
            } else {
                fmt_emit("{fname}: {format_type_ann(ftype)}")
            }
            i = i + 1
        }
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else {
        fmt_emit(line)
    }
}

pub fn format_trait_def(node: Int) ! Format.Emit {
    emit_comments(node)
    let name = np_name.get(node).unwrap()
    let is_pub = np_is_pub.get(node).unwrap()
    let methods_sl = np_methods.get(node).unwrap()
    let tparams = np_type_params.get(node).unwrap()

    let mut line = ""
    if is_pub != 0 {
        line = "pub "
    }
    line = line.concat("trait ").concat(name)
    if tparams != -1 && sublist_length(tparams) > 0 {
        line = line.concat("[")
        let mut i = 0
        while i < sublist_length(tparams) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(format_type_ann(sublist_get(tparams, i)))
            i = i + 1
        }
        line = line.concat("]")
    }
    line = line.concat(" \{")
    fmt_emit(line)
    fmt_indent = fmt_indent + 1
    if methods_sl != -1 {
        let mut i = 0
        while i < sublist_length(methods_sl) {
            if i > 0 {
                fmt_emit("")
            }
            format_fn_def(sublist_get(methods_sl, i))
            i = i + 1
        }
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_impl_block(node: Int) ! Format.Emit {
    emit_comments(node)
    let trait_name = np_trait_name.get(node).unwrap()
    let type_name = np_name.get(node).unwrap()
    let methods_sl = np_methods.get(node).unwrap()
    let tparams = np_type_params.get(node).unwrap()

    let mut line = "impl ".concat(trait_name)
    if tparams != -1 && sublist_length(tparams) > 0 {
        line = line.concat("[")
        let mut i = 0
        while i < sublist_length(tparams) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(format_type_ann(sublist_get(tparams, i)))
            i = i + 1
        }
        line = line.concat("]")
    }
    if type_name != "" {
        line = line.concat(" for ").concat(type_name)
    }
    line = line.concat(" \{")
    fmt_emit(line)
    fmt_indent = fmt_indent + 1
    if methods_sl != -1 {
        let mut i = 0
        while i < sublist_length(methods_sl) {
            if i > 0 {
                fmt_emit("")
            }
            format_fn_def(sublist_get(methods_sl, i))
            i = i + 1
        }
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_test_block(node: Int) ! Format.Emit {
    emit_comments(node)
    let name = np_name.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    fmt_emit("test \"{name}\" \{")
    fmt_indent = fmt_indent + 1
    format_block_body(body)
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn annotation_order(name: Str) -> Int {
    if name == "mod" { return 0 }
    if name == "capabilities" { return 1 }
    if name == "derive" { return 2 }
    if name == "src" { return 3 }
    if name == "requires" { return 4 }
    if name == "ensures" { return 5 }
    if name == "where" { return 6 }
    if name == "invariant" { return 7 }
    if name == "perf" { return 8 }
    if name == "ffi" { return 9 }
    if name == "trusted" { return 10 }
    if name == "effects" { return 11 }
    if name == "alt" { return 12 }
    if name == "verify" { return 13 }
    if name == "deprecated" { return 14 }
    99
}

pub fn format_annotation(node: Int) ! Format.Emit {
    let name = np_name.get(node).unwrap()
    let args_sl = np_args.get(node).unwrap()
    let mut line = "@".concat(name)
    if args_sl != -1 && sublist_length(args_sl) > 0 {
        line = line.concat("(")
        if name == "requires" || name == "ensures" {
            line = line.concat(format_expr(sublist_get(args_sl, 0)))
        } else {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    line = line.concat(", ")
                }
                let arg_nd = sublist_get(args_sl, i)
                let arg_kind = np_kind.get(arg_nd).unwrap()
                if arg_kind == NodeKind.InterpString {
                    let arg_key = np_name.get(arg_nd).unwrap()
                    if arg_key != "" {
                        line = line.concat(arg_key).concat(": ")
                    }
                    line = line.concat(format_expr(arg_nd))
                } else {
                    line = line.concat(np_name.get(arg_nd).unwrap())
                }
                i = i + 1
            }
        }
        line = line.concat(")")
    }
    fmt_emit(line)
}

pub fn format_import(node: Int) ! Format.Emit {
    emit_comments(node)
    let path = np_str_val.get(node).unwrap()
    let names_sl = np_args.get(node).unwrap()
    let mut line = "import ".concat(path)
    if names_sl != -1 && sublist_length(names_sl) > 0 {
        line = line.concat(" \{ ")
        let mut i = 0
        while i < sublist_length(names_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(np_name.get(sublist_get(names_sl, i)).unwrap())
            i = i + 1
        }
        line = line.concat(" }")
    }
    fmt_emit(line)
}

pub fn format_effect_decl(node: Int) ! Format.Emit {
    emit_comments(node)
    let name = np_name.get(node).unwrap()
    let is_pub = np_is_pub.get(node).unwrap()
    let children_sl = np_elements.get(node).unwrap()

    let mut line = ""
    if is_pub != 0 {
        line = "pub "
    }
    line = line.concat("effect ").concat(name)

    if children_sl == -1 || sublist_length(children_sl) == 0 {
        fmt_emit(line)
        return
    }

    fmt_emit(line.concat(" \{"))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < sublist_length(children_sl) {
        let child = sublist_get(children_sl, i)
        let child_name = np_name.get(child).unwrap()
        let child_ops = np_methods.get(child).unwrap()
        if child_ops != -1 && sublist_length(child_ops) > 0 {
            fmt_emit("effect {child_name} \{")
            fmt_indent = fmt_indent + 1
            let mut j = 0
            while j < sublist_length(child_ops) {
                let op = sublist_get(child_ops, j)
                format_effect_op_sig(op)
                j = j + 1
            }
            fmt_indent = fmt_indent - 1
            fmt_emit("}")
        } else {
            fmt_emit("effect {child_name}")
        }
        i = i + 1
    }
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_effect_op_sig(node: Int) ! Format.Emit {
    let name = np_name.get(node).unwrap()
    let params_sl = np_params.get(node).unwrap()
    let ret = np_return_type.get(node).unwrap()
    let mut line = "fn ".concat(name).concat("(")
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(format_param(sublist_get(params_sl, i)))
            i = i + 1
        }
    }
    line = line.concat(")")
    if ret != "" {
        line = line.concat(" -> ").concat(ret)
    }
    fmt_emit(line)
}

// ── Main entry point ────────────────────────────────────────────────

pub fn format(program: Int) -> Str ! Format.Emit {
    fmt_lines = []
    fmt_indent = 0

    // File-level header comments
    emit_comments(program)

    // Imports
    let imports_sl = np_elements.get(program).unwrap()
    if imports_sl != -1 && sublist_length(imports_sl) > 0 {
        let mut i = 0
        while i < sublist_length(imports_sl) {
            let imp_node = sublist_get(imports_sl, i)
            format_import(imp_node)
            emit_trailing_comment(imp_node)
            i = i + 1
        }
        fmt_emit("")
    }

    // Top-level annotations (on Program node) — sorted by canonical order
    let anns_sl = np_handlers.get(program).unwrap()
    if anns_sl != -1 && sublist_length(anns_sl) > 0 {
        let ann_count = sublist_length(anns_sl)
        let mut sorted_anns: List[Int] = []
        let mut i = 0
        while i < ann_count {
            sorted_anns.push(sublist_get(anns_sl, i))
            i = i + 1
        }
        let mut si = 0
        while si < ann_count - 1 {
            let mut min_idx = si
            let mut sj = si + 1
            while sj < ann_count {
                if annotation_order(np_name.get(sorted_anns.get(sj).unwrap()).unwrap()) < annotation_order(np_name.get(sorted_anns.get(min_idx).unwrap()).unwrap()) {
                    min_idx = sj
                }
                sj = sj + 1
            }
            if min_idx != si {
                let tmp = sorted_anns.get(si).unwrap()
                sorted_anns.set(si, sorted_anns.get(min_idx).unwrap())
                sorted_anns.set(min_idx, tmp)
            }
            si = si + 1
        }
        i = 0
        while i < ann_count {
            format_annotation(sorted_anns.get(i).unwrap())
            i = i + 1
        }
        fmt_emit("")
    }

    // Effect declarations
    let effects_sl = np_args.get(program).unwrap()
    if effects_sl != -1 && sublist_length(effects_sl) > 0 {
        let mut i = 0
        while i < sublist_length(effects_sl) {
            let ed_node = sublist_get(effects_sl, i)
            format_effect_decl(ed_node)
            emit_trailing_comment(ed_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // Type definitions
    let types_sl = np_fields.get(program).unwrap()
    if types_sl != -1 && sublist_length(types_sl) > 0 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let td_node = sublist_get(types_sl, i)
            format_type_def(td_node)
            emit_trailing_comment(td_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // Top-level let bindings
    let lets_sl = np_stmts.get(program).unwrap()
    if lets_sl != -1 && sublist_length(lets_sl) > 0 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            format_stmt(let_node)
            emit_trailing_comment(let_node)
            i = i + 1
        }
        fmt_emit("")
    }

    // Trait definitions
    let traits_sl = np_arms.get(program).unwrap()
    if traits_sl != -1 && sublist_length(traits_sl) > 0 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            let tr_node = sublist_get(traits_sl, i)
            format_trait_def(tr_node)
            emit_trailing_comment(tr_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // Impl blocks
    let impls_sl = np_methods.get(program).unwrap()
    if impls_sl != -1 && sublist_length(impls_sl) > 0 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let impl_node = sublist_get(impls_sl, i)
            format_impl_block(impl_node)
            emit_trailing_comment(impl_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // Function definitions
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 && sublist_length(fns_sl) > 0 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            format_fn_def(fn_node)
            emit_trailing_comment(fn_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // Test blocks
    let tests_sl = np_captures.get(program).unwrap()
    if tests_sl != -1 && sublist_length(tests_sl) > 0 {
        let mut i = 0
        while i < sublist_length(tests_sl) {
            let test_node = sublist_get(tests_sl, i)
            format_test_block(test_node)
            emit_trailing_comment(test_node)
            fmt_emit("")
            i = i + 1
        }
    }

    // EOF trailing comments
    emit_trailing_comments_block(program)

    // Strip trailing blank lines
    while fmt_lines.len() > 0 && fmt_lines.get(fmt_lines.len() - 1).unwrap() == "" {
        fmt_lines.pop()
    }

    // Ensure trailing newline
    fmt_lines.push("")

    fmt_join()
}
