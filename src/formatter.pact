import ast
import parser

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

pub fn fmt_emit(line: Str) {
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

pub fn fmt_emit_raw(line: Str) {
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
    let mut result = ""
    let mut i = 0
    while i < fmt_lines.len() {
        if i > 0 {
            result = result.concat("\n")
        }
        result = result.concat(fmt_lines.get(i))
        i = i + 1
    }
    result
}

// ── Type annotation formatting ──────────────────────────────────────

pub fn format_type_ann(node: Int) -> Str {
    if node == -1 {
        return ""
    }
    let kind = np_kind.get(node)
    if kind != NodeKind.TypeAnn {
        return np_name.get(node)
    }
    let name = np_name.get(node)
    let elems_sl = np_elements.get(node)
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
        let ret = np_return_type.get(node)
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
    let kind = np_kind.get(node)

    if kind == NodeKind.WildcardPattern {
        return "_"
    }
    if kind == NodeKind.IntPattern {
        return np_str_val.get(node)
    }
    if kind == NodeKind.StringPattern {
        return "\"".concat(np_str_val.get(node)).concat("\"")
    }
    if kind == NodeKind.IdentPattern {
        return np_name.get(node)
    }
    if kind == NodeKind.Ident {
        return np_name.get(node)
    }
    if kind == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(node)
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
        let alts_sl = np_elements.get(node)
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
        let lo = np_str_val.get(node)
        let hi = np_name.get(node)
        if np_inclusive.get(node) != 0 {
            return "{lo}..={hi}"
        }
        return "{lo}..{hi}"
    }
    if kind == NodeKind.EnumPattern {
        let ename = np_name.get(node)
        let vname = np_type_name.get(node)
        let flds_sl = np_fields.get(node)
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
        let sname = np_type_name.get(node)
        let flds_sl = np_fields.get(node)
        let has_rest = np_inclusive.get(node)
        let mut result = "{sname} \{"
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                let fld = sublist_get(flds_sl, i)
                let fname = np_name.get(fld)
                let fpat = np_pattern.get(fld)
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
        let name = np_name.get(node)
        let inner = np_pattern.get(node)
        return "{name} as ".concat(format_pattern(inner))
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
    let kind = np_kind.get(child)
    if kind != NodeKind.BinOp {
        return 0
    }
    let child_op = np_op.get(child)
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
    let kind = np_kind.get(node)

    if kind == NodeKind.IntLit {
        let s = np_str_val.get(node)
        if s != "" {
            return s
        }
        return "{np_int_val.get(node)}"
    }

    if kind == NodeKind.FloatLit {
        return np_str_val.get(node)
    }

    if kind == NodeKind.BoolLit {
        if np_int_val.get(node) != 0 {
            return "true"
        }
        return "false"
    }

    if kind == NodeKind.Ident {
        return np_name.get(node)
    }

    if kind == NodeKind.InterpString {
        return format_interp_string(node)
    }

    if kind == NodeKind.BinOp {
        let op = np_op.get(node)
        let left = np_left.get(node)
        let right = np_right.get(node)
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
        let op = np_op.get(node)
        let operand = np_left.get(node)
        if op == "?" {
            return format_expr(operand).concat("?")
        }
        let inner = format_expr(operand)
        let inner_kind = np_kind.get(operand)
        if inner_kind == NodeKind.BinOp {
            return "{op}(".concat(inner).concat(")")
        }
        return op.concat(inner)
    }

    if kind == NodeKind.Call {
        let func = np_left.get(node)
        let args_sl = np_args.get(node)
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
        let obj = np_obj.get(node)
        let method = np_method.get(node)
        let args_sl = np_args.get(node)
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
        let obj = np_obj.get(node)
        let field = np_name.get(node)
        return "{format_expr(obj)}.{field}"
    }

    if kind == NodeKind.IndexExpr {
        let obj = np_obj.get(node)
        let idx = np_index.get(node)
        return "{format_expr(obj)}[{format_expr(idx)}]"
    }

    if kind == NodeKind.TupleLit {
        let elems_sl = np_elements.get(node)
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
        let elems_sl = np_elements.get(node)
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
        let tname = np_type_name.get(node)
        let flds_sl = np_fields.get(node)
        let mut result = "{tname} \{ "
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                if i > 0 {
                    result = result.concat(", ")
                }
                let fld = sublist_get(flds_sl, i)
                let fname = np_name.get(fld)
                let fval = np_value.get(fld)
                result = result.concat("{fname}: {format_expr(fval)}")
                i = i + 1
            }
        }
        return result.concat(" }")
    }

    if kind == NodeKind.RangeLit {
        let start = np_start.get(node)
        let end = np_end.get(node)
        if np_inclusive.get(node) != 0 {
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
        return "async.scope ".concat(format_block_inline(np_body.get(node)))
    }

    if kind == NodeKind.AsyncSpawn {
        return "async.spawn ".concat(format_block_inline(np_body.get(node)))
    }

    if kind == NodeKind.AwaitExpr {
        return format_expr(np_obj.get(node)).concat(".await")
    }

    if kind == NodeKind.ChannelNew {
        let tparams = np_type_params.get(node)
        let args_sl = np_args.get(node)
        let mut result = "channel.new"
        if tparams != -1 && sublist_length(tparams) > 0 {
            result = result.concat("[")
            let mut i = 0
            while i < sublist_length(tparams) {
                if i > 0 {
                    result = result.concat(", ")
                }
                result = result.concat(np_name.get(sublist_get(tparams, i)))
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

    ""
}

pub fn format_interp_string(node: Int) -> Str {
    let parts_sl = np_elements.get(node)
    if parts_sl == -1 {
        return "\"\""
    }
    let mut result = "\""
    let mut i = 0
    while i < sublist_length(parts_sl) {
        let part = sublist_get(parts_sl, i)
        let pk = np_kind.get(part)
        if pk == NodeKind.Ident && np_str_val.get(part) == np_name.get(part) {
            result = result.concat(np_str_val.get(part))
        } else {
            result = result.concat("\{").concat(format_expr(part)).concat("}")
        }
        i = i + 1
    }
    result.concat("\"")
}

pub fn format_closure_inline(node: Int) -> Str {
    let params_sl = np_params.get(node)
    let body = np_body.get(node)
    let ret = np_return_type.get(node)
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
    let name = np_name.get(node)
    let type_name = np_type_name.get(node)
    let is_mut = np_is_mut.get(node)
    let type_ann = np_type_ann.get(node)
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
    let stmts_sl = np_stmts.get(node)
    if stmts_sl == -1 || sublist_length(stmts_sl) == 0 {
        return "\{ }"
    }
    if sublist_length(stmts_sl) == 1 {
        let stmt = sublist_get(stmts_sl, 0)
        let sk = np_kind.get(stmt)
        if sk == NodeKind.ExprStmt {
            let inner = np_value.get(stmt)
            return "\{ ".concat(format_expr(inner)).concat(" }")
        }
        if sk == NodeKind.Return {
            let val = np_value.get(stmt)
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
    let cond = np_condition.get(node)
    let then_b = np_then_body.get(node)
    let else_b = np_else_body.get(node)
    let mut result = "if ".concat(format_expr(cond)).concat(" ").concat(format_block_inline(then_b))
    if else_b != -1 {
        let else_stmts = np_stmts.get(else_b)
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner) == NodeKind.IfExpr {
                result = result.concat(" else ").concat(format_if_inline(inner))
                return result
            }
        }
        result = result.concat(" else ").concat(format_block_inline(else_b))
    }
    result
}

pub fn format_match_inline(node: Int) -> Str {
    return "match ".concat(format_expr(np_scrutinee.get(node))).concat(" \{ ... }")
}

pub fn format_handler_inline(node: Int) -> Str {
    let name = np_name.get(node)
    return "handler {name} \{ ... }"
}

// ── Wrapped emission helpers ────────────────────────────────────────

pub fn emit_call_wrapped(node: Int, prefix: Str) {
    let kind = np_kind.get(node)
    if kind == NodeKind.Call {
        let func = np_left.get(node)
        let args_sl = np_args.get(node)
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
        let obj = np_obj.get(node)
        let method = np_method.get(node)
        let args_sl = np_args.get(node)
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

pub fn emit_list_wrapped(node: Int, prefix: Str) {
    let elems_sl = np_elements.get(node)
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

pub fn emit_struct_lit_wrapped(node: Int, prefix: Str) {
    let tname = np_type_name.get(node)
    let flds_sl = np_fields.get(node)
    if flds_sl == -1 || sublist_length(flds_sl) == 0 {
        fmt_emit(prefix.concat(tname).concat(" \{ }"))
        return
    }
    fmt_emit(prefix.concat(tname).concat(" \{"))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let fld = sublist_get(flds_sl, i)
        let fname = np_name.get(fld)
        let fval = np_value.get(fld)
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

pub fn emit_binop_wrapped(node: Int, prefix: Str) {
    binop_parts = []
    binop_ops = []
    flatten_binop_chain(node)
    if binop_parts.len() == 0 {
        fmt_emit(prefix.concat(format_expr(node)))
        return
    }
    fmt_emit(prefix.concat(binop_parts.get(0)))
    fmt_indent = fmt_indent + 1
    let mut i = 0
    while i < binop_ops.len() {
        fmt_emit("{binop_ops.get(i)} {binop_parts.get(i + 1)}")
        i = i + 1
    }
    fmt_indent = fmt_indent - 1
}

fn flatten_binop_chain(node: Int) {
    let kind = np_kind.get(node)
    if kind != NodeKind.BinOp {
        binop_parts.push(format_expr(node))
        return
    }
    let op = np_op.get(node)
    let left = np_left.get(node)
    let right = np_right.get(node)
    let left_kind = np_kind.get(left)
    if left_kind == NodeKind.BinOp && np_op.get(left) == op {
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

pub fn emit_method_chain_wrapped(node: Int, prefix: Str) {
    let mut chain: List[Int] = []
    let mut cur = node
    while np_kind.get(cur) == NodeKind.MethodCall {
        chain.push(cur)
        cur = np_obj.get(cur)
    }
    let base_str = format_expr(cur)
    fmt_emit(prefix.concat(base_str))
    fmt_indent = fmt_indent + 1
    let mut i = chain.len() - 1
    while i >= 0 {
        let mc = chain.get(i)
        let method = np_method.get(mc)
        let args_sl = np_args.get(mc)
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
    if np_kind.get(node) != NodeKind.MethodCall {
        return 0
    }
    let obj = np_obj.get(node)
    if np_kind.get(obj) == NodeKind.MethodCall {
        return 1
    }
    0
}

pub fn chain_depth(node: Int) -> Int {
    let mut depth = 0
    let mut cur = node
    while np_kind.get(cur) == NodeKind.MethodCall {
        depth = depth + 1
        cur = np_obj.get(cur)
    }
    depth
}

pub fn emit_expr_wrapped(node: Int, prefix: Str, suffix: Str) {
    let expr_str = format_expr(node)
    let full = prefix.concat(expr_str).concat(suffix)
    if fmt_needs_wrap(full) == 0 {
        fmt_emit(full)
        return
    }
    let kind = np_kind.get(node)
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

pub fn emit_comments(node: Int) {
    let doc = np_doc_comment.get(node)
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
    let leading = np_leading_comments.get(node)
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

pub fn format_stmt(node: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)

    emit_comments(node)

    if kind == NodeKind.LetBinding {
        let name = np_name.get(node)
        let is_mut = np_is_mut.get(node)
        let is_pub = np_is_pub.get(node)
        let val = np_value.get(node)
        let type_ann = np_target.get(node)
        let mut prefix = ""
        if is_pub != 0 {
            prefix = "pub "
        }
        prefix = prefix.concat("let ")
        if is_mut != 0 {
            prefix = prefix.concat("mut ")
        }
        prefix = prefix.concat(name)
        if type_ann != -1 {
            prefix = prefix.concat(": ").concat(format_type_ann(type_ann))
        }
        prefix = prefix.concat(" = ")
        emit_expr_wrapped(val, prefix, "")
        return
    }

    if kind == NodeKind.Assignment {
        let target = np_target.get(node)
        let val = np_value.get(node)
        let assign_prefix = format_expr(target).concat(" = ")
        emit_expr_wrapped(val, assign_prefix, "")
        return
    }

    if kind == NodeKind.CompoundAssign {
        let op = np_op.get(node)
        let target = np_target.get(node)
        let val = np_value.get(node)
        let comp_prefix = "{format_expr(target)} {op}= "
        emit_expr_wrapped(val, comp_prefix, "")
        return
    }

    if kind == NodeKind.ExprStmt {
        let val = np_value.get(node)
        let val_kind = np_kind.get(val)
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
        let val = np_value.get(node)
        if val != -1 {
            emit_expr_wrapped(val, "return ", "")
        } else {
            fmt_emit("return")
        }
        return
    }

    if kind == NodeKind.Break {
        let val = np_value.get(node)
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
        let var_name = np_var_name.get(node)
        let iterable = np_iterable.get(node)
        let body = np_body.get(node)
        let for_line = "for {var_name} in {format_expr(iterable)} \{"
        if fmt_needs_wrap(for_line) != 0 {
            emit_expr_wrapped(iterable, "for {var_name} in ", " \{")
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
        let cond = np_condition.get(node)
        let body = np_body.get(node)
        let while_line = "while {format_expr(cond)} \{"
        if fmt_needs_wrap(while_line) != 0 && np_kind.get(cond) == NodeKind.BinOp {
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
        let body = np_body.get(node)
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

pub fn format_if_stmt(node: Int) {
    format_if_chain(node, "if")
}

pub fn format_if_chain(node: Int, prefix: Str) {
    let cond = np_condition.get(node)
    let then_b = np_then_body.get(node)
    let else_b = np_else_body.get(node)
    let cond_str = format_expr(cond)
    let if_line = "{prefix} {cond_str} \{"
    if fmt_needs_wrap(if_line) != 0 && np_kind.get(cond) == NodeKind.BinOp {
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
        let else_stmts = np_stmts.get(else_b)
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner) == NodeKind.IfExpr {
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

pub fn format_else_if(node: Int) -> Str {
    ""
}

pub fn format_match_stmt(node: Int) {
    let scrut = np_scrutinee.get(node)
    let arms_sl = np_arms.get(node)
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

pub fn format_match_arm(node: Int) {
    let pat = np_pattern.get(node)
    let guard = np_guard.get(node)
    let body = np_body.get(node)
    let mut line = format_pattern(pat)
    if guard != -1 {
        line = line.concat(" if ").concat(format_expr(guard))
    }
    line = line.concat(" => ")
    let body_kind = np_kind.get(body)
    if body_kind == NodeKind.Block {
        let stmts_sl = np_stmts.get(body)
        if stmts_sl != -1 && sublist_length(stmts_sl) == 1 {
            let inner = sublist_get(stmts_sl, 0)
            let ik = np_kind.get(inner)
            if ik == NodeKind.ExprStmt {
                fmt_emit(line.concat(format_expr(np_value.get(inner))))
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
        fmt_emit(line.concat(format_expr(np_value.get(body))))
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

pub fn format_with_block(node: Int) {
    let handlers_sl = np_handlers.get(node)
    let body = np_body.get(node)
    let mut line = "with "
    if handlers_sl != -1 {
        let mut i = 0
        while i < sublist_length(handlers_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            let h = sublist_get(handlers_sl, i)
            let hk = np_kind.get(h)
            if hk == NodeKind.WithResource {
                let val = np_value.get(h)
                let binding = np_name.get(h)
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

pub fn format_block_body(node: Int) {
    if node == -1 {
        return
    }
    let stmts_sl = np_stmts.get(node)
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        format_stmt(sublist_get(stmts_sl, i))
        i = i + 1
    }
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
            suffix = suffix.concat(np_name.get(sublist_get(effects_sl, i)))
            i = i + 1
        }
    }
    suffix
}

pub fn format_fn_def(node: Int) {
    emit_comments(node)
    let name = np_name.get(node)
    let is_pub = np_is_pub.get(node)
    let params_sl = np_params.get(node)
    let ret = np_return_type.get(node)
    let ret_ann = np_type_ann.get(node)
    let body = np_body.get(node)
    let effects_sl = np_effects.get(node)
    let tparams = np_type_params.get(node)

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
            line = line.concat(np_name.get(tp))
            i = i + 1
        }
        line = line.concat("]")
    }
    line = line.concat("(")
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
                    fn_prefix = fn_prefix.concat(np_name.get(sublist_get(tparams, ti)))
                    ti = ti + 1
                }
                fn_prefix = fn_prefix.concat("]")
            }
            fmt_emit(fn_prefix.concat("("))
            fmt_indent = fmt_indent + 1
            let mut pi = 0
            while pi < sublist_length(params_sl) {
                let p_str = format_param(sublist_get(params_sl, pi))
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
                    fn_prefix = fn_prefix.concat(np_name.get(sublist_get(tparams, ti)))
                    ti = ti + 1
                }
                fn_prefix = fn_prefix.concat("]")
            }
            fmt_emit(fn_prefix.concat("("))
            fmt_indent = fmt_indent + 1
            let mut pi = 0
            while pi < sublist_length(params_sl) {
                let p_str = format_param(sublist_get(params_sl, pi))
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

pub fn format_type_def(node: Int) {
    emit_comments(node)
    let name = np_name.get(node)
    let is_pub = np_is_pub.get(node)
    let flds_sl = np_fields.get(node)
    let tparams = np_type_params.get(node)

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
            line = line.concat(np_name.get(tp))
            i = i + 1
        }
        line = line.concat("]")
    }

    if flds_sl == -1 || sublist_length(flds_sl) == 0 {
        fmt_emit(line)
        return
    }

    let first = sublist_get(flds_sl, 0)
    let first_kind = np_kind.get(first)

    if first_kind == NodeKind.TypeVariant {
        fmt_emit(line.concat(" \{"))
        fmt_indent = fmt_indent + 1
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v)
            let vflds_sl = np_fields.get(v)
            if vflds_sl != -1 && sublist_length(vflds_sl) > 0 {
                let mut vline = vname.concat("(")
                let mut j = 0
                while j < sublist_length(vflds_sl) {
                    if j > 0 {
                        vline = vline.concat(", ")
                    }
                    let vf = sublist_get(vflds_sl, j)
                    let vfn = np_name.get(vf)
                    let vft = np_value.get(vf)
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
            let fname = np_name.get(f)
            let ftype = np_value.get(f)
            fmt_emit("{fname}: {format_type_ann(ftype)}")
            i = i + 1
        }
        fmt_indent = fmt_indent - 1
        fmt_emit("}")
    } else {
        fmt_emit(line)
    }
}

pub fn format_trait_def(node: Int) {
    emit_comments(node)
    let name = np_name.get(node)
    let is_pub = np_is_pub.get(node)
    let methods_sl = np_methods.get(node)
    let tparams = np_type_params.get(node)

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

pub fn format_impl_block(node: Int) {
    emit_comments(node)
    let trait_name = np_trait_name.get(node)
    let type_name = np_name.get(node)
    let methods_sl = np_methods.get(node)
    let tparams = np_type_params.get(node)

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

pub fn format_test_block(node: Int) {
    emit_comments(node)
    let name = np_name.get(node)
    let body = np_body.get(node)
    fmt_emit("test \"{name}\" \{")
    fmt_indent = fmt_indent + 1
    format_block_body(body)
    fmt_indent = fmt_indent - 1
    fmt_emit("}")
}

pub fn format_annotation(node: Int) {
    let name = np_name.get(node)
    let args_sl = np_args.get(node)
    let mut line = "@".concat(name)
    if args_sl != -1 && sublist_length(args_sl) > 0 {
        line = line.concat("(")
        let mut i = 0
        while i < sublist_length(args_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(np_name.get(sublist_get(args_sl, i)))
            i = i + 1
        }
        line = line.concat(")")
    }
    fmt_emit(line)
}

pub fn format_import(node: Int) {
    emit_comments(node)
    let path = np_str_val.get(node)
    let names_sl = np_args.get(node)
    let mut line = "import ".concat(path)
    if names_sl != -1 && sublist_length(names_sl) > 0 {
        line = line.concat(" \{ ")
        let mut i = 0
        while i < sublist_length(names_sl) {
            if i > 0 {
                line = line.concat(", ")
            }
            line = line.concat(np_name.get(sublist_get(names_sl, i)))
            i = i + 1
        }
        line = line.concat(" }")
    }
    fmt_emit(line)
}

pub fn format_effect_decl(node: Int) {
    emit_comments(node)
    let name = np_name.get(node)
    let is_pub = np_is_pub.get(node)
    let children_sl = np_elements.get(node)

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
        let child_name = np_name.get(child)
        let child_ops = np_methods.get(child)
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

pub fn format_effect_op_sig(node: Int) {
    let name = np_name.get(node)
    let params_sl = np_params.get(node)
    let ret = np_return_type.get(node)
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

pub fn format(program: Int) -> Str {
    fmt_lines = []
    fmt_indent = 0

    // Imports
    let imports_sl = np_elements.get(program)
    if imports_sl != -1 && sublist_length(imports_sl) > 0 {
        let mut i = 0
        while i < sublist_length(imports_sl) {
            format_import(sublist_get(imports_sl, i))
            i = i + 1
        }
        fmt_emit("")
    }

    // Top-level annotations (on Program node)
    let anns_sl = np_handlers.get(program)
    if anns_sl != -1 && sublist_length(anns_sl) > 0 {
        let mut i = 0
        while i < sublist_length(anns_sl) {
            format_annotation(sublist_get(anns_sl, i))
            i = i + 1
        }
        fmt_emit("")
    }

    // Effect declarations
    let effects_sl = np_args.get(program)
    if effects_sl != -1 && sublist_length(effects_sl) > 0 {
        let mut i = 0
        while i < sublist_length(effects_sl) {
            format_effect_decl(sublist_get(effects_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Type definitions
    let types_sl = np_fields.get(program)
    if types_sl != -1 && sublist_length(types_sl) > 0 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            format_type_def(sublist_get(types_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Top-level let bindings
    let lets_sl = np_stmts.get(program)
    if lets_sl != -1 && sublist_length(lets_sl) > 0 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            format_stmt(sublist_get(lets_sl, i))
            i = i + 1
        }
        fmt_emit("")
    }

    // Trait definitions
    let traits_sl = np_arms.get(program)
    if traits_sl != -1 && sublist_length(traits_sl) > 0 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            format_trait_def(sublist_get(traits_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Impl blocks
    let impls_sl = np_methods.get(program)
    if impls_sl != -1 && sublist_length(impls_sl) > 0 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            format_impl_block(sublist_get(impls_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Function definitions
    let fns_sl = np_params.get(program)
    if fns_sl != -1 && sublist_length(fns_sl) > 0 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            format_fn_def(sublist_get(fns_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Test blocks
    let tests_sl = np_captures.get(program)
    if tests_sl != -1 && sublist_length(tests_sl) > 0 {
        let mut i = 0
        while i < sublist_length(tests_sl) {
            format_test_block(sublist_get(tests_sl, i))
            fmt_emit("")
            i = i + 1
        }
    }

    // Strip trailing blank lines
    while fmt_lines.len() > 0 && fmt_lines.get(fmt_lines.len() - 1) == "" {
        fmt_lines.pop()
    }

    // Ensure trailing newline
    fmt_lines.push("")

    fmt_join()
}
