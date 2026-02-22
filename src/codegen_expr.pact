import codegen_types
import codegen_methods
import codegen_closures
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
pub fn iter_from_source(obj_str: Str, obj_type: Int) ! Codegen.Emit {
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

pub fn emit_expr(node: Int) ! Codegen.Emit {
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

pub fn emit_handler_expr(node: Int) ! Codegen.Emit {
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

pub fn emit_async_spawn_closure(closure_node: Int, wrapper_idx: Int, wrapper_name: Str, task_fn_name: Str) ! Codegen.Emit {
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

pub fn emit_await_expr(node: Int) ! Codegen.Emit {
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

pub fn emit_async_scope(node: Int) ! Codegen.Emit {
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

pub fn emit_binop(node: Int) ! Codegen.Emit {
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

pub fn emit_unaryop(node: Int) ! Codegen.Emit {
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

pub fn emit_call(node: Int) ! Codegen.Emit {
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

        if fn_name == "debug_assert" {
            let args_sl = np_args.get(node)
            if cg_debug_mode == 0 {
                expr_result_str = ""
                expr_result_type = CT_VOID
                return
            }
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let cond_str = expr_result_str
                let mut msg_str = "\"debug assertion failed\""
                if sublist_length(args_sl) >= 2 {
                    emit_expr(sublist_get(args_sl, 1))
                    msg_str = expr_result_str
                }
                emit_line("\{")
                cg_indent = cg_indent + 1
                emit_line("int64_t _dbg_val = (int64_t)({cond_str});")
                emit_line("if (!_dbg_val) \{")
                cg_indent = cg_indent + 1
                emit_line("__pact_debug_assert_fail(\"{diag_source_file}\", {call_line}, \"{cg_current_fn_name}\", \"{cond_str}\", {msg_str});")
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
        if fn_name == "get_env" {
            let args_sl = np_args.get(node)
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("_env_")
            emit_line("const char* {tmp} = getenv({arg_str});")
            emit_line("if ({tmp} == NULL) {tmp} = \"\";")
            expr_result_str = tmp
            expr_result_type = CT_STRING
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

pub fn emit_interp_string(node: Int) ! Codegen.Emit {
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

pub fn emit_list_lit(node: Int) ! Codegen.Emit {
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

pub fn emit_struct_lit(node: Int) ! Codegen.Emit {
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
