import tokens
import ast
import parser

// codegen.pact — Self-hosting C code generator for Pact
//
// Minimal subset: enough to compile hello_compiled.pact via the
// Python C backend. Reads the parallel-array AST node pool produced
// by parser.pact and emits C source as a list of strings.
//
// Constraints: same as lexer/parser — parallel arrays, no struct-in-list,
// no closures, no imports. Constants duplicated for self-contained compilation.

// ── C type constants ────────────────────────────────────────────────
// Instead of enums, plain ints.

pub let CT_INT = 0
pub let CT_FLOAT = 1
pub let CT_BOOL = 2
pub let CT_STRING = 3
pub let CT_LIST = 4
pub let CT_VOID = 5
pub let CT_CLOSURE = 6
pub let CT_OPTION = 7
pub let CT_RESULT = 8


// ── Codegen state ───────────────────────────────────────────────────

pub let mut cg_lines: List[Str] = []
pub let mut cg_indent: Int = 0
pub let mut cg_temp_counter: Int = 0
pub let mut cg_global_inits: List[Str] = []
pub let mut struct_reg_names: List[Str] = []
pub let mut enum_reg_names: List[Str] = []
pub let mut enum_reg_variant_names: List[Str] = []
pub let mut enum_reg_variant_enum_idx: List[Int] = []
pub let mut var_enum_names: List[Str] = []
pub let mut var_enum_types: List[Str] = []
pub let mut fn_enum_ret_names: List[Str] = []
pub let mut fn_enum_ret_types: List[Str] = []
pub let mut emitted_let_names: List[Str] = []
pub let mut emitted_fn_names: List[Str] = []
pub let mut cg_closure_defs: List[Str] = []
pub let mut cg_closure_counter: Int = 0

// Capture analysis: per-closure capture info (flat list with start/count indexes)
pub let mut closure_capture_names: List[Str] = []
pub let mut closure_capture_types: List[Int] = []
pub let mut closure_capture_muts: List[Int] = []
pub let mut closure_capture_starts: List[Int] = []
pub let mut closure_capture_counts: List[Int] = []

// Active closure context: set while emitting a closure body, -1 otherwise
pub let mut cg_closure_cap_start: Int = -1
pub let mut cg_closure_cap_count: Int = 0

// Variables in the outer scope that are heap-boxed because a closure captures them mutably
pub let mut mut_captured_vars: List[Str] = []

// Trait registry: maps trait name -> method names
pub let mut trait_reg_names: List[Str] = []
pub let mut trait_reg_method_sl: List[Int] = []

// Impl registry: maps (trait, type) -> method FnDef nodes
pub let mut impl_reg_trait: List[Str] = []
pub let mut impl_reg_type: List[Str] = []
pub let mut impl_reg_methods_sl: List[Int] = []

// From impl registry: (source_type, target_type) -> methods sublist
pub let mut from_reg_source: List[Str] = []
pub let mut from_reg_target: List[Str] = []
pub let mut from_reg_method_sl: List[Int] = []

// Variable-to-struct-type tracking (for method resolution)
pub let mut var_struct_names: List[Str] = []
pub let mut var_struct_types: List[Str] = []

// Struct field type registry: (struct_name, field_name) -> field C type
pub let mut sf_reg_struct: List[Str] = []
pub let mut sf_reg_field: List[Str] = []
pub let mut sf_reg_type: List[Int] = []
pub let mut sf_reg_stype: List[Str] = []

// Closure-typed variable tracking: (name) -> C function pointer signature
pub let mut var_closure_names: List[Str] = []
pub let mut var_closure_sigs: List[Str] = []

// Generic function definition registry: fn_name -> fn_node for generic fns
pub let mut generic_fn_names: List[Str] = []
pub let mut generic_fn_nodes: List[Int] = []

// Mono function instances to emit: (base_fn_name, concrete_args)
pub let mut mono_fn_bases: List[Str] = []
pub let mut mono_fn_args: List[Str] = []

// Generic monomorphic instance registry
pub let mut mono_base_names: List[Str] = []
pub let mut mono_concrete_args: List[Str] = []
pub let mut mono_c_names: List[Str] = []

// Option/Result type tracking
pub let mut var_option_names: List[Str] = []
pub let mut var_option_inner: List[Int] = []
pub let mut var_result_names: List[Str] = []
pub let mut var_result_ok: List[Int] = []
pub let mut var_result_err: List[Int] = []
pub let mut emitted_option_types: List[Int] = []
pub let mut emitted_result_types: List[Str] = []

// Assignment context for .into() type inference
pub let mut cg_let_target_type: Int = 0

// Scope: parallel lists for variable names, types, and mutability.
// Each scope is a "frame" delimited by frame_starts.
pub let mut scope_names: List[Str] = []
pub let mut scope_types: List[Int] = []
pub let mut scope_muts: List[Int] = []
pub let mut scope_frame_starts: List[Int] = []

// Function registry: parallel lists (fn name -> return type, param count)
pub let mut fn_reg_names: List[Str] = []
pub let mut fn_reg_ret: List[Int] = []
pub let mut fn_reg_effect_sl: List[Int] = []

// Effect registry: name -> parent index (-1 = top-level)
pub let mut effect_reg_names: List[Str] = []
pub let mut effect_reg_parent: List[Int] = []

// Current function being emitted (for effect propagation checking)
pub let mut cg_current_fn_name: Str = ""

pub let mut var_list_elem_names: List[Str] = []
pub let mut var_list_elem_types: List[Int] = []

// Scratch space for tuple match scrutinee temps
pub let mut cg_program_node: Int = 0

pub let mut match_scrut_strs: List[Str] = []
pub let mut match_scrut_types: List[Int] = []
pub let mut match_scrut_enum: Str = ""

pub fn push_scope() {
    scope_frame_starts.push(scope_names.len())
}

pub fn pop_scope() {
    let start = scope_frame_starts.get(scope_frame_starts.len() - 1)
    scope_frame_starts.pop()
    while scope_names.len() > start {
        scope_names.pop()
        scope_types.pop()
        scope_muts.pop()
    }
}

pub fn set_var(name: Str, ctype: Int, is_mut: Int) {
    scope_names.push(name)
    scope_types.push(ctype)
    scope_muts.push(is_mut)
}

pub fn get_var_type(name: Str) -> Int {
    let mut i = scope_names.len() - 1
    while i >= 0 {
        if scope_names.get(i) == name {
            return scope_types.get(i)
        }
        i = i - 1
    }
    CT_INT
}

pub fn get_var_mut(name: Str) -> Int {
    let mut i = scope_names.len() - 1
    while i >= 0 {
        if scope_names.get(i) == name {
            return scope_muts.get(i)
        }
        i = i - 1
    }
    0
}

pub fn is_mut_captured(name: Str) -> Int {
    let mut i = 0
    while i < mut_captured_vars.len() {
        if mut_captured_vars.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_capture_index(name: Str) -> Int {
    if cg_closure_cap_start < 0 {
        return -1
    }
    let mut i = 0
    while i < cg_closure_cap_count {
        if closure_capture_names.get(cg_closure_cap_start + i) == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn capture_cast_expr(idx: Int) -> Str {
    let ct = closure_capture_types.get(cg_closure_cap_start + idx)
    if ct == CT_INT {
        "(int64_t)(intptr_t)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_FLOAT {
        "*(double*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_STRING {
        "(const char*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_BOOL {
        "(int)(intptr_t)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_LIST {
        "(pact_list*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_CLOSURE {
        "(pact_closure*)pact_closure_get_capture(__self, {idx})"
    } else {
        "pact_closure_get_capture(__self, {idx})"
    }
}

pub fn reg_fn(name: Str, ret: Int) {
    fn_reg_names.push(name)
    fn_reg_ret.push(ret)
    fn_reg_effect_sl.push(-1)
}

pub fn reg_fn_with_effects(name: Str, ret: Int, effects_sl: Int) {
    fn_reg_names.push(name)
    fn_reg_ret.push(ret)
    fn_reg_effect_sl.push(effects_sl)
}

pub fn get_fn_effect_sl(name: Str) -> Int {
    let mut i = 0
    while i < fn_reg_names.len() {
        if fn_reg_names.get(i) == name {
            return fn_reg_effect_sl.get(i)
        }
        i = i + 1
    }
    -1
}

pub fn reg_effect(name: Str, parent: Int) -> Int {
    let idx = effect_reg_names.len()
    effect_reg_names.push(name)
    effect_reg_parent.push(parent)
    idx
}

pub fn get_effect_idx(name: Str) -> Int {
    let mut i = 0
    while i < effect_reg_names.len() {
        if effect_reg_names.get(i) == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn effect_satisfies(caller_effect: Str, callee_effect: Str) -> Int {
    if caller_effect == callee_effect {
        return 1
    }
    let callee_idx = get_effect_idx(callee_effect)
    if callee_idx == -1 {
        return 0
    }
    let parent_idx = effect_reg_parent.get(callee_idx)
    if parent_idx == -1 {
        return 0
    }
    let parent_name = effect_reg_names.get(parent_idx)
    if parent_name == caller_effect {
        return 1
    }
    0
}

pub fn check_effect_propagation(callee_name: Str) {
    if cg_current_fn_name == "main" {
        return
    }
    let callee_sl = get_fn_effect_sl(callee_name)
    if callee_sl == -1 {
        return
    }
    let callee_count = sublist_length(callee_sl)
    if callee_count == 0 {
        return
    }
    let caller_sl = get_fn_effect_sl(cg_current_fn_name)
    let mut ci = 0
    while ci < callee_count {
        let callee_eff_node = sublist_get(callee_sl, ci)
        let callee_eff = np_name.get(callee_eff_node)
        let mut satisfied = 0
        if caller_sl != -1 {
            let caller_count = sublist_length(caller_sl)
            let mut ki = 0
            while ki < caller_count {
                let caller_eff_node = sublist_get(caller_sl, ki)
                let caller_eff = np_name.get(caller_eff_node)
                if effect_satisfies(caller_eff, callee_eff) != 0 {
                    satisfied = 1
                }
                ki = ki + 1
            }
        }
        if satisfied == 0 {
            io.println("error E0500: function '{callee_name}' requires effect '{callee_eff}' but caller '{cg_current_fn_name}' does not declare it")
        }
        ci = ci + 1
    }
}

pub fn init_builtin_effects() {
    let io_idx = reg_effect("IO", -1)
    reg_effect("IO.Print", io_idx)
    reg_effect("IO.Log", io_idx)
    let fs_idx = reg_effect("FS", -1)
    reg_effect("FS.Read", fs_idx)
    reg_effect("FS.Write", fs_idx)
    reg_effect("FS.Delete", fs_idx)
    reg_effect("FS.Watch", fs_idx)
    let net_idx = reg_effect("Net", -1)
    reg_effect("Net.Connect", net_idx)
    reg_effect("Net.Listen", net_idx)
    reg_effect("Net.DNS", net_idx)
    let db_idx = reg_effect("DB", -1)
    reg_effect("DB.Read", db_idx)
    reg_effect("DB.Write", db_idx)
    reg_effect("DB.Admin", db_idx)
    let env_idx = reg_effect("Env", -1)
    reg_effect("Env.Read", env_idx)
    reg_effect("Env.Write", env_idx)
    let time_idx = reg_effect("Time", -1)
    reg_effect("Time.Read", time_idx)
    reg_effect("Time.Sleep", time_idx)
    reg_effect("Rand", -1)
    let crypto_idx = reg_effect("Crypto", -1)
    reg_effect("Crypto.Hash", crypto_idx)
    reg_effect("Crypto.Sign", crypto_idx)
    reg_effect("Crypto.Encrypt", crypto_idx)
    reg_effect("Crypto.Decrypt", crypto_idx)
    let proc_idx = reg_effect("Process", -1)
    reg_effect("Process.Spawn", proc_idx)
    reg_effect("Process.Signal", proc_idx)
}

pub fn get_fn_ret(name: Str) -> Int {
    let mut i = 0
    while i < fn_reg_names.len() {
        if fn_reg_names.get(i) == name {
            return fn_reg_ret.get(i)
        }
        i = i + 1
    }
    CT_VOID
}

pub fn set_list_elem_type(name: Str, elem_type: Int) {
    var_list_elem_names.push(name)
    var_list_elem_types.push(elem_type)
}

pub fn get_list_elem_type(name: Str) -> Int {
    let mut i = 0
    while i < var_list_elem_names.len() {
        if var_list_elem_names.get(i) == name {
            return var_list_elem_types.get(i)
        }
        i = i + 1
    }
    CT_INT
}

pub fn is_struct_type(name: Str) -> Int {
    let mut i = 0
    while i < struct_reg_names.len() {
        if struct_reg_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_enum_type(name: Str) -> Int {
    let mut i = 0
    while i < enum_reg_names.len() {
        if enum_reg_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn resolve_variant(name: Str) -> Str {
    let mut i = 0
    while i < enum_reg_variant_names.len() {
        if enum_reg_variant_names.get(i) == name {
            return enum_reg_names.get(enum_reg_variant_enum_idx.get(i))
        }
        i = i + 1
    }
    ""
}

pub fn get_var_enum(name: Str) -> Str {
    let mut i = 0
    while i < var_enum_names.len() {
        if var_enum_names.get(i) == name {
            return var_enum_types.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn get_fn_enum_ret(name: Str) -> Str {
    let mut i = 0
    while i < fn_enum_ret_names.len() {
        if fn_enum_ret_names.get(i) == name {
            return fn_enum_ret_types.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn set_var_struct(name: Str, type_name: Str) {
    var_struct_names.push(name)
    var_struct_types.push(type_name)
}

pub fn get_var_struct(name: Str) -> Str {
    let mut i = 0
    while i < var_struct_names.len() {
        if var_struct_names.get(i) == name {
            return var_struct_types.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn get_struct_field_type(sname: Str, fname: Str) -> Int {
    let mut i = 0
    while i < sf_reg_struct.len() {
        if sf_reg_struct.get(i) == sname && sf_reg_field.get(i) == fname {
            return sf_reg_type.get(i)
        }
        i = i + 1
    }
    CT_VOID
}

pub fn get_struct_field_stype(sname: Str, fname: Str) -> Str {
    let mut i = 0
    while i < sf_reg_struct.len() {
        if sf_reg_struct.get(i) == sname && sf_reg_field.get(i) == fname {
            return sf_reg_stype.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn set_var_closure(name: Str, sig: Str) {
    var_closure_names.push(name)
    var_closure_sigs.push(sig)
}

pub fn get_var_closure_sig(name: Str) -> Str {
    let mut i = 0
    while i < var_closure_names.len() {
        if var_closure_names.get(i) == name {
            return var_closure_sigs.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn build_closure_sig_from_type_ann(ta: Int) -> Str {
    let ret_name = np_return_type.get(ta)
    let ret_type = type_from_name(ret_name)
    let elems_sl = np_elements.get(ta)
    let mut sig_params = "pact_closure*"
    if elems_sl != -1 && sublist_length(elems_sl) > 0 {
        let mut i = 0
        while i < sublist_length(elems_sl) {
            let elem = sublist_get(elems_sl, i)
            let ename = np_name.get(elem)
            sig_params = sig_params.concat(", ")
            if is_enum_type(ename) != 0 {
                sig_params = sig_params.concat("pact_{ename}")
            } else if is_struct_type(ename) != 0 {
                sig_params = sig_params.concat("pact_{ename}")
            } else {
                sig_params = sig_params.concat(c_type_str(type_from_name(ename)))
            }
            i = i + 1
        }
    }
    "{c_type_str(ret_type)}(*)({sig_params})"
}

pub fn is_generic_fn(name: Str) -> Int {
    let mut i = 0
    while i < generic_fn_names.len() {
        if generic_fn_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_generic_fn_node(name: Str) -> Int {
    let mut i = 0
    while i < generic_fn_names.len() {
        if generic_fn_names.get(i) == name {
            return generic_fn_nodes.get(i)
        }
        i = i + 1
    }
    -1
}

pub fn register_mono_fn(base: Str, args: Str) {
    let mut i = 0
    while i < mono_fn_bases.len() {
        if mono_fn_bases.get(i) == base && mono_fn_args.get(i) == args {
            return
        }
        i = i + 1
    }
    mono_fn_bases.push(base)
    mono_fn_args.push(args)
}

pub fn infer_fn_type_args_from_types(fn_node: Int, arg_types: List[Int]) -> Str {
    let tparams_sl = np_type_params.get(fn_node)
    if tparams_sl == -1 {
        return ""
    }
    let num_params = sublist_length(tparams_sl)
    if num_params == 0 {
        return ""
    }
    let fn_params_sl = np_params.get(fn_node)
    if fn_params_sl == -1 {
        return ""
    }
    let mut args = ""
    let mut pi = 0
    while pi < num_params {
        let param_name = np_name.get(sublist_get(tparams_sl, pi))
        let mut resolved = "Void"
        let mut fi = 0
        while fi < sublist_length(fn_params_sl) && fi < arg_types.len() {
            let p = sublist_get(fn_params_sl, fi)
            let ptype = np_type_name.get(p)
            if ptype == param_name {
                resolved = type_name_from_ct(arg_types.get(fi))
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

pub fn type_name_from_ct(ct: Int) -> Str {
    if ct == CT_INT { "Int" }
    else if ct == CT_FLOAT { "Float" }
    else if ct == CT_BOOL { "Bool" }
    else if ct == CT_STRING { "Str" }
    else if ct == CT_LIST { "List" }
    else { "Void" }
}

pub fn mangle_generic_name(base: Str, args: Str) -> Str {
    let mut result = base
    let mut i = 0
    let mut seg_start = 0
    while i <= args.len() {
        if i == args.len() || args.char_at(i) == 44 {
            let seg = args.substr(seg_start, i - seg_start)
            result = result.concat("_").concat(seg)
            seg_start = i + 1
        }
        i = i + 1
    }
    result
}

pub fn register_mono_instance(base: Str, args: Str) -> Str {
    let existing = lookup_mono_instance(base, args)
    if existing != "" {
        return existing
    }
    let c_name = mangle_generic_name(base, args)
    mono_base_names.push(base)
    mono_concrete_args.push(args)
    mono_c_names.push(c_name)
    c_name
}

pub fn lookup_mono_instance(base: Str, args: Str) -> Str {
    let mut i = 0
    while i < mono_base_names.len() {
        if mono_base_names.get(i) == base && mono_concrete_args.get(i) == args {
            return mono_c_names.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn is_trait_type(name: Str) -> Int {
    let mut i = 0
    while i < trait_reg_names.len() {
        if trait_reg_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn lookup_impl_method(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_reg_type.len() {
        if impl_reg_type.get(i) == type_name {
            let methods_sl = impl_reg_methods_sl.get(i)
            let mut j = 0
            while j < sublist_length(methods_sl) {
                let m = sublist_get(methods_sl, j)
                if np_name.get(m) == method {
                    return 1
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    0
}

pub fn lookup_impl_type_for_trait(trait_name: Str, type_name: Str) -> Int {
    let mut i = 0
    while i < impl_reg_trait.len() {
        if impl_reg_trait.get(i) == trait_name && impl_reg_type.get(i) == type_name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_impl_method_ret(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_reg_type.len() {
        if impl_reg_type.get(i) == type_name {
            let methods_sl = impl_reg_methods_sl.get(i)
            let mut j = 0
            while j < sublist_length(methods_sl) {
                let m = sublist_get(methods_sl, j)
                if np_name.get(m) == method {
                    let ret_str = np_return_type.get(m)
                    return type_from_name(ret_str)
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    CT_VOID
}

pub fn find_from_impl(source: Str, target: Str) -> Int {
    let mut i = 0
    while i < from_reg_source.len() {
        if from_reg_source.get(i) == source && from_reg_target.get(i) == target {
            return from_reg_method_sl.get(i)
        }
        i = i + 1
    }
    -1
}

pub fn impl_method_has_self(fn_node: Int) -> Int {
    let params_sl = np_params.get(fn_node)
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            if np_name.get(p) == "self" {
                return 1
            }
            i = i + 1
        }
    }
    0
}

pub fn resolve_self_type(ret_str: Str, impl_type: Str) -> Str {
    if ret_str == "Self" {
        return impl_type
    }
    ret_str
}

pub fn is_emitted_let(name: Str) -> Int {
    let mut i = 0
    while i < emitted_let_names.len() {
        if emitted_let_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_emitted_fn(name: Str) -> Int {
    let mut i = 0
    while i < emitted_fn_names.len() {
        if emitted_fn_names.get(i) == name {
            return 1
        }
        i = i + 1
    }
    0
}

// ── Helpers ─────────────────────────────────────────────────────────

pub fn c_type_str(ct: Int) -> Str {
    if ct == CT_INT { "int64_t" }
    else if ct == CT_FLOAT { "double" }
    else if ct == CT_BOOL { "int" }
    else if ct == CT_STRING { "const char*" }
    else if ct == CT_LIST { "pact_list*" }
    else if ct == CT_CLOSURE { "pact_closure*" }
    else { "void" }
}

pub fn type_from_name(name: Str) -> Int {
    match name {
        "Int" => CT_INT
        "Str" => CT_STRING
        "Float" => CT_FLOAT
        "Bool" => CT_BOOL
        "List" => CT_LIST
        "Option" => CT_OPTION
        "Result" => CT_RESULT
        _ => CT_VOID
    }
}

pub fn option_c_type(inner: Int) -> Str {
    "pact_Option_{c_type_tag(inner)}"
}

pub fn result_c_type(ok_t: Int, err_t: Int) -> Str {
    "pact_Result_{c_type_tag(ok_t)}_{c_type_tag(err_t)}"
}

pub fn c_type_tag(ct: Int) -> Str {
    if ct == CT_INT { "int" }
    else if ct == CT_FLOAT { "double" }
    else if ct == CT_BOOL { "bool" }
    else if ct == CT_STRING { "str" }
    else if ct == CT_LIST { "list" }
    else { "void" }
}

pub fn ensure_option_type(inner: Int) {
    let mut i = 0
    while i < emitted_option_types.len() {
        if emitted_option_types.get(i) == inner {
            return
        }
        i = i + 1
    }
    emitted_option_types.push(inner)
}

pub fn ensure_result_type(ok_t: Int, err_t: Int) {
    let key = "{ok_t}_{err_t}"
    let mut i = 0
    while i < emitted_result_types.len() {
        if emitted_result_types.get(i) == key {
            return
        }
        i = i + 1
    }
    emitted_result_types.push(key)
}

pub fn set_var_option(name: Str, inner: Int) {
    var_option_names.push(name)
    var_option_inner.push(inner)
}

pub fn get_var_option_inner(name: Str) -> Int {
    let mut i = var_option_names.len() - 1
    while i >= 0 {
        if var_option_names.get(i) == name {
            return var_option_inner.get(i)
        }
        i = i - 1
    }
    -1
}

pub fn set_var_result(name: Str, ok_t: Int, err_t: Int) {
    var_result_names.push(name)
    var_result_ok.push(ok_t)
    var_result_err.push(err_t)
}

pub fn get_var_result_ok(name: Str) -> Int {
    let mut i = var_result_names.len() - 1
    while i >= 0 {
        if var_result_names.get(i) == name {
            return var_result_ok.get(i)
        }
        i = i - 1
    }
    -1
}

pub fn get_var_result_err(name: Str) -> Int {
    let mut i = var_result_names.len() - 1
    while i >= 0 {
        if var_result_names.get(i) == name {
            return var_result_err.get(i)
        }
        i = i - 1
    }
    -1
}

pub fn emit_option_typedef(inner: Int) {
    let tag = c_type_tag(inner)
    let tname = "pact_Option_{tag}"
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ int tag; {c_inner} value; } {tname};")
    emit_line("")
}

pub fn emit_result_typedef(ok_t: Int, err_t: Int) {
    let ok_tag = c_type_tag(ok_t)
    let err_tag = c_type_tag(err_t)
    let tname = "pact_Result_{ok_tag}_{err_tag}"
    let c_ok = c_type_str(ok_t)
    let c_err = c_type_str(err_t)
    emit_line("typedef struct \{ int tag; union \{ {c_ok} ok; {c_err} err; }; } {tname};")
    emit_line("")
}

pub fn emit_all_option_result_types() {
    let mut i = 0
    while i < emitted_option_types.len() {
        emit_option_typedef(emitted_option_types.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_result_types.len() {
        let key = emitted_result_types.get(i)
        let mut sep = 0
        let mut j = 0
        while j < key.len() {
            if key.char_at(j) == 95 {
                sep = j
            }
            j = j + 1
        }
        let ok_str = key.substring(0, sep)
        let err_str = key.substring(sep + 1, key.len() - sep - 1)
        let mut ok_t = CT_INT
        let mut err_t = CT_INT
        if ok_str == "0" { ok_t = CT_INT }
        else if ok_str == "1" { ok_t = CT_FLOAT }
        else if ok_str == "2" { ok_t = CT_BOOL }
        else if ok_str == "3" { ok_t = CT_STRING }
        else if ok_str == "4" { ok_t = CT_LIST }
        if err_str == "0" { err_t = CT_INT }
        else if err_str == "1" { err_t = CT_FLOAT }
        else if err_str == "2" { err_t = CT_BOOL }
        else if err_str == "3" { err_t = CT_STRING }
        else if err_str == "4" { err_t = CT_LIST }
        emit_result_typedef(ok_t, err_t)
        i = i + 1
    }
}

pub fn fresh_temp(prefix: Str) -> Str {
    let n = cg_temp_counter
    cg_temp_counter = cg_temp_counter + 1
    "{prefix}{n}"
}

pub fn emit_line(line: Str) {
    if line == "" {
        cg_lines.push("")
    } else {
        let mut pad = ""
        let mut i = 0
        while i < cg_indent {
            pad = pad.concat("    ")
            i = i + 1
        }
        cg_lines.push(pad.concat(line))
    }
}

pub fn join_lines() -> Str {
    let mut result = ""
    let mut i = 0
    while i < cg_lines.len() {
        if i > 0 {
            result = result.concat("\n")
        }
        result = result.concat(cg_lines.get(i))
        i = i + 1
    }
    result
}

// ── Expression codegen ──────────────────────────────────────────────
// Returns (expr_str, type) packed into parallel result slots.
// Since we can't return tuples in the C backend, we use mutable globals.

pub let mut expr_result_str: Str = ""
pub let mut expr_result_type: Int = 0
pub let mut expr_closure_sig: Str = ""
pub let mut expr_option_inner: Int = -1
pub let mut expr_result_ok_type: Int = -1
pub let mut expr_result_err_type: Int = -1

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
        let variant_enum = resolve_variant(name)
        if variant_enum != "" {
            expr_result_str = "pact_{variant_enum}_{name}"
            expr_result_type = CT_INT
            return
        }
        let cap_idx = get_capture_index(name)
        if cap_idx >= 0 {
            expr_result_str = capture_cast_expr(cap_idx)
            expr_result_type = closure_capture_types.get(cg_closure_cap_start + cap_idx)
            return
        }
        if is_mut_captured(name) != 0 {
            expr_result_str = "(*{name}_cell)"
            expr_result_type = get_var_type(name)
            return
        }
        expr_result_str = name
        expr_result_type = get_var_type(name)
        if expr_result_type == CT_OPTION {
            expr_option_inner = get_var_option_inner(name)
        }
        if expr_result_type == CT_RESULT {
            expr_result_ok_type = get_var_result_ok(name)
            expr_result_err_type = get_var_result_err(name)
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

    expr_result_str = "0"
    expr_result_type = CT_VOID
}

pub fn emit_binop(node: Int) {
    let op = np_op.get(node)
    if op == "??" {
        emit_expr(np_left.get(node))
        let left_str = expr_result_str
        let left_type = expr_result_type
        let opt_inner = expr_option_inner
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
            let rok = expr_result_ok_type
            let rerr = expr_result_err_type
            let res_c = result_c_type(rok, rerr)
            emit_line("{res_c} {tmp} = {operand_str};")
            emit_line("if ({tmp}.tag == 1) return ({res_c})\{.tag = 1, .err = {tmp}.err};")
            expr_result_str = "{tmp}.ok"
            expr_result_type = rok
        } else {
            emit_line("int64_t {tmp} = (int64_t){operand_str};")
            expr_result_str = "{tmp}"
            expr_result_type = operand_type
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
        expr_result_str = "pact_{fn_name}({args_str})"
        expr_result_type = get_fn_ret(fn_name)
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
        let tgt_name = type_name_from_ct(target)
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
            if val_type == CT_INT {
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
            if elem_type == CT_STRING {
                expr_result_str = "(const char*)pact_list_get({obj_str}, {idx_str})"
                expr_result_type = CT_STRING
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
            if val_type2 == CT_INT {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*)(intptr_t){val_str2});")
            } else {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){val_str2});")
            }
            expr_result_str = "0"
            expr_result_type = CT_VOID
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
    if elems_sl != -1 {
        let mut i = 0
        while i < sublist_length(elems_sl) {
            emit_expr(sublist_get(elems_sl, i))
            let e_str = expr_result_str
            let e_type = expr_result_type
            if e_type == CT_INT {
                emit_line("pact_list_push({tmp}, (void*)(intptr_t){e_str});")
            } else {
                emit_line("pact_list_push({tmp}, (void*){e_str});")
            }
            i = i + 1
        }
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
    while i < scope_names.len() {
        if scope_names.get(i) == name {
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
        while fi < fn_reg_names.len() {
            if fn_reg_names.get(fi) == name {
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

pub fn emit_closure(node: Int) {
    let closure_idx = cg_closure_counter
    let cname = "__closure_{closure_idx}"
    cg_closure_counter = cg_closure_counter + 1

    let params_sl = np_params.get(node)
    let ret_str = np_return_type.get(node)
    let ret_type = type_from_name(ret_str)

    // Capture analysis: find free variables before switching codegen context
    let captures = analyze_captures(np_body.get(node), params_sl)
    let cap_start = closure_capture_names.len()
    let mut cap_i = 0
    while cap_i < captures.len() {
        closure_capture_names.push(captures.get(cap_i))
        cap_i = cap_i + 1
    }
    cap_i = 0
    while cap_i < captures.len() {
        let cname_lookup = closure_capture_names.get(cap_start + cap_i)
        let cap_ct = get_var_type(cname_lookup)
        closure_capture_types.push(cap_ct)
        cap_i = cap_i + 1
    }
    closure_capture_starts.push(cap_start)
    closure_capture_counts.push(captures.len())

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
                    var_enum_names.push(pname)
                    var_enum_types.push(ptype)
                }
            }
            i = i + 1
        }
    }

    emit_line("static {c_type_str(ret_type)} {cname}({params_c}) \{")
    cg_indent = cg_indent + 1
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
            let cap_name = closure_capture_names.get(cap_start + ci2)
            let cap_type = closure_capture_types.get(cap_start + ci2)
            if cap_type == CT_INT {
                emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_name};")
            } else if cap_type == CT_FLOAT {
                emit_line("\{double* __fp_{closure_idx}_{ci2} = (double*)pact_alloc(sizeof(double)); *__fp_{closure_idx}_{ci2} = {cap_name}; {caps_var}[{ci2}] = (void*)__fp_{closure_idx}_{ci2};}")
            } else if cap_type == CT_BOOL {
                emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_name};")
            } else {
                emit_line("{caps_var}[{ci2}] = (void*){cap_name};")
            }
            ci2 = ci2 + 1
        }
        expr_result_str = "pact_closure_new((void*){cname}, {caps_var}, {captures.len()})"
    } else {
        expr_result_str = "pact_closure_new((void*){cname}, NULL, 0)"
    }
    expr_result_type = CT_CLOSURE
}

pub fn emit_if_expr(node: Int) {
    let tmp = fresh_temp("_if_")
    // Infer type from then branch
    let then_type = infer_block_type(np_then_body.get(node))
    emit_line("{c_type_str(then_type)} {tmp};")
    emit_expr(np_condition.get(node))
    let cond_str = expr_result_str
    emit_line("if ({cond_str}) \{")
    cg_indent = cg_indent + 1
    let then_val = emit_block_value(np_then_body.get(node))
    emit_line("{tmp} = {then_val};")
    cg_indent = cg_indent - 1
    if np_else_body.get(node) != -1 {
        emit_line("} else \{")
        cg_indent = cg_indent + 1
        let else_val = emit_block_value(np_else_body.get(node))
        emit_line("{tmp} = {else_val};")
        cg_indent = cg_indent - 1
    }
    emit_line("}")
    set_var(tmp, then_type, 1)
    expr_result_str = tmp
    expr_result_type = then_type
}

pub fn emit_match_expr(node: Int) {
    let scrut = np_scrutinee.get(node)

    // Build list of scrutinee values (multiple if tuple literal)
    match_scrut_strs = []
    match_scrut_types = []
    match_scrut_enum = ""

    if np_kind.get(scrut) == NodeKind.TupleLit {
        let elems_sl = np_elements.get(scrut)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                emit_expr(sublist_get(elems_sl, ei))
                let tmp = fresh_temp("_tup_")
                emit_line("{c_type_str(expr_result_type)} {tmp} = {expr_result_str};")
                set_var(tmp, expr_result_type, 1)
                match_scrut_strs.push(tmp)
                match_scrut_types.push(expr_result_type)
                ei = ei + 1
            }
        }
    } else {
        if np_kind.get(scrut) == NodeKind.Ident {
            match_scrut_enum = get_var_enum(np_name.get(scrut))
        } else if np_kind.get(scrut) == NodeKind.FieldAccess {
            match_scrut_enum = infer_enum_from_node(scrut)
        }
        emit_expr(scrut)
        match_scrut_strs.push(expr_result_str)
        match_scrut_types.push(expr_result_type)
    }

    let arms_sl = np_arms.get(node)
    if arms_sl == -1 {
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    let first_arm = sublist_get(arms_sl, 0)
    let result_type = infer_arm_type(first_arm)
    let result_var = fresh_temp("_match_")
    emit_line("{c_type_str(result_type)} {result_var};")

    let mut has_guards = 0
    let mut gi = 0
    while gi < sublist_length(arms_sl) {
        if np_guard.get(sublist_get(arms_sl, gi)) != -1 {
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
        let arm = sublist_get(arms_sl, i)
        let pat = np_pattern.get(arm)

        let pat_cond = pattern_condition(pat, 0, match_scrut_strs.len())
        let guard_node = np_guard.get(arm)
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
            bind_pattern_vars(pat, 0, match_scrut_strs.len())
            if guard_node != -1 {
                emit_expr(guard_node)
                let guard_str = expr_result_str
                emit_line("if ({guard_str}) \{")
                cg_indent = cg_indent + 1
                let arm_val = emit_arm_value(np_body.get(arm))
                emit_line("{result_var} = {arm_val};")
                emit_line("_mg_ = 1;")
                cg_indent = cg_indent - 1
                emit_line("}")
            } else {
                let arm_val = emit_arm_value(np_body.get(arm))
                emit_line("{result_var} = {arm_val};")
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
            bind_pattern_vars(pat, 0, match_scrut_strs.len())
            let arm_val = emit_arm_value(np_body.get(arm))
            emit_line("{result_var} = {arm_val};")
            cg_indent = cg_indent - 1
        }

        first = 0
        i = i + 1
    }
    emit_line("}")
    set_var(result_var, result_type, 1)
    expr_result_str = result_var
    expr_result_type = result_type
}

// Build a C condition string for a pattern.
// scrut_off/scrut_len index into match_scrut_strs/match_scrut_types.
// Returns "" when the pattern always matches (wildcard/ident).
pub fn pattern_condition(pat: Int, scrut_off: Int, scrut_len: Int) -> Str {
    let pk = np_kind.get(pat)
    if pk == NodeKind.WildcardPattern {
        return ""
    }
    if pk == NodeKind.IdentPattern {
        let pat_name = np_name.get(pat)
        let mut enum_name = match_scrut_enum
        if enum_name == "" {
            enum_name = resolve_variant(pat_name)
        }
        if enum_name != "" {
            return "({match_scrut_strs.get(scrut_off)} == pact_{enum_name}_{pat_name})"
        }
        return ""
    }
    if pk == NodeKind.IntPattern {
        let pat_val = np_str_val.get(pat)
        return "({match_scrut_strs.get(scrut_off)} == {pat_val})"
    }
    if pk == NodeKind.StringPattern {
        let pat_val = np_str_val.get(pat)
        return "(pact_str_eq({match_scrut_strs.get(scrut_off)}, \"{pat_val}\"))"
    }
    if pk == NodeKind.RangePattern {
        let lo = np_str_val.get(pat)
        let hi = np_name.get(pat)
        let scrut = match_scrut_strs.get(scrut_off)
        if np_inclusive.get(pat) != 0 {
            return "({scrut} >= {lo} && {scrut} <= {hi})"
        }
        return "({scrut} >= {lo} && {scrut} < {hi})"
    }
    if pk == NodeKind.EnumPattern {
        let enum_name = np_name.get(pat)
        let variant_name = np_type_name.get(pat)
        if variant_name != "" {
            return "({match_scrut_strs.get(scrut_off)} == pact_{enum_name}_{variant_name})"
        }
        return ""
    }
    if pk == NodeKind.StructPattern {
        let flds_sl = np_fields.get(pat)
        if flds_sl == -1 {
            return ""
        }
        let mut parts = ""
        let mut parts_n = 0
        let scrut = match_scrut_strs.get(scrut_off)
        let mut j = 0
        while j < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, j)
            let fname = np_name.get(sf)
            let fpat = np_pattern.get(sf)
            if fpat != -1 {
                let saved_strs = match_scrut_strs
                let saved_types = match_scrut_types
                match_scrut_strs = ["{scrut}.{fname}"]
                match_scrut_types = [CT_VOID]
                let sub_cond = pattern_condition(fpat, 0, 1)
                match_scrut_strs = saved_strs
                match_scrut_types = saved_types
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
        let alts_sl = np_elements.get(pat)
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
        let inner = np_pattern.get(pat)
        return pattern_condition(inner, scrut_off, scrut_len)
    }
    if pk == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(pat)
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
    ""
}

// Emit C variable bindings for ident sub-patterns within a pattern.
// scrut_off/scrut_len index into match_scrut_strs/match_scrut_types.
pub fn bind_pattern_vars(pat: Int, scrut_off: Int, scrut_len: Int) {
    let pk = np_kind.get(pat)
    if pk == NodeKind.EnumPattern {
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
        let alts_sl = np_elements.get(pat)
        if alts_sl != -1 && sublist_length(alts_sl) > 0 {
            bind_pattern_vars(sublist_get(alts_sl, 0), scrut_off, scrut_len)
        }
        return
    }
    if pk == NodeKind.StructPattern {
        let flds_sl = np_fields.get(pat)
        if flds_sl == -1 {
            return
        }
        let scrut = match_scrut_strs.get(scrut_off)
        let stype_name = np_type_name.get(pat)
        let mut j = 0
        while j < sublist_length(flds_sl) {
            let sf = sublist_get(flds_sl, j)
            let fname = np_name.get(sf)
            let fpat = np_pattern.get(sf)
            if fpat != -1 {
                let saved_strs = match_scrut_strs
                let saved_types = match_scrut_types
                match_scrut_strs = ["{scrut}.{fname}"]
                match_scrut_types = [CT_VOID]
                bind_pattern_vars(fpat, 0, 1)
                match_scrut_strs = saved_strs
                match_scrut_types = saved_types
            } else {
                emit_line("__typeof__({scrut}.{fname}) {fname} = {scrut}.{fname};")
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
        let bind_name = np_name.get(pat)
        let st = match_scrut_types.get(scrut_off)
        let scrut_str = match_scrut_strs.get(scrut_off)
        if match_scrut_enum != "" {
            emit_line("pact_{match_scrut_enum} {bind_name} = {scrut_str};")
            set_var(bind_name, CT_INT, 1)
            var_enum_names.push(bind_name)
            var_enum_types.push(match_scrut_enum)
        } else {
            emit_line("{c_type_str(st)} {bind_name} = {scrut_str};")
            set_var(bind_name, st, 1)
        }
        bind_pattern_vars(np_pattern.get(pat), scrut_off, scrut_len)
        return
    }
    if pk == NodeKind.IdentPattern {
        let bind_name = np_name.get(pat)
        let mut enum_name = match_scrut_enum
        if enum_name == "" {
            enum_name = resolve_variant(bind_name)
        }
        if enum_name != "" {
            return
        }
        if scrut_len == 1 {
            let st = match_scrut_types.get(scrut_off)
            emit_line("{c_type_str(st)} {bind_name} = {match_scrut_strs.get(scrut_off)};")
            set_var(bind_name, st, 1)
        }
        return
    }
    if pk == NodeKind.TuplePattern {
        let elems_sl = np_elements.get(pat)
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
}

pub fn emit_block_expr(node: Int) {
    let stmts_sl = np_stmts.get(node)
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
        let last_kind = np_kind.get(last)
        if last_kind == NodeKind.ExprStmt {
            emit_expr(np_value.get(last))
            return
        }
        emit_stmt(last)
    }
    expr_result_str = "0"
    expr_result_type = CT_VOID
}

pub fn emit_arm_value(body: Int) -> Str {
    if body == -1 {
        return "0"
    }
    let kind = np_kind.get(body)
    if kind == NodeKind.Block {
        return emit_block_value(body)
    }
    if kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(body))
        return expr_result_str
    }
    emit_expr(body)
    expr_result_str
}

pub fn emit_block_value(block: Int) -> Str {
    if block == -1 {
        return "0"
    }
    let stmts_sl = np_stmts.get(block)
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
    let last_kind = np_kind.get(last)
    if last_kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(last))
        return expr_result_str
    }
    if last_kind == NodeKind.IfExpr {
        emit_if_expr(last)
        return expr_result_str
    }
    if last_kind == NodeKind.Return {
        if np_value.get(last) != -1 {
            emit_expr(np_value.get(last))
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
    let stmts_sl = np_stmts.get(block)
    if stmts_sl == -1 {
        return CT_VOID
    }
    let count = sublist_length(stmts_sl)
    if count == 0 {
        return CT_VOID
    }
    let last = sublist_get(stmts_sl, count - 1)
    let last_kind = np_kind.get(last)
    if last_kind == NodeKind.ExprStmt {
        return infer_expr_type(np_value.get(last))
    }
    CT_VOID
}

pub fn infer_arm_type(arm: Int) -> Int {
    let body = np_body.get(arm)
    if body == -1 {
        return CT_VOID
    }
    let kind = np_kind.get(body)
    if kind == NodeKind.Block {
        return infer_block_type(body)
    }
    if kind == NodeKind.ExprStmt {
        return infer_expr_type(np_value.get(body))
    }
    infer_expr_type(body)
}

pub fn infer_expr_type(node: Int) -> Int {
    if node == -1 {
        return CT_VOID
    }
    let kind = np_kind.get(node)
    if kind == NodeKind.IntLit { return CT_INT }
    if kind == NodeKind.FloatLit { return CT_FLOAT }
    if kind == NodeKind.BoolLit { return CT_BOOL }
    if kind == NodeKind.InterpString { return CT_STRING }
    if kind == NodeKind.ListLit { return CT_LIST }
    if kind == NodeKind.Ident {
        let iname = np_name.get(node)
        if resolve_variant(iname) != "" {
            return CT_INT
        }
        return get_var_type(iname)
    }
    if kind == NodeKind.FieldAccess {
        let fa_obj = np_obj.get(node)
        let fa_field = np_name.get(node)
        if np_kind.get(fa_obj) == NodeKind.Ident {
            let obj_name = np_name.get(fa_obj)
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
        return infer_block_type(np_then_body.get(node))
    }
    if kind == NodeKind.Call {
        let func_node = np_left.get(node)
        if np_kind.get(func_node) == NodeKind.Ident {
            return get_fn_ret(np_name.get(func_node))
        }
    }
    if kind == NodeKind.BinOp {
        let op = np_op.get(node)
        if op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||" {
            return CT_BOOL
        }
        return infer_expr_type(np_left.get(node))
    }
    CT_VOID
}

// ── Statement codegen ───────────────────────────────────────────────

pub fn emit_stmt(node: Int) {
    let kind = np_kind.get(node)

    if kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(node))
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
        emit_expr(np_target.get(node))
        let target_str = expr_result_str
        emit_expr(np_value.get(node))
        let val_str = expr_result_str
        emit_line("{target_str} = {val_str};")
        return
    }

    if kind == NodeKind.CompoundAssign {
        emit_expr(np_target.get(node))
        let target_str = expr_result_str
        emit_expr(np_value.get(node))
        let val_str = expr_result_str
        let op = np_op.get(node)
        emit_line("{target_str} {op}= {val_str};")
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
        return
    }

    if kind == NodeKind.ForIn {
        emit_for_in(node)
        return
    }

    if kind == NodeKind.WhileLoop {
        emit_expr(np_condition.get(node))
        let cond_str = expr_result_str
        emit_line("while ({cond_str}) \{")
        cg_indent = cg_indent + 1
        emit_block(np_body.get(node))
        cg_indent = cg_indent - 1
        emit_line("}")
        return
    }

    if kind == NodeKind.LoopExpr {
        emit_line("while (1) \{")
        cg_indent = cg_indent + 1
        emit_block(np_body.get(node))
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
    let vk = np_kind.get(val_node)
    if vk == NodeKind.FieldAccess {
        let obj = np_obj.get(val_node)
        if np_kind.get(obj) == NodeKind.Ident {
            let obj_name = np_name.get(obj)
            if is_enum_type(obj_name) != 0 {
                return obj_name
            }
        }
    }
    if vk == NodeKind.Ident {
        return resolve_variant(np_name.get(val_node))
    }
    ""
}

pub fn emit_let_binding(node: Int) {
    let val_node = np_value.get(node)
    let mut enum_type = infer_enum_from_node(val_node)
    let type_ann = np_target.get(node)
    if enum_type == "" && type_ann != -1 {
        let ann_name = np_name.get(type_ann)
        if is_enum_type(ann_name) != 0 {
            enum_type = ann_name
        }
    }
    let saved_let_target = cg_let_target_type
    if type_ann != -1 {
        cg_let_target_type = type_from_name(np_name.get(type_ann))
    } else {
        cg_let_target_type = 0
    }
    emit_expr(val_node)
    cg_let_target_type = saved_let_target
    let val_str = expr_result_str
    let val_type = expr_result_type
    let name = np_name.get(node)
    let is_mut = np_is_mut.get(node)
    set_var(name, val_type, is_mut)
    if enum_type != "" {
        var_enum_names.push(name)
        var_enum_types.push(enum_type)
    }
    if val_type == CT_CLOSURE {
        set_var_closure(name, expr_closure_sig)
    }
    if val_type == CT_OPTION {
        set_var_option(name, expr_option_inner)
    }
    if val_type == CT_RESULT {
        set_var_result(name, expr_result_ok_type, expr_result_err_type)
    }
    if np_kind.get(val_node) == NodeKind.StructLit {
        let expr_struct = get_var_struct(val_str)
        if expr_struct != "" {
            set_var_struct(name, expr_struct)
        } else {
            let sname = np_type_name.get(val_node)
            if is_struct_type(sname) != 0 {
                set_var_struct(name, sname)
            }
        }
    } else if type_ann != -1 {
        let ann_name = np_name.get(type_ann)
        if is_struct_type(ann_name) != 0 {
            set_var_struct(name, ann_name)
        }
    } else {
        let expr_struct = get_var_struct(val_str)
        if expr_struct != "" {
            set_var_struct(name, expr_struct)
        }
    }
    if val_type == CT_LIST && type_ann != -1 {
        let ann_name = np_name.get(type_ann)
        if ann_name == "List" {
            let elems_sl = np_elements.get(type_ann)
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                let elem_ann = sublist_get(elems_sl, 0)
                let elem_name = np_name.get(elem_ann)
                set_list_elem_type(name, type_from_name(elem_name))
            }
        }
    }
    let struct_type = get_var_struct(name)
    if val_type == CT_OPTION {
        let opt_inner = get_var_option_inner(name)
        let opt_c = option_c_type(opt_inner)
        if is_mut != 0 {
            emit_line("{opt_c} {name} = {val_str};")
        } else {
            emit_line("const {opt_c} {name} = {val_str};")
        }
    } else if val_type == CT_RESULT {
        let rok = get_var_result_ok(name)
        let rerr = get_var_result_err(name)
        let res_c = result_c_type(rok, rerr)
        if is_mut != 0 {
            emit_line("{res_c} {name} = {val_str};")
        } else {
            emit_line("const {res_c} {name} = {val_str};")
        }
    } else if enum_type != "" {
        if is_mut != 0 {
            emit_line("pact_{enum_type} {name} = {val_str};")
        } else {
            emit_line("const pact_{enum_type} {name} = {val_str};")
        }
    } else if struct_type != "" {
        if is_mut != 0 {
            emit_line("pact_{struct_type} {name} = {val_str};")
        } else {
            emit_line("const pact_{struct_type} {name} = {val_str};")
        }
    } else {
        let ts = c_type_str(val_type)
        if is_mut != 0 || val_type == CT_STRING {
            emit_line("{ts} {name} = {val_str};")
        } else {
            emit_line("const {ts} {name} = {val_str};")
        }
    }
}

pub fn emit_for_in(node: Int) {
    let var_name = np_var_name.get(node)
    let iter_node = np_iterable.get(node)
    let iter_kind = np_kind.get(iter_node)

    if iter_kind == NodeKind.RangeLit {
        emit_expr(np_start.get(iter_node))
        let start_str = expr_result_str
        emit_expr(np_end.get(iter_node))
        let end_str = expr_result_str
        let mut op = "<"
        if np_inclusive.get(iter_node) != 0 {
            op = "<="
        }
        emit_line("for (int64_t {var_name} = {start_str}; {var_name} {op} {end_str}; {var_name}++) \{")
        push_scope()
        set_var(var_name, CT_INT, 1)
        cg_indent = cg_indent + 1
        emit_block(np_body.get(node))
        cg_indent = cg_indent - 1
        pop_scope()
        emit_line("}")
    } else {
        emit_expr(iter_node)
        let iter_str = expr_result_str
        let iter_type = expr_result_type
        if iter_type == CT_LIST {
            let idx = fresh_temp("_i")
            emit_line("for (int64_t {idx} = 0; {idx} < pact_list_len({iter_str}); {idx}++) \{")
            push_scope()
            emit_line("    int64_t {var_name} = (int64_t)(intptr_t)pact_list_get({iter_str}, {idx});")
            set_var(var_name, CT_INT, 0)
            cg_indent = cg_indent + 1
            emit_block(np_body.get(node))
            cg_indent = cg_indent - 1
            pop_scope()
            emit_line("}")
        } else {
            emit_line("/* unsupported iterable */")
        }
    }
}

pub fn emit_if_stmt(node: Int) {
    emit_expr(np_condition.get(node))
    let cond_str = expr_result_str
    emit_line("if ({cond_str}) \{")
    cg_indent = cg_indent + 1
    emit_block(np_then_body.get(node))
    cg_indent = cg_indent - 1
    if np_else_body.get(node) != -1 {
        let else_b = np_else_body.get(node)
        let else_stmts = np_stmts.get(else_b)
        // Check for else-if chain
        if else_stmts != -1 && sublist_length(else_stmts) == 1 {
            let inner = sublist_get(else_stmts, 0)
            if np_kind.get(inner) == NodeKind.IfExpr {
                let saved_lines2 = cg_lines
                cg_lines = []
                emit_expr(np_condition.get(inner))
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
                    emit_block(np_then_body.get(inner))
                    cg_indent = cg_indent - 1
                    if np_else_body.get(inner) != -1 {
                        emit_line("} else \{")
                        cg_indent = cg_indent + 1
                        emit_block(np_else_body.get(inner))
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

pub fn emit_block(block: Int) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
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

pub fn emit_with_block(node: Int) {
    let handlers_sl = np_handlers.get(node)
    let body = np_body.get(node)
    if handlers_sl == -1 {
        emit_block(body)
        return
    }
    let count = sublist_length(handlers_sl)
    let mut resource_names: List[Str] = []
    let mut resource_vars: List[Str] = []
    emit_line("\{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < count {
        let item = sublist_get(handlers_sl, i)
        let item_kind = np_kind.get(item)
        if item_kind == NodeKind.WithResource {
            let binding = np_name.get(item)
            let res_expr = np_value.get(item)
            emit_expr(res_expr)
            let res_str = expr_result_str
            let tmp = fresh_temp("_wr_")
            emit_line("int64_t {tmp} = {res_str};")
            emitted_let_names.push(binding)
            emit_line("int64_t {binding} = {tmp};")
            resource_names.push(binding)
            resource_vars.push(tmp)
        } else {
            emit_expr(item)
            let handler_str = expr_result_str
            if handler_str != "" {
                emit_line("{handler_str};")
            }
        }
        i = i + 1
    }
    emit_block(body)
    let mut ri = resource_names.len() - 1
    while ri >= 0 {
        let rname = resource_names.get(ri)
        emit_line("// close resource: {rname}")
        emit_line("/* {rname}.close() -- Closeable trait call */")
        ri = ri - 1
    }
    cg_indent = cg_indent - 1
    emit_line("}")
}

// ── Function codegen ────────────────────────────────────────────────

pub fn format_params(fn_node: Int) -> Str {
    let params_sl = np_params.get(fn_node)
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
        let pname = np_name.get(p)
        let ptype = np_type_name.get(p)
        if i > 0 {
            result = result.concat(", ")
        }
        if ptype == "Fn" {
            result = result.concat("pact_closure* {pname}")
        } else if is_enum_type(ptype) != 0 {
            result = result.concat("pact_{ptype} {pname}")
        } else if is_struct_type(ptype) != 0 {
            result = result.concat("pact_{ptype} {pname}")
        } else {
            let ct = type_from_name(ptype)
            result = result.concat("{c_type_str(ct)} {pname}")
        }
        i = i + 1
    }
    result
}

pub fn format_impl_params(fn_node: Int, impl_type: Str) -> Str {
    let params_sl = np_params.get(fn_node)
    let has_self = impl_method_has_self(fn_node)
    let mut result = ""
    if has_self != 0 {
        result = "pact_{impl_type} self"
    }
    let mut first = 1
    if has_self != 0 {
        first = 0
    }
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            if pname != "self" {
                let ptype_raw = np_type_name.get(p)
                let ptype = resolve_self_type(ptype_raw, impl_type)
                if first == 0 {
                    result = result.concat(", ")
                }
                first = 0
                if ptype == "Fn" {
                    result = result.concat("pact_closure* {pname}")
                } else if is_struct_type(ptype) != 0 {
                    result = result.concat("pact_{ptype} {pname}")
                } else if is_enum_type(ptype) != 0 {
                    result = result.concat("pact_{ptype} {pname}")
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

pub fn emit_impl_method_def(fn_node: Int, impl_type: Str) {
    push_scope()
    cg_temp_counter = 0
    let mname = np_name.get(fn_node)
    let mangled = "{impl_type}_{mname}"
    cg_current_fn_name = mangled
    let ret_str_raw = np_return_type.get(fn_node)
    let ret_str = resolve_self_type(ret_str_raw, impl_type)
    let ret_type = type_from_name(ret_str)
    let params = format_impl_params(fn_node, impl_type)
    let enum_ret = get_fn_enum_ret(mangled)
    let mut sig = ""
    if enum_ret != "" {
        sig = "pact_{enum_ret} pact_{mangled}({params})"
    } else if is_struct_type(ret_str) != 0 {
        sig = "pact_{ret_str} pact_{mangled}({params})"
    } else {
        sig = "{c_type_str(ret_type)} pact_{mangled}({params})"
    }

    let has_self = impl_method_has_self(fn_node)
    if has_self != 0 {
        set_var("self", CT_VOID, 0)
        set_var_struct("self", impl_type)
    }

    let params_sl = np_params.get(fn_node)
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            if pname != "self" {
                let ptype_raw = np_type_name.get(p)
                let ptype = resolve_self_type(ptype_raw, impl_type)
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
                        var_enum_names.push(pname)
                        var_enum_types.push(ptype)
                    }
                }
            }
            i = i + 1
        }
    }

    let mut body_ret = ret_type
    if is_struct_type(ret_str) != 0 || is_enum_type(ret_str) != 0 {
        body_ret = CT_INT
    }
    emit_line("{sig} \{")
    cg_indent = cg_indent + 1
    emit_fn_body(np_body.get(fn_node), body_ret)
    cg_indent = cg_indent - 1
    emit_line("}")
    pop_scope()
}

pub fn emit_fn_decl(fn_node: Int) {
    let name = np_name.get(fn_node)
    if name == "main" {
        emit_line("void pact_main(void);")
        return
    }
    let params = format_params(fn_node)
    let enum_ret = get_fn_enum_ret(name)
    if enum_ret != "" {
        emit_line("pact_{enum_ret} pact_{name}({params});")
    } else {
        let ret_str = np_return_type.get(fn_node)
        let ret_type = type_from_name(ret_str)
        emit_line("{c_type_str(ret_type)} pact_{name}({params});")
    }
}

pub fn emit_fn_def(fn_node: Int) {
    push_scope()
    cg_temp_counter = 0
    let name = np_name.get(fn_node)
    cg_current_fn_name = name
    let ret_str = np_return_type.get(fn_node)
    let ret_type = type_from_name(ret_str)
    let mut sig = ""
    if name == "main" {
        sig = "void pact_main(void)"
    } else {
        let params = format_params(fn_node)
        let enum_ret = get_fn_enum_ret(name)
        if enum_ret != "" {
            sig = "pact_{enum_ret} pact_{name}({params})"
        } else {
            sig = "{c_type_str(ret_type)} pact_{name}({params})"
        }
    }

    // Register params in scope
    let params_sl = np_params.get(fn_node)
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
                    var_enum_names.push(pname)
                    var_enum_types.push(ptype)
                }
            }
            i = i + 1
        }
    }

    emit_line("{sig} \{")
    cg_indent = cg_indent + 1
    emit_fn_body(np_body.get(fn_node), ret_type)
    cg_indent = cg_indent - 1
    emit_line("}")
    pop_scope()
}

pub fn emit_fn_body(block: Int, ret_type: Int) {
    if block == -1 {
        return
    }
    let stmts_sl = np_stmts.get(block)
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
    let last_kind = np_kind.get(last)
    if ret_type != CT_VOID && last_kind == NodeKind.ExprStmt {
        emit_expr(np_value.get(last))
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
    let types_sl = np_fields.get(cg_program_node)
    if types_sl == -1 {
        return -1
    }
    let mut i = 0
    while i < sublist_length(types_sl) {
        let td = sublist_get(types_sl, i)
        if np_name.get(td) == name {
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
        if np_name.get(tp) == param_name {
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
    while check < sf_reg_struct.len() {
        if sf_reg_struct.get(check) == mono_name {
            return
        }
        check = check + 1
    }
    let td = find_type_def(base_name)
    if td == -1 {
        return
    }
    let tparams_sl = np_type_params.get(td)
    if tparams_sl == -1 {
        return
    }
    let flds_sl = np_fields.get(td)
    if flds_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f)
        let type_ann_node = np_value.get(f)
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node)
            let resolved = resolve_type_param(type_name, tparams_sl, concrete_args)
            if is_struct_type(resolved) != 0 {
                sf_reg_struct.push(mono_name)
                sf_reg_field.push(fname)
                sf_reg_type.push(CT_VOID)
                sf_reg_stype.push(resolved)
            } else {
                let ct = type_from_name(resolved)
                sf_reg_struct.push(mono_name)
                sf_reg_field.push(fname)
                sf_reg_type.push(ct)
                sf_reg_stype.push("")
            }
        } else {
            sf_reg_struct.push(mono_name)
            sf_reg_field.push(fname)
            sf_reg_type.push(CT_INT)
            sf_reg_stype.push("")
        }
        i = i + 1
    }
}

pub fn emit_mono_struct_typedef(base_name: Str, concrete_args: Str) {
    let td = find_type_def(base_name)
    if td == -1 {
        return
    }
    let tparams_sl = np_type_params.get(td)
    if tparams_sl == -1 {
        return
    }
    let c_name = mangle_generic_name(base_name, concrete_args)
    let flds_sl = np_fields.get(td)
    if flds_sl == -1 {
        return
    }
    struct_reg_names.push(c_name)
    emit_line("typedef struct \{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f)
        let type_ann_node = np_value.get(f)
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node)
            let resolved = resolve_type_param(type_name, tparams_sl, concrete_args)
            if is_struct_type(resolved) != 0 {
                emit_line("pact_{resolved} {fname};")
                sf_reg_struct.push(c_name)
                sf_reg_field.push(fname)
                sf_reg_type.push(CT_VOID)
                sf_reg_stype.push(resolved)
            } else {
                let ct = type_from_name(resolved)
                emit_line("{c_type_str(ct)} {fname};")
                sf_reg_struct.push(c_name)
                sf_reg_field.push(fname)
                sf_reg_type.push(ct)
                sf_reg_stype.push("")
            }
        } else {
            emit_line("int64_t {fname};")
            sf_reg_struct.push(c_name)
            sf_reg_field.push(fname)
            sf_reg_type.push(CT_INT)
            sf_reg_stype.push("")
        }
        i = i + 1
    }
    cg_indent = cg_indent - 1
    emit_line("} pact_{c_name};")
    emit_line("")
}

pub fn emit_all_mono_typedefs() {
    let mut i = 0
    while i < mono_base_names.len() {
        let base = mono_base_names.get(i)
        let args = mono_concrete_args.get(i)
        let td = find_type_def(base)
        if td != -1 {
            let flds_sl = np_fields.get(td)
            if flds_sl != -1 && sublist_length(flds_sl) > 0 {
                if np_kind.get(sublist_get(flds_sl, 0)) != NodeKind.TypeVariant {
                    emit_mono_struct_typedef(base, args)
                }
            }
        }
        i = i + 1
    }
}

pub fn emit_mono_fn_def(fn_node: Int, concrete_args: Str) {
    let base_name = np_name.get(fn_node)
    let mangled = mangle_generic_name(base_name, concrete_args)
    let tparams_sl = np_type_params.get(fn_node)

    // Resolve return type
    let ret_str = np_return_type.get(fn_node)
    let resolved_ret = resolve_type_param(ret_str, tparams_sl, concrete_args)
    let ret_type = type_from_name(resolved_ret)

    // Build parameter string with substituted types
    let params_sl = np_params.get(fn_node)
    let mut params_c = "void"
    if params_sl != -1 && sublist_length(params_sl) > 0 {
        params_c = ""
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            let ptype = np_type_name.get(p)
            let resolved_ptype = resolve_type_param(ptype, tparams_sl, concrete_args)
            if i > 0 {
                params_c = params_c.concat(", ")
            }
            if is_struct_type(resolved_ptype) != 0 {
                params_c = params_c.concat("pact_{resolved_ptype} {pname}")
            } else if is_enum_type(resolved_ptype) != 0 {
                params_c = params_c.concat("pact_{resolved_ptype} {pname}")
            } else {
                let ct = type_from_name(resolved_ptype)
                params_c = params_c.concat("{c_type_str(ct)} {pname}")
            }
            i = i + 1
        }
    }

    // Forward declaration
    emit_line("{c_type_str(ret_type)} pact_{mangled}({params_c});")

    // Register params in scope
    push_scope()
    cg_temp_counter = 0
    if params_sl != -1 {
        let mut i = 0
        while i < sublist_length(params_sl) {
            let p = sublist_get(params_sl, i)
            let pname = np_name.get(p)
            let ptype = np_type_name.get(p)
            let resolved_ptype = resolve_type_param(ptype, tparams_sl, concrete_args)
            set_var(pname, type_from_name(resolved_ptype), 1)
            if is_struct_type(resolved_ptype) != 0 {
                set_var_struct(pname, resolved_ptype)
            }
            if is_enum_type(resolved_ptype) != 0 {
                var_enum_names.push(pname)
                var_enum_types.push(resolved_ptype)
            }
            i = i + 1
        }
    }

    emit_line("{c_type_str(ret_type)} pact_{mangled}({params_c}) \{")
    cg_indent = cg_indent + 1
    emit_fn_body(np_body.get(fn_node), ret_type)
    cg_indent = cg_indent - 1
    emit_line("}")
    emit_line("")
    pop_scope()
}

pub fn emit_all_mono_fns() {
    let mut i = 0
    while i < mono_fn_bases.len() {
        let base = mono_fn_bases.get(i)
        let args = mono_fn_args.get(i)
        let fn_node = get_generic_fn_node(base)
        if fn_node != -1 {
            emit_mono_fn_def(fn_node, args)
        }
        i = i + 1
    }
}

pub fn emit_struct_typedef(td_node: Int) {
    let name = np_name.get(td_node)
    let flds_sl = np_fields.get(td_node)
    if flds_sl == -1 {
        return
    }
    // Check if this is a variant-only type (enum), skip for now
    if sublist_length(flds_sl) > 0 {
        let first = sublist_get(flds_sl, 0)
        if np_kind.get(first) == NodeKind.TypeVariant {
            return
        }
    }
    // Skip generic types — they get monomorphized instances instead
    let tparams_sl = np_type_params.get(td_node)
    if tparams_sl != -1 && sublist_length(tparams_sl) > 0 {
        return
    }
    emit_line("typedef struct \{")
    cg_indent = cg_indent + 1
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let f = sublist_get(flds_sl, i)
        let fname = np_name.get(f)
        let type_ann_node = np_value.get(f)
        if type_ann_node != -1 {
            let type_name = np_name.get(type_ann_node)
            if type_name == name {
                emit_line("int64_t {fname};")
                sf_reg_struct.push(name)
                sf_reg_field.push(fname)
                sf_reg_type.push(CT_INT)
                sf_reg_stype.push("")
            } else if is_struct_type(type_name) != 0 {
                emit_line("pact_{type_name} {fname};")
                sf_reg_struct.push(name)
                sf_reg_field.push(fname)
                sf_reg_type.push(CT_VOID)
                sf_reg_stype.push(type_name)
            } else {
                let ct = type_from_name(type_name)
                emit_line("{c_type_str(ct)} {fname};")
                sf_reg_struct.push(name)
                sf_reg_field.push(fname)
                sf_reg_type.push(ct)
                sf_reg_stype.push("")
            }
        } else {
            emit_line("int64_t {fname};")
            sf_reg_struct.push(name)
            sf_reg_field.push(fname)
            sf_reg_type.push(CT_INT)
            sf_reg_stype.push("")
        }
        i = i + 1
    }
    cg_indent = cg_indent - 1
    emit_line("} pact_{name};")
    emit_line("")
}

pub fn emit_enum_typedef(td_node: Int) {
    let name = np_name.get(td_node)
    let flds_sl = np_fields.get(td_node)
    if flds_sl == -1 {
        return
    }
    let enum_idx = enum_reg_names.len()
    enum_reg_names.push(name)
    let mut variants_str = ""
    let mut i = 0
    while i < sublist_length(flds_sl) {
        let v = sublist_get(flds_sl, i)
        let vname = np_name.get(v)
        enum_reg_variant_names.push(vname)
        enum_reg_variant_enum_idx.push(enum_idx)
        if i > 0 {
            variants_str = variants_str.concat(", ")
        }
        variants_str = variants_str.concat("pact_{name}_{vname}")
        i = i + 1
    }
    emit_line("typedef enum \{ {variants_str} } pact_{name};")
    emit_line("")
}

// ── Top-level: generate ─────────────────────────────────────────────

pub fn emit_top_level_let(node: Int) {
    let saved_lines = cg_lines
    cg_lines = []
    emit_expr(np_value.get(node))
    let val_str = expr_result_str
    let val_type = expr_result_type
    let helper_lines = cg_lines
    cg_lines = saved_lines
    let name = np_name.get(node)
    let is_mut = np_is_mut.get(node)
    set_var(name, val_type, is_mut)
    // Track list element type from annotation
    let type_ann = np_target.get(node)
    if val_type == CT_LIST && type_ann != -1 {
        let ann_name = np_name.get(type_ann)
        if ann_name == "List" {
            let elems_sl = np_elements.get(type_ann)
            if elems_sl != -1 && sublist_length(elems_sl) > 0 {
                let elem_ann = sublist_get(elems_sl, 0)
                let elem_name = np_name.get(elem_ann)
                set_list_elem_type(name, type_from_name(elem_name))
            }
        }
    }
    let ts = c_type_str(val_type)
    let needs_init = helper_lines.len() > 0 || val_type == CT_LIST
    if needs_init {
        emit_line("static {ts} {name};")
        let mut hi = 0
        while hi < helper_lines.len() {
            cg_global_inits.push(helper_lines.get(hi))
            hi = hi + 1
        }
        cg_global_inits.push("    {name} = {val_str};")
    } else if is_mut != 0 {
        emit_line("static {ts} {name} = {val_str};")
    } else {
        emit_line("static const {ts} {name} = {val_str};")
    }
}

pub fn generate(program: Int) -> Str {
    cg_program_node = program
    // Reset state
    cg_lines = []
    cg_indent = 0
    cg_temp_counter = 0
    scope_names = []
    scope_types = []
    scope_muts = []
    scope_frame_starts = []
    fn_reg_names = []
    fn_reg_ret = []
    fn_reg_effect_sl = []
    effect_reg_names = []
    effect_reg_parent = []
    cg_current_fn_name = ""
    cg_global_inits = []
    var_list_elem_names = []
    var_list_elem_types = []
    struct_reg_names = []
    enum_reg_names = []
    enum_reg_variant_names = []
    enum_reg_variant_enum_idx = []
    var_enum_names = []
    var_enum_types = []
    fn_enum_ret_names = []
    fn_enum_ret_types = []
    emitted_let_names = []
    emitted_fn_names = []
    trait_reg_names = []
    trait_reg_method_sl = []
    impl_reg_trait = []
    impl_reg_type = []
    impl_reg_methods_sl = []
    from_reg_source = []
    from_reg_target = []
    from_reg_method_sl = []
    var_struct_names = []
    var_struct_types = []
    sf_reg_struct = []
    sf_reg_field = []
    sf_reg_type = []
    sf_reg_stype = []
    mono_base_names = []
    mono_concrete_args = []
    mono_c_names = []
    cg_closure_defs = []
    cg_closure_counter = 0
    var_closure_names = []
    var_closure_sigs = []
    generic_fn_names = []
    generic_fn_nodes = []
    mono_fn_bases = []
    mono_fn_args = []
    var_option_names = []
    var_option_inner = []
    var_result_names = []
    var_result_ok = []
    var_result_err = []
    emitted_option_types = []
    emitted_result_types = []
    cg_let_target_type = 0

    push_scope()

    // Register builtins
    reg_fn("arg_count", CT_INT)
    reg_fn("get_arg", CT_STRING)
    reg_fn("read_file", CT_STRING)
    reg_fn("write_file", CT_VOID)
    reg_fn("file_exists", CT_INT)
    reg_fn("path_join", CT_STRING)
    reg_fn("path_dirname", CT_STRING)

    // Register built-in structs
    struct_reg_names.push("ConversionError")
    sf_reg_struct.push("ConversionError")
    sf_reg_field.push("message")
    sf_reg_type.push(CT_STRING)
    sf_reg_stype.push("")
    sf_reg_struct.push("ConversionError")
    sf_reg_field.push("source_type")
    sf_reg_type.push(CT_STRING)
    sf_reg_stype.push("")
    sf_reg_struct.push("ConversionError")
    sf_reg_field.push("target_type")
    sf_reg_type.push(CT_STRING)
    sf_reg_stype.push("")

    init_builtin_effects()

    // Register user-defined effect declarations
    let effects_decl_sl = np_args.get(program)
    if effects_decl_sl != -1 {
        let mut ei = 0
        while ei < sublist_length(effects_decl_sl) {
            let ed = sublist_get(effects_decl_sl, ei)
            let eff_name = np_name.get(ed)
            let parent_idx = reg_effect(eff_name, -1)
            let children_sl = np_elements.get(ed)
            if children_sl != -1 {
                let mut ci = 0
                while ci < sublist_length(children_sl) {
                    let child = sublist_get(children_sl, ci)
                    let child_name = np_name.get(child)
                    reg_effect("{eff_name}.{child_name}", parent_idx)
                    ci = ci + 1
                }
            }
            ei = ei + 1
        }
    }

    // Preamble: include runtime
    cg_lines.push("#include \"runtime.h\"")
    cg_lines.push("")

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
                generic_fn_names.push(fn_name)
                generic_fn_nodes.push(fn_node)
            } else if is_emitted_fn(fn_name) == 0 {
                let ret_str = np_return_type.get(fn_node)
                let fn_eff_sl = np_effects.get(fn_node)
                if is_enum_type(ret_str) != 0 {
                    fn_enum_ret_names.push(fn_name)
                    fn_enum_ret_types.push(ret_str)
                    reg_fn_with_effects(fn_name, CT_INT, fn_eff_sl)
                } else {
                    reg_fn_with_effects(fn_name, type_from_name(ret_str), fn_eff_sl)
                }
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
            trait_reg_names.push(np_name.get(tr))
            trait_reg_method_sl.push(np_methods.get(tr))
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
            impl_reg_trait.push(impl_trait)
            impl_reg_type.push(impl_type)
            impl_reg_methods_sl.push(np_methods.get(im))
            if impl_trait == "From" {
                let trait_tparams = np_type_params.get(im)
                if trait_tparams != -1 && sublist_length(trait_tparams) > 0 {
                    let src_node = sublist_get(trait_tparams, 0)
                    let src_type = np_name.get(src_node)
                    from_reg_source.push(src_type)
                    from_reg_target.push(impl_type)
                    from_reg_method_sl.push(np_methods.get(im))
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
                        fn_enum_ret_names.push(mangled)
                        fn_enum_ret_types.push(ret_str)
                        reg_fn(mangled, CT_INT)
                    } else if is_struct_type(ret_str) != 0 {
                        reg_fn(mangled, CT_VOID)
                    } else {
                        reg_fn(mangled, type_from_name(ret_str))
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    // Auto-derive Into from From
    let mut into_i = 0
    while into_i < from_reg_source.len() {
        let src = from_reg_source.get(into_i)
        let tgt = from_reg_target.get(into_i)
        impl_reg_trait.push("Into")
        impl_reg_type.push(src)
        impl_reg_methods_sl.push(from_reg_method_sl.get(into_i))
        into_i = into_i + 1
    }

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
                            let ret_type = type_from_name(ret_str)
                            emit_line("{c_type_str(ret_type)} pact_{mangled}({params});")
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

    // Emit Option/Result type definitions discovered during codegen
    emit_all_option_result_types()

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

    // Now append the function definitions
    let mut fi = 0
    while fi < fn_def_lines.len() {
        cg_lines.push(fn_def_lines.get(fi))
        fi = fi + 1
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
    if cg_global_inits.len() > 0 {
        emit_line("__pact_init_globals();")
    }
    emit_line("pact_main();")
    emit_line("return 0;")
    cg_indent = cg_indent - 1
    emit_line("}")

    pop_scope()

    join_lines()
}
