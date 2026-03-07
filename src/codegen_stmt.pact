// codegen_stmt.pact — Statement codegen, control flow, functions, type definitions

import codegen_types
import codegen_expr

pub fn emit_if_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let tmp = fresh_temp("_if_")
    let then_type = infer_block_type(np_then_body.get(node).unwrap())
    if then_type == CT_VOID {
        emit_if_stmt(node)
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }
    if then_type == CT_RESULT {
        let rt = get_fn_ret_type(cg_current_fn_name)
        let fsi = get_fn_ret_struct_inner(cg_current_fn_name)
        if fsi.ok_struct != "" || fsi.err_struct != "" {
            emit_line("{result_c_type_mixed(rt.inner1, rt.inner2, fsi.ok_struct, fsi.err_struct)} {tmp};")
        } else if rt.inner1 >= 0 {
            emit_line("{result_c_type(rt.inner1, rt.inner2)} {tmp};")
        } else {
            emit_line("{result_c_type(CT_INT, CT_STRING)} {tmp};")
        }
    } else if then_type == CT_OPTION {
        let rt = get_fn_ret_type(cg_current_fn_name)
        let fsi = get_fn_ret_struct_inner(cg_current_fn_name)
        if fsi.ok_struct != "" {
            emit_line("{struct_option_c_type(fsi.ok_struct)} {tmp};")
        } else if rt.inner1 >= 0 {
            emit_line("{option_c_type(rt.inner1)} {tmp};")
        } else {
            emit_line("{option_c_type(CT_INT)} {tmp};")
        }
    } else {
        emit_line("{c_type_str(then_type)} {tmp};")
    }
    emit_expr(np_condition.get(node).unwrap())
    let cond_str = expr_result_str
    emit_line("if ({cond_str}) \{")
    cg_indent = cg_indent + 1
    let then_val = emit_block_value(np_then_body.get(node).unwrap())
    emit_line("{tmp} = {then_val};")
    cg_indent = cg_indent - 1
    if np_else_body.get(node).unwrap() != -1 {
        emit_line("} else \{")
        cg_indent = cg_indent + 1
        let else_val = emit_block_value(np_else_body.get(node).unwrap())
        emit_line("{tmp} = {else_val};")
        cg_indent = cg_indent - 1
    }
    emit_line("}")
    set_var(tmp, then_type, 1)
    if then_type == CT_RESULT {
        let rt2 = get_fn_ret_type(cg_current_fn_name)
        let fsi2 = get_fn_ret_struct_inner(cg_current_fn_name)
        if fsi2.ok_struct != "" || fsi2.err_struct != "" {
            set_var_result_struct(tmp, rt2.inner1, rt2.inner2, fsi2.ok_struct, fsi2.err_struct)
            expr_result_ok_struct = fsi2.ok_struct
            expr_result_err_struct = fsi2.err_struct
        } else {
            set_var_result(tmp, rt2.inner1, rt2.inner2)
        }
        expr_result_ok_type = rt2.inner1
        expr_result_err_type = rt2.inner2
    }
    if then_type == CT_OPTION {
        let rt3 = get_fn_ret_type(cg_current_fn_name)
        let fsi3 = get_fn_ret_struct_inner(cg_current_fn_name)
        if fsi3.ok_struct != "" {
            set_var_option_struct(tmp, rt3.inner1, fsi3.ok_struct)
            expr_option_inner_struct = fsi3.ok_struct
        } else {
            set_var_option(tmp, rt3.inner1)
        }
        expr_option_inner = rt3.inner1
    }
    expr_result_str = tmp
    expr_result_type = then_type
}

pub fn emit_match_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let scrut = np_scrutinee.get(node).unwrap()

    // Build list of scrutinee values (multiple if tuple literal)
    match_scruts = []
    match_scrut_enum = ""

    if np_kind.get(scrut).unwrap() == NodeKind.TupleLit {
        let elems_sl = np_elements.get(scrut).unwrap()
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                emit_expr(sublist_get(elems_sl, ei))
                let tmp = fresh_temp("_tup_")
                emit_line("{c_type_str(expr_result_type)} {tmp} = {expr_result_str};")
                set_var(tmp, expr_result_type, 1)
                match_scruts.push(MatchScrutEntry { str_val: tmp, scrut_type: expr_result_type })
                ei = ei + 1
            }
        }
    } else {
        if np_kind.get(scrut).unwrap() == NodeKind.Ident {
            match_scrut_enum = get_var_enum(np_name.get(scrut).unwrap())
        } else if np_kind.get(scrut).unwrap() == NodeKind.FieldAccess {
            match_scrut_enum = infer_enum_from_node(scrut)
        }
        emit_expr(scrut)
        if match_scrut_enum != "" && is_data_enum(match_scrut_enum) != 0 {
            let scrut_tmp = fresh_temp("_scrut_")
            emit_line("{c_type_c_name(match_scrut_enum)} {scrut_tmp} = {expr_result_str};")
            set_var(scrut_tmp, CT_INT, 1)
            match_scruts.push(MatchScrutEntry { str_val: scrut_tmp, scrut_type: expr_result_type })
        } else if expr_result_type == CT_RESULT || expr_result_type == CT_OPTION {
            let scrut_tmp = fresh_temp("_scrut_")
            let rok = expr_result_ok_type
            let rerr = expr_result_err_type
            if expr_result_type == CT_RESULT {
                let rok_s = expr_result_ok_struct
                let rerr_s = expr_result_err_struct
                if rok_s != "" || rerr_s != "" {
                    let res_c = result_c_type_mixed(rok, rerr, rok_s, rerr_s)
                    emit_line("{res_c} {scrut_tmp} = {expr_result_str};")
                } else {
                    let res_c = result_c_type(rok, rerr)
                    emit_line("{res_c} {scrut_tmp} = {expr_result_str};")
                }
            } else {
                let oi = expr_option_inner
                let oi_s = expr_option_inner_struct
                if oi_s != "" {
                    let opt_c = struct_option_c_type(oi_s)
                    emit_line("{opt_c} {scrut_tmp} = {expr_result_str};")
                } else {
                    let opt_c = option_c_type(oi)
                    emit_line("{opt_c} {scrut_tmp} = {expr_result_str};")
                }
            }
            match_scruts.push(MatchScrutEntry { str_val: scrut_tmp, scrut_type: expr_result_type })
        } else if expr_result_type == CT_LIST {
            let scrut_tmp = fresh_temp("_scrut_")
            emit_line("pact_list* {scrut_tmp} = {expr_result_str};")
            set_var(scrut_tmp, CT_LIST, 1)
            let mut src_name = expr_result_str
            if np_kind.get(scrut).unwrap() == NodeKind.Ident {
                src_name = np_name.get(scrut).unwrap()
            }
            let lelem = get_list_elem_type(src_name)
            if lelem >= 0 {
                set_list_elem_type(scrut_tmp, lelem)
            }
            let lstruct = get_list_elem_struct(src_name)
            if lstruct != "" {
                set_list_elem_struct(scrut_tmp, lstruct)
            }
            match_scruts.push(MatchScrutEntry { str_val: scrut_tmp, scrut_type: CT_LIST })
        } else {
            match_scruts.push(MatchScrutEntry { str_val: expr_result_str, scrut_type: expr_result_type })
        }
    }

    let saved_ok_type = expr_result_ok_type
    let saved_err_type = expr_result_err_type
    let saved_option_inner = expr_option_inner
    let saved_ok_struct = expr_result_ok_struct
    let saved_err_struct = expr_result_err_struct
    let saved_option_inner_struct = expr_option_inner_struct

    let arms_sl = np_arms.get(node).unwrap()
    if arms_sl == -1 {
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    let first_arm = sublist_get(arms_sl, 0)
    let result_type = infer_arm_type(first_arm)
    let result_var = fresh_temp("_match_")
    if result_type != CT_VOID {
        emit_line("{c_type_str(result_type)} {result_var};")
    }

    let mut has_guards = 0
    let mut gi = 0
    while gi < sublist_length(arms_sl) {
        if np_guard.get(sublist_get(arms_sl, gi)).unwrap() != -1 {
            has_guards = 1
        }
        gi = gi + 1
    }

    if has_guards {
        emit_line("int _mg_ = 0;")
    }

    let mut first = 1
    let mut i = 0
    while i < sublist_length(arms_sl) {
        expr_result_ok_type = saved_ok_type
        expr_result_err_type = saved_err_type
        expr_option_inner = saved_option_inner
        expr_result_ok_struct = saved_ok_struct
        expr_result_err_struct = saved_err_struct
        expr_option_inner_struct = saved_option_inner_struct
        let arm = sublist_get(arms_sl, i)
        let pat = np_pattern.get(arm).unwrap()

        let pat_cond = pattern_condition(pat, 0, match_scruts.len())
        let guard_node = np_guard.get(arm).unwrap()
        let is_wildcard = pat_cond == "" && guard_node == -1

        if has_guards {
            if pat_cond == "" {
                if first {
                    emit_line("if (!_mg_) \{")
                } else {
                    emit_line("} if (!_mg_) \{")
                }
            } else if first {
                emit_line("if (!_mg_ && {pat_cond}) \{")
            } else {
                emit_line("} if (!_mg_ && {pat_cond}) \{")
            }
            cg_indent = cg_indent + 1
            bind_pattern_vars(pat, 0, match_scruts.len())
            if guard_node != -1 {
                emit_expr(guard_node)
                let guard_str = expr_result_str
                emit_line("if ({guard_str}) \{")
                cg_indent = cg_indent + 1
                let arm_val = emit_arm_value(np_body.get(arm).unwrap())
                if result_type != CT_VOID {
                    emit_line("{result_var} = {arm_val};")
                }
                emit_line("_mg_ = 1;")
                cg_indent = cg_indent - 1
                emit_line("}")
            } else {
                let arm_val = emit_arm_value(np_body.get(arm).unwrap())
                if result_type != CT_VOID {
                    emit_line("{result_var} = {arm_val};")
                }
                emit_line("_mg_ = 1;")
            }
            cg_indent = cg_indent - 1
        } else {
            if is_wildcard {
                if first {
                    emit_line("\{")
                } else {
                    emit_line("} else \{")
                }
            } else if first {
                emit_line("if ({pat_cond}) \{")
            } else {
                emit_line("} else if ({pat_cond}) \{")
            }
            cg_indent = cg_indent + 1
            bind_pattern_vars(pat, 0, match_scruts.len())
            let arm_val = emit_arm_value(np_body.get(arm).unwrap())
            if result_type != CT_VOID {
                emit_line("{result_var} = {arm_val};")
            }
            cg_indent = cg_indent - 1
        }

        first = 0
        i = i + 1
    }
    emit_line("}")
    if result_type != CT_VOID {
        set_var(result_var, result_type, 1)
        expr_result_str = result_var
    } else {
        expr_result_str = "0"
    }
    expr_result_type = result_type
}

// Build a C condition string for a pattern.
// scrut_off/scrut_len index into match_scruts.
// Returns "" when the pattern always matches (wildcard/ident).
pub fn pattern_condition(pat: Int, scrut_off: Int, scrut_len: Int) -> Str {
    let pk = np_kind.get(pat).unwrap()
    if pk == NodeKind.WildcardPattern {
        return ""
    }
    if pk == NodeKind.IdentPattern {
        let pat_name = np_name.get(pat).unwrap()
        if pat_name == "None" {
            return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == 0)"
        }
        let mut enum_name = match_scrut_enum
        if enum_name == "" {
            enum_name = resolve_variant(pat_name)
        }
        if enum_name != "" {
            if is_data_enum(enum_name) != 0 {
                let tag = get_variant_tag(enum_name, pat_name)
                return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == {tag})"
            }
            return "({match_scruts.get(scrut_off).unwrap().str_val} == {c_type_c_name(enum_name)}_{pat_name})"
        }
        return ""
    }
    if pk == NodeKind.IntPattern {
        let pat_val = np_str_val.get(pat).unwrap()
        return "({match_scruts.get(scrut_off).unwrap().str_val} == {pat_val})"
    }
    if pk == NodeKind.StringPattern {
        let pat_val = np_str_val.get(pat).unwrap()
        return "(pact_str_eq({match_scruts.get(scrut_off).unwrap().str_val}, \"{pat_val}\"))"
    }
    if pk == NodeKind.RangePattern {
        let lo = np_str_val.get(pat).unwrap()
        let hi = np_name.get(pat).unwrap()
        let scrut = match_scruts.get(scrut_off).unwrap().str_val
        if np_inclusive.get(pat).unwrap() != 0 {
            return "({scrut} >= {lo} && {scrut} <= {hi})"
        }
        return "({scrut} >= {lo} && {scrut} < {hi})"
    }
    if pk == NodeKind.EnumPattern {
        let enum_name = np_name.get(pat).unwrap()
        let variant_name = np_type_name.get(pat).unwrap()
        if enum_name == "Ok" {
            return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == 0)"
        }
        if enum_name == "Err" {
            return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == 1)"
        }
        if enum_name == "Some" {
            return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == 1)"
        }
        if variant_name != "" {
            if is_data_enum(enum_name) != 0 {
                let tag = get_variant_tag(enum_name, variant_name)
                return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == {tag})"
            }
            return "({match_scruts.get(scrut_off).unwrap().str_val} == {c_type_c_name(enum_name)}_{variant_name})"
        }
        let pat_name = np_name.get(pat).unwrap()
        let resolved = resolve_variant(pat_name)
        if resolved != "" && is_data_enum(resolved) != 0 {
            let tag = get_variant_tag(resolved, pat_name)
            return "({match_scruts.get(scrut_off).unwrap().str_val}.tag == {tag})"
        }
        return ""
    }
    if pk == NodeKind.StructPattern {
        let flds_sl = np_fields.get(pat).unwrap()
        if flds_sl == -1 {
            return ""
        }
        let mut parts = ""
        let mut parts_n = 0
        let scrut = match_scruts.get(scrut_off).unwrap().str_val
        let mut j = 0
        while j < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, j)
            let fname = np_name.get(sf).unwrap()
            let fpat = np_pattern.get(sf).unwrap()
            if fpat != -1 {
                let saved_scruts = match_scruts
                match_scruts = [MatchScrutEntry { str_val: "{scrut}.{fname}", scrut_type: CT_VOID }]
                let sub_cond = pattern_condition(fpat, 0, 1)
                match_scruts = saved_scruts
                if sub_cond != "" {
                    if parts_n > 0 {
                        parts = parts.concat(" && ")
                    }
                    parts = parts.concat(sub_cond)
                    parts_n = parts_n + 1
                }
            }
            j = j + 1
        }
        return parts
    }
    if pk == NodeKind.OrPattern {
        let alts_sl = np_elements.get(pat).unwrap()
        if alts_sl == -1 {
            return ""
        }
        let mut parts = ""
        let mut parts_n = 0
        let mut j = 0
        while j < sublist_length(alts_sl) {
            let sub_pat = sublist_get(alts_sl, j)
            let sub_cond = pattern_condition(sub_pat, scrut_off, scrut_len)
            if sub_cond != "" {
                if parts_n > 0 {
                    parts = parts.concat(" || ")
                }
                parts = parts.concat(sub_cond)
                parts_n = parts_n + 1
            }
            j = j + 1
        }
        return parts
    }
    if pk == NodeKind.AsPattern {
        let inner = np_pattern.get(pat).unwrap()
        return pattern_condition(inner, scrut_off, scrut_len)
    }
    if pk == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(pat).unwrap()
        if elems_sl == -1 {
            return ""
        }
        let mut parts = ""
        let mut parts_n = 0
        let mut j = 0
        while j < sublist_length(elems_sl) {
            let sub_pat = sublist_get(elems_sl, j)
            let sub_cond = pattern_condition(sub_pat, scrut_off + j, 1)
            if sub_cond != "" {
                if parts_n > 0 {
                    parts = parts.concat(" && ")
                }
                parts = parts.concat(sub_cond)
                parts_n = parts_n + 1
            }
            j = j + 1
        }
        return parts
    }
    if pk == NodeKind.ListPattern {
        let elems_sl = np_elements.get(pat).unwrap()
        let has_rest = np_inclusive.get(pat).unwrap()
        let scrut = match_scruts.get(scrut_off).unwrap().str_val
        let mut elem_count = 0
        if elems_sl != -1 {
            elem_count = sublist_length(elems_sl)
        }
        let mut parts = ""
        let mut parts_n = 0
        if has_rest != 0 {
            parts = "(pact_list_len({scrut}) >= {elem_count})"
        } else {
            parts = "(pact_list_len({scrut}) == {elem_count})"
        }
        parts_n = 1
        if elems_sl != -1 {
            let mut j = 0
            while j < sublist_length(elems_sl) {
                let sub_pat = sublist_get(elems_sl, j)
                let saved_scruts = match_scruts
                let elem_type = get_list_elem_type(scrut)
                let elem_struct = get_list_elem_struct(scrut)
                let mut cast = "(int64_t)(intptr_t)"
                let mut sub_scrut_type = CT_STRING
                if elem_type == CT_STRING {
                    cast = "(const char*)"
                    sub_scrut_type = CT_STRING
                } else if elem_struct != "" {
                    cast = "({c_type_c_name(elem_struct)})(intptr_t)"
                    sub_scrut_type = CT_INT
                } else if elem_type >= 0 {
                    sub_scrut_type = elem_type
                }
                match_scruts = [MatchScrutEntry { str_val: "{cast}pact_list_get({scrut}, {j})", scrut_type: sub_scrut_type }]
                let sub_cond = pattern_condition(sub_pat, 0, 1)
                match_scruts = saved_scruts
                if sub_cond != "" {
                    if parts_n > 0 {
                        parts = parts.concat(" && ")
                    }
                    parts = parts.concat(sub_cond)
                    parts_n = parts_n + 1
                }
                j = j + 1
            }
        }
        return parts
    }
    ""
}

// Emit C variable bindings for ident sub-patterns within a pattern.
// scrut_off/scrut_len index into match_scruts.
pub fn bind_pattern_vars(pat: Int, scrut_off: Int, scrut_len: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let pk = np_kind.get(pat).unwrap()
    if pk == NodeKind.EnumPattern {
        let enum_name = np_name.get(pat).unwrap()
        let variant_name = np_type_name.get(pat).unwrap()
        let ep_flds_sl = np_fields.get(pat).unwrap()
        if (enum_name == "Ok" || enum_name == "Err" || enum_name == "Some") && ep_flds_sl != -1 && sublist_length(ep_flds_sl) >= 1 {
            let sub_pat = sublist_get(ep_flds_sl, 0)
            let sub_pk = np_kind.get(sub_pat).unwrap()
            let scrut = match_scruts.get(scrut_off).unwrap().str_val
            let scrut_type = match_scruts.get(scrut_off).unwrap().scrut_type
            if sub_pk == NodeKind.IdentPattern {
                let bind_name = np_name.get(sub_pat).unwrap()
                if bind_name != "_" {
                    let c_bind = c_safe_name(bind_name)
                    let mut field = "ok"
                    let mut inner_ct = CT_STRING
                    let mut inner_struct = ""
                    if enum_name == "Err" {
                        field = "err"
                        if scrut_type == CT_RESULT {
                            inner_ct = expr_result_err_type
                            inner_struct = expr_result_err_struct
                        }
                    } else if enum_name == "Ok" {
                        if scrut_type == CT_RESULT {
                            inner_ct = expr_result_ok_type
                            inner_struct = expr_result_ok_struct
                        }
                    } else if enum_name == "Some" {
                        field = "value"
                        if scrut_type == CT_OPTION {
                            inner_ct = expr_option_inner
                            inner_struct = expr_option_inner_struct
                        }
                    }
                    if inner_struct != "" {
                        emit_line("{c_type_c_name(inner_struct)} {c_bind} = {scrut}.{field};")
                        set_var(bind_name, CT_INT, 0)
                        set_var_struct(bind_name, inner_struct)
                        if is_enum_type(inner_struct) != 0 {
                            var_enums.push(VarEnumEntry { name: bind_name, enum_type: inner_struct })
                        }
                    } else {
                        emit_line("{c_type_str(inner_ct)} {c_bind} = {scrut}.{field};")
                        set_var(bind_name, inner_ct, 0)
                    }
                }
            } else if sub_pk == NodeKind.WildcardPattern {
                let _skip = 0
            }
            return
        }
        let mut resolved_enum = enum_name
        let mut resolved_variant = variant_name
        if variant_name == "" {
            resolved_variant = enum_name
            resolved_enum = resolve_variant(enum_name)
        }
        if resolved_enum != "" && is_data_enum(resolved_enum) != 0 && ep_flds_sl != -1 {
            let vidx = get_variant_index(resolved_enum, resolved_variant)
            if vidx >= 0 {
                let fcount = get_variant_field_count(vidx)
                let scrut = match_scruts.get(scrut_off).unwrap().str_val
                let mut fi = 0
                while fi < sublist_length(ep_flds_sl) && fi < fcount {
                    let sub_pat = sublist_get(ep_flds_sl, fi)
                    let sub_pk = np_kind.get(sub_pat).unwrap()
                    let field_name = get_variant_field_name(vidx, fi)
                    let field_type_name = get_variant_field_type_str(vidx, fi)
                    let field_ct = type_from_name(field_type_name)
                    if sub_pk == NodeKind.IdentPattern {
                        let bind_name = np_name.get(sub_pat).unwrap()
                        if bind_name != "_" {
                            let c_bind = c_safe_name(bind_name)
                            if is_struct_type(field_type_name) != 0 {
                                emit_line("{c_type_c_name(field_type_name)} {c_bind} = {scrut}.data.{resolved_variant}.{field_name};")
                                set_var(bind_name, CT_VOID, 0)
                                set_var_struct(bind_name, field_type_name)
                            } else if is_enum_type(field_type_name) != 0 {
                                emit_line("{c_type_c_name(field_type_name)} {c_bind} = {scrut}.data.{resolved_variant}.{field_name};")
                                set_var(bind_name, CT_INT, 0)
                                var_enums.push(VarEnumEntry { name: bind_name, enum_type: field_type_name })
                            } else {
                                emit_line("{c_type_str(field_ct)} {c_bind} = {scrut}.data.{resolved_variant}.{field_name};")
                                set_var(bind_name, field_ct, 0)
                            }
                        }
                    } else if sub_pk == NodeKind.WildcardPattern {
                        let _skip = 0
                    } else {
                        let saved_scruts = match_scruts
                        match_scruts = [MatchScrutEntry { str_val: "{scrut}.data.{resolved_variant}.{field_name}", scrut_type: field_ct }]
                        bind_pattern_vars(sub_pat, 0, 1)
                        match_scruts = saved_scruts
                    }
                    fi = fi + 1
                }
            }
        }
        return
    }
    if pk == NodeKind.StringPattern {
        return
    }
    if pk == NodeKind.RangePattern {
        return
    }
    if pk == NodeKind.IntPattern {
        return
    }
    if pk == NodeKind.OrPattern {
        let alts_sl = np_elements.get(pat).unwrap()
        if alts_sl != -1 && sublist_length(alts_sl) > 0 {
            bind_pattern_vars(sublist_get(alts_sl, 0), scrut_off, scrut_len)
        }
        return
    }
    if pk == NodeKind.StructPattern {
        let flds_sl = np_fields.get(pat).unwrap()
        if flds_sl == -1 {
            return
        }
        let scrut = match_scruts.get(scrut_off).unwrap().str_val
        let stype_name = np_type_name.get(pat).unwrap()
        let mut j = 0
        while j < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, j)
            let fname = np_name.get(sf).unwrap()
            let c_fname = c_safe_name(fname)
            let fpat = np_pattern.get(sf).unwrap()
            if fpat != -1 {
                let saved_scruts = match_scruts
                match_scruts = [MatchScrutEntry { str_val: "{scrut}.{fname}", scrut_type: CT_VOID }]
                bind_pattern_vars(fpat, 0, 1)
                match_scruts = saved_scruts
            } else {
                emit_line("__typeof__({scrut}.{fname}) {c_fname} = {scrut}.{fname};")
                let ftype = get_struct_field_type(stype_name, fname)
                let fstype = get_struct_field_stype(stype_name, fname)
                set_var(fname, ftype, 0)
                if fstype != "" {
                    set_var_struct(fname, fstype)
                }
            }
            j = j + 1
        }
        return
    }
    if pk == NodeKind.AsPattern {
        let bind_name = np_name.get(pat).unwrap()
        let c_bind = c_safe_name(bind_name)
        let st = match_scruts.get(scrut_off).unwrap().scrut_type
        let scrut_str = match_scruts.get(scrut_off).unwrap().str_val
        if match_scrut_enum != "" {
            emit_line("{c_type_c_name(match_scrut_enum)} {c_bind} = {scrut_str};")
            set_var(bind_name, CT_INT, 1)
            var_enums.push(VarEnumEntry { name: bind_name, enum_type: match_scrut_enum })
        } else {
            emit_line("{c_type_str(st)} {c_bind} = {scrut_str};")
            set_var(bind_name, st, 1)
        }
        bind_pattern_vars(np_pattern.get(pat).unwrap(), scrut_off, scrut_len)
        return
    }
    if pk == NodeKind.IdentPattern {
        let bind_name = np_name.get(pat).unwrap()
        if bind_name == "None" {
            return
        }
        let mut enum_name = match_scrut_enum
        if enum_name == "" {
            enum_name = resolve_variant(bind_name)
        }
        if enum_name != "" {
            return
        }
        if scrut_len == 1 {
            let c_bind = c_safe_name(bind_name)
            let st = match_scruts.get(scrut_off).unwrap().scrut_type
            emit_line("{c_type_str(st)} {c_bind} = {match_scruts.get(scrut_off).unwrap().str_val};")
            set_var(bind_name, st, 1)
        }
        return
    }
    if pk == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(pat).unwrap()
        if elems_sl != -1 {
            let mut j = 0
            while j < sublist_length(elems_sl) {
                let sub_pat = sublist_get(elems_sl, j)
                bind_pattern_vars(sub_pat, scrut_off + j, 1)
                j = j + 1
            }
        }
        return
    }
    if pk == NodeKind.ListPattern {
        let elems_sl = np_elements.get(pat).unwrap()
        if elems_sl != -1 {
            let scrut = match_scruts.get(scrut_off).unwrap().str_val
            let elem_type = get_list_elem_type(scrut)
            let elem_struct = get_list_elem_struct(scrut)
            let mut j = 0
            while j < sublist_length(elems_sl) {
                let sub_pat = sublist_get(elems_sl, j)
                let saved_scruts = match_scruts
                let mut cast = "(int64_t)(intptr_t)"
                let mut bind_ct = CT_INT
                if elem_type == CT_STRING {
                    cast = "(const char*)"
                    bind_ct = CT_STRING
                } else if elem_struct != "" {
                    cast = "({c_type_c_name(elem_struct)})(intptr_t)"
                    bind_ct = CT_INT
                } else if elem_type >= 0 {
                    bind_ct = elem_type
                }
                match_scruts = [MatchScrutEntry { str_val: "{cast}pact_list_get({scrut}, {j})", scrut_type: bind_ct }]
                bind_pattern_vars(sub_pat, 0, 1)
                match_scruts = saved_scruts
                j = j + 1
            }
        }
        return
    }
}

pub fn emit_block_expr(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let stmts_sl = np_stmts.get(node).unwrap()
    if stmts_sl == -1 {
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }
    let count = sublist_length(stmts_sl)
    let mut i = 0
    while i < count - 1 {
        emit_stmt(sublist_get(stmts_sl, i))
        i = i + 1
    }
    if count > 0 {
        let last = sublist_get(stmts_sl, count - 1)
        let last_kind = np_kind.get(last).unwrap()
        if last_kind == NodeKind.ExprStmt {
            emit_expr(np_value.get(last).unwrap())
            return
        }
        emit_stmt(last)
    }
    expr_result_str = "0"
    expr_result_type = CT_VOID
}

pub fn emit_arm_value(body: Int) -> Str ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    if body == -1 {
        return "0"
    }
    let kind = np_kind.get(body).unwrap()
    if kind == NodeKind.Block {
        return emit_block_value(body)
    }
    if kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(body).unwrap())
        return expr_result_str
    }
    emit_expr(body)
    expr_result_str
}

pub fn emit_block_value(block: Int) -> Str ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    if block == -1 {
        return "0"
    }
    let stmts_sl = np_stmts.get(block).unwrap()
    if stmts_sl == -1 {
        return "0"
    }
    let count = sublist_length(stmts_sl)
    if count == 0 {
        return "0"
    }
    let mut i = 0
    while i < count - 1 {
        emit_stmt(sublist_get(stmts_sl, i))
        i = i + 1
    }
    let last = sublist_get(stmts_sl, count - 1)
    let last_kind = np_kind.get(last).unwrap()
    if last_kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(last).unwrap())
        return expr_result_str
    }
    if last_kind == NodeKind.IfExpr {
        emit_if_expr(last)
        return expr_result_str
    }
    if last_kind == NodeKind.Return {
        if np_value.get(last).unwrap() != -1 {
            emit_expr(np_value.get(last).unwrap())
            let val_s = expr_result_str
            emit_line("return {val_s};")
        } else {
            emit_line("return;")
        }
        return "0"
    }
    emit_stmt(last)
    "0"
}

pub fn infer_block_type(block: Int) -> Int {
    if block == -1 {
        return CT_VOID
    }
    let stmts_sl = np_stmts.get(block).unwrap()
    if stmts_sl == -1 {
        return CT_VOID
    }
    let count = sublist_length(stmts_sl)
    if count == 0 {
        return CT_VOID
    }
    let last = sublist_get(stmts_sl, count - 1)
    let last_kind = np_kind.get(last).unwrap()
    if last_kind == NodeKind.ExprStmt {
        return infer_expr_type(np_value.get(last).unwrap())
    }
    if last_kind == NodeKind.IfExpr {
        return infer_expr_type(last)
    }
    if last_kind == NodeKind.MatchExpr {
        return infer_arm_type(sublist_get(np_arms.get(last).unwrap(), 0))
    }
    CT_VOID
}

pub fn infer_arm_type(arm: Int) -> Int {
    let body = np_body.get(arm).unwrap()
    if body == -1 {
        return CT_VOID
    }
    let kind = np_kind.get(body).unwrap()
    if kind == NodeKind.Block {
        return infer_block_type(body)
    }
    if kind == NodeKind.ExprStmt {
        return infer_expr_type(np_value.get(body).unwrap())
    }
    infer_expr_type(body)
}

pub fn infer_expr_type(node: Int) -> Int {
    if node == -1 {
        return CT_VOID
    }
    let kind = np_kind.get(node).unwrap()
    if kind == NodeKind.IntLit { return CT_INT }
    if kind == NodeKind.FloatLit { return CT_FLOAT }
    if kind == NodeKind.BoolLit { return CT_BOOL }
    if kind == NodeKind.InterpString { return CT_STRING }
    if kind == NodeKind.ListLit { return CT_LIST }
    if kind == NodeKind.Ident {
        let iname = np_name.get(node).unwrap()
        if iname == "None" {
            return CT_OPTION
        }
        if resolve_variant(iname) != "" {
            return CT_INT
        }
        return get_var_type(iname)
    }
    if kind == NodeKind.FieldAccess {
        let fa_obj = np_obj.get(node).unwrap()
        let fa_field = np_name.get(node).unwrap()
        if np_kind.get(fa_obj).unwrap() == NodeKind.Ident {
            let obj_name = np_name.get(fa_obj).unwrap()
            if is_enum_type(obj_name) != 0 {
                return CT_INT
            }
            let stype = get_var_struct(obj_name)
            if stype != "" {
                return get_struct_field_type(stype, fa_field)
            }
        }
        return CT_VOID
    }
    if kind == NodeKind.IfExpr {
        let t = infer_block_type(np_then_body.get(node).unwrap())
        if t != CT_VOID { return t }
        let e = np_else_body.get(node).unwrap()
        if e != -1 { return infer_block_type(e) }
        return CT_VOID
    }
    if kind == NodeKind.Call {
        let func_node = np_left.get(node).unwrap()
        if np_kind.get(func_node).unwrap() == NodeKind.Ident {
            let call_name = np_name.get(func_node).unwrap()
            if call_name == "Ok" || call_name == "Err" {
                return CT_RESULT
            }
            if call_name == "Some" {
                return CT_OPTION
            }
            return get_fn_ret(call_name)
        }
    }
    if kind == NodeKind.BinOp {
        let op = np_op.get(node).unwrap()
        if op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||" {
            return CT_BOOL
        }
        let left_t = infer_expr_type(np_left.get(node).unwrap())
        if left_t == CT_STRING { return CT_STRING }
        if op == "+" {
            let right_t = infer_expr_type(np_right.get(node).unwrap())
            if right_t == CT_STRING { return CT_STRING }
        }
        return left_t
    }
    CT_VOID
}

// ── Statement codegen ───────────────────────────────────────────────

pub fn emit_stmt(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(node).unwrap())
        let s = expr_result_str
        if s != "" && s != "0" {
            emit_line("{s};")
        }
        return
    }

    if kind == NodeKind.LetBinding {
        emit_let_binding(node)
        return
    }

    if kind == NodeKind.Assignment {
        emit_expr(np_target.get(node).unwrap())
        let target_str = expr_result_str
        emit_expr(np_value.get(node).unwrap())
        let val_str = expr_result_str
        emit_line("{target_str} = {val_str};")
        return
    }

    if kind == NodeKind.CompoundAssign {
        emit_expr(np_target.get(node).unwrap())
        let target_str = expr_result_str
        emit_expr(np_value.get(node).unwrap())
        let val_str = expr_result_str
        let op = np_op.get(node).unwrap()
        emit_line("{target_str} {op}= {val_str};")
        return
    }

    if kind == NodeKind.Return {
        if np_value.get(node).unwrap() != -1 {
            emit_expr(np_value.get(node).unwrap())
            let val_str = expr_result_str
            emit_line("return {val_str};")
        } else {
            emit_line("return;")
        }
        return
    }

    if kind == NodeKind.ForIn {
        emit_for_in(node)
        return
    }

    if kind == NodeKind.WhileLoop {
        let pre_len = cg_lines.len()
        emit_expr(np_condition.get(node).unwrap())
        let cond_str = expr_result_str
        let post_len = cg_lines.len()
        if post_len > pre_len {
            let mut cond_setup: List[Str] = []
            let mut ci = pre_len
            while ci < post_len {
                cond_setup.push(cg_lines.get(ci).unwrap())
                ci = ci + 1
            }
            let mut ri = post_len - 1
            while ri >= pre_len {
                cg_lines.pop()
                ri = ri - 1
            }
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            let mut si = 0
            while si < cond_setup.len() {
                cg_lines.push(cond_setup.get(si).unwrap())
                si = si + 1
            }
            emit_line("if (!({cond_str})) break;")
            emit_block(np_body.get(node).unwrap())
            cg_indent = cg_indent - 1
            emit_line("}")
        } else {
            emit_line("while ({cond_str}) \{")
            cg_indent = cg_indent + 1
            emit_block(np_body.get(node).unwrap())
            cg_indent = cg_indent - 1
            emit_line("}")
        }
        return
    }

    if kind == NodeKind.LoopExpr {
        emit_line("while (1) \{")
        cg_indent = cg_indent + 1
        emit_block(np_body.get(node).unwrap())
        cg_indent = cg_indent - 1
        emit_line("}")
        return
    }

    if kind == NodeKind.Break {
        emit_line("break;")
        return
    }

    if kind == NodeKind.Continue {
        emit_line("continue;")
        return
    }

    if kind == NodeKind.IfExpr {
        emit_if_stmt(node)
        return
    }

    if kind == NodeKind.MatchExpr {
        emit_match_expr(node)
        return
    }

    if kind == NodeKind.WithBlock {
        emit_with_block(node)
        return
    }

    // Fallback: treat as expression
    emit_expr(node)
    let s = expr_result_str
    if s != "" {
        emit_line("{s};")
    }
}

pub fn infer_enum_from_node(val_node: Int) -> Str {
    let vk = np_kind.get(val_node).unwrap()
    if vk == NodeKind.FieldAccess {
        let obj = np_obj.get(val_node).unwrap()
        if np_kind.get(obj).unwrap() == NodeKind.Ident {
            let obj_name = np_name.get(obj).unwrap()
            if is_enum_type(obj_name) != 0 {
                return obj_name
            }
        }
    }
    if vk == NodeKind.Ident {
        return resolve_variant(np_name.get(val_node).unwrap())
    }
    if vk == NodeKind.Call {
        let func = np_left.get(val_node).unwrap()
        if np_kind.get(func).unwrap() == NodeKind.Ident {
            let fn_name = np_name.get(func).unwrap()
            let resolved = resolve_variant(fn_name)
            if resolved != "" {
                return resolved
            }
        }
    }
    if vk == NodeKind.MethodCall {
        let mc_obj = np_obj.get(val_node).unwrap()
        if np_kind.get(mc_obj).unwrap() == NodeKind.Ident {
            let mc_name = np_name.get(mc_obj).unwrap()
            if is_enum_type(mc_name) != 0 {
                return mc_name
            }
        }
    }
    ""
}

pub fn emit_tuple_destructure(pat_node: Int, source_var: Str, struct_name: Str, is_mut: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope {
    let elems_sl = np_elements.get(pat_node).unwrap()
    if elems_sl == -1 { return }
    let mut di = 0
    while di < sublist_length(elems_sl) {
        let sub_pat = sublist_get(elems_sl, di)
        let elem_name = np_name.get(sub_pat).unwrap()
        let field_name = "_{di}"
        let ft = get_struct_field_type(struct_name, field_name)
        let fs = get_struct_field_stype(struct_name, field_name)
        let c_elem = c_safe_name(elem_name)
        if fs != "" {
            emit_line("{c_type_c_name(fs)} {c_elem} = {source_var}.{field_name};")
            set_var(elem_name, CT_VOID, is_mut)
            set_var_struct(c_elem, fs)
        } else {
            emit_line("{c_type_str(ft)} {c_elem} = {source_var}.{field_name};")
            set_var(elem_name, ft, is_mut)
        }
        di = di + 1
    }
}

pub fn emit_let_binding(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let val_node = np_value.get(node).unwrap()
    let mut enum_type = infer_enum_from_node(val_node)
    let type_ann = np_target.get(node).unwrap()
    if enum_type == "" && type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if is_enum_type(ann_name) != 0 {
            enum_type = ann_name
        }
    }
    let saved_let_target = cg_let_target_type
    let saved_let_target_name = cg_let_target_name
    if type_ann != -1 {
        cg_let_target_type = type_from_name(np_name.get(type_ann).unwrap())
        cg_let_target_name = np_name.get(type_ann).unwrap()
    } else {
        cg_let_target_type = 0
        cg_let_target_name = ""
    }
    emit_expr(val_node)
    cg_let_target_type = saved_let_target
    cg_let_target_name = saved_let_target_name
    let val_str = expr_result_str
    let val_type = expr_result_type
    if val_type == CT_RESULT {
        enum_type = ""
    }
    let mut name = np_name.get(node).unwrap()
    if name == "_destructure" {
        name = fresh_temp("_destr")
    }
    let is_mut = np_is_mut.get(node).unwrap()
    set_var(name, val_type, is_mut)
    if enum_type != "" {
        var_enums.push(VarEnumEntry { name: name, enum_type: enum_type })
    }
    if val_type == CT_CLOSURE {
        set_var_closure(name, expr_closure_sig)
    }
    if val_type == CT_OPTION {
        if expr_option_inner_struct != "" {
            set_var_option_struct(name, expr_option_inner, expr_option_inner_struct)
        } else {
            set_var_option(name, expr_option_inner)
        }
        if expr_option_inner == CT_LIST && expr_option_inner_list_elem != -1 {
            set_var_option_inner2(name, expr_option_inner_list_elem)
            expr_option_inner_list_elem = -1
        }
    }
    if val_type == CT_RESULT {
        if expr_result_ok_struct != "" || expr_result_err_struct != "" {
            set_var_result_struct(name, expr_result_ok_type, expr_result_err_type, expr_result_ok_struct, expr_result_err_struct)
        } else {
            set_var_result(name, expr_result_ok_type, expr_result_err_type)
        }
    }
    if val_type == CT_HANDLE {
        let inner = get_var_handle_inner(val_str)
        if inner >= 0 {
            set_var_handle(name, inner)
        } else {
            set_var_handle(name, CT_INT)
        }
    }
    if val_type == CT_CHANNEL {
        let ch_inner = get_var_channel_inner(val_str)
        if ch_inner >= 0 {
            set_var_channel(name, ch_inner)
        } else {
            set_var_channel(name, CT_INT)
        }
    }
    if np_kind.get(val_node).unwrap() == NodeKind.StructLit {
        let expr_struct = get_var_struct(val_str)
        if expr_struct != "" {
            set_var_struct(name, expr_struct)
        } else {
            let sname = np_type_name.get(val_node).unwrap()
            if is_struct_type(sname) != 0 {
                set_var_struct(name, sname)
            }
        }
    } else if type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if is_struct_type(ann_name) != 0 {
            set_var_struct(name, ann_name)
        } else if ann_name == "Tuple" {
            let tup_name = resolve_tuple_ann(type_ann)
            set_var_struct(name, tup_name)
        } else {
            let expr_struct = get_var_struct(val_str)
            if expr_struct != "" {
                set_var_struct(name, expr_struct)
            }
        }
    } else {
        let expr_struct = get_var_struct(val_str)
        if expr_struct != "" {
            set_var_struct(name, expr_struct)
        }
    }
    if val_type == CT_LIST && type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if ann_name == "List" {
            let elems_sl = np_elements.get(type_ann).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                let elem_ann = sublist_get(elems_sl, 0)
                let elem_name = np_name.get(elem_ann).unwrap()
                let elem_ct = type_from_name(elem_name)
                set_list_elem_type(name, elem_ct)
                if elem_ct == CT_VOID && is_struct_type(elem_name) != 0 {
                    set_list_elem_struct(name, elem_name)
                }
                if elem_ct == CT_LIST {
                    let nested_sl = np_elements.get(elem_ann).unwrap()
                    if nested_sl != -1 && sublist_length(nested_sl) > 0 {
                        let nested_ann = sublist_get(nested_sl, 0)
                        let nested_name = np_name.get(nested_ann).unwrap()
                        set_list_nested_elem_type(name, type_from_name(nested_name))
                    }
                }
            }
        }
    }
    if val_type == CT_MAP && type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if ann_name == "Map" {
            let elems_sl = np_elements.get(type_ann).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                let key_ann = sublist_get(elems_sl, 0)
                let val_ann = sublist_get(elems_sl, 1)
                let key_ct = type_from_name(np_name.get(key_ann).unwrap())
                let val_ct = type_from_name(np_name.get(val_ann).unwrap())
                set_map_types(name, key_ct, val_ct)
            }
        }
    }
    if val_type == CT_LIST && expr_list_elem_type >= 0 {
        set_list_elem_type(name, expr_list_elem_type)
        expr_list_elem_type = -1
        let src_struct = get_list_elem_struct(val_str)
        if src_struct != "" {
            set_list_elem_struct(name, src_struct)
        }
        let src_nested = get_list_nested_elem_type(val_str)
        if src_nested != -1 {
            set_list_nested_elem_type(name, src_nested)
        }
    }
    if val_type == CT_ITERATOR {
        set_var_alias(name, val_str)
        let iter_inner = get_var_iterator_inner(val_str)
        let iter_next = get_var_iter_next_fn(val_str)
        if iter_inner >= 0 {
            set_var_iterator(name, iter_inner, iter_next)
        }
        return
    }
    let struct_type = get_var_struct(name)
    let cname = c_safe_name(name)
    if val_type == CT_OPTION {
        let opt_inner = get_var_option_inner(name)
        let opt_inner_s = get_var_option_inner_struct(name)
        let opt_c_inner = opt_inner
        let opt_c = option_c_type_mixed(opt_c_inner, opt_inner_s)
        if is_mut != 0 {
            emit_line("{opt_c} {cname} = {val_str};")
        } else {
            emit_line("const {opt_c} {cname} = {val_str};")
        }
    } else if val_type == CT_RESULT {
        let rok = get_var_result_ok(name)
        let rerr = get_var_result_err(name)
        let rok_s = get_var_result_ok_struct(name)
        let rerr_s = get_var_result_err_struct(name)
        let res_c = result_c_type_mixed(rok, rerr, rok_s, rerr_s)
        if is_mut != 0 {
            emit_line("{res_c} {cname} = {val_str};")
        } else {
            emit_line("const {res_c} {cname} = {val_str};")
        }
    } else if enum_type != "" {
        if is_mut != 0 {
            emit_line("{c_type_c_name(enum_type)} {cname} = {val_str};")
        } else {
            emit_line("const {c_type_c_name(enum_type)} {cname} = {val_str};")
        }
    } else if struct_type != "" {
        if is_mut != 0 {
            emit_line("{c_type_c_name(struct_type)} {cname} = {val_str};")
        } else {
            emit_line("const {c_type_c_name(struct_type)} {cname} = {val_str};")
        }
    } else {
        let ts = c_type_str(val_type)
        if is_mut != 0 || val_type == CT_STRING || val_type == CT_LIST || val_type == CT_MAP || val_type == CT_BYTES || val_type == CT_CLOSURE || val_type == CT_ITERATOR || val_type == CT_HANDLE || val_type == CT_CHANNEL {
            emit_line("{ts} {cname} = {val_str};")
        } else {
            emit_line("const {ts} {cname} = {val_str};")
        }
    }
    if is_mut_captured(name) != 0 {
        let cell_type = c_type_str(val_type)
        emit_line("{cell_type}* {cname}_cell = ({cell_type}*)pact_alloc(sizeof({cell_type}));")
        emit_line("*{cname}_cell = {cname};")
    }
    let destr_pat_sl = np_elements.get(node).unwrap()
    if destr_pat_sl != -1 {
        let tup_struct = get_var_struct(cname)
        if tup_struct != "" {
            emit_tuple_destructure(destr_pat_sl, cname, tup_struct, is_mut)
        }
    }
}

pub fn emit_for_in(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let var_name = np_var_name.get(node).unwrap()
    let c_var_name = c_safe_name(var_name)
    let iter_node = np_iterable.get(node).unwrap()
    let iter_kind = np_kind.get(iter_node).unwrap()

    if iter_kind == NodeKind.RangeLit {
        ensure_range_iter()
        emit_expr(np_start.get(iter_node).unwrap())
        let start_str = expr_result_str
        emit_expr(np_end.get(iter_node).unwrap())
        let end_str = expr_result_str
        let mut incl_val = "0"
        if np_inclusive.get(iter_node).unwrap() != 0 {
            incl_val = "1"
        }
        let iter_var = fresh_temp("__iter_")
        let next_var = fresh_temp("__next_")
        let opt_type = option_c_type(CT_INT)
        emit_line("pact_RangeIterator {iter_var} = \{ .current = {start_str}, .end = {end_str}, .is_inclusive = {incl_val} };")
        emit_line("while (1) \{")
        cg_indent = cg_indent + 1
        emit_line("{opt_type} {next_var} = pact_RangeIterator_next(&{iter_var});")
        emit_line("if ({next_var}.tag == 0) break;")
        emit_line("int64_t {c_var_name} = {next_var}.value;")
        push_scope()
        set_var(var_name, CT_INT, 1)
        emit_block(np_body.get(node).unwrap())
        pop_scope()
        cg_indent = cg_indent - 1
        emit_line("}")
    } else {
        emit_expr(iter_node)
        let iter_str = expr_result_str
        let iter_type = expr_result_type
        if iter_type == CT_LIST {
            let mut elem_type = get_list_elem_type(iter_str)
            if elem_type == -1 { elem_type = CT_INT }
            let elem_struct = get_list_elem_struct(iter_str)
            if elem_struct != "" {
                ensure_iter_type(CT_INT)
                let li_type = list_iter_c_type(CT_INT)
                let opt_type = option_c_type(CT_INT)
                let iter_var = fresh_temp("__iter_")
                let next_var = fresh_temp("__next_")
                emit_line("{li_type} {iter_var} = pact_list_into_iter_int({iter_str});")
                emit_line("while (1) \{")
                cg_indent = cg_indent + 1
                emit_line("{opt_type} {next_var} = {li_type}_next(&{iter_var});")
                emit_line("if ({next_var}.tag == 0) break;")
                let struct_c = c_type_c_name(elem_struct)
                emit_line("{struct_c} {c_var_name} = *({struct_c}*)(intptr_t){next_var}.value;")
                push_scope()
                set_var(var_name, CT_VOID, 0)
                set_var_struct(c_var_name, elem_struct)
                let for_pat_sl = np_elements.get(node).unwrap()
                if for_pat_sl != -1 {
                    emit_tuple_destructure(for_pat_sl, c_var_name, elem_struct, 0)
                }
                emit_block(np_body.get(node).unwrap())
                pop_scope()
                cg_indent = cg_indent - 1
                emit_line("}")
            } else {
                ensure_iter_type(elem_type)
                let tag = c_type_tag(elem_type)
                let li_type = list_iter_c_type(elem_type)
                let opt_type = option_c_type(elem_type)
                let iter_var = fresh_temp("__iter_")
                let next_var = fresh_temp("__next_")
                emit_line("{li_type} {iter_var} = pact_list_into_iter_{tag}({iter_str});")
                emit_line("while (1) \{")
                cg_indent = cg_indent + 1
                emit_line("{opt_type} {next_var} = {li_type}_next(&{iter_var});")
                emit_line("if ({next_var}.tag == 0) break;")
                emit_line("{c_type_str(elem_type)} {c_var_name} = {next_var}.value;")
                push_scope()
                set_var(var_name, elem_type, 0)
                emit_block(np_body.get(node).unwrap())
                pop_scope()
                cg_indent = cg_indent - 1
                emit_line("}")
            }
        } else if iter_type == CT_ITERATOR {
            let elem_type = get_var_iterator_inner(iter_str)
            let next_fn = get_var_iter_next_fn(iter_str)
            let opt_type = option_c_type(elem_type)
            let iter_var = fresh_temp("__iter_")
            let next_var = fresh_temp("__next_")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_type} {next_var} = (({opt_type} (*)(void*)){next_fn})(&{iter_str});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("{c_type_str(elem_type)} {c_var_name} = {next_var}.value;")
            push_scope()
            set_var(var_name, elem_type, 0)
            emit_block(np_body.get(node).unwrap())
            pop_scope()
            cg_indent = cg_indent - 1
            emit_line("}")
        } else if iter_type == CT_CHANNEL {
            let ch_inner = get_var_channel_inner(iter_str)
            let recv_tmp = fresh_temp("__chrecv_")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("void* {recv_tmp} = pact_channel_recv({iter_str});")
            emit_line("if ({recv_tmp} == NULL) break;")
            if ch_inner == CT_STRING {
                emit_line("const char* {c_var_name} = (const char*){recv_tmp};")
                push_scope()
                set_var(var_name, CT_STRING, 0)
            } else {
                emit_line("int64_t {c_var_name} = (int64_t)(intptr_t){recv_tmp};")
                push_scope()
                set_var(var_name, CT_INT, 0)
            }
            emit_block(np_body.get(node).unwrap())
            pop_scope()
            cg_indent = cg_indent - 1
            emit_line("}")
        } else if iter_type == CT_STRING {
            ensure_str_iter()
            let iter_var = fresh_temp("__str_iter_")
            let next_var = fresh_temp("__str_next_")
            let opt_type = option_c_type(CT_STRING)
            emit_line("pact_StrIterator {iter_var} = \{ .str = {iter_str}, .index = 0, .len = pact_str_len({iter_str}) };")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_type} {next_var} = pact_StrIterator_next(&{iter_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("const char* {c_var_name} = {next_var}.value;")
            push_scope()
            set_var(var_name, CT_STRING, 0)
            emit_block(np_body.get(node).unwrap())
            pop_scope()
            cg_indent = cg_indent - 1
            emit_line("}")
        } else {
            emit_line("/* unsupported iterable */")
        }
    }
}

pub fn emit_if_stmt(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    emit_expr(np_condition.get(node).unwrap())
    let cond_str = expr_result_str
    emit_line("if ({cond_str}) \{")
    cg_indent = cg_indent + 1
    emit_block(np_then_body.get(node).unwrap())
    cg_indent = cg_indent - 1
    if np_else_body.get(node).unwrap() != -1 {
        let else_b = np_else_body.get(node).unwrap()
        let else_stmts = np_stmts.get(else_b).unwrap()
        // Check for else-if chain
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner).unwrap() == NodeKind.IfExpr {
                let saved_lines2 = cg_lines
                cg_lines = []
                emit_expr(np_condition.get(inner).unwrap())
                let hoisted_lines = cg_lines
                cg_lines = saved_lines2
                if hoisted_lines.len() > 0 {
                    emit_line("} else \{")
                    cg_indent = cg_indent + 1
                    emit_if_stmt(inner)
                    cg_indent = cg_indent - 1
                } else {
                    let inner_cond = expr_result_str
                    emit_line("} else if ({inner_cond}) \{")
                    cg_indent = cg_indent + 1
                    emit_block(np_then_body.get(inner).unwrap())
                    cg_indent = cg_indent - 1
                    if np_else_body.get(inner).unwrap() != -1 {
                        emit_line("} else \{")
                        cg_indent = cg_indent + 1
                        emit_block(np_else_body.get(inner).unwrap())
                        cg_indent = cg_indent - 1
                    }
                }
                emit_line("}")
                return
            }
        }
        emit_line("} else \{")
        cg_indent = cg_indent + 1
        emit_block(else_b)
        cg_indent = cg_indent - 1
    }
    emit_line("}")
}

pub fn emit_block(block: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block).unwrap()
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        emit_stmt(sublist_get(stmts_sl, i))
        i = i + 1
    }
}

// __ With-block codegen __

pub fn emit_with_block(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let handlers_sl = np_handlers.get(node).unwrap()
    let body = np_body.get(node).unwrap()
    if handlers_sl == -1 {
        emit_block(body)
        return
    }
    let count = sublist_length(handlers_sl)
    let mut resource_names: List[Str] = []
    let mut resource_vars: List[Str] = []
    let mut saved_fields: List[Str] = []
    let mut saved_temps: List[Str] = []
    emit_line("\{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < count {
        let item = sublist_get(handlers_sl, i)
        let item_kind = np_kind.get(item).unwrap()
        if item_kind == NodeKind.WithResource {
            let binding = np_name.get(item).unwrap()
            let res_expr = np_value.get(item).unwrap()
            emit_expr(res_expr)
            let res_str = expr_result_str
            let tmp = fresh_temp("_wr_")
            emit_line("int64_t {tmp} = {res_str};")
            emitted_let_names.push(binding)
            emitted_let_set.set(binding, 1)
            emit_line("int64_t {binding} = {tmp};")
            resource_names.push(binding)
            resource_vars.push(tmp)
        } else {
            emit_expr(item)
            let handler_str = expr_result_str
            let vtable_field = cg_handler_vtable_field
            let is_ue = cg_handler_is_user_effect
            if vtable_field != "" {
                let save_name = fresh_temp("__saved_")
                if is_ue != 0 {
                    emit_line("void* {save_name} = (void*)__pact_ue_{vtable_field};")
                    emit_line("__pact_ue_{vtable_field} = &{handler_str};")
                } else {
                    emit_line("void* {save_name} = (void*)__pact_ctx.{vtable_field};")
                    emit_line("__pact_ctx.{vtable_field} = &{handler_str};")
                }
                if is_ue != 0 {
                    saved_fields.push("ue:{vtable_field}")
                } else {
                    saved_fields.push(vtable_field)
                }
                saved_temps.push(save_name)
            } else if handler_str != "" {
                emit_line("{handler_str};")
            }
        }
        i = i + 1
    }
    emit_block(body)
    let mut ri = saved_fields.len() - 1
    while ri >= 0 {
        let sf = saved_fields.get(ri).unwrap()
        let st = saved_temps.get(ri).unwrap()
        if sf.starts_with("ue:") {
            let ue_field = sf.substring(3, sf.len())
            emit_line("__pact_ue_{ue_field} = (void*){st};")
        } else {
            emit_line("__pact_ctx.{sf} = (void*){st};")
        }
        ri = ri - 1
    }
    let mut rri = resource_names.len() - 1
    while rri >= 0 {
        let rname = resource_names.get(rri).unwrap()
        emit_line("// close resource: {rname}")
        emit_line("/* {rname}.close() -- Closeable trait call */")
        rri = rri - 1
    }
    cg_indent = cg_indent - 1
    emit_line("}")
}

// ── Function codegen ────────────────────────────────────────────────

pub fn format_params(fn_node: Int) -> Str {
    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl == -1 {
        return "void"
    }
    let count = sublist_length(params_sl)
    if count == 0 {
        return "void"
    }
    let mut result = ""
    let mut i = 0
    while i < count {
        let p = sublist_get(params_sl, i)
        let pname = c_safe_name(np_name.get(p).unwrap())
        let ptype = np_type_name.get(p).unwrap()
        if i > 0 {
            result = result.concat(", ")
        }
        if ptype == "Fn" {
            result = result.concat("pact_closure* {pname}")
        } else if ptype == "Tuple" {
            let ta = np_type_ann.get(p).unwrap()
            if ta != -1 {
                let tup_name = resolve_tuple_ann(ta)
                result = result.concat("{c_type_c_name(tup_name)} {pname}")
            } else {
                result = result.concat("void {pname}")
            }
        } else if is_enum_type(ptype) != 0 {
            result = result.concat("{c_type_c_name(ptype)} {pname}")
        } else if is_struct_type(ptype) != 0 {
            result = result.concat("{c_type_c_name(ptype)} {pname}")
        } else {
            let ct = type_from_name(ptype)
            result = result.concat("{c_type_str(ct)} {pname}")
        }
        i = i + 1
    }
    result
}

pub fn format_impl_params(fn_node: Int, impl_type: Str) -> Str {
    let params_sl = np_params.get(fn_node).unwrap()
    let has_self = impl_method_has_self(fn_node)
    let mut result = ""
    if has_self != 0 {
        result = "{c_type_c_name(impl_type)} self"
    }
    let mut first = 1
    if has_self != 0 {
        first = 0
    }
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname_raw = np_name.get(p).unwrap()
            if pname_raw != "self" {
                let pname = c_safe_name(pname_raw)
                let ptype_raw = np_type_name.get(p).unwrap()
                let ptype = resolve_self_type(ptype_raw, impl_type)
                if first == 0 {
                    result = result.concat(", ")
                }
                first = 0
                if ptype == "Fn" {
                    result = result.concat("pact_closure* {pname}")
                } else if ptype == "Tuple" {
                    let ta = np_type_ann.get(p).unwrap()
                    if ta != -1 {
                        let tup_name = resolve_tuple_ann(ta)
                        result = result.concat("{c_type_c_name(tup_name)} {pname}")
                    } else {
                        result = result.concat("void {pname}")
                    }
                } else if is_struct_type(ptype) != 0 {
                    result = result.concat("{c_type_c_name(ptype)} {pname}")
                } else if is_enum_type(ptype) != 0 {
                    result = result.concat("{c_type_c_name(ptype)} {pname}")
                } else {
                    let ct = type_from_name(ptype)
                    result = result.concat("{c_type_str(ct)} {pname}")
                }
            }
            i = i + 1
        }
    }
    if result == "" {
        result = "void"
    }
    result
}

pub fn emit_requires_assertions(fn_node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let anns_sl = np_handlers.get(fn_node).unwrap()
    if anns_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(anns_sl) {
        let ann = sublist_get(anns_sl, i)
        let ann_name = np_name.get(ann).unwrap()
        if ann_name == "requires" {
            let args_sl = np_args.get(ann).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                let expr_node = sublist_get(args_sl, 0)
                emit_expr(expr_node)
                let cond = expr_result_str
                emit_line("if (!({cond})) \{ fprintf(stderr, \"precondition failed: @requires in %s\\n\", \"{cg_current_fn_name}\"); exit(1); }")
            }
        }
        i = i + 1
    }
}

pub fn emit_impl_method_def(fn_node: Int, impl_type: Str) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    push_scope()
    cg_temp_counter = 0
    let mname = np_name.get(fn_node).unwrap()
    let mangled = "{impl_type}_{mname}"
    cg_current_fn_name = mangled
    let ret_str_raw = np_return_type.get(fn_node).unwrap()
    let ret_str = resolve_self_type(ret_str_raw, impl_type)
    let ret_type = type_from_name(ret_str)
    cg_current_fn_ret = ret_type
    let params = format_impl_params(fn_node, impl_type)
    let enum_ret = get_fn_enum_ret(mangled)
    let mut sig = ""
    if enum_ret != "" {
        sig = "{c_type_c_name(enum_ret)} {c_fn_name(mangled)}({params})"
    } else if is_struct_type(ret_str) != 0 {
        sig = "{c_type_c_name(ret_str)} {c_fn_name(mangled)}({params})"
    } else {
        let resolved = resolve_ret_type_from_ann(fn_node)
        if resolved != "" {
            sig = "{resolved} {c_fn_name(mangled)}({params})"
        } else {
            sig = "{c_type_str(ret_type)} {c_fn_name(mangled)}({params})"
        }
    }

    let has_self = impl_method_has_self(fn_node)
    if has_self != 0 {
        set_var("self", CT_VOID, 0)
        set_var_struct("self", impl_type)
    }

    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p).unwrap()
            if pname != "self" {
                let ptype_raw = np_type_name.get(p).unwrap()
                let ptype = resolve_self_type(ptype_raw, impl_type)
                if ptype == "Fn" {
                    set_var(pname, CT_CLOSURE, 1)
                    let ta = np_type_ann.get(p).unwrap()
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
                    if ptype == "List" {
                        let ta = np_type_ann.get(p).unwrap()
                        if ta != -1 {
                            let elems_sl = np_elements.get(ta).unwrap()
                            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                                let elem_ann = sublist_get(elems_sl, 0)
                                let elem_name = np_name.get(elem_ann).unwrap()
                                let elem_ct = type_from_name(elem_name)
                                set_list_elem_type(pname, elem_ct)
                                if elem_ct == CT_VOID && is_struct_type(elem_name) != 0 {
                                    set_list_elem_struct(pname, elem_name)
                                }
                            }
                        }
                    }
                    if ptype == "Map" {
                        let ta = np_type_ann.get(p).unwrap()
                        if ta != -1 {
                            let elems_sl = np_elements.get(ta).unwrap()
                            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                                let key_ann = sublist_get(elems_sl, 0)
                                let val_ann = sublist_get(elems_sl, 1)
                                set_map_types(pname, type_from_name(np_name.get(key_ann).unwrap()), type_from_name(np_name.get(val_ann).unwrap()))
                            }
                        }
                    }
                    if ptype == "Tuple" {
                        let ta = np_type_ann.get(p).unwrap()
                        if ta != -1 {
                            let tup_name = resolve_tuple_ann(ta)
                            set_var_struct(pname, tup_name)
                        }
                    }
                }
            }
            i = i + 1
        }
    }

    let mut body_ret = ret_type
    if is_struct_type(ret_str) != 0 || is_enum_type(ret_str) != 0 || ret_str == "Tuple" {
        body_ret = CT_INT
    }
    cg_current_fn_node = fn_node
    emit_line("{sig} \{")
    cg_indent = cg_indent + 1
    emit_requires_assertions(fn_node)
    emit_fn_body(np_body.get(fn_node).unwrap(), body_ret)
    cg_indent = cg_indent - 1
    emit_line("}")
    pop_scope()
}

pub fn emit_fn_decl(fn_node: Int) ! Codegen.Emit {
    let name = np_name.get(fn_node).unwrap()
    if name == "main" {
        emit_line("void pact_main(void);")
        return
    }
    let params = format_params(fn_node)
    let enum_ret = get_fn_enum_ret(name)
    if enum_ret != "" {
        emit_line("{c_type_c_name(enum_ret)} {c_fn_name(name)}({params});")
    } else {
        let ret_str = np_return_type.get(fn_node).unwrap()
        if is_struct_type(ret_str) != 0 {
            emit_line("{c_type_c_name(ret_str)} {c_fn_name(name)}({params});")
        } else {
            let resolved = resolve_ret_type_from_ann(fn_node)
            if resolved != "" {
                emit_line("{resolved} {c_fn_name(name)}({params});")
            } else {
                let ret_type = type_from_name(ret_str)
                emit_line("{c_type_str(ret_type)} {c_fn_name(name)}({params});")
            }
        }
    }
}

pub fn emit_fn_def(fn_node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    push_scope()
    cg_temp_counter = 0
    let name = np_name.get(fn_node).unwrap()
    cg_current_fn_name = name
    let ret_str = np_return_type.get(fn_node).unwrap()
    let ret_type = type_from_name(ret_str)
    cg_current_fn_ret = ret_type
    let mut sig = ""
    if name == "main" {
        sig = "void pact_main(void)"
    } else {
        let params = format_params(fn_node)
        let enum_ret = get_fn_enum_ret(name)
        if enum_ret != "" {
            sig = "{c_type_c_name(enum_ret)} {c_fn_name(name)}({params})"
        } else if is_struct_type(ret_str) != 0 {
            sig = "{c_type_c_name(ret_str)} {c_fn_name(name)}({params})"
        } else {
            let resolved = resolve_ret_type_from_ann(fn_node)
            if resolved != "" {
                sig = "{resolved} {c_fn_name(name)}({params})"
            } else {
                sig = "{c_type_str(ret_type)} {c_fn_name(name)}({params})"
            }
        }
    }

    // Register params in scope
    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p).unwrap()
            let ptype = np_type_name.get(p).unwrap()
            if ptype == "Fn" {
                set_var(pname, CT_CLOSURE, 1)
                let ta = np_type_ann.get(p).unwrap()
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
                if ptype == "List" {
                    let ta = np_type_ann.get(p).unwrap()
                    if ta != -1 {
                        let elems_sl = np_elements.get(ta).unwrap()
                        if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                            let elem_ann = sublist_get(elems_sl, 0)
                            let elem_name = np_name.get(elem_ann).unwrap()
                            let elem_ct = type_from_name(elem_name)
                            set_list_elem_type(pname, elem_ct)
                            if elem_ct == CT_VOID && is_struct_type(elem_name) != 0 {
                                set_list_elem_struct(pname, elem_name)
                            }
                        }
                    }
                }
                if ptype == "Map" {
                    let ta = np_type_ann.get(p).unwrap()
                    if ta != -1 {
                        let elems_sl = np_elements.get(ta).unwrap()
                        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                            let key_ann = sublist_get(elems_sl, 0)
                            let val_ann = sublist_get(elems_sl, 1)
                            set_map_types(pname, type_from_name(np_name.get(key_ann).unwrap()), type_from_name(np_name.get(val_ann).unwrap()))
                        }
                    }
                }
                if ptype == "Tuple" {
                    let ta = np_type_ann.get(p).unwrap()
                    if ta != -1 {
                        let tup_name = resolve_tuple_ann(ta)
                        set_var_struct(pname, tup_name)
                    }
                }
            }
            i = i + 1
        }
    }

    mut_captured_vars = []
    prescan_mut_captures(np_body.get(fn_node).unwrap())

    let mut body_ret = ret_type
    if is_struct_type(ret_str) != 0 || ret_str == "Tuple" {
        body_ret = CT_INT
    }
    cg_current_fn_node = fn_node
    emit_line("{sig} \{")
    cg_indent = cg_indent + 1
    emit_requires_assertions(fn_node)
    emit_fn_body(np_body.get(fn_node).unwrap(), body_ret)
    cg_indent = cg_indent - 1
    emit_line("}")
    pop_scope()
}

pub fn emit_fn_body(block: Int, ret_type: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block).unwrap()
    if stmts_sl == -1 {
        return
    }
    let count = sublist_length(stmts_sl)
    if count == 0 {
        return
    }
    let mut i = 0
    while i < count - 1 {
        emit_stmt(sublist_get(stmts_sl, i))
        i = i + 1
    }
    let last = sublist_get(stmts_sl, count - 1)
    let last_kind = np_kind.get(last).unwrap()
    if ret_type != CT_VOID && last_kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(last).unwrap())
        let val_str = expr_result_str
        emit_line("return {val_str};")
    } else if ret_type != CT_VOID && last_kind == NodeKind.IfExpr {
        emit_if_expr(last)
        let val_str = expr_result_str
        emit_line("return {val_str};")
    } else {
        emit_stmt(last)
    }
}

// ── Type definition codegen ─────────────────────────────────────────

pub fn find_type_def(name: Str) -> Int {
    let types_sl = np_fields.get(cg_program_node).unwrap()
    if types_sl == -1 {
        return -1
    }
    let mut i = 0
    while i < sublist_length(types_sl) {
        let td = sublist_get(types_sl, i)
        if np_name.get(td).unwrap() == name {
            return td
        }
        i = i + 1
    }
    -1
}

pub fn resolve_type_param(param_name: Str, tparams_sl: Int, concrete_args: Str) -> Str {
    let mut pi = 0
    let mut arg_idx = 0
    while pi < sublist_length(tparams_sl) {
        let tp = sublist_get(tparams_sl, pi)
        if np_name.get(tp).unwrap() == param_name {
            // Find the arg_idx-th comma-separated segment in concrete_args
            let mut seg_start = 0
            let mut seg_idx = 0
            let mut ci = 0
            while ci <= concrete_args.len() {
                if ci == concrete_args.len() || concrete_args.char_at(ci) == 44 {
                    if seg_idx == arg_idx {
                        return concrete_args.substring(seg_start, ci - seg_start)
                    }
                    seg_idx = seg_idx + 1
                    seg_start = ci + 1
                }
                ci = ci + 1
            }
        }
        pi = pi + 1
        arg_idx = arg_idx + 1
    }
    param_name
}

pub fn register_mono_field_types(base_name: Str, mono_name: Str, concrete_args: Str) {
    // Check if already registered
    let mut check = 0
    while check < sf_entries.len() {
        if sf_entries.get(check).unwrap().struct_name == mono_name {
            return
        }
        check = check + 1
    }
    let td = find_type_def(base_name)
    if td == -1 {
        return
    }
    let tparams_sl = np_type_params.get(td).unwrap()
    if tparams_sl == -1 {
        return
    }
    let flds_sl = np_fields.get(td).unwrap()
    if flds_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f).unwrap()
        let type_ann_node = np_value.get(f).unwrap()
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node).unwrap()
            let resolved = resolve_type_param(type_name, tparams_sl, concrete_args)
            if is_struct_type(resolved) != 0 {
                sf_entries.push(StructFieldEntry { struct_name: mono_name, field_name: fname, field_type: CT_VOID, stype: resolved })
            } else {
                let ct = type_from_name(resolved)
                sf_entries.push(StructFieldEntry { struct_name: mono_name, field_name: fname, field_type: ct, stype: "" })
            }
        } else {
            sf_entries.push(StructFieldEntry { struct_name: mono_name, field_name: fname, field_type: CT_INT, stype: "" })
        }
        i = i + 1
    }
}

pub fn emit_mono_struct_typedef(base_name: Str, concrete_args: Str) ! Codegen.Emit {
    let td = find_type_def(base_name)
    if td == -1 {
        return
    }
    let tparams_sl = np_type_params.get(td).unwrap()
    if tparams_sl == -1 {
        return
    }
    let c_name = mangle_generic_name(base_name, concrete_args)
    let flds_sl = np_fields.get(td).unwrap()
    if flds_sl == -1 {
        return
    }
    struct_reg_names.push(c_name)
    struct_reg_set.set(c_name, 1)
    emit_line("typedef struct \{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f).unwrap()
        let type_ann_node = np_value.get(f).unwrap()
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node).unwrap()
            let resolved = resolve_type_param(type_name, tparams_sl, concrete_args)
            if is_struct_type(resolved) != 0 {
                emit_line("{c_type_c_name(resolved)} {fname};")
                sf_entries.push(StructFieldEntry { struct_name: c_name, field_name: fname, field_type: CT_VOID, stype: resolved })
            } else {
                let ct = type_from_name(resolved)
                emit_line("{c_type_str(ct)} {fname};")
                sf_entries.push(StructFieldEntry { struct_name: c_name, field_name: fname, field_type: ct, stype: "" })
            }
        } else {
            emit_line("int64_t {fname};")
            sf_entries.push(StructFieldEntry { struct_name: c_name, field_name: fname, field_type: CT_INT, stype: "" })
        }
        i = i + 1
    }
    cg_indent = cg_indent - 1
    emit_line("} {c_type_c_name(c_name)};")
    emit_line("")
}

pub fn emit_all_mono_typedefs() ! Codegen.Emit {
    let mut i = 0
    while i < mono_instances.len() {
        let mi = mono_instances.get(i).unwrap()
        let td = find_type_def(mi.base)
        if td != -1 {
            let flds_sl = np_fields.get(td).unwrap()
            if flds_sl != -1 && sublist_length(flds_sl) > 0 {
                if np_kind.get(sublist_get(flds_sl, 0)).unwrap() != NodeKind.TypeVariant {
                    emit_mono_struct_typedef(mi.base, mi.args)
                }
            }
        }
        i = i + 1
    }
}

pub fn emit_mono_fn_def(fn_node: Int, concrete_args: Str) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let base_name = np_name.get(fn_node).unwrap()
    let mangled = mangle_generic_name(base_name, concrete_args)
    let tparams_sl = np_type_params.get(fn_node).unwrap()

    // Resolve return type
    let ret_str = np_return_type.get(fn_node).unwrap()
    let resolved_ret = resolve_type_param(ret_str, tparams_sl, concrete_args)
    let ret_type = type_from_name(resolved_ret)

    // Build parameter string with substituted types
    let params_sl = np_params.get(fn_node).unwrap()
    let mut params_c = "void"
    if params_sl != -1 && sublist_length(params_sl) > 0 {
        params_c = ""
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = c_safe_name(np_name.get(p).unwrap())
            let ptype = np_type_name.get(p).unwrap()
            let resolved_ptype = resolve_type_param(ptype, tparams_sl, concrete_args)
            if i > 0 {
                params_c = params_c.concat(", ")
            }
            if is_struct_type(resolved_ptype) != 0 {
                params_c = params_c.concat("{c_type_c_name(resolved_ptype)} {pname}")
            } else if is_enum_type(resolved_ptype) != 0 {
                params_c = params_c.concat("{c_type_c_name(resolved_ptype)} {pname}")
            } else {
                let ct = type_from_name(resolved_ptype)
                params_c = params_c.concat("{c_type_str(ct)} {pname}")
            }
            i = i + 1
        }
    }

    // Forward declaration
    emit_line("{c_type_str(ret_type)} {c_fn_name(mangled)}({params_c});")

    // Register params in scope
    push_scope()
    cg_temp_counter = 0
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p).unwrap()
            let ptype = np_type_name.get(p).unwrap()
            let resolved_ptype = resolve_type_param(ptype, tparams_sl, concrete_args)
            set_var(pname, type_from_name(resolved_ptype), 1)
            if is_struct_type(resolved_ptype) != 0 {
                set_var_struct(pname, resolved_ptype)
            }
            if is_enum_type(resolved_ptype) != 0 {
                var_enums.push(VarEnumEntry { name: pname, enum_type: resolved_ptype })
            }
            if resolved_ptype == "List" {
                let ta = np_type_ann.get(p).unwrap()
                if ta != -1 {
                    let elems_sl = np_elements.get(ta).unwrap()
                    if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                        let elem_ann = sublist_get(elems_sl, 0)
                        let elem_name = np_name.get(elem_ann).unwrap()
                        let elem_ct = type_from_name(elem_name)
                        set_list_elem_type(pname, elem_ct)
                        if elem_ct == CT_VOID && is_struct_type(elem_name) != 0 {
                            set_list_elem_struct(pname, elem_name)
                        }
                    }
                }
            }
            if resolved_ptype == "Map" {
                let ta = np_type_ann.get(p).unwrap()
                if ta != -1 {
                    let elems_sl = np_elements.get(ta).unwrap()
                    if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                        let key_ann = sublist_get(elems_sl, 0)
                        let val_ann = sublist_get(elems_sl, 1)
                        set_map_types(pname, type_from_name(np_name.get(key_ann).unwrap()), type_from_name(np_name.get(val_ann).unwrap()))
                    }
                }
            }
            if resolved_ptype == "Tuple" {
                let ta = np_type_ann.get(p).unwrap()
                if ta != -1 {
                    let tup_name = resolve_tuple_ann(ta)
                    set_var_struct(pname, tup_name)
                }
            }
            i = i + 1
        }
    }

    emit_line("{c_type_str(ret_type)} {c_fn_name(mangled)}({params_c}) \{")
    cg_indent = cg_indent + 1
    emit_fn_body(np_body.get(fn_node).unwrap(), ret_type)
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")
    pop_scope()
}

pub fn emit_all_mono_fns() ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let mut i = 0
    while i < mono_fns.len() {
        let mf = mono_fns.get(i).unwrap()
        let fn_node = get_generic_fn_node(mf.base)
        if fn_node != -1 {
            emit_mono_fn_def(fn_node, mf.args)
        }
        i = i + 1
    }
}

pub fn emit_mono_typedefs_from(start: Int) ! Codegen.Emit {
    let mut i = start
    while i < mono_instances.len() {
        let mi = mono_instances.get(i).unwrap()
        let td = find_type_def(mi.base)
        if td != -1 {
            let flds_sl = np_fields.get(td).unwrap()
            if flds_sl != -1 && sublist_length(flds_sl) > 0 {
                if np_kind.get(sublist_get(flds_sl, 0)).unwrap() != NodeKind.TypeVariant {
                    emit_mono_struct_typedef(mi.base, mi.args)
                }
            }
        }
        i = i + 1
    }
}

pub fn emit_mono_fns_from(start: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let mut i = start
    while i < mono_fns.len() {
        let mf = mono_fns.get(i).unwrap()
        let fn_node = get_generic_fn_node(mf.base)
        if fn_node != -1 {
            emit_mono_fn_def(fn_node, mf.args)
        }
        i = i + 1
    }
}

pub fn emit_struct_typedef(td_node: Int) ! Codegen.Emit {
    let name = np_name.get(td_node).unwrap()
    let flds_sl = np_fields.get(td_node).unwrap()
    if flds_sl == -1 {
        return
    }
    // Check if this is a variant-only type (enum), skip for now
    if sublist_length(flds_sl) > 0 {
        let first = sublist_get(flds_sl, 0)
        if np_kind.get(first).unwrap() == NodeKind.TypeVariant {
            return
        }
    }
    // Skip generic types — they get monomorphized instances instead
    let tparams_sl = np_type_params.get(td_node).unwrap()
    if tparams_sl != -1 && sublist_length(tparams_sl) > 0 {
        return
    }
    emit_line("typedef struct \{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f).unwrap()
        let type_ann_node = np_value.get(f).unwrap()
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node).unwrap()
            if type_name == "Fn" {
                emit_line("pact_closure* {fname};")
                sf_entries.push(StructFieldEntry { struct_name: name, field_name: fname, field_type: CT_CLOSURE, stype: "" })
                let sig = build_closure_sig_from_type_ann(type_ann_node)
                sf_closure_sigs.push(StructFieldClosureSig { struct_name: name, field_name: fname, sig: sig })
            } else if type_name == name {
                emit_line("int64_t {fname};")
                sf_entries.push(StructFieldEntry { struct_name: name, field_name: fname, field_type: CT_INT, stype: "" })
            } else if is_struct_type(type_name) != 0 {
                emit_line("{c_type_c_name(type_name)} {fname};")
                sf_entries.push(StructFieldEntry { struct_name: name, field_name: fname, field_type: CT_VOID, stype: type_name })
            } else {
                let ct = type_from_name(type_name)
                emit_line("{c_type_str(ct)} {fname};")
                sf_entries.push(StructFieldEntry { struct_name: name, field_name: fname, field_type: ct, stype: "" })
                // Track list element type for List[SomeStruct] fields
                if type_name == "List" {
                    let elem_sl = np_elements.get(type_ann_node).unwrap()
                    if elem_sl != -1 && sublist_length(elem_sl) > 0 {
                        let elem_ann = sublist_get(elem_sl, 0)
                        let elem_name = np_name.get(elem_ann).unwrap()
                        if is_struct_type(elem_name) != 0 {
                            sf_list_elems.push(StructFieldListElem { struct_name: name, field_name: fname, elem_struct: elem_name, elem_type: CT_VOID })
                        } else {
                            let ect = type_from_name(elem_name)
                            sf_list_elems.push(StructFieldListElem { struct_name: name, field_name: fname, elem_struct: "", elem_type: ect })
                        }
                    }
                }
            }
        } else {
            emit_line("int64_t {fname};")
            sf_entries.push(StructFieldEntry { struct_name: name, field_name: fname, field_type: CT_INT, stype: "" })
        }
        let default_node = np_condition.get(f).unwrap()
        if default_node != -1 {
            struct_field_defaults.push(StructFieldDefault { struct_name: name, field_name: fname, default_node: default_node })
        }
        i = i + 1
    }
    cg_indent = cg_indent - 1
    emit_line("} {c_type_c_name(name)};")
    emit_line("")
}

pub fn emit_enum_typedef(td_node: Int) ! Codegen.Emit {
    let name = np_name.get(td_node).unwrap()
    let flds_sl = np_fields.get(td_node).unwrap()
    if flds_sl == -1 {
        return
    }
    let enum_idx = enum_regs.len()

    let mut has_data = 0
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let v = sublist_get(flds_sl, i)
        let vflds = np_fields.get(v).unwrap()
        if vflds != -1 && sublist_length(vflds) > 0 {
            has_data = 1
        }
        i = i + 1
    }
    enum_regs.push(EnumReg { name: name, has_data: has_data })
    enum_reg_set.set(name, 1)

    i = 0
    while i < sublist_length(flds_sl) {
        let v = sublist_get(flds_sl, i)
        let vname = np_name.get(v).unwrap()
        let vflds = np_fields.get(v).unwrap()
        if vflds != -1 && sublist_length(vflds) > 0 {
            let mut field_names = ""
            let mut field_types = ""
            let mut fi = 0
            while fi < sublist_length(vflds) {
                let vf = sublist_get(vflds, fi)
                let vf_name = np_name.get(vf).unwrap()
                let vf_type_ann = np_value.get(vf).unwrap()
                let mut vf_type_name = "Int"
                if vf_type_ann != -1 {
                    vf_type_name = np_name.get(vf_type_ann).unwrap()
                }
                if fi > 0 {
                    field_names = field_names.concat(",")
                    field_types = field_types.concat(",")
                }
                field_names = field_names.concat(vf_name)
                field_types = field_types.concat(vf_type_name)
                fi = fi + 1
            }
            enum_variants.push(EnumVariant { name: vname, enum_idx: enum_idx, field_names: field_names, field_types: field_types, field_count: sublist_length(vflds) })
        } else {
            enum_variants.push(EnumVariant { name: vname, enum_idx: enum_idx, field_names: "", field_types: "", field_count: 0 })
        }
        i = i + 1
    }

    if has_data == 0 {
        let mut variants_str = ""
        i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v).unwrap()
            if i > 0 {
                variants_str = variants_str.concat(", ")
            }
            variants_str = variants_str.concat("{c_type_c_name(name)}_{vname}")
            i = i + 1
        }
        emit_line("typedef enum \{ {variants_str} } {c_type_c_name(name)};")
        emit_line("")
    } else {
        emit_line("typedef struct \{")
        cg_indent = cg_indent + 1
        emit_line("int tag;")
        emit_line("union \{")
        cg_indent = cg_indent + 1
        i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v).unwrap()
            let vflds = np_fields.get(v).unwrap()
            if vflds != -1 && sublist_length(vflds) > 0 {
                emit_line("struct \{")
                cg_indent = cg_indent + 1
                let mut fi = 0
                while fi < sublist_length(vflds) {
                    let vf = sublist_get(vflds, fi)
                    let vf_name = np_name.get(vf).unwrap()
                    let vf_type_ann = np_value.get(vf).unwrap()
                    let mut vf_c_type = "int64_t"
                    if vf_type_ann != -1 {
                        let vf_type_name = np_name.get(vf_type_ann).unwrap()
                        if is_struct_type(vf_type_name) != 0 {
                            vf_c_type = "{c_type_c_name(vf_type_name)}"
                        } else if is_enum_type(vf_type_name) != 0 {
                            if is_data_enum(vf_type_name) != 0 {
                                vf_c_type = "{c_type_c_name(vf_type_name)}"
                            } else {
                                vf_c_type = "{c_type_c_name(vf_type_name)}"
                            }
                        } else {
                            vf_c_type = c_type_str(type_from_name(vf_type_name))
                        }
                    }
                    emit_line("{vf_c_type} {vf_name};")
                    fi = fi + 1
                }
                cg_indent = cg_indent - 1
                emit_line("} {vname};")
            }
            i = i + 1
        }
        cg_indent = cg_indent - 1
        emit_line("} data;")
        cg_indent = cg_indent - 1
        emit_line("} {c_type_c_name(name)};")
        emit_line("")
        i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v).unwrap()
            emit_line("#define {c_type_c_name(name)}_{vname}_TAG {i}")
            i = i + 1
        }
        emit_line("")
    }
}

// ── Top-level: generate ─────────────────────────────────────────────

pub fn emit_top_level_let(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let saved_lines = cg_lines
    cg_lines = []
    emit_expr(np_value.get(node).unwrap())
    let val_str = expr_result_str
    let val_type = expr_result_type
    let helper_lines = cg_lines
    cg_lines = saved_lines
    let name = np_name.get(node).unwrap()
    let is_mut = np_is_mut.get(node).unwrap()
    set_var(name, val_type, is_mut)
    // Track list element type from annotation
    let type_ann = np_target.get(node).unwrap()
    if val_type == CT_LIST && type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if ann_name == "List" {
            let elems_sl = np_elements.get(type_ann).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                let elem_ann = sublist_get(elems_sl, 0)
                let elem_name = np_name.get(elem_ann).unwrap()
                let elem_ct = type_from_name(elem_name)
                set_list_elem_type(name, elem_ct)
                if elem_ct == CT_VOID && is_struct_type(elem_name) != 0 {
                    set_list_elem_struct(name, elem_name)
                }
                if elem_ct == CT_LIST {
                    let nested_sl = np_elements.get(elem_ann).unwrap()
                    if nested_sl != -1 && sublist_length(nested_sl) > 0 {
                        let nested_ann = sublist_get(nested_sl, 0)
                        let nested_name = np_name.get(nested_ann).unwrap()
                        set_list_nested_elem_type(name, type_from_name(nested_name))
                    }
                }
            }
        }
    }
    if val_type == CT_MAP && type_ann != -1 {
        let ann_name = np_name.get(type_ann).unwrap()
        if ann_name == "Map" {
            let elems_sl = np_elements.get(type_ann).unwrap()
            if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
                let key_ann = sublist_get(elems_sl, 0)
                let val_ann = sublist_get(elems_sl, 1)
                let key_ct = type_from_name(np_name.get(key_ann).unwrap())
                let val_ct = type_from_name(np_name.get(val_ann).unwrap())
                set_map_types(name, key_ct, val_ct)
            }
        }
    }
    if val_type == CT_LIST && expr_list_elem_type >= 0 {
        set_list_elem_type(name, expr_list_elem_type)
        expr_list_elem_type = -1
        let src_struct = get_list_elem_struct(val_str)
        if src_struct != "" {
            set_list_elem_struct(name, src_struct)
        }
        let src_nested = get_list_nested_elem_type(val_str)
        if src_nested != -1 {
            set_list_nested_elem_type(name, src_nested)
        }
    }
    let ts = c_type_str(val_type)
    let cname = c_safe_name(name)
    let needs_init = helper_lines.len() > 0 || val_type == CT_LIST || val_type == CT_MAP
    if needs_init {
        emit_line("static {ts} {cname};")
        let mut hi = 0
        while hi < helper_lines.len() {
            cg_global_inits.push(helper_lines.get(hi).unwrap())
            hi = hi + 1
        }
        cg_global_inits.push("    ".concat(cname).concat(" = ").concat(val_str).concat(";"))
    } else if is_mut != 0 {
        emit_line("static ".concat(ts).concat(" ").concat(cname).concat(" = ").concat(val_str).concat(";"))
    } else {
        let qualifier = if val_type == CT_STRING { "static " } else { "static const " }
        emit_line(qualifier.concat(ts).concat(" ").concat(cname).concat(" = ").concat(val_str).concat(";"))
    }
}
