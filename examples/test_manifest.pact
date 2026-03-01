import pkg.manifest

test "basic manifest parsing" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"acme/myapp\"\nversion = \"0.1.0\"\nedition = \"2026\"\ndescription = \"My app\"\nlicense = \"MIT\"\nrepository = \"https://github.com/acme/myapp\"\n"
    toml_parse(content)
    let rc = load_package()
    assert_eq(rc, 0)
    assert_eq(manifest_name, "acme/myapp")
    assert_eq(manifest_version, "0.1.0")
    assert_eq(manifest_edition, "2026")
    assert_eq(manifest_description, "My app")
    assert_eq(manifest_license, "MIT")
    assert_eq(manifest_repository, "https://github.com/acme/myapp")
}

test "missing name returns error" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nversion = \"1.0.0\"\n"
    toml_parse(content)
    let rc = load_package()
    assert_eq(rc, 1)
}

test "missing version returns error" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\n"
    toml_parse(content)
    let rc = load_package()
    assert_eq(rc, 1)
}

test "string dependencies" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\nstd/json = \"~1.0\"\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    assert_eq(rc, 0)
    assert_eq(manifest_dep_count(), 2)
    assert_eq(manifest_has_dep("std/http"), 1)
    assert_eq(manifest_has_dep("std/json"), 1)
}

test "git dependency" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\ninternal/lib = \{ git = \"https://github.com/org/lib.git\", tag = \"v1.0\" \}\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    assert_eq(rc, 0)
    assert_eq(manifest_dep_count(), 1)
    assert_eq(manifest_get_dep_source(0), "git")
    assert_eq(dep_git_urls.get(0).unwrap(), "https://github.com/org/lib.git")
    assert_eq(dep_git_tags.get(0).unwrap(), "v1.0")
}

test "path dependency" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nlocal/utils = \{ path = \"../utils\" \}\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dependencies", 0)
    assert_eq(rc, 0)
    assert_eq(manifest_dep_count(), 1)
    assert_eq(manifest_get_dep_source(0), "path")
    assert_eq(dep_paths.get(0).unwrap(), "../utils")
}

test "dev dependencies" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dev-dependencies]\nstd/bench = \"0.3\"\n"
    toml_parse(content)
    load_package()
    let rc = load_deps("dev-dependencies", 1)
    assert_eq(rc, 0)
    assert_eq(manifest_dep_count(), 1)
    assert_eq(dep_is_dev.get(0).unwrap(), 1)
}

test "capabilities" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[capabilities]\nrequired = [\"Net.Connect\", \"Net.DNS\"]\noptional = [\"IO.Log\"]\n"
    toml_parse(content)
    load_package()
    load_capabilities()
    assert_eq(cap_required.len(), 2)
    assert_eq(cap_required.get(0).unwrap(), "Net.Connect")
    assert_eq(cap_required.get(1).unwrap(), "Net.DNS")
    assert_eq(cap_optional.len(), 1)
    assert_eq(cap_optional.get(0).unwrap(), "IO.Log")
}

test "alternatives" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[alternatives]\nNet.Connect = \"mock-http\"\n"
    toml_parse(content)
    load_package()
    load_alternatives()
    assert_eq(alt_keys.len(), 1)
    assert_eq(alt_keys.get(0).unwrap(), "Net.Connect")
    assert_eq(alt_values.get(0).unwrap(), "mock-http")
}

test "dependency source query" {
    manifest_clear()
    toml_clear()
    let content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\n"
    toml_parse(content)
    load_package()
    load_deps("dependencies", 0)
    assert_eq(manifest_get_dep_source(0), "registry")
    assert_eq(manifest_get_dep_version(0), "1.2")
    assert_eq(manifest_get_dep_name(0), "std/http")
}

test "manifest clear resets all fields" {
    manifest_clear()
    assert_eq(manifest_name, "")
    assert_eq(manifest_version, "")
    assert_eq(manifest_dep_count(), 0)
    assert_eq(cap_required.len(), 0)
}
