import codegen_types
import codegen_methods
import codegen_closures
import diagnostics
import std.path

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
pub let mut expr_result_ok_struct: Str = ""
pub let mut expr_result_err_struct: Str = ""
pub let mut expr_option_inner_struct: Str = ""
pub let mut expr_list_elem_type: Int = -1
pub let mut expr_list_elem_struct: Str = ""
pub let mut expr_map_key_type: Int = -1
pub let mut expr_map_val_type: Int = -1
pub let mut expr_option_inner_list_elem: Int = -1
pub let mut expr_option_inner_list_struct: Str = ""
let mut expr_iter_next_fn: Str = ""

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
        let mut elem_type = get_list_elem_type(obj_str)
        if elem_type == -1 { elem_type = CT_INT }
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

fn propagate_enum_struct(name: Str, result_str: Str) {
    if get_var_struct(name) == "" {
        let ve = get_var_enum(name)
        if ve != "" && is_data_enum(ve) != 0 {
            set_var_struct(result_str, ve)
        }
    }
}

@allow(UnrestoredMutation, IncompleteStateRestore)
pub fn emit_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let kind = np_kind.get(node).unwrap()
    expr_closure_sig = ""

    if kind == NodeKind.IntLit {
        let s = np_str_val.get(node).unwrap()
        if s == "" {
            expr_result_str = "{np_int_val.get(node).unwrap()}"
        } else {
            expr_result_str = s
        }
        expr_result_type = CT_INT
        return
    }

    if kind == NodeKind.FloatLit {
        expr_result_str = np_str_val.get(node).unwrap()
        expr_result_type = CT_FLOAT
        return
    }

    if kind == NodeKind.BoolLit {
        if np_int_val.get(node).unwrap() != 0 {
            expr_result_str = "1"
        } else {
            expr_result_str = "0"
        }
        expr_result_type = CT_BOOL
        return
    }

    if kind == NodeKind.Ident {
        let name = np_name.get(node).unwrap()
        if name == "self" && cg_where_self_var != "" {
            expr_result_str = cg_where_self_var
            expr_result_type = CT_INT
            return
        }
        if name == "None" {
            let fsi = get_fn_ret_struct_inner(cg_current_fn_name)
            if fsi.ok_struct != "" && cg_current_fn_ret == CT_OPTION {
                ensure_struct_option_type(fsi.ok_struct)
                let opt_type = struct_option_c_type(fsi.ok_struct)
                expr_result_str = "({opt_type})\{.tag = 0}"
                expr_result_type = CT_OPTION
                expr_option_inner = CT_INT
                expr_option_inner_struct = fsi.ok_struct
            } else {
                let none_inner = if cg_current_fn_option_inner != 0 { cg_current_fn_option_inner } else { CT_INT }
                ensure_option_type(none_inner)
                let opt_type = option_c_type(none_inner)
                expr_result_str = "({opt_type})\{.tag = 0}"
                expr_result_type = CT_OPTION
                expr_option_inner = none_inner
                expr_option_inner_struct = ""
            }
            return
        }
        let variant_enum2 = resolve_variant(name)
        if variant_enum2 != "" {
            if is_data_enum(variant_enum2) != 0 {
                let tag = get_variant_tag(variant_enum2, name)
                expr_result_str = "({c_type_c_name(variant_enum2)})\{.tag = {tag}}"
                expr_result_type = CT_VOID
                set_var_struct(expr_result_str, variant_enum2)
                return
            }
            expr_result_str = "{c_type_c_name(variant_enum2)}_{name}"
            expr_result_type = CT_INT
            return
        }
        let safe = c_safe_name(name)
        let cap_idx = get_capture_index(name)
        if cap_idx >= 0 {
            let cap_entry = closure_captures.get(cg_closure_cap_start + cap_idx).unwrap()
            if cap_entry.is_mut != 0 {
                expr_result_str = "(*{safe}_cell)"
                expr_result_type = tp_get_kind(cap_entry.tp_id)
                return
            }
            expr_result_str = capture_cast_expr(cap_idx)
            expr_result_type = tp_get_kind(cap_entry.tp_id)
            return
        }
        if is_mut_captured(name) != 0 {
            let mut is_closure_param = 0
            let mut cpi = 0
            while cpi < closure_param_names.len() {
                if closure_param_names.get(cpi).unwrap() == name {
                    is_closure_param = 1
                }
                cpi = cpi + 1
            }
            if is_closure_param == 0 {
                expr_result_str = "(*{safe}_cell)"
                expr_result_type = get_var_type(name)
                return
            }
        }
        let alias = get_var_alias(name)
        if alias != "" {
            expr_result_str = alias
        } else {
            expr_result_str = safe
        }
        expr_result_type = get_var_type(name)
        if expr_result_type == CT_OPTION {
            expr_option_inner = get_var_option_inner(name)
            expr_option_inner_struct = get_var_option_inner_struct(name)
            if expr_option_inner == CT_LIST {
                expr_option_inner_list_elem = get_var_option_inner2(name)
                expr_option_inner_list_struct = get_var_option_inner2_struct(name)
            }
        }
        if expr_result_type == CT_RESULT {
            expr_result_ok_type = get_var_result_ok(name)
            expr_result_err_type = get_var_result_err(name)
            expr_result_ok_struct = get_var_result_ok_struct(name)
            expr_result_err_struct = get_var_result_err_struct(name)
        }
        if expr_result_type == CT_ITERATOR {
            expr_iter_next_fn = get_var_iter_next_fn(name)
        }
        if expr_result_type == CT_LIST {
            expr_list_elem_type = get_list_elem_type(name)
            expr_list_elem_struct = get_list_elem_struct(name)
        }
        if expr_result_type == CT_VOID {
            propagate_enum_struct(name, expr_result_str)
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
        let fa_obj = np_obj.get(node).unwrap()
        let fa_field = np_name.get(node).unwrap()
        if np_kind.get(fa_obj).unwrap() == NodeKind.Ident {
            let obj_name = np_name.get(fa_obj).unwrap()
            if is_enum_type(obj_name) != 0 {
                if is_data_enum(obj_name) != 0 {
                    let tag = get_variant_tag(obj_name, fa_field)
                    expr_result_str = "({c_type_c_name(obj_name)})\{.tag = {tag}}"
                    expr_result_type = CT_VOID
                    set_var_struct(expr_result_str, obj_name)
                    return
                }
                expr_result_str = "{c_type_c_name(obj_name)}_{fa_field}"
                expr_result_type = CT_INT
                return
            }
        }
        emit_expr(fa_obj)
        let obj_str = expr_result_str
        let mut c_field = fa_field
        if fa_field.len() > 0 && fa_field.char_at(0) >= 48 && fa_field.char_at(0) <= 57 {
            c_field = "_{fa_field}"
        }
        expr_result_str = "{obj_str}.{c_field}"
        let mut fa_type = CT_VOID
        let struct_type = get_var_struct(obj_str)
        if struct_type != "" {
            fa_type = get_struct_field_type(struct_type, c_field)
            let fa_stype = get_struct_field_stype(struct_type, c_field)
            if fa_stype != "" {
                set_var_struct(expr_result_str, fa_stype)
            }
            if fa_type == CT_CLOSURE {
                let cls_sig = get_struct_field_closure_sig(struct_type, c_field)
                if cls_sig != "" {
                    set_var_closure(expr_result_str, cls_sig)
                    expr_closure_sig = cls_sig
                }
            }
            if fa_type == CT_LIST {
                let le_struct = get_struct_field_list_elem(struct_type, c_field)
                if le_struct != "" {
                    set_list_elem_struct(expr_result_str, le_struct)
                    set_list_elem_type(expr_result_str, CT_VOID)
                } else {
                    let le_type = get_struct_field_list_elem_type(struct_type, c_field)
                    if le_type != CT_INT {
                        set_list_elem_type(expr_result_str, le_type)
                    }
                }
            }
        }
        expr_result_type = fa_type
        return
    }

    if kind == NodeKind.IndexExpr {
        emit_expr(np_obj.get(node).unwrap())
        let obj_str = expr_result_str
        let obj_type = expr_result_type
        emit_expr(np_index.get(node).unwrap())
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
        if np_value.get(node).unwrap() != -1 {
            emit_expr(np_value.get(node).unwrap())
            emit_return_with_trace(expr_result_str, cg_current_fn_ret)
        } else {
            emit_trace_exit_void()
            emit_line("return;")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    if kind == NodeKind.TupleLit {
        emit_tuple_lit(node)
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
        let args_sl = np_args.get(node).unwrap()
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

    if kind == NodeKind.EmbedExpr {
        let embed_path = np_str_val.get(node).unwrap()
        let source_dir = path_dirname(diag_source_file)
        let full_path = if source_dir != "" {
            "{source_dir}/{embed_path}"
        } else {
            embed_path
        }
        if file_exists(full_path) != 1 {
            diag_error("FileNotFound", "E1108", "#embed file not found: {full_path}", np_line.get(node).unwrap(), np_col.get(node).unwrap(), "")
            expr_result_str = "\"\""
            expr_result_type = CT_STRING
            return
        }
        let content = read_file(full_path)
        let escaped = escape_c_string(content)
        expr_result_str = "\"".concat(escaped).concat("\"")
        expr_result_type = CT_STRING
        return
    }

    if kind == NodeKind.NamedArg {
        let inner = np_value.get(node).unwrap()
        emit_expr(inner)
        return
    }

    expr_result_str = "0"
    expr_result_type = CT_VOID
}

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_handler_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let effect_name = np_name.get(node).unwrap()
    let methods_sl = np_methods.get(node).unwrap()
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
            let ue = ue_effects.get(uei).unwrap()
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
            let mname = np_name.get(m).unwrap()
            let static_name = "__handler_{handler_idx}_{mname}"
            let mut param_str = ""
            let params_sl = np_params.get(m).unwrap()
            if params_sl != -1 {
                let mut pi = 0
                while pi < sublist_length(params_sl) {
                    if pi > 0 {
                        param_str = param_str.concat(", ")
                    }
                    let p = sublist_get(params_sl, pi)
                    let pname = np_name.get(p).unwrap()
                    let ptype = np_type_name.get(p).unwrap()
                    let ct = type_from_name(ptype)
                    param_str = param_str.concat("{c_type_str(ct)} {pname}")
                    pi = pi + 1
                }
            }
            if param_str == "" {
                param_str = "void"
            }
            let ret_str = np_return_type.get(m).unwrap()
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
                    let pname = np_name.get(p).unwrap()
                    let ptype = np_type_name.get(p).unwrap()
                    set_var(pname, type_from_name(ptype), 0)
                    pi = pi + 1
                }
            }
            emit_fn_body(np_body.get(m).unwrap(), ret_type)
            pop_scope()
            let mut li = 0
            while li < cg_lines.len() {
                cg_closure_defs.push(cg_lines.get(li).unwrap())
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
    emit_line("{vtable_type} {vt_name} = *{outer_ptr_name};")
    if methods_sl != -1 {
        let mut mi = 0
        while mi < sublist_length(methods_sl) {
            let m = sublist_get(methods_sl, mi)
            let mname = np_name.get(m).unwrap()
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

@allow(UnrestoredMutation, IncompleteStateRestore)
pub fn emit_async_spawn_closure(closure_node: Int, wrapper_idx: Int, wrapper_name: Str, task_fn_name: Str) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let cl_params_sl = np_params.get(closure_node).unwrap()
    let captures = analyze_captures(np_body.get(closure_node).unwrap(), cl_params_sl)
    let cap_start = closure_captures.len()
    let mut cap_i = 0
    while cap_i < captures.len() {
        let cap_tp = get_var_tp(captures.get(cap_i).unwrap())
        let cap_mut = if is_mut_captured(captures.get(cap_i).unwrap()) != 0 { 1 } else { 0 }
        closure_captures.push(CaptureEntry { name: captures.get(cap_i).unwrap(), is_mut: cap_mut, tp_id: cap_tp })
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

    let saved_in_traced = cg_in_traced_fn
    cg_in_traced_fn = 0
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

    let mut task_params = "const pact_closure* __self"
    emit_line("static int64_t {task_fn_name}({task_params}) \{")
    cg_indent = cg_indent + 1

    let mut mc_i = 0
    while mc_i < captures.len() {
        let mc_e = closure_captures.get(cap_start + mc_i).unwrap()
        if mc_e.is_mut != 0 {
            let mc_ts = c_type_str(tp_get_kind(mc_e.tp_id))
            emit_line("{mc_ts}* {mc_e.name}_cell = ({mc_ts}*)pact_closure_get_capture(__self, {mc_i});")
        }
        mc_i = mc_i + 1
    }

    let cl_body = np_body.get(closure_node).unwrap()
    let cl_ret_str = np_return_type.get(closure_node).unwrap()
    if cl_ret_str == "Void" || (cl_ret_str == "" && infer_block_type(cl_body) == CT_VOID) {
        emit_fn_body(cl_body, CT_VOID)
        emit_line("return 0;")
    } else {
        emit_fn_body(cl_body, CT_INT)
    }
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
    cg_in_traced_fn = saved_in_traced

    let mut tli = 0
    while tli < task_lines.len() {
        cg_closure_defs.push(task_lines.get(tli).unwrap())
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

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_await_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    emit_expr(np_obj.get(node).unwrap())
    let handle_str = expr_result_str
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

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_async_scope(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    cg_uses_async = 1
    let scope_idx = cg_async_scope_counter
    cg_async_scope_counter = cg_async_scope_counter + 1
    let list_name = "__scope_handles_{scope_idx}"
    emit_line("pact_list* {list_name} = pact_list_new();")
    cg_async_scope_stack.push(list_name)
    emit_block_expr(np_body.get(node).unwrap())
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

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_binop(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let op = np_op.get(node).unwrap()
    if op == "??" {
        emit_expr(np_left.get(node).unwrap())
        let left_str = expr_result_str
        let left_type = expr_result_type
        let opt_inner = expr_option_inner
        let opt_inner_s = expr_option_inner_struct
        if left_type == CT_BOOL || left_type == CT_FLOAT || left_type == CT_STRING || left_type == CT_LIST || left_type == CT_RESULT || left_type == CT_CLOSURE {
            diag_error_at("CoalesceRequiresOption", "E0502", "the ?? operator requires an Option value but got a non-Option type in function '{cg_current_fn_name}'", node, "")
        }
        emit_expr(np_right.get(node).unwrap())
        let right_str = expr_result_str
        let right_type = expr_result_type
        let tmp = fresh_temp("__opt")
        if opt_inner_s != "" {
            let opt_c = struct_option_c_type(opt_inner_s)
            emit_line("{opt_c} {tmp} = {left_str};")
            let val_tmp = fresh_temp("__optv")
            emit_line("{c_type_c_name(opt_inner_s)} {val_tmp} = {tmp}.tag == 1 ? {tmp}.value : {right_str};")
            set_var_struct(val_tmp, opt_inner_s)
            expr_result_str = val_tmp
            expr_result_type = right_type
        } else if opt_inner == CT_LIST {
            let opt_c = option_c_type(CT_LIST)
            emit_line("{opt_c} {tmp} = {left_str};")
            let val_tmp = fresh_temp("__optv")
            emit_line("pact_list* {val_tmp} = {tmp}.tag == 1 ? {tmp}.value : {right_str};")
            set_var(val_tmp, CT_LIST, 0)
            let inner2 = expr_option_inner_list_elem
            if inner2 >= 0 {
                set_list_elem_type(val_tmp, inner2)
                expr_list_elem_type = inner2
            }
            let inner2_s = expr_option_inner_list_struct
            if inner2_s != "" {
                set_list_elem_struct(val_tmp, inner2_s)
            }
            expr_result_str = val_tmp
            expr_result_type = CT_LIST
        } else if opt_inner >= 0 {
            let opt_c = option_c_type(opt_inner)
            emit_line("{opt_c} {tmp} = {left_str};")
            expr_result_str = "({tmp}.tag == 1 ? {tmp}.value : {right_str})"
            expr_result_type = right_type
        } else {
            emit_line("const int64_t {tmp} = (int64_t){left_str};")
            expr_result_str = "({tmp}.tag == 1 ? {tmp}.value : {right_str})"
            expr_result_type = right_type
        }
        return
    }
    emit_expr(np_left.get(node).unwrap())
    let left_str = expr_result_str
    let left_type = expr_result_type

    if op == "&&" || op == "||" {
        let pre_len = cg_lines.len()
        emit_expr(np_right.get(node).unwrap())
        let right_str = expr_result_str
        let post_len = cg_lines.len()
        if post_len > pre_len {
            let mut rhs_lines: List[Str] = []
            let mut ri = pre_len
            while ri < post_len {
                rhs_lines.push(cg_lines.get(ri).unwrap())
                ri = ri + 1
            }
            let mut pi = post_len - 1
            while pi >= pre_len {
                cg_lines.pop()
                pi = pi - 1
            }
            let sc_tmp = fresh_temp("__sc")
            emit_line("int64_t {sc_tmp};")
            if op == "&&" {
                emit_line("if ({left_str}) \{")
            } else {
                emit_line("if (!({left_str})) \{")
            }
            cg_indent = cg_indent + 1
            let mut si = 0
            while si < rhs_lines.len() {
                cg_lines.push(rhs_lines.get(si).unwrap())
                si = si + 1
            }
            emit_line("{sc_tmp} = ({right_str}) ? 1 : 0;")
            cg_indent = cg_indent - 1
            if op == "&&" {
                emit_line("} else \{ {sc_tmp} = 0; }")
            } else {
                emit_line("} else \{ {sc_tmp} = 1; }")
            }
            expr_result_str = sc_tmp
            expr_result_type = CT_BOOL
        } else {
            expr_result_str = "({left_str} {op} {right_str})"
            expr_result_type = CT_BOOL
        }
        return
    }

    emit_expr(np_right.get(node).unwrap())
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
    if op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" {
        expr_result_type = CT_BOOL
    } else {
        expr_result_type = left_type
    }
}

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_unaryop(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    emit_expr(np_left.get(node).unwrap())
    let operand_str = expr_result_str
    let operand_type = expr_result_type
    let op = np_op.get(node).unwrap()
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
                diag_error_at("QuestionMarkResultInNonResult", "E0508", "'?' on Result in function '{cg_current_fn_name}' which does not return Result", node, "change the return type to Result")
                diag_set_last_fix("replace", "-> Result[T, E]")
                expr_result_str = "0"
                expr_result_type = CT_INT
            } else {
                let rok = expr_result_ok_type
                let rerr = expr_result_err_type
                let rok_s = expr_result_ok_struct
                let rerr_s = expr_result_err_struct
                if rok_s != "" || rerr_s != "" {
                    let res_c = result_c_type_mixed(rok, rerr, rok_s, rerr_s)
                    let fn_fsi = get_fn_ret_struct_inner(cg_current_fn_name)
                    let fn_ok_s = fn_fsi.ok_struct
                    let fn_err_s = fn_fsi.err_struct
                    let fn_rt = get_fn_ret_type(cg_current_fn_name)
                    let fn_res_c = result_c_type_mixed(tp_child1_kind(fn_rt.tp_id), tp_child2_kind(fn_rt.tp_id), fn_ok_s, fn_err_s)
                    emit_line("{res_c} {tmp} = {operand_str};")
                    emit_line("if ({tmp}.tag == 1) return ({fn_res_c})\{.tag = 1, .err = {tmp}.err};")
                    expr_result_str = "{tmp}.ok"
                    if rok_s != "" {
                        expr_result_type = CT_INT
                        set_var_struct(expr_result_str, rok_s)
                    } else {
                        expr_result_type = rok
                    }
                    expr_result_ok_struct = ""
                    expr_result_err_struct = ""
                } else {
                    let res_c = result_c_type(rok, rerr)
                    emit_line("{res_c} {tmp} = {operand_str};")
                    emit_line("if ({tmp}.tag == 1) return ({res_c})\{.tag = 1, .err = {tmp}.err};")
                    expr_result_str = "{tmp}.ok"
                    expr_result_type = rok
                }
            }
        } else if operand_type == CT_OPTION {
            if cg_current_fn_ret != CT_OPTION {
                diag_error_at("QuestionMarkOptionInNonOption", "E0509", "'?' on Option in function '{cg_current_fn_name}' which does not return Option", node, "change the return type to Option")
                diag_set_last_fix("replace", "-> Option[T]")
            } else {
                diag_error_at("QuestionMarkInvalidOperand", "E0502", "'?' on Option is not yet supported, use '??' instead", node, "")
            }
            expr_result_str = "0"
            expr_result_type = CT_INT
        } else {
            diag_error_at("QuestionMarkInvalidOperand", "E0502", "'?' requires a Result or Option value", node, "")
            expr_result_str = "0"
            expr_result_type = CT_INT
        }
    } else {
        expr_result_str = "({op}{operand_str})"
        expr_result_type = operand_type
    }
}

let mut reorder_result: List[Int] = []

fn reorder_named_args(fn_name: Str, args_sl: Int, call_node: Int) ! Diag.Report {
    reorder_result = []
    if args_sl == -1 {
        return
    }
    let argc = sublist_length(args_sl)
    if argc == 0 {
        return
    }
    let mut positional_end = -1
    let mut i = 0
    while i < argc {
        let arg = sublist_get(args_sl, i)
        if np_kind.get(arg).unwrap() == NodeKind.NamedArg {
            positional_end = i
            i = argc
        }
        i = i + 1
    }
    if positional_end == -1 {
        return
    }
    let fn_node = get_fn_node(fn_name)
    if fn_node == -1 {
        return
    }
    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl == -1 {
        return
    }
    let param_count = sublist_length(params_sl)
    i = positional_end
    while i < argc {
        let arg = sublist_get(args_sl, i)
        if np_kind.get(arg).unwrap() == NodeKind.NamedArg {
            let label = np_name.get(arg).unwrap()
            let mut valid = 0
            let mut k = 0
            while k < param_count {
                let pk = sublist_get(params_sl, k)
                if np_name.get(pk).unwrap() == label {
                    valid = 1
                    k = param_count
                }
                k = k + 1
            }
            if valid == 0 {
                diag_error_at("InvalidKeywordArg", "E0511", "no parameter named '{label}' in function '{fn_name}'", call_node, "check the function signature")
                return
            }
        } else {
            diag_error_at("InvalidKeywordArg", "E0511", "positional argument after named argument in call to '{fn_name}'", call_node, "place all positional arguments before named arguments")
            return
        }
        i = i + 1
    }
    let mut result: List[Int] = []
    i = 0
    while i < positional_end {
        result.push(sublist_get(args_sl, i))
        i = i + 1
    }
    i = positional_end
    while i < param_count {
        let param_node = sublist_get(params_sl, i)
        let param_name = np_name.get(param_node).unwrap()
        let mut found = 0
        let mut j = positional_end
        while j < argc {
            let arg = sublist_get(args_sl, j)
            if np_kind.get(arg).unwrap() == NodeKind.NamedArg {
                let label = np_name.get(arg).unwrap()
                if label == param_name {
                    result.push(arg)
                    found = 1
                    j = argc
                }
            }
            j = j + 1
        }
        if found == 0 {
            diag_error_at("MissingKeywordArg", "E0510", "missing keyword argument '{param_name}' in call to '{fn_name}'", call_node, "add '{param_name}: <value>'")
            return
        }
        i = i + 1
    }
    reorder_result = result
}

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_call(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let func_node = np_left.get(node).unwrap()
    let func_kind = np_kind.get(func_node).unwrap()
    if func_kind == NodeKind.Ident {
        let fn_name = np_name.get(func_node).unwrap()
        let call_line = np_line.get(func_node).unwrap()

        if fn_name == "assert" {
            let args_sl = np_args.get(node).unwrap()
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
            let args_sl = np_args.get(node).unwrap()
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
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) >= 2 {
                emit_expr(sublist_get(args_sl, 0))
                let left_str = expr_result_str
                let left_type = expr_result_type
                let left_ok = expr_result_ok_type
                let left_err = expr_result_err_type
                let left_ok_s = expr_result_ok_struct
                let left_err_s = expr_result_err_struct
                let left_opt_inner = expr_option_inner
                let left_opt_inner_s = expr_option_inner_struct
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
                } else if left_type == CT_RESULT {
                    let res_c = if left_ok_s != "" || left_err_s != "" {
                        result_c_type_mixed(left_ok, left_err, left_ok_s, left_err_s)
                    } else {
                        result_c_type(left_ok, left_err)
                    }
                    emit_line("{res_c} _left = {left_str};")
                    emit_line("{res_c} _right = {right_str};")
                    emit_line("if (memcmp(&_left, &_right, sizeof({res_c})) != 0) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp4 = fresh_temp("_msg")
                    emit_line("char {msg_tmp4}[256];")
                    emit_line("snprintf({msg_tmp4}, 256, \"ASSERT_EQ FAILED: Result values differ (tag %%lld vs %%lld)\", (long long)_left.tag, (long long)_right.tag);")
                    emit_line("__pact_assert_fail({msg_tmp4}, {call_line});")
                    cg_indent = cg_indent - 1
                    emit_line("}")
                } else if left_type == CT_OPTION {
                    let opt_c = if left_opt_inner_s != "" {
                        struct_option_c_type(left_opt_inner_s)
                    } else {
                        option_c_type(left_opt_inner)
                    }
                    emit_line("{opt_c} _left = {left_str};")
                    emit_line("{opt_c} _right = {right_str};")
                    emit_line("if (memcmp(&_left, &_right, sizeof({opt_c})) != 0) \{")
                    cg_indent = cg_indent + 1
                    let msg_tmp5 = fresh_temp("_msg")
                    emit_line("char {msg_tmp5}[256];")
                    emit_line("snprintf({msg_tmp5}, 256, \"ASSERT_EQ FAILED: Option values differ (tag %%lld vs %%lld)\", (long long)_left.tag, (long long)_right.tag);")
                    emit_line("__pact_assert_fail({msg_tmp5}, {call_line});")
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
            let args_sl = np_args.get(node).unwrap()
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
            let args_sl = np_args.get(node).unwrap()
            let mut init_str = "({c_type_c_name(variant_enum)})\{.tag = {tag}"
            if fcount > 0 && args_sl != -1 {
                init_str = init_str.concat(", .data.{fn_name} = \{")
                let mut fi = 0
                while fi < sublist_length(args_sl) && fi < fcount {
                    if fi > 0 {
                        init_str = init_str.concat(", ")
                    }
                    let field_name = get_variant_field_name(vidx, fi).unwrap()
                    emit_expr(sublist_get(args_sl, fi))
                    let arg_str = expr_result_str
                    init_str = init_str.concat(".{field_name} = {arg_str}")
                    fi = fi + 1
                }
                init_str = init_str.concat("}")
            }
            init_str = init_str.concat("}")
            expr_result_str = init_str
            expr_result_type = CT_VOID
            set_var_struct(init_str, variant_enum)
            return
        }
        if fn_name == "Some" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let inner_str = expr_result_str
                let inner_type = expr_result_type
                let inner_s = get_var_struct(inner_str)
                if inner_s != "" {
                    ensure_struct_option_type(inner_s)
                    let opt_type = struct_option_c_type(inner_s)
                    expr_result_str = "({opt_type})\{.tag = 1, .value = {inner_str}}"
                    expr_result_type = CT_OPTION
                    expr_option_inner = inner_type
                    expr_option_inner_struct = inner_s
                } else {
                    ensure_option_type(inner_type)
                    let opt_type = option_c_type(inner_type)
                    expr_result_str = "({opt_type})\{.tag = 1, .value = {inner_str}}"
                    expr_result_type = CT_OPTION
                    expr_option_inner = inner_type
                    expr_option_inner_struct = ""
                }
                return
            }
        }
        if fn_name == "Ok" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let ok_str = expr_result_str
                let ok_type = expr_result_type
                let ok_s = get_var_struct(ok_str)
                let fsi = get_fn_ret_struct_inner(cg_current_fn_name)
                let err_s = fsi.err_struct
                let err_type = if err_s != "" { CT_INT } else { CT_STRING }
                if ok_s != "" || err_s != "" {
                    ensure_mixed_result_type(ok_type, err_type, ok_s, err_s)
                    let res_type = result_c_type_mixed(ok_type, err_type, ok_s, err_s)
                    expr_result_str = "({res_type})\{.tag = 0, .ok = {ok_str}}"
                    expr_result_type = CT_RESULT
                    expr_result_ok_type = ok_type
                    expr_result_err_type = err_type
                    expr_result_ok_struct = ok_s
                    expr_result_err_struct = err_s
                } else {
                    ensure_result_type(ok_type, err_type)
                    let res_type = result_c_type(ok_type, err_type)
                    expr_result_str = "({res_type})\{.tag = 0, .ok = {ok_str}}"
                    expr_result_type = CT_RESULT
                    expr_result_ok_type = ok_type
                    expr_result_err_type = err_type
                    expr_result_ok_struct = ""
                    expr_result_err_struct = ""
                }
                return
            }
        }
        if fn_name == "Err" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let err_str = expr_result_str
                let err_type = expr_result_type
                let err_enum = get_var_enum(err_str)
                let fsi = get_fn_ret_struct_inner(cg_current_fn_name)
                let err_s = if err_enum != "" { err_enum } else { fsi.err_struct }
                let ok_s = fsi.ok_struct
                let ok_type = if ok_s != "" { CT_INT } else { CT_INT }
                if ok_s != "" || err_s != "" {
                    ensure_mixed_result_type(ok_type, err_type, ok_s, err_s)
                    let res_type = result_c_type_mixed(ok_type, err_type, ok_s, err_s)
                    expr_result_str = "({res_type})\{.tag = 1, .err = {err_str}}"
                    expr_result_type = CT_RESULT
                    expr_result_ok_type = ok_type
                    expr_result_err_type = err_type
                    expr_result_ok_struct = ok_s
                    expr_result_err_struct = err_s
                } else {
                    ensure_result_type(ok_type, err_type)
                    let res_type = result_c_type(ok_type, err_type)
                    expr_result_str = "({res_type})\{.tag = 1, .err = {err_str}}"
                    expr_result_type = CT_RESULT
                    expr_result_ok_type = ok_type
                    expr_result_err_type = err_type
                    expr_result_ok_struct = ""
                    expr_result_err_struct = ""
                }
                return
            }
        }
        if fn_name == "Map" {
            expr_result_str = "pact_map_new()"
            expr_result_type = CT_MAP
            return
        }
        if fn_name == "Bytes" {
            expr_result_str = "pact_bytes_new()"
            expr_result_type = CT_BYTES
            return
        }
        if fn_name == "StringBuilder" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let cap_str = expr_result_str
                expr_result_str = "pact_sb_with_capacity({cap_str})"
            } else {
                expr_result_str = "pact_sb_new()"
            }
            expr_result_type = CT_STRINGBUILDER
            return
        }
        if fn_name == "Channel" {
            let args_sl = np_args.get(node).unwrap()
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
        if fn_name == "ffi_scope" {
            expr_result_str = "pact_ffi_scope_new()"
            expr_result_type = CT_FFI_SCOPE
            return
        }
        if fn_name == "alloc_ptr" {
            let inner_c = resolve_ptr_inner_c()
            expr_result_str = "({inner_c}*)malloc(sizeof({inner_c}))"
            expr_result_type = CT_PTR
            return
        }
        if fn_name == "null_ptr" {
            let inner_c = resolve_ptr_inner_c()
            expr_result_str = "(({inner_c}*)NULL)"
            expr_result_type = CT_PTR
            return
        }
        if fn_name == "get_env" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            ensure_option_type(CT_STRING)
            let opt_type = option_c_type(CT_STRING)
            let tmp = fresh_temp("_env_")
            let res = fresh_temp("_env_opt_")
            emit_line("const char* {tmp} = getenv({arg_str});")
            emit_line("{opt_type} {res} = {tmp} ? ({opt_type})\{.tag = 1, .value = {tmp}} : ({opt_type})\{.tag = 0};")
            set_var_option(res, CT_STRING)
            expr_result_str = res
            expr_result_type = CT_OPTION
            expr_option_inner = CT_STRING
            expr_option_inner_struct = ""
            return
        }
        // Check if this is a closure-typed variable
        let closure_sig = get_var_closure_sig(fn_name)
        if closure_sig != "" {
            let args_sl = np_args.get(node).unwrap()
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
            let ret_part = closure_sig_ret_part(closure_sig)
            if ret_part.starts_with("pact_") {
                let sname = ret_part.substring(5, ret_part.len() - 5)
                let resolved = resolve_struct_from_c_name(sname)
                if resolved != "" {
                    let tmp = fresh_temp("_cls_ret_")
                    emit_line("{ret_part} {tmp} = (({closure_sig}){fn_name}->fn_ptr)({args_str});")
                    set_var(tmp, CT_VOID, 0)
                    set_var_struct(tmp, resolved)
                    expr_result_str = tmp
                    expr_result_type = CT_VOID
                    return
                }
            }
            expr_result_str = "(({closure_sig}){fn_name}->fn_ptr)({args_str})"
            expr_result_type = closure_ret_ct(ret_part)
            return
        }
        let args_sl = np_args.get(node).unwrap()
        let mut args_str = ""
        let mut arg_types: List[Int] = []
        let mut arg_elem_types: List[Int] = []
        let mut arg_closure_sigs: List[Str] = []
        let is_generic = is_generic_fn(fn_name)
        reorder_named_args(fn_name, args_sl, node)
        if reorder_result.len() > 0 {
            let mut i = 0
            while i < reorder_result.len() {
                if i > 0 {
                    args_str = args_str.concat(", ")
                }
                let arg_node = reorder_result.get(i).unwrap()
                let mut actual = arg_node
                if np_kind.get(arg_node).unwrap() == NodeKind.NamedArg {
                    actual = np_value.get(arg_node).unwrap()
                }
                emit_expr(actual)
                args_str = args_str.concat(expr_result_str)
                if is_generic != 0 {
                    arg_types.push(expr_result_type)
                    arg_elem_types.push(expr_list_elem_type)
                    arg_closure_sigs.push(expr_closure_sig)
                }
                i = i + 1
            }
        } else if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                if i > 0 {
                    args_str = args_str.concat(", ")
                }
                emit_expr(sublist_get(args_sl, i))
                args_str = args_str.concat(expr_result_str)
                if is_generic != 0 {
                    arg_types.push(expr_result_type)
                    arg_elem_types.push(expr_list_elem_type)
                    arg_closure_sigs.push(expr_closure_sig)
                }
                i = i + 1
            }
        }
        check_effect_propagation(fn_name)
        // Check for generic function call
        if is_generic != 0 {
            let gfn_node = get_generic_fn_node(fn_name)
            let type_args = infer_fn_type_args_from_types(gfn_node, arg_types, arg_elem_types, arg_closure_sigs)
            if type_args.is_some() {
                let ta_str = type_args.unwrap()
                let mangled = mangle_generic_name(fn_name, ta_str)
                register_mono_fn(fn_name, ta_str)
                register_mono_instance(fn_name, ta_str)
                let ret_str = np_return_type.get(gfn_node).unwrap()
                let tparams_sl = np_type_params.get(gfn_node).unwrap()
                let resolved_ret = resolve_type_param(ret_str, tparams_sl, ta_str)
                let ret_type = type_from_name(resolved_ret)
                reg_fn(mangled, ret_type)
                if ret_type == CT_OPTION {
                    let ret_ann = np_type_ann.get(gfn_node).unwrap()
                    if ret_ann != -1 {
                        let elems_sl = np_elements.get(ret_ann).unwrap()
                        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
                            let inner_ann = sublist_get(elems_sl, 0)
                            let inner_name_raw = np_name.get(inner_ann).unwrap()
                            let inner_name = resolve_type_param(inner_name_raw, tparams_sl, ta_str)
                            let inner_ct = type_from_name(inner_name)
                            expr_option_inner = inner_ct
                            ensure_option_type(inner_ct)
                            reg_fn_ret_type(mangled, CT_OPTION, inner_ct, -1)
                            if inner_ct == CT_VOID && is_struct_type(inner_name) != 0 {
                                ensure_struct_option_type(inner_name)
                                expr_option_inner_struct = inner_name
                            }
                        }
                    }
                } else if ret_type == CT_RESULT {
                    let ret_ann = np_type_ann.get(gfn_node).unwrap()
                    if ret_ann != -1 {
                        let elems_sl = np_elements.get(ret_ann).unwrap()
                        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                            let ok_ann = sublist_get(elems_sl, 0)
                            let err_ann = sublist_get(elems_sl, 1)
                            let ok_name = resolve_type_param(np_name.get(ok_ann).unwrap(), tparams_sl, ta_str)
                            let err_name = resolve_type_param(np_name.get(err_ann).unwrap(), tparams_sl, ta_str)
                            let ok_ct = type_from_name(ok_name)
                            let err_ct = type_from_name(err_name)
                            expr_result_ok_type = ok_ct
                            expr_result_err_type = err_ct
                            ensure_result_type(ok_ct, err_ct)
                            reg_fn_ret_type(mangled, CT_RESULT, ok_ct, err_ct)
                        }
                    }
                } else if ret_type == CT_LIST {
                    let ret_ann = np_type_ann.get(gfn_node).unwrap()
                    if ret_ann != -1 {
                        let elems_sl = np_elements.get(ret_ann).unwrap()
                        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
                            let inner_ann = sublist_get(elems_sl, 0)
                            let inner_name_raw = np_name.get(inner_ann).unwrap()
                            let inner_name = resolve_type_param(inner_name_raw, tparams_sl, ta_str)
                            expr_list_elem_type = type_from_name(inner_name)
                        }
                    }
                }
                expr_result_str = "{c_fn_name(mangled)}({args_str})"
                expr_result_type = ret_type
                return
            }
        }
        if is_fn_registered(fn_name) == 0 && is_generic_fn(fn_name) == 0 {
            diag_error_at("UndefinedFunction", "E0504", "undefined function '{fn_name}' called in '{cg_current_fn_name}'", node, "")
            emit_line("/* undefined: {fn_name} */")
            expr_result_str = "0"
            expr_result_type = CT_INT
            return
        }
        expr_result_str = "{c_fn_name(fn_name)}({args_str})"
        expr_result_type = get_fn_ret(fn_name)
        if expr_result_type == CT_VOID {
            let fn_sret = get_fn_ret_struct(fn_name)
            if fn_sret != "" {
                let s_tmp = fresh_temp("_sr")
                emit_line("{c_type_c_name(fn_sret)} {s_tmp} = {c_fn_name(fn_name)}({args_str});")
                set_var_struct(s_tmp, fn_sret)
                expr_result_str = s_tmp
            }
        }
        let rt = get_fn_ret_type(fn_name)
        if expr_result_type == CT_RESULT {
            expr_result_ok_type = tp_child1_kind(rt.tp_id)
            expr_result_err_type = tp_child2_kind(rt.tp_id)
            let fsi = get_fn_ret_struct_inner(fn_name)
            expr_result_ok_struct = fsi.ok_struct
            expr_result_err_struct = fsi.err_struct
        }
        if expr_result_type == CT_OPTION {
            expr_option_inner = tp_child1_kind(rt.tp_id)
            let fsi = get_fn_ret_struct_inner(fn_name)
            expr_option_inner_struct = fsi.ok_struct
        }
        if expr_result_type == CT_LIST {
            expr_list_elem_type = tp_child1_kind(rt.tp_id)
            let fsi = get_fn_ret_struct_inner(fn_name)
            expr_list_elem_struct = fsi.ok_struct
        }
        if expr_result_type == CT_MAP {
            expr_map_key_type = tp_child1_kind(rt.tp_id)
            expr_map_val_type = tp_child2_kind(rt.tp_id)
        }
        return
    }
    // Qualified trait call: Trait.method(x, ...)
    if func_kind == NodeKind.FieldAccess {
        let trait_obj = np_obj.get(func_node).unwrap()
        if np_kind.get(trait_obj).unwrap() == NodeKind.Ident {
            let trait_name = np_name.get(trait_obj).unwrap()
            if is_trait_type(trait_name) != 0 {
                let method = np_name.get(func_node).unwrap()
                let args_sl = np_args.get(node).unwrap()
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
                        expr_result_str = "{c_fn_name(mangled)}({args_str})"
                        expr_result_type = get_impl_method_ret(type_name, method)
                        return
                    }
                }
            }
        }
    }
    emit_expr(func_node)
    let func_str = expr_result_str
    let func_cls_sig = expr_closure_sig
    let args_sl = np_args.get(node).unwrap()
    let mut args_str = ""
    if func_cls_sig != "" {
        args_str = func_str
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                args_str = args_str.concat(", ")
                emit_expr(sublist_get(args_sl, i))
                args_str = args_str.concat(expr_result_str)
                i = i + 1
            }
        }
        expr_result_str = "(({func_cls_sig}){func_str}->fn_ptr)({args_str})"
        let ret_part = closure_sig_ret_part(func_cls_sig)
        if ret_part.starts_with("pact_") {
            let sname = ret_part.substring(5, ret_part.len() - 5)
            let resolved = resolve_struct_from_c_name(sname)
            if resolved != "" {
                let tmp = fresh_temp("_cls_ret_")
                emit_line("{ret_part} {tmp} = (({func_cls_sig}){func_str}->fn_ptr)({args_str});")
                set_var(tmp, CT_VOID, 0)
                set_var_struct(tmp, resolved)
                expr_result_str = tmp
                expr_result_type = CT_VOID
            } else {
                expr_result_type = CT_VOID
            }
        } else {
            expr_result_type = closure_ret_ct(ret_part)
        }
    } else {
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
        } else if ch == 13 {
            result = result.concat("\\r")
        } else if ch == 9 {
            result = result.concat("\\t")
        } else if ch == 8 {
            result = result.concat("\\b")
        } else if ch == 12 {
            result = result.concat("\\f")
        } else if ch == 63 {
            result = result.concat("\\?")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

fn escape_fmt_percent(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let ch = s.char_at(i)
        if ch == 37 {
            if i + 1 < s.len() && s.char_at(i + 1) == 37 {
                result = result.concat("%%")
                i = i + 2
            } else {
                result = result.concat("%%")
                i = i + 1
            }
        } else {
            result = result.concat(s.substring(i, 1))
            i = i + 1
        }
    }
    result
}

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_interp_string(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let parts_sl = np_elements.get(node).unwrap()
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
        let pk = np_kind.get(part).unwrap()
        if !(pk == NodeKind.Ident && np_str_val.get(part).unwrap() == np_name.get(part).unwrap()) {
            all_literal = 0
        }
        ai = ai + 1
    }
    if all_literal != 0 {
        let mut concat_str = ""
        let mut ci = 0
        while ci < sublist_length(parts_sl) {
            let part = sublist_get(parts_sl, ci)
            concat_str = concat_str.concat(escape_c_string(np_str_val.get(part).unwrap()))
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
        let pk = np_kind.get(part).unwrap()
        // Literal string parts: parser stores them as NodeKind.Ident with str_val == name
        // Expression parts: NodeKind.Ident with str_val == "" (or other node kinds)
        if pk == NodeKind.Ident && np_str_val.get(part).unwrap() == np_name.get(part).unwrap() {
            fmt = fmt.concat(escape_fmt_percent(escape_c_string(np_str_val.get(part).unwrap())))
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

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_list_lit(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let tmp = fresh_temp("_l")
    emit_line("pact_list* {tmp} = pact_list_new();")
    let elems_sl = np_elements.get(node).unwrap()
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
                emit_line("{c_type_c_name(e_struct)}* {box_tmp} = ({c_type_c_name(e_struct)}*)pact_alloc(sizeof({c_type_c_name(e_struct)}));")
                emit_line("*{box_tmp} = {e_str};")
                emit_line("pact_list_push({tmp}, (void*){box_tmp});")
            } else if e_type == CT_INT {
                emit_line("pact_list_push({tmp}, (void*)(intptr_t){e_str});")
            } else if e_type == CT_FLOAT {
                let box_tmp = fresh_temp("_fbox")
                emit_line("double* {box_tmp} = (double*)pact_alloc(sizeof(double));")
                emit_line("*{box_tmp} = {e_str};")
                emit_line("pact_list_push({tmp}, (void*){box_tmp});")
            } else {
                emit_line("pact_list_push({tmp}, (void*){e_str});")
            }
            i = i + 1
        }
    }
    if first_elem_type >= 0 {
        expr_list_elem_type = first_elem_type
    } else {
        expr_list_elem_type = -1
    }
    if first_elem_struct != "" {
        set_list_elem_type(tmp, CT_VOID)
        set_list_elem_struct(tmp, first_elem_struct)
        expr_list_elem_struct = first_elem_struct
    } else {
        expr_list_elem_struct = ""
    }
    expr_result_str = tmp
    expr_result_type = CT_LIST
}

fn infer_struct_type_args(type_name: Str, field_types: List[Int]) -> Option[Str] {
    let types_sl = np_fields.get(cg_program_node).unwrap()
    if types_sl == -1 {
        return None
    }
    let mut td = -1
    let mut ti = 0
    while ti < sublist_length(types_sl) {
        let candidate = sublist_get(types_sl, ti)
        if np_name.get(candidate).unwrap() == type_name {
            td = candidate
        }
        ti = ti + 1
    }
    if td == -1 {
        return None
    }
    let tparams_sl = np_type_params.get(td).unwrap()
    if tparams_sl == -1 {
        return None
    }
    let num_params = sublist_length(tparams_sl)
    if num_params == 0 {
        return None
    }
    let td_flds_sl = np_fields.get(td).unwrap()
    if td_flds_sl == -1 {
        return None
    }
    let mut args = ""
    let mut pi = 0
    while pi < num_params {
        let param_name = np_name.get(sublist_get(tparams_sl, pi)).unwrap()
        let mut resolved = "Void"
        let mut fi = 0
        while fi < sublist_length(td_flds_sl) && fi < field_types.len() {
            let f = sublist_get(td_flds_sl, fi)
            let type_ann_node = np_value.get(f).unwrap()
            if type_ann_node != -1 {
                if np_name.get(type_ann_node).unwrap() == param_name {
                    resolved = type_name_from_ct(field_types.get(fi).unwrap())
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
    Some(args)
}

@allow(UnrestoredMutation, IncompleteStateRestore)
fn emit_struct_lit(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let sname = np_type_name.get(node).unwrap()
    let mut c_type = c_type_c_name(sname)
    let tmp = fresh_temp("_s")
    let flds_sl = np_fields.get(node).unwrap()
    let mut inits = ""
    let mut field_types: List[Int] = []
    let mut provided_fields: List[Str] = []
    let mut _init_count = 0
    if flds_sl != -1 {
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, i)
            let fname = np_name.get(sf).unwrap()
            provided_fields.push(fname)
            emit_expr(np_value.get(sf).unwrap())
            let val_str = expr_result_str
            field_types.push(expr_result_type)
            if _init_count > 0 {
                inits = inits.concat(", ")
            }
            inits = inits.concat(".{fname} = {val_str}")
            _init_count = _init_count + 1
            i = i + 1
        }
    }
    let mut di = 0
    while di < struct_field_defaults.len() {
        let dfl = struct_field_defaults.get(di).unwrap()
        if dfl.struct_name == sname {
            let mut found = 0
            let mut pi = 0
            while pi < provided_fields.len() {
                if provided_fields.get(pi).unwrap() == dfl.field_name {
                    found = 1
                    break
                }
                pi = pi + 1
            }
            if found == 0 {
                emit_expr(dfl.default_node)
                let dval = expr_result_str
                field_types.push(expr_result_type)
                if _init_count > 0 {
                    inits = inits.concat(", ")
                }
                inits = inits.concat(".{dfl.field_name} = {dval}")
                _init_count = _init_count + 1
            }
        }
        di = di + 1
    }
    let type_args = infer_struct_type_args(sname, field_types)
    let mut struct_key = sname
    if type_args.is_some() {
        let ta_str = type_args.unwrap()
        let mono_name = register_mono_instance(sname, ta_str)
        c_type = c_type_c_name(mono_name)
        struct_key = mono_name
        register_mono_field_types(sname, mono_name, ta_str)
    }
    emit_line("{c_type} {tmp} = \{ {inits} };")
    set_var_struct(tmp, struct_key)
    let mut ii = 0
    while ii < struct_invariants.len() {
        let inv = struct_invariants.get(ii).unwrap()
        if inv.struct_name == sname {
            let old_self = cg_where_self_var
            cg_where_self_var = tmp
            emit_expr(inv.expr_node)
            let inv_cond = expr_result_str
            emit_line("if (!({inv_cond})) \{ fprintf(stderr, \"invariant violated: @invariant on %s\\n\", \"{sname}\"); exit(1); }")
            cg_where_self_var = old_self
        }
        ii = ii + 1
    }
    expr_result_str = tmp
    expr_result_type = CT_VOID
}

fn emit_tuple_lit(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let elems_sl = np_elements.get(node).unwrap()
    if elems_sl == -1 {
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }
    let arity = sublist_length(elems_sl)
    let mut val_strs: List[Str] = []
    let mut val_types: List[Int] = []
    let mut val_structs: List[Str] = []
    let mut i = 0
    while i < arity {
        emit_expr(sublist_get(elems_sl, i))
        val_strs.push(expr_result_str)
        val_types.push(expr_result_type)
        let sn = get_var_struct(expr_result_str)
        val_structs.push(sn)
        i = i + 1
    }
    let mut tags = ""
    let mut elem_types_enc = ""
    let mut elem_structs_enc = ""
    let mut inits = ""
    i = 0
    while i < arity {
        if i > 0 {
            tags = tags.concat("_")
            elem_types_enc = elem_types_enc.concat(",")
            elem_structs_enc = elem_structs_enc.concat(",")
            inits = inits.concat(", ")
        }
        let vs = val_structs.get(i).unwrap()
        if vs != "" {
            tags = tags.concat(vs)
            elem_structs_enc = elem_structs_enc.concat(vs)
        } else {
            tags = tags.concat(c_type_tag(val_types.get(i).unwrap()))
            elem_structs_enc = elem_structs_enc.concat("-")
        }
        elem_types_enc = elem_types_enc.concat("{val_types.get(i).unwrap()}")
        inits = inits.concat("._{i} = {val_strs.get(i).unwrap()}")
        i = i + 1
    }
    let tup_name = tuple_c_type_name(tags, arity)
    ensure_tuple_type(tup_name, arity, elem_types_enc, elem_structs_enc)
    let tmp = fresh_temp("_tup")
    emit_line("{c_type_c_name(tup_name)} {tmp} = \{ {inits} };")
    set_var_struct(tmp, tup_name)
    expr_result_str = tmp
    expr_result_type = CT_VOID
}
