import ast
import parser
import diagnostics

// symbol_index.pact — Symbol registry and dependency graph for incremental compilation
//
// Parallel-array storage following mutation_analysis.pact pattern.
// Walks the AST after parsing to build a symbol index with forward/reverse
// dependency edges. Used by LSP, incremental recompilation, and diagnostics.

// ── Symbol kind constants ─────────────────────────────────────────────

pub let SK_FN = 0
pub let SK_STRUCT = 1
pub let SK_ENUM = 2
pub let SK_TRAIT = 3
pub let SK_LET = 4

// ── Dependency kind constants ─────────────────────────────────────────

pub let DK_CALLS = 0
pub let DK_USES_TYPE = 1
pub let DK_FIELD_ACCESS = 2

// ── Visibility constants ──────────────────────────────────────────────

pub let VIS_PRIVATE = 0
pub let VIS_PUB = 1

// ── Symbol registry (parallel arrays) ─────────────────────────────────

pub let mut si_sym_name: List[Str] = []
pub let mut si_sym_kind: List[Int] = []
pub let mut si_sym_module: List[Str] = []
pub let mut si_sym_file: List[Str] = []
pub let mut si_sym_line: List[Int] = []
pub let mut si_sym_vis: List[Int] = []
pub let mut si_sym_effects: List[Str] = []
pub let mut si_sym_sig: List[Str] = []
pub let mut si_sym_ret_type: List[Str] = []
pub let mut si_sym_param_types: List[Str] = []
pub let mut si_sym_doc: List[Str] = []
pub let mut si_sym_intent: List[Str] = []
pub let mut si_sym_requires: List[Str] = []
pub let mut si_sym_ensures: List[Str] = []
pub let mut si_sym_end_line: List[Int] = []

pub let mut si_sym_count: Int = 0

// ── Forward dependency arrays ─────────────────────────────────────────

pub let mut si_dep_from: List[Int] = []
pub let mut si_dep_to: List[Int] = []
pub let mut si_dep_kind: List[Int] = []

pub let mut si_dep_count: Int = 0

// ── Reverse dependency arrays ─────────────────────────────────────────

pub let mut si_rdep_from: List[Int] = []
pub let mut si_rdep_to: List[Int] = []

pub let mut si_rdep_count: Int = 0

// ── File tracking ─────────────────────────────────────────────────────

pub let mut si_file_path: List[Str] = []
pub let mut si_file_mtime: List[Int] = []
pub let mut si_file_sym_start: List[Int] = []
pub let mut si_file_sym_end: List[Int] = []

pub let mut si_file_count: Int = 0

// ── Lookup maps for O(1) access ───────────────────────────────────────

let mut sym_name_map: Map[Str, Int] = Map()
let mut file_path_map: Map[Str, Int] = Map()

// ── Internal helpers ──────────────────────────────────────────────────

fn extract_intent(doc: Str) -> Str {
    if doc == "" {
        return ""
    }
    let mut i = 0
    while i < doc.len() {
        if doc.char_at(i) == 10 {
            return doc.substring(0, i)
        }
        i = i + 1
    }
    doc
}

fn extract_annotation_args(node: Int, ann_name: Str) -> Str {
    let anns_sl = np_handlers.unsafe_get(node)
    if anns_sl == -1 {
        return ""
    }
    let mut result = ""
    let mut i = 0
    while i < sublist_length(anns_sl) {
        let ann = sublist_get(anns_sl, i)
        if np_name.unsafe_get(ann) == ann_name {
            let args_sl = np_args.unsafe_get(ann)
            if args_sl != -1 {
                let mut j = 0
                while j < sublist_length(args_sl) {
                    if result != "" {
                        result = result.concat(",")
                    }
                    result = result.concat(np_name.unsafe_get(sublist_get(args_sl, j)))
                    j = j + 1
                }
            }
        }
        i = i + 1
    }
    result
}

fn add_symbol(name: Str, kind: Int, module: Str, file: Str, line: Int, vis: Int, effects: Str, sig: Str, ret_type: Str, param_types: Str) -> Int {
    let idx = si_sym_count
    si_sym_name.push(name)
    si_sym_kind.push(kind)
    si_sym_module.push(module)
    si_sym_file.push(file)
    si_sym_line.push(line)
    si_sym_vis.push(vis)
    si_sym_effects.push(effects)
    si_sym_sig.push(sig)
    si_sym_ret_type.push(ret_type)
    si_sym_param_types.push(param_types)
    sym_name_map.set(name, idx)
    si_sym_count = si_sym_count + 1
    idx
}

fn si_add_dep(from_idx: Int, to_idx: Int, kind: Int) {
    si_dep_from.push(from_idx)
    si_dep_to.push(to_idx)
    si_dep_kind.push(kind)
    si_dep_count = si_dep_count + 1
}

fn add_rdep(from_idx: Int, to_idx: Int) {
    si_rdep_from.push(from_idx)
    si_rdep_to.push(to_idx)
    si_rdep_count = si_rdep_count + 1
}

fn register_file(path: Str, mtime: Int, sym_start: Int) -> Int {
    let idx = si_file_count
    si_file_path.push(path)
    si_file_mtime.push(mtime)
    si_file_sym_start.push(sym_start)
    si_file_sym_end.push(sym_start)
    file_path_map.set(path, idx)
    si_file_count = si_file_count + 1
    idx
}

fn sym_index(name: Str) -> Int {
    if sym_name_map.has(name) != 0 {
        return sym_name_map.get(name)
    }
    -1
}

// ── Build: collect params as comma-separated type string ──────────────

fn collect_param_types(fn_node: Int) -> Str {
    let params_sl = np_params.unsafe_get(fn_node)
    if params_sl == -1 {
        return ""
    }
    let mut result = ""
    let mut i = 0
    while i < sublist_length(params_sl) {
        let p = sublist_get(params_sl, i)
        if i > 0 {
            result = result.concat(",")
        }
        result = result.concat(np_type_name.unsafe_get(p))
        i = i + 1
    }
    result
}

fn collect_effects(fn_node: Int) -> Str {
    let eff_sl = np_effects.unsafe_get(fn_node)
    if eff_sl == -1 {
        return ""
    }
    let mut result = ""
    let mut i = 0
    while i < sublist_length(eff_sl) {
        let e = sublist_get(eff_sl, i)
        if i > 0 {
            result = result.concat(",")
        }
        result = result.concat(np_name.unsafe_get(e))
        i = i + 1
    }
    result
}

// ── Build: walk expressions for dependency extraction ─────────────────

fn walk_deps(node: Int, from_idx: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.unsafe_get(node)

    if kind == NodeKind.Call {
        let callee = np_left.unsafe_get(node)
        if callee != -1 && np_kind.unsafe_get(callee) == NodeKind.Ident {
            let callee_name = np_name.unsafe_get(callee)
            let callee_idx = sym_index(callee_name)
            if callee_idx >= 0 {
                si_add_dep(from_idx, callee_idx, DK_CALLS)
            }
        }
        walk_deps(callee, from_idx)
        let args_sl = np_args.unsafe_get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_deps(sublist_get(args_sl, ai), from_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.MethodCall {
        walk_deps(np_obj.unsafe_get(node), from_idx)
        let args_sl = np_args.unsafe_get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_deps(sublist_get(args_sl, ai), from_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.FieldAccess {
        let obj = np_obj.unsafe_get(node)
        if obj != -1 && np_kind.unsafe_get(obj) == NodeKind.Ident {
            let obj_name = np_name.unsafe_get(obj)
            let obj_idx = sym_index(obj_name)
            if obj_idx >= 0 {
                si_add_dep(from_idx, obj_idx, DK_FIELD_ACCESS)
            }
        }
        walk_deps(obj, from_idx)
        return
    }

    if kind == NodeKind.Ident {
        let ref_name = np_name.unsafe_get(node)
        let ref_idx = sym_index(ref_name)
        if ref_idx >= 0 && ref_idx != from_idx {
            si_add_dep(from_idx, ref_idx, DK_USES_TYPE)
        }
        return
    }

    if kind == NodeKind.BinOp {
        walk_deps(np_left.unsafe_get(node), from_idx)
        walk_deps(np_right.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.UnaryOp {
        walk_deps(np_left.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.IfExpr {
        walk_deps(np_condition.unsafe_get(node), from_idx)
        walk_deps(np_then_body.unsafe_get(node), from_idx)
        walk_deps(np_else_body.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.Block {
        walk_dep_stmts(np_stmts.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.LetBinding {
        walk_deps(np_value.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.ExprStmt {
        walk_deps(np_value.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.Return {
        walk_deps(np_value.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        walk_deps(np_target.unsafe_get(node), from_idx)
        walk_deps(np_value.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.ForIn {
        walk_deps(np_iterable.unsafe_get(node), from_idx)
        walk_deps(np_body.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.WhileLoop {
        walk_deps(np_condition.unsafe_get(node), from_idx)
        walk_deps(np_body.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.LoopExpr {
        walk_deps(np_body.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.MatchExpr {
        walk_deps(np_scrutinee.unsafe_get(node), from_idx)
        let arms_sl = np_arms.unsafe_get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                walk_deps(np_guard.unsafe_get(arm), from_idx)
                walk_deps(np_body.unsafe_get(arm), from_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.IndexExpr {
        walk_deps(np_obj.unsafe_get(node), from_idx)
        walk_deps(np_index.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.TupleLit || kind == NodeKind.ListLit {
        let elems_sl = np_elements.unsafe_get(node)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                walk_deps(sublist_get(elems_sl, ei), from_idx)
                ei = ei + 1
            }
        }
        return
    }

    if kind == NodeKind.StructLit {
        let type_name = np_type_name.unsafe_get(node)
        let type_idx = sym_index(type_name)
        if type_idx >= 0 {
            si_add_dep(from_idx, type_idx, DK_USES_TYPE)
        }
        let fields_sl = np_fields.unsafe_get(node)
        if fields_sl != -1 {
            let mut fi = 0
            while fi < sublist_length(fields_sl) {
                let fld = sublist_get(fields_sl, fi)
                walk_deps(np_value.unsafe_get(fld), from_idx)
                fi = fi + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        walk_deps(np_body.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.unsafe_get(node)
        if parts_sl != -1 {
            let mut pi = 0
            while pi < sublist_length(parts_sl) {
                walk_deps(sublist_get(parts_sl, pi), from_idx)
                pi = pi + 1
            }
        }
        return
    }

    if kind == NodeKind.RangeLit {
        walk_deps(np_start.unsafe_get(node), from_idx)
        walk_deps(np_end.unsafe_get(node), from_idx)
        return
    }

    if kind == NodeKind.WithBlock {
        walk_deps(np_body.unsafe_get(node), from_idx)
        return
    }
}

fn walk_dep_stmts(stmts_sl: Int, from_idx: Int) {
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        walk_deps(sublist_get(stmts_sl, i), from_idx)
        i = i + 1
    }
}

// ── Build: register type references in return type / param types ──────

fn register_type_dep(from_idx: Int, type_name: Str) {
    if type_name == "" || type_name == "Int" || type_name == "Str" || type_name == "Float" || type_name == "Bool" || type_name == "Void" {
        return
    }
    let type_idx = sym_index(type_name)
    if type_idx >= 0 {
        si_add_dep(from_idx, type_idx, DK_USES_TYPE)
    }
}

// ── Build reverse deps from forward deps ──────────────────────────────

fn build_reverse_deps() {
    let mut i = 0
    while i < si_dep_count {
        add_rdep(si_dep_to.unsafe_get(i), si_dep_from.unsafe_get(i))
        i = i + 1
    }
}

// ── Entry point ───────────────────────────────────────────────────────

pub fn si_build(program: Int, file_path: Str, module_name: Str) {
    let file_sym_start = si_sym_count
    let file_idx = register_file(file_path, 0, file_sym_start)

    // Step 1: register all function symbols
    let fns_sl = np_params.unsafe_get(program)
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let name = np_name.unsafe_get(fn_node)
            let vis = if np_is_pub.unsafe_get(fn_node) != 0 { VIS_PUB } else { VIS_PRIVATE }
            let ret = np_return_type.unsafe_get(fn_node)
            let ptypes = collect_param_types(fn_node)
            let effs = collect_effects(fn_node)
            let sig = name.concat("(").concat(ptypes).concat(") -> ").concat(ret)
            add_symbol(name, SK_FN, module_name, file_path, np_line.unsafe_get(fn_node), vis, effs, sig, ret, ptypes)
            let fn_doc = np_doc_comment.unsafe_get(fn_node)
            si_sym_doc.push(fn_doc)
            si_sym_intent.push(extract_intent(fn_doc))
            si_sym_requires.push(extract_annotation_args(fn_node, "requires"))
            si_sym_ensures.push(extract_annotation_args(fn_node, "ensures"))
            si_sym_end_line.push(np_end_line.unsafe_get(fn_node))
            i = i + 1
        }
    }

    // Step 2: register type definitions (structs/enums)
    let types_sl = np_fields.unsafe_get(program)
    if types_sl != -1 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let type_node = sublist_get(types_sl, i)
            let name = np_name.unsafe_get(type_node)
            let vis = if np_is_pub.unsafe_get(type_node) != 0 { VIS_PUB } else { VIS_PRIVATE }
            let kind = np_kind.unsafe_get(type_node)
            let sym_kind = if kind == NodeKind.TypeDef { SK_STRUCT } else { SK_ENUM }
            add_symbol(name, sym_kind, module_name, file_path, np_line.unsafe_get(type_node), vis, "", "", "", "")
            let type_doc = np_doc_comment.unsafe_get(type_node)
            si_sym_doc.push(type_doc)
            si_sym_intent.push(extract_intent(type_doc))
            si_sym_requires.push("")
            si_sym_ensures.push("")
            si_sym_end_line.push(np_end_line.unsafe_get(type_node))
            i = i + 1
        }
    }

    // Step 3: register trait definitions
    let traits_sl = np_arms.unsafe_get(program)
    if traits_sl != -1 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            let trait_node = sublist_get(traits_sl, i)
            let name = np_name.unsafe_get(trait_node)
            let vis = if np_is_pub.unsafe_get(trait_node) != 0 { VIS_PUB } else { VIS_PRIVATE }
            add_symbol(name, SK_TRAIT, module_name, file_path, np_line.unsafe_get(trait_node), vis, "", "", "", "")
            let trait_doc = np_doc_comment.unsafe_get(trait_node)
            si_sym_doc.push(trait_doc)
            si_sym_intent.push(extract_intent(trait_doc))
            si_sym_requires.push("")
            si_sym_ensures.push("")
            si_sym_end_line.push(np_end_line.unsafe_get(trait_node))
            i = i + 1
        }
    }

    // Step 4: register module-level let bindings
    let lets_sl = np_stmts.unsafe_get(program)
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            if np_kind.unsafe_get(let_node) == NodeKind.LetBinding {
                let name = np_name.unsafe_get(let_node)
                let vis = if np_is_pub.unsafe_get(let_node) != 0 { VIS_PUB } else { VIS_PRIVATE }
                add_symbol(name, SK_LET, module_name, file_path, np_line.unsafe_get(let_node), vis, "", "", "", "")
                let let_doc = np_doc_comment.unsafe_get(let_node)
                si_sym_doc.push(let_doc)
                si_sym_intent.push(extract_intent(let_doc))
                si_sym_requires.push("")
                si_sym_ensures.push("")
                si_sym_end_line.push(np_line.unsafe_get(let_node))
            }
            i = i + 1
        }
    }

    // Update file symbol range end
    si_file_sym_end.set(file_idx, si_sym_count)

    // Step 5: walk function bodies to extract dependency edges
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fn_name = np_name.unsafe_get(fn_node)
            let fn_idx = sym_index(fn_name)
            if fn_idx >= 0 {
                // Register type deps from return type and param types
                register_type_dep(fn_idx, np_return_type.unsafe_get(fn_node))
                let params_sl = np_params.unsafe_get(fn_node)
                if params_sl != -1 {
                    let mut pi = 0
                    while pi < sublist_length(params_sl) {
                        let p = sublist_get(params_sl, pi)
                        register_type_dep(fn_idx, np_type_name.unsafe_get(p))
                        pi = pi + 1
                    }
                }
                // Walk body for call/field deps
                walk_deps(np_body.unsafe_get(fn_node), fn_idx)
            }
            i = i + 1
        }
    }

    // Step 6: build reverse dependency index
    build_reverse_deps()
}

// ── Query API ─────────────────────────────────────────────────────────

pub fn si_get_rdeps(sym_idx: Int) -> List[Int] {
    let mut result: List[Int] = []
    let mut i = 0
    while i < si_rdep_count {
        if si_rdep_from.unsafe_get(i) == sym_idx {
            result.push(si_rdep_to.unsafe_get(i))
        }
        i = i + 1
    }
    result
}

pub fn si_find_sym(name: Str) -> Int {
    if sym_name_map.has(name) != 0 {
        return sym_name_map.get(name)
    }
    -1
}

pub fn si_file_symbols(path: Str) -> List[Int] {
    let mut result: List[Int] = []
    if file_path_map.has(path) == 0 {
        return result
    }
    let file_idx = file_path_map.get(path)
    let start = si_file_sym_start.unsafe_get(file_idx)
    let end = si_file_sym_end.unsafe_get(file_idx)
    let mut i = start
    while i < end {
        result.push(i)
        i = i + 1
    }
    result
}

pub fn si_reset() {
    si_sym_name = []
    si_sym_kind = []
    si_sym_module = []
    si_sym_file = []
    si_sym_line = []
    si_sym_vis = []
    si_sym_effects = []
    si_sym_sig = []
    si_sym_ret_type = []
    si_sym_param_types = []
    si_sym_doc = []
    si_sym_intent = []
    si_sym_requires = []
    si_sym_ensures = []
    si_sym_end_line = []
    si_sym_count = 0

    si_dep_from = []
    si_dep_to = []
    si_dep_kind = []
    si_dep_count = 0

    si_rdep_from = []
    si_rdep_to = []
    si_rdep_count = 0

    si_file_path = []
    si_file_mtime = []
    si_file_sym_start = []
    si_file_sym_end = []
    si_file_count = 0

    sym_name_map = Map()
    file_path_map = Map()
}

// ── Convenience: symbol kind name ─────────────────────────────────────

pub fn sym_kind_name(kind: Int) -> Str {
    if kind == SK_FN { return "fn" }
    if kind == SK_STRUCT { return "struct" }
    if kind == SK_ENUM { return "enum" }
    if kind == SK_TRAIT { return "trait" }
    if kind == SK_LET { return "let" }
    "unknown"
}

// ── Convenience: dep kind name ────────────────────────────────────────

pub fn dep_kind_name(kind: Int) -> Str {
    if kind == DK_CALLS { return "calls" }
    if kind == DK_USES_TYPE { return "uses_type" }
    if kind == DK_FIELD_ACCESS { return "field_access" }
    "unknown"
}
