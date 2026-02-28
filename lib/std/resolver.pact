// resolver.pact — MVS dependency resolver (§8.9.5)
//
// Walks the dependency graph, resolving path and git dependencies.
// For path+git-only (no registry), "MVS" reduces to: resolve each dep,
// check for version conflicts, recurse into transitive deps.

import std.manifest
import std.lockfile
import std.semver
import std.pathdeps
import std.gitdeps

// ── Resolved dependency graph: parallel arrays ──────────────────
pub let mut res_names: List[Str] = []
pub let mut res_versions: List[Str] = []
pub let mut res_sources: List[Str] = []
pub let mut res_hashes: List[Str] = []
pub let mut res_caps: List[Str] = []

// ── Clear ───────────────────────────────────────────────────────

pub fn resolver_clear() {
    res_names = []
    res_versions = []
    res_sources = []
    res_hashes = []
    res_caps = []
}

// ── Helpers ─────────────────────────────────────────────────────

fn trim_str(s: Str) -> Str {
    let mut end = s.len()
    while end > 0 {
        let ch = s.char_at(end - 1)
        if ch == 10 || ch == 13 || ch == 32 {
            end = end - 1
        } else {
            return s.substring(0, end)
        }
    }
    ""
}

fn find_resolved(name: Str) -> Int {
    let mut i = 0
    while i < res_names.len() {
        if res_names.get(i).unwrap() == name {
            return i
        }
        i = i + 1
    }
    -1
}

fn add_resolved(name: Str, version: Str, source: Str, hash: Str, caps: Str) -> Int {
    let existing = find_resolved(name)
    if existing >= 0 {
        if res_versions.get(existing).unwrap() != version {
            io.println("error: version conflict for '{name}': resolved {res_versions.get(existing).unwrap()} but also need {version}")
            return 1
        }
        return 0
    }
    res_names.push(name)
    res_versions.push(version)
    res_sources.push(source)
    res_hashes.push(hash)
    res_caps.push(caps)
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
    shell_exec("find {dir} -name '*.pact' -type f | sort | xargs cat | sha256sum | cut -c1-64 > /tmp/_pact_hash")
    let raw = read_file("/tmp/_pact_hash")
    trim_str(raw)
}

// ── Process a single path dependency ────────────────────────────

fn process_path_dep(name: Str, dep_path: Str, base_dir: Str) -> Int {
    let full_path = path_join(base_dir, dep_path)

    if is_dir(full_path) == 0 {
        io.println("error: path dependency '{name}' not found: {full_path}")
        return 1
    }

    let manifest_path = path_join(full_path, "pact.toml")
    if file_exists(manifest_path) == 0 {
        io.println("error: path dependency '{name}' missing pact.toml: {full_path}")
        return 1
    }

    let load_rc = manifest_load(manifest_path)
    if load_rc != 0 {
        io.println("error: failed to load manifest for '{name}'")
        return 1
    }

    let pkg_name = manifest_name
    let pkg_version = manifest_version
    let pkg_caps = build_caps_string()
    let pkg_hash = compute_dir_hash(full_path)
    let pkg_source = "path:".concat(full_path)

    // Extract transitive deps before clobbering manifest state
    let sub_count = manifest_dep_count()
    let mut sub_names: List[Str] = []
    let mut sub_paths: List[Str] = []
    let mut sub_git_urls: List[Str] = []
    let mut sub_git_tags: List[Str] = []
    let mut sub_sources: List[Str] = []
    let mut i = 0
    while i < sub_count {
        sub_names.push(manifest_get_dep_name(i))
        sub_paths.push(dep_paths.get(i).unwrap())
        sub_git_urls.push(dep_git_urls.get(i).unwrap())
        sub_git_tags.push(dep_git_tags.get(i).unwrap())
        sub_sources.push(manifest_get_dep_source(i))
        i = i + 1
    }

    let add_rc = add_resolved(pkg_name, pkg_version, pkg_source, pkg_hash, pkg_caps)
    if add_rc != 0 {
        return 1
    }

    // Recurse into transitive deps
    let mut j = 0
    while j < sub_count {
        let src = sub_sources.get(j).unwrap()
        if src == "path" {
            let rc = process_path_dep(sub_names.get(j).unwrap(), sub_paths.get(j).unwrap(), full_path)
            if rc != 0 {
                return 1
            }
        } else if src == "git" {
            let rc = process_git_dep(sub_names.get(j).unwrap(), sub_git_urls.get(j).unwrap(), sub_git_tags.get(j).unwrap())
            if rc != 0 {
                return 1
            }
        }
        j = j + 1
    }

    0
}

// ── Process a single git dependency ─────────────────────────────

fn process_git_dep(name: Str, url: Str, tag: Str) -> Int {
    let mut effective_tag = tag
    if effective_tag == "" {
        effective_tag = "HEAD"
    }

    let fetch_rc = git_fetch(url, effective_tag)
    if fetch_rc != 0 {
        io.println("error: failed to fetch git dependency '{name}' from {url}")
        return 1
    }

    let checkout_path = git_get_checkout_path()
    let commit = git_get_commit()
    let content_hash = git_get_content_hash()

    // Load the dep's manifest from checkout
    let manifest_path = path_join(checkout_path, "pact.toml")
    if file_exists(manifest_path) == 0 {
        io.println("error: git dependency '{name}' missing pact.toml")
        return 1
    }

    let load_rc = manifest_load(manifest_path)
    if load_rc != 0 {
        io.println("error: failed to load manifest for git dependency '{name}'")
        return 1
    }

    let pkg_name = manifest_name
    let pkg_version = manifest_version
    let pkg_caps = build_caps_string()
    let pkg_source = "git:".concat(url).concat("#").concat(commit)

    // Extract transitive deps before clobbering
    let sub_count = manifest_dep_count()
    let mut sub_names: List[Str] = []
    let mut sub_paths: List[Str] = []
    let mut sub_git_urls: List[Str] = []
    let mut sub_git_tags: List[Str] = []
    let mut sub_sources: List[Str] = []
    let mut i = 0
    while i < sub_count {
        sub_names.push(manifest_get_dep_name(i))
        sub_paths.push(dep_paths.get(i).unwrap())
        sub_git_urls.push(dep_git_urls.get(i).unwrap())
        sub_git_tags.push(dep_git_tags.get(i).unwrap())
        sub_sources.push(manifest_get_dep_source(i))
        i = i + 1
    }

    let add_rc = add_resolved(pkg_name, pkg_version, pkg_source, content_hash, pkg_caps)
    if add_rc != 0 {
        return 1
    }

    // Recurse into transitive deps
    let mut j = 0
    while j < sub_count {
        let src = sub_sources.get(j).unwrap()
        if src == "path" {
            let rc = process_path_dep(sub_names.get(j).unwrap(), sub_paths.get(j).unwrap(), checkout_path)
            if rc != 0 {
                return 1
            }
        } else if src == "git" {
            let rc = process_git_dep(sub_names.get(j).unwrap(), sub_git_urls.get(j).unwrap(), sub_git_tags.get(j).unwrap())
            if rc != 0 {
                return 1
            }
        }
        j = j + 1
    }

    0
}

// ── Main resolver entry point ───────────────────────────────────

pub fn resolve(project_root: Str) -> Int {
    let root_manifest = path_join(project_root, "pact.toml")
    let load_rc = manifest_load(root_manifest)
    if load_rc != 0 {
        io.println("error: failed to load root manifest")
        return 1
    }

    // Extract root deps into local arrays
    let dep_count = manifest_dep_count()
    let mut local_names: List[Str] = []
    let mut local_paths: List[Str] = []
    let mut local_git_urls: List[Str] = []
    let mut local_git_tags: List[Str] = []
    let mut local_sources: List[Str] = []
    let mut i = 0
    while i < dep_count {
        local_names.push(manifest_get_dep_name(i))
        local_paths.push(dep_paths.get(i).unwrap())
        local_git_urls.push(dep_git_urls.get(i).unwrap())
        local_git_tags.push(dep_git_tags.get(i).unwrap())
        local_sources.push(manifest_get_dep_source(i))
        i = i + 1
    }

    // Process each dependency
    let mut j = 0
    while j < dep_count {
        let src = local_sources.get(j).unwrap()
        if src == "path" {
            let rc = process_path_dep(local_names.get(j).unwrap(), local_paths.get(j).unwrap(), project_root)
            if rc != 0 {
                return 1
            }
        } else if src == "git" {
            let rc = process_git_dep(local_names.get(j).unwrap(), local_git_urls.get(j).unwrap(), local_git_tags.get(j).unwrap())
            if rc != 0 {
                return 1
            }
        }
        j = j + 1
    }

    0
}

// ── Resolve + write lockfile ────────────────────────────────────

pub fn resolve_and_lock(project_root: Str, pact_version: Str) -> Int {
    resolver_clear()
    let rc = resolve(project_root)
    if rc != 0 {
        return 1
    }

    lockfile_clear()
    let generated = time.read().to_rfc3339()
    lockfile_set_metadata(pact_version, generated)

    let mut i = 0
    while i < res_names.len() {
        lockfile_add_pkg(res_names.get(i).unwrap(), res_versions.get(i).unwrap(), res_sources.get(i).unwrap(), res_hashes.get(i).unwrap(), res_caps.get(i).unwrap())
        i = i + 1
    }

    let lock_path = path_join(project_root, "pact.lock")
    lockfile_write(lock_path)
    0
}

// ── Query functions ─────────────────────────────────────────────

pub fn resolver_count() -> Int {
    res_names.len()
}

pub fn resolver_get_name(i: Int) -> Str {
    if i < 0 || i >= res_names.len() {
        return ""
    }
    res_names.get(i).unwrap()
}

pub fn resolver_get_version(i: Int) -> Str {
    if i < 0 || i >= res_versions.len() {
        return ""
    }
    res_versions.get(i).unwrap()
}

pub fn resolver_get_source(i: Int) -> Str {
    if i < 0 || i >= res_sources.len() {
        return ""
    }
    res_sources.get(i).unwrap()
}

pub fn resolver_get_hash(i: Int) -> Str {
    if i < 0 || i >= res_hashes.len() {
        return ""
    }
    res_hashes.get(i).unwrap()
}

pub fn resolver_get_caps(i: Int) -> Str {
    if i < 0 || i >= res_caps.len() {
        return ""
    }
    res_caps.get(i).unwrap()
}
