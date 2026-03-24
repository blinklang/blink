// pathdeps.pact — path dependency resolver
//
// Resolves local path dependencies from pact.toml manifests, handling
// transitive deps and cycle detection. Uses pkg.manifest for loading.

import std.path
import pkg.manifest

// ── Resolved path deps: parallel arrays ────────────────────────
pub let mut resolved_names: List[Str] = []
pub let mut resolved_versions: List[Str] = []
pub let mut resolved_sources: List[Str] = []
pub let mut resolved_hashes: List[Str] = []
pub let mut resolved_caps: List[Str] = []

// ── Cycle detection ────────────────────────────────────────────
let mut visit_stack: List[Str] = []
let mut stack_depth: Int = 0

// ── Clear all state ────────────────────────────────────────────

pub fn pathdeps_clear() {
    resolved_names = []
    resolved_versions = []
    resolved_sources = []
    resolved_hashes = []
    resolved_caps = []
    visit_stack = []
    stack_depth = 0
}

// ── Helpers ────────────────────────────────────────────────────

fn is_already_resolved(name: Str) -> Int {
    let mut i = 0
    while i < resolved_names.len() {
        if resolved_names.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

fn build_caps_string() -> Str {
    let mut result = ""
    let mut i = 0
    while i < cap_required.len() {
        if i > 0 {
            result = result.concat(",")
        }
        result = result.concat(cap_required.get(i).unwrap())
        i = i + 1
    }
    result
}

fn compute_dir_hash(dir: Str) -> Str {
    let result = process_run("sh", ["-c", "find {dir} -name '*.pact' -type f | sort | xargs cat | sha256sum | cut -c1-64"])
    let raw = result.out
    if raw.len() > 0 && raw.char_at(raw.len() - 1) == 10 {
        return raw.substring(0, raw.len() - 1)
    }
    raw
}

// ── Resolve a single path dependency ───────────────────────────

fn resolve_one(name: Str, rel_path: Str, base_dir: Str) -> Int {
    let full_path = path_join(base_dir, rel_path)

    // Validate directory exists
    if is_dir(full_path) == 0 {
        io.println("error: path dependency '{name}' directory not found: {full_path}")
        return 1
    }

    // Validate manifest exists
    let mut manifest_path = path_join(full_path, "blink.toml")
    if file_exists(manifest_path) == 0 {
        manifest_path = path_join(full_path, "pact.toml")
    }
    if file_exists(manifest_path) == 0 {
        io.println("error: path dependency '{name}' missing manifest in: {full_path}")
        return 1
    }

    // Cycle check: scan visit_stack up to stack_depth
    let mut i = 0
    while i < stack_depth {
        if visit_stack.get(i).unwrap() == name {
            io.println("error: circular path dependency detected: {name}")
            return 1
        }
        i = i + 1
    }

    // Push to visit stack
    if stack_depth < visit_stack.len() {
        visit_stack.set(stack_depth, name)
    } else {
        visit_stack.push(name)
    }
    stack_depth = stack_depth + 1

    // Load the dependency's manifest
    let load_rc = manifest_load(manifest_path)
    if load_rc != 0 {
        io.println("error: failed to load manifest for path dependency '{name}'")
        stack_depth = stack_depth - 1
        return 1
    }

    // Extract info from manifest globals BEFORE recursing
    let dep_pkg_name = manifest_name
    let dep_pkg_version = manifest_version
    let dep_caps = build_caps_string()

    // Compute hash of the dependency directory
    let dep_hash = compute_dir_hash(full_path)

    // Build source string
    let dep_source = "path:".concat(full_path)

    // Add to resolved if not already present
    if is_already_resolved(dep_pkg_name) == 0 {
        resolved_names.push(dep_pkg_name)
        resolved_versions.push(dep_pkg_version)
        resolved_sources.push(dep_source)
        resolved_hashes.push(dep_hash)
        resolved_caps.push(dep_caps)
    }

    // Extract this dep's own path deps into local arrays before recursing
    let sub_dep_count = manifest_dep_count()
    let mut sub_dep_names: List[Str] = []
    let mut sub_dep_paths: List[Str] = []
    let mut sub_dep_sources: List[Str] = []
    let mut j = 0
    while j < sub_dep_count {
        sub_dep_names.push(manifest_get_dep_name(j))
        sub_dep_paths.push(dep_paths.get(j).unwrap())
        sub_dep_sources.push(manifest_get_dep_source(j))
        j = j + 1
    }

    // Recurse for transitive path deps
    let mut k = 0
    while k < sub_dep_count {
        if sub_dep_sources.get(k).unwrap() == "path" {
            let rc = resolve_one(sub_dep_names.get(k).unwrap(), sub_dep_paths.get(k).unwrap(), full_path)
            if rc != 0 {
                stack_depth = stack_depth - 1
                return 1
            }
        }
        k = k + 1
    }

    // Pop visit stack
    stack_depth = stack_depth - 1
    0
}

// ── Main entry point ───────────────────────────────────────────

pub fn resolve_path_deps(project_root: Str) -> Int {
    let mut root_manifest = path_join(project_root, "blink.toml")
    if file_exists(root_manifest) == 0 {
        root_manifest = path_join(project_root, "pact.toml")
    }
    let load_rc = manifest_load(root_manifest)
    if load_rc != 0 {
        io.println("error: failed to load root manifest")
        return 1
    }

    // Extract dep info into local arrays before recursing
    // (manifest_load clobbers the globals)
    let dep_count = manifest_dep_count()
    let mut local_dep_names: List[Str] = []
    let mut local_dep_paths: List[Str] = []
    let mut local_dep_sources: List[Str] = []
    let mut i = 0
    while i < dep_count {
        local_dep_names.push(manifest_get_dep_name(i))
        local_dep_paths.push(dep_paths.get(i).unwrap())
        local_dep_sources.push(manifest_get_dep_source(i))
        i = i + 1
    }

    // Resolve each path dependency
    let mut j = 0
    while j < dep_count {
        if local_dep_sources.get(j).unwrap() == "path" {
            let rc = resolve_one(local_dep_names.get(j).unwrap(), local_dep_paths.get(j).unwrap(), project_root)
            if rc != 0 {
                return 1
            }
        }
        j = j + 1
    }

    0
}

// ── Query functions ────────────────────────────────────────────

pub fn pathdeps_count() -> Int {
    resolved_names.len()
}

pub fn pathdeps_get_name(i: Int) -> Str {
    if i < 0 || i >= resolved_names.len() {
        return ""
    }
    resolved_names.get(i).unwrap()
}

pub fn pathdeps_get_version(i: Int) -> Str {
    if i < 0 || i >= resolved_versions.len() {
        return ""
    }
    resolved_versions.get(i).unwrap()
}

pub fn pathdeps_get_source(i: Int) -> Str {
    if i < 0 || i >= resolved_sources.len() {
        return ""
    }
    resolved_sources.get(i).unwrap()
}

pub fn pathdeps_get_hash(i: Int) -> Str {
    if i < 0 || i >= resolved_hashes.len() {
        return ""
    }
    resolved_hashes.get(i).unwrap()
}

pub fn pathdeps_get_caps(i: Int) -> Str {
    if i < 0 || i >= resolved_caps.len() {
        return ""
    }
    resolved_caps.get(i).unwrap()
}
