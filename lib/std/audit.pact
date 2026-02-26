// audit.pact — capability escalation auditing (§8.9.7)
//
// Compares current lockfile capabilities against a baseline to detect
// new or escalated capabilities in dependencies.

import std.lockfile

// ── Baseline: parallel arrays from reference lockfile ───────────
let mut base_names: List[Str] = []
let mut base_versions: List[Str] = []
let mut base_caps: List[Str] = []

// ── Findings: escalations detected ──────────────────────────────
pub let mut escalation_names: List[Str] = []
pub let mut escalation_new_caps: List[Str] = []
pub let mut escalation_types: List[Str] = []

// ── Clear ───────────────────────────────────────────────────────

pub fn audit_clear() {
    base_names = []
    base_versions = []
    base_caps = []
    escalation_names = []
    escalation_new_caps = []
    escalation_types = []
}

// ── Find package in baseline by name ────────────────────────────

fn find_in_baseline(name: Str) -> Int {
    let mut i = 0
    while i < base_names.len() {
        if base_names.unsafe_get(i) == name {
            return i
        }
        i = i + 1
    }
    -1
}

// ── Check if comma-separated caps string contains a cap ─────────

fn caps_contains(caps_csv: Str, cap: Str) -> Int {
    if caps_csv == "" {
        return 0
    }
    let mut start = 0
    let mut i = 0
    while i < caps_csv.len() {
        if caps_csv.char_at(i) == 44 {
            let item = caps_csv.substring(start, i - start)
            if item == cap {
                return 1
            }
            start = i + 1
        }
        i = i + 1
    }
    let last = caps_csv.substring(start, caps_csv.len() - start)
    if last == cap {
        return 1
    }
    0
}

// ── Find new capabilities in current not in baseline ────────────

fn find_new_caps(current_caps: Str, baseline_caps: Str) -> Str {
    if current_caps == "" {
        return ""
    }
    let mut result = ""
    let mut start = 0
    let mut i = 0
    while i < current_caps.len() {
        if current_caps.char_at(i) == 44 {
            let cap = current_caps.substring(start, i - start)
            if caps_contains(baseline_caps, cap) == 0 {
                if result != "" {
                    result = result.concat(",")
                }
                result = result.concat(cap)
            }
            start = i + 1
        }
        i = i + 1
    }
    let last_cap = current_caps.substring(start, current_caps.len() - start)
    if caps_contains(baseline_caps, last_cap) == 0 {
        if result != "" {
            result = result.concat(",")
        }
        result = result.concat(last_cap)
    }
    result
}

// ── Load baseline lockfile ──────────────────────────────────────

pub fn audit_load_baseline(path: Str) -> Int {
    let rc = lockfile_load(path)
    if rc != 0 {
        return 1
    }

    let mut i = 0
    while i < lock_pkg_names.len() {
        base_names.push(lock_pkg_names.unsafe_get(i))
        base_versions.push(lock_pkg_versions.unsafe_get(i))
        base_caps.push(lock_pkg_caps.unsafe_get(i))
        i = i + 1
    }

    lockfile_clear()
    0
}

// ── Check current lockfile against baseline ─────────────────────

pub fn audit_check() -> Int {
    escalation_names = []
    escalation_new_caps = []
    escalation_types = []

    let mut i = 0
    while i < lock_pkg_names.len() {
        let name = lock_pkg_names.unsafe_get(i)
        let current_caps = lock_pkg_caps.unsafe_get(i)
        let base_idx = find_in_baseline(name)

        if base_idx == -1 {
            if current_caps != "" {
                escalation_names.push(name)
                escalation_new_caps.push(current_caps)
                escalation_types.push("new_pkg")
            }
        } else {
            let new_caps = find_new_caps(current_caps, base_caps.unsafe_get(base_idx))
            if new_caps != "" {
                escalation_names.push(name)
                escalation_new_caps.push(new_caps)
                escalation_types.push("escalation")
            }
        }

        i = i + 1
    }

    escalation_names.len()
}

// ── Print human-readable report ─────────────────────────────────

pub fn audit_report() {
    if escalation_names.len() == 0 {
        io.println("audit: no capability escalations found")
        return
    }

    io.println("audit: {escalation_names.len()} capability escalation(s) found")
    let mut i = 0
    while i < escalation_names.len() {
        let name = escalation_names.unsafe_get(i)
        let caps = escalation_new_caps.unsafe_get(i)
        let etype = escalation_types.unsafe_get(i)
        if etype == "new_pkg" {
            io.println("  WARNING: new dependency '{name}' requires capabilities: {caps}")
        } else {
            io.println("  ERROR: dependency '{name}' gained new capabilities: {caps}")
        }
        i = i + 1
    }
}
