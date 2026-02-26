import std.manifest

fn check_str(actual: Str, expected: Str, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected \"{expected}\", got \"{actual}\"")
    }
}

fn check_int(actual: Int, expected: Int, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected {expected}, got {actual}")
    }
}

fn test_basic_manifest() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"acme/myapp\"\nversion = \"0.1.0\"\nedition = \"2026\"\ndescription = \"My app\"\nlicense = \"MIT\"\nrepository = \"https://github.com/acme/myapp\"\n"
    toml_parse(content)
    let rc = load_package()
    check_int(rc, 0, "load_package succeeds")
    check_str(manifest_name, "acme/myapp", "package name")
    check_str(manifest_version, "0.1.0", "package version")
    check_str(manifest_edition, "2026", "edition")
    check_str(manifest_description, "My app", "description")
    check_str(manifest_license, "MIT", "license")
    check_str(manifest_repository, "https://github.com/acme/myapp", "repository")
}

fn test_missing_name() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nversion = \"1.0.0\"\n"
    toml_parse(content)
    let rc = load_package()
    check_int(rc, 1, "missing name returns error")
}

fn test_missing_version() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\n"
    toml_parse(content)
    let rc = load_package()
    check_int(rc, 1, "missing version returns error")
}

fn test_string_deps() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\nstd/json = \"~1.0\"\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    check_int(rc, 0, "string deps load ok")
    check_int(manifest_dep_count(), 2, "two deps loaded")
    check_int(manifest_has_dep("std/http"), 1, "has std/http")
    check_int(manifest_has_dep("std/json"), 1, "has std/json")
}

fn test_git_dep() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\ninternal/lib = \{ git = \"https://github.com/org/lib.git\", tag = \"v1.0\" \}\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    check_int(rc, 0, "git dep loads ok")
    check_int(manifest_dep_count(), 1, "one git dep")
    check_str(manifest_get_dep_source(0), "git", "dep source is git")
    check_str(dep_git_urls.unsafe_get(0), "https://github.com/org/lib.git", "git url")
    check_str(dep_git_tags.unsafe_get(0), "v1.0", "git tag")
}

fn test_path_dep() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nlocal/utils = \{ path = \"../utils\" \}\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    check_int(rc, 0, "path dep loads ok")
    check_int(manifest_dep_count(), 1, "one path dep")
    check_str(manifest_get_dep_source(0), "path", "dep source is path")
    check_str(dep_paths.unsafe_get(0), "../utils", "path value")
}

fn test_dev_deps() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dev-dependencies]\nstd/bench = \"0.3\"\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dev-dependencies", 1)
    check_int(rc, 0, "dev deps load ok")
    check_int(manifest_dep_count(), 1, "one dev dep")
    check_int(dep_is_dev.unsafe_get(0), 1, "is dev dependency")
}

fn test_capabilities() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[capabilities]\nrequired = [\"Net.Connect\", \"Net.DNS\"]\noptional = [\"IO.Log\"]\n"
    toml_parse(content)
    load_package()
    load_capabilities()
    check_int(cap_required.len(), 2, "2 required caps")
    check_str(cap_required.unsafe_get(0), "Net.Connect", "required cap 0")
    check_str(cap_required.unsafe_get(1), "Net.DNS", "required cap 1")
    check_int(cap_optional.len(), 1, "1 optional cap")
    check_str(cap_optional.unsafe_get(0), "IO.Log", "optional cap 0")
}

fn test_alternatives() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[alternatives]\nNet.Connect = \"mock-http\"\n"
    toml_parse(content)
    load_package()
    load_alternatives()
    check_int(alt_keys.len(), 1, "1 alternative")
    check_str(alt_keys.unsafe_get(0), "Net.Connect", "alt key")
    check_str(alt_values.unsafe_get(0), "mock-http", "alt value")
}

fn test_dep_source_query() {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\n"
    toml_parse(content)
    load_package()
    load_deps("dependencies", 0)
    check_str(manifest_get_dep_source(0), "registry", "registry source")
    check_str(manifest_get_dep_version(0), "1.2", "dep version")
    check_str(manifest_get_dep_name(0), "std/http", "dep name")
}

fn test_manifest_clear() {
    manifest_clear()
    check_str(manifest_name, "", "cleared name")
    check_str(manifest_version, "", "cleared version")
    check_int(manifest_dep_count(), 0, "cleared deps")
    check_int(cap_required.len(), 0, "cleared caps")
}

fn main() {
    test_basic_manifest()
    test_missing_name()
    test_missing_version()
    test_string_deps()
    test_git_dep()
    test_path_dep()
    test_dev_deps()
    test_capabilities()
    test_alternatives()
    test_dep_source_query()
    test_manifest_clear()
    io.println("All manifest tests complete")
}
