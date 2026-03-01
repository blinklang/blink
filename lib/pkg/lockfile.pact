// lockfile.pact — pact.lock reader/writer (§8.9.6)
//
// Reads and writes deterministic lockfiles using std.toml for parsing.
// Stores package data in parallel arrays (no structs in lists).

import std.toml

// ── Metadata ─────────────────────────────────────────────────────
pub let mut lock_version: Int = 0
pub let mut lock_pact_version: Str = ""
pub let mut lock_generated: Str = ""

// ── Package parallel arrays ──────────────────────────────────────
pub let mut lock_pkg_names: List[Str] = []
pub let mut lock_pkg_versions: List[Str] = []
pub let mut lock_pkg_sources: List[Str] = []
pub let mut lock_pkg_hashes: List[Str] = []
pub let mut lock_pkg_caps: List[Str] = []

// ── Clear ────────────────────────────────────────────────────────

pub fn lockfile_clear() {
    lock_version = 0
    lock_pact_version = ""
    lock_generated = ""
    lock_pkg_names = []
    lock_pkg_versions = []
    lock_pkg_sources = []
    lock_pkg_hashes = []
    lock_pkg_caps = []
}

// ── Query functions ──────────────────────────────────────────────

pub fn lockfile_pkg_count() -> Int {
    lock_pkg_names.len()
}

pub fn lockfile_find_pkg(name: Str) -> Int {
    let mut i = 0
    while i < lock_pkg_names.len() {
        if lock_pkg_names.get(i).unwrap() == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn lockfile_get_pkg_hash(name: Str) -> Str {
    let idx = lockfile_find_pkg(name)
    if idx == -1 {
        return ""
    }
    lock_pkg_hashes.get(idx).unwrap()
}

pub fn lockfile_verify_hash(name: Str, expected_hash: Str) -> Int {
    let actual = lockfile_get_pkg_hash(name)
    if actual == "" {
        return 0
    }
    if actual == expected_hash {
        return 1
    }
    0
}

// ── Add / set helpers ────────────────────────────────────────────

pub fn lockfile_add_pkg(name: Str, version: Str, source: Str, hash: Str, caps: Str) {
    lock_pkg_names.push(name)
    lock_pkg_versions.push(version)
    lock_pkg_sources.push(source)
    lock_pkg_hashes.push(hash)
    lock_pkg_caps.push(caps)
}

pub fn lockfile_set_metadata(pact_version: Str, generated: Str) {
    lock_version = 1
    lock_pact_version = pact_version
    lock_generated = generated
}

// ── String comparison for sorting ────────────────────────────────
// Returns -1 if a < b, 0 if equal, 1 if a > b (lexicographic)

fn str_compare(a: Str, b: Str) -> Int {
    let mut i = 0
    let a_len = a.len()
    let b_len = b.len()
    while i < a_len && i < b_len {
        let ca = a.char_at(i)
        let cb = b.char_at(i)
        if ca < cb {
            return -1
        }
        if ca > cb {
            return 1
        }
        i = i + 1
    }
    if a_len < b_len {
        return -1
    }
    if a_len > b_len {
        return 1
    }
    0
}

// ── Sort packages by name (insertion sort) ───────────────────────

fn sort_packages() {
    let n = lock_pkg_names.len()
    let mut i = 1
    while i < n {
        let key_name = lock_pkg_names.get(i).unwrap()
        let key_ver = lock_pkg_versions.get(i).unwrap()
        let key_src = lock_pkg_sources.get(i).unwrap()
        let key_hash = lock_pkg_hashes.get(i).unwrap()
        let key_caps = lock_pkg_caps.get(i).unwrap()
        let mut j = i - 1
        while j >= 0 && str_compare(lock_pkg_names.get(j).unwrap(), key_name) > 0 {
            lock_pkg_names.set(j + 1, lock_pkg_names.get(j).unwrap())
            lock_pkg_versions.set(j + 1, lock_pkg_versions.get(j).unwrap())
            lock_pkg_sources.set(j + 1, lock_pkg_sources.get(j).unwrap())
            lock_pkg_hashes.set(j + 1, lock_pkg_hashes.get(j).unwrap())
            lock_pkg_caps.set(j + 1, lock_pkg_caps.get(j).unwrap())
            j = j - 1
        }
        lock_pkg_names.set(j + 1, key_name)
        lock_pkg_versions.set(j + 1, key_ver)
        lock_pkg_sources.set(j + 1, key_src)
        lock_pkg_hashes.set(j + 1, key_hash)
        lock_pkg_caps.set(j + 1, key_caps)
        i = i + 1
    }
}

// ── Format capabilities as TOML array ────────────────────────────
// Input: comma-separated string like "Net.Connect,Net.DNS"
// Output: TOML array like ["Net.Connect", "Net.DNS"]

fn format_caps_toml(caps: Str) -> Str {
    if caps == "" {
        return "[]"
    }
    let mut result = "["
    let mut start = 0
    let mut i = 0
    let mut first = 1
    while i < caps.len() {
        if caps.char_at(i) == 44 {
            if first == 0 {
                result = result.concat(", ")
            }
            result = result.concat("\"").concat(caps.substring(start, i - start)).concat("\"")
            first = 0
            start = i + 1
        }
        i = i + 1
    }
    if start < caps.len() {
        if first == 0 {
            result = result.concat(", ")
        }
        result = result.concat("\"").concat(caps.substring(start, caps.len() - start)).concat("\"")
    }
    result.concat("]")
}

// ── Write lockfile ───────────────────────────────────────────────

pub fn lockfile_write(path: Str) -> Int {
    sort_packages()

    let mut out = "[metadata]\n"
    out = out.concat("lockfile-version = 1\n")
    out = out.concat("pact-version = \"").concat(lock_pact_version).concat("\"\n")
    out = out.concat("generated = \"").concat(lock_generated).concat("\"\n")

    let mut i = 0
    while i < lock_pkg_names.len() {
        out = out.concat("\n[[package]]\n")
        out = out.concat("name = \"").concat(lock_pkg_names.get(i).unwrap()).concat("\"\n")
        out = out.concat("version = \"").concat(lock_pkg_versions.get(i).unwrap()).concat("\"\n")
        out = out.concat("source = \"").concat(lock_pkg_sources.get(i).unwrap()).concat("\"\n")
        out = out.concat("hash = \"").concat(lock_pkg_hashes.get(i).unwrap()).concat("\"\n")
        out = out.concat("capabilities = ").concat(format_caps_toml(lock_pkg_caps.get(i).unwrap())).concat("\n")
        i = i + 1
    }

    write_file(path, out)
    0
}

// ── Parse capabilities from TOML array into comma-separated ──────

fn parse_caps_for_pkg(prefix: Str) -> Str {
    let caps_key = prefix.concat(".capabilities")
    if toml_has(caps_key) == 0 {
        return ""
    }
    let count = toml_get_array_len(caps_key)
    if count == 0 {
        return ""
    }
    let mut result = ""
    let mut i = 0
    while i < count {
        if i > 0 {
            result = result.concat(",")
        }
        result = result.concat(toml_get_array_item(caps_key, i))
        i = i + 1
    }
    result
}

// ── Load lockfile ────────────────────────────────────────────────

pub fn lockfile_load(path: Str) -> Int {
    lockfile_clear()

    if file_exists(path) == 0 {
        return 1
    }

    let content = read_file(path)
    toml_clear()
    toml_parse(content)

    if toml_has("metadata.lockfile-version") == 0 {
        return 1
    }
    let ver = toml_get_int("metadata.lockfile-version")
    if ver != 1 {
        return 1
    }
    lock_version = ver

    if toml_has("metadata.pact-version") == 1 {
        lock_pact_version = toml_get("metadata.pact-version")
    }
    if toml_has("metadata.generated") == 1 {
        lock_generated = toml_get("metadata.generated")
    }

    let pkg_count = toml_array_len("package")
    let mut i = 0
    while i < pkg_count {
        let prefix = "package[{i}]"
        let name_key = prefix.concat(".name")
        let ver_key = prefix.concat(".version")
        let src_key = prefix.concat(".source")
        let hash_key = prefix.concat(".hash")

        if toml_has(name_key) == 0 {
            return 1
        }
        if toml_has(ver_key) == 0 {
            return 1
        }
        if toml_has(src_key) == 0 {
            return 1
        }
        if toml_has(hash_key) == 0 {
            return 1
        }

        let pkg_name = toml_get(name_key)
        let pkg_ver = toml_get(ver_key)
        let pkg_src = toml_get(src_key)
        let pkg_hash = toml_get(hash_key)
        let pkg_caps = parse_caps_for_pkg(prefix)

        lock_pkg_names.push(pkg_name)
        lock_pkg_versions.push(pkg_ver)
        lock_pkg_sources.push(pkg_src)
        lock_pkg_hashes.push(pkg_hash)
        lock_pkg_caps.push(pkg_caps)

        i = i + 1
    }

    0
}
