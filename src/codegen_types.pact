import tokens
import ast
import parser
import diagnostics

effect Codegen {
    effect Emit
    effect Register
    effect Scope
}

// codegen_types.pact — Type constants, global state, scope/registry helpers
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
pub let CT_ITERATOR = 9
pub let CT_HANDLE = 10
pub let CT_CHANNEL = 11
pub let CT_TAGGED_ENUM = 12
pub let CT_MAP = 13


// ── Codegen state ───────────────────────────────────────────────────

pub let mut cg_lines: List[Str] = []
pub let mut cg_indent: Int = 0
pub let mut cg_temp_counter: Int = 0
pub let mut cg_global_inits: List[Str] = []
pub let mut struct_reg_names: List[Str] = []
type EnumReg {
    name: Str
    has_data: Int
}

type EnumVariant {
    name: Str
    enum_idx: Int
    field_names: Str
    field_types: Str
    field_count: Int
}

pub let mut enum_regs: List[EnumReg] = []
pub let mut enum_variants: List[EnumVariant] = []
type VarEnumEntry {
    name: Str
    enum_type: Str
}
pub let mut var_enums: List[VarEnumEntry] = []
type FnEnumRetEntry {
    name: Str
    enum_type: Str
}
pub let mut fn_enum_rets: List[FnEnumRetEntry] = []
pub let mut emitted_let_names: List[Str] = []
pub let mut emitted_fn_names: List[Str] = []
pub let mut struct_reg_set: Map[Str, Int] = Map()
pub let mut enum_reg_set: Map[Str, Int] = Map()
pub let mut emitted_fn_set: Map[Str, Int] = Map()
pub let mut emitted_let_set: Map[Str, Int] = Map()
pub let mut emitted_option_set: Map[Str, Int] = Map()
pub let mut emitted_result_set: Map[Str, Int] = Map()
pub let mut emitted_iter_set: Map[Str, Int] = Map()
pub let mut cg_closure_defs: List[Str] = []
pub let mut cg_closure_counter: Int = 0

// Capture analysis: per-capture info (flat list) and per-closure start/count
type CaptureEntry {
    name: Str
    ctype: Int
    is_mut: Int
}

type ClosureCapInfo {
    start: Int
    count: Int
}

pub let mut closure_captures: List[CaptureEntry] = []
pub let mut closure_cap_infos: List[ClosureCapInfo] = []

// Active closure context: set while emitting a closure body, -1 otherwise
pub let mut cg_closure_cap_start: Int = -1
pub let mut cg_closure_cap_count: Int = 0

// Variables in the outer scope that are heap-boxed because a closure captures them mutably
pub let mut mut_captured_vars: List[Str] = []

// Trait registry: maps trait name -> method names
type TraitEntry {
    name: Str
    method_sl: Int
}
pub let mut trait_entries: List[TraitEntry] = []

// Impl registry: maps (trait, type) -> method FnDef nodes
type ImplEntry {
    trait_name: Str
    type_name: Str
    methods_sl: Int
}
pub let mut impl_entries: List[ImplEntry] = []

// From impl registry: (source_type, target_type) -> methods sublist
type FromImplEntry {
    source: Str
    target: Str
    method_sl: Int
}
pub let mut from_entries: List[FromImplEntry] = []

// TryFrom impl registry: (source_type, target_type) -> methods sublist
type TryFromImplEntry {
    source: Str
    target: Str
    method_sl: Int
}
pub let mut tryfrom_entries: List[TryFromImplEntry] = []

// Variable-to-struct-type tracking (for method resolution)
type VarStructEntry {
    name: Str
    stype: Str
}
pub let mut var_structs: List[VarStructEntry] = []
pub let mut var_struct_frame_starts: List[Int] = []

// Struct field type registry: (struct_name, field_name) -> field C type
type StructFieldEntry {
    struct_name: Str
    field_name: Str
    field_type: Int
    stype: Str
}
pub let mut sf_entries: List[StructFieldEntry] = []

// Closure-typed variable tracking: (name) -> C function pointer signature
type VarClosureEntry {
    name: Str
    sig: Str
}
pub let mut var_closures: List[VarClosureEntry] = []
pub let mut var_closure_frame_starts: List[Int] = []

// Generic function definition registry: fn_name -> fn_node for generic fns
type GenericFnEntry {
    name: Str
    node: Int
}
pub let mut generic_fns: List[GenericFnEntry] = []

// Mono function instances to emit: (base_fn_name, concrete_args)
type MonoFnInstance {
    base: Str
    args: Str
}
pub let mut mono_fns: List[MonoFnInstance] = []

// Generic monomorphic instance registry
type MonoInstance {
    base: Str
    args: Str
    c_name: Str
}
pub let mut mono_instances: List[MonoInstance] = []

// Option/Result type tracking
type VarOptionEntry {
    name: Str
    inner: Int
}
pub let mut var_options: List[VarOptionEntry] = []
pub let mut var_option_frame_starts: List[Int] = []
type VarResultEntry {
    name: Str
    ok_type: Int
    err_type: Int
}
pub let mut var_results: List[VarResultEntry] = []
pub let mut var_result_frame_starts: List[Int] = []
pub let mut emitted_option_types: List[Int] = []
pub let mut emitted_result_types: List[Str] = []
pub let mut emitted_iter_types: List[Int] = []
pub let mut emitted_range_iter: Int = 0
pub let mut emitted_str_iter: Int = 0

type VarIteratorEntry {
    name: Str
    inner: Int
    next_fn: Str
    next_name: Str
}
pub let mut var_iterators: List[VarIteratorEntry] = []
pub let mut var_iterator_frame_starts: List[Int] = []
type VarAliasEntry {
    name: Str
    target: Str
}
pub let mut var_aliases: List[VarAliasEntry] = []
pub let mut var_alias_frame_starts: List[Int] = []
pub let mut emitted_map_iters: List[Int] = []
pub let mut emitted_filter_iters: List[Int] = []
pub let mut emitted_take_iters: List[Int] = []
pub let mut emitted_skip_iters: List[Int] = []
pub let mut emitted_chain_iters: List[Int] = []
pub let mut emitted_flat_map_iters: List[Int] = []

type VarHandleEntry {
    name: Str
    inner: Int
}
pub let mut var_handles: List[VarHandleEntry] = []
pub let mut var_handle_frame_starts: List[Int] = []
type VarChannelEntry {
    name: Str
    inner: Int
}
pub let mut var_channels: List[VarChannelEntry] = []
pub let mut var_channel_frame_starts: List[Int] = []

// Assignment context for .into() type inference
pub let mut cg_let_target_type: Int = 0
pub let mut cg_let_target_name: Str = ""

// Handler vtable field set by emit_handler_expr for emit_with_block
pub let mut cg_handler_vtable_field: Str = ""
pub let mut cg_handler_is_user_effect: Int = 0
// Tracks the current handler's vtable type and field for default delegation
pub let mut cg_in_handler_body: Int = 0
pub let mut cg_handler_body_vtable_type: Str = ""
pub let mut cg_handler_body_field: Str = ""
pub let mut cg_handler_body_is_ue: Int = 0
pub let mut cg_handler_body_idx: Int = 0

// Scope: parallel lists for variable names, types, and mutability.
// Each scope is a "frame" delimited by frame_starts.
type ScopeVar {
    name: Str
    ctype: Int
    is_mut: Int
}
pub let mut scope_vars: List[ScopeVar] = []
pub let mut scope_frame_starts: List[Int] = []

// Function registry: parallel lists (fn name -> return type, param count)
type FnRegEntry {
    name: Str
    ret: Int
    effect_sl: Int
}
pub let mut fn_regs: List[FnRegEntry] = []

// Function return struct type tracking
type FnRetStructEntry {
    name: Str
    stype: Str
}
pub let mut fn_ret_structs: List[FnRetStructEntry] = []

// Function return type tracking — unified struct
type RetType {
    name: Str
    kind: Int
    inner1: Int
    inner2: Int
}

pub let mut fn_ret_types: List[RetType] = []

// Effect registry: name -> parent index (-1 = top-level)
type EffectEntry {
    name: Str
    parent: Int
}
pub let mut effect_entries: List[EffectEntry] = []

// User-defined effect registry
type UeEffect {
    name: Str
    handle: Str
}

type UeMethod {
    name: Str
    params: Str
    ret: Str
    effect_handle: Str
}

pub let mut ue_effects: List[UeEffect] = []
pub let mut ue_methods: List[UeMethod] = []

// @capabilities budget: allowed effects for the module (-1 = no budget)
pub let mut cap_budget_names: List[Str] = []
pub let mut cap_budget_active: Int = 0

// Current function being emitted (for effect propagation checking)
pub let mut cg_current_fn_name: Str = ""
pub let mut cg_current_fn_ret: Int = 0

type VarListElemEntry {
    name: Str
    elem_type: Int
    struct_name: Str
}
pub let mut var_list_elems: List[VarListElemEntry] = []
pub let mut var_list_elem_frame_starts: List[Int] = []

type VarMapEntry {
    name: Str
    key_type: Int
    value_type: Int
    value_struct: Str
}
pub let mut var_maps: List[VarMapEntry] = []
pub let mut var_map_frame_starts: List[Int] = []

// Scratch space for tuple match scrutinee temps
pub let mut cg_program_node: Int = 0
pub let mut cg_uses_async: Int = 0
pub let mut cg_async_wrapper_counter: Int = 0

// Async scope tracking: stack of scope handle list variable names
pub let mut cg_async_scope_stack: List[Str] = []
pub let mut cg_async_scope_counter: Int = 0

type MatchScrutEntry {
    str_val: Str
    scrut_type: Int
}
pub let mut match_scruts: List[MatchScrutEntry] = []
pub let mut match_scrut_enum: Str = ""

// Debug mode: 0 = release (strip debug_assert), 1 = debug (emit checks)
pub let mut cg_debug_mode: Int = 0

pub fn push_scope() ! Codegen.Scope {
    scope_frame_starts.push(scope_vars.len())
    var_struct_frame_starts.push(var_structs.len())
    var_closure_frame_starts.push(var_closures.len())
    var_option_frame_starts.push(var_options.len())
    var_result_frame_starts.push(var_results.len())
    var_iterator_frame_starts.push(var_iterators.len())
    var_alias_frame_starts.push(var_aliases.len())
    var_handle_frame_starts.push(var_handles.len())
    var_channel_frame_starts.push(var_channels.len())
    var_list_elem_frame_starts.push(var_list_elems.len())
    var_map_frame_starts.push(var_maps.len())
}

pub fn pop_scope() ! Codegen.Scope {
    let start = scope_frame_starts.get(scope_frame_starts.len() - 1)
    scope_frame_starts.pop()
    while scope_vars.len() > start {
        scope_vars.pop()
    }
    let vs_start = var_struct_frame_starts.get(var_struct_frame_starts.len() - 1)
    var_struct_frame_starts.pop()
    while var_structs.len() > vs_start {
        var_structs.pop()
    }
    let vc_start = var_closure_frame_starts.get(var_closure_frame_starts.len() - 1)
    var_closure_frame_starts.pop()
    while var_closures.len() > vc_start {
        var_closures.pop()
    }
    let vo_start = var_option_frame_starts.get(var_option_frame_starts.len() - 1)
    var_option_frame_starts.pop()
    while var_options.len() > vo_start {
        var_options.pop()
    }
    let vr_start = var_result_frame_starts.get(var_result_frame_starts.len() - 1)
    var_result_frame_starts.pop()
    while var_results.len() > vr_start {
        var_results.pop()
    }
    let vi_start = var_iterator_frame_starts.get(var_iterator_frame_starts.len() - 1)
    var_iterator_frame_starts.pop()
    while var_iterators.len() > vi_start {
        var_iterators.pop()
    }
    let va_start = var_alias_frame_starts.get(var_alias_frame_starts.len() - 1)
    var_alias_frame_starts.pop()
    while var_aliases.len() > va_start {
        var_aliases.pop()
    }
    let vh_start = var_handle_frame_starts.get(var_handle_frame_starts.len() - 1)
    var_handle_frame_starts.pop()
    while var_handles.len() > vh_start {
        var_handles.pop()
    }
    let vch_start = var_channel_frame_starts.get(var_channel_frame_starts.len() - 1)
    var_channel_frame_starts.pop()
    while var_channels.len() > vch_start {
        var_channels.pop()
    }
    let vle_start = var_list_elem_frame_starts.get(var_list_elem_frame_starts.len() - 1)
    var_list_elem_frame_starts.pop()
    while var_list_elems.len() > vle_start {
        var_list_elems.pop()
    }
    let vm_start = var_map_frame_starts.get(var_map_frame_starts.len() - 1)
    var_map_frame_starts.pop()
    while var_maps.len() > vm_start {
        var_maps.pop()
    }
}

pub fn set_var(name: Str, ctype: Int, is_mut: Int) ! Codegen.Scope {
    scope_vars.push(ScopeVar { name: name, ctype: ctype, is_mut: is_mut })
}

pub fn get_var_type(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i)
        if sv.name == name {
            return sv.ctype
        }
        i = i - 1
    }
    CT_INT
}

pub fn get_var_mut(name: Str) -> Int {
    let mut i = scope_vars.len() - 1
    while i >= 0 {
        let sv = scope_vars.get(i)
        if sv.name == name {
            return sv.is_mut
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
        if closure_captures.get(cg_closure_cap_start + i).name == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn capture_cast_expr(idx: Int) -> Str {
    let ct = closure_captures.get(cg_closure_cap_start + idx).ctype
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
    } else if ct == CT_MAP {
        "(pact_map*)pact_closure_get_capture(__self, {idx})"
    } else if ct == CT_CLOSURE {
        "(pact_closure*)pact_closure_get_capture(__self, {idx})"
    } else {
        "pact_closure_get_capture(__self, {idx})"
    }
}

pub fn reg_fn(name: Str, ret: Int) ! Codegen.Register {
    fn_regs.push(FnRegEntry { name: name, ret: ret, effect_sl: -1 })
}

pub fn reg_fn_with_effects(name: Str, ret: Int, effects_sl: Int) ! Codegen.Register {
    fn_regs.push(FnRegEntry { name: name, ret: ret, effect_sl: effects_sl })
}

pub fn get_fn_effect_sl(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        let fr = fn_regs.get(i)
        if fr.name == name {
            return fr.effect_sl
        }
        i = i + 1
    }
    -1
}

pub fn reg_fn_struct_ret(name: Str, stype: Str) ! Codegen.Register {
    fn_ret_structs.push(FnRetStructEntry { name: name, stype: stype })
}

pub fn get_fn_ret_struct(name: Str) -> Str {
    let mut i = fn_ret_structs.len() - 1
    while i >= 0 {
        let frs = fn_ret_structs.get(i)
        if frs.name == name {
            return frs.stype
        }
        i = i - 1
    }
    ""
}

pub fn reg_fn_ret_type(name: Str, kind: Int, inner1: Int, inner2: Int) ! Codegen.Register {
    fn_ret_types.push(RetType { name: name, kind: kind, inner1: inner1, inner2: inner2 })
}

pub fn get_fn_ret_type(name: Str) -> RetType {
    let mut i = fn_ret_types.len() - 1
    while i >= 0 {
        let rt = fn_ret_types.get(i)
        if rt.name == name {
            return rt
        }
        i = i - 1
    }
    RetType { name: "", kind: CT_VOID, inner1: -1, inner2: -1 }
}

pub fn resolve_ret_type_from_ann(fn_node: Int) -> Str {
    let ret_str = np_return_type.get(fn_node)
    let ta = np_type_ann.get(fn_node)
    if ret_str == "Result" && ta != -1 {
        let elems_sl = np_elements.get(ta)
        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
            let ok_ann = sublist_get(elems_sl, 0)
            let err_ann = sublist_get(elems_sl, 1)
            let ok_t = type_from_name(np_name.get(ok_ann))
            let err_t = type_from_name(np_name.get(err_ann))
            return result_c_type(ok_t, err_t)
        }
        return result_c_type(CT_INT, CT_STRING)
    }
    if ret_str == "Option" && ta != -1 {
        let elems_sl = np_elements.get(ta)
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let inner_ann = sublist_get(elems_sl, 0)
            let inner_t = type_from_name(np_name.get(inner_ann))
            return option_c_type(inner_t)
        }
        return option_c_type(CT_INT)
    }
    ""
}

pub fn reg_fn_ret_from_ann(name: Str, fn_node: Int) ! Codegen.Register {
    let ret_str = np_return_type.get(fn_node)
    let ta = np_type_ann.get(fn_node)
    if ret_str == "Result" && ta != -1 {
        let elems_sl = np_elements.get(ta)
        if elems_sl != -1 && sublist_length(elems_sl) >= 2 {
            let ok_ann = sublist_get(elems_sl, 0)
            let err_ann = sublist_get(elems_sl, 1)
            let ok_t = type_from_name(np_name.get(ok_ann))
            let err_t = type_from_name(np_name.get(err_ann))
            reg_fn_ret_type(name, CT_RESULT, ok_t, err_t)
            ensure_result_type(ok_t, err_t)
        }
    }
    if ret_str == "Option" && ta != -1 {
        let elems_sl = np_elements.get(ta)
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let inner_ann = sublist_get(elems_sl, 0)
            let inner_t = type_from_name(np_name.get(inner_ann))
            reg_fn_ret_type(name, CT_OPTION, inner_t, -1)
            ensure_option_type(inner_t)
        }
    }
    if ret_str == "List" && ta != -1 {
        let elems_sl = np_elements.get(ta)
        if elems_sl != -1 && sublist_length(elems_sl) >= 1 {
            let elem_ann = sublist_get(elems_sl, 0)
            let elem_name = np_name.get(elem_ann)
            let elem_t = type_from_name(elem_name)
            reg_fn_ret_type(name, CT_LIST, elem_t, -1)
        }
    }
}

pub fn reg_effect(name: Str, parent: Int) -> Int ! Codegen.Register {
    let idx = effect_entries.len()
    effect_entries.push(EffectEntry { name: name, parent: parent })
    idx
}

pub fn get_effect_idx(name: Str) -> Int {
    let mut i = 0
    while i < effect_entries.len() {
        if effect_entries.get(i).name == name {
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
    let parent_idx = effect_entries.get(callee_idx).parent
    if parent_idx == -1 {
        return 0
    }
    let parent_name = effect_entries.get(parent_idx).name
    if parent_name == caller_effect {
        return 1
    }
    0
}

pub fn check_effect_propagation(callee_name: Str) ! Diag.Report {
    if cg_current_fn_name == "main" || cg_current_fn_name.starts_with("__test_") {
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
            diag_warn("UndeclaredEffect", "E0500", "function '{callee_name}' requires effect '{callee_eff}' but caller '{cg_current_fn_name}' does not declare it", 0, 0, "")
        }
        ci = ci + 1
    }
}

pub fn check_capabilities_budget(fn_name: Str, effects_sl: Int) ! Diag.Report {
    if cap_budget_active == 0 {
        return
    }
    if fn_name == "main" || fn_name.starts_with("__test_") {
        return
    }
    if effects_sl == -1 {
        return
    }
    let count = sublist_length(effects_sl)
    let mut ei = 0
    while ei < count {
        let eff_node = sublist_get(effects_sl, ei)
        let eff_name = np_name.get(eff_node)
        let mut allowed = 0
        let mut bi = 0
        while bi < cap_budget_names.len() {
            let budget_eff = cap_budget_names.get(bi)
            if effect_satisfies(budget_eff, eff_name) != 0 {
                allowed = 1
            }
            bi = bi + 1
        }
        if allowed == 0 {
            diag_error_no_loc("InsufficientCapability", "E0501", "function '{fn_name}' uses effect '{eff_name}' which is not in @capabilities budget", "add the effect to @capabilities")
        }
        ei = ei + 1
    }
}

pub fn init_builtin_effects() ! Codegen.Register {
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
    let async_idx = reg_effect("Async", -1)
    reg_effect("Async.Spawn", async_idx)
    reg_effect("Async.Channel", async_idx)
}

pub fn get_ue_handle(effect_name: Str) -> Str {
    let mut i = 0
    while i < ue_effects.len() {
        let ue = ue_effects.get(i)
        if ue.name == effect_name {
            return ue.handle
        }
        i = i + 1
    }
    ""
}

pub fn get_ue_top_for_handle(handle: Str) -> Str {
    let mut i = 0
    while i < ue_effects.len() {
        let ue = ue_effects.get(i)
        if ue.handle == handle {
            return ue.name
        }
        i = i + 1
    }
    ""
}

pub fn is_user_effect_handle(name: Str) -> Int {
    let mut i = 0
    while i < ue_effects.len() {
        if ue_effects.get(i).handle == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn ue_has_method(handle: Str, method: Str) -> Int {
    let mut i = 0
    while i < ue_methods.len() {
        let uem = ue_methods.get(i)
        if uem.effect_handle == handle && uem.name == method {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn is_fn_registered(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        if fn_regs.get(i).name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_fn_ret(name: Str) -> Int {
    let mut i = 0
    while i < fn_regs.len() {
        let fr = fn_regs.get(i)
        if fr.name == name {
            return fr.ret
        }
        i = i + 1
    }
    CT_VOID
}

pub fn set_list_elem_type(name: Str, elem_type: Int) {
    var_list_elems.push(VarListElemEntry { name: name, elem_type: elem_type, struct_name: "" })
}

pub fn get_list_elem_type(name: Str) -> Int {
    let mut i = var_list_elems.len() - 1
    while i >= 0 {
        let e = var_list_elems.get(i)
        if e.name == name && e.elem_type != -1 {
            return e.elem_type
        }
        i = i - 1
    }
    CT_INT
}

pub fn set_list_elem_struct(name: Str, struct_name: Str) {
    var_list_elems.push(VarListElemEntry { name: name, elem_type: -1, struct_name: struct_name })
}

pub fn get_list_elem_struct(name: Str) -> Str {
    let mut i = var_list_elems.len() - 1
    while i >= 0 {
        let e = var_list_elems.get(i)
        if e.name == name && e.struct_name != "" {
            return e.struct_name
        }
        i = i - 1
    }
    ""
}

pub fn set_map_types(name: Str, key_type: Int, value_type: Int) {
    var_maps.push(VarMapEntry { name: name, key_type: key_type, value_type: value_type, value_struct: "" })
}

pub fn get_map_key_type(name: Str) -> Int {
    let mut i = var_maps.len() - 1
    while i >= 0 {
        let vm = var_maps.get(i)
        if vm.name == name {
            return vm.key_type
        }
        i = i - 1
    }
    CT_STRING
}

pub fn get_map_value_type(name: Str) -> Int {
    let mut i = var_maps.len() - 1
    while i >= 0 {
        let vm = var_maps.get(i)
        if vm.name == name {
            return vm.value_type
        }
        i = i - 1
    }
    CT_INT
}

pub fn set_map_value_struct(name: Str, struct_name: Str) {
    let mut i = var_maps.len() - 1
    while i >= 0 {
        let vm = var_maps.get(i)
        if vm.name == name {
            var_maps.set(i, VarMapEntry { name: name, key_type: vm.key_type, value_type: vm.value_type, value_struct: struct_name })
            return
        }
        i = i - 1
    }
}

pub fn get_map_value_struct(name: Str) -> Str {
    let mut i = var_maps.len() - 1
    while i >= 0 {
        let vm = var_maps.get(i)
        if vm.name == name {
            return vm.value_struct
        }
        i = i - 1
    }
    ""
}

pub fn is_struct_type(name: Str) -> Int {
    struct_reg_set.has(name)
}

pub fn is_enum_type(name: Str) -> Int {
    enum_reg_set.has(name)
}

pub fn resolve_variant(name: Str) -> Str {
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i)
        if evar.name == name {
            return enum_regs.get(evar.enum_idx).name
        }
        i = i + 1
    }
    ""
}

pub fn get_var_enum(name: Str) -> Str {
    let mut i = 0
    while i < var_enums.len() {
        let ve = var_enums.get(i)
        if ve.name == name {
            return ve.enum_type
        }
        i = i + 1
    }
    ""
}

pub fn is_data_enum(name: Str) -> Int {
    let mut i = 0
    while i < enum_regs.len() {
        let ereg = enum_regs.get(i)
        if ereg.name == name {
            return ereg.has_data
        }
        i = i + 1
    }
    0
}

pub fn get_variant_index(enum_name: Str, variant_name: Str) -> Int {
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i)
        if evar.name == variant_name {
            if enum_regs.get(evar.enum_idx).name == enum_name {
                return i
            }
        }
        i = i + 1
    }
    -1
}

pub fn get_variant_tag(enum_name: Str, variant_name: Str) -> Int {
    let mut tag = 0
    let mut i = 0
    while i < enum_variants.len() {
        let evar = enum_variants.get(i)
        if enum_regs.get(evar.enum_idx).name == enum_name {
            if evar.name == variant_name {
                return tag
            }
            tag = tag + 1
        }
        i = i + 1
    }
    -1
}

pub fn get_variant_field_count(variant_idx: Int) -> Int {
    if variant_idx < 0 || variant_idx >= enum_variants.len() {
        return 0
    }
    enum_variants.get(variant_idx).field_count
}

pub fn get_variant_field_name(variant_idx: Int, field_idx: Int) -> Str {
    let names_str = enum_variants.get(variant_idx).field_names
    if names_str == "" {
        return ""
    }
    let mut seg_start = 0
    let mut seg_idx = 0
    let mut i = 0
    while i <= names_str.len() {
        if i == names_str.len() || names_str.char_at(i) == 44 {
            if seg_idx == field_idx {
                return names_str.substr(seg_start, i - seg_start)
            }
            seg_start = i + 1
            seg_idx = seg_idx + 1
        }
        i = i + 1
    }
    ""
}

pub fn get_variant_field_type_str(variant_idx: Int, field_idx: Int) -> Str {
    let types_str = enum_variants.get(variant_idx).field_types
    if types_str == "" {
        return ""
    }
    let mut seg_start = 0
    let mut seg_idx = 0
    let mut i = 0
    while i <= types_str.len() {
        if i == types_str.len() || types_str.char_at(i) == 44 {
            if seg_idx == field_idx {
                return types_str.substr(seg_start, i - seg_start)
            }
            seg_start = i + 1
            seg_idx = seg_idx + 1
        }
        i = i + 1
    }
    ""
}

pub fn get_fn_enum_ret(name: Str) -> Str {
    let mut i = 0
    while i < fn_enum_rets.len() {
        let fe = fn_enum_rets.get(i)
        if fe.name == name {
            return fe.enum_type
        }
        i = i + 1
    }
    ""
}

pub fn set_var_struct(name: Str, type_name: Str) {
    var_structs.push(VarStructEntry { name: name, stype: type_name })
}

pub fn get_var_struct(name: Str) -> Str {
    let mut i = var_structs.len() - 1
    while i >= 0 {
        let vs = var_structs.get(i)
        if vs.name == name {
            return vs.stype
        }
        i = i - 1
    }
    ""
}

pub fn get_struct_field_type(sname: Str, fname: Str) -> Int {
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i)
        if sf.struct_name == sname && sf.field_name == fname {
            return sf.field_type
        }
        i = i + 1
    }
    CT_VOID
}

pub fn get_struct_field_stype(sname: Str, fname: Str) -> Str {
    let mut i = 0
    while i < sf_entries.len() {
        let sf = sf_entries.get(i)
        if sf.struct_name == sname && sf.field_name == fname {
            return sf.stype
        }
        i = i + 1
    }
    ""
}

pub fn set_var_closure(name: Str, sig: Str) {
    var_closures.push(VarClosureEntry { name: name, sig: sig })
}

pub fn get_var_closure_sig(name: Str) -> Str {
    let mut i = 0
    while i < var_closures.len() {
        let vc = var_closures.get(i)
        if vc.name == name {
            return vc.sig
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
    while i < generic_fns.len() {
        if generic_fns.get(i).name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_generic_fn_node(name: Str) -> Int {
    let mut i = 0
    while i < generic_fns.len() {
        let gf = generic_fns.get(i)
        if gf.name == name {
            return gf.node
        }
        i = i + 1
    }
    -1
}

pub fn register_mono_fn(base: Str, args: Str) ! Codegen.Register {
    let mut i = 0
    while i < mono_fns.len() {
        let mf = mono_fns.get(i)
        if mf.base == base && mf.args == args {
            return
        }
        i = i + 1
    }
    mono_fns.push(MonoFnInstance { base: base, args: args })
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
    else if ct == CT_ITERATOR { "Iterator" }
    else if ct == CT_HANDLE { "Handle" }
    else if ct == CT_CHANNEL { "Channel" }
    else if ct == CT_MAP { "Map" }
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

pub fn register_mono_instance(base: Str, args: Str) -> Str ! Codegen.Register {
    let existing = lookup_mono_instance(base, args)
    if existing != "" {
        return existing
    }
    let c_name = mangle_generic_name(base, args)
    mono_instances.push(MonoInstance { base: base, args: args, c_name: c_name })
    c_name
}

pub fn lookup_mono_instance(base: Str, args: Str) -> Str {
    let mut i = 0
    while i < mono_instances.len() {
        let m = mono_instances.get(i)
        if m.base == base && m.args == args {
            return m.c_name
        }
        i = i + 1
    }
    ""
}

pub fn is_trait_type(name: Str) -> Int {
    let mut i = 0
    while i < trait_entries.len() {
        if trait_entries.get(i).name == name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn lookup_impl_method(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_entries.len() {
        let ie = impl_entries.get(i)
        if ie.type_name == type_name {
            let mut j = 0
            while j < sublist_length(ie.methods_sl) {
                let m = sublist_get(ie.methods_sl, j)
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
    while i < impl_entries.len() {
        let ie = impl_entries.get(i)
        if ie.trait_name == trait_name && ie.type_name == type_name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn get_impl_method_ret(type_name: Str, method: Str) -> Int {
    let mut i = 0
    while i < impl_entries.len() {
        let ie = impl_entries.get(i)
        if ie.type_name == type_name {
            let mut j = 0
            while j < sublist_length(ie.methods_sl) {
                let m = sublist_get(ie.methods_sl, j)
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
    while i < from_entries.len() {
        let fe = from_entries.get(i)
        if fe.source == source && fe.target == target {
            return fe.method_sl
        }
        i = i + 1
    }
    -1
}

pub fn find_tryfrom_impl(source: Str, target: Str) -> Int {
    let mut i = 0
    while i < tryfrom_entries.len() {
        let te = tryfrom_entries.get(i)
        if te.source == source && te.target == target {
            return te.method_sl
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
    emitted_let_set.has(name)
}

pub fn is_emitted_fn(name: Str) -> Int {
    emitted_fn_set.has(name)
}

// ── Helpers ─────────────────────────────────────────────────────────

pub fn c_type_str(ct: Int) -> Str {
    if ct == CT_INT { "int64_t" }
    else if ct == CT_FLOAT { "double" }
    else if ct == CT_BOOL { "int" }
    else if ct == CT_STRING { "const char*" }
    else if ct == CT_LIST { "pact_list*" }
    else if ct == CT_CLOSURE { "pact_closure*" }
    else if ct == CT_ITERATOR { "void*" }
    else if ct == CT_HANDLE { "pact_handle*" }
    else if ct == CT_CHANNEL { "pact_channel*" }
    else if ct == CT_MAP { "pact_map*" }
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
        "Iterator" => CT_ITERATOR
        "Map" => CT_MAP
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
    else if ct == CT_ITERATOR { "iter" }
    else if ct == CT_HANDLE { "handle" }
    else if ct == CT_CHANNEL { "channel" }
    else if ct == CT_MAP { "map" }
    else { "void" }
}

pub fn ensure_option_type(inner: Int) {
    let key = "{inner}"
    if emitted_option_set.has(key) != 0 {
        return
    }
    emitted_option_set.set(key, 1)
    emitted_option_types.push(inner)
}

pub fn ensure_result_type(ok_t: Int, err_t: Int) {
    let key = "{ok_t}_{err_t}"
    if emitted_result_set.has(key) != 0 {
        return
    }
    emitted_result_set.set(key, 1)
    emitted_result_types.push(key)
}

pub fn set_var_option(name: Str, inner: Int) {
    var_options.push(VarOptionEntry { name: name, inner: inner })
}

pub fn get_var_option_inner(name: Str) -> Int {
    let mut i = var_options.len() - 1
    while i >= 0 {
        let vo = var_options.get(i)
        if vo.name == name {
            return vo.inner
        }
        i = i - 1
    }
    -1
}

pub fn set_var_result(name: Str, ok_t: Int, err_t: Int) {
    var_results.push(VarResultEntry { name: name, ok_type: ok_t, err_type: err_t })
}

pub fn get_var_result_ok(name: Str) -> Int {
    let mut i = var_results.len() - 1
    while i >= 0 {
        let vr = var_results.get(i)
        if vr.name == name {
            return vr.ok_type
        }
        i = i - 1
    }
    -1
}

pub fn get_var_result_err(name: Str) -> Int {
    let mut i = var_results.len() - 1
    while i >= 0 {
        let vr = var_results.get(i)
        if vr.name == name {
            return vr.err_type
        }
        i = i - 1
    }
    -1
}

pub fn set_var_iterator(name: Str, inner: Int, next_fn: Str) {
    var_iterators.push(VarIteratorEntry { name: name, inner: inner, next_fn: next_fn, next_name: "" })
}

pub fn get_var_iterator_inner(name: Str) -> Int {
    let mut i = var_iterators.len() - 1
    while i >= 0 {
        let vi = var_iterators.get(i)
        if vi.name == name {
            return vi.inner
        }
        i = i - 1
    }
    -1
}

pub fn get_var_iter_next_fn(name: Str) -> Str {
    let mut i = var_iterators.len() - 1
    while i >= 0 {
        let vi = var_iterators.get(i)
        if vi.name == name {
            return vi.next_fn
        }
        i = i - 1
    }
    ""
}

pub fn set_var_alias(name: Str, target: Str) {
    var_aliases.push(VarAliasEntry { name: name, target: target })
}

pub fn get_var_alias(name: Str) -> Str {
    let mut i = var_aliases.len() - 1
    while i >= 0 {
        let va = var_aliases.get(i)
        if va.name == name {
            return va.target
        }
        i = i - 1
    }
    ""
}

pub fn set_var_handle(name: Str, inner: Int) {
    var_handles.push(VarHandleEntry { name: name, inner: inner })
}

pub fn get_var_handle_inner(name: Str) -> Int {
    let mut i = var_handles.len() - 1
    while i >= 0 {
        let vh = var_handles.get(i)
        if vh.name == name {
            return vh.inner
        }
        i = i - 1
    }
    -1
}

pub fn set_var_channel(name: Str, inner: Int) {
    var_channels.push(VarChannelEntry { name: name, inner: inner })
}

pub fn get_var_channel_inner(name: Str) -> Int {
    let mut i = var_channels.len() - 1
    while i >= 0 {
        let vch = var_channels.get(i)
        if vch.name == name {
            return vch.inner
        }
        i = i - 1
    }
    -1
}

pub fn emit_option_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let tname = "pact_Option_{tag}"
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ int tag; {c_inner} value; } {tname};")
    emit_line("")
}

pub fn emit_result_typedef(ok_t: Int, err_t: Int) ! Codegen.Emit {
    let ok_tag = c_type_tag(ok_t)
    let err_tag = c_type_tag(err_t)
    let tname = "pact_Result_{ok_tag}_{err_tag}"
    let c_ok = c_type_str(ok_t)
    let c_err = c_type_str(err_t)
    emit_line("typedef struct \{ int tag; union \{ {c_ok} ok; {c_err} err; }; } {tname};")
    emit_line("")
}

pub fn ensure_iter_type(inner: Int) {
    let key = "{inner}"
    if emitted_iter_set.has(key) != 0 {
        return
    }
    emitted_iter_set.set(key, 1)
    emitted_iter_types.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_range_iter() {
    if emitted_range_iter != 0 {
        return
    }
    emitted_range_iter = 1
    ensure_option_type(CT_INT)
}

pub fn ensure_str_iter() {
    if emitted_str_iter != 0 {
        return
    }
    emitted_str_iter = 1
    ensure_option_type(CT_INT)
}

pub fn emit_range_iter_typedef() ! Codegen.Emit {
    emit_line("typedef struct \{ int64_t current; int64_t end; int is_inclusive; } pact_RangeIterator;")
    emit_line("")
    emit_line("static pact_Option_int pact_RangeIterator_next(pact_RangeIterator* self) \{")
    emit_line("    int in_range = self->is_inclusive ? (self->current <= self->end) : (self->current < self->end);")
    emit_line("    if (in_range) \{")
    emit_line("        int64_t val = self->current;")
    emit_line("        self->current++;")
    emit_line("        return (pact_Option_int)\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return (pact_Option_int)\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn emit_str_iter_typedef() ! Codegen.Emit {
    emit_line("typedef struct \{ const char* str; int64_t index; int64_t len; } pact_StrIterator;")
    emit_line("")
    emit_line("static pact_Option_int pact_StrIterator_next(pact_StrIterator* self) \{")
    emit_line("    if (self->index < self->len) \{")
    emit_line("        int64_t val = (int64_t)(unsigned char)self->str[self->index];")
    emit_line("        self->index++;")
    emit_line("        return (pact_Option_int)\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return (pact_Option_int)\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn list_iter_c_type(inner: Int) -> Str {
    "pact_ListIterator_{c_type_tag(inner)}"
}

pub fn emit_list_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let tname = "pact_ListIterator_{tag}"
    let opt_name = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ pact_list* items; int64_t index; } {tname};")
    emit_line("")
    emit_line("static {opt_name} {tname}_next({tname}* self) \{")
    emit_line("    if (self->index < pact_list_len(self->items)) \{")
    if inner == CT_INT {
        emit_line("        int64_t val = (int64_t)(intptr_t)pact_list_get(self->items, self->index);")
    } else if inner == CT_STRING {
        emit_line("        const char* val = (const char*)pact_list_get(self->items, self->index);")
    } else {
        emit_line("        {c_inner} val = ({c_inner})(intptr_t)pact_list_get(self->items, self->index);")
    }
    emit_line("        self->index++;")
    emit_line("        return ({opt_name})\{ .tag = 1, .value = val };")
    emit_line("    }")
    emit_line("    return ({opt_name})\{ .tag = 0 };")
    emit_line("}")
    emit_line("")
    emit_line("static {tname} pact_list_into_iter_{tag}(pact_list* self) \{")
    emit_line("    return ({tname})\{ .items = self, .index = 0 };")
    emit_line("}")
    emit_line("")
}

pub fn emit_all_iter_types() ! Codegen.Emit {
    if emitted_range_iter != 0 {
        emit_range_iter_typedef()
    }
    if emitted_str_iter != 0 {
        emit_str_iter_typedef()
    }
    let mut i = 0
    while i < emitted_iter_types.len() {
        emit_list_iter_typedef(emitted_iter_types.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_map_iters.len() {
        emit_map_iter_typedef(emitted_map_iters.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_filter_iters.len() {
        emit_filter_iter_typedef(emitted_filter_iters.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_take_iters.len() {
        emit_take_iter_typedef(emitted_take_iters.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_skip_iters.len() {
        emit_skip_iter_typedef(emitted_skip_iters.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_chain_iters.len() {
        emit_chain_iter_typedef(emitted_chain_iters.get(i))
        i = i + 1
    }
    i = 0
    while i < emitted_flat_map_iters.len() {
        emit_flat_map_iter_typedef(emitted_flat_map_iters.get(i))
        i = i + 1
    }
}

pub fn emit_iter_types_from(list_start: Int, map_start: Int, filter_start: Int, take_start: Int, skip_start: Int, chain_start: Int, flat_map_start: Int) ! Codegen.Emit {
    let mut i = list_start
    while i < emitted_iter_types.len() {
        emit_list_iter_typedef(emitted_iter_types.get(i))
        i = i + 1
    }
    i = map_start
    while i < emitted_map_iters.len() {
        emit_map_iter_typedef(emitted_map_iters.get(i))
        i = i + 1
    }
    i = filter_start
    while i < emitted_filter_iters.len() {
        emit_filter_iter_typedef(emitted_filter_iters.get(i))
        i = i + 1
    }
    i = take_start
    while i < emitted_take_iters.len() {
        emit_take_iter_typedef(emitted_take_iters.get(i))
        i = i + 1
    }
    i = skip_start
    while i < emitted_skip_iters.len() {
        emit_skip_iter_typedef(emitted_skip_iters.get(i))
        i = i + 1
    }
    i = chain_start
    while i < emitted_chain_iters.len() {
        emit_chain_iter_typedef(emitted_chain_iters.get(i))
        i = i + 1
    }
    i = flat_map_start
    while i < emitted_flat_map_iters.len() {
        emit_flat_map_iter_typedef(emitted_flat_map_iters.get(i))
        i = i + 1
    }
}

pub fn has_int_in_list(lst: List[Int], val: Int) -> Bool {
    let mut i = 0
    while i < lst.len() {
        if lst.get(i) == val {
            return true
        }
        i = i + 1
    }
    false
}

pub fn ensure_map_iter(inner: Int) {
    if has_int_in_list(emitted_map_iters, inner) { return }
    emitted_map_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_filter_iter(inner: Int) {
    if has_int_in_list(emitted_filter_iters, inner) { return }
    emitted_filter_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_take_iter(inner: Int) {
    if has_int_in_list(emitted_take_iters, inner) { return }
    emitted_take_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_skip_iter(inner: Int) {
    if has_int_in_list(emitted_skip_iters, inner) { return }
    emitted_skip_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_chain_iter(inner: Int) {
    if has_int_in_list(emitted_chain_iters, inner) { return }
    emitted_chain_iters.push(inner)
    ensure_option_type(inner)
}

pub fn ensure_flat_map_iter(inner: Int) {
    if has_int_in_list(emitted_flat_map_iters, inner) { return }
    emitted_flat_map_iters.push(inner)
    ensure_option_type(inner)
}

pub fn emit_map_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; } pact_MapIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_MapIterator_{tag}_next(pact_MapIterator_{tag}* self) \{")
    emit_line("    {opt} __src = self->source_next(self->source);")
    emit_line("    if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("    {c_inner} __val = (({c_inner} (*)(pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value);")
    emit_line("    return ({opt})\{ .tag = 1, .value = __val };")
    emit_line("}")
    emit_line("")
}

pub fn emit_filter_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; } pact_FilterIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_FilterIterator_{tag}_next(pact_FilterIterator_{tag}* self) \{")
    emit_line("    while (1) \{")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("        if (((int (*)(pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value)) \{")
    emit_line("            return __src;")
    emit_line("        }")
    emit_line("    }")
    emit_line("}")
    emit_line("")
}

pub fn emit_take_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); int64_t limit; int64_t count; } pact_TakeIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_TakeIterator_{tag}_next(pact_TakeIterator_{tag}* self) \{")
    emit_line("    if (self->count >= self->limit) return ({opt})\{ .tag = 0 };")
    emit_line("    {opt} __src = self->source_next(self->source);")
    emit_line("    if (__src.tag == 0) return __src;")
    emit_line("    self->count++;")
    emit_line("    return __src;")
    emit_line("}")
    emit_line("")
}

pub fn emit_skip_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); int64_t skip_n; int64_t skipped; } pact_SkipIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_SkipIterator_{tag}_next(pact_SkipIterator_{tag}* self) \{")
    emit_line("    while (self->skipped < self->skip_n) \{")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return __src;")
    emit_line("        self->skipped++;")
    emit_line("    }")
    emit_line("    return self->source_next(self->source);")
    emit_line("}")
    emit_line("")
}

pub fn emit_chain_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    emit_line("typedef struct \{ void* source_a; {opt} (*next_a)(void*); void* source_b; {opt} (*next_b)(void*); int phase; } pact_ChainIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_ChainIterator_{tag}_next(pact_ChainIterator_{tag}* self) \{")
    emit_line("    if (self->phase == 0) \{")
    emit_line("        {opt} __src = self->next_a(self->source_a);")
    emit_line("        if (__src.tag != 0) return __src;")
    emit_line("        self->phase = 1;")
    emit_line("    }")
    emit_line("    return self->next_b(self->source_b);")
    emit_line("}")
    emit_line("")
}

pub fn emit_flat_map_iter_typedef(inner: Int) ! Codegen.Emit {
    let tag = c_type_tag(inner)
    let opt = option_c_type(inner)
    let c_inner = c_type_str(inner)
    emit_line("typedef struct \{ void* source; {opt} (*source_next)(void*); pact_closure* fn; pact_list* buffer; int64_t buf_idx; } pact_FlatMapIterator_{tag};")
    emit_line("")
    emit_line("static {opt} pact_FlatMapIterator_{tag}_next(pact_FlatMapIterator_{tag}* self) \{")
    emit_line("    while (1) \{")
    emit_line("        if (self->buffer && self->buf_idx < pact_list_len(self->buffer)) \{")
    if inner == CT_INT {
        emit_line("            {c_inner} val = (int64_t)(intptr_t)pact_list_get(self->buffer, self->buf_idx);")
    } else if inner == CT_STRING {
        emit_line("            {c_inner} val = (const char*)pact_list_get(self->buffer, self->buf_idx);")
    } else {
        emit_line("            {c_inner} val = ({c_inner})(intptr_t)pact_list_get(self->buffer, self->buf_idx);")
    }
    emit_line("            self->buf_idx++;")
    emit_line("            return ({opt})\{ .tag = 1, .value = val };")
    emit_line("        }")
    emit_line("        {opt} __src = self->source_next(self->source);")
    emit_line("        if (__src.tag == 0) return ({opt})\{ .tag = 0 };")
    emit_line("        self->buffer = ((pact_list* (*)(pact_closure*, {c_inner}))self->fn->fn_ptr)(self->fn, __src.value);")
    emit_line("        self->buf_idx = 0;")
    emit_line("    }")
    emit_line("}")
    emit_line("")
}

pub fn emit_all_option_result_types() ! Codegen.Emit {
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

pub fn emit_option_result_types_from(opt_start: Int, res_start: Int) ! Codegen.Emit {
    let mut i = opt_start
    while i < emitted_option_types.len() {
        emit_option_typedef(emitted_option_types.get(i))
        i = i + 1
    }
    i = res_start
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

pub fn emit_line(line: Str) ! Codegen.Emit {
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

pub fn join_lines() -> Str ! Codegen.Emit {
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
