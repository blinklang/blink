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
let SK_STRUCT = 1
let SK_ENUM = 2
pub let SK_TRAIT = 3
pub let SK_LET = 4

// ── Dependency kind constants ─────────────────────────────────────────

let DK_CALLS = 0
let DK_USES_TYPE = 1
let DK_FIELD_ACCESS = 2

// ── Visibility constants ──────────────────────────────────────────────

let VIS_PRIVATE = 0
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
let mut si_sym_ret_type: List[Str] = []
let mut si_sym_param_types: List[Str] = []
pub let mut si_sym_doc: List[Str] = []
pub let mut si_sym_intent: List[Str] = []
pub let mut si_sym_requires: List[Str] = []
pub let mut si_sym_ensures: List[Str] = []
pub let mut si_sym_end_line: List[Int] = []
pub let mut si_sym_col: List[Int] = []
pub let mut si_sym_end_col: List[Int] = []

pub let mut si_sym_count: Int = 0

// ── Forward dependency arrays ─────────────────────────────────────────

pub let mut si_dep_from: List[Int] = []
let mut si_dep_to: List[Int] = []
let mut si_dep_kind: List[Int] = []
pub let mut si_dep_line: List[Int] = []
pub let mut si_dep_col: List[Int] = []
pub let mut si_dep_name_len: List[Int] = []

let mut si_dep_count: Int = 0

// ── Reverse dependency arrays ─────────────────────────────────────────

let mut si_rdep_from: List[Int] = []
let mut si_rdep_to: List[Int] = []

let mut si_rdep_count: Int = 0

// ── File tracking ─────────────────────────────────────────────────────

pub let mut si_file_path: List[Str] = []
let mut si_file_mtime: List[Int] = []
let mut si_file_sym_start: List[Int] = []
let mut si_file_sym_end: List[Int] = []

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
    let anns_sl = np_handlers.get(node).unwrap()
    if anns_sl == -1 {
        return ""
    }
    let mut result = ""
    let mut i = 0
    while i < sublist_length(anns_sl) {
        let ann = sublist_get(anns_sl, i)
        if np_name.get(ann).unwrap() == ann_name {
            let args_sl = np_args.get(ann).unwrap()
            if args_sl != -1 {
                let mut j = 0
                while j < sublist_length(args_sl) {
                    if result != "" {
                        result = result.concat(",")
                    }
                    result = result.concat(np_name.get(sublist_get(args_sl, j)).unwrap())
                    j = j + 1
                }
            }
        }
        i = i + 1
    }
    result
}

fn add_symbol(name: Str, kind: Int, module: Str, file: Str, line: Int, col: Int, vis: Int, effects: Str, sig: Str, ret_type: Str, param_types: Str) -> Int {
    let idx = si_sym_count
    si_sym_name.push(name)
    si_sym_kind.push(kind)
    si_sym_module.push(module)
    si_sym_file.push(file)
    si_sym_line.push(line)
    si_sym_col.push(col)
    si_sym_vis.push(vis)
    si_sym_effects.push(effects)
    si_sym_sig.push(sig)
    si_sym_ret_type.push(ret_type)
    si_sym_param_types.push(param_types)
    sym_name_map.set(name, idx)
    si_sym_count = si_sym_count + 1
    idx
}

fn si_add_dep(from_idx: Int, to_idx: Int, kind: Int, line: Int, col: Int, name_len: Int) {
    si_dep_from.push(from_idx)
    si_dep_to.push(to_idx)
    si_dep_kind.push(kind)
    si_dep_line.push(line)
    si_dep_col.push(col)
    si_dep_name_len.push(name_len)
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
    let params_sl = np_params.get(fn_node).unwrap()
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
        result = result.concat(np_type_name.get(p).unwrap())
        i = i + 1
    }
    result
}

pub fn collect_effects(fn_node: Int) -> Str {
    let eff_sl = np_effects.get(fn_node).unwrap()
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
        result = result.concat(np_name.get(e).unwrap())
        i = i + 1
    }
    result
}

// ── Build: walk expressions for dependency extraction ─────────────────

fn walk_deps(node: Int, from_idx: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.Call {
        let callee = np_left.get(node).unwrap()
        if callee != -1 && np_kind.get(callee).unwrap() == NodeKind.Ident {
            let callee_name = np_name.get(callee).unwrap()
            let callee_idx = sym_index(callee_name)
            if callee_idx >= 0 {
                si_add_dep(from_idx, callee_idx, DK_CALLS, np_line.get(callee).unwrap(), np_col.get(callee).unwrap(), callee_name.len())
            }
        } else {
            walk_deps(callee, from_idx)
        }
        let args_sl = np_args.get(node).unwrap()
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
        walk_deps(np_obj.get(node).unwrap(), from_idx)
        let args_sl = np_args.get(node).unwrap()
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
        let obj = np_obj.get(node).unwrap()
        if obj != -1 && np_kind.get(obj).unwrap() == NodeKind.Ident {
            let obj_name = np_name.get(obj).unwrap()
            let obj_idx = sym_index(obj_name)
            if obj_idx >= 0 {
                si_add_dep(from_idx, obj_idx, DK_FIELD_ACCESS, np_line.get(obj).unwrap(), np_col.get(obj).unwrap(), obj_name.len())
            }
        } else {
            walk_deps(obj, from_idx)
        }
        return
    }

    if kind == NodeKind.Ident {
        let ref_name = np_name.get(node).unwrap()
        let ref_idx = sym_index(ref_name)
        if ref_idx >= 0 && ref_idx != from_idx {
            si_add_dep(from_idx, ref_idx, DK_USES_TYPE, np_line.get(node).unwrap(), np_col.get(node).unwrap(), ref_name.len())
        }
        return
    }

    if kind == NodeKind.BinOp {
        walk_deps(np_left.get(node).unwrap(), from_idx)
        walk_deps(np_right.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.UnaryOp {
        walk_deps(np_left.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.IfExpr {
        walk_deps(np_condition.get(node).unwrap(), from_idx)
        walk_deps(np_then_body.get(node).unwrap(), from_idx)
        walk_deps(np_else_body.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.Block {
        walk_dep_stmts(np_stmts.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.LetBinding {
        walk_deps(np_value.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.ExprStmt {
        walk_deps(np_value.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.Return {
        walk_deps(np_value.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        walk_deps(np_target.get(node).unwrap(), from_idx)
        walk_deps(np_value.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.ForIn {
        walk_deps(np_iterable.get(node).unwrap(), from_idx)
        walk_deps(np_body.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.WhileLoop {
        walk_deps(np_condition.get(node).unwrap(), from_idx)
        walk_deps(np_body.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.LoopExpr {
        walk_deps(np_body.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.MatchExpr {
        walk_deps(np_scrutinee.get(node).unwrap(), from_idx)
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                walk_deps(np_guard.get(arm).unwrap(), from_idx)
                walk_deps(np_body.get(arm).unwrap(), from_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.IndexExpr {
        walk_deps(np_obj.get(node).unwrap(), from_idx)
        walk_deps(np_index.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.TupleLit || kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node).unwrap()
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
        let type_name = np_type_name.get(node).unwrap()
        let type_idx = sym_index(type_name)
        if type_idx >= 0 {
            si_add_dep(from_idx, type_idx, DK_USES_TYPE, np_line.get(node).unwrap(), np_col.get(node).unwrap(), type_name.len())
        }
        let fields_sl = np_fields.get(node).unwrap()
        if fields_sl != -1 {
            let mut fi = 0
            while fi < sublist_length(fields_sl) {
                let fld = sublist_get(fields_sl, fi)
                walk_deps(np_value.get(fld).unwrap(), from_idx)
                fi = fi + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        walk_deps(np_body.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node).unwrap()
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
        walk_deps(np_start.get(node).unwrap(), from_idx)
        walk_deps(np_end.get(node).unwrap(), from_idx)
        return
    }

    if kind == NodeKind.WithBlock {
        walk_deps(np_body.get(node).unwrap(), from_idx)
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
        si_add_dep(from_idx, type_idx, DK_USES_TYPE, 0, 0, 0)
    }
}

// ── Build reverse deps from forward deps ──────────────────────────────

fn build_reverse_deps() {
    let mut i = 0
    while i < si_dep_count {
        add_rdep(si_dep_to.get(i).unwrap(), si_dep_from.get(i).unwrap())
        i = i + 1
    }
}

// ── Entry point ───────────────────────────────────────────────────────

@allow(UnrestoredMutation, IncompleteStateRestore)
pub fn si_build(program: Int, file_path: Str, module_name: Str) {
    let file_sym_start = si_sym_count
    let file_idx = register_file(file_path, 0, file_sym_start)

    // Step 1: register all function symbols
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let name = np_name.get(fn_node).unwrap()
            let vis = if np_is_pub.get(fn_node).unwrap() != 0 { VIS_PUB } else { VIS_PRIVATE }
            let ret = np_return_type.get(fn_node).unwrap()
            let ptypes = collect_param_types(fn_node)
            let effs = collect_effects(fn_node)
            let sig = name.concat("(").concat(ptypes).concat(") -> ").concat(ret)
            add_symbol(name, SK_FN, module_name, file_path, np_line.get(fn_node).unwrap(), np_col.get(fn_node).unwrap(), vis, effs, sig, ret, ptypes)
            let fn_doc = np_doc_comment.get(fn_node).unwrap()
            si_sym_doc.push(fn_doc)
            si_sym_intent.push(extract_intent(fn_doc))
            si_sym_requires.push(extract_annotation_args(fn_node, "requires"))
            si_sym_ensures.push(extract_annotation_args(fn_node, "ensures"))
            si_sym_end_line.push(np_end_line.get(fn_node).unwrap())
            si_sym_end_col.push(np_end_col.get(fn_node).unwrap())
            i = i + 1
        }
    }

    // Step 2: register type definitions (structs/enums)
    let types_sl = np_fields.get(program).unwrap()
    if types_sl != -1 {
        let mut i = 0
        while i < sublist_length(types_sl) {
            let type_node = sublist_get(types_sl, i)
            let name = np_name.get(type_node).unwrap()
            let vis = if np_is_pub.get(type_node).unwrap() != 0 { VIS_PUB } else { VIS_PRIVATE }
            let kind = np_kind.get(type_node).unwrap()
            let sym_kind = if kind == NodeKind.TypeDef { SK_STRUCT } else { SK_ENUM }
            add_symbol(name, sym_kind, module_name, file_path, np_line.get(type_node).unwrap(), np_col.get(type_node).unwrap(), vis, "", "", "", "")
            let type_doc = np_doc_comment.get(type_node).unwrap()
            si_sym_doc.push(type_doc)
            si_sym_intent.push(extract_intent(type_doc))
            si_sym_requires.push("")
            si_sym_ensures.push("")
            si_sym_end_line.push(np_end_line.get(type_node).unwrap())
            si_sym_end_col.push(np_end_col.get(type_node).unwrap())
            i = i + 1
        }
    }

    // Step 3: register trait definitions
    let traits_sl = np_arms.get(program).unwrap()
    if traits_sl != -1 {
        let mut i = 0
        while i < sublist_length(traits_sl) {
            let trait_node = sublist_get(traits_sl, i)
            let name = np_name.get(trait_node).unwrap()
            let vis = if np_is_pub.get(trait_node).unwrap() != 0 { VIS_PUB } else { VIS_PRIVATE }
            add_symbol(name, SK_TRAIT, module_name, file_path, np_line.get(trait_node).unwrap(), np_col.get(trait_node).unwrap(), vis, "", "", "", "")
            let trait_doc = np_doc_comment.get(trait_node).unwrap()
            si_sym_doc.push(trait_doc)
            si_sym_intent.push(extract_intent(trait_doc))
            si_sym_requires.push("")
            si_sym_ensures.push("")
            si_sym_end_line.push(np_end_line.get(trait_node).unwrap())
            si_sym_end_col.push(np_end_col.get(trait_node).unwrap())
            i = i + 1
        }
    }

    // Step 4: register module-level let bindings
    let lets_sl = np_stmts.get(program).unwrap()
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            if np_kind.get(let_node).unwrap() == NodeKind.LetBinding {
                let name = np_name.get(let_node).unwrap()
                let vis = if np_is_pub.get(let_node).unwrap() != 0 { VIS_PUB } else { VIS_PRIVATE }
                add_symbol(name, SK_LET, module_name, file_path, np_line.get(let_node).unwrap(), np_col.get(let_node).unwrap(), vis, "", "", "", "")
                let let_doc = np_doc_comment.get(let_node).unwrap()
                si_sym_doc.push(let_doc)
                si_sym_intent.push(extract_intent(let_doc))
                si_sym_requires.push("")
                si_sym_ensures.push("")
                si_sym_end_line.push(np_line.get(let_node).unwrap())
                si_sym_end_col.push(np_end_col.get(let_node).unwrap())
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
            let fn_name = np_name.get(fn_node).unwrap()
            let fn_idx = sym_index(fn_name)
            if fn_idx >= 0 {
                // Register type deps from return type and param types
                register_type_dep(fn_idx, np_return_type.get(fn_node).unwrap())
                let params_sl = np_params.get(fn_node).unwrap()
                if params_sl != -1 {
                    let mut pi = 0
                    while pi < sublist_length(params_sl) {
                        let p = sublist_get(params_sl, pi)
                        register_type_dep(fn_idx, np_type_name.get(p).unwrap())
                        pi = pi + 1
                    }
                }
                // Walk body for call/field deps
                walk_deps(np_body.get(fn_node).unwrap(), fn_idx)
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
        if si_rdep_from.get(i).unwrap() == sym_idx {
            result.push(si_rdep_to.get(i).unwrap())
        }
        i = i + 1
    }
    result
}

pub fn si_get_ref_locations(sym_idx: Int) -> List[Int] {
    let mut result: List[Int] = []
    let mut i = 0
    while i < si_dep_count {
        if si_dep_to.get(i).unwrap() == sym_idx && si_dep_line.get(i).unwrap() > 0 {
            result.push(i)
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
    let start = si_file_sym_start.get(file_idx).unwrap()
    let end = si_file_sym_end.get(file_idx).unwrap()
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
    si_sym_col = []
    si_sym_end_col = []
    si_sym_count = 0

    si_dep_from = []
    si_dep_to = []
    si_dep_kind = []
    si_dep_line = []
    si_dep_col = []
    si_dep_name_len = []
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

fn dep_kind_name(kind: Int) -> Str {
    if kind == DK_CALLS { return "calls" }
    if kind == DK_USES_TYPE { return "uses_type" }
    if kind == DK_FIELD_ACCESS { return "field_access" }
    "unknown"
}

pub fn si_symbol_at(file: Str, line: Int, col: Int) -> Int {
    let syms = si_file_symbols(file)
    let mut best = -1
    let mut best_size = 999999
    let mut i = 0
    while i < syms.len() {
        let idx = syms.get(i).unwrap()
        let sym_line = si_sym_line.get(idx).unwrap()
        let sym_col = si_sym_col.get(idx).unwrap()
        let sym_end_line = si_sym_end_line.get(idx).unwrap()
        let sym_end_col = si_sym_end_col.get(idx).unwrap()
        let after_start = if line > sym_line { 1 } else if line == sym_line && col >= sym_col { 1 } else { 0 }
        let before_end = if line < sym_end_line { 1 } else if line == sym_end_line && col <= sym_end_col { 1 } else { 0 }
        if after_start != 0 && before_end != 0 {
            let size = (sym_end_line - sym_line) * 1000 + (sym_end_col - sym_col)
            if size < best_size {
                best = idx
                best_size = size
            }
        }
        i = i + 1
    }
    best
}
