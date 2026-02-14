import codegen_types
import diagnostics

// codegen_expr.pact — Expression codegen, closures, capture analysis

// ── Expression codegen ──────────────────────────────────────────────
// Returns (expr_str, type) packed into parallel result slots.
// Since we can't return tuples in the C backend, we use mutable globals.

pub let mut expr_result_str: Str = ""
pub let mut expr_result_type: Int = 0
pub let mut expr_closure_sig: Str = ""
pub let mut expr_option_inner: Int = -1
pub let mut expr_result_ok_type: Int = -1
pub let mut expr_result_err_type: Int = -1
pub let mut expr_list_elem_type: Int = -1
pub let mut expr_iter_next_fn: Str = ""

// Helper output for iter_from_source
pub let mut ifs_iter_var: Str = ""
pub let mut ifs_next_fn: Str = ""
pub let mut ifs_elem_type: Int = 0
pub let mut ifs_opt_type: Str = ""

// Convert a CT_LIST or CT_ITERATOR source into a uniform iterator representation.
// Sets ifs_iter_var (C var name of the iterator struct on the stack),
// ifs_next_fn (C function name to call next), ifs_elem_type, ifs_opt_type.
pub fn iter_from_source(obj_str: Str, obj_type: Int) {
    if obj_type == CT_LIST {
        let elem_type = get_list_elem_type(obj_str)
        ensure_iter_type(elem_type)
        let tag = c_type_tag(elem_type)
        let li_type = list_iter_c_type(elem_type)
        let iter_var = fresh_temp("__src_iter_")
        emit_line("{li_type} {iter_var} = pact_list_into_iter_{tag}({obj_str});")
        ifs_iter_var = iter_var
        ifs_next_fn = "{li_type}_next"
        ifs_elem_type = elem_type
        ifs_opt_type = option_c_type(elem_type)
    } else {
        ifs_iter_var = obj_str
        ifs_next_fn = get_var_iter_next_fn(obj_str)
        ifs_elem_type = get_var_iterator_inner(obj_str)
        ifs_opt_type = option_c_type(ifs_elem_type)
    }
}

pub fn emit_expr(node: Int) {
    let kind = np_kind.get(node)

    if kind == NodeKind.IntLit {
        let s = np_str_val.get(node)
        if s == "" {
            expr_result_str = "{np_int_val.get(node)}"
        } else {
            expr_result_str = s
        }
        expr_result_type = CT_INT
        return
    }

    if kind == NodeKind.FloatLit {
        expr_result_str = np_str_val.get(node)
        expr_result_type = CT_FLOAT
        return
    }

    if kind == NodeKind.BoolLit {
        if np_int_val.get(node) != 0 {
            expr_result_str = "1"
        } else {
            expr_result_str = "0"
        }
        expr_result_type = CT_BOOL
        return
    }

    if kind == NodeKind.Ident {
        let name = np_name.get(node)
        if name == "None" {
            ensure_option_type(CT_INT)
            let opt_type = option_c_type(CT_INT)
            expr_result_str = "({opt_type})\{.tag = 0}"
            expr_result_type = CT_OPTION
            expr_option_inner = CT_INT
            return
        }
        let variant_enum2 = resolve_variant(name)
        if variant_enum2 != "" {
            if is_data_enum(variant_enum2) != 0 {
                let tag = get_variant_tag(variant_enum2, name)
                expr_result_str = "(pact_{variant_enum2})\{.tag = {tag}}"
                expr_result_type = CT_INT
                return
            }
            expr_result_str = "pact_{variant_enum2}_{name}"
            expr_result_type = CT_INT
            return
        }
        let cap_idx = get_capture_index(name)
        if cap_idx >= 0 {
            let cap_entry = closure_captures.get(cg_closure_cap_start + cap_idx)
            if cap_entry.is_mut != 0 {
                expr_result_str = "(*{name}_cell)"
                expr_result_type = cap_entry.ctype
                return
            }
            expr_result_str = capture_cast_expr(cap_idx)
            expr_result_type = cap_entry.ctype
            return
        }
        if is_mut_captured(name) != 0 {
            expr_result_str = "(*{name}_cell)"
            expr_result_type = get_var_type(name)
            return
        }
        let alias = get_var_alias(name)
        if alias != "" {
            expr_result_str = alias
        } else {
            expr_result_str = name
        }
        expr_result_type = get_var_type(name)
        if expr_result_type == CT_OPTION {
            expr_option_inner = get_var_option_inner(name)
        }
        if expr_result_type == CT_RESULT {
            expr_result_ok_type = get_var_result_ok(name)
            expr_result_err_type = get_var_result_err(name)
        }
        if expr_result_type == CT_ITERATOR {
            expr_iter_next_fn = get_var_iter_next_fn(name)
        }
        return
    }

    if kind == NodeKind.BinOp {
        emit_binop(node)
        return
    }

    if kind == NodeKind.UnaryOp {
        emit_unaryop(node)
        return
    }

    if kind == NodeKind.Call {
        emit_call(node)
        return
    }

    if kind == NodeKind.MethodCall {
        emit_method_call(node)
        return
    }

    if kind == NodeKind.InterpString {
        emit_interp_string(node)
        return
    }

    if kind == NodeKind.IfExpr {
        emit_if_expr(node)
        return
    }

    if kind == NodeKind.FieldAccess {
        let fa_obj = np_obj.get(node)
        let fa_field = np_name.get(node)
        if np_kind.get(fa_obj) == NodeKind.Ident {
            let obj_name = np_name.get(fa_obj)
            if is_enum_type(obj_name) != 0 {
                if is_data_enum(obj_name) != 0 {
                    let tag = get_variant_tag(obj_name, fa_field)
                    expr_result_str = "(pact_{obj_name})\{.tag = {tag}}"
                    expr_result_type = CT_INT
                    return
                }
                expr_result_str = "pact_{obj_name}_{fa_field}"
                expr_result_type = CT_INT
                return
            }
        }
        emit_expr(fa_obj)
        let obj_str = expr_result_str
        expr_result_str = "{obj_str}.{fa_field}"
        let mut fa_type = CT_VOID
        let struct_type = get_var_struct(obj_str)
        if struct_type != "" {
            fa_type = get_struct_field_type(struct_type, fa_field)
            let fa_stype = get_struct_field_stype(struct_type, fa_field)
            if fa_stype != "" {
                set_var_struct(expr_result_str, fa_stype)
            }
        }
        expr_result_type = fa_type
        return
    }

    if kind == NodeKind.IndexExpr {
        emit_expr(np_obj.get(node))
        let obj_str = expr_result_str
        let obj_type = expr_result_type
        emit_expr(np_index.get(node))
        let idx_str = expr_result_str
        if obj_type == CT_STRING {
            expr_result_str = "pact_str_char_at({obj_str}, {idx_str})"
            expr_result_type = CT_INT
        } else {
            expr_result_str = "{obj_str}[{idx_str}]"
            expr_result_type = CT_INT
        }
        return
    }

    if kind == NodeKind.ListLit {
        emit_list_lit(node)
        return
    }

    if kind == NodeKind.RangeLit {
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    if kind == NodeKind.MatchExpr {
        emit_match_expr(node)
        return
    }

    if kind == NodeKind.Block {
        emit_block_expr(node)
        return
    }

    if kind == NodeKind.Return {
        if np_value.get(node) != -1 {
            emit_expr(np_value.get(node))
            let val_str = expr_result_str
            emit_line("return {val_str};")
        } else {
            emit_line("return;")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    if kind == NodeKind.StructLit {
        emit_struct_lit(node)
        return
    }

    if kind == NodeKind.Closure {
        emit_closure(node)
        return
    }

    if kind == NodeKind.HandlerExpr {
        emit_handler_expr(node)
        return
    }

    if kind == NodeKind.AwaitExpr {
        emit_await_expr(node)
        return
    }

    if kind == NodeKind.AsyncScope {
        emit_async_scope(node)
        return
    }

    if kind == NodeKind.ChannelNew {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let cap_str = expr_result_str
            expr_result_str = "pact_channel_new({cap_str})"
        } else {
            expr_result_str = "pact_channel_new(16)"
        }
        expr_result_type = CT_CHANNEL
        return
    }

    expr_result_str = "0"
    expr_result_type = CT_VOID
}

pub fn emit_handler_expr(node: Int) {
    let effect_name = np_name.get(node)
    let methods_sl = np_methods.get(node)
    let handler_idx = cg_temp_counter
    cg_temp_counter = cg_temp_counter + 1

    let mut vtable_type = ""
    let mut vtable_field = ""
    if effect_name == "IO" || effect_name == "IO.Print" || effect_name == "IO.Log" {
        vtable_type = "pact_io_vtable"
        vtable_field = "io"
    } else if effect_name == "FS" || effect_name == "FS.Read" || effect_name == "FS.Write" || effect_name == "FS.Delete" || effect_name == "FS.Watch" {
        vtable_type = "pact_fs_vtable"
        vtable_field = "fs"
    } else if effect_name == "DB" || effect_name == "DB.Read" || effect_name == "DB.Write" || effect_name == "DB.Admin" {
        vtable_type = "pact_db_vtable"
        vtable_field = "db"
    } else if effect_name == "Net" || effect_name == "Net.Connect" || effect_name == "Net.Listen" || effect_name == "Net.DNS" {
        vtable_type = "pact_net_vtable"
        vtable_field = "net"
    } else if effect_name == "Crypto" || effect_name == "Crypto.Hash" || effect_name == "Crypto.Sign" || effect_name == "Crypto.Encrypt" || effect_name == "Crypto.Decrypt" {
        vtable_type = "pact_crypto_vtable"
        vtable_field = "crypto"
    } else if effect_name == "Rand" {
        vtable_type = "pact_rand_vtable"
        vtable_field = "rand"
    } else if effect_name == "Time" || effect_name == "Time.Read" || effect_name == "Time.Sleep" {
        vtable_type = "pact_time_vtable"
        vtable_field = "time"
    } else if effect_name == "Env" || effect_name == "Env.Read" || effect_name == "Env.Write" {
        vtable_type = "pact_env_vtable"
        vtable_field = "env"
    } else if effect_name == "Process" || effect_name == "Process.Spawn" || effect_name == "Process.Signal" {
        vtable_type = "pact_process_vtable"
        vtable_field = "process"
    }

    let mut is_user_effect = 0
    if vtable_type == "" {
        let mut uei = 0
        while uei < ue_effects.len() {
            let ue = ue_effects.get(uei)
            if effect_name == ue.name || effect_name.starts_with("{ue.name}.") {
                vtable_type = "pact_ue_{ue.handle}_vtable"
                vtable_field = ue.handle
                is_user_effect = 1
                break
            }
            uei = uei + 1
        }
    }

    if vtable_type == "" {
        emit_line("/* handler for unknown effect: {effect_name} */")
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // Emit a static global for the saved outer vtable (for default delegation)
    let outer_ptr_name = "__handler_{handler_idx}_outer"
    cg_closure_defs.push("static {vtable_type}* {outer_ptr_name} = NULL;")
    cg_closure_defs.push("")

    if methods_sl != -1 && sublist_length(methods_sl) > 0 {
        let mut mi = 0
        while mi < sublist_length(methods_sl) {
            let m = sublist_get(methods_sl, mi)
            let mname = np_name.get(m)
            let static_name = "__handler_{handler_idx}_{mname}"
            let mut param_str = ""
            let params_sl = np_params.get(m)
            if params_sl != -1 {
                let mut pi = 0
                while pi < sublist_length(params_sl) {
                    if pi > 0 {
                        param_str = param_str.concat(", ")
                    }
                    let p = sublist_get(params_sl, pi)
                    let pname = np_name.get(p)
                    let ptype = np_type_name.get(p)
                    let ct = type_from_name(ptype)
                    param_str = param_str.concat("{c_type_str(ct)} {pname}")
                    pi = pi + 1
                }
            }
            if param_str == "" {
                param_str = "void"
            }
            let ret_str = np_return_type.get(m)
            let ret_type = type_from_name(ret_str)
            let ret_c = c_type_str(ret_type)
            let fn_line = "static {ret_c} {static_name}({param_str}) \{"
            cg_closure_defs.push(fn_line)
            let saved_lines = cg_lines
            let saved_indent = cg_indent
            let saved_in_handler = cg_in_handler_body
            let saved_handler_vt = cg_handler_body_vtable_type
            let saved_handler_field = cg_handler_body_field
            let saved_handler_ue = cg_handler_body_is_ue
            let saved_handler_hidx = cg_handler_body_idx
            cg_lines = []
            cg_indent = 1
            cg_in_handler_body = 1
            cg_handler_body_vtable_type = vtable_type
            cg_handler_body_field = vtable_field
            cg_handler_body_is_ue = is_user_effect
            cg_handler_body_idx = handler_idx
            push_scope()
            if params_sl != -1 {
                let mut pi = 0
                while pi < sublist_length(params_sl) {
                    let p = sublist_get(params_sl, pi)
                    let pname = np_name.get(p)
                    let ptype = np_type_name.get(p)
                    set_var(pname, type_from_name(ptype), 0)
                    pi = pi + 1
                }
            }
            emit_fn_body(np_body.get(m), ret_type)
            pop_scope()
            let mut li = 0
            while li < cg_lines.len() {
                cg_closure_defs.push(cg_lines.get(li))
                li = li + 1
            }
            cg_closure_defs.push("}")
            cg_closure_defs.push("")
            cg_lines = saved_lines
            cg_indent = saved_indent
            cg_in_handler_body = saved_in_handler
            cg_handler_body_vtable_type = saved_handler_vt
            cg_handler_body_field = saved_handler_field
            cg_handler_body_is_ue = saved_handler_ue
            cg_handler_body_idx = saved_handler_hidx
            mi = mi + 1
        }
    }

    // Save current vtable as outer before installing new handler
    let vt_name = "__handler_vt_{handler_idx}"
    if is_user_effect != 0 {
        emit_line("{outer_ptr_name} = __pact_ue_{vtable_field};")
    } else {
        emit_line("{outer_ptr_name} = __pact_ctx.{vtable_field};")
    }
    emit_line("{vtable_type} {vt_name} = {vtable_type}_default;")
    if methods_sl != -1 {
        let mut mi = 0
        while mi < sublist_length(methods_sl) {
            let m = sublist_get(methods_sl, mi)
            let mname = np_name.get(m)
            let static_name = "__handler_{handler_idx}_{mname}"
            emit_line("{vt_name}.{mname} = {static_name};")
            mi = mi + 1
        }
    }
    expr_result_str = vt_name
    expr_result_type = CT_VOID
    cg_handler_vtable_field = vtable_field
    cg_handler_is_user_effect = is_user_effect
}

pub fn emit_async_spawn_closure(closure_node: Int, wrapper_idx: Int, wrapper_name: Str, task_fn_name: Str) {
    let cl_params_sl = np_params.get(closure_node)
    let captures = analyze_captures(np_body.get(closure_node), cl_params_sl)
    let cap_start = closure_captures.len()
    let mut cap_i = 0
    while cap_i < captures.len() {
        let cap_ct = get_var_type(captures.get(cap_i))
        let cap_mut = if is_mut_captured(captures.get(cap_i)) != 0 { 1 } else { 0 }
        closure_captures.push(CaptureEntry { name: captures.get(cap_i), ctype: cap_ct, is_mut: cap_mut })
        cap_i = cap_i + 1
    }
    closure_cap_infos.push(ClosureCapInfo { start: cap_start, count: captures.len() })

    cg_closure_defs.push("typedef struct \{")
    cg_closure_defs.push("    pact_handle* handle;")
    if captures.len() > 0 {
        cg_closure_defs.push("    void** captures;")
        cg_closure_defs.push("    int64_t capture_count;")
    }
    cg_closure_defs.push("} __async_arg_{wrapper_idx}_t;")
    cg_closure_defs.push("")

    let saved_lines = cg_lines
    let saved_indent = cg_indent
    let saved_temp = cg_temp_counter
    let saved_cap_start = cg_closure_cap_start
    let saved_cap_count = cg_closure_cap_count
    cg_lines = []
    cg_indent = 0
    cg_temp_counter = 0
    cg_closure_cap_start = cap_start
    cg_closure_cap_count = captures.len()

    push_scope()

    let mut task_params = "pact_closure* __self"
    emit_line("static int64_t {task_fn_name}({task_params}) \{")
    cg_indent = cg_indent + 1

    let mut mc_i = 0
    while mc_i < captures.len() {
        let mc_e = closure_captures.get(cap_start + mc_i)
        if mc_e.is_mut != 0 {
            let mc_ts = c_type_str(mc_e.ctype)
            emit_line("{mc_ts}* {mc_e.name}_cell = ({mc_ts}*)pact_closure_get_capture(__self, {mc_i});")
        }
        mc_i = mc_i + 1
    }

    emit_fn_body(np_body.get(closure_node), CT_INT)
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")

    pop_scope()

    let task_lines = cg_lines
    cg_lines = saved_lines
    cg_indent = saved_indent
    cg_temp_counter = saved_temp
    cg_closure_cap_start = saved_cap_start
    cg_closure_cap_count = saved_cap_count

    let mut tli = 0
    while tli < task_lines.len() {
        cg_closure_defs.push(task_lines.get(tli))
        tli = tli + 1
    }

    cg_closure_defs.push("static void {wrapper_name}(void* __arg) \{")
    cg_closure_defs.push("    __async_arg_{wrapper_idx}_t* __a = (__async_arg_{wrapper_idx}_t*)__arg;")
    cg_closure_defs.push("    pact_handle* __h = __a->handle;")
    if captures.len() > 0 {
        cg_closure_defs.push("    pact_closure __self_data = \{NULL, __a->captures, __a->capture_count};")
        cg_closure_defs.push("    int64_t __r = {task_fn_name}(&__self_data);")
    } else {
        cg_closure_defs.push("    int64_t __r = {task_fn_name}(NULL);")
    }
    cg_closure_defs.push("    pact_handle_set_result(__h, (void*)(intptr_t)__r);")
    cg_closure_defs.push("    free(__arg);")
    cg_closure_defs.push("}")
    cg_closure_defs.push("")
}

pub fn emit_await_expr(node: Int) {
    emit_expr(np_obj.get(node))
    let handle_str = expr_result_str
    let handle_type = expr_result_type
    let inner_type = get_var_handle_inner(handle_str)
    let tmp = fresh_temp("__await_")
    emit_line("void* {tmp} = pact_handle_await({handle_str});")
    if inner_type == CT_INT {
        expr_result_str = "(int64_t)(intptr_t){tmp}"
        expr_result_type = CT_INT
    } else if inner_type == CT_STRING {
        expr_result_str = "(const char*){tmp}"
        expr_result_type = CT_STRING
    } else if inner_type == CT_FLOAT {
        expr_result_str = "*(double*){tmp}"
        expr_result_type = CT_FLOAT
    } else if inner_type == CT_BOOL {
        expr_result_str = "(int)(intptr_t){tmp}"
        expr_result_type = CT_BOOL
    } else {
        expr_result_str = "(int64_t)(intptr_t){tmp}"
        expr_result_type = CT_INT
    }
}

pub fn emit_async_scope(node: Int) {
    cg_uses_async = 1
    let scope_idx = cg_async_scope_counter
    cg_async_scope_counter = cg_async_scope_counter + 1
    let list_name = "__scope_handles_{scope_idx}"
    emit_line("pact_list* {list_name} = pact_list_new();")
    cg_async_scope_stack.push(list_name)
    emit_block_expr(np_body.get(node))
    let saved_str = expr_result_str
    let saved_type = expr_result_type
    cg_async_scope_stack.pop()
    let iter_var = fresh_temp("__si_")
    emit_line("for (int64_t {iter_var} = 0; {iter_var} < pact_list_len({list_name}); {iter_var}++) \{")
    cg_indent = cg_indent + 1
    let handle_var = fresh_temp("__sh_")
    emit_line("pact_handle* {handle_var} = (pact_handle*)pact_list_get({list_name}, {iter_var});")
    emit_line("if ({handle_var}->status == PACT_HANDLE_RUNNING) \{")
    cg_indent = cg_indent + 1
    emit_line("pact_handle_await({handle_var});")
    cg_indent = cg_indent - 1
    emit_line("}")
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("pact_list_free({list_name});")
    expr_result_str = saved_str
    expr_result_type = saved_type
}

pub fn emit_binop(node: Int) {
    let op = np_op.get(node)
    if op == "??" {
        emit_expr(np_left.get(node))
        let left_str = expr_result_str
        let left_type = expr_result_type
        let opt_inner = expr_option_inner
        if left_type == CT_BOOL || left_type == CT_FLOAT || left_type == CT_STRING || left_type == CT_LIST || left_type == CT_RESULT || left_type == CT_CLOSURE {
            diag_error_no_loc("CoalesceRequiresOption", "E0502", "the ?? operator requires an Option value but got a non-Option type in function '{cg_current_fn_name}'", "")
        }
        emit_expr(np_right.get(node))
        let right_str = expr_result_str
        let right_type = expr_result_type
        let tmp = fresh_temp("__opt")
        if opt_inner >= 0 {
            let opt_c = option_c_type(opt_inner)
            emit_line("{opt_c} {tmp} = {left_str};")
        } else {
            emit_line("const int64_t {tmp} = (int64_t){left_str};")
        }
        expr_result_str = "({tmp}.tag == 1 ? {tmp}.value : {right_str})"
        expr_result_type = right_type
        return
    }
    emit_expr(np_left.get(node))
    let left_str = expr_result_str
    let left_type = expr_result_type
    emit_expr(np_right.get(node))
    let right_str = expr_result_str
    let right_type = expr_result_type

    if op == "==" && left_type == CT_STRING && right_type == CT_STRING {
        expr_result_str = "pact_str_eq({left_str}, {right_str})"
        expr_result_type = CT_BOOL
        return
    }
    if op == "!=" && left_type == CT_STRING && right_type == CT_STRING {
        expr_result_str = "(!pact_str_eq({left_str}, {right_str}))"
        expr_result_type = CT_BOOL
        return
    }
    if op == "+" && (left_type == CT_STRING || right_type == CT_STRING) {
        expr_result_str = "pact_str_concat({left_str}, {right_str})"
        expr_result_type = CT_STRING
        return
    }

    expr_result_str = "({left_str} {op} {right_str})"
    if op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||" {
        expr_result_type = CT_BOOL
    } else {
        expr_result_type = left_type
    }
}

pub fn emit_unaryop(node: Int) {
    emit_expr(np_left.get(node))
    let operand_str = expr_result_str
    let operand_type = expr_result_type
    let op = np_op.get(node)
    if op == "-" {
        expr_result_str = "(-{operand_str})"
        expr_result_type = operand_type
    } else if op == "!" {
        expr_result_str = "(!{operand_str})"
        expr_result_type = CT_BOOL
    } else if op == "?" {
        let tmp = fresh_temp("__res")
        if operand_type == CT_RESULT {
            if cg_current_fn_ret != CT_RESULT {
                diag_error_no_loc("QuestionMarkRequiresResult", "E0503", "'?' operator used in function '{cg_current_fn_name}' which does not return Result", "change the return type to Result")
                expr_result_str = "0"
                expr_result_type = CT_INT
            } else {
                let rok = expr_result_ok_type
                let rerr = expr_result_err_type
                let res_c = result_c_type(rok, rerr)
                emit_line("{res_c} {tmp} = {operand_str};")
                emit_line("if ({tmp}.tag == 1) return ({res_c})\{.tag = 1, .err = {tmp}.err};")
                expr_result_str = "{tmp}.ok"
                expr_result_type = rok
            }
        } else {
            diag_error_no_loc("QuestionMarkRequiresResult", "E0503", "'?' operator requires a Result value but got a non-Result type in function '{cg_current_fn_name}'", "")
            expr_result_str = "0"
            expr_result_type = CT_INT
        }
    } else {
        expr_result_str = "({op}{operand_str})"
        expr_result_type = operand_type
    }
}

pub fn emit_call(node: Int) {
    let func_node = np_left.get(node)
    let func_kind = np_kind.get(func_node)
    if func_kind == NodeKind.Ident {
        let fn_name = np_name.get(func_node)
        let call_line = np_line.get(func_node)

        if fn_name == "assert" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let val_str = expr_result_str
                emit_line("\{")
                cg_indent = cg_indent + 1
                emit_line("int64_t _val = (int64_t)({val_str});")
                emit_line("if (!_val) \{")
                cg_indent = cg_indent + 1
                emit_line("__pact_assert_fail(\"ASSERT FAILED: assertion failed\", {call_line});")
                cg_indent = cg_indent - 1
                emit_line("}")
                cg_indent = cg_indent - 1
                emit_line("}")
            }
            expr_result_str = ""
            expr_result_type = CT_VOID
            return
        }

        if fn_name == "assert_eq" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) >= 2 {
                emit_expr(sublist_get(args_sl, 0))
                let left_str = expr_result_str
                let left_type = expr_result_type
                emit_expr(sublist_get(args_sl, 1))
                let right_str = expr_result_str
                emit_line("\{")
                cg_indent = cg_indent + 1
                if left_type == CT_STRING {
                    emit_line("const char* _left = {left_str};")
                    emit_line("const char* _right = {right_str};")
                    emit_line("if (!pact_str_eq(_left, _right)) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp1 = fresh_temp("_msg")
                    emit_line("char {msg_tmp1}[512];")
                    emit_line("snprintf({msg_tmp1}, 512, \"ASSERT_EQ FAILED: \\\"%%s\\\" != \\\"%%s\\\"\", _left, _right);")
                    emit_line("__pact_assert_fail({msg_tmp1}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                } else if left_type == CT_FLOAT {
                    emit_line("double _left = (double)({left_str});")
                    emit_line("double _right = (double)({right_str});")
                    emit_line("if (_left != _right) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp3 = fresh_temp("_msg")
                    emit_line("char {msg_tmp3}[256];")
                    emit_line("snprintf({msg_tmp3}, 256, \"ASSERT_EQ FAILED: %%f != %%f\", _left, _right);")
                    emit_line("__pact_assert_fail({msg_tmp3}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                } else {
                    emit_line("int64_t _left = (int64_t)({left_str});")
                    emit_line("int64_t _right = (int64_t)({right_str});")
                    emit_line("if (_left != _right) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp2 = fresh_temp("_msg")
                    emit_line("char {msg_tmp2}[256];")
                    emit_line("snprintf({msg_tmp2}, 256, \"ASSERT_EQ FAILED: %%lld != %%lld\", (long long)_left, (long long)_right);")
                    emit_line("__pact_assert_fail({msg_tmp2}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                }
                cg_indent = cg_indent - 1
                emit_line("}")
            }
            expr_result_str = ""
            expr_result_type = CT_VOID
            return
        }

        if fn_name == "assert_ne" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) >= 2 {
                emit_expr(sublist_get(args_sl, 0))
                let left_str = expr_result_str
                let left_type = expr_result_type
                emit_expr(sublist_get(args_sl, 1))
                let right_str = expr_result_str
                emit_line("\{")
                cg_indent = cg_indent + 1
                if left_type == CT_STRING {
                    emit_line("const char* _left = {left_str};")
                    emit_line("const char* _right = {right_str};")
                    emit_line("if (pact_str_eq(_left, _right)) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp1 = fresh_temp("_msg")
                    emit_line("char {msg_tmp1}[512];")
                    emit_line("snprintf({msg_tmp1}, 512, \"ASSERT_NE FAILED: \\\"%%s\\\" == \\\"%%s\\\"\", _left, _right);")
                    emit_line("__pact_assert_fail({msg_tmp1}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                } else if left_type == CT_FLOAT {
                    emit_line("double _left = (double)({left_str});")
                    emit_line("double _right = (double)({right_str});")
                    emit_line("if (_left == _right) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp3 = fresh_temp("_msg")
                    emit_line("char {msg_tmp3}[256];")
                    emit_line("snprintf({msg_tmp3}, 256, \"ASSERT_NE FAILED: %%f == %%f\", _left, _right);")
                    emit_line("__pact_assert_fail({msg_tmp3}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                } else {
                    emit_line("int64_t _left = (int64_t)({left_str});")
                    emit_line("int64_t _right = (int64_t)({right_str});")
                    emit_line("if (_left == _right) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp2 = fresh_temp("_msg")
                    emit_line("char {msg_tmp2}[256];")
                    emit_line("snprintf({msg_tmp2}, 256, \"ASSERT_NE FAILED: %%lld == %%lld\", (long long)_left, (long long)_right);")
                    emit_line("__pact_assert_fail({msg_tmp2}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                }
                cg_indent = cg_indent - 1
                emit_line("}")
            }
            expr_result_str = ""
            expr_result_type = CT_VOID
            return
        }

        let variant_enum = resolve_variant(fn_name)
        if variant_enum != "" && is_data_enum(variant_enum) != 0 {
            let vidx = get_variant_index(variant_enum, fn_name)
            let tag = get_variant_tag(variant_enum, fn_name)
            let fcount = get_variant_field_count(vidx)
            let args_sl = np_args.get(node)
            let mut init_str = "(pact_{variant_enum})\{.tag = {tag}"
            if fcount > 0 && args_sl != -1 {
                init_str = init_str.concat(", .data.{fn_name} = \{")
                let mut fi = 0
                while fi < sublist_length(args_sl) && fi < fcount {
                    if fi > 0 {
                        init_str = init_str.concat(", ")
                    }
                    let field_name = get_variant_field_name(vidx, fi)
                    emit_expr(sublist_get(args_sl, fi))
                    let arg_str = expr_result_str
                    init_str = init_str.concat(".{field_name} = {arg_str}")
                    fi = fi + 1
                }
                init_str = init_str.concat("}")
            }
            init_str = init_str.concat("}")
            expr_result_str = init_str
            expr_result_type = CT_INT
            return
        }
        if fn_name == "Some" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let inner_str = expr_result_str
                let inner_type = expr_result_type
                ensure_option_type(inner_type)
                let opt_type = option_c_type(inner_type)
                expr_result_str = "({opt_type})\{.tag = 1, .value = {inner_str}}"
                expr_result_type = CT_OPTION
                expr_option_inner = inner_type
                return
            }
        }
        if fn_name == "Ok" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let ok_str = expr_result_str
                let ok_type = expr_result_type
                let err_type = CT_STRING
                ensure_result_type(ok_type, err_type)
                let res_type = result_c_type(ok_type, err_type)
                expr_result_str = "({res_type})\{.tag = 0, .ok = {ok_str}}"
                expr_result_type = CT_RESULT
                expr_result_ok_type = ok_type
                expr_result_err_type = err_type
                return
            }
        }
        if fn_name == "Err" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let err_str = expr_result_str
                let err_type = expr_result_type
                let ok_type = CT_INT
                ensure_result_type(ok_type, err_type)
                let res_type = result_c_type(ok_type, err_type)
                expr_result_str = "({res_type})\{.tag = 1, .err = {err_str}}"
                expr_result_type = CT_RESULT
                expr_result_ok_type = ok_type
                expr_result_err_type = err_type
                return
            }
        }
        if fn_name == "Map" {
            expr_result_str = "pact_map_new()"
            expr_result_type = CT_MAP
            return
        }
        if fn_name == "Channel" {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let cap_str = expr_result_str
                expr_result_str = "pact_channel_new({cap_str})"
            } else {
                expr_result_str = "pact_channel_new(16)"
            }
            expr_result_type = CT_CHANNEL
            return
        }
        // Check if this is a closure-typed variable
        let closure_sig = get_var_closure_sig(fn_name)
        if closure_sig != "" {
            let args_sl = np_args.get(node)
            let mut args_str = fn_name
            if args_sl != -1 {
                let mut i = 0
                while i < sublist_length(args_sl) {
                    args_str = args_str.concat(", ")
                    emit_expr(sublist_get(args_sl, i))
                    args_str = args_str.concat(expr_result_str)
                    i = i + 1
                }
            }
            expr_result_str = "(({closure_sig}){fn_name}->fn_ptr)({args_str})"
            // Parse return type from sig (everything before the first '(')
            let mut ret_end = 0
            while ret_end < closure_sig.len() && closure_sig.char_at(ret_end) != 40 {
                ret_end = ret_end + 1
            }
            let ret_part = closure_sig.substring(0, ret_end)
            if ret_part == "int64_t" {
                expr_result_type = CT_INT
            } else if ret_part == "double" {
                expr_result_type = CT_FLOAT
            } else if ret_part == "const char*" {
                expr_result_type = CT_STRING
            } else if ret_part == "int" {
                expr_result_type = CT_BOOL
            } else {
                expr_result_type = CT_VOID
            }
            return
        }
        let args_sl = np_args.get(node)
        let mut args_str = ""
        let mut arg_types: List[Int] = []
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    args_str = args_str.concat(", ")
                }
                emit_expr(sublist_get(args_sl, i))
                args_str = args_str.concat(expr_result_str)
                arg_types.push(expr_result_type)
                i = i + 1
            }
        }
        check_effect_propagation(fn_name)
        // Check for generic function call
        if is_generic_fn(fn_name) != 0 {
            let gfn_node = get_generic_fn_node(fn_name)
            let type_args = infer_fn_type_args_from_types(gfn_node, arg_types)
            if type_args != "" {
                let mangled = mangle_generic_name(fn_name, type_args)
                register_mono_fn(fn_name, type_args)
                register_mono_instance(fn_name, type_args)
                let ret_str = np_return_type.get(gfn_node)
                let tparams_sl = np_type_params.get(gfn_node)
                let resolved_ret = resolve_type_param(ret_str, tparams_sl, type_args)
                let ret_type = type_from_name(resolved_ret)
                reg_fn(mangled, ret_type)
                expr_result_str = "pact_{mangled}({args_str})"
                expr_result_type = ret_type
                return
            }
        }
        if is_fn_registered(fn_name) == 0 && is_generic_fn(fn_name) == 0 {
            diag_error_no_loc("UndefinedFunction", "E0504", "undefined function '{fn_name}' called in '{cg_current_fn_name}'", "")
        }
        expr_result_str = "pact_{fn_name}({args_str})"
        expr_result_type = get_fn_ret(fn_name)
        if expr_result_type == CT_VOID {
            let fn_sret = get_fn_ret_struct(fn_name)
            if fn_sret != "" {
                let s_tmp = fresh_temp("_sr")
                emit_line("pact_{fn_sret} {s_tmp} = pact_{fn_name}({args_str});")
                set_var_struct(s_tmp, fn_sret)
                expr_result_str = s_tmp
            }
        }
        let rt = get_fn_ret_type(fn_name)
        if expr_result_type == CT_RESULT {
            expr_result_ok_type = rt.inner1
            expr_result_err_type = rt.inner2
        }
        if expr_result_type == CT_OPTION {
            expr_option_inner = rt.inner1
        }
        if expr_result_type == CT_LIST {
            expr_list_elem_type = rt.inner1
        }
        return
    }
    // Qualified trait call: Trait.method(x, ...)
    if func_kind == NodeKind.FieldAccess {
        let trait_obj = np_obj.get(func_node)
        if np_kind.get(trait_obj) == NodeKind.Ident {
            let trait_name = np_name.get(trait_obj)
            if is_trait_type(trait_name) != 0 {
                let method = np_name.get(func_node)
                let args_sl = np_args.get(node)
                // First arg determines the type
                if args_sl != -1 && sublist_length(args_sl) > 0 {
                    emit_expr(sublist_get(args_sl, 0))
                    let first_str = expr_result_str
                    let type_name = get_var_struct(first_str)
                    if type_name != "" {
                        let mangled = "{type_name}_{method}"
                        let mut args_str = first_str
                        let mut i = 1
                        while i < sublist_length(args_sl) {
                            args_str = args_str.concat(", ")
                            emit_expr(sublist_get(args_sl, i))
                            args_str = args_str.concat(expr_result_str)
                            i = i + 1
                        }
                        expr_result_str = "pact_{mangled}({args_str})"
                        expr_result_type = get_impl_method_ret(type_name, method)
                        return
                    }
                }
            }
        }
    }
    emit_expr(func_node)
    let func_str = expr_result_str
    let args_sl = np_args.get(node)
    let mut args_str = ""
    if args_sl != -1 {
        let mut i = 0
        while i < sublist_length(args_sl) {
            if i > 0 {
                args_str = args_str.concat(", ")
            }
            emit_expr(sublist_get(args_sl, i))
            args_str = args_str.concat(expr_result_str)
            i = i + 1
        }
    }
    expr_result_str = "{func_str}({args_str})"
    expr_result_type = CT_VOID
}

pub fn emit_method_call(node: Int) {
    let obj_node = np_obj.get(node)
    let method = np_method.get(node)

    // Data-carrying enum variant constructor: Shape.Circle(5.0)
    if np_kind.get(obj_node) == NodeKind.Ident {
        let mc_obj_name = np_name.get(obj_node)
        if is_enum_type(mc_obj_name) != 0 && is_data_enum(mc_obj_name) != 0 {
            let vidx = get_variant_index(mc_obj_name, method)
            if vidx >= 0 {
                let tag = get_variant_tag(mc_obj_name, method)
                let fcount = get_variant_field_count(vidx)
                let args_sl = np_args.get(node)
                let mut init_str = "(pact_{mc_obj_name})\{.tag = {tag}"
                if fcount > 0 && args_sl != -1 {
                    init_str = init_str.concat(", .data.{method} = \{")
                    let mut fi = 0
                    while fi < sublist_length(args_sl) && fi < fcount {
                        if fi > 0 {
                            init_str = init_str.concat(", ")
                        }
                        let field_name = get_variant_field_name(vidx, fi)
                        emit_expr(sublist_get(args_sl, fi))
                        let arg_str = expr_result_str
                        init_str = init_str.concat(".{field_name} = {arg_str}")
                        fi = fi + 1
                    }
                    init_str = init_str.concat("}")
                }
                init_str = init_str.concat("}")
                expr_result_str = init_str
                expr_result_type = CT_INT
                return
            }
        }
    }

    // Special case: io.println
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "io" && method == "println" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("printf(\"%%lld\\n\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("printf(\"%%g\\n\", {arg_str});")
            } else if arg_type == CT_BOOL {
                emit_line("printf(\"%%s\\n\", {arg_str} ? \"true\" : \"false\");")
            } else {
                emit_line("printf(\"%%s\\n\", {arg_str});")
            }
        } else {
            emit_line("printf(\"\\n\");")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.print — like println but no trailing newline
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "io" && method == "print" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("printf(\"%%lld\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("printf(\"%%g\", {arg_str});")
            } else if arg_type == CT_BOOL {
                emit_line("printf(\"%%s\", {arg_str} ? \"true\" : \"false\");")
            } else {
                emit_line("printf(\"%%s\", {arg_str});")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.log — log to stderr
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "io" && method == "log" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("fprintf(stderr, \"[LOG] %%lld\\n\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("fprintf(stderr, \"[LOG] %%g\\n\", {arg_str});")
            } else {
                emit_line("fprintf(stderr, \"[LOG] %%s\\n\", {arg_str});")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // async.spawn(closure) — spawn async task on thread pool
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "async" && method == "spawn" {
        cg_uses_async = 1
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            let spawn_arg_node = sublist_get(args_sl, 0)
            let wrapper_idx = cg_async_wrapper_counter
            cg_async_wrapper_counter = cg_async_wrapper_counter + 1
            let wrapper_name = "__async_wrapper_{wrapper_idx}"
            let task_fn_name = "__async_task_{wrapper_idx}"
            let handle_tmp = fresh_temp("__handle_")
            let arg_tmp = fresh_temp("__spawn_arg_")

            if np_kind.get(spawn_arg_node) == NodeKind.Closure {
                let cap_reg_idx = closure_cap_infos.len()
                emit_async_spawn_closure(spawn_arg_node, wrapper_idx, wrapper_name, task_fn_name)

                emit_line("pact_handle* {handle_tmp} = pact_handle_new();")
                emit_line("__async_arg_{wrapper_idx}_t* {arg_tmp} = (__async_arg_{wrapper_idx}_t*)pact_alloc(sizeof(__async_arg_{wrapper_idx}_t));")
                emit_line("{arg_tmp}->handle = {handle_tmp};")
                let ac_info = closure_cap_infos.get(cap_reg_idx)
                if ac_info.count > 0 {
                    let caps_var = "__acaps_{wrapper_idx}"
                    emit_line("void** {caps_var} = (void**)pact_alloc(sizeof(void*) * {ac_info.count});")
                    let mut ci2 = 0
                    while ci2 < ac_info.count {
                        let cap_e = closure_captures.get(ac_info.start + ci2)
                        if cap_e.is_mut != 0 {
                            emit_line("{caps_var}[{ci2}] = (void*){cap_e.name}_cell;")
                        } else if cap_e.ctype == CT_INT {
                            emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
                        } else if cap_e.ctype == CT_FLOAT {
                            let fp_tmp = fresh_temp("__fp_")
                            emit_line("\{double* {fp_tmp} = (double*)pact_alloc(sizeof(double)); *{fp_tmp} = {cap_e.name}; {caps_var}[{ci2}] = (void*){fp_tmp};}")
                        } else if cap_e.ctype == CT_BOOL {
                            emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
                        } else {
                            emit_line("{caps_var}[{ci2}] = (void*){cap_e.name};")
                        }
                        ci2 = ci2 + 1
                    }
                    emit_line("{arg_tmp}->captures = {caps_var};")
                    emit_line("{arg_tmp}->capture_count = {ac_info.count};")
                }
                emit_line("pact_threadpool_submit(__pact_pool, {wrapper_name}, (void*){arg_tmp});")
            } else {
                emit_expr(spawn_arg_node)
                let closure_str = expr_result_str
                cg_closure_defs.push("typedef struct \{")
                cg_closure_defs.push("    pact_closure* closure;")
                cg_closure_defs.push("    pact_handle* handle;")
                cg_closure_defs.push("} __async_arg_{wrapper_idx}_t;")
                cg_closure_defs.push("")
                cg_closure_defs.push("static void {wrapper_name}(void* __arg) \{")
                cg_closure_defs.push("    __async_arg_{wrapper_idx}_t* __a = (__async_arg_{wrapper_idx}_t*)__arg;")
                cg_closure_defs.push("    pact_closure* __cl = __a->closure;")
                cg_closure_defs.push("    pact_handle* __h = __a->handle;")
                cg_closure_defs.push("    int64_t __r = ((int64_t(*)(pact_closure*))__cl->fn_ptr)(__cl);")
                cg_closure_defs.push("    pact_handle_set_result(__h, (void*)(intptr_t)__r);")
                cg_closure_defs.push("    free(__arg);")
                cg_closure_defs.push("}")
                cg_closure_defs.push("")

                emit_line("pact_handle* {handle_tmp} = pact_handle_new();")
                emit_line("__async_arg_{wrapper_idx}_t* {arg_tmp} = (__async_arg_{wrapper_idx}_t*)pact_alloc(sizeof(__async_arg_{wrapper_idx}_t));")
                emit_line("{arg_tmp}->closure = {closure_str};")
                emit_line("{arg_tmp}->handle = {handle_tmp};")
                emit_line("pact_threadpool_submit(__pact_pool, {wrapper_name}, (void*){arg_tmp});")
            }

            if cg_async_scope_stack.len() > 0 {
                let scope_list = cg_async_scope_stack.get(cg_async_scope_stack.len() - 1)
                emit_line("pact_list_push({scope_list}, (void*){handle_tmp});")
            }

            set_var_handle(handle_tmp, CT_INT)
            expr_result_str = handle_tmp
            expr_result_type = CT_HANDLE
        } else {
            expr_result_str = "0"
            expr_result_type = CT_VOID
        }
        return
    }

    // fs.read — read file contents
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "fs" && method == "read" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            expr_result_str = "pact_read_file({arg_str})"
            expr_result_type = CT_STRING
        } else {
            expr_result_str = "\"\""
            expr_result_type = CT_STRING
        }
        return
    }

    // fs.write — write file contents
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "fs" && method == "write" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let path_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let content_str = expr_result_str
            emit_line("pact_write_file({path_str}, {content_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // fs.list_dir — list directory contents
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "fs" && method == "list_dir" {
        let args_sl = np_args.get(node)
        if args_sl != -1 && sublist_length(args_sl) >= 1 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            expr_result_str = "pact_list_dir({arg_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
        } else {
            expr_result_str = "pact_list_new()"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
        }
        return
    }

    // default.method(args) — delegate to outer handler inside handler body
    if np_kind.get(obj_node) == NodeKind.Ident && np_name.get(obj_node) == "default" && cg_in_handler_body != 0 {
        let outer_name = "__handler_{cg_handler_body_idx}_outer"
        let args_sl = np_args.get(node)
        let mut args_str = ""
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                if ai > 0 {
                    args_str = args_str.concat(", ")
                }
                emit_expr(sublist_get(args_sl, ai))
                args_str = args_str.concat(expr_result_str)
                ai = ai + 1
            }
        }
        expr_result_str = "{outer_name}->{method}({args_str})"
        expr_result_type = CT_VOID
        return
    }

    // User-defined effect handle dispatch: handle.method(args) -> __pact_ue_handle->method(args)
    if np_kind.get(obj_node) == NodeKind.Ident {
        let handle_name = np_name.get(obj_node)
        if is_user_effect_handle(handle_name) != 0 {
            let args_sl = np_args.get(node)
            let mut args_str = ""
            if args_sl != -1 {
                let mut ai = 0
                while ai < sublist_length(args_sl) {
                    if ai > 0 {
                        args_str = args_str.concat(", ")
                    }
                    emit_expr(sublist_get(args_sl, ai))
                    args_str = args_str.concat(expr_result_str)
                    ai = ai + 1
                }
            }
            let mut ue_ret_type = CT_VOID
            let mut mi = 0
            while mi < ue_methods.len() {
                let uem = ue_methods.get(mi)
                if uem.effect_handle == handle_name && uem.name == method {
                    if uem.ret == "int64_t" {
                        ue_ret_type = CT_INT
                    } else if uem.ret == "const char*" {
                        ue_ret_type = CT_STRING
                    } else if uem.ret == "double" {
                        ue_ret_type = CT_FLOAT
                    } else if uem.ret == "int" {
                        ue_ret_type = CT_BOOL
                    }
                    break
                }
                mi = mi + 1
            }
            if ue_ret_type == CT_VOID {
                emit_line("__pact_ue_{handle_name}->{method}({args_str});")
                expr_result_str = "0"
            } else {
                expr_result_str = "__pact_ue_{handle_name}->{method}({args_str})"
            }
            expr_result_type = ue_ret_type
            return
        }
    }

    // Qualified trait call: Trait.method(args) parsed as MethodCall(obj=Trait, method=method)
    if np_kind.get(obj_node) == NodeKind.Ident {
        let trait_name = np_name.get(obj_node)
        if is_trait_type(trait_name) != 0 {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let first_str = expr_result_str
                let type_name = get_var_struct(first_str)
                if type_name != "" {
                    let mangled = "{type_name}_{method}"
                    let mut args_str = first_str
                    let mut i = 1
                    while i < sublist_length(args_sl) {
                        args_str = args_str.concat(", ")
                        emit_expr(sublist_get(args_sl, i))
                        args_str = args_str.concat(expr_result_str)
                        i = i + 1
                    }
                    expr_result_str = "pact_{mangled}({args_str})"
                    expr_result_type = get_impl_method_ret(type_name, method)
                    return
                }
            }
        }
    }

    // Static From dispatch: Type.from(value)
    if np_kind.get(obj_node) == NodeKind.Ident {
        let target_type = np_name.get(obj_node)
        if method == "from" && (is_struct_type(target_type) != 0 || is_enum_type(target_type) != 0) {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                let arg_type = expr_result_type
                let source_type = type_name_from_ct(arg_type)
                let arg_struct = get_var_struct(arg_str)
                let mut src = source_type
                if arg_struct != "" {
                    src = arg_struct
                }
                let from_methods = find_from_impl(src, target_type)
                if from_methods != -1 && sublist_length(from_methods) > 0 {
                    let from_fn = sublist_get(from_methods, 0)
                    let from_name = np_name.get(from_fn)
                    let mangled = "{target_type}_{from_name}"
                    expr_result_str = "pact_{mangled}({arg_str})"
                    expr_result_type = get_fn_ret(mangled)
                    if expr_result_type == CT_VOID {
                        set_var_struct(expr_result_str, target_type)
                    }
                    return
                }
            }
        }
    }

    // Static TryFrom dispatch: Type.try_from(value)
    if np_kind.get(obj_node) == NodeKind.Ident {
        let target_type = np_name.get(obj_node)
        if method == "try_from" && (is_struct_type(target_type) != 0 || is_enum_type(target_type) != 0) {
            let args_sl = np_args.get(node)
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                let arg_type = expr_result_type
                let source_type = type_name_from_ct(arg_type)
                let arg_struct = get_var_struct(arg_str)
                let mut src = source_type
                if arg_struct != "" {
                    src = arg_struct
                }
                let tf_methods = find_tryfrom_impl(src, target_type)
                if tf_methods != -1 && sublist_length(tf_methods) > 0 {
                    let tf_fn = sublist_get(tf_methods, 0)
                    let tf_name = np_name.get(tf_fn)
                    let mangled = "{target_type}_{tf_name}"
                    expr_result_str = "pact_{mangled}({arg_str})"
                    expr_result_type = get_fn_ret(mangled)
                    let tf_rt = get_fn_ret_type(mangled)
                    if tf_rt.inner1 != -1 && tf_rt.inner2 != -1 {
                        expr_result_ok_type = tf_rt.inner1
                        expr_result_err_type = tf_rt.inner2
                        set_var_result(expr_result_str, tf_rt.inner1, tf_rt.inner2)
                    }
                    return
                }
            }
        }
    }

    emit_expr(obj_node)
    let obj_str = expr_result_str
    let obj_type = expr_result_type

    // .into() dispatch — infer target type from assignment context
    if method == "into" {
        let target = cg_let_target_type
        if target == CT_FLOAT && obj_type == CT_INT {
            expr_result_str = "(double){obj_str}"
            expr_result_type = CT_FLOAT
            return
        }
        if target == CT_INT && obj_type == CT_FLOAT {
            expr_result_str = "(int64_t){obj_str}"
            expr_result_type = CT_INT
            return
        }
        if target == CT_STRING && obj_type == CT_INT {
            expr_result_str = "pact_int_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if target == CT_STRING && obj_type == CT_FLOAT {
            expr_result_str = "pact_float_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        let mut src_name = type_name_from_ct(obj_type)
        let src_struct = get_var_struct(obj_str)
        if src_struct != "" {
            src_name = src_struct
        }
        let mut tgt_name = type_name_from_ct(target)
        if target == CT_VOID && cg_let_target_name != "" {
            tgt_name = cg_let_target_name
        }
        let from_methods = find_from_impl(src_name, tgt_name)
        if from_methods != -1 && sublist_length(from_methods) > 0 {
            let from_fn = sublist_get(from_methods, 0)
            let from_name = np_name.get(from_fn)
            let mangled = "{tgt_name}_{from_name}"
            expr_result_str = "pact_{mangled}({obj_str})"
            expr_result_type = target
            return
        }
        emit_line("/* into() conversion not found */")
        expr_result_str = obj_str
        expr_result_type = obj_type
        return
    }

    // String methods
    if obj_type == CT_STRING {
        if method == "len" {
            expr_result_str = "pact_str_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "char_at" || method == "charAt" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            expr_result_str = "pact_str_char_at({obj_str}, {idx_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "substring" || method == "substr" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let start_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let len_str = expr_result_str
            expr_result_str = "pact_str_substr({obj_str}, {start_str}, {len_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "contains" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let needle_str = expr_result_str
            expr_result_str = "pact_str_contains({obj_str}, {needle_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "starts_with" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let pfx_str = expr_result_str
            expr_result_str = "pact_str_starts_with({obj_str}, {pfx_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "ends_with" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let sfx_str = expr_result_str
            expr_result_str = "pact_str_ends_with({obj_str}, {sfx_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "concat" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_str_concat({obj_str}, {other_str})"
            expr_result_type = CT_STRING
            return
        }
    }

    // List methods
    if obj_type == CT_LIST {
        if method == "push" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let val_str = expr_result_str
            let val_type = expr_result_type
            if val_type != CT_INT {
                set_list_elem_type(obj_str, val_type)
            }
            let val_struct = get_var_struct(val_str)
            if val_type == CT_VOID && val_struct != "" {
                set_list_elem_struct(obj_str, val_struct)
                set_list_elem_type(obj_str, CT_VOID)
                let box_tmp = fresh_temp("_box")
                emit_line("pact_{val_struct}* {box_tmp} = (pact_{val_struct}*)pact_alloc(sizeof(pact_{val_struct}));")
                emit_line("*{box_tmp} = {val_str};")
                emit_line("pact_list_push({obj_str}, (void*){box_tmp});")
            } else if val_type == CT_INT {
                emit_line("pact_list_push({obj_str}, (void*)(intptr_t){val_str});")
            } else {
                emit_line("pact_list_push({obj_str}, (void*){val_str});")
            }
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "pop" {
            emit_line("pact_list_pop({obj_str});")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "len" {
            expr_result_str = "pact_list_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "get" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            let elem_type = get_list_elem_type(obj_str)
            let elem_struct = get_list_elem_struct(obj_str)
            if elem_type == CT_VOID && elem_struct != "" {
                let ub_tmp = fresh_temp("_ub")
                emit_line("pact_{elem_struct} {ub_tmp} = *(pact_{elem_struct}*)pact_list_get({obj_str}, {idx_str});")
                set_var_struct(ub_tmp, elem_struct)
                expr_result_str = ub_tmp
                expr_result_type = CT_VOID
            } else if elem_type == CT_STRING {
                expr_result_str = "(const char*)pact_list_get({obj_str}, {idx_str})"
                expr_result_type = CT_STRING
            } else if elem_type == CT_LIST {
                expr_result_str = "(pact_list*)pact_list_get({obj_str}, {idx_str})"
                expr_result_type = CT_LIST
                set_list_elem_type(expr_result_str, CT_INT)
            } else {
                expr_result_str = "(int64_t)(intptr_t)pact_list_get({obj_str}, {idx_str})"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "set" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let val_str2 = expr_result_str
            let val_type2 = expr_result_type
            let val_struct2 = get_var_struct(val_str2)
            if val_type2 == CT_VOID && val_struct2 != "" {
                let box_tmp = fresh_temp("_box")
                emit_line("pact_{val_struct2}* {box_tmp} = (pact_{val_struct2}*)pact_alloc(sizeof(pact_{val_struct2}));")
                emit_line("*{box_tmp} = {val_str2};")
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){box_tmp});")
            } else if val_type2 == CT_INT {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*)(intptr_t){val_str2});")
            } else {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){val_str2});")
            }
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
    }

    // Iterator adapter and consumer methods — work on both CT_LIST and CT_ITERATOR
    if (obj_type == CT_LIST || obj_type == CT_ITERATOR) && (method == "count" || method == "collect" || method == "for_each" || method == "any" || method == "all" || method == "find" || method == "fold" || method == "map" || method == "filter" || method == "take" || method == "skip" || method == "chain" || method == "flat_map" || method == "enumerate" || method == "zip") {

        // --- Adapter methods: return CT_ITERATOR ---

        if method == "map" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_map_iter(elem_type)
            let adapter_var = fresh_temp("__map_")
            emit_line("pact_MapIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str} };")
            set_var_iterator(adapter_var, elem_type, "pact_MapIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_MapIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "filter" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_filter_iter(elem_type)
            let adapter_var = fresh_temp("__filter_")
            emit_line("pact_FilterIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str} };")
            set_var_iterator(adapter_var, elem_type, "pact_FilterIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_FilterIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "take" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let n_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_take_iter(elem_type)
            let adapter_var = fresh_temp("__take_")
            emit_line("pact_TakeIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .limit = {n_str}, .count = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_TakeIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_TakeIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "skip" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let n_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_skip_iter(elem_type)
            let adapter_var = fresh_temp("__skip_")
            emit_line("pact_SkipIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .skip_n = {n_str}, .skipped = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_SkipIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_SkipIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "chain" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            let other_type = expr_result_type
            iter_from_source(obj_str, obj_type)
            let src_a_var = ifs_iter_var
            let next_a = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let tag = c_type_tag(elem_type)
            iter_from_source(other_str, other_type)
            let src_b_var = ifs_iter_var
            let next_b = ifs_next_fn
            ensure_chain_iter(elem_type)
            let adapter_var = fresh_temp("__chain_")
            emit_line("pact_ChainIterator_{tag} {adapter_var} = \{ .source_a = &{src_a_var}, .next_a = ({opt_t} (*)(void*)){next_a}, .source_b = &{src_b_var}, .next_b = ({opt_t} (*)(void*)){next_b}, .phase = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_ChainIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_ChainIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "flat_map" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_flat_map_iter(elem_type)
            let adapter_var = fresh_temp("__flatmap_")
            emit_line("pact_FlatMapIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str}, .buffer = NULL, .buf_idx = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_FlatMapIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_FlatMapIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "enumerate" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let tag = c_type_tag(elem_type)
            let result_list = fresh_temp("__enum_")
            let next_var = fresh_temp("__enum_next_")
            let i_var = fresh_temp("__enum_i_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("int64_t {i_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            let pair_var = fresh_temp("__enum_pair_")
            emit_line("pact_list* {pair_var} = pact_list_new();")
            emit_line("pact_list_push({pair_var}, (void*)(intptr_t){i_var});")
            if elem_type == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_var}.value);")
            }
            emit_line("pact_list_push({result_list}, (void*){pair_var});")
            emit_line("{i_var}++;")
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, CT_LIST)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_LIST
            return
        }
        if method == "zip" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            let other_type = expr_result_type
            iter_from_source(obj_str, obj_type)
            let src_a_var = ifs_iter_var
            let next_a = ifs_next_fn
            let elem_type_a = ifs_elem_type
            let opt_a = ifs_opt_type
            iter_from_source(other_str, other_type)
            let src_b_var = ifs_iter_var
            let next_b = ifs_next_fn
            let elem_type_b = ifs_elem_type
            let opt_b = ifs_opt_type
            let result_list = fresh_temp("__zip_")
            let next_a_var = fresh_temp("__zip_na_")
            let next_b_var = fresh_temp("__zip_nb_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_a} {next_a_var} = (({opt_a} (*)(void*)){next_a})(&{src_a_var});")
            emit_line("if ({next_a_var}.tag == 0) break;")
            emit_line("{opt_b} {next_b_var} = (({opt_b} (*)(void*)){next_b})(&{src_b_var});")
            emit_line("if ({next_b_var}.tag == 0) break;")
            let pair_var = fresh_temp("__zip_pair_")
            emit_line("pact_list* {pair_var} = pact_list_new();")
            if elem_type_a == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_a_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_a_var}.value);")
            }
            if elem_type_b == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_b_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_b_var}.value);")
            }
            emit_line("pact_list_push({result_list}, (void*){pair_var});")
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, CT_LIST)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_LIST
            return
        }

        // --- Consumer methods: drive an iterator to completion ---

        if method == "collect" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let result_list = fresh_temp("__collect_")
            let next_var = fresh_temp("__collect_next_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            if elem_type == CT_INT {
                emit_line("pact_list_push({result_list}, (void*)(intptr_t){next_var}.value);")
            } else {
                emit_line("pact_list_push({result_list}, (void*){next_var}.value);")
            }
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, elem_type)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = elem_type
            return
        }
        if method == "count" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type
            let count_var = fresh_temp("__count_")
            let next_var = fresh_temp("__count_next_")
            emit_line("int64_t {count_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("{count_var}++;")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = count_var
            expr_result_type = CT_INT
            return
        }
        if method == "for_each" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let c_inner = c_type_str(elem_type)
            let next_var = fresh_temp("__fe_next_")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("(({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value);")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "any" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let c_inner = c_type_str(elem_type)
            let result_var = fresh_temp("__any_")
            let next_var = fresh_temp("__any_next_")
            emit_line("int {result_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if ((({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = 1; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = result_var
            expr_result_type = CT_BOOL
            return
        }
        if method == "all" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let c_inner = c_type_str(elem_type)
            let result_var = fresh_temp("__all_")
            let next_var = fresh_temp("__all_next_")
            emit_line("int {result_var} = 1;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if (!(({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = 0; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = result_var
            expr_result_type = CT_BOOL
            return
        }
        if method == "find" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            ensure_option_type(elem_type)
            let result_var = fresh_temp("__find_")
            let next_var = fresh_temp("__find_next_")
            emit_line("{opt_t} {result_var} = ({opt_t})\{.tag = 0};")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if ((({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = ({opt_t})\{.tag = 1, .value = {next_var}.value}; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = result_var
            expr_result_type = CT_OPTION
            expr_option_inner = elem_type
            return
        }
        if method == "fold" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let init_str = expr_result_str
            let init_type = expr_result_type
            emit_expr(sublist_get(args_sl, 1))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let acc_var = fresh_temp("__fold_acc_")
            let next_var = fresh_temp("__fold_next_")
            emit_line("{c_type_str(init_type)} {acc_var} = {init_str};")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("{acc_var} = (({fn_sig}){fn_str}->fn_ptr)({fn_str}, {acc_var}, {next_var}.value);")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = acc_var
            expr_result_type = init_type
            return
        }
    }

    // Channel methods
    if obj_type == CT_CHANNEL {
        if method == "send" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let val_str = expr_result_str
            let val_type = expr_result_type
            if val_type == CT_INT {
                emit_line("pact_channel_send({obj_str}, (void*)(intptr_t){val_str});")
            } else {
                emit_line("pact_channel_send({obj_str}, (void*){val_str});")
            }
            expr_result_str = "0"
            expr_result_type = CT_INT
            return
        }
        if method == "recv" {
            let recv_tmp = fresh_temp("__recv_")
            let ch_inner = get_var_channel_inner(obj_str)
            emit_line("void* {recv_tmp} = pact_channel_recv({obj_str});")
            if ch_inner == CT_STRING {
                expr_result_str = "(const char*){recv_tmp}"
                expr_result_type = CT_STRING
            } else {
                expr_result_str = "(int64_t)(intptr_t){recv_tmp}"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "close" {
            emit_line("pact_channel_close({obj_str});")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
    }

    // Map methods
    if obj_type == CT_MAP {
        if method == "set" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let val_str2 = expr_result_str
            let val_type2 = expr_result_type
            if val_type2 == CT_INT {
                emit_line("pact_map_set({obj_str}, {key_str}, (void*)(intptr_t){val_str2});")
            } else {
                emit_line("pact_map_set({obj_str}, {key_str}, (void*){val_str2});")
            }
            set_map_types(obj_str, CT_STRING, val_type2)
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "get" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            let vtype = get_map_value_type(obj_str)
            if vtype == CT_STRING {
                expr_result_str = "(const char*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_STRING
            } else if vtype == CT_LIST {
                expr_result_str = "(pact_list*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_LIST
            } else if vtype == CT_MAP {
                expr_result_str = "(pact_map*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_MAP
            } else {
                expr_result_str = "(int64_t)(intptr_t)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "has" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            expr_result_str = "pact_map_has({obj_str}, {key_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "remove" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            expr_result_str = "pact_map_remove({obj_str}, {key_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "len" {
            expr_result_str = "pact_map_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "keys" {
            expr_result_str = "pact_map_keys({obj_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
            return
        }
        if method == "values" {
            let vtype = get_map_value_type(obj_str)
            expr_result_str = "pact_map_values({obj_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = vtype
            return
        }
    }

    // Trait impl method resolution
    let struct_type = get_var_struct(obj_str)
    if struct_type != "" && lookup_impl_method(struct_type, method) != 0 {
        let mangled = "{struct_type}_{method}"
        let args_sl = np_args.get(node)
        let mut args_str = obj_str
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                args_str = args_str.concat(", ")
                emit_expr(sublist_get(args_sl, i))
                args_str = args_str.concat(expr_result_str)
                i = i + 1
            }
        }
        expr_result_str = "pact_{mangled}({args_str})"
        expr_result_type = get_impl_method_ret(struct_type, method)
        return
    }

    // Generic fallback
    diag_error_no_loc("UnresolvedMethod", "E0505", "unresolved method '.{method}' called on variable in '{cg_current_fn_name}'", "")
    let args_sl = np_args.get(node)
    let mut args_str = ""
    if args_sl != -1 {
        let mut i = 0
        while i < sublist_length(args_sl) {
            if i > 0 {
                args_str = args_str.concat(", ")
            }
            emit_expr(sublist_get(args_sl, i))
            args_str = args_str.concat(expr_result_str)
            i = i + 1
        }
    }
    expr_result_str = "{obj_str}_{method}({args_str})"
    expr_result_type = CT_VOID
}

pub fn escape_c_string(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let ch = s.char_at(i)
        if ch == 92 {
            result = result.concat("\\\\")
        } else if ch == 34 {
            result = result.concat("\\\"")
        } else if ch == 10 {
            result = result.concat("\\n")
        } else if ch == 9 {
            result = result.concat("\\t")
        } else if ch == 63 {
            result = result.concat("\\?")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

pub fn emit_interp_string(node: Int) {
    let parts_sl = np_elements.get(node)
    if parts_sl == -1 {
        expr_result_str = "\"\""
        expr_result_type = CT_STRING
        return
    }

    // Fast path: if all parts are literal, emit a simple string constant
    let mut all_literal = 1
    let mut ai = 0
    while ai < sublist_length(parts_sl) {
        let part = sublist_get(parts_sl, ai)
        let pk = np_kind.get(part)
        if !(pk == NodeKind.Ident && np_str_val.get(part) == np_name.get(part)) {
            all_literal = 0
        }
        ai = ai + 1
    }
    if all_literal != 0 {
        let mut concat_str = ""
        let mut ci = 0
        while ci < sublist_length(parts_sl) {
            let part = sublist_get(parts_sl, ci)
            concat_str = concat_str.concat(escape_c_string(np_str_val.get(part)))
            ci = ci + 1
        }
        expr_result_str = "\"".concat(concat_str).concat("\"")
        expr_result_type = CT_STRING
        return
    }

    // Slow path: use snprintf for strings with expression parts
    let buf_name = fresh_temp("_si_")
    emit_line("char {buf_name}[4096];")
    let mut fmt = ""
    let mut args = ""
    let mut has_args = 0
    let mut i = 0
    while i < sublist_length(parts_sl) {
        let part = sublist_get(parts_sl, i)
        let pk = np_kind.get(part)
        // Literal string parts: parser stores them as NodeKind.Ident with str_val == name
        // Expression parts: NodeKind.Ident with str_val == "" (or other node kinds)
        if pk == NodeKind.Ident && np_str_val.get(part) == np_name.get(part) {
            fmt = fmt.concat(escape_c_string(np_str_val.get(part)))
        } else {
            // Expression part
            emit_expr(part)
            let e_str = expr_result_str
            let e_type = expr_result_type
            if e_type == CT_INT {
                fmt = fmt.concat("%lld")
                if has_args {
                    args = args.concat(", ")
                }
                args = args.concat("(long long)")
                args = args.concat(e_str)
                has_args = 1
            } else if e_type == CT_FLOAT {
                fmt = fmt.concat("%g")
                if has_args {
                    args = args.concat(", ")
                }
                args = args.concat(e_str)
                has_args = 1
            } else if e_type == CT_BOOL {
                fmt = fmt.concat("%s")
                if has_args {
                    args = args.concat(", ")
                }
                args = args.concat(e_str)
                args = args.concat(" ? \"true\" : \"false\"")
                has_args = 1
            } else {
                fmt = fmt.concat("%s")
                if has_args {
                    args = args.concat(", ")
                }
                args = args.concat(e_str)
                has_args = 1
            }
        }
        i = i + 1
    }
    if has_args {
        let line = "snprintf(".concat(buf_name).concat(", 4096, \"").concat(fmt).concat("\", ").concat(args).concat(");")
        emit_line(line)
    } else {
        let line = "snprintf(".concat(buf_name).concat(", 4096, \"").concat(fmt).concat("\");")
        emit_line(line)
    }
    expr_result_str = "strdup(".concat(buf_name).concat(")")
    expr_result_type = CT_STRING
}

pub fn emit_list_lit(node: Int) {
    let tmp = fresh_temp("_l")
    emit_line("pact_list* {tmp} = pact_list_new();")
    let elems_sl = np_elements.get(node)
    let mut first_elem_type = -1
    let mut first_elem_struct = ""
    if elems_sl != -1 {
        let mut i = 0
        while i < sublist_length(elems_sl) {
            emit_expr(sublist_get(elems_sl, i))
            let e_str = expr_result_str
            let e_type = expr_result_type
            if i == 0 {
                first_elem_type = e_type
                first_elem_struct = get_var_struct(e_str)
            }
            let e_struct = get_var_struct(e_str)
            if e_type == CT_VOID && e_struct != "" {
                let box_tmp = fresh_temp("_box")
                emit_line("pact_{e_struct}* {box_tmp} = (pact_{e_struct}*)pact_alloc(sizeof(pact_{e_struct}));")
                emit_line("*{box_tmp} = {e_str};")
                emit_line("pact_list_push({tmp}, (void*){box_tmp});")
            } else if e_type == CT_INT {
                emit_line("pact_list_push({tmp}, (void*)(intptr_t){e_str});")
            } else {
                emit_line("pact_list_push({tmp}, (void*){e_str});")
            }
            i = i + 1
        }
    }
    if first_elem_type >= 0 {
        expr_list_elem_type = first_elem_type
    }
    if first_elem_struct != "" {
        set_list_elem_type(tmp, CT_VOID)
        set_list_elem_struct(tmp, first_elem_struct)
    }
    expr_result_str = tmp
    expr_result_type = CT_LIST
}

pub fn infer_struct_type_args(type_name: Str, field_types: List[Int]) -> Str {
    let types_sl = np_fields.get(cg_program_node)
    if types_sl == -1 {
        return ""
    }
    let mut td = -1
    let mut ti = 0
    while ti < sublist_length(types_sl) {
        let candidate = sublist_get(types_sl, ti)
        if np_name.get(candidate) == type_name {
            td = candidate
        }
        ti = ti + 1
    }
    if td == -1 {
        return ""
    }
    let tparams_sl = np_type_params.get(td)
    if tparams_sl == -1 {
        return ""
    }
    let num_params = sublist_length(tparams_sl)
    if num_params == 0 {
        return ""
    }
    let td_flds_sl = np_fields.get(td)
    if td_flds_sl == -1 {
        return ""
    }
    let mut args = ""
    let mut pi = 0
    while pi < num_params {
        let param_name = np_name.get(sublist_get(tparams_sl, pi))
        let mut resolved = "Void"
        let mut fi = 0
        while fi < sublist_length(td_flds_sl) && fi < field_types.len() {
            let f = sublist_get(td_flds_sl, fi)
            let type_ann_node = np_value.get(f)
            if type_ann_node != -1 {
                if np_name.get(type_ann_node) == param_name {
                    resolved = type_name_from_ct(field_types.get(fi))
                }
            }
            fi = fi + 1
        }
        if pi > 0 {
            args = args.concat(",")
        }
        args = args.concat(resolved)
        pi = pi + 1
    }
    args
}

pub fn emit_struct_lit(node: Int) {
    let sname = np_type_name.get(node)
    let mut c_type = "pact_{sname}"
    let tmp = fresh_temp("_s")
    let flds_sl = np_fields.get(node)
    let mut inits = ""
    let mut field_types: List[Int] = []
    if flds_sl != -1 {
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, i)
            let fname = np_name.get(sf)
            emit_expr(np_value.get(sf))
            let val_str = expr_result_str
            field_types.push(expr_result_type)
            if i > 0 {
                inits = inits.concat(", ")
            }
            inits = inits.concat(".{fname} = {val_str}")
            i = i + 1
        }
    }
    let type_args = infer_struct_type_args(sname, field_types)
    let mut struct_key = sname
    if type_args != "" {
        let mono_name = register_mono_instance(sname, type_args)
        c_type = "pact_{mono_name}"
        struct_key = mono_name
        // Register field types for the mono instance so field access works
        register_mono_field_types(sname, mono_name, type_args)
    }
    emit_line("{c_type} {tmp} = \{ {inits} };")
    set_var_struct(tmp, struct_key)
    expr_result_str = tmp
    expr_result_type = CT_VOID
}

// ── Capture analysis ────────────────────────────────────────────────
// Walk a closure body AST collecting free variable references.

pub fn list_contains_str(lst: List[Str], val: Str) -> Int {
    let mut i = 0
    while i < lst.len() {
        if lst.get(i) == val {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_in_scope(name: Str) -> Int {
    let mut i = 0
    while i < scope_vars.len() {
        if scope_vars.get(i).name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn collect_free_vars(node: Int, params: List[Str], locals: List[Str], result: List[Str]) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)

    if kind == NodeKind.Ident {
        let name = np_name.get(node)
        if list_contains_str(params, name) {
            return
        }
        if list_contains_str(locals, name) {
            return
        }
        if list_contains_str(result, name) {
            return
        }
        if is_emitted_fn(name) {
            return
        }
        if resolve_variant(name) != "" {
            return
        }
        if is_enum_type(name) != 0 {
            return
        }
        if is_struct_type(name) != 0 {
            return
        }
        let mut fi = 0
        let mut is_fn_reg = 0
        while fi < fn_regs.len() {
            if fn_regs.get(fi).name == name {
                is_fn_reg = 1
            }
            fi = fi + 1
        }
        if is_fn_reg {
            return
        }
        if is_in_scope(name) {
            result.push(name)
        }
        return
    }

    if kind == NodeKind.BinOp {
        collect_free_vars(np_left.get(node), params, locals, result)
        collect_free_vars(np_right.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.UnaryOp {
        collect_free_vars(np_left.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.Call {
        collect_free_vars(np_left.get(node), params, locals, result)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                collect_free_vars(sublist_get(args_sl, ai), params, locals, result)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.MethodCall {
        collect_free_vars(np_obj.get(node), params, locals, result)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                collect_free_vars(sublist_get(args_sl, ai), params, locals, result)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.IfExpr {
        collect_free_vars(np_condition.get(node), params, locals, result)
        collect_free_vars_block(np_then_body.get(node), params, locals, result)
        collect_free_vars_block(np_else_body.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.Block {
        collect_free_vars_block(node, params, locals, result)
        return
    }

    if kind == NodeKind.LetBinding {
        collect_free_vars(np_value.get(node), params, locals, result)
        let bound_name = np_name.get(node)
        if !list_contains_str(locals, bound_name) {
            locals.push(bound_name)
        }
        return
    }

    if kind == NodeKind.ForIn {
        collect_free_vars(np_iterable.get(node), params, locals, result)
        let vn = np_var_name.get(node)
        let mut inner_locals: List[Str] = []
        let mut li = 0
        while li < locals.len() {
            inner_locals.push(locals.get(li))
            li = li + 1
        }
        inner_locals.push(vn)
        collect_free_vars_block(np_body.get(node), params, inner_locals, result)
        return
    }

    if kind == NodeKind.WhileLoop {
        collect_free_vars(np_condition.get(node), params, locals, result)
        collect_free_vars_block(np_body.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.LoopExpr {
        collect_free_vars_block(np_body.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.Return {
        collect_free_vars(np_value.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.ExprStmt {
        collect_free_vars(np_value.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.Assignment {
        collect_free_vars(np_target.get(node), params, locals, result)
        collect_free_vars(np_value.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.CompoundAssign {
        collect_free_vars(np_target.get(node), params, locals, result)
        collect_free_vars(np_value.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.MatchExpr {
        collect_free_vars(np_scrutinee.get(node), params, locals, result)
        let arms_sl = np_arms.get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                collect_free_vars(np_guard.get(arm), params, locals, result)
                collect_free_vars(np_body.get(arm), params, locals, result)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.FieldAccess {
        collect_free_vars(np_obj.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.IndexExpr {
        collect_free_vars(np_obj.get(node), params, locals, result)
        collect_free_vars(np_index.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node)
        if parts_sl != -1 {
            let mut pi = 0
            while pi < sublist_length(parts_sl) {
                let part = sublist_get(parts_sl, pi)
                if np_kind.get(part) != NodeKind.Ident || np_str_val.get(part) == "" {
                    collect_free_vars(part, params, locals, result)
                }
                pi = pi + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        return
    }

    if kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                collect_free_vars(sublist_get(elems_sl, ei), params, locals, result)
                ei = ei + 1
            }
        }
        return
    }

    if kind == NodeKind.StructLit {
        let flds_sl = np_fields.get(node)
        if flds_sl != -1 {
            let mut fi = 0
            while fi < sublist_length(flds_sl) {
                let sf = sublist_get(flds_sl, fi)
                collect_free_vars(np_value.get(sf), params, locals, result)
                fi = fi + 1
            }
        }
        return
    }

    if kind == NodeKind.TupleLit {
        let elems_sl = np_elements.get(node)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                collect_free_vars(sublist_get(elems_sl, ei), params, locals, result)
                ei = ei + 1
            }
        }
        return
    }

    if kind == NodeKind.RangeLit {
        collect_free_vars(np_start.get(node), params, locals, result)
        collect_free_vars(np_end.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.WithBlock {
        let wh_sl = np_handlers.get(node)
        if wh_sl != -1 {
            let mut hi = 0
            while hi < sublist_length(wh_sl) {
                let hitem = sublist_get(wh_sl, hi)
                if np_kind.get(hitem) == NodeKind.WithResource {
                    collect_free_vars(np_value.get(hitem), params, locals, result)
                } else {
                    collect_free_vars(hitem, params, locals, result)
                }
                hi = hi + 1
            }
        }
        collect_free_vars_block(np_body.get(node), params, locals, result)
        return
    }

    if kind == NodeKind.WithResource {
        collect_free_vars(np_value.get(node), params, locals, result)
        return
    }
}

pub fn collect_free_vars_block(block: Int, params: List[Str], locals: List[Str], result: List[Str]) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
    if stmts_sl == -1 {
        return
    }
    let mut block_locals: List[Str] = []
    let mut li = 0
    while li < locals.len() {
        block_locals.push(locals.get(li))
        li = li + 1
    }
    let mut si = 0
    while si < sublist_length(stmts_sl) {
        collect_free_vars(sublist_get(stmts_sl, si), params, block_locals, result)
        si = si + 1
    }
}

pub fn analyze_captures(body: Int, params_sl: Int) -> List[Str] {
    let mut param_names: List[Str] = []
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            param_names.push(np_name.get(p))
            i = i + 1
        }
    }
    let mut locals: List[Str] = []
    let mut result: List[Str] = []
    collect_free_vars_block(body, param_names, locals, result)
    result
}

// Prescan: collect all let-mut names from a block (non-recursive into closures)
pub let mut prescan_mut_names: List[Str] = []

pub fn prescan_collect_muts(node: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)
    if kind == NodeKind.LetBinding {
        if np_is_mut.get(node) != 0 {
            prescan_mut_names.push(np_name.get(node))
        }
        return
    }
    if kind == NodeKind.Block {
        prescan_collect_muts_block(node)
        return
    }
    if kind == NodeKind.IfExpr {
        prescan_collect_muts_block(np_then_body.get(node))
        prescan_collect_muts_block(np_else_body.get(node))
        return
    }
    if kind == NodeKind.WhileLoop {
        prescan_collect_muts_block(np_body.get(node))
        return
    }
    if kind == NodeKind.ForIn {
        prescan_collect_muts_block(np_body.get(node))
        return
    }
    if kind == NodeKind.LoopExpr {
        prescan_collect_muts_block(np_body.get(node))
        return
    }
    if kind == NodeKind.WithBlock {
        prescan_collect_muts_block(np_body.get(node))
        return
    }
}

pub fn prescan_collect_muts_block(block: Int) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        prescan_collect_muts(sublist_get(stmts_sl, i))
        i = i + 1
    }
}

// Prescan: collect all idents used inside closure bodies
pub let mut prescan_closure_idents: List[Str] = []

pub fn prescan_collect_closure_idents(node: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)
    if kind == NodeKind.Ident {
        prescan_closure_idents.push(np_name.get(node))
        return
    }
    if kind == NodeKind.BinOp {
        prescan_collect_closure_idents(np_left.get(node))
        prescan_collect_closure_idents(np_right.get(node))
        return
    }
    if kind == NodeKind.UnaryOp {
        prescan_collect_closure_idents(np_left.get(node))
        return
    }
    if kind == NodeKind.Call {
        prescan_collect_closure_idents(np_left.get(node))
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                prescan_collect_closure_idents(sublist_get(args_sl, ai))
                ai = ai + 1
            }
        }
        return
    }
    if kind == NodeKind.MethodCall {
        prescan_collect_closure_idents(np_obj.get(node))
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                prescan_collect_closure_idents(sublist_get(args_sl, ai))
                ai = ai + 1
            }
        }
        return
    }
    if kind == NodeKind.Assignment {
        prescan_collect_closure_idents(np_target.get(node))
        prescan_collect_closure_idents(np_value.get(node))
        return
    }
    if kind == NodeKind.CompoundAssign {
        prescan_collect_closure_idents(np_target.get(node))
        prescan_collect_closure_idents(np_value.get(node))
        return
    }
    if kind == NodeKind.LetBinding {
        prescan_collect_closure_idents(np_value.get(node))
        return
    }
    if kind == NodeKind.ExprStmt {
        prescan_collect_closure_idents(np_value.get(node))
        return
    }
    if kind == NodeKind.Return {
        prescan_collect_closure_idents(np_value.get(node))
        return
    }
    if kind == NodeKind.Block {
        prescan_collect_closure_idents_block(node)
        return
    }
    if kind == NodeKind.IfExpr {
        prescan_collect_closure_idents(np_condition.get(node))
        prescan_collect_closure_idents_block(np_then_body.get(node))
        prescan_collect_closure_idents_block(np_else_body.get(node))
        return
    }
    if kind == NodeKind.WhileLoop {
        prescan_collect_closure_idents(np_condition.get(node))
        prescan_collect_closure_idents_block(np_body.get(node))
        return
    }
    if kind == NodeKind.ForIn {
        prescan_collect_closure_idents(np_iterable.get(node))
        prescan_collect_closure_idents_block(np_body.get(node))
        return
    }
    if kind == NodeKind.LoopExpr {
        prescan_collect_closure_idents_block(np_body.get(node))
        return
    }
    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node)
        if parts_sl != -1 {
            let mut pi = 0
            while pi < sublist_length(parts_sl) {
                prescan_collect_closure_idents(sublist_get(parts_sl, pi))
                pi = pi + 1
            }
        }
        return
    }
    if kind == NodeKind.FieldAccess {
        prescan_collect_closure_idents(np_obj.get(node))
        return
    }
    if kind == NodeKind.IndexExpr {
        prescan_collect_closure_idents(np_obj.get(node))
        prescan_collect_closure_idents(np_index.get(node))
        return
    }
    if kind == NodeKind.MatchExpr {
        prescan_collect_closure_idents(np_scrutinee.get(node))
        let arms_sl = np_arms.get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                prescan_collect_closure_idents(np_body.get(arm))
                ai = ai + 1
            }
        }
        return
    }
}

pub fn prescan_collect_closure_idents_block(block: Int) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        prescan_collect_closure_idents(sublist_get(stmts_sl, i))
        i = i + 1
    }
}

// Walk function body looking for closures; for each, collect idents used in body
pub fn prescan_closures_in_node(node: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)

    if kind == NodeKind.Closure {
        prescan_collect_closure_idents_block(np_body.get(node))
        return
    }

    if kind == NodeKind.Block {
        prescan_closures_in_block(node)
        return
    }

    if kind == NodeKind.LetBinding {
        prescan_closures_in_node(np_value.get(node))
        return
    }

    if kind == NodeKind.ExprStmt {
        prescan_closures_in_node(np_value.get(node))
        return
    }

    if kind == NodeKind.Assignment {
        prescan_closures_in_node(np_value.get(node))
        return
    }

    if kind == NodeKind.CompoundAssign {
        prescan_closures_in_node(np_value.get(node))
        return
    }

    if kind == NodeKind.IfExpr {
        prescan_closures_in_node(np_condition.get(node))
        prescan_closures_in_block(np_then_body.get(node))
        prescan_closures_in_block(np_else_body.get(node))
        return
    }

    if kind == NodeKind.WhileLoop {
        prescan_closures_in_node(np_condition.get(node))
        prescan_closures_in_block(np_body.get(node))
        return
    }

    if kind == NodeKind.ForIn {
        prescan_closures_in_node(np_iterable.get(node))
        prescan_closures_in_block(np_body.get(node))
        return
    }

    if kind == NodeKind.LoopExpr {
        prescan_closures_in_block(np_body.get(node))
        return
    }

    if kind == NodeKind.Return {
        prescan_closures_in_node(np_value.get(node))
        return
    }

    if kind == NodeKind.Call {
        prescan_closures_in_node(np_left.get(node))
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                prescan_closures_in_node(sublist_get(args_sl, ai))
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.MethodCall {
        prescan_closures_in_node(np_obj.get(node))
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                prescan_closures_in_node(sublist_get(args_sl, ai))
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.BinOp {
        prescan_closures_in_node(np_left.get(node))
        prescan_closures_in_node(np_right.get(node))
        return
    }

    if kind == NodeKind.UnaryOp {
        prescan_closures_in_node(np_left.get(node))
        return
    }

    if kind == NodeKind.MatchExpr {
        prescan_closures_in_node(np_scrutinee.get(node))
        let arms_sl = np_arms.get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                prescan_closures_in_node(np_body.get(arm))
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.WithBlock {
        prescan_closures_in_block(np_body.get(node))
        return
    }
}

pub fn prescan_closures_in_block(block: Int) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        prescan_closures_in_node(sublist_get(stmts_sl, i))
        i = i + 1
    }
}

pub fn prescan_mut_captures(block: Int) {
    prescan_mut_names = []
    prescan_closure_idents = []
    prescan_collect_muts_block(block)
    prescan_closures_in_block(block)
    let mut i = 0
    while i < prescan_mut_names.len() {
        let mname = prescan_mut_names.get(i)
        let mut j = 0
        while j < prescan_closure_idents.len() {
            let cident = prescan_closure_idents.get(j)
            if mname == cident {
                if is_mut_captured(mname) == 0 {
                    mut_captured_vars.push(mname)
                }
            }
            j = j + 1
        }
        i = i + 1
    }
}

pub fn emit_closure(node: Int) {
    let closure_idx = cg_closure_counter
    let cname = "__closure_{closure_idx}"
    cg_closure_counter = cg_closure_counter + 1

    let params_sl = np_params.get(node)
    let ret_str = np_return_type.get(node)
    let ret_type = type_from_name(ret_str)

    // Capture analysis: find free variables before switching codegen context
    let captures = analyze_captures(np_body.get(node), params_sl)
    let cap_start = closure_captures.len()
    let mut cap_i = 0
    while cap_i < captures.len() {
        let cap_name = captures.get(cap_i)
        let cap_ct = get_var_type(cap_name)
        let cap_mut = if is_mut_captured(cap_name) != 0 { 1 } else { 0 }
        closure_captures.push(CaptureEntry { name: cap_name, ctype: cap_ct, is_mut: cap_mut })
        cap_i = cap_i + 1
    }
    closure_cap_infos.push(ClosureCapInfo { start: cap_start, count: captures.len() })

    // Build C parameter list: __self first if captures, then user params
    let has_caps = captures.len() > 0
    let mut params_c = "pact_closure* __self"
    if params_sl != -1 && sublist_length(params_sl) > 0 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            let ptype = np_type_name.get(p)
            params_c = params_c.concat(", ")
            if ptype == "Fn" {
                params_c = params_c.concat("pact_closure* {pname}")
            } else if is_enum_type(ptype) != 0 {
                params_c = params_c.concat("pact_{ptype} {pname}")
            } else if is_struct_type(ptype) != 0 {
                params_c = params_c.concat("pact_{ptype} {pname}")
            } else {
                let ct = type_from_name(ptype)
                params_c = params_c.concat("{c_type_str(ct)} {pname}")
            }
            i = i + 1
        }
    }

    let saved_lines = cg_lines
    let saved_indent = cg_indent
    let saved_temp = cg_temp_counter
    let saved_cap_start = cg_closure_cap_start
    let saved_cap_count = cg_closure_cap_count
    cg_lines = []
    cg_indent = 0
    cg_temp_counter = 0
    cg_closure_cap_start = cap_start
    cg_closure_cap_count = captures.len()

    push_scope()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            let ptype = np_type_name.get(p)
            if ptype == "Fn" {
                set_var(pname, CT_CLOSURE, 1)
                let ta = np_type_ann.get(p)
                if ta != -1 {
                    let sig_str = build_closure_sig_from_type_ann(ta)
                    set_var_closure(pname, sig_str)
                }
            } else {
                set_var(pname, type_from_name(ptype), 1)
                if is_struct_type(ptype) != 0 {
                    set_var_struct(pname, ptype)
                }
                if is_enum_type(ptype) != 0 {
                    var_enums.push(VarEnumEntry { name: pname, enum_type: ptype })
                }
            }
            i = i + 1
        }
    }

    emit_line("static {c_type_str(ret_type)} {cname}({params_c}) \{")
    cg_indent = cg_indent + 1
    let mut mc_done: List[Str] = []
    let mut mc_i = 0
    while mc_i < captures.len() {
        let mc_e = closure_captures.get(cap_start + mc_i)
        if mc_e.is_mut != 0 {
            let mut mc_dup = 0
            let mut mc_j = 0
            while mc_j < mc_i {
                if closure_captures.get(cap_start + mc_j).name == mc_e.name {
                    mc_dup = 1
                }
                mc_j = mc_j + 1
            }
            if mc_dup == 0 {
                let mc_ts = c_type_str(mc_e.ctype)
                emit_line("{mc_ts}* {mc_e.name}_cell = ({mc_ts}*)pact_closure_get_capture(__self, {mc_i});")
            }
        }
        mc_i = mc_i + 1
    }
    emit_fn_body(np_body.get(node), ret_type)
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")

    pop_scope()

    let closure_lines = cg_lines
    cg_lines = saved_lines
    cg_indent = saved_indent
    cg_temp_counter = saved_temp
    cg_closure_cap_start = saved_cap_start
    cg_closure_cap_count = saved_cap_count

    let mut ci = 0
    while ci < closure_lines.len() {
        cg_closure_defs.push(closure_lines.get(ci))
        ci = ci + 1
    }

    // Build C function pointer signature for closure calls
    let mut sig_params = "pact_closure*"
    if params_sl != -1 && sublist_length(params_sl) > 0 {
        let mut si = 0
        while si < sublist_length(params_sl) {
            let sp = sublist_get(params_sl, si)
            let sptype = np_type_name.get(sp)
            sig_params = sig_params.concat(", ")
            if sptype == "Fn" {
                sig_params = sig_params.concat("pact_closure*")
            } else if is_enum_type(sptype) != 0 {
                sig_params = sig_params.concat("pact_{sptype}")
            } else if is_struct_type(sptype) != 0 {
                sig_params = sig_params.concat("pact_{sptype}")
            } else {
                sig_params = sig_params.concat(c_type_str(type_from_name(sptype)))
            }
            si = si + 1
        }
    }
    expr_closure_sig = "{c_type_str(ret_type)}(*)({sig_params})"

    // Build captures array if needed
    if captures.len() > 0 {
        let caps_var = "__caps_{closure_idx}"
        emit_line("void** {caps_var} = (void**)pact_alloc(sizeof(void*) * {captures.len()});")
        let mut ci2 = 0
        while ci2 < captures.len() {
            let cap_e = closure_captures.get(cap_start + ci2)
            if cap_e.is_mut != 0 {
                emit_line("{caps_var}[{ci2}] = (void*){cap_e.name}_cell;")
            } else if cap_e.ctype == CT_INT {
                emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
            } else if cap_e.ctype == CT_FLOAT {
                emit_line("\{double* __fp_{closure_idx}_{ci2} = (double*)pact_alloc(sizeof(double)); *__fp_{closure_idx}_{ci2} = {cap_e.name}; {caps_var}[{ci2}] = (void*)__fp_{closure_idx}_{ci2};}")
            } else if cap_e.ctype == CT_BOOL {
                emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
            } else {
                emit_line("{caps_var}[{ci2}] = (void*){cap_e.name};")
            }
            ci2 = ci2 + 1
        }
        expr_result_str = "pact_closure_new((void*){cname}, {caps_var}, {captures.len()})"
    } else {
        expr_result_str = "pact_closure_new((void*){cname}, NULL, 0)"
    }
    expr_result_type = CT_CLOSURE
}
