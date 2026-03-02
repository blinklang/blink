import ast
import parser
import diagnostics

effect TypeCheck {
    effect Register
    effect Resolve
    effect Report
}

// typecheck.pact — Type representation, registries, and type checking
//
// Phase 0: Type registries — registers struct/enum/fn/trait types into pools
// Phase 1: Name resolution — walks function bodies checking identifiers resolve
// Phase 2: Expression type inference — infers types, checks compatibility
//
// The pipeline: lex → parse → typecheck → codegen

// ── Type kind constants ─────────────────────────────────────────────
pub let TK_INT = 0
pub let TK_FLOAT = 1
pub let TK_BOOL = 2
pub let TK_STR = 3
pub let TK_VOID = 4
pub let TK_LIST = 5
pub let TK_OPTION = 6
pub let TK_RESULT = 7
pub let TK_FN = 8
pub let TK_STRUCT = 9
pub let TK_ENUM = 10
pub let TK_TYPEVAR = 11
pub let TK_UNKNOWN = 12
pub let TK_CLOSURE = 13
pub let TK_ITERATOR = 14
pub let TK_HANDLE = 15
pub let TK_CHANNEL = 16
pub let TK_TUPLE = 17
pub let TK_MAP = 18
pub let TK_BYTES = 19

// ── Type pool (parallel arrays) ─────────────────────────────────────
pub let mut ty_kind: List[Int] = []
pub let mut ty_name: List[Str] = []
pub let mut ty_inner1: List[Int] = []
pub let mut ty_inner2: List[Int] = []
pub let mut ty_params_start: List[Int] = []
pub let mut ty_params_count: List[Int] = []

pub let mut ty_param_list: List[Int] = []

// ── Builtin type indices (populated by init_types) ──────────────────
pub let mut TYPE_INT: Int = -1
pub let mut TYPE_FLOAT: Int = -1
pub let mut TYPE_BOOL: Int = -1
pub let mut TYPE_STR: Int = -1
pub let mut TYPE_VOID: Int = -1
pub let mut TYPE_UNKNOWN: Int = -1

// ── Type registries ─────────────────────────────────────────────────
pub let mut named_type_names: List[Str] = []
pub let mut named_type_ids: List[Int] = []

pub let mut sfield_struct_id: List[Int] = []
pub let mut sfield_name: List[Str] = []
pub let mut sfield_type_id: List[Int] = []

pub let mut evar_enum_id: List[Int] = []
pub let mut evar_name: List[Str] = []
pub let mut evar_tag: List[Int] = []
pub let mut evar_has_data: List[Int] = []

pub let mut evfield_var_idx: List[Int] = []
pub let mut evfield_name: List[Str] = []
pub let mut evfield_type_id: List[Int] = []

pub let mut named_type_map: Map[Str, Int] = Map()
pub let mut fnsig_map: Map[Str, Int] = Map()

pub let mut fnsig_name: List[Str] = []
pub let mut fnsig_ret: List[Int] = []
pub let mut fnsig_params_start: List[Int] = []
pub let mut fnsig_params_count: List[Int] = []
pub let mut fnsig_param_list: List[Int] = []
pub let mut fnsig_type_params_start: List[Int] = []
pub let mut fnsig_type_params_count: List[Int] = []
pub let mut fnsig_type_param_names: List[Str] = []

pub let mut tc_trait_names: List[Str] = []
pub let mut tc_trait_method_names: List[Str] = []

pub let mut tc_fn_effects: List[Str] = []

pub let mut tc_current_fn_ret: Int = -1
pub let mut tc_current_fn_name: Str = ""

pub let mut tc_errors: List[Str] = []
pub let mut tc_warnings: List[Str] = []

// ── Incremental filter ──────────────────────────────────────────────
// When enabled, only functions whose names appear in the filter set
// are typechecked. Used by the incremental recheck engine.

let mut tc_inc_enabled: Int = 0
let mut tc_inc_filter: Map[Str, Int] = Map()

// ── Type creation ───────────────────────────────────────────────────

pub fn new_type(kind: Int, name: Str) -> Int {
    let idx = ty_kind.len()
    ty_kind.push(kind)
    ty_name.push(name)
    ty_inner1.push(-1)
    ty_inner2.push(-1)
    ty_params_start.push(-1)
    ty_params_count.push(0)
    idx
}

pub fn make_list_type(inner: Int) -> Int {
    let t = new_type(TK_LIST, "List")
    ty_inner1.set(t, inner)
    t
}

pub fn make_option_type(inner: Int) -> Int {
    let t = new_type(TK_OPTION, "Option")
    ty_inner1.set(t, inner)
    t
}

pub fn make_result_type(ok_type: Int, err_type: Int) -> Int {
    let t = new_type(TK_RESULT, "Result")
    ty_inner1.set(t, ok_type)
    ty_inner2.set(t, err_type)
    t
}

pub fn make_fn_type(ret_type: Int, param_types: List[Int]) -> Int {
    let t = new_type(TK_FN, "Fn")
    ty_inner1.set(t, ret_type)
    let start = ty_param_list.len()
    let mut i = 0
    while i < param_types.len() {
        ty_param_list.push(param_types.get(i).unwrap())
        i = i + 1
    }
    ty_params_start.set(t, start)
    ty_params_count.set(t, param_types.len())
    t
}

pub fn make_typevar(name: Str) -> Int {
    new_type(TK_TYPEVAR, name)
}

pub fn make_tuple_type(elem_types: List[Int]) -> Int {
    let t = new_type(TK_TUPLE, "Tuple")
    let start = ty_param_list.len()
    let mut i = 0
    while i < elem_types.len() {
        ty_param_list.push(elem_types.get(i).unwrap())
        i = i + 1
    }
    ty_params_start.set(t, start)
    ty_params_count.set(t, elem_types.len())
    t
}


pub fn make_map_type(key_type: Int, value_type: Int) -> Int {
    let t = new_type(TK_MAP, "Map")
    ty_inner1.set(t, key_type)
    ty_inner2.set(t, value_type)
    t
}

// ── Type lookup ─────────────────────────────────────────────────────

pub fn lookup_named_type(name: Str) -> Int {
    if named_type_map.has(name) != 0 {
        return named_type_map.get(name)
    }
    -1
}

pub fn resolve_type_name(name: Str) -> Int ! TypeCheck.Resolve {
    if name == "Int" { return TYPE_INT }
    if name == "Float" { return TYPE_FLOAT }
    if name == "Bool" { return TYPE_BOOL }
    if name == "Str" { return TYPE_STR }
    if name == "Void" || name == "" { return TYPE_VOID }
    lookup_named_type(name)
}

pub fn get_struct_field_tid(struct_tid: Int, fname: Str) -> Int {
    let mut i = 0
    while i < sfield_struct_id.len() {
        if sfield_struct_id.get(i).unwrap() == struct_tid && sfield_name.get(i).unwrap() == fname {
            return sfield_type_id.get(i).unwrap()
        }
        i = i + 1
    }
    -1
}

pub fn get_variant_by_name(enum_tid: Int, vname: Str) -> Int {
    let mut i = 0
    while i < evar_enum_id.len() {
        if evar_enum_id.get(i).unwrap() == enum_tid && evar_name.get(i).unwrap() == vname {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn lookup_fnsig(name: Str) -> Int {
    if fnsig_map.has(name) != 0 {
        return fnsig_map.get(name)
    }
    -1
}

pub fn instantiate_return_type(sig: Int, args_sl: Int) -> Int ! TypeCheck.Resolve, TypeCheck.Report, Diag.Report {
    let ret = fnsig_ret.get(sig).unwrap()
    if ret < 0 || ret >= ty_kind.len() { return ret }
    if ty_kind.get(ret).unwrap() != TK_TYPEVAR { return ret }

    let tp_name = ty_name.get(ret).unwrap()
    let tp_start = fnsig_type_params_start.get(sig).unwrap()
    let tp_count = fnsig_type_params_count.get(sig).unwrap()
    let param_start = fnsig_params_start.get(sig).unwrap()
    let param_count = fnsig_params_count.get(sig).unwrap()

    let mut ti = 0
    while ti < tp_count {
        if fnsig_type_param_names.get(tp_start + ti).unwrap() == tp_name {
            let mut pi = 0
            while pi < param_count {
                let ptid = fnsig_param_list.get(param_start + pi).unwrap()
                if ptid >= 0 && ptid < ty_kind.len() && ty_kind.get(ptid).unwrap() == TK_TYPEVAR && ty_name.get(ptid).unwrap() == tp_name {
                    if args_sl != -1 && pi < sublist_length(args_sl) {
                        return infer_type(sublist_get(args_sl, pi))
                    }
                }
                pi = pi + 1
            }
        }
        ti = ti + 1
    }
    ret
}

// ── Error reporting ─────────────────────────────────────────────────

pub fn tc_error(msg: Str) ! TypeCheck.Report, Diag.Report {
    tc_errors.push(msg)
    diag_error_no_loc("TypeError", "E0300", msg, "")
}

pub fn tc_error_at(msg: Str, node_id: Int) ! TypeCheck.Report, Diag.Report {
    tc_errors.push(msg)
    diag_error_at("TypeError", "E0300", msg, node_id, "")
}

pub fn tc_warn(msg: Str) ! TypeCheck.Report {
    tc_warnings.push(msg)
}

// ── Incremental filter API ──────────────────────────────────────────

pub fn tc_set_incremental_filter(names: List[Str]) {
    tc_inc_filter = Map()
    let mut i = 0
    while i < names.len() {
        tc_inc_filter.set(names.get(i).unwrap(), 1)
        i = i + 1
    }
    tc_inc_enabled = 1
}

pub fn tc_clear_incremental_filter() {
    tc_inc_filter = Map()
    tc_inc_enabled = 0
}

fn tc_should_check_fn(name: Str) -> Int {
    if tc_inc_enabled == 0 {
        return 1
    }
    tc_inc_filter.has(name)
}

// ── Type annotation resolution ──────────────────────────────────────

pub fn resolve_type_ann(ann_node: Int) -> Int ! TypeCheck.Resolve {
    if ann_node == -1 {
        return TYPE_UNKNOWN
    }
    let name = np_name.get(ann_node).unwrap()
    let elems_sl = np_elements.get(ann_node).unwrap()

    if name == "List" {
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let inner = resolve_type_ann(sublist_get(elems_sl, 0))
            return make_list_type(inner)
        }
        return make_list_type(TYPE_UNKNOWN)
    }
    if name == "Option" {
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let inner = resolve_type_ann(sublist_get(elems_sl, 0))
            return make_option_type(inner)
        }
        return make_option_type(TYPE_UNKNOWN)
    }
    if name == "Result" {
        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
            let ok_t = resolve_type_ann(sublist_get(elems_sl, 0))
            let err_t = resolve_type_ann(sublist_get(elems_sl, 1))
            return make_result_type(ok_t, err_t)
        }
        return make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN)
    }
    if name == "Map" {
        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
            let key_t = resolve_type_ann(sublist_get(elems_sl, 0))
            let val_t = resolve_type_ann(sublist_get(elems_sl, 1))
            return make_map_type(key_t, val_t)
        }
        return make_map_type(TYPE_UNKNOWN, TYPE_UNKNOWN)
    }
    if name == "Bytes" {
        return new_type(TK_BYTES, "Bytes")
    }

    let resolved = resolve_type_name(name)
    if resolved != -1 {
        return resolved
    }

    make_typevar(name)
}

// ── Registration from AST ───────────────────────────────────────────

pub fn register_struct_type(td: Int) ! TypeCheck.Register, TypeCheck.Resolve {
    let name = np_name.get(td).unwrap()
    let tid = new_type(TK_STRUCT, name)
    named_type_names.push(name)
    named_type_ids.push(tid)
    named_type_map.set(name, tid)

    let flds_sl = np_fields.get(td).unwrap()
    if flds_sl != -1 {
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let f = sublist_get(flds_sl, i)
            let fname = np_name.get(f).unwrap()
            let ftype_ann = np_value.get(f).unwrap()
            let ftype_id = resolve_type_ann(ftype_ann)
            sfield_struct_id.push(tid)
            sfield_name.push(fname)
            sfield_type_id.push(ftype_id)
            i = i + 1
        }
    }
}

pub fn register_enum_type(td: Int) ! TypeCheck.Register, TypeCheck.Resolve {
    let name = np_name.get(td).unwrap()
    let tid = new_type(TK_ENUM, name)
    named_type_names.push(name)
    named_type_ids.push(tid)
    named_type_map.set(name, tid)

    let flds_sl = np_fields.get(td).unwrap()
    if flds_sl != -1 {
        let mut tag = 0
        let mut i = 0
        while i < sublist_length(flds_sl) {
            let v = sublist_get(flds_sl, i)
            let vname = np_name.get(v).unwrap()
            let var_idx = evar_enum_id.len()
            evar_enum_id.push(tid)
            evar_name.push(vname)
            evar_tag.push(tag)

            let vflds_sl = np_fields.get(v).unwrap()
            if vflds_sl != -1 && sublist_length(vflds_sl) > 0 {
                evar_has_data.push(1)
                let mut fi = 0
                while fi < sublist_length(vflds_sl) {
                    let vf = sublist_get(vflds_sl, fi)
                    let vf_name = np_name.get(vf).unwrap()
                    let vf_type_ann = np_value.get(vf).unwrap()
                    let vf_type_id = resolve_type_ann(vf_type_ann)
                    evfield_var_idx.push(var_idx)
                    evfield_name.push(vf_name)
                    evfield_type_id.push(vf_type_id)
                    fi = fi + 1
                }
            } else {
                evar_has_data.push(0)
            }

            tag = tag + 1
            i = i + 1
        }
    }
}

pub fn register_fn_sig(fn_node: Int) ! TypeCheck.Register, TypeCheck.Resolve {
    let name = np_name.get(fn_node).unwrap()
    let ret_str = np_return_type.get(fn_node).unwrap()
    let ret_ann = np_type_ann.get(fn_node).unwrap()
    let mut ret_tid = TYPE_VOID

    if ret_ann != -1 {
        ret_tid = resolve_type_ann(ret_ann)
    } else if ret_str != "" {
        ret_tid = resolve_type_name(ret_str)
        if ret_tid == -1 {
            ret_tid = TYPE_VOID
        }
    }

    let sig_idx = fnsig_name.len()
    fnsig_name.push(name)
    fnsig_map.set(name, sig_idx)
    fnsig_ret.push(ret_tid)
    let start = fnsig_param_list.len()
    fnsig_params_start.push(start)

    let params_sl = np_params.get(fn_node).unwrap()
    let mut count = 0
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let ptype_str = np_type_name.get(p).unwrap()
            let ptype_ann = np_type_ann.get(p).unwrap()
            let mut ptid = TYPE_UNKNOWN
            if ptype_ann != -1 {
                ptid = resolve_type_ann(ptype_ann)
            } else if ptype_str != "" {
                ptid = resolve_type_name(ptype_str)
                if ptid == -1 {
                    ptid = TYPE_UNKNOWN
                }
            }
            fnsig_param_list.push(ptid)
            count = count + 1
            i = i + 1
        }
    }
    fnsig_params_count.push(count)

    let tparams_sl = np_type_params.get(fn_node).unwrap()
    let tp_start = fnsig_type_param_names.len()
    let mut tp_count = 0
    if tparams_sl != -1 {
        let mut ti = 0
        while ti < sublist_length(tparams_sl) {
            let tp = sublist_get(tparams_sl, ti)
            fnsig_type_param_names.push(np_name.get(tp).unwrap())
            tp_count = tp_count + 1
            ti = ti + 1
        }
    }
    fnsig_type_params_start.push(tp_start)
    fnsig_type_params_count.push(tp_count)

    let effects_sl = np_effects.get(fn_node).unwrap()
    let mut effs = ""
    if effects_sl != -1 {
        let mut ei = 0
        while ei < sublist_length(effects_sl) {
            let eff = sublist_get(effects_sl, ei)
            if ei > 0 {
                effs = effs.concat(",")
            }
            effs = effs.concat(np_name.get(eff).unwrap())
            ei = ei + 1
        }
    }
    tc_fn_effects.push(effs)
}

pub fn tc_get_fn_effects(name: Str) -> Str {
    let sig = lookup_fnsig(name)
    if sig == -1 { return "" }
    if sig >= tc_fn_effects.len() { return "" }
    tc_fn_effects.get(sig).unwrap()
}

pub fn register_trait(tr_node: Int) ! TypeCheck.Register {
    let name = np_name.get(tr_node).unwrap()
    tc_trait_names.push(name)
    let methods_sl = np_methods.get(tr_node).unwrap()
    if methods_sl != -1 {
        let mut i = 0
        while i < sublist_length(methods_sl) {
            let m = sublist_get(methods_sl, i)
            tc_trait_method_names.push("{name}.{np_name.get(m).unwrap()}")
            i = i + 1
        }
    }
}

// ── Main entry point ────────────────────────────────────────────────

pub fn init_types() ! TypeCheck.Register {
    ty_kind = []
    ty_name = []
    ty_inner1 = []
    ty_inner2 = []
    ty_params_start = []
    ty_params_count = []
    ty_param_list = []
    named_type_names = []
    named_type_ids = []
    named_type_map = Map()
    sfield_struct_id = []
    sfield_name = []
    sfield_type_id = []
    evar_enum_id = []
    evar_name = []
    evar_tag = []
    evar_has_data = []
    evfield_var_idx = []
    evfield_name = []
    evfield_type_id = []
    fnsig_name = []
    fnsig_map = Map()
    fnsig_ret = []
    fnsig_params_start = []
    fnsig_params_count = []
    fnsig_param_list = []
    fnsig_type_params_start = []
    fnsig_type_params_count = []
    fnsig_type_param_names = []
    tc_trait_names = []
    tc_trait_method_names = []
    tc_fn_effects = []
    tc_current_fn_ret = -1
    tc_current_fn_name = ""
    tc_errors = []
    tc_warnings = []

    TYPE_INT = new_type(TK_INT, "Int")
    TYPE_FLOAT = new_type(TK_FLOAT, "Float")
    TYPE_BOOL = new_type(TK_BOOL, "Bool")
    TYPE_STR = new_type(TK_STR, "Str")
    TYPE_VOID = new_type(TK_VOID, "Void")
    TYPE_UNKNOWN = new_type(TK_UNKNOWN, "?")
}

pub fn check_types(program: Int) -> Int ! TypeCheck, Diag.Report {
    init_types()

    // Register all type definitions (structs and enums)
    let types_sl = np_fields.get(program).unwrap()
    if types_sl != -1 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let td = sublist_get(types_sl, i)
            let td_flds = np_fields.get(td).unwrap()
            let mut is_enum = 0
            if td_flds != -1 && sublist_length(td_flds) > 0 {
                if np_kind.get(sublist_get(td_flds, 0)).unwrap() == NodeKind.TypeVariant {
                    is_enum = 1
                }
            }
            if is_enum != 0 {
                register_enum_type(td)
            } else {
                register_struct_type(td)
            }
            i = i + 1
        }
    }

    // Register all function signatures
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            register_fn_sig(sublist_get(fns_sl, i))
            i = i + 1
        }
    }

    // Register traits
    let traits_sl = np_arms.get(program).unwrap()
    if traits_sl != -1 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            register_trait(sublist_get(traits_sl, i))
            i = i + 1
        }
    }

    // Register impl method signatures
    let impls_sl = np_methods.get(program).unwrap()
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_type = np_name.get(im).unwrap()
            let methods_sl = np_methods.get(im).unwrap()
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    let orig_name = np_name.get(m).unwrap()
                    np_name.set(m, "{impl_type}_{orig_name}")
                    register_fn_sig(m)
                    np_name.set(m, orig_name)
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    // Register user-defined effect handle names
    tc_ue_handles = []
    let effects_decl_sl = np_args.get(program).unwrap()
    if effects_decl_sl != -1 {
        let mut ei = 0
        while ei < sublist_length(effects_decl_sl) {
            let ed = sublist_get(effects_decl_sl, ei)
            let eff_name = np_name.get(ed).unwrap()
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
            register_ue_handle(handle)
            ei = ei + 1
        }
    }

    // Phase 1: Name resolution
    resolve_names(program)

    // Phase 2: Expression type inference
    tc_infer_program(program)

    tc_errors.len()
}

// ── User-effect handle name tracking ────────────────────────────────

pub let mut tc_ue_handles: List[Str] = []

pub fn register_ue_handle(name: Str) {
    tc_ue_handles.push(name)
}

pub fn is_user_effect_handle_name(name: Str) -> Int {
    let mut i = 0
    while i < tc_ue_handles.len() {
        if tc_ue_handles.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

// ── Import visibility ───────────────────────────────────────────────

let mut nr_private_imports: Map[Str, Str] = Map()
let mut nr_current_module: Str = ""

fn is_private_access(name: Str) -> Int {
    if nr_private_imports.has(name) == 0 { return 0 }
    let mods = nr_private_imports.get(name)
    if mods.contains("|{nr_current_module}|") != 0 { return 0 }
    1
}

// ── Name resolution scope ───────────────────────────────────────────

pub let mut nr_scope_names: List[Str] = []
pub let mut nr_scope_muts: List[Int] = []
pub let mut nr_scope_types: List[Int] = []
pub let mut nr_scope_frames: List[Int] = []

pub fn nr_push_scope() {
    nr_scope_frames.push(nr_scope_names.len())
}

pub fn nr_pop_scope() {
    let start = nr_scope_frames.get(nr_scope_frames.len() - 1).unwrap()
    nr_scope_frames.pop()
    while nr_scope_names.len() > start {
        nr_scope_names.pop()
        nr_scope_muts.pop()
        nr_scope_types.pop()
    }
}

pub fn nr_define(name: Str) {
    nr_scope_names.push(name)
    nr_scope_muts.push(0)
    nr_scope_types.push(TYPE_UNKNOWN)
}

pub fn nr_define_mut(name: Str, is_mut: Int) {
    nr_scope_names.push(name)
    nr_scope_muts.push(is_mut)
    nr_scope_types.push(TYPE_UNKNOWN)
}

pub fn nr_define_typed(name: Str, is_mut: Int, tid: Int) {
    nr_scope_names.push(name)
    nr_scope_muts.push(is_mut)
    nr_scope_types.push(tid)
}

pub fn nr_is_defined(name: Str) -> Int {
    let mut i = nr_scope_names.len() - 1
    while i >= 0 {
        if nr_scope_names.get(i).unwrap() == name {
            return 1
        }
        i = i - 1
    }
    0
}

pub fn nr_is_mut(name: Str) -> Int {
    let mut i = nr_scope_names.len() - 1
    while i >= 0 {
        if nr_scope_names.get(i).unwrap() == name {
            return nr_scope_muts.get(i).unwrap()
        }
        i = i - 1
    }
    0
}

pub fn nr_get_type(name: Str) -> Int {
    let mut i = nr_scope_names.len() - 1
    while i >= 0 {
        if nr_scope_names.get(i).unwrap() == name {
            return nr_scope_types.get(i).unwrap()
        }
        i = i - 1
    }
    TYPE_UNKNOWN
}

pub fn is_builtin_fn(name: Str) -> Int {
    if name == "arg_count" { return 1 }
    if name == "get_arg" { return 1 }
    if name == "read_file" { return 1 }
    if name == "write_file" { return 1 }
    if name == "file_exists" { return 1 }
    if name == "path_join" { return 1 }
    if name == "path_dirname" { return 1 }
    if name == "path_basename" { return 1 }
    if name == "shell_exec" { return 1 }
    if name == "exit" { return 1 }
    if name == "is_dir" { return 1 }
    if name == "get_env" { return 1 }
    if name == "time_ms" { return 1 }
    if name == "Some" { return 1 }
    if name == "None" { return 1 }
    if name == "Ok" { return 1 }
    if name == "Err" { return 1 }
    if name == "assert" { return 1 }
    if name == "assert_eq" { return 1 }
    if name == "assert_ne" { return 1 }
    if name == "debug_assert" { return 1 }
    if name == "Map" { return 1 }
    if name == "Bytes" { return 1 }
    if name == "Channel" { return 1 }
    if name == "unix_socket_listen" { return 1 }
    if name == "unix_socket_connect" { return 1 }
    if name == "unix_socket_accept" { return 1 }
    if name == "unix_socket_accept_timeout" { return 1 }
    if name == "unix_socket_close" { return 1 }
    if name == "socket_read_line" { return 1 }
    if name == "socket_write" { return 1 }
    if name == "file_mtime" { return 1 }
    if name == "getpid" { return 1 }
    if name == "process_run" { return 1 }
    if name == "process_exec" { return 1 }
    0
}

pub fn is_builtin_method(name: Str) -> Int {
    // String methods
    if name == "len" { return 1 }
    if name == "contains" { return 1 }
    if name == "starts_with" { return 1 }
    if name == "ends_with" { return 1 }
    if name == "concat" { return 1 }
    if name == "slice" { return 1 }
    if name == "to_int" { return 1 }
    if name == "split" { return 1 }
    if name == "char_at" { return 1 }
    if name == "charAt" { return 1 }
    if name == "substring" { return 1 }
    if name == "substr" { return 1 }
    if name == "index_of" { return 1 }
    if name == "trim" { return 1 }
    if name == "to_lower" { return 1 }
    if name == "to_upper" { return 1 }
    if name == "replace" { return 1 }
    // List methods
    if name == "push" { return 1 }
    if name == "pop" { return 1 }
    if name == "get" { return 1 }
    if name == "set" { return 1 }
    if name == "join" { return 1 }
    // Iterator methods
    if name == "map" { return 1 }
    if name == "filter" { return 1 }
    if name == "collect" { return 1 }
    if name == "count" { return 1 }
    if name == "for_each" { return 1 }
    if name == "any" { return 1 }
    if name == "all" { return 1 }
    if name == "find" { return 1 }
    if name == "fold" { return 1 }
    if name == "take" { return 1 }
    if name == "skip" { return 1 }
    if name == "chain" { return 1 }
    if name == "flat_map" { return 1 }
    if name == "enumerate" { return 1 }
    if name == "zip" { return 1 }
    // Map methods
    if name == "has" { return 1 }
    if name == "remove" { return 1 }
    if name == "keys" { return 1 }
    if name == "values" { return 1 }
    // Bytes methods
    if name == "is_empty" { return 1 }
    if name == "to_str" { return 1 }
    if name == "to_hex" { return 1 }
    if name == "from_str" { return 1 }
    if name == "from_code_point" { return 1 }
    // Effect handle methods (io, fs, net, time, async, env)
    if name == "println" { return 1 }
    if name == "print" { return 1 }
    if name == "eprintln" { return 1 }
    if name == "eprint" { return 1 }
    if name == "log" { return 1 }
    if name == "read" { return 1 }
    if name == "write" { return 1 }
    if name == "list_dir" { return 1 }
    if name == "args" { return 1 }
    if name == "sleep" { return 1 }
    if name == "spawn" { return 1 }
    // Net methods
    if name == "request" { return 1 }
    if name == "listen" { return 1 }
    if name == "accept" { return 1 }
    if name == "read_line" { return 1 }
    if name == "read_n" { return 1 }
    if name == "write_line" { return 1 }
    if name == "close" { return 1 }
    if name == "post" { return 1 }
    if name == "put" { return 1 }
    if name == "patch" { return 1 }
    if name == "head" { return 1 }
    if name == "delete" { return 1 }
    // Channel methods
    if name == "send" { return 1 }
    if name == "recv" { return 1 }
    // Conversion methods
    if name == "into" { return 1 }
    if name == "to_float" { return 1 }
    if name == "to_string" { return 1 }
    if name == "from" { return 1 }
    if name == "try_from" { return 1 }
    // Int methods
    if name == "abs" { return 1 }
    if name == "min" { return 1 }
    if name == "max" { return 1 }
    // Option methods
    if name == "unwrap" { return 1 }
    if name == "is_some" { return 1 }
    if name == "is_none" { return 1 }
    // Result methods
    if name == "unwrap_err" { return 1 }
    if name == "is_ok" { return 1 }
    if name == "is_err" { return 1 }
    // Instant methods
    if name == "elapsed" { return 1 }
    if name == "since" { return 1 }
    if name == "add" { return 1 }
    if name == "to_rfc3339" { return 1 }
    if name == "to_unix_ms" { return 1 }
    if name == "to_unix_secs" { return 1 }
    // Duration static constructors
    if name == "nanos" { return 1 }
    if name == "ms" { return 1 }
    if name == "seconds" { return 1 }
    if name == "minutes" { return 1 }
    if name == "hours" { return 1 }
    // Duration methods
    if name == "to_ms" { return 1 }
    if name == "to_seconds" { return 1 }
    if name == "to_nanos" { return 1 }
    if name == "sub" { return 1 }
    if name == "scale" { return 1 }
    if name == "is_zero" { return 1 }
    // Bytes/Instant static constructors
    if name == "new" { return 1 }
    if name == "from_epoch_secs" { return 1 }
    0
}

pub fn get_builtin_fn_ret(name: Str) -> Int {
    if name == "arg_count" { return TYPE_INT }
    if name == "get_arg" { return TYPE_STR }
    if name == "read_file" { return TYPE_STR }
    if name == "write_file" { return TYPE_VOID }
    if name == "file_exists" { return TYPE_INT }
    if name == "path_join" { return TYPE_STR }
    if name == "path_dirname" { return TYPE_STR }
    if name == "path_basename" { return TYPE_STR }
    if name == "shell_exec" { return TYPE_INT }
    if name == "exit" { return TYPE_VOID }
    if name == "is_dir" { return TYPE_INT }
    if name == "get_env" { return make_option_type(TYPE_STR) }
    if name == "time_ms" { return TYPE_INT }
    if name == "assert" { return TYPE_VOID }
    if name == "assert_eq" { return TYPE_VOID }
    if name == "assert_ne" { return TYPE_VOID }
    if name == "debug_assert" { return TYPE_VOID }
    if name == "unix_socket_listen" { return TYPE_INT }
    if name == "unix_socket_connect" { return TYPE_INT }
    if name == "unix_socket_accept" { return TYPE_INT }
    if name == "unix_socket_accept_timeout" { return TYPE_INT }
    if name == "unix_socket_close" { return TYPE_VOID }
    if name == "socket_read_line" { return TYPE_STR }
    if name == "socket_write" { return TYPE_VOID }
    if name == "file_mtime" { return TYPE_INT }
    if name == "getpid" { return TYPE_INT }
    if name == "process_run" { return TYPE_VOID }
    if name == "process_exec" { return TYPE_VOID }
    if name == "Bytes" { return new_type(TK_BYTES, "Bytes") }
    TYPE_UNKNOWN
}

pub fn is_variant_name(name: Str) -> Int {
    let mut i = 0
    while i < evar_name.len() {
        if evar_name.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_variant_enum_tid(name: Str) -> Int {
    let mut i = 0
    while i < evar_name.len() {
        if evar_name.get(i).unwrap() == name {
            return evar_enum_id.get(i).unwrap()
        }
        i = i + 1
    }
    TYPE_UNKNOWN
}

pub fn is_trait_name(name: Str) -> Int {
    let mut i = 0
    while i < tc_trait_names.len() {
        if tc_trait_names.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_known_type(name: Str) -> Int {
    if name == "Int" || name == "Float" || name == "Bool" || name == "Str" { return 1 }
    if name == "Void" || name == "List" || name == "Option" || name == "Result" { return 1 }
    if name == "Iterator" || name == "Handle" || name == "Channel" || name == "Map" || name == "Bytes" || name == "Instant" || name == "Duration" || name == "Char" { return 1 }
    if name == "Fn" || name == "Self" { return 1 }
    if lookup_named_type(name) != -1 { return 1 }
    0
}

// Impl method registry for name resolution
pub let mut nr_impl_type_names: List[Str] = []
pub let mut nr_impl_method_names: List[Str] = []

pub fn nr_has_impl_method(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < nr_impl_type_names.len() {
        if nr_impl_type_names.get(i).unwrap() == type_name && nr_impl_method_names.get(i).unwrap() == method {
            return 1
        }
        i = i + 1
    }
    0
}

// ── Name resolution walker ──────────────────────────────────────────

pub fn resolve_names(program: Int) ! TypeCheck.Resolve, Diag.Report {
    nr_scope_names = []
    nr_scope_muts = []
    nr_scope_types = []
    nr_scope_frames = []
    nr_impl_type_names = []
    nr_impl_method_names = []
    nr_private_imports = Map()
    nr_push_scope()

    // Build private import set: imported non-pub fns, types, lets
    // A name is private only if no pub definition exists for it
    let mut nr_pub_names: Map[Str, Int] = Map()

    // First pass: collect all pub imported names
    let fns_sl_priv = np_params.get(program).unwrap()
    if fns_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl_priv) {
            let fn_node = sublist_get(fns_sl_priv, i)
            if np_module.get(fn_node).unwrap() != "" && np_is_pub.get(fn_node).unwrap() != 0 {
                nr_pub_names.set(np_name.get(fn_node).unwrap(), 1)
            }
            i = i + 1
        }
    }
    let types_sl_priv = np_fields.get(program).unwrap()
    if types_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(types_sl_priv) {
            let td = sublist_get(types_sl_priv, i)
            if np_module.get(td).unwrap() != "" && np_is_pub.get(td).unwrap() != 0 {
                nr_pub_names.set(np_name.get(td).unwrap(), 1)
            }
            i = i + 1
        }
    }
    let lets_sl_priv = np_stmts.get(program).unwrap()
    if lets_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl_priv) {
            let l = sublist_get(lets_sl_priv, i)
            if np_module.get(l).unwrap() != "" && np_is_pub.get(l).unwrap() != 0 {
                nr_pub_names.set(np_name.get(l).unwrap(), 1)
            }
            i = i + 1
        }
    }

    // Second pass: register private names (skip if a pub version exists)
    // Value format: "|mod1|mod2|" so contains("|modX|") works for same-module check
    if fns_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl_priv) {
            let fn_node = sublist_get(fns_sl_priv, i)
            let fn_name = np_name.get(fn_node).unwrap()
            let mod_name = np_module.get(fn_node).unwrap()
            if mod_name != "" && np_is_pub.get(fn_node).unwrap() == 0 && nr_pub_names.has(fn_name) == 0 {
                if nr_private_imports.has(fn_name) != 0 {
                    let prev = nr_private_imports.get(fn_name)
                    nr_private_imports.set(fn_name, "{prev}{mod_name}|")
                } else {
                    nr_private_imports.set(fn_name, "|{mod_name}|")
                }
            }
            i = i + 1
        }
    }
    if types_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(types_sl_priv) {
            let td = sublist_get(types_sl_priv, i)
            let td_name = np_name.get(td).unwrap()
            let mod_name = np_module.get(td).unwrap()
            if mod_name != "" && np_is_pub.get(td).unwrap() == 0 && nr_pub_names.has(td_name) == 0 {
                if nr_private_imports.has(td_name) != 0 {
                    let prev = nr_private_imports.get(td_name)
                    nr_private_imports.set(td_name, "{prev}{mod_name}|")
                } else {
                    nr_private_imports.set(td_name, "|{mod_name}|")
                }
            }
            i = i + 1
        }
    }
    if lets_sl_priv != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl_priv) {
            let l = sublist_get(lets_sl_priv, i)
            let l_name = np_name.get(l).unwrap()
            let mod_name = np_module.get(l).unwrap()
            if mod_name != "" && np_is_pub.get(l).unwrap() == 0 && nr_pub_names.has(l_name) == 0 {
                if nr_private_imports.has(l_name) != 0 {
                    let prev = nr_private_imports.get(l_name)
                    nr_private_imports.set(l_name, "{prev}{mod_name}|")
                } else {
                    nr_private_imports.set(l_name, "|{mod_name}|")
                }
            }
            i = i + 1
        }
    }

    // Register all top-level let binding names
    let lets_sl = np_stmts.get(program).unwrap()
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let l = sublist_get(lets_sl, i)
            nr_define(np_name.get(l).unwrap())
            i = i + 1
        }
    }

    // Register all function names in scope
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            nr_define(np_name.get(sublist_get(fns_sl, i)).unwrap())
            i = i + 1
        }
    }

    // Register impl methods for method call resolution
    let impls_sl = np_methods.get(program).unwrap()
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_type = np_name.get(im).unwrap()
            let methods_sl = np_methods.get(im).unwrap()
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    nr_impl_type_names.push(impl_type)
                    nr_impl_method_names.push(np_name.get(m).unwrap())
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    // Walk each function body
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            nr_current_module = np_module.get(fn_node).unwrap()
            nr_check_fn(fn_node)
            i = i + 1
        }
    }

    // Walk each impl method body
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            nr_current_module = np_module.get(im).unwrap()
            let methods_sl = np_methods.get(im).unwrap()
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    nr_check_fn(sublist_get(methods_sl, j))
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    nr_pop_scope()
}

pub fn nr_check_fn(fn_node: Int) ! TypeCheck.Resolve, Diag.Report {
    nr_push_scope()
    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            nr_define(np_name.get(p).unwrap())
            nr_check_type_ref(np_type_name.get(p).unwrap())
            i = i + 1
        }
    }
    let ret_str = np_return_type.get(fn_node).unwrap()
    if ret_str != "" {
        nr_check_type_ref(ret_str)
    }
    let body = np_body.get(fn_node).unwrap()
    if body != -1 {
        nr_check_node(body)
    }
    nr_pop_scope()
}

pub fn nr_check_type_ref(name: Str) ! TypeCheck.Resolve, Diag.Report {
    if name == "" { return }
    if is_known_type(name) != 0 { return }
    if name.len() == 1 { return }
    tc_errors.push("unknown type '{name}'")
    diag_error_no_loc("UnknownType", "E0507", "unknown type '{name}'", "")
}

pub fn nr_check_node(node: Int) ! TypeCheck.Resolve, Diag.Report {
    if node == -1 { return }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.Block {
        nr_push_scope()
        let stmts_sl = np_stmts.get(node).unwrap()
        if stmts_sl != -1 {
            let mut i = 0
            while i < sublist_length(stmts_sl) {
                nr_check_node(sublist_get(stmts_sl, i))
                i = i + 1
            }
        }
        nr_pop_scope()
        return
    }

    if kind == NodeKind.LetBinding {
        let val = np_value.get(node).unwrap()
        if val != -1 {
            nr_check_node(val)
        }
        nr_define_mut(np_name.get(node).unwrap(), np_is_mut.get(node).unwrap())
        return
    }

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        nr_check_node(np_target.get(node).unwrap())
        nr_check_node(np_value.get(node).unwrap())
        return
    }

    if kind == NodeKind.ExprStmt {
        nr_check_node(np_value.get(node).unwrap())
        return
    }

    if kind == NodeKind.Return {
        nr_check_node(np_value.get(node).unwrap())
        return
    }

    if kind == NodeKind.Ident {
        let name = np_name.get(node).unwrap()
        if name == "true" || name == "false" || name == "None" { return }
        if name == "io" || name == "fs" || name == "net" || name == "db" || name == "env" || name == "time" || name == "async" || name == "channel" || name == "default" { return }
        if is_user_effect_handle_name(name) != 0 { return }
        if is_private_access(name) != 0 {
            tc_errors.push("cannot access private item '{name}'")
            diag_error_at("PrivateItemAccess", "E1003", "cannot access private item '{name}' from another module", node, "mark the item as 'pub' in its module")
            return
        }
        if nr_is_defined(name) != 0 { return }
        if is_variant_name(name) != 0 { return }
        if is_builtin_fn(name) != 0 { return }
        if is_known_type(name) != 0 { return }
        if is_trait_name(name) != 0 { return }
        tc_errors.push("undefined variable '{name}'")
        diag_error_at("UndefinedVariable", "E0506", "undefined variable '{name}'", node, "")
        return
    }

    if kind == NodeKind.IntLit || kind == NodeKind.FloatLit || kind == NodeKind.BoolLit {
        return
    }

    if kind == NodeKind.InterpString {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                let part = sublist_get(elems_sl, i)
                let pk = np_kind.get(part).unwrap()
                if pk == NodeKind.Ident && np_str_val.get(part).unwrap() == np_name.get(part).unwrap() {
                    let _skip = 0
                } else {
                    nr_check_node(part)
                }
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.Call {
        let callee = np_left.get(node).unwrap()
        if callee != -1 {
            let callee_kind = np_kind.get(callee).unwrap()
            if callee_kind == NodeKind.Ident {
                let fn_name = np_name.get(callee).unwrap()
                if is_private_access(fn_name) != 0 {
                    tc_errors.push("cannot access private function '{fn_name}'")
                    diag_error_at("PrivateItemAccess", "E1003", "cannot access private function '{fn_name}' from another module", node, "mark the function as 'pub' in its module")
                } else if nr_is_defined(fn_name) == 0 && is_builtin_fn(fn_name) == 0 && is_variant_name(fn_name) == 0 && is_known_type(fn_name) == 0 && is_trait_name(fn_name) == 0 {
                    tc_errors.push("undefined function '{fn_name}'")
                    diag_error_at("UndefinedFunction", "E0504", "undefined function '{fn_name}'", node, "")
                }
            } else {
                nr_check_node(callee)
            }
        }
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                nr_check_node(sublist_get(args_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.MethodCall {
        let obj = np_obj.get(node).unwrap()
        if obj != -1 {
            nr_check_node(obj)
        }
        let method_name = np_method.get(node).unwrap()
        if is_builtin_method(method_name) == 0 && is_variant_name(method_name) == 0 {
            let mut found_in_impl = 0
            let mut mi = 0
            while mi < nr_impl_method_names.len() {
                if nr_impl_method_names.get(mi).unwrap() == method_name {
                    found_in_impl = 1
                }
                mi = mi + 1
            }
            if found_in_impl == 0 {
                diag_warn_at("UnknownMethod", "W0501", "unknown method '{method_name}' — may fail at compile time", node, "")
            }
        }
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                nr_check_node(sublist_get(args_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.FieldAccess {
        let obj = np_obj.get(node).unwrap()
        if obj != -1 {
            nr_check_node(obj)
        }
        return
    }

    if kind == NodeKind.IndexExpr {
        nr_check_node(np_obj.get(node).unwrap())
        nr_check_node(np_index.get(node).unwrap())
        return
    }

    if kind == NodeKind.BinOp {
        nr_check_node(np_left.get(node).unwrap())
        nr_check_node(np_right.get(node).unwrap())
        return
    }

    if kind == NodeKind.UnaryOp {
        nr_check_node(np_right.get(node).unwrap())
        return
    }

    if kind == NodeKind.IfExpr {
        nr_check_node(np_condition.get(node).unwrap())
        nr_check_node(np_then_body.get(node).unwrap())
        nr_check_node(np_else_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WhileLoop {
        nr_check_node(np_condition.get(node).unwrap())
        nr_check_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.LoopExpr {
        nr_check_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.ForIn {
        nr_check_node(np_iterable.get(node).unwrap())
        nr_push_scope()
        nr_define(np_var_name.get(node).unwrap())
        nr_check_node(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.Break || kind == NodeKind.Continue {
        return
    }

    if kind == NodeKind.MatchExpr {
        nr_check_node(np_scrutinee.get(node).unwrap())
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 {
            let mut i = 0
            while i < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, i)
                nr_push_scope()
                nr_check_pattern(np_pattern.get(arm).unwrap())
                let guard = np_guard.get(arm).unwrap()
                if guard != -1 {
                    nr_check_node(guard)
                }
                nr_check_node(np_body.get(arm).unwrap())
                nr_pop_scope()
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        nr_push_scope()
        let params_sl = np_params.get(node).unwrap()
        if params_sl != -1 {
            let mut i = 0
            while i < sublist_length(params_sl) {
                nr_define(np_name.get(sublist_get(params_sl, i)).unwrap())
                i = i + 1
            }
        }
        nr_check_node(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.StructLit {
        let type_name = np_type_name.get(node).unwrap()
        if type_name != "" {
            nr_check_type_ref(type_name)
        }
        let flds_sl = np_fields.get(node).unwrap()
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                let f = sublist_get(flds_sl, i)
                nr_check_node(np_value.get(f).unwrap())
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                nr_check_node(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.TupleLit {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                nr_check_node(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.RangeLit {
        nr_check_node(np_start.get(node).unwrap())
        nr_check_node(np_end.get(node).unwrap())
        return
    }

    if kind == NodeKind.WithBlock {
        let handlers_sl = np_handlers.get(node).unwrap()
        if handlers_sl != -1 {
            let mut i = 0
            while i < sublist_length(handlers_sl) {
                nr_check_node(sublist_get(handlers_sl, i))
                i = i + 1
            }
        }
        nr_check_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WithResource {
        nr_push_scope()
        nr_define(np_name.get(node).unwrap())
        nr_check_node(np_value.get(node).unwrap())
        nr_check_node(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.HandlerExpr {
        let methods_sl = np_methods.get(node).unwrap()
        if methods_sl != -1 {
            let mut i = 0
            while i < sublist_length(methods_sl) {
                nr_check_fn(sublist_get(methods_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.AsyncScope {
        nr_check_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.AsyncSpawn {
        nr_check_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.AwaitExpr {
        nr_check_node(np_value.get(node).unwrap())
        return
    }

    if kind == NodeKind.ChannelNew {
        return
    }

    if kind == NodeKind.EmbedExpr {
        return
    }

    let _skip = 0
}

pub fn nr_check_pattern(node: Int) ! TypeCheck.Resolve {
    if node == -1 { return }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.IdentPattern {
        let name = np_name.get(node).unwrap()
        if name != "_" {
            nr_define(name)
        }
        return
    }

    if kind == NodeKind.IntPattern || kind == NodeKind.StringPattern || kind == NodeKind.WildcardPattern {
        return
    }

    if kind == NodeKind.EnumPattern {
        let flds_sl = np_fields.get(node).unwrap()
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                nr_check_pattern(sublist_get(flds_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.StructPattern {
        let flds_sl = np_fields.get(node).unwrap()
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                let f = sublist_get(flds_sl, i)
                nr_define(np_name.get(f).unwrap())
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                nr_check_pattern(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.ListPattern {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                nr_check_pattern(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }

    if kind == NodeKind.OrPattern {
        nr_check_pattern(np_left.get(node).unwrap())
        nr_check_pattern(np_right.get(node).unwrap())
        return
    }

    if kind == NodeKind.RangePattern {
        return
    }

    if kind == NodeKind.AsPattern {
        nr_check_pattern(np_pattern.get(node).unwrap())
        nr_define(np_name.get(node).unwrap())
        return
    }

    let _skip = 0
}

// ── Phase 2: Type compatibility ─────────────────────────────────────

pub fn types_compatible(a: Int, b: Int) -> Int {
    if a == b { return 1 }
    if a == TYPE_UNKNOWN || b == TYPE_UNKNOWN { return 1 }
    if a < 0 || b < 0 { return 1 }
    if a >= ty_kind.len() || b >= ty_kind.len() { return 1 }
    let ka = ty_kind.get(a).unwrap()
    let kb = ty_kind.get(b).unwrap()
    if ka == TK_TYPEVAR || kb == TK_TYPEVAR { return 1 }
    // Int and Bool are interchangeable in Pact (C-style truthiness)
    if (ka == TK_INT || ka == TK_BOOL) && (kb == TK_INT || kb == TK_BOOL) { return 1 }
    if ka == kb {
        if ka == TK_LIST || ka == TK_OPTION || ka == TK_ITERATOR {
            return types_compatible(ty_inner1.get(a).unwrap(), ty_inner1.get(b).unwrap())
        }
        if ka == TK_MAP {
            if types_compatible(ty_inner1.get(a).unwrap(), ty_inner1.get(b).unwrap()) == 0 { return 0 }
            return types_compatible(ty_inner2.get(a).unwrap(), ty_inner2.get(b).unwrap())
        }
        if ka == TK_RESULT {
            if types_compatible(ty_inner1.get(a).unwrap(), ty_inner1.get(b).unwrap()) == 0 { return 0 }
            return types_compatible(ty_inner2.get(a).unwrap(), ty_inner2.get(b).unwrap())
        }
        if ka == TK_STRUCT || ka == TK_ENUM {
            return 0
        }
        return 1
    }
    0
}

pub fn type_kind(tid: Int) -> Int {
    if tid < 0 || tid >= ty_kind.len() { return TK_UNKNOWN }
    ty_kind.get(tid).unwrap()
}

// Pact treats Int as truthy — Int is valid in Bool contexts
pub fn is_bool_compat(tid: Int) -> Int {
    if tid == TYPE_UNKNOWN { return 1 }
    if tid == TYPE_BOOL { return 1 }
    if tid == TYPE_INT { return 1 }
    let k = type_kind(tid)
    if k == TK_BOOL || k == TK_INT { return 1 }
    0
}

// ── Phase 2: Expression type inference ──────────────────────────────

pub fn infer_type(node: Int) -> Int ! TypeCheck.Resolve, TypeCheck.Report, Diag.Report {
    if node == -1 { return TYPE_UNKNOWN }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.IntLit { return TYPE_INT }
    if kind == NodeKind.FloatLit { return TYPE_FLOAT }
    if kind == NodeKind.BoolLit { return TYPE_BOOL }
    if kind == NodeKind.InterpString { return TYPE_STR }
    if kind == NodeKind.EmbedExpr { return TYPE_STR }

    if kind == NodeKind.Ident {
        let name = np_name.get(node).unwrap()
        if name == "true" || name == "false" { return TYPE_BOOL }
        if name == "None" { return make_option_type(TYPE_UNKNOWN) }
        let vt = nr_get_type(name)
        if vt != TYPE_UNKNOWN { return vt }
        if is_variant_name(name) != 0 {
            return get_variant_enum_tid(name)
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.BinOp {
        let op = np_op.get(node).unwrap()
        let lt = infer_type(np_left.get(node).unwrap())
        let rt = infer_type(np_right.get(node).unwrap())

        if op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" {
            return TYPE_BOOL
        }
        if op == "&&" || op == "||" {
            if is_bool_compat(lt) == 0 {
                tc_error_at("logical operator '{op}' requires Bool operands, got {type_to_str(lt)}", node)
            }
            if is_bool_compat(rt) == 0 {
                tc_error_at("logical operator '{op}' requires Bool operands, got {type_to_str(rt)}", node)
            }
            return TYPE_BOOL
        }
        if op == "+" {
            if type_kind(lt) == TK_STR || type_kind(rt) == TK_STR {
                return TYPE_STR
            }
        }
        if op == "+" || op == "-" || op == "*" || op == "/" || op == "%" {
            if lt != TYPE_UNKNOWN && rt != TYPE_UNKNOWN {
                if types_compatible(lt, rt) == 0 {
                    tc_error_at("binary '{op}': incompatible types {type_to_str(lt)} and {type_to_str(rt)}", node)
                }
            }
            if lt != TYPE_UNKNOWN { return lt }
            return rt
        }
        if lt != TYPE_UNKNOWN { return lt }
        return rt
    }

    if kind == NodeKind.UnaryOp {
        let op = np_op.get(node).unwrap()
        let operand = infer_type(np_right.get(node).unwrap())
        if op == "!" { return TYPE_BOOL }
        if op == "-" { return operand }
        if op == "?" {
            if tc_current_fn_ret >= 0 && tc_current_fn_ret < ty_kind.len() {
                let ret_kind = ty_kind.get(tc_current_fn_ret).unwrap()
                if ret_kind != TK_RESULT && ret_kind != TK_UNKNOWN {
                    tc_errors.push("'?' operator used in function '{tc_current_fn_name}' which does not return Result")
                    diag_error_at("TypeError", "E0300", "'?' operator used in function '{tc_current_fn_name}' which does not return Result", node, "change the return type to Result")
                }
            }
            let ok = type_kind(operand)
            if ok == TK_OPTION { return ty_inner1.get(operand).unwrap() }
            if ok == TK_RESULT { return ty_inner1.get(operand).unwrap() }
            return operand
        }
        if op == "??" {
            let operand_k = type_kind(operand)
            if operand_k != TK_OPTION && operand_k != TK_UNKNOWN {
                tc_error_at("'??' operator requires Option value, got {type_to_str(operand)}", node)
            }
            if operand_k == TK_OPTION { return ty_inner1.get(operand).unwrap() }
            return operand
        }
        return operand
    }

    if kind == NodeKind.Call {
        let callee = np_left.get(node).unwrap()
        if callee != -1 {
            let callee_kind = np_kind.get(callee).unwrap()
            if callee_kind == NodeKind.Ident {
                let fn_name = np_name.get(callee).unwrap()
                if fn_name == "Some" {
                    let args_sl = np_args.get(node).unwrap()
                    if args_sl != -1 && sublist_length(args_sl) >= 1 {
                        let inner = infer_type(sublist_get(args_sl, 0))
                        return make_option_type(inner)
                    }
                    return make_option_type(TYPE_UNKNOWN)
                }
                if fn_name == "Ok" {
                    let args_sl = np_args.get(node).unwrap()
                    if args_sl != -1 && sublist_length(args_sl) >= 1 {
                        let inner = infer_type(sublist_get(args_sl, 0))
                        return make_result_type(inner, TYPE_UNKNOWN)
                    }
                    return make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN)
                }
                if fn_name == "Err" {
                    let args_sl = np_args.get(node).unwrap()
                    if args_sl != -1 && sublist_length(args_sl) >= 1 {
                        let inner = infer_type(sublist_get(args_sl, 0))
                        return make_result_type(TYPE_UNKNOWN, inner)
                    }
                    return make_result_type(TYPE_UNKNOWN, TYPE_UNKNOWN)
                }
                if is_builtin_fn(fn_name) != 0 {
                    return get_builtin_fn_ret(fn_name)
                }
                if is_variant_name(fn_name) != 0 {
                    return get_variant_enum_tid(fn_name)
                }
                let sig = lookup_fnsig(fn_name)
                if sig != -1 {
                    let args_sl = np_args.get(node).unwrap()
                    let mut arg_count = 0
                    if args_sl != -1 {
                        arg_count = sublist_length(args_sl)
                    }
                    let expected = fnsig_params_count.get(sig).unwrap()
                    if arg_count != expected {
                        tc_error_at("function '{fn_name}' expects {expected} argument(s), got {arg_count}", node)
                    }
                    let tp_count = fnsig_type_params_count.get(sig).unwrap()
                    if tp_count > 0 {
                        return instantiate_return_type(sig, args_sl)
                    }
                    return fnsig_ret.get(sig).unwrap()
                }
            } else if callee_kind == NodeKind.FieldAccess {
                let obj = np_obj.get(callee).unwrap()
                if obj != -1 && np_kind.get(obj).unwrap() == NodeKind.Ident {
                    let type_name = np_name.get(obj).unwrap()
                    let tid = lookup_named_type(type_name)
                    if tid != -1 { return tid }
                }
            }
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.MethodCall {
        let obj_node = np_obj.get(node).unwrap()
        let method = np_method.get(node).unwrap()
        let obj_t = infer_type(obj_node)
        let obj_k = type_kind(obj_t)

        if obj_k == TK_LIST {
            if method == "len" || method == "count" { return TYPE_INT }
            if method == "get" { return make_option_type(ty_inner1.get(obj_t).unwrap()) }
            if method == "push" || method == "set" || method == "pop" || method == "for_each" { return TYPE_VOID }
            if method == "map" || method == "filter" || method == "take" || method == "skip" || method == "collect" {
                return obj_t
            }
            if method == "contains" || method == "any" || method == "all" || method == "is_empty" { return TYPE_BOOL }
            if method == "find" { return make_option_type(ty_inner1.get(obj_t).unwrap()) }
            if method == "fold" {
                let args_sl = np_args.get(node).unwrap()
                if args_sl != -1 && sublist_length(args_sl) >= 1 {
                    return infer_type(sublist_get(args_sl, 0))
                }
                return TYPE_UNKNOWN
            }
        }

        if obj_k == TK_STR {
            if method == "len" { return TYPE_INT }
            if method == "contains" || method == "starts_with" || method == "ends_with" { return TYPE_BOOL }
            if method == "substring" || method == "concat" || method == "trim" || method == "to_lower" || method == "to_upper" || method == "replace" || method == "slice" {
                return TYPE_STR
            }
            if method == "char_at" || method == "index_of" || method == "to_int" { return TYPE_INT }
            if method == "split" { return make_list_type(TYPE_STR) }
        }

        if obj_k == TK_INT {
            if method == "to_str" { return TYPE_STR }
            if method == "abs" || method == "min" || method == "max" { return TYPE_INT }
        }

        if obj_k == TK_OPTION {
            if method == "unwrap" { return ty_inner1.get(obj_t).unwrap() }
            if method == "is_some" || method == "is_none" { return TYPE_BOOL }
        }

        if obj_k == TK_RESULT {
            if method == "unwrap" { return ty_inner1.get(obj_t).unwrap() }
            if method == "unwrap_err" { return ty_inner2.get(obj_t).unwrap() }
            if method == "is_ok" || method == "is_err" { return TYPE_BOOL }
        }

        if obj_k == TK_MAP {
            if method == "len" { return TYPE_INT }
            if method == "has" || method == "remove" { return TYPE_INT }
            if method == "set" { return TYPE_VOID }
            if method == "get" { return ty_inner2.get(obj_t).unwrap() }
            if method == "keys" { return make_list_type(ty_inner1.get(obj_t).unwrap()) }
            if method == "values" { return make_list_type(ty_inner2.get(obj_t).unwrap()) }
        }

        if obj_k == TK_BYTES {
            if method == "len" { return TYPE_INT }
            if method == "get" { return make_option_type(TYPE_INT) }
            if method == "is_empty" { return TYPE_BOOL }
            if method == "push" || method == "set" { return TYPE_VOID }
            if method == "slice" || method == "concat" { return obj_t }
            if method == "to_str" { return make_result_type(TYPE_STR, TYPE_STR) }
            if method == "to_hex" { return TYPE_STR }
        }

        if obj_k == TK_STRUCT || obj_k == TK_ENUM {
            let tname = ty_name.get(obj_t).unwrap()
            let sig_name = "{tname}_{method}"
            let sig = lookup_fnsig(sig_name)
            if sig != -1 {
                return fnsig_ret.get(sig).unwrap()
            }
        }

        return TYPE_UNKNOWN
    }

    if kind == NodeKind.FieldAccess {
        let obj_node = np_obj.get(node).unwrap()
        let fname = np_name.get(node).unwrap()
        if obj_node == -1 { return TYPE_UNKNOWN }

        if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
            let obj_name = np_name.get(obj_node).unwrap()
            let tid = lookup_named_type(obj_name)
            if tid != -1 && type_kind(tid) == TK_ENUM {
                return tid
            }
        }

        let obj_t = infer_type(obj_node)
        if type_kind(obj_t) == TK_STRUCT {
            let ft = get_struct_field_tid(obj_t, fname)
            if ft != -1 { return ft }
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.IndexExpr {
        let obj_t = infer_type(np_obj.get(node).unwrap())
        if type_kind(obj_t) == TK_LIST {
            return ty_inner1.get(obj_t).unwrap()
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 && sublist_length(elems_sl) > 0 {
            let first_t = infer_type(sublist_get(elems_sl, 0))
            return make_list_type(first_t)
        }
        return make_list_type(TYPE_UNKNOWN)
    }

    if kind == NodeKind.StructLit {
        let sname = np_type_name.get(node).unwrap()
        if sname != "" {
            let tid = lookup_named_type(sname)
            if tid != -1 { return tid }
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.TupleLit {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut elem_types: List[Int] = []
            let mut i = 0
            while i < sublist_length(elems_sl) {
                elem_types.push(infer_type(sublist_get(elems_sl, i)))
                i = i + 1
            }
            return make_tuple_type(elem_types)
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.IfExpr {
        let cond_t = infer_type(np_condition.get(node).unwrap())
        if is_bool_compat(cond_t) == 0 {
            tc_error_at("if condition must be Bool, got {type_to_str(cond_t)}", node)
        }
        let then_t = infer_type(np_then_body.get(node).unwrap())
        let else_node = np_else_body.get(node).unwrap()
        if else_node != -1 {
            let else_t = infer_type(else_node)
            if then_t != TYPE_UNKNOWN && else_t != TYPE_UNKNOWN {
                if types_compatible(then_t, else_t) == 0 {
                    tc_error_at("if branches have incompatible types: {type_to_str(then_t)} vs {type_to_str(else_t)}", node)
                }
            }
            if then_t != TYPE_UNKNOWN { return then_t }
            return else_t
        }
        return then_t
    }

    if kind == NodeKind.MatchExpr {
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 && sublist_length(arms_sl) > 0 {
            let first_arm = sublist_get(arms_sl, 0)
            return infer_type(np_body.get(first_arm).unwrap())
        }
        return TYPE_UNKNOWN
    }

    if kind == NodeKind.Block {
        let stmts_sl = np_stmts.get(node).unwrap()
        if stmts_sl != -1 && sublist_length(stmts_sl) > 0 {
            let last = sublist_get(stmts_sl, sublist_length(stmts_sl) - 1)
            let last_k = np_kind.get(last).unwrap()
            if last_k == NodeKind.ExprStmt {
                return infer_type(np_value.get(last).unwrap())
            }
            if last_k == NodeKind.Return {
                return infer_type(np_value.get(last).unwrap())
            }
            if last_k == NodeKind.IfExpr || last_k == NodeKind.MatchExpr || last_k == NodeKind.Call || last_k == NodeKind.MethodCall || last_k == NodeKind.Ident || last_k == NodeKind.IntLit || last_k == NodeKind.FloatLit || last_k == NodeKind.BoolLit || last_k == NodeKind.InterpString || last_k == NodeKind.BinOp || last_k == NodeKind.UnaryOp {
                return infer_type(last)
            }
        }
        return TYPE_VOID
    }

    if kind == NodeKind.RangeLit {
        return make_list_type(TYPE_INT)
    }

    if kind == NodeKind.Closure {
        return TYPE_UNKNOWN
    }

    TYPE_UNKNOWN
}

// ── Phase 2: Type check function bodies ─────────────────────────────

pub fn resolve_param_type(p: Int) -> Int ! TypeCheck.Resolve {
    let ptype_str = np_type_name.get(p).unwrap()
    let ptype_ann = np_type_ann.get(p).unwrap()
    if ptype_ann != -1 {
        return resolve_type_ann(ptype_ann)
    }
    if ptype_str != "" {
        let t = resolve_type_name(ptype_str)
        if t != -1 { return t }
    }
    TYPE_UNKNOWN
}

pub fn tc_check_fn(fn_node: Int) ! TypeCheck.Resolve, TypeCheck.Report, Diag.Report {
    nr_push_scope()
    let fn_name = np_name.get(fn_node).unwrap()
    let prev_fn_name = tc_current_fn_name
    let prev_fn_ret = tc_current_fn_ret
    tc_current_fn_name = fn_name
    let sig = lookup_fnsig(fn_name)
    if sig != -1 {
        tc_current_fn_ret = fnsig_ret.get(sig).unwrap()
    }

    let params_sl = np_params.get(fn_node).unwrap()
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p).unwrap()
            let ptid = resolve_param_type(p)
            nr_define_typed(pname, 0, ptid)
            i = i + 1
        }
    }

    let body = np_body.get(fn_node).unwrap()
    if body != -1 {
        tc_check_body(body)

        if sig != -1 {
            let declared_ret = fnsig_ret.get(sig).unwrap()
            if declared_ret != TYPE_VOID && declared_ret != TYPE_UNKNOWN {
                let inferred_ret = infer_type(body)
                if inferred_ret != TYPE_UNKNOWN {
                    if types_compatible(declared_ret, inferred_ret) == 0 {
                        tc_error_at("function '{fn_name}' declared return type {type_to_str(declared_ret)} but body returns {type_to_str(inferred_ret)}", fn_node)
                    }
                }
            }
        }
    }
    tc_current_fn_name = prev_fn_name
    tc_current_fn_ret = prev_fn_ret
    nr_pop_scope()
}

pub fn tc_check_body(node: Int) ! TypeCheck.Resolve, TypeCheck.Report, Diag.Report {
    if node == -1 { return }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.Block {
        nr_push_scope()
        let stmts_sl = np_stmts.get(node).unwrap()
        if stmts_sl != -1 {
            let mut i = 0
            while i < sublist_length(stmts_sl) {
                tc_check_body(sublist_get(stmts_sl, i))
                i = i + 1
            }
        }
        nr_pop_scope()
        return
    }

    if kind == NodeKind.LetBinding {
        let vname = np_name.get(node).unwrap()
        let val = np_value.get(node).unwrap()
        let is_mut = np_is_mut.get(node).unwrap()

        let type_str = np_type_name.get(node).unwrap()
        let type_ann = np_type_ann.get(node).unwrap()
        let mut declared_tid = TYPE_UNKNOWN
        if type_ann != -1 {
            declared_tid = resolve_type_ann(type_ann)
        } else if type_str != "" {
            let rt = resolve_type_name(type_str)
            if rt != -1 {
                declared_tid = rt
            }
        }

        let mut inferred_tid = TYPE_UNKNOWN
        if val != -1 {
            inferred_tid = infer_type(val)
            tc_check_body(val)
        }

        if declared_tid != TYPE_UNKNOWN && inferred_tid != TYPE_UNKNOWN {
            if types_compatible(declared_tid, inferred_tid) == 0 {
                tc_error_at("variable '{vname}': declared type {type_to_str(declared_tid)} but got {type_to_str(inferred_tid)}", node)
            }
        }

        let mut final_tid = declared_tid
        if final_tid == TYPE_UNKNOWN {
            final_tid = inferred_tid
        }
        nr_define_typed(vname, is_mut, final_tid)
        return
    }

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        let target = np_target.get(node).unwrap()
        let val = np_value.get(node).unwrap()
        if target != -1 && val != -1 {
            let target_t = infer_type(target)
            let val_t = infer_type(val)
            if target_t != TYPE_UNKNOWN && val_t != TYPE_UNKNOWN {
                if types_compatible(target_t, val_t) == 0 {
                    tc_error_at("assignment: cannot assign {type_to_str(val_t)} to {type_to_str(target_t)}", node)
                }
            }
        }
        return
    }

    if kind == NodeKind.IfExpr {
        let cond_t = infer_type(np_condition.get(node).unwrap())
        if is_bool_compat(cond_t) == 0 {
            tc_error_at("if condition must be Bool, got {type_to_str(cond_t)}", node)
        }
        tc_check_body(np_then_body.get(node).unwrap())
        tc_check_body(np_else_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WhileLoop {
        let cond_t = infer_type(np_condition.get(node).unwrap())
        if is_bool_compat(cond_t) == 0 {
            tc_error_at("while condition must be Bool, got {type_to_str(cond_t)}", node)
        }
        tc_check_body(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.ForIn {
        nr_push_scope()
        let iter_t = infer_type(np_iterable.get(node).unwrap())
        let mut elem_t = TYPE_UNKNOWN
        if type_kind(iter_t) == TK_LIST {
            elem_t = ty_inner1.get(iter_t).unwrap()
        }
        nr_define_typed(np_var_name.get(node).unwrap(), 0, elem_t)
        tc_check_body(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.MatchExpr {
        tc_check_body(np_scrutinee.get(node).unwrap())
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 {
            let mut i = 0
            while i < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, i)
                nr_push_scope()
                tc_check_pattern_types(np_pattern.get(arm).unwrap())
                tc_check_body(np_body.get(arm).unwrap())
                nr_pop_scope()
                i = i + 1
            }

            let mut has_wildcard = 0
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                let pat = np_pattern.get(arm).unwrap()
                if pat != -1 {
                    let pk = np_kind.get(pat).unwrap()
                    if pk == NodeKind.WildcardPattern || pk == NodeKind.IdentPattern {
                        has_wildcard = 1
                    }
                }
                ai = ai + 1
            }
            if has_wildcard == 0 {
                tc_warn("match expression may not be exhaustive (no wildcard or catch-all arm)")
            }
        }
        return
    }

    if kind == NodeKind.LoopExpr {
        tc_check_body(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WithBlock {
        tc_check_body(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WithResource {
        nr_push_scope()
        nr_define(np_name.get(node).unwrap())
        tc_check_body(np_value.get(node).unwrap())
        tc_check_body(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.AsyncScope {
        tc_check_body(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.AsyncSpawn {
        tc_check_body(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.Closure {
        nr_push_scope()
        let params_sl = np_params.get(node).unwrap()
        if params_sl != -1 {
            let mut i = 0
            while i < sublist_length(params_sl) {
                let p = sublist_get(params_sl, i)
                let pname = np_name.get(p).unwrap()
                let ptid = resolve_param_type(p)
                nr_define_typed(pname, 0, ptid)
                i = i + 1
            }
        }
        tc_check_body(np_body.get(node).unwrap())
        nr_pop_scope()
        return
    }

    if kind == NodeKind.ExprStmt {
        let val = np_value.get(node).unwrap()
        if val != -1 {
            infer_type(val)
        }
        return
    }

    if kind == NodeKind.Return {
        let val = np_value.get(node).unwrap()
        if val != -1 {
            infer_type(val)
        }
        return
    }

    let _skip = 0
}

pub fn tc_check_pattern_types(node: Int) ! TypeCheck.Resolve {
    if node == -1 { return }
    let kind = np_kind.get(node).unwrap()
    if kind == NodeKind.IdentPattern {
        let name = np_name.get(node).unwrap()
        if name != "_" {
            nr_define(name)
        }
        return
    }
    if kind == NodeKind.EnumPattern {
        let flds_sl = np_fields.get(node).unwrap()
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                tc_check_pattern_types(sublist_get(flds_sl, i))
                i = i + 1
            }
        }
        return
    }
    if kind == NodeKind.StructPattern {
        let flds_sl = np_fields.get(node).unwrap()
        if flds_sl != -1 {
            let mut i = 0
            while i < sublist_length(flds_sl) {
                nr_define(np_name.get(sublist_get(flds_sl, i)).unwrap())
                i = i + 1
            }
        }
        return
    }
    if kind == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                tc_check_pattern_types(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }
    if kind == NodeKind.ListPattern {
        let elems_sl = np_elements.get(node).unwrap()
        if elems_sl != -1 {
            let mut i = 0
            while i < sublist_length(elems_sl) {
                tc_check_pattern_types(sublist_get(elems_sl, i))
                i = i + 1
            }
        }
        return
    }
    if kind == NodeKind.OrPattern {
        tc_check_pattern_types(np_left.get(node).unwrap())
        tc_check_pattern_types(np_right.get(node).unwrap())
        return
    }
    if kind == NodeKind.AsPattern {
        tc_check_pattern_types(np_pattern.get(node).unwrap())
        nr_define(np_name.get(node).unwrap())
        return
    }
    let _skip = 0
}

// ── Phase 2: Top-level driver ───────────────────────────────────────

pub fn tc_infer_program(program: Int) ! TypeCheck.Resolve, TypeCheck.Report, Diag.Report {
    nr_scope_names = []
    nr_scope_muts = []
    nr_scope_types = []
    nr_scope_frames = []
    nr_push_scope()

    // Register top-level let bindings
    let lets_sl = np_stmts.get(program).unwrap()
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let l = sublist_get(lets_sl, i)
            nr_define(np_name.get(l).unwrap())
            i = i + 1
        }
    }

    // Register function names
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            nr_define(np_name.get(sublist_get(fns_sl, i)).unwrap())
            i = i + 1
        }
    }

    // Type check each function body (skip unaffected when incremental filter active)
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            if tc_should_check_fn(np_name.get(fn_node).unwrap()) != 0 {
                tc_check_fn(fn_node)
            }
            i = i + 1
        }
    }

    // Type check impl methods (skip unaffected when incremental filter active)
    let impls_sl = np_methods.get(program).unwrap()
    if impls_sl != -1 {
        let mut i = 0
        while i < sublist_length(impls_sl) {
            let im = sublist_get(impls_sl, i)
            let impl_type = np_name.get(im).unwrap()
            let methods_sl = np_methods.get(im).unwrap()
            if methods_sl != -1 {
                let mut j = 0
                while j < sublist_length(methods_sl) {
                    let m = sublist_get(methods_sl, j)
                    let orig_name = np_name.get(m).unwrap()
                    let qualified = "{impl_type}_{orig_name}"
                    if tc_should_check_fn(qualified) != 0 {
                        np_name.set(m, qualified)
                        tc_check_fn(m)
                        np_name.set(m, orig_name)
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    nr_pop_scope()
}

// ── Debug / introspection ───────────────────────────────────────────

pub fn type_to_str(tid: Int) -> Str {
    if tid < 0 || tid >= ty_kind.len() {
        return "<?>"
    }
    let k = ty_kind.get(tid).unwrap()
    let name = ty_name.get(tid).unwrap()

    if k == TK_INT { return "Int" }
    if k == TK_FLOAT { return "Float" }
    if k == TK_BOOL { return "Bool" }
    if k == TK_STR { return "Str" }
    if k == TK_VOID { return "Void" }
    if k == TK_UNKNOWN { return "?" }
    if k == TK_TYPEVAR { return name }
    if k == TK_STRUCT { return name }
    if k == TK_ENUM { return name }

    if k == TK_LIST {
        let inner = ty_inner1.get(tid).unwrap()
        return "List[{type_to_str(inner)}]"
    }
    if k == TK_OPTION {
        let inner = ty_inner1.get(tid).unwrap()
        return "Option[{type_to_str(inner)}]"
    }
    if k == TK_RESULT {
        let ok_t = ty_inner1.get(tid).unwrap()
        let err_t = ty_inner2.get(tid).unwrap()
        return "Result[{type_to_str(ok_t)}, {type_to_str(err_t)}]"
    }
    if k == TK_MAP {
        let key_t = ty_inner1.get(tid).unwrap()
        let val_t = ty_inner2.get(tid).unwrap()
        return "Map[{type_to_str(key_t)}, {type_to_str(val_t)}]"
    }
    if k == TK_BYTES {
        return "Bytes"
    }
    if k == TK_FN {
        let ret = ty_inner1.get(tid).unwrap()
        let start = ty_params_start.get(tid).unwrap()
        let count = ty_params_count.get(tid).unwrap()
        let mut params = ""
        let mut i = 0
        while i < count {
            if i > 0 {
                params = params.concat(", ")
            }
            params = params.concat(type_to_str(ty_param_list.get(start + i).unwrap()))
            i = i + 1
        }
        return "Fn({params}) -> {type_to_str(ret)}"
    }
    if k == TK_TUPLE {
        let start = ty_params_start.get(tid).unwrap()
        let count = ty_params_count.get(tid).unwrap()
        let mut elems = ""
        let mut i = 0
        while i < count {
            if i > 0 {
                elems = elems.concat(", ")
            }
            elems = elems.concat(type_to_str(ty_param_list.get(start + i).unwrap()))
            i = i + 1
        }
        return "({elems})"
    }

    name
}
