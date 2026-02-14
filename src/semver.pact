// semver.pact — Semantic version parser and constraint matcher
//
// Implements §8.9.4: caret (default), tilde, exact, and explicit range
// constraints. Pre-1.0 rules apply: 0.x.y treats minor as breaking.
//
// Uses parallel arrays for constraint bounds since the C backend
// cannot store structs in lists.

// ── ASCII constants ────────────────────────────────────────────────

let CH_SPACE = 32
let CH_PLUS = 43
let CH_COMMA = 44
let CH_MINUS = 45
let CH_DOT = 46
let CH_0 = 48
let CH_9 = 57
let CH_LESS = 60
let CH_EQUALS = 61
let CH_GREATER = 62
let CH_TILDE = 126

// ── Version struct ─────────────────────────────────────────────────

pub type Version {
    major: Int
    minor: Int
    patch: Int
}

// ── Parse output globals ───────────────────────────────────────────

pub let mut ver_major = 0
pub let mut ver_minor = 0
pub let mut ver_patch = 0
pub let mut ver_has_minor = 0
pub let mut ver_has_patch = 0

// ── Constraint parallel arrays ─────────────────────────────────────
// Op codes: 0=gte, 1=lt, 2=eq, 3=lte, 4=gt

let OP_GTE = 0
let OP_LT = 1
let OP_EQ = 2
let OP_LTE = 3
let OP_GT = 4

pub let mut constraint_ops: List[Int] = []
pub let mut constraint_majors: List[Int] = []
pub let mut constraint_minors: List[Int] = []
pub let mut constraint_patches: List[Int] = []

// ── Helpers ────────────────────────────────────────────────────────

fn is_digit(c: Int) -> Int {
    c >= CH_0 && c <= CH_9
}

fn str_to_int(s: Str, start: Int, len: Int) -> Int {
    let mut result = 0
    let mut i = start
    while i < start + len {
        let ch = s.char_at(i)
        result = result * 10 + (ch - 48)
        i = i + 1
    }
    result
}

fn skip_whitespace(s: Str, start: Int) -> Int {
    let mut i = start
    while i < s.len() {
        if s.char_at(i) != CH_SPACE {
            return i
        }
        i = i + 1
    }
    i
}

fn add_bound(op: Int, major: Int, minor: Int, patch: Int) {
    constraint_ops.push(op)
    constraint_majors.push(major)
    constraint_minors.push(minor)
    constraint_patches.push(patch)
}

// ── parse_version ──────────────────────────────────────────────────
// Parses version string starting at position `start` up to `end`.
// Populates ver_major/minor/patch and has_minor/has_patch flags.
// Returns 1 on success, 0 on failure.

fn parse_version_range(s: Str, start: Int, end: Int) -> Int {
    ver_major = 0
    ver_minor = 0
    ver_patch = 0
    ver_has_minor = 0
    ver_has_patch = 0

    let mut pos = start

    // Skip leading whitespace
    pos = skip_whitespace(s, pos)

    if pos >= end {
        return 0
    }

    // Parse major
    let major_start = pos
    while pos < end && is_digit(s.char_at(pos)) {
        pos = pos + 1
    }
    if pos == major_start {
        return 0
    }
    ver_major = str_to_int(s, major_start, pos - major_start)

    // Check for .minor
    if pos < end && s.char_at(pos) == CH_DOT {
        pos = pos + 1
        ver_has_minor = 1

        let minor_start = pos
        while pos < end && is_digit(s.char_at(pos)) {
            pos = pos + 1
        }
        if pos == minor_start {
            return 0
        }
        ver_minor = str_to_int(s, minor_start, pos - minor_start)

        // Check for .patch
        if pos < end && s.char_at(pos) == CH_DOT {
            pos = pos + 1
            ver_has_patch = 1

            let patch_start = pos
            while pos < end && is_digit(s.char_at(pos)) {
                pos = pos + 1
            }
            if pos == patch_start {
                return 0
            }
            ver_patch = str_to_int(s, patch_start, pos - patch_start)
        }
    }

    // Skip trailing whitespace and pre-release/build metadata (+ or -)
    // For now we just ignore anything after the version numbers
    1
}

pub fn parse_version(s: Str) -> Int {
    parse_version_range(s, 0, s.len())
}

// ── version_compare ────────────────────────────────────────────────

pub fn version_compare(a_major: Int, a_minor: Int, a_patch: Int,
                       b_major: Int, b_minor: Int, b_patch: Int) -> Int {
    if a_major < b_major {
        return -1
    }
    if a_major > b_major {
        return 1
    }
    if a_minor < b_minor {
        return -1
    }
    if a_minor > b_minor {
        return 1
    }
    if a_patch < b_patch {
        return -1
    }
    if a_patch > b_patch {
        return 1
    }
    0
}

// ── version_to_str ─────────────────────────────────────────────────

pub fn version_to_str(major: Int, minor: Int, patch: Int) -> Str {
    "{major}.{minor}.{patch}"
}

// ── Constraint expansion: caret ────────────────────────────────────

fn expand_caret(major: Int, minor: Int, patch: Int,
                has_minor: Int, has_patch: Int) {
    // Lower bound: >= given version (defaulting missing parts to 0)
    add_bound(OP_GTE, major, minor, patch)

    if major > 0 {
        // Major > 0: next major
        add_bound(OP_LT, major + 1, 0, 0)
    } else if has_minor == 1 {
        if minor > 0 {
            // 0.minor > 0: next minor
            add_bound(OP_LT, 0, minor + 1, 0)
        } else if has_patch == 1 {
            // 0.0.patch: next patch
            add_bound(OP_LT, 0, 0, patch + 1)
        } else {
            // "0.0" with no patch: bump minor
            add_bound(OP_LT, 0, 1, 0)
        }
    } else {
        // Only major given, e.g. "0": bump major
        add_bound(OP_LT, major + 1, 0, 0)
    }
}

// ── Constraint expansion: tilde ────────────────────────────────────

fn expand_tilde(major: Int, minor: Int, patch: Int,
                has_minor: Int, has_patch: Int) {
    add_bound(OP_GTE, major, minor, patch)

    if has_minor == 1 {
        // ~X.Y or ~X.Y.Z: bump minor
        add_bound(OP_LT, major, minor + 1, 0)
    } else {
        // ~X: only major given, bump major
        add_bound(OP_LT, major + 1, 0, 0)
    }
}

// ── Parse a single constraint term ─────────────────────────────────
// Handles: >=, <=, >, <, =, ~, or bare version (caret)
// Parses from position `start` to `end` in string `s`.
// Adds bounds to the global constraint arrays.

fn parse_single_constraint(s: Str, start: Int, end: Int) {
    let mut pos = skip_whitespace(s, start)

    if pos >= end {
        return
    }

    let ch = s.char_at(pos)

    // Tilde: ~version
    if ch == CH_TILDE {
        pos = pos + 1
        pos = skip_whitespace(s, pos)
        let ok = parse_version_range(s, pos, end)
        if ok == 1 {
            expand_tilde(ver_major, ver_minor, ver_patch,
                         ver_has_minor, ver_has_patch)
        }
        return
    }

    // Exact: =version
    if ch == CH_EQUALS {
        let next_pos = pos + 1
        if next_pos < end && is_digit(s.char_at(next_pos)) {
            pos = next_pos
            pos = skip_whitespace(s, pos)
            let ok = parse_version_range(s, pos, end)
            if ok == 1 {
                add_bound(OP_EQ, ver_major, ver_minor, ver_patch)
            }
            return
        }
        // Could be ==, treat same as =
        if next_pos < end && s.char_at(next_pos) == CH_EQUALS {
            pos = next_pos + 1
            pos = skip_whitespace(s, pos)
            let ok = parse_version_range(s, pos, end)
            if ok == 1 {
                add_bound(OP_EQ, ver_major, ver_minor, ver_patch)
            }
            return
        }
    }

    // >=
    if ch == CH_GREATER {
        let next_pos = pos + 1
        if next_pos < end && s.char_at(next_pos) == CH_EQUALS {
            pos = next_pos + 1
            pos = skip_whitespace(s, pos)
            let ok = parse_version_range(s, pos, end)
            if ok == 1 {
                add_bound(OP_GTE, ver_major, ver_minor, ver_patch)
            }
            return
        }
        // Just >
        pos = next_pos
        pos = skip_whitespace(s, pos)
        let ok = parse_version_range(s, pos, end)
        if ok == 1 {
            add_bound(OP_GT, ver_major, ver_minor, ver_patch)
        }
        return
    }

    // <=
    if ch == CH_LESS {
        let next_pos = pos + 1
        if next_pos < end && s.char_at(next_pos) == CH_EQUALS {
            pos = next_pos + 1
            pos = skip_whitespace(s, pos)
            let ok = parse_version_range(s, pos, end)
            if ok == 1 {
                add_bound(OP_LTE, ver_major, ver_minor, ver_patch)
            }
            return
        }
        // Just <
        pos = next_pos
        pos = skip_whitespace(s, pos)
        let ok = parse_version_range(s, pos, end)
        if ok == 1 {
            add_bound(OP_LT, ver_major, ver_minor, ver_patch)
        }
        return
    }

    // Bare version: caret (default)
    if is_digit(ch) {
        let ok = parse_version_range(s, pos, end)
        if ok == 1 {
            expand_caret(ver_major, ver_minor, ver_patch,
                         ver_has_minor, ver_has_patch)
        }
        return
    }
}

// ── parse_constraint ───────────────────────────────────────────────
// Parses a constraint string which may contain comma-separated terms.
// Returns the number of bounds parsed.

pub fn parse_constraint(s: Str) -> Int {
    constraint_ops = []
    constraint_majors = []
    constraint_minors = []
    constraint_patches = []

    let slen = s.len()
    if slen == 0 {
        return 0
    }

    // Split on commas and parse each term
    let mut term_start = 0
    let mut i = 0
    while i < slen {
        if s.char_at(i) == CH_COMMA {
            parse_single_constraint(s, term_start, i)
            term_start = i + 1
        }
        i = i + 1
    }
    // Parse the last (or only) term
    parse_single_constraint(s, term_start, slen)

    constraint_ops.len()
}

// ── version_satisfies ──────────────────────────────────────────────
// Checks if the given version satisfies all bounds in the constraint
// arrays. Call parse_constraint first.
// Returns 1 if satisfied, 0 otherwise.

pub fn version_satisfies(major: Int, minor: Int, patch: Int) -> Int {
    let mut i = 0
    while i < constraint_ops.len() {
        let op = constraint_ops.get(i)
        let c_major = constraint_majors.get(i)
        let c_minor = constraint_minors.get(i)
        let c_patch = constraint_patches.get(i)

        let cmp = version_compare(major, minor, patch,
                                  c_major, c_minor, c_patch)

        if op == OP_GTE {
            // version >= constraint
            if cmp < 0 {
                return 0
            }
        } else if op == OP_LT {
            // version < constraint
            if cmp >= 0 {
                return 0
            }
        } else if op == OP_EQ {
            // version == constraint
            if cmp != 0 {
                return 0
            }
        } else if op == OP_LTE {
            // version <= constraint
            if cmp > 0 {
                return 0
            }
        } else if op == OP_GT {
            // version > constraint
            if cmp <= 0 {
                return 0
            }
        }

        i = i + 1
    }

    1
}

// ── version_matches ────────────────────────────────────────────────
// Convenience: parse both version and constraint, then check match.
// Returns 1 if version satisfies constraint, 0 otherwise.

pub fn version_matches(version_str: Str, constraint_str: Str) -> Int {
    let ok = parse_version(version_str)
    if ok == 0 {
        return 0
    }
    let v_major = ver_major
    let v_minor = ver_minor
    let v_patch = ver_patch

    let num_bounds = parse_constraint(constraint_str)
    if num_bounds == 0 {
        return 0
    }

    version_satisfies(v_major, v_minor, v_patch)
}
