import symbol_index

// file_watcher.pact — Poll-based file watcher for incremental recompilation
//
// Tracks .pact file mtimes via parallel arrays. Polls on demand,
// detects changed/new files, returns dirty list for recheck engine.
// Complements incremental.pact (snapshot+affected) with continuous watching.

// ── Watched file storage (parallel arrays) ──────────────────────────

pub let mut fw_path: List[Str] = []
pub let mut fw_mtime: List[Int] = []
pub let mut fw_count: Int = 0

// ── Dirty file list ─────────────────────────────────────────────────

pub let mut fw_dirty_path: List[Str] = []
pub let mut fw_dirty_count: Int = 0

// ── Configuration ───────────────────────────────────────────────────

pub let mut fw_poll_interval: Int = 500

// ── Lookup map for O(1) path check ──────────────────────────────────

let mut path_map: Map[Str, Int] = Map()

// ── Init: snapshot symbol index file list ───────────────────────────

pub fn fw_init() {
    fw_path = []
    fw_mtime = []
    fw_count = 0
    fw_dirty_path = []
    fw_dirty_count = 0
    path_map = Map()

    let mut i = 0
    while i < si_file_count {
        let p = si_file_path.unsafe_get(i)
        let mt = file_mtime(p)
        fw_path.push(p)
        fw_mtime.push(mt)
        path_map.set(p, fw_count)
        fw_count = fw_count + 1
        i = i + 1
    }
}

// ── Poll: check all watched files for mtime changes ─────────────────

pub fn fw_poll() -> Int {
    fw_dirty_path = []
    fw_dirty_count = 0

    // Check existing watched files for mtime changes
    let mut i = 0
    while i < fw_count {
        let p = fw_path.unsafe_get(i)
        let old_mt = fw_mtime.unsafe_get(i)
        let cur_mt = file_mtime(p)
        if cur_mt != old_mt {
            fw_mtime.set(i, cur_mt)
            fw_dirty_path.push(p)
            fw_dirty_count = fw_dirty_count + 1
        }
        i = i + 1
    }

    // Detect new files in symbol index not yet tracked
    i = 0
    while i < si_file_count {
        let p = si_file_path.unsafe_get(i)
        if path_map.has(p) == 0 {
            let mt = file_mtime(p)
            fw_path.push(p)
            fw_mtime.push(mt)
            path_map.set(p, fw_count)
            fw_count = fw_count + 1
            fw_dirty_path.push(p)
            fw_dirty_count = fw_dirty_count + 1
        }
        i = i + 1
    }

    fw_dirty_count
}

// ── Get dirty file list ─────────────────────────────────────────────

pub fn fw_get_dirty() -> List[Str] {
    fw_dirty_path
}

// ── Clear dirty list after processing ───────────────────────────────

pub fn fw_clear_dirty() {
    fw_dirty_path = []
    fw_dirty_count = 0
}

// ── Manually add a file to watch ────────────────────────────────────

pub fn fw_add_file(path: Str) {
    if path_map.has(path) != 0 {
        return
    }
    let mt = file_mtime(path)
    fw_path.push(path)
    fw_mtime.push(mt)
    path_map.set(path, fw_count)
    fw_count = fw_count + 1
}

// ── Reset all state ─────────────────────────────────────────────────

pub fn fw_reset() {
    fw_path = []
    fw_mtime = []
    fw_count = 0
    fw_dirty_path = []
    fw_dirty_count = 0
    path_map = Map()
}
