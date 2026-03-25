import pkg.resolver
import pkg.lockfile

test "clear" {
    res_names.push("test")
    res_versions.push("1.0")
    res_sources.push("path:/x")
    res_hashes.push("abc")
    res_caps.push("")

    resolver_clear()
    assert_eq(resolver_count(), 0)
    assert_eq(resolver_get_name(0), "")
}

test "query bounds" {
    resolver_clear()
    assert_eq(resolver_get_name(-1), "")
    assert_eq(resolver_get_version(-1), "")
    assert_eq(resolver_get_source(99), "")
    assert_eq(resolver_get_hash(99), "")
    assert_eq(resolver_get_caps(99), "")
}

test "single path dep" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_single")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_single/mylib/src")

    write_file("/tmp/_pact_test_resolve_single/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"mylib\" \}\n")
    write_file("/tmp/_pact_test_resolve_single/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")
    write_file("/tmp/_pact_test_resolve_single/mylib/src/lib.pact", "pub fn hello() -> Str \{ \"hi\" \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_single")
    assert_eq(rc, 0)
    assert_eq(resolver_count(), 1)
    assert_eq(resolver_get_name(0), "mylib")
    assert_eq(resolver_get_version(0), "0.1.0")
    assert(resolver_get_source(0).starts_with("path:"))
}

test "single git dep" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_git")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_git/project")

    // Create a git repo to use as dependency
    shell_exec("mkdir -p /tmp/_pact_test_resolve_git/gitlib/src")
    write_file("/tmp/_pact_test_resolve_git/gitlib/pact.toml", "[package]\nname = \"gitlib\"\nversion = \"2.0.0\"\n")
    write_file("/tmp/_pact_test_resolve_git/gitlib/src/lib.pact", "pub fn greet() -> Str \{ \"hello\" \}\n")
    shell_exec("cd /tmp/_pact_test_resolve_git/gitlib && git init && git add -A && git commit -m 'init' && git tag v2.0")

    write_file("/tmp/_pact_test_resolve_git/project/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\ngitlib = \{ git = \"file:///tmp/_pact_test_resolve_git/gitlib\", tag = \"v2.0\" \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_git/project")
    assert_eq(rc, 0)
    assert_eq(resolver_count(), 1)
    assert_eq(resolver_get_name(0), "gitlib")
    assert_eq(resolver_get_version(0), "2.0.0")
    assert(resolver_get_source(0).starts_with("git:"))
}

test "diamond same version" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_diamond")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_diamond/libA/shared/src")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_diamond/libB")

    write_file("/tmp/_pact_test_resolve_diamond/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibA = \{ path = \"libA\" \}\nlibB = \{ path = \"libB\" \}\n")
    write_file("/tmp/_pact_test_resolve_diamond/libA/pact.toml", "[package]\nname = \"libA\"\nversion = \"0.1.0\"\n\n[dependencies]\nshared = \{ path = \"shared\" \}\n")
    write_file("/tmp/_pact_test_resolve_diamond/libA/shared/pact.toml", "[package]\nname = \"shared\"\nversion = \"0.5.0\"\n")
    write_file("/tmp/_pact_test_resolve_diamond/libA/shared/src/lib.pact", "pub fn common() -> Int \{ 42 \}\n")
    shell_exec("cp -r /tmp/_pact_test_resolve_diamond/libA/shared /tmp/_pact_test_resolve_diamond/libB/shared")
    write_file("/tmp/_pact_test_resolve_diamond/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.2.0\"\n\n[dependencies]\nshared = \{ path = \"shared\" \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_diamond")
    assert_eq(rc, 0)

    // shared should appear once
    let mut shared_count = 0
    let mut i = 0
    while i < resolver_count() {
        if resolver_get_name(i) == "shared" {
            shared_count = shared_count + 1
        }
        i = i + 1
    }
    assert_eq(shared_count, 1)
}

test "diamond conflict" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_conflict")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_conflict/libA/shared/src")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_conflict/libB/shared/src")

    write_file("/tmp/_pact_test_resolve_conflict/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibA = \{ path = \"libA\" \}\nlibB = \{ path = \"libB\" \}\n")
    write_file("/tmp/_pact_test_resolve_conflict/libA/pact.toml", "[package]\nname = \"libA\"\nversion = \"0.1.0\"\n\n[dependencies]\nshared = \{ path = \"shared\" \}\n")
    write_file("/tmp/_pact_test_resolve_conflict/libA/shared/pact.toml", "[package]\nname = \"shared\"\nversion = \"0.5.0\"\n")
    write_file("/tmp/_pact_test_resolve_conflict/libA/shared/src/lib.pact", "pub fn f() -> Int \{ 1 \}\n")
    write_file("/tmp/_pact_test_resolve_conflict/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.2.0\"\n\n[dependencies]\nshared = \{ path = \"shared\" \}\n")
    write_file("/tmp/_pact_test_resolve_conflict/libB/shared/pact.toml", "[package]\nname = \"shared\"\nversion = \"0.9.0\"\n")
    write_file("/tmp/_pact_test_resolve_conflict/libB/shared/src/lib.pact", "pub fn f() -> Int \{ 2 \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_conflict")
    assert_eq(rc, 1)
}

test "transitive chain" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_chain")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_chain/libA/libB/src")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_chain/libA/src")

    write_file("/tmp/_pact_test_resolve_chain/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibA = \{ path = \"libA\" \}\n")
    write_file("/tmp/_pact_test_resolve_chain/libA/pact.toml", "[package]\nname = \"libA\"\nversion = \"0.1.0\"\n\n[dependencies]\nlibB = \{ path = \"libB\" \}\n")
    write_file("/tmp/_pact_test_resolve_chain/libA/src/a.pact", "pub fn a() -> Int \{ 1 \}\n")
    write_file("/tmp/_pact_test_resolve_chain/libA/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.2.0\"\n")
    write_file("/tmp/_pact_test_resolve_chain/libA/libB/src/b.pact", "pub fn b() -> Int \{ 2 \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_chain")
    assert_eq(rc, 0)
    assert_eq(resolver_count(), 2)
    assert_eq(resolver_get_name(0), "libA")
    assert_eq(resolver_get_name(1), "libB")
}

test "resolve and lock" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_lock")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_lock/mylib/src")

    write_file("/tmp/_pact_test_resolve_lock/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"mylib\" \}\n")
    write_file("/tmp/_pact_test_resolve_lock/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.3.0\"\n\n[capabilities]\nrequired = [\"Net.Connect\"]\n")
    write_file("/tmp/_pact_test_resolve_lock/mylib/src/lib.pact", "pub fn fetch() -> Int \{ 0 \}\n")

    let rc = resolve_and_lock("/tmp/_pact_test_resolve_lock", "0.0.0-test")
    assert_eq(rc, 0)

    // Verify lockfile was written (resolver writes blink.lock)
    let mut lock_path = "/tmp/_pact_test_resolve_lock/blink.lock"
    let mut exists = file_exists(lock_path)
    if exists == 0 {
        lock_path = "/tmp/_pact_test_resolve_lock/pact.lock"
        exists = file_exists(lock_path)
    }
    assert_eq(exists, 1)

    // Load and verify lockfile contents
    lockfile_clear()
    let load_rc = lockfile_load(lock_path)
    assert_eq(load_rc, 0)
    assert_eq(lockfile_pkg_count(), 1)
    assert_eq(lock_pkg_names.get(0).unwrap(), "mylib")
    assert_eq(lock_pkg_versions.get(0).unwrap(), "0.3.0")
    assert(lock_pkg_sources.get(0).unwrap().starts_with("path:"))
    assert_eq(lock_pkg_caps.get(0).unwrap(), "Net.Connect")
}

test "cleanup" {
    shell_exec("rm -rf /tmp/_pact_test_resolve_single /tmp/_pact_test_resolve_git /tmp/_pact_test_resolve_diamond /tmp/_pact_test_resolve_conflict /tmp/_pact_test_resolve_chain /tmp/_pact_test_resolve_lock /tmp/_pact_hash /tmp/_pact_commit /tmp/_pact_home")
    shell_exec("rm -rf ~/.blink/cache/git/*_pact_test_*")
}
