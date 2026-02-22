import ast
import parser

// mutation_analysis.pact — Tier 1 write-set inference for Pact modules
//
// Walks the AST after parsing to determine which module-level mutable
// bindings each function may write to (directly or transitively via
// intra-module calls). Results are stored for diagnostics/LSP.

// ── Parallel-array storage ────────────────────────────────────────────

pub let mut ma_fn_names: List[Str] = []
pub let mut ma_write_items: List[Str] = []
pub let mut ma_write_starts: List[Int] = []
pub let mut ma_write_counts: List[Int] = []

pub let mut ma_globals: List[Str] = []

// Call edges stored as indices (not names) for O(1) propagation
pub let mut ma_call_edges_from: List[Int] = []
pub let mut ma_call_edges_to: List[Int] = []

// Hash maps for O(1) lookups
let mut fn_name_map: Map[Str, Int] = Map()
let mut global_set: Map[Str, Int] = Map()
let mut global_idx_map: Map[Str, Int] = Map()

let mut mutating_method_set: Map[Str, Int] = Map()

fn init_mutating_methods() {
    if mutating_method_set.len() > 0 {
        return
    }
    mutating_method_set.set("push", 1)
    mutating_method_set.set("pop", 1)
    mutating_method_set.set("append", 1)
    mutating_method_set.set("clear", 1)
    mutating_method_set.set("insert", 1)
    mutating_method_set.set("remove", 1)
    mutating_method_set.set("set", 1)
}

fn is_mutating_method(name: Str) -> Int {
    mutating_method_set.has(name)
}

fn is_global(name: Str) -> Int {
    global_set.has(name)
}

fn fn_index(name: Str) -> Int {
    if fn_name_map.has(name) != 0 {
        return fn_name_map.get(name)
    }
    -1
}

fn global_index(name: Str) -> Int {
    if global_idx_map.has(name) != 0 {
        return global_idx_map.get(name)
    }
    -1
}

// Flat boolean matrix: writes_mat[fn_idx * num_globals + global_idx]
let mut writes_mat: List[Int] = []
let mut writes_mat_cols: Int = 0

fn mat_has_write(fn_idx: Int, gi: Int) -> Int {
    writes_mat.get(fn_idx * writes_mat_cols + gi)
}

fn mat_set_write(fn_idx: Int, gi: Int) {
    writes_mat.set(fn_idx * writes_mat_cols + gi, 1)
}

fn fn_has_write(fn_idx: Int, global_name: Str) -> Int {
    let gi = global_index(global_name)
    if gi < 0 {
        return 0
    }
    mat_has_write(fn_idx, gi)
}

fn add_write(fn_idx: Int, global_name: Str) {
    let gi = global_index(global_name)
    if gi < 0 {
        return
    }
    if mat_has_write(fn_idx, gi) != 0 {
        return
    }
    mat_set_write(fn_idx, gi)
    ma_write_items.push(global_name)
    ma_write_counts.set(fn_idx, ma_write_counts.get(fn_idx) + 1)
}

// ── AST walking ───────────────────────────────────────────────────────

fn extract_ident_name(node: Int) -> Str {
    if node == -1 {
        return ""
    }
    if np_kind.get(node) == NodeKind.Ident {
        return np_name.get(node)
    }
    ""
}

fn walk_expr(node: Int, fn_idx: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        let target = np_target.get(node)
        if target != -1 {
            let tk = np_kind.get(target)
            if tk == NodeKind.Ident {
                let tname = np_name.get(target)
                if is_global(tname) != 0 {
                    add_write(fn_idx, tname)
                }
            }
            if tk == NodeKind.FieldAccess {
                let obj = np_obj.get(target)
                if obj != -1 && np_kind.get(obj) == NodeKind.Ident {
                    let oname = np_name.get(obj)
                    if is_global(oname) != 0 {
                        add_write(fn_idx, oname)
                    }
                }
            }
            if tk == NodeKind.IndexExpr {
                let obj = np_obj.get(target)
                if obj != -1 && np_kind.get(obj) == NodeKind.Ident {
                    let oname = np_name.get(obj)
                    if is_global(oname) != 0 {
                        add_write(fn_idx, oname)
                    }
                }
            }
        }
        walk_expr(np_value.get(node), fn_idx)
        return
    }

    if kind == NodeKind.MethodCall {
        let obj = np_obj.get(node)
        let method = np_method.get(node)
        if obj != -1 && np_kind.get(obj) == NodeKind.Ident {
            let oname = np_name.get(obj)
            if is_global(oname) != 0 && is_mutating_method(method) != 0 {
                add_write(fn_idx, oname)
            }
        }
        walk_expr(obj, fn_idx)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_expr(sublist_get(args_sl, ai), fn_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.Call {
        let callee = np_left.get(node)
        let callee_name = extract_ident_name(callee)
        if callee_name != "" {
            let callee_idx = fn_index(callee_name)
            if callee_idx >= 0 {
                ma_call_edges_from.push(fn_idx)
                ma_call_edges_to.push(callee_idx)
            }
        }
        walk_expr(callee, fn_idx)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_expr(sublist_get(args_sl, ai), fn_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.BinOp {
        walk_expr(np_left.get(node), fn_idx)
        walk_expr(np_right.get(node), fn_idx)
        return
    }

    if kind == NodeKind.UnaryOp {
        walk_expr(np_left.get(node), fn_idx)
        return
    }

    if kind == NodeKind.IfExpr {
        walk_expr(np_condition.get(node), fn_idx)
        walk_expr(np_then_body.get(node), fn_idx)
        walk_expr(np_else_body.get(node), fn_idx)
        return
    }

    if kind == NodeKind.Block {
        walk_stmts(np_stmts.get(node), fn_idx)
        return
    }

    if kind == NodeKind.LetBinding {
        walk_expr(np_value.get(node), fn_idx)
        return
    }

    if kind == NodeKind.ExprStmt {
        walk_expr(np_value.get(node), fn_idx)
        return
    }

    if kind == NodeKind.Return {
        walk_expr(np_value.get(node), fn_idx)
        return
    }

    if kind == NodeKind.ForIn {
        walk_expr(np_iterable.get(node), fn_idx)
        walk_expr(np_body.get(node), fn_idx)
        return
    }

    if kind == NodeKind.WhileLoop {
        walk_expr(np_condition.get(node), fn_idx)
        walk_expr(np_body.get(node), fn_idx)
        return
    }

    if kind == NodeKind.LoopExpr {
        walk_expr(np_body.get(node), fn_idx)
        return
    }

    if kind == NodeKind.MatchExpr {
        walk_expr(np_scrutinee.get(node), fn_idx)
        let arms_sl = np_arms.get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                walk_expr(np_guard.get(arm), fn_idx)
                walk_expr(np_body.get(arm), fn_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.FieldAccess {
        walk_expr(np_obj.get(node), fn_idx)
        return
    }

    if kind == NodeKind.IndexExpr {
        walk_expr(np_obj.get(node), fn_idx)
        walk_expr(np_index.get(node), fn_idx)
        return
    }

    if kind == NodeKind.TupleLit || kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                walk_expr(sublist_get(elems_sl, ei), fn_idx)
                ei = ei + 1
            }
        }
        return
    }

    if kind == NodeKind.StructLit {
        let fields_sl = np_fields.get(node)
        if fields_sl != -1 {
            let mut fi = 0
            while fi < sublist_length(fields_sl) {
                let fld = sublist_get(fields_sl, fi)
                walk_expr(np_value.get(fld), fn_idx)
                fi = fi + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        walk_expr(np_body.get(node), fn_idx)
        return
    }

    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node)
        if parts_sl != -1 {
            let mut pi = 0
            while pi < sublist_length(parts_sl) {
                walk_expr(sublist_get(parts_sl, pi), fn_idx)
                pi = pi + 1
            }
        }
        return
    }

    if kind == NodeKind.RangeLit {
        walk_expr(np_start.get(node), fn_idx)
        walk_expr(np_end.get(node), fn_idx)
        return
    }

    if kind == NodeKind.WithBlock {
        walk_expr(np_body.get(node), fn_idx)
        return
    }
}

fn walk_stmts(stmts_sl: Int, fn_idx: Int) {
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        walk_expr(sublist_get(stmts_sl, i), fn_idx)
        i = i + 1
    }
}

// ── Transitive closure ────────────────────────────────────────────────

fn propagate_writes() -> Int {
    let mut changed = 0
    let num_globals = ma_globals.len()
    let mut ei = 0
    while ei < ma_call_edges_from.len() {
        let caller_idx = ma_call_edges_from.get(ei)
        let callee_idx = ma_call_edges_to.get(ei)
        let mut gi = 0
        while gi < num_globals {
            if mat_has_write(callee_idx, gi) != 0 && mat_has_write(caller_idx, gi) == 0 {
                mat_set_write(caller_idx, gi)
                changed = 1
            }
            gi = gi + 1
        }
        ei = ei + 1
    }
    changed
}

fn rebuild_write_lists() {
    ma_write_items = []
    ma_write_starts = []
    ma_write_counts = []
    let num_globals = ma_globals.len()
    let mut fi = 0
    while fi < ma_fn_names.len() {
        let start = ma_write_items.len()
        ma_write_starts.push(start)
        let mut count = 0
        let mut gi = 0
        while gi < num_globals {
            if mat_has_write(fi, gi) != 0 {
                ma_write_items.push(ma_globals.get(gi))
                count = count + 1
            }
            gi = gi + 1
        }
        ma_write_counts.push(count)
        fi = fi + 1
    }
}

// ── Entry point ───────────────────────────────────────────────────────

pub fn analyze_mutations(program: Int) {
    init_mutating_methods()

    ma_fn_names = []
    ma_write_items = []
    ma_write_starts = []
    ma_write_counts = []
    ma_globals = []
    ma_call_edges_from = []
    ma_call_edges_to = []
    fn_name_map = Map()
    global_set = Map()
    global_idx_map = Map()

    // Step 1: collect module-level let mut bindings
    let lets_sl = np_stmts.get(program)
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            if np_kind.get(let_node) == NodeKind.LetBinding && np_is_mut.get(let_node) != 0 {
                let gname = np_name.get(let_node)
                ma_globals.push(gname)
                global_set.set(gname, 1)
                global_idx_map.set(gname, ma_globals.len() - 1)
            }
            i = i + 1
        }
    }

    // Step 2: register all function names
    let fns_sl = np_params.get(program)
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fname = np_name.get(fn_node)
            ma_fn_names.push(fname)
            fn_name_map.set(fname, i)
            ma_write_starts.push(0)
            ma_write_counts.push(0)
            i = i + 1
        }
    }

    // Init boolean matrix: fns × globals
    writes_mat_cols = ma_globals.len()
    writes_mat = []
    let mat_size = ma_fn_names.len() * writes_mat_cols
    let mut mi = 0
    while mi < mat_size {
        writes_mat.push(0)
        mi = mi + 1
    }

    // Step 3: walk each function body to find direct writes and call edges
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let body = np_body.get(fn_node)
            walk_expr(body, i)
            i = i + 1
        }
    }

    // Step 4: transitive closure — propagate callee writes to callers
    let mut max_iters = ma_fn_names.len() + 1
    let mut iter = 0
    while iter < max_iters {
        if propagate_writes() == 0 {
            iter = max_iters
        }
        iter = iter + 1
    }

    // Step 5: rebuild write lists from matrix
    rebuild_write_lists()
}

// ── Query API ─────────────────────────────────────────────────────────

pub fn get_fn_write_count(name: Str) -> Int {
    let idx = fn_index(name)
    if idx >= 0 {
        return ma_write_counts.get(idx)
    }
    0
}

pub fn get_fn_write_at(name: Str, wi: Int) -> Str {
    let idx = fn_index(name)
    if idx >= 0 {
        let start = ma_write_starts.get(idx)
        return ma_write_items.get(start + wi)
    }
    ""
}

pub fn get_all_globals() -> List[Str] {
    ma_globals
}

pub fn fn_writes_to(fn_name: Str, global_name: Str) -> Int {
    let idx = fn_index(fn_name)
    if idx >= 0 {
        return fn_has_write(idx, global_name)
    }
    0
}
