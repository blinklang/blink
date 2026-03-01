// manifest.pact — pact.toml manifest loader and validator (§8.9.3)
//
// Loads, parses, and validates pact.toml project manifests.
// Uses std.toml for parsing and stores results in parallel arrays.

import std.toml

// ── Package metadata ─────────────────────────────────────────────
pub let mut manifest_name: Str = ""
pub let mut manifest_version: Str = ""
pub let mut manifest_edition: Str = ""
pub let mut manifest_description: Str = ""
pub let mut manifest_license: Str = ""
pub let mut manifest_repository: Str = ""

// ── Dependencies: parallel arrays ────────────────────────────────
pub let mut dep_names: List[Str] = []
pub let mut dep_versions: List[Str] = []
pub let mut dep_git_urls: List[Str] = []
pub let mut dep_git_tags: List[Str] = []
pub let mut dep_paths: List[Str] = []
pub let mut dep_is_dev: List[Int] = []

// ── Capabilities ─────────────────────────────────────────────────
pub let mut cap_required: List[Str] = []
pub let mut cap_optional: List[Str] = []

// ── Alternatives ─────────────────────────────────────────────────
pub let mut alt_keys: List[Str] = []
pub let mut alt_values: List[Str] = []

// ── Known top-level sections ─────────────────────────────────────
let SECTION_COUNT = 5
let mut known_sections: List[Str] = ["package", "dependencies", "dev-dependencies", "capabilities", "alternatives"]

// ── Clear all manifest state ─────────────────────────────────────

pub fn manifest_clear() {
    manifest_name = ""
    manifest_version = ""
    manifest_edition = ""
    manifest_description = ""
    manifest_license = ""
    manifest_repository = ""
    dep_names = []
    dep_versions = []
    dep_git_urls = []
    dep_git_tags = []
    dep_paths = []
    dep_is_dev = []
    cap_required = []
    cap_optional = []
    alt_keys = []
    alt_values = []
}

// ── Helpers ──────────────────────────────────────────────────────

fn is_known_section(name: Str) -> Int {
    let mut i = 0
    while i < known_sections.len() {
        if known_sections.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

fn has_dep(name: Str) -> Int {
    let mut i = 0
    while i < dep_names.len() {
        if dep_names.get(i).unwrap() == name {
            return 1
        }
        i = i + 1
    }
    0
}

// Extract the dep name from a toml key like "dependencies.std/http" or
// "dependencies.std/http.git". Returns the portion after "dependencies."
// up to the next dot (if any) that isn't part of a package name with /.
// dep_prefix is "dependencies" or "dev-dependencies".
fn extract_dep_name(key: Str, prefix_len: Int) -> Str {
    // Skip past "dependencies." or "dev-dependencies."
    let start = prefix_len + 1
    if start >= key.len() {
        return ""
    }
    let rest = key.substring(start, key.len() - start)
    // The dep name can contain / (e.g. std/http). We need to find the
    // sub-key separator dot that comes AFTER the dep name. Dep names
    // are bare-key chars (alphanumeric, -, _, /). We scan for a dot
    // that is followed by a known sub-key: git, tag, path, version, features.
    let mut i = 0
    while i < rest.len() {
        if rest.char_at(i) == 46 {
            // 46 = '.'
            let after = rest.substring(i + 1, rest.len() - i - 1)
            if after == "git" || after == "tag" || after == "path" || after == "version" || after == "features" {
                return rest.substring(0, i)
            }
            if after.starts_with("features[") {
                return rest.substring(0, i)
            }
        }
        i = i + 1
    }
    rest
}

fn add_dep(name: Str, version: Str, git_url: Str, git_tag: Str, dep_path: Str, is_dev: Int) {
    dep_names.push(name)
    dep_versions.push(version)
    dep_git_urls.push(git_url)
    dep_git_tags.push(git_tag)
    dep_paths.push(dep_path)
    dep_is_dev.push(is_dev)
}

// ── Load package metadata from parsed toml ───────────────────────

pub fn load_package() -> Int {
    if toml_has("package.name") == 0 {
        io.println("error: [package] section missing required field 'name'")
        return 1
    }
    if toml_has("package.version") == 0 {
        io.println("error: [package] section missing required field 'version'")
        return 1
    }

    manifest_name = toml_get("package.name")
    manifest_version = toml_get("package.version")

    if manifest_name == "" {
        io.println("error: package name must not be empty")
        return 1
    }
    if manifest_version == "" {
        io.println("error: package version must not be empty")
        return 1
    }

    if toml_has("package.edition") == 1 {
        manifest_edition = toml_get("package.edition")
    }
    if toml_has("package.description") == 1 {
        manifest_description = toml_get("package.description")
    }
    if toml_has("package.license") == 1 {
        manifest_license = toml_get("package.license")
    }
    if toml_has("package.repository") == 1 {
        manifest_repository = toml_get("package.repository")
    }

    0
}

// ── Collect dependency names from toml keys ──────────────────────
// Scans toml_keys for entries starting with the given prefix
// (e.g. "dependencies" or "dev-dependencies") and collects
// unique dep names into a temporary list.

let mut tmp_dep_names: List[Str] = []

fn collect_dep_names(prefix: Str) {
    tmp_dep_names = []
    let prefix_dot = prefix.concat(".")
    let prefix_dot_len = prefix_dot.len()
    let mut i = 0
    while i < toml_keys.len() {
        let key = toml_keys.get(i).unwrap()
        if key.starts_with(prefix_dot) {
            let name = extract_dep_name(key, prefix.len())
            if name != "" {
                // Check if already collected
                let mut found = 0
                let mut j = 0
                while j < tmp_dep_names.len() {
                    if tmp_dep_names.get(j).unwrap() == name {
                        found = 1
                    }
                    j = j + 1
                }
                if found == 0 {
                    tmp_dep_names.push(name)
                }
            }
        }
        i = i + 1
    }
}

// ── Load dependencies from a section ─────────────────────────────

pub fn load_deps(prefix: Str, is_dev: Int) -> Int {
    collect_dep_names(prefix)

    let mut i = 0
    while i < tmp_dep_names.len() {
        let name = tmp_dep_names.get(i).unwrap()
        let base_key = prefix.concat(".").concat(name)

        let mut version = ""
        let mut git_url = ""
        let mut git_tag = ""
        let mut dep_path = ""
        let mut source_count = 0

        // Check if this is a plain string value (e.g. std/http = "1.2")
        if toml_has(base_key) == 1 {
            let idx = find_dep_type(base_key)
            if idx == 0 {
                // TOML_STRING — simple version constraint
                version = toml_get(base_key)
                source_count = source_count + 1
            } else if idx == 4 {
                // TOML_INLINE_TABLE — check sub-keys
                let ver_key = base_key.concat(".version")
                let git_key = base_key.concat(".git")
                let tag_key = base_key.concat(".tag")
                let path_key = base_key.concat(".path")

                if toml_has(ver_key) == 1 {
                    version = toml_get(ver_key)
                    source_count = source_count + 1
                }
                if toml_has(git_key) == 1 {
                    git_url = toml_get(git_key)
                    source_count = source_count + 1
                    if toml_has(tag_key) == 1 {
                        git_tag = toml_get(tag_key)
                    }
                }
                if toml_has(path_key) == 1 {
                    dep_path = toml_get(path_key)
                    source_count = source_count + 1
                }
            }
        } else {
            // Inline table sub-keys exist but no base entry — check sub-keys directly
            let ver_key = base_key.concat(".version")
            let git_key = base_key.concat(".git")
            let tag_key = base_key.concat(".tag")
            let path_key = base_key.concat(".path")

            if toml_has(ver_key) == 1 {
                version = toml_get(ver_key)
                source_count = source_count + 1
            }
            if toml_has(git_key) == 1 {
                git_url = toml_get(git_key)
                source_count = source_count + 1
                if toml_has(tag_key) == 1 {
                    git_tag = toml_get(tag_key)
                }
            }
            if toml_has(path_key) == 1 {
                dep_path = toml_get(path_key)
                source_count = source_count + 1
            }
        }

        if source_count == 0 {
            io.println("error: dependency '{name}' has no source (need version, git, or path)")
            return 1
        }
        if source_count > 1 {
            io.println("error: dependency '{name}' has multiple sources (must specify exactly one of: version, git, path)")
            return 1
        }

        add_dep(name, version, git_url, git_tag, dep_path, is_dev)
        i = i + 1
    }

    0
}

// Look up the toml type tag for a key
fn find_dep_type(key: Str) -> Int {
    let mut i = 0
    while i < toml_keys.len() {
        if toml_keys.get(i).unwrap() == key {
            return toml_types.get(i).unwrap()
        }
        i = i + 1
    }
    -1
}

// ── Load capabilities ────────────────────────────────────────────

pub fn load_capabilities() {
    if toml_has("capabilities.required") == 1 {
        let count = toml_get_array_len("capabilities.required")
        let mut i = 0
        while i < count {
            let item = toml_get_array_item("capabilities.required", i)
            cap_required.push(item)
            i = i + 1
        }
    }
    if toml_has("capabilities.optional") == 1 {
        let count = toml_get_array_len("capabilities.optional")
        let mut i = 0
        while i < count {
            let item = toml_get_array_item("capabilities.optional", i)
            cap_optional.push(item)
            i = i + 1
        }
    }
}

// ── Load alternatives ────────────────────────────────────────────

pub fn load_alternatives() {
    let prefix = "alternatives."
    let prefix_len = prefix.len()
    let mut i = 0
    while i < toml_keys.len() {
        let key = toml_keys.get(i).unwrap()
        if key.starts_with(prefix) {
            let alt_key = key.substring(prefix_len, key.len() - prefix_len)
            let alt_val = toml_values.get(i).unwrap()
            alt_keys.push(alt_key)
            alt_values.push(alt_val)
        }
        i = i + 1
    }
}

// ── Warn about unknown sections ──────────────────────────────────

fn check_unknown_sections() {
    let mut i = 0
    while i < toml_keys.len() {
        let key = toml_keys.get(i).unwrap()
        // Extract top-level section name (part before first dot)
        let mut dot_pos = -1
        let mut j = 0
        while j < key.len() {
            if key.char_at(j) == 46 {
                dot_pos = j
                j = key.len()
            }
            j = j + 1
        }
        let mut section = key
        if dot_pos > 0 {
            section = key.substring(0, dot_pos)
        }
        if is_known_section(section) == 0 {
            io.println("warning: unknown section '{section}' in pact.toml")
            // Only warn once per unknown section — add it to known list
            known_sections.push(section)
        }
        i = i + 1
    }
}

// ── Main load function ───────────────────────────────────────────

pub fn manifest_load(path: Str) -> Int {
    manifest_clear()
    toml_clear()

    if file_exists(path) == 0 {
        io.println("error: manifest file not found: {path}")
        return 1
    }

    let content = read_file(path)
    let parse_result = toml_parse(content)
    if parse_result != 0 {
        io.println("error: failed to parse manifest: {path}")
        return 1
    }

    let pkg_result = load_package()
    if pkg_result != 0 {
        return 1
    }

    let dep_result = load_deps("dependencies", 0)
    if dep_result != 0 {
        return 1
    }

    let dev_dep_result = load_deps("dev-dependencies", 1)
    if dev_dep_result != 0 {
        return 1
    }

    load_capabilities()
    load_alternatives()
    check_unknown_sections()

    0
}

// ── Query functions ──────────────────────────────────────────────

pub fn manifest_dep_count() -> Int {
    dep_names.len()
}

pub fn manifest_get_dep_name(i: Int) -> Str {
    if i < 0 || i >= dep_names.len() {
        return ""
    }
    dep_names.get(i).unwrap()
}

pub fn manifest_get_dep_version(i: Int) -> Str {
    if i < 0 || i >= dep_versions.len() {
        return ""
    }
    dep_versions.get(i).unwrap()
}

pub fn manifest_get_dep_source(i: Int) -> Str {
    if i < 0 || i >= dep_names.len() {
        return ""
    }
    if dep_git_urls.get(i).unwrap() != "" {
        return "git"
    }
    if dep_paths.get(i).unwrap() != "" {
        return "path"
    }
    "registry"
}

pub fn manifest_has_dep(name: Str) -> Int {
    has_dep(name)
}
