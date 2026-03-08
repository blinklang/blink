import ast
import parser
import diagnostics

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
    writes_mat.get(fn_idx * writes_mat_cols + gi).unwrap()
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
    ma_write_counts.set(fn_idx, ma_write_counts.get(fn_idx).unwrap() + 1)
}

// ── AST walking ───────────────────────────────────────────────────────

fn extract_ident_name(node: Int) -> Str {
    if node == -1 {
        return ""
    }
    if np_kind.get(node).unwrap() == NodeKind.Ident {
        return np_name.get(node).unwrap()
    }
    ""
}

fn walk_expr(node: Int, fn_idx: Int) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        let target = np_target.get(node).unwrap()
        if target != -1 {
            let tk = np_kind.get(target).unwrap()
            if tk == NodeKind.Ident {
                let tname = np_name.get(target).unwrap()
                if is_global(tname) != 0 {
                    add_write(fn_idx, tname)
                }
            }
            if tk == NodeKind.FieldAccess {
                let obj = np_obj.get(target).unwrap()
                if obj != -1 && np_kind.get(obj).unwrap() == NodeKind.Ident {
                    let oname = np_name.get(obj).unwrap()
                    if is_global(oname) != 0 {
                        add_write(fn_idx, oname)
                    }
                }
            }
            if tk == NodeKind.IndexExpr {
                let obj = np_obj.get(target).unwrap()
                if obj != -1 && np_kind.get(obj).unwrap() == NodeKind.Ident {
                    let oname = np_name.get(obj).unwrap()
                    if is_global(oname) != 0 {
                        add_write(fn_idx, oname)
                    }
                }
            }
        }
        walk_expr(np_value.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.MethodCall {
        let obj = np_obj.get(node).unwrap()
        let method = np_method.get(node).unwrap()
        if obj != -1 && np_kind.get(obj).unwrap() == NodeKind.Ident {
            let oname = np_name.get(obj).unwrap()
            if is_global(oname) != 0 && is_mutating_method(method) != 0 {
                add_write(fn_idx, oname)
            }
        }
        walk_expr(obj, fn_idx)
        let args_sl = np_args.get(node).unwrap()
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
        let callee = np_left.get(node).unwrap()
        let callee_name = extract_ident_name(callee)
        if callee_name != "" {
            let callee_idx = fn_index(callee_name)
            if callee_idx >= 0 {
                ma_call_edges_from.push(fn_idx)
                ma_call_edges_to.push(callee_idx)
            }
        }
        walk_expr(callee, fn_idx)
        let args_sl = np_args.get(node).unwrap()
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
        walk_expr(np_left.get(node).unwrap(), fn_idx)
        walk_expr(np_right.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.UnaryOp {
        walk_expr(np_left.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.IfExpr {
        walk_expr(np_condition.get(node).unwrap(), fn_idx)
        walk_expr(np_then_body.get(node).unwrap(), fn_idx)
        walk_expr(np_else_body.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.Block {
        walk_stmts(np_stmts.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.LetBinding {
        walk_expr(np_value.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.ExprStmt {
        walk_expr(np_value.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.Return {
        walk_expr(np_value.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.ForIn {
        walk_expr(np_iterable.get(node).unwrap(), fn_idx)
        walk_expr(np_body.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.WhileLoop {
        walk_expr(np_condition.get(node).unwrap(), fn_idx)
        walk_expr(np_body.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.LoopExpr {
        walk_expr(np_body.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.MatchExpr {
        walk_expr(np_scrutinee.get(node).unwrap(), fn_idx)
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                walk_expr(np_guard.get(arm).unwrap(), fn_idx)
                walk_expr(np_body.get(arm).unwrap(), fn_idx)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.FieldAccess {
        walk_expr(np_obj.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.IndexExpr {
        walk_expr(np_obj.get(node).unwrap(), fn_idx)
        walk_expr(np_index.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.TupleLit || kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node).unwrap()
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
        let fields_sl = np_fields.get(node).unwrap()
        if fields_sl != -1 {
            let mut fi = 0
            while fi < sublist_length(fields_sl) {
                let fld = sublist_get(fields_sl, fi)
                walk_expr(np_value.get(fld).unwrap(), fn_idx)
                fi = fi + 1
            }
        }
        return
    }

    if kind == NodeKind.Closure {
        walk_expr(np_body.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node).unwrap()
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
        walk_expr(np_start.get(node).unwrap(), fn_idx)
        walk_expr(np_end.get(node).unwrap(), fn_idx)
        return
    }

    if kind == NodeKind.WithBlock {
        walk_expr(np_body.get(node).unwrap(), fn_idx)
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
        let caller_idx = ma_call_edges_from.get(ei).unwrap()
        let callee_idx = ma_call_edges_to.get(ei).unwrap()
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
                ma_write_items.push(ma_globals.get(gi).unwrap())
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
    let lets_sl = np_stmts.get(program).unwrap()
    if lets_sl != -1 {
        let mut i = 0
        while i < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, i)
            if np_kind.get(let_node).unwrap() == NodeKind.LetBinding && np_is_mut.get(let_node).unwrap() != 0 {
                let gname = np_name.get(let_node).unwrap()
                ma_globals.push(gname)
                global_set.set(gname, 1)
                global_idx_map.set(gname, ma_globals.len() - 1)
            }
            i = i + 1
        }
    }

    // Step 2: register all function names
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl != -1 {
        let mut i = 0
        while i < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, i)
            let fname = np_name.get(fn_node).unwrap()
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
            let body = np_body.get(fn_node).unwrap()
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
        return ma_write_counts.get(idx).unwrap()
    }
    0
}

pub fn get_fn_write_at(name: Str, wi: Int) -> Str {
    let idx = fn_index(name)
    if idx >= 0 {
        let start = ma_write_starts.get(idx).unwrap()
        return ma_write_items.get(start + wi).unwrap()
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

// ── W0550/W0551 Save/Restore pattern detection ──────────────────────

// Per-block analysis scratch state
let mut sr_save_local: List[Str] = []
let mut sr_save_global: List[Str] = []
let mut sr_restore_globals: Map[Str, Int] = Map()
let mut sr_current_fn: Str = ""
let mut sr_fn_has_save_restore: Int = 0
let mut sr_allow_w0550: Int = 0
let mut sr_allow_w0551: Int = 0

fn sr_reset() {
    sr_save_local = []
    sr_save_global = []
    sr_restore_globals = Map()
}

fn sr_add_save(local_name: Str, global_name: Str) {
    sr_save_local.push(local_name)
    sr_save_global.push(global_name)
}

fn sr_is_save_local(name: Str) -> Str {
    let mut i = 0
    while i < sr_save_local.len() {
        if sr_save_local.get(i).unwrap() == name {
            return sr_save_global.get(i).unwrap()
        }
        i = i + 1
    }
    ""
}

fn sr_is_saved_global(name: Str) -> Int {
    let mut i = 0
    while i < sr_save_global.len() {
        if sr_save_global.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

fn sr_check_call(call_node: Int, callee_name: Str) ! Diag.Report {
    let callee_idx = fn_index(callee_name)
    if callee_idx < 0 {
        return
    }
    let wcount = ma_write_counts.get(callee_idx).unwrap()
    if wcount == 0 {
        return
    }

    let wstart = ma_write_starts.get(callee_idx).unwrap()
    let mut saved_count = 0
    let mut unsaved: List[Str] = []

    let mut wi = 0
    while wi < wcount {
        let gname = ma_write_items.get(wstart + wi).unwrap()
        if sr_is_saved_global(gname) != 0 {
            saved_count = saved_count + 1
        } else {
            unsaved.push(gname)
        }
        wi = wi + 1
    }

    if saved_count > 0 && unsaved.len() > 0 && sr_allow_w0550 == 0 {
        let mut missing = ""
        let mut ui = 0
        while ui < unsaved.len() {
            if ui > 0 {
                missing = missing.concat(", ")
            }
            missing = missing.concat(unsaved.get(ui).unwrap())
            ui = ui + 1
        }
        diag_warn_at(
            "IncompleteStateRestore", "W0550",
            "call to '{callee_name}' in '{sr_current_fn}' mutates [{missing}] which are not saved/restored (write-set: {wcount} globals, saved: {saved_count})",
            call_node,
            "save and restore [{missing}] around this call, or verify the mutation is intentional"
        )
    }

    if saved_count == 0 && sr_fn_has_save_restore != 0 && sr_allow_w0551 == 0 {
        let mut all_writes = ""
        wi = 0
        while wi < wcount {
            if wi > 0 {
                all_writes = all_writes.concat(", ")
            }
            all_writes = all_writes.concat(ma_write_items.get(wstart + wi).unwrap())
            wi = wi + 1
        }
        diag_warn_at(
            "UnrestoredMutation", "W0551",
            "call to '{callee_name}' in '{sr_current_fn}' mutates [{all_writes}] with no save/restore pattern",
            call_node,
            "if this call is speculative, save/restore affected globals"
        )
    }
}

fn sr_scan_stmts(stmts_sl: Int) ! Diag.Report {
    if stmts_sl == -1 {
        return
    }
    let num_stmts = sublist_length(stmts_sl)
    let mut i = 0

    // Pass 1: collect all saves and restores in this block
    while i < num_stmts {
        let stmt = sublist_get(stmts_sl, i)
        let kind = np_kind.get(stmt).unwrap()

        if kind == NodeKind.LetBinding {
            let local_name = np_name.get(stmt).unwrap()
            let val = np_value.get(stmt).unwrap()
            if val != -1 && np_kind.get(val).unwrap() == NodeKind.Ident {
                let val_name = np_name.get(val).unwrap()
                if is_global(val_name) != 0 {
                    sr_add_save(local_name, val_name)
                }
            }
        }

        if kind == NodeKind.Assignment {
            let target = np_target.get(stmt).unwrap()
            let val = np_value.get(stmt).unwrap()
            if target != -1 && val != -1 {
                if np_kind.get(target).unwrap() == NodeKind.Ident && np_kind.get(val).unwrap() == NodeKind.Ident {
                    let tname = np_name.get(target).unwrap()
                    let vname = np_name.get(val).unwrap()
                    let mapped = sr_is_save_local(vname)
                    if mapped != "" && mapped == tname {
                        sr_restore_globals.set(tname, 1)
                    }
                }
            }
        }

        i = i + 1
    }

    // Pass 2: check each call against the save/restore sets
    i = 0
    while i < num_stmts {
        let stmt = sublist_get(stmts_sl, i)
        let kind = np_kind.get(stmt).unwrap()

        if kind == NodeKind.ExprStmt {
            let inner = np_value.get(stmt).unwrap()
            if inner != -1 {
                let ik = np_kind.get(inner).unwrap()
                if ik == NodeKind.Call {
                    let callee = np_left.get(inner).unwrap()
                    let cname = extract_ident_name(callee)
                    if cname != "" {
                        sr_check_call(inner, cname)
                    }
                }
            }
        }

        if kind == NodeKind.Call {
            let callee = np_left.get(stmt).unwrap()
            let cname = extract_ident_name(callee)
            if cname != "" {
                sr_check_call(stmt, cname)
            }
        }

        i = i + 1
    }

    // Pass 3: recurse into nested blocks (if, while, match, etc.)
    i = 0
    while i < num_stmts {
        let stmt = sublist_get(stmts_sl, i)
        sr_scan_node(stmt)
        i = i + 1
    }
}

fn sr_scan_node(node: Int) ! Diag.Report {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node).unwrap()

    if kind == NodeKind.Block {
        let outer_saves_l = sr_save_local
        let outer_saves_g = sr_save_global
        let outer_restores = sr_restore_globals
        sr_save_local = []
        sr_save_global = []
        sr_restore_globals = Map()
        sr_scan_stmts(np_stmts.get(node).unwrap())
        sr_save_local = outer_saves_l
        sr_save_global = outer_saves_g
        sr_restore_globals = outer_restores
        return
    }

    if kind == NodeKind.IfExpr {
        sr_scan_node(np_then_body.get(node).unwrap())
        sr_scan_node(np_else_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.WhileLoop {
        sr_scan_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.ForIn {
        sr_scan_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.LoopExpr {
        sr_scan_node(np_body.get(node).unwrap())
        return
    }

    if kind == NodeKind.MatchExpr {
        let arms_sl = np_arms.get(node).unwrap()
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                sr_scan_node(np_body.get(arm).unwrap())
                ai = ai + 1
            }
        }
        return
    }
}

fn sr_prescan_has_save(stmts_sl: Int) -> Int {
    if stmts_sl == -1 {
        return 0
    }
    let num_stmts = sublist_length(stmts_sl)
    let mut i = 0
    while i < num_stmts {
        let stmt = sublist_get(stmts_sl, i)
        let kind = np_kind.get(stmt).unwrap()
        if kind == NodeKind.LetBinding {
            let val = np_value.get(stmt).unwrap()
            if val != -1 && np_kind.get(val).unwrap() == NodeKind.Ident {
                let val_name = np_name.get(val).unwrap()
                if is_global(val_name) != 0 {
                    return 1
                }
            }
        }
        if kind == NodeKind.Block {
            if sr_prescan_has_save(np_stmts.get(stmt).unwrap()) != 0 {
                return 1
            }
        }
        if kind == NodeKind.IfExpr {
            let then_body = np_then_body.get(stmt).unwrap()
            if then_body != -1 && np_kind.get(then_body).unwrap() == NodeKind.Block {
                if sr_prescan_has_save(np_stmts.get(then_body).unwrap()) != 0 {
                    return 1
                }
            }
            let else_body = np_else_body.get(stmt).unwrap()
            if else_body != -1 && np_kind.get(else_body).unwrap() == NodeKind.Block {
                if sr_prescan_has_save(np_stmts.get(else_body).unwrap()) != 0 {
                    return 1
                }
            }
        }
        if kind == NodeKind.WhileLoop || kind == NodeKind.ForIn || kind == NodeKind.LoopExpr {
            let body = np_body.get(stmt).unwrap()
            if body != -1 && np_kind.get(body).unwrap() == NodeKind.Block {
                if sr_prescan_has_save(np_stmts.get(body).unwrap()) != 0 {
                    return 1
                }
            }
        }
        if kind == NodeKind.MatchExpr {
            let arms_sl = np_arms.get(stmt).unwrap()
            if arms_sl != -1 {
                let mut ai = 0
                while ai < sublist_length(arms_sl) {
                    let arm = sublist_get(arms_sl, ai)
                    let arm_body = np_body.get(arm).unwrap()
                    if arm_body != -1 && np_kind.get(arm_body).unwrap() == NodeKind.Block {
                        if sr_prescan_has_save(np_stmts.get(arm_body).unwrap()) != 0 {
                            return 1
                        }
                    }
                    ai = ai + 1
                }
            }
        }
        i = i + 1
    }
    0
}

fn sr_analyze_fn(fn_node: Int) ! Diag.Report {
    sr_current_fn = np_name.get(fn_node).unwrap()
    let saved_source = diag_source_file
    diag_source_file = diag_file_for_node(fn_node)
    sr_reset()
    sr_fn_has_save_restore = 0
    sr_allow_w0550 = 0
    sr_allow_w0551 = 0
    let allow_ann = get_annotation(fn_node, "allow")
    if allow_ann != -1 {
        let allow_args_sl = np_args.get(allow_ann).unwrap()
        if allow_args_sl != -1 {
            let mut saj = 0
            while saj < sublist_length(allow_args_sl) {
                let sr_arg_name = np_name.get(sublist_get(allow_args_sl, saj)).unwrap()
                if sr_arg_name == "IncompleteStateRestore" {
                    sr_allow_w0550 = 1
                }
                if sr_arg_name == "UnrestoredMutation" {
                    sr_allow_w0551 = 1
                }
                saj = saj + 1
            }
        }
    }
    let body = np_body.get(fn_node).unwrap()
    if body == -1 {
        return
    }
    let body_kind = np_kind.get(body).unwrap()
    if body_kind == NodeKind.Block {
        let body_stmts = np_stmts.get(body).unwrap()
        sr_fn_has_save_restore = sr_prescan_has_save(body_stmts)
        sr_scan_stmts(body_stmts)
    }
    diag_source_file = saved_source
}

pub fn analyze_save_restore(program: Int) ! Diag.Report {
    let fns_sl = np_params.get(program).unwrap()
    if fns_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(fns_sl) {
        sr_analyze_fn(sublist_get(fns_sl, i))
        i = i + 1
    }
}
