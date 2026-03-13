import symbol_index

// incremental.pact — Incremental recheck engine for Pact compiler
//
// Detects changed files via mtime comparison against a snapshot,
// computes affected symbol set by walking reverse deps transitively,
// and provides a filter for selective typechecking.
//
// MVP approach: re-parse all files (fast ~5ms/file), selective typecheck.
// Deps: symbol_index for file tracking and reverse deps.

// ── Snapshot storage (parallel arrays) ───────────────────────────────

pub let mut inc_snap_path: List[Str] = []
pub let mut inc_snap_mtime: List[Int] = []
pub let mut inc_snap_count: Int = 0

// ── Changed file list ────────────────────────────────────────────────

pub let mut inc_dirty_path: List[Str] = []
pub let mut inc_dirty_count: Int = 0

// ── Affected symbol set ──────────────────────────────────────────────

pub let mut inc_affected: List[Int] = []
pub let mut inc_affected_count: Int = 0

// Lookup map for O(1) affected check (keyed by string-converted sym index)
let mut affected_map: Map[Str, Int] = Map()

// Snapshot path lookup for O(1) mtime comparison
let mut snap_path_map: Map[Str, Int] = Map()

// ── Snapshot: capture current file mtimes from symbol index ──────────

pub fn inc_snapshot() {
    inc_snap_path = []
    inc_snap_mtime = []
    inc_snap_count = 0
    snap_path_map = Map()

    let mut i = 0
    while i < si_file_count {
        let path = si_file_path.get(i).unwrap()
        let mtime = file_mtime(path)
        inc_snap_path.push(path)
        inc_snap_mtime.push(mtime)
        snap_path_map.set(path, i)
        inc_snap_count = inc_snap_count + 1
        i = i + 1
    }
}

// ── Detect changes: compare current mtimes to snapshot ───────────────

pub fn inc_detect_changes() {
    inc_dirty_path = []
    inc_dirty_count = 0

    let mut i = 0
    while i < inc_snap_count {
        let path = inc_snap_path.get(i).unwrap()
        let old_mtime = inc_snap_mtime.get(i).unwrap()
        let cur_mtime = file_mtime(path)
        if cur_mtime != old_mtime {
            inc_dirty_path.push(path)
            inc_dirty_count = inc_dirty_count + 1
        }
        i = i + 1
    }

    // Also check for new files in the symbol index that weren't in the snapshot
    i = 0
    while i < si_file_count {
        let path = si_file_path.get(i).unwrap()
        if snap_path_map.has(path) == 0 {
            inc_dirty_path.push(path)
            inc_dirty_count = inc_dirty_count + 1
        }
        i = i + 1
    }
}

// ── Compute affected set: dirty symbols + transitive reverse deps ────

fn mark_affected(sym_idx: Int) {
    let key = "{sym_idx}"
    if affected_map.has(key) != 0 {
        return
    }
    affected_map.set(key, 1)
    inc_affected.push(sym_idx)
    inc_affected_count = inc_affected_count + 1

    // Walk reverse deps transitively
    let rdeps = si_get_rdeps(sym_idx)
    let mut i = 0
    while i < rdeps.len() {
        mark_affected(rdeps.get(i).unwrap())
        i = i + 1
    }
}

pub fn inc_compute_affected() {
    inc_affected = []
    inc_affected_count = 0
    affected_map = Map()

    // For each dirty file, get its symbols and mark them + rdeps as affected
    let mut di = 0
    while di < inc_dirty_count {
        let path = inc_dirty_path.get(di).unwrap()
        let syms = si_file_symbols(path)
        let mut si = 0
        while si < syms.len() {
            mark_affected(syms.get(si).unwrap())
            si = si + 1
        }
        di = di + 1
    }
}

// ── Query: check if a symbol needs rechecking ────────────────────────

pub fn inc_needs_recheck(sym_idx: Int) -> Int {
    if inc_affected_count == 0 {
        // No affected set computed — recheck everything
        return 1
    }
    affected_map.has("{sym_idx}")
}

// ── Collect affected symbol names ─────────────────────────────────────

pub fn inc_affected_names() -> List[Str] {
    let mut names: List[Str] = []
    let mut i = 0
    while i < inc_affected_count {
        let sym_idx = inc_affected.get(i).unwrap()
        names.push(si_sym_name.get(sym_idx).unwrap())
        i = i + 1
    }
    names
}

// ── Reset all incremental state ──────────────────────────────────────

pub fn inc_reset() {
    inc_snap_path = []
    inc_snap_mtime = []
    inc_snap_count = 0

    inc_dirty_path = []
    inc_dirty_count = 0

    inc_affected = []
    inc_affected_count = 0

    affected_map = Map()
    snap_path_map = Map()
}
