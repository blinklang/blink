import tokens
import ast
import parser
import codegen_types
import codegen_expr
import codegen_stmt

// codegen.pact — Code generation orchestrator
//
// Imports codegen_types (state, registries, helpers),
// codegen_expr (expression/closure emission), and
// codegen_stmt (statement/function/type emission).
// This file contains only generate() — the top-level entry point.

// ── Top-level: generate ─────────────────────────────────────────────

pub fn generate(program: Int) -> Str {
    cg_program_node = program
    // Reset state
    cg_lines = []
    cg_indent = 0
    cg_temp_counter = 0
    scope_vars = []
    scope_frame_starts = []
    fn_regs = []
    fn_ret_structs = []
    fn_ret_types = []
    effect_entries = []
    cg_current_fn_name = ""
    cg_current_fn_ret = 0
    cg_global_inits = []
    var_list_elems = []
    var_list_elem_frame_starts = []
    struct_reg_names = []
    enum_regs = []
    enum_variants = []
    var_enums = []
    fn_enum_rets = []
    emitted_let_names = []
    emitted_fn_names = []
    trait_entries = []
    impl_entries = []
    from_entries = []
    tryfrom_entries = []
    var_structs = []
    var_struct_frame_starts = []
    sf_entries = []
    mono_instances = []
    cg_closure_defs = []
    cg_closure_counter = 0
    var_closures = []
    var_closure_frame_starts = []
    generic_fns = []
    mono_fns = []
    var_options = []
    var_option_frame_starts = []
    var_results = []
    var_result_frame_starts = []
    emitted_option_types = []
    emitted_result_types = []
    emitted_iter_types = []
    emitted_range_iter = 0
    emitted_str_iter = 0
    emitted_map_iters = []
    emitted_filter_iters = []
    emitted_take_iters = []
    emitted_skip_iters = []
    emitted_chain_iters = []
    emitted_flat_map_iters = []
    var_iterators = []
    var_iterator_frame_starts = []
    var_aliases = []
    var_alias_frame_starts = []
    var_handles = []
    var_handle_frame_starts = []
    var_channels = []
    var_channel_frame_starts = []
    cg_let_target_type = 0
    cg_let_target_name = ""
    cg_handler_vtable_field = ""
    cg_handler_is_user_effect = 0
    cg_in_handler_body = 0
    cg_handler_body_vtable_type = ""
    cg_handler_body_field = ""
    cg_handler_body_is_ue = 0
    cg_handler_body_idx = 0
    cg_uses_async = 0
    cg_async_wrapper_counter = 0
    cg_async_scope_stack = []
    cg_async_scope_counter = 0
    cap_budget_names = []
    cap_budget_active = 0
    ue_effects = []
    ue_methods = []

    push_scope()

    // Register builtins
    reg_fn("arg_count", CT_INT)
    reg_fn("get_arg", CT_STRING)
    reg_fn("read_file", CT_STRING)
    reg_fn("write_file", CT_VOID)
    reg_fn("file_exists", CT_INT)
    reg_fn("path_join", CT_STRING)
    reg_fn("path_dirname", CT_STRING)
    reg_fn("shell_exec", CT_INT)
    reg_fn("exit", CT_VOID)
    reg_fn("path_basename", CT_STRING)
    reg_fn("is_dir", CT_INT)

    // Register built-in structs
    struct_reg_names.push("ConversionError")
    sf_entries.push(StructFieldEntry { struct_name: "ConversionError", field_name: "message", field_type: CT_STRING, stype: "" })
    sf_entries.push(StructFieldEntry { struct_name: "ConversionError", field_name: "source_type", field_type: CT_STRING, stype: "" })
    sf_entries.push(StructFieldEntry { struct_name: "ConversionError", field_name: "target_type", field_type: CT_STRING, stype: "" })

    init_builtin_effects()

    trait_entries.push(TraitEntry { name: "Iterator", method_sl: -1 })
    trait_entries.push(TraitEntry { name: "IntoIterator", method_sl: -1 })

    // Register user-defined effect declarations
    let effects_decl_sl = np_args.get(program)
    if effects_decl_sl != -1 {
        let mut ei = 0
        while ei < sublist_length(effects_decl_sl) {
            let ed = sublist_get(effects_decl_sl, ei)
            let eff_name = np_name.get(ed)
            let parent_idx = reg_effect(eff_name, -1)
            let mut handle = ""
            let mut hi = 0
            while hi < eff_name.len() {
                let ch = eff_name.char_at(hi)
                if ch == 65 { handle = handle.concat("a") }
                else if ch == 66 { handle = handle.concat("b") }
                else if ch == 67 { handle = handle.concat("c") }
                else if ch == 68 { handle = handle.concat("d") }
                else if ch == 69 { handle = handle.concat("e") }
                else if ch == 70 { handle = handle.concat("f") }
                else if ch == 71 { handle = handle.concat("g") }
                else if ch == 72 { handle = handle.concat("h") }
                else if ch == 73 { handle = handle.concat("i") }
                else if ch == 74 { handle = handle.concat("j") }
                else if ch == 75 { handle = handle.concat("k") }
                else if ch == 76 { handle = handle.concat("l") }
                else if ch == 77 { handle = handle.concat("m") }
                else if ch == 78 { handle = handle.concat("n") }
                else if ch == 79 { handle = handle.concat("o") }
                else if ch == 80 { handle = handle.concat("p") }
                else if ch == 81 { handle = handle.concat("q") }
                else if ch == 82 { handle = handle.concat("r") }
                else if ch == 83 { handle = handle.concat("s") }
                else if ch == 84 { handle = handle.concat("t") }
                else if ch == 85 { handle = handle.concat("u") }
                else if ch == 86 { handle = handle.concat("v") }
                else if ch == 87 { handle = handle.concat("w") }
                else if ch == 88 { handle = handle.concat("x") }
                else if ch == 89 { handle = handle.concat("y") }
                else if ch == 90 { handle = handle.concat("z") }
                else { handle = handle.concat(eff_name.substring(hi, 1)) }
                hi = hi + 1
            }
            ue_effects.push(UeEffect { name: eff_name, handle: handle })
            let children_sl = np_elements.get(ed)
            if children_sl != -1 {
                let mut ci = 0
                while ci < sublist_length(children_sl) {
                    let child = sublist_get(children_sl, ci)
                    let child_name = np_name.get(child)
                    reg_effect("{eff_name}.{child_name}", parent_idx)
                    let child_ops = np_methods.get(child)
                    if child_ops != -1 {
                        let mut oi = 0
                        while oi < sublist_length(child_ops) {
                            let op = sublist_get(child_ops, oi)
                            let op_name = np_name.get(op)
                            let op_ret = np_return_type.get(op)
                            let mut op_c_ret = "void"
                            if op_ret == "Int" {
                                op_c_ret = "int64_t"
                            } else if op_ret == "Str" {
                                op_c_ret = "const char*"
                            } else if op_ret == "Float" {
                                op_c_ret = "double"
                            } else if op_ret == "Bool" {
                                op_c_ret = "int"
                            } else if op_ret != "" {
                                op_c_ret = "int64_t"
                            }
                            let op_params_sl = np_params.get(op)
                            let mut op_c_params = ""
                            if op_params_sl != -1 {
                                let mut pi = 0
                                while pi < sublist_length(op_params_sl) {
                                    if pi > 0 {
                                        op_c_params = op_c_params.concat(", ")
                                    }
                                    let p = sublist_get(op_params_sl, pi)
                                    let ptype = np_type_name.get(p)
                                    let pname = np_name.get(p)
                                    let mut pc = "int64_t"
                                    if ptype == "Str" {
                                        pc = "const char*"
                                    } else if ptype == "Float" {
                                        pc = "double"
                                    } else if ptype == "Bool" {
                                        pc = "int"
                                    } else if ptype == "Int" {
                                        pc = "int64_t"
                                    }
                                    op_c_params = op_c_params.concat("{pc} {pname}")
                                    pi = pi + 1
                                }
                            }
                            if op_c_params == "" {
                                op_c_params = "void"
                            }
                            ue_methods.push(UeMethod { name: op_name, params: op_c_params, ret: op_c_ret, effect_handle: handle })
                            oi = oi + 1
                        }
                    }
                    ci = ci + 1
                }
            }
            ei = ei + 1
        }
    }

    // Process top-level annotations (e.g. @capabilities)
    let anns_sl = np_handlers.get(program)
    if anns_sl != -1 {
        let mut ai = 0
        while ai < sublist_length(anns_sl) {
            let ann = sublist_get(anns_sl, ai)
            let ann_name = np_name.get(ann)
            if ann_name == "capabilities" {
                cap_budget_active = 1
                let ann_args_sl = np_args.get(ann)
                if ann_args_sl != -1 {
                    let mut aj = 0
                    while aj < sublist_length(ann_args_sl) {
                        let arg_nd = sublist_get(ann_args_sl, aj)
                        cap_budget_names.push(np_name.get(arg_nd))
                        aj = aj + 1
                    }
                }
            }
            ai = ai + 1
        }
    }

    // Preamble: include runtime
    cg_lines.push("#include \"runtime.h\"")
    cg_lines.push("")
    cg_lines.push("static pact_ctx __pact_ctx;")
    cg_lines.push("")

    // Emit user-defined effect vtable structs and globals
    let mut uei = 0
    while uei < ue_effects.len() {
        let ue = ue_effects.get(uei)
        let vt_type = "pact_ue_{ue.handle}_vtable"
        cg_lines.push("typedef struct \{")
        let mut mi = 0
        while mi < ue_methods.len() {
            let uem = ue_methods.get(mi)
            if uem.effect_handle == ue.handle {
                cg_lines.push("    {uem.ret} (*{uem.name})({uem.params});")
            }
            mi = mi + 1
        }
        cg_lines.push("} {vt_type};")
        cg_lines.push("")
        mi = 0
        while mi < ue_methods.len() {
            let uem = ue_methods.get(mi)
            if uem.effect_handle == ue.handle {
                let dfn = "pact_ue_{ue.handle}_default_{uem.name}"
                if uem.ret == "void" {
                    cg_lines.push("static void {dfn}({uem.params}) \{")
                    cg_lines.push("    fprintf(stderr, \"pact: {ue.handle}.{uem.name} not implemented\\n\");")
                    cg_lines.push("}")
                } else if uem.ret == "const char*" {
                    cg_lines.push("static const char* {dfn}({uem.params}) \{")
                    cg_lines.push("    fprintf(stderr, \"pact: {ue.handle}.{uem.name} not implemented\\n\");")
                    cg_lines.push("    return NULL;")
                    cg_lines.push("}")
                } else {
                    cg_lines.push("static {uem.ret} {dfn}({uem.params}) \{")
                    cg_lines.push("    fprintf(stderr, \"pact: {ue.handle}.{uem.name} not implemented\\n\");")
                    cg_lines.push("    return 0;")
                    cg_lines.push("}")
                }
                cg_lines.push("")
            }
            mi = mi + 1
        }
        cg_lines.push("static {vt_type} {vt_type}_default = \{")
        mi = 0
        let mut first_m = 1
        while mi < ue_methods.len() {
            let uem = ue_methods.get(mi)
            if uem.effect_handle == ue.handle {
                if first_m == 0 {
                    cg_lines.push(",")
                }
                cg_lines.push("    pact_ue_{ue.handle}_default_{uem.name}")
                first_m = 0
            }
            mi = mi + 1
        }
        cg_lines.push("};")
        cg_lines.push("")
        cg_lines.push("static {vt_type}* __pact_ue_{ue.handle} = &{vt_type}_default;")
        cg_lines.push("")
        uei = uei + 1
    }

    // Register type names first (struct or enum)
    let types_sl = np_fields.get(program)
    if types_sl != -1 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let td = sublist_get(types_sl, i)
            let td_flds = np_fields.get(td)
            let mut is_enum = 0
            if td_flds != -1 && sublist_length(td_flds) > 0 {
                if np_kind.get(sublist_get(td_flds, 0)) == NodeKind.TypeVariant {
                    is_enum = 1
                }
            }
            if is_enum == 0 {
                struct_reg_names.push(np_name.get(td))
            }
            i = i + 1
        }
    }

    // Type definitions (structs and enums)
    if types_sl != -1 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let td = sublist_get(types_sl, i)
            let td_flds = np_fields.get(td)
            let mut is_enum = 0
            if td_flds != -1 && sublist_length(td_flds) > 0 {
                if np_kind.get(sublist_get(td_flds, 0)) == NodeKind.TypeVariant {
                    is_enum = 1
                }
            }
            if is_enum != 0 {
                emit_enum_typedef(td)
            } else {
                emit_struct_typedef(td)
            }
            i = i + 1
        }
    }

    // Top-level let bindings (deduplicated)
    let lets_sl = np_stmts.get(program)
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            let let_name = np_name.get(let_node)
            if is_emitted_let(let_name) == 0 {
                emit_top_level_let(let_node)
                emitted_let_names.push(let_name)
            }
            i = i + 1
        }
        emit_line("")
    }

    // Register all functions first (deduplicated)
    let fns_sl = np_params.get(program)
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fn_name = np_name.get(fn_node)
            // Track generic functions separately
            let fn_tparams = np_type_params.get(fn_node)
            if fn_tparams != -1 && sublist_length(fn_tparams) > 0 {
                generic_fns.push(GenericFnEntry { name: fn_name, node: fn_node })
            } else if is_emitted_fn(fn_name) == 0 {
                let ret_str = np_return_type.get(fn_node)
                let fn_eff_sl = np_effects.get(fn_node)
                if is_enum_type(ret_str) != 0 {
                    fn_enum_rets.push(FnEnumRetEntry { name: fn_name, enum_type: ret_str })
                    reg_fn_with_effects(fn_name, CT_INT, fn_eff_sl)
                } else {
                    reg_fn_with_effects(fn_name, type_from_name(ret_str), fn_eff_sl)
                    if is_struct_type(ret_str) != 0 {
                        reg_fn_struct_ret(fn_name, ret_str)
                    }
                }
                reg_fn_ret_from_ann(fn_name, fn_node)
                check_capabilities_budget(fn_name, fn_eff_sl)
                emitted_fn_names.push(fn_name)
            }
            i = i + 1
        }
    }

    // Register traits
    let traits_sl = np_arms.get(program)
    if traits_sl != -1 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            let tr = sublist_get(traits_sl, i)
            trait_entries.push(TraitEntry { name: np_name.get(tr), method_sl: np_methods.get(tr) })
            i = i + 1
        }
    }

    // Register impls and their methods
    let impls_sl = np_methods.get(program)
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_trait = np_trait_name.get(im)
            let impl_type = np_name.get(im)
            impl_entries.push(ImplEntry { trait_name: impl_trait, type_name: impl_type, methods_sl: np_methods.get(im) })
            if impl_trait == "From" {
                let trait_tparams = np_type_params.get(im)
                if trait_tparams != -1 && sublist_length(trait_tparams) > 0 {
                    let src_node = sublist_get(trait_tparams, 0)
                    let src_type = np_name.get(src_node)
                    from_entries.push(FromImplEntry { source: src_type, target: impl_type, method_sl: np_methods.get(im) })
                }
            }
            if impl_trait == "TryFrom" {
                let trait_tparams = np_type_params.get(im)
                if trait_tparams != -1 && sublist_length(trait_tparams) > 0 {
                    let src_node = sublist_get(trait_tparams, 0)
                    let src_type = np_name.get(src_node)
                    tryfrom_entries.push(TryFromImplEntry { source: src_type, target: impl_type, method_sl: np_methods.get(im) })
                }
            }
            let methods_sl = np_methods.get(im)
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    let mname = np_name.get(m)
                    let mangled = "{impl_type}_{mname}"
                    let ret_str_raw = np_return_type.get(m)
                    let ret_str = resolve_self_type(ret_str_raw, impl_type)
                    if is_enum_type(ret_str) != 0 {
                        fn_enum_rets.push(FnEnumRetEntry { name: mangled, enum_type: ret_str })
                        reg_fn(mangled, CT_INT)
                    } else if is_struct_type(ret_str) != 0 {
                        reg_fn(mangled, CT_VOID)
                        reg_fn_struct_ret(mangled, ret_str)
                    } else {
                        reg_fn(mangled, type_from_name(ret_str))
                    }
                    reg_fn_ret_from_ann(mangled, m)
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    // Auto-derive Into from From
    let mut into_i = 0
    while into_i < from_entries.len() {
        let fe = from_entries.get(into_i)
        impl_entries.push(ImplEntry { trait_name: "Into", type_name: fe.source, methods_sl: fe.method_sl })
        into_i = into_i + 1
    }

    emit_all_option_result_types()
    let early_option_count = emitted_option_types.len()
    let early_result_count = emitted_result_types.len()

    // Forward declarations (deduplicated, skip generics)
    emitted_fn_names = []
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fn_name = np_name.get(fn_node)
            if is_emitted_fn(fn_name) == 0 && is_generic_fn(fn_name) == 0 {
                emit_fn_decl(fn_node)
                emitted_fn_names.push(fn_name)
            }
            i = i + 1
        }
    }

    // Impl method forward declarations
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_type = np_name.get(im)
            let methods_sl = np_methods.get(im)
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    let mname = np_name.get(m)
                    let mangled = "{impl_type}_{mname}"
                    let params = format_impl_params(m, impl_type)
                    let enum_ret = get_fn_enum_ret(mangled)
                    if enum_ret != "" {
                        emit_line("pact_{enum_ret} pact_{mangled}({params});")
                    } else {
                        let ret_str_raw = np_return_type.get(m)
                        let ret_str = resolve_self_type(ret_str_raw, impl_type)
                        if is_struct_type(ret_str) != 0 {
                            emit_line("pact_{ret_str} pact_{mangled}({params});")
                        } else {
                            let resolved = resolve_ret_type_from_ann(m)
                            if resolved != "" {
                                emit_line("{resolved} pact_{mangled}({params});")
                            } else {
                                let ret_type = type_from_name(ret_str)
                                emit_line("{c_type_str(ret_type)} pact_{mangled}({params});")
                            }
                        }
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
    }
    emit_line("")

    // Function definitions (deduplicated) — emit into temp buffer
    // so we can prepend closure defs discovered during emission
    let pre_fn_lines = cg_lines
    cg_lines = []
    emitted_fn_names = []
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fn_name = np_name.get(fn_node)
            if is_emitted_fn(fn_name) == 0 && is_generic_fn(fn_name) == 0 {
                emit_fn_def(fn_node)
                emit_line("")
                emitted_fn_names.push(fn_name)
            }
            i = i + 1
        }
    }

    // Impl method definitions
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_type = np_name.get(im)
            let methods_sl = np_methods.get(im)
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    emit_impl_method_def(m, impl_type)
                    emit_line("")
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    let fn_def_lines = cg_lines
    cg_lines = pre_fn_lines

    // Emit monomorphized type definitions discovered during function emission
    emit_all_mono_typedefs()

    // Emit Option/Result type definitions discovered during codegen (skip early ones)
    emit_option_result_types_from(early_option_count, early_result_count)

    // Emit iterator type definitions discovered during codegen
    emit_all_iter_types()

    // Emit monomorphized function definitions
    emit_all_mono_fns()

    // Emit closure definitions (lifted from function bodies) before fn defs
    if cg_closure_defs.len() > 0 {
        let mut ci = 0
        while ci < cg_closure_defs.len() {
            cg_lines.push(cg_closure_defs.get(ci))
            ci = ci + 1
        }
    }

    // Thread pool global (emitted before function definitions so fns can reference it)
    if cg_uses_async != 0 {
        emit_line("static pact_threadpool* __pact_pool;")
        emit_line("")
    }

    // Now append the function definitions
    let mut fi = 0
    while fi < fn_def_lines.len() {
        cg_lines.push(fn_def_lines.get(fi))
        fi = fi + 1
    }

    // Emit test functions into temp buffer so we can prepend closure defs
    let tests_sl = np_captures.get(program)
    let mut test_names: List[Str] = []
    let mut test_c_names: List[Str] = []
    let mut test_all_tags: List[Str] = []
    let mut test_tag_offsets: List[Int] = []
    let mut test_tag_counts: List[Int] = []
    let pre_test_lines = cg_lines
    let pre_test_closure_count = cg_closure_defs.len()
    let pre_test_mono_td_count = mono_instances.len()
    let pre_test_mono_fn_count = mono_fns.len()
    let pre_test_option_count = emitted_option_types.len()
    let pre_test_result_count = emitted_result_types.len()
    let pre_test_iter_count = emitted_iter_types.len()
    let pre_test_map_iter_count = emitted_map_iters.len()
    let pre_test_filter_iter_count = emitted_filter_iters.len()
    let pre_test_take_iter_count = emitted_take_iters.len()
    let pre_test_skip_iter_count = emitted_skip_iters.len()
    let pre_test_chain_iter_count = emitted_chain_iters.len()
    let pre_test_flat_map_iter_count = emitted_flat_map_iters.len()
    cg_lines = []
    if tests_sl != -1 {
        let mut ti = 0
        while ti < sublist_length(tests_sl) {
            let tb = sublist_get(tests_sl, ti)
            let tname = np_name.get(tb)
            let tbody = np_body.get(tb)
            let mut sanitized = ""
            let mut si = 0
            while si < tname.len() {
                let ch = tname.char_at(si)
                if ch == 32 {
                    sanitized = sanitized.concat("_")
                } else if ch >= 48 && ch <= 57 {
                    sanitized = sanitized.concat(tname.substring(si, 1))
                } else if ch >= 65 && ch <= 90 {
                    sanitized = sanitized.concat(tname.substring(si, 1))
                } else if ch >= 97 && ch <= 122 {
                    sanitized = sanitized.concat(tname.substring(si, 1))
                } else if ch == 95 {
                    sanitized = sanitized.concat("_")
                }
                si = si + 1
            }
            let c_name = "pact_test_{sanitized}"
            test_names.push(tname)
            test_c_names.push(c_name)
            let tag_offset = test_all_tags.len()
            let tb_anns = np_handlers.get(tb)
            if tb_anns != -1 {
                let mut tai = 0
                while tai < sublist_length(tb_anns) {
                    let ann = sublist_get(tb_anns, tai)
                    if np_name.get(ann) == "tags" {
                        let tag_args_sl = np_args.get(ann)
                        if tag_args_sl != -1 {
                            let mut tgi = 0
                            while tgi < sublist_length(tag_args_sl) {
                                let tag_nd = sublist_get(tag_args_sl, tgi)
                                test_all_tags.push(np_name.get(tag_nd))
                                tgi = tgi + 1
                            }
                        }
                    }
                    tai = tai + 1
                }
            }
            test_tag_offsets.push(tag_offset)
            test_tag_counts.push(test_all_tags.len() - tag_offset)
            push_scope()
            cg_current_fn_name = "__test_{sanitized}"
            cg_current_fn_ret = CT_VOID
            mut_captured_vars = []
            prescan_mut_captures(tbody)
            emit_line("static void {c_name}(void) \{")
            cg_indent = cg_indent + 1
            emit_block(tbody)
            cg_indent = cg_indent - 1
            emit_line("}")
            emit_line("")
            pop_scope()
            ti = ti + 1
        }
    }
    let test_fn_lines = cg_lines
    cg_lines = pre_test_lines

    // Flush type defs discovered during test block emission
    emit_mono_typedefs_from(pre_test_mono_td_count)
    emit_option_result_types_from(pre_test_option_count, pre_test_result_count)
    emit_iter_types_from(pre_test_iter_count, pre_test_map_iter_count, pre_test_filter_iter_count, pre_test_take_iter_count, pre_test_skip_iter_count, pre_test_chain_iter_count, pre_test_flat_map_iter_count)
    emit_mono_fns_from(pre_test_mono_fn_count)

    // Flush closure defs discovered during test block emission
    if cg_closure_defs.len() > pre_test_closure_count {
        let mut tci = pre_test_closure_count
        while tci < cg_closure_defs.len() {
            cg_lines.push(cg_closure_defs.get(tci))
            tci = tci + 1
        }
    }

    // Now append the test function definitions
    let mut tfi = 0
    while tfi < test_fn_lines.len() {
        cg_lines.push(test_fn_lines.get(tfi))
        tfi = tfi + 1
    }

    // Emit test registry and runner
    let test_count = test_names.len()
    if test_count > 0 {
        let mut tti = 0
        while tti < test_count {
            let tag_count = test_tag_counts.get(tti)
            if tag_count > 0 {
                let tcn = test_c_names.get(tti)
                let mut tag_arr = "static const char* {tcn}_tags[] = \{"
                let mut tgi = 0
                while tgi < tag_count {
                    if tgi > 0 {
                        tag_arr = tag_arr.concat(", ")
                    }
                    let tag_val = test_all_tags.get(test_tag_offsets.get(tti) + tgi)
                    tag_arr = tag_arr.concat("\"{tag_val}\"")
                    tgi = tgi + 1
                }
                tag_arr = tag_arr.concat("};")
                emit_line(tag_arr)
            }
            tti = tti + 1
        }
        emit_line("static const pact_test_entry __pact_tests[] = \{")
        cg_indent = cg_indent + 1
        let mut tri = 0
        while tri < test_count {
            let tn = test_names.get(tri)
            let tcn = test_c_names.get(tri)
            let comma = if tri < test_count - 1 { "," } else { "" }
            let tc = test_tag_counts.get(tri)
            if tc > 0 {
                emit_line("\{\"{tn}\", {tcn}, __FILE__, 0, 0, {tcn}_tags, {tc}}{comma}")
            } else {
                emit_line("\{\"{tn}\", {tcn}, __FILE__, 0, 0, NULL, 0}{comma}")
            }
            tri = tri + 1
        }
        cg_indent = cg_indent - 1
        emit_line("};")
        emit_line("")
        emit_line("static void __pact_run_tests(int argc, const char** argv) \{")
        cg_indent = cg_indent + 1
        emit_line("pact_test_run(__pact_tests, {test_count}, argc, argv);")
        cg_indent = cg_indent - 1
        emit_line("}")
        emit_line("")
    }

    // Global init function (if needed)
    if cg_global_inits.len() > 0 {
        emit_line("static void __pact_init_globals(void) \{")
        let mut gi = 0
        while gi < cg_global_inits.len() {
            cg_lines.push(cg_global_inits.get(gi))
            gi = gi + 1
        }
        emit_line("}")
        emit_line("")
    }

    // C main wrapper
    emit_line("int main(int argc, char** argv) \{")
    cg_indent = cg_indent + 1
    emit_line("pact_g_argc = argc;")
    emit_line("pact_g_argv = (const char**)argv;")
    emit_line("__pact_ctx = pact_ctx_default();")
    if cg_uses_async != 0 {
        emit_line("__pact_pool = pact_threadpool_init(4);")
    }
    if cg_global_inits.len() > 0 {
        emit_line("__pact_init_globals();")
    }
    let has_main = is_emitted_fn("main")
    if test_count > 0 && has_main != 0 {
        emit_line("for (int i = 1; i < argc; i++) \{")
        cg_indent = cg_indent + 1
        emit_line("if (strcmp(argv[i], \"--test\") == 0) \{")
        cg_indent = cg_indent + 1
        emit_line("__pact_run_tests(argc, (const char**)argv);")
        if cg_uses_async != 0 {
            emit_line("pact_threadpool_shutdown(__pact_pool);")
        }
        emit_line("return 0;")
        cg_indent = cg_indent - 1
        emit_line("}")
        cg_indent = cg_indent - 1
        emit_line("}")
    }
    if test_count > 0 && has_main == 0 {
        emit_line("__pact_run_tests(argc, (const char**)argv);")
    } else {
        emit_line("pact_main();")
    }
    if cg_uses_async != 0 {
        emit_line("pact_threadpool_shutdown(__pact_pool);")
    }
    emit_line("return 0;")
    cg_indent = cg_indent - 1
    emit_line("}")

    pop_scope()

    join_lines()
}
