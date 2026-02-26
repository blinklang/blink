import std.resolver
import std.lockfile

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

fn check_starts_with(actual: Str, prefix: Str, label: Str) {
    if actual.starts_with(prefix) {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected to start with \"{prefix}\", got \"{actual}\"")
    }
}

// ── Test: single path dependency ────────────────────────────────

fn test_single_path_dep() {
    io.println("--- test_single_path_dep ---")
    shell_exec("rm -rf /tmp/_pact_test_resolve_single")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_single/mylib/src")

    write_file("/tmp/_pact_test_resolve_single/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"mylib\" \}\n")
    write_file("/tmp/_pact_test_resolve_single/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")
    write_file("/tmp/_pact_test_resolve_single/mylib/src/lib.pact", "pub fn hello() -> Str \{ \"hi\" \}\n")

    resolver_clear()
    let rc = resolve("/tmp/_pact_test_resolve_single")
    check_int(rc, 0, "single path dep resolves")
    check_int(resolver_count(), 1, "one dep resolved")
    check_str(resolver_get_name(0), "mylib", "resolved name")
    check_str(resolver_get_version(0), "0.1.0", "resolved version")
    check_starts_with(resolver_get_source(0), "path:", "source is path")
}

// ── Test: single git dependency ─────────────────────────────────

fn test_single_git_dep() {
    io.println("--- test_single_git_dep ---")
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
    check_int(rc, 0, "git dep resolves")
    check_int(resolver_count(), 1, "one git dep resolved")
    check_str(resolver_get_name(0), "gitlib", "git dep name")
    check_str(resolver_get_version(0), "2.0.0", "git dep version")
    check_starts_with(resolver_get_source(0), "git:", "source is git")
}

// ── Test: diamond dep (same version = OK) ───────────────────────

fn test_diamond_same_version() {
    io.println("--- test_diamond_same_version ---")
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
    check_int(rc, 0, "diamond same version resolves ok")

    // shared should appear once
    let mut shared_count = 0
    let mut i = 0
    while i < resolver_count() {
        if resolver_get_name(i) == "shared" {
            shared_count = shared_count + 1
        }
        i = i + 1
    }
    check_int(shared_count, 1, "shared resolved once")
}

// ── Test: diamond conflict (diff version = error) ───────────────

fn test_diamond_conflict() {
    io.println("--- test_diamond_conflict ---")
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
    check_int(rc, 1, "diamond conflict returns error")
}

// ── Test: transitive chain ──────────────────────────────────────

fn test_transitive_chain() {
    io.println("--- test_transitive_chain ---")
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
    check_int(rc, 0, "chain resolves ok")
    check_int(resolver_count(), 2, "two deps in chain")
    check_str(resolver_get_name(0), "libA", "first is libA")
    check_str(resolver_get_name(1), "libB", "second is libB")
}

// ── Test: resolve_and_lock writes lockfile ──────────────────────

fn test_resolve_and_lock() {
    io.println("--- test_resolve_and_lock ---")
    shell_exec("rm -rf /tmp/_pact_test_resolve_lock")
    shell_exec("mkdir -p /tmp/_pact_test_resolve_lock/mylib/src")

    write_file("/tmp/_pact_test_resolve_lock/pact.toml", "[package]\nname = \"root\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"mylib\" \}\n")
    write_file("/tmp/_pact_test_resolve_lock/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.3.0\"\n\n[capabilities]\nrequired = [\"Net.Connect\"]\n")
    write_file("/tmp/_pact_test_resolve_lock/mylib/src/lib.pact", "pub fn fetch() -> Int \{ 0 \}\n")

    let rc = resolve_and_lock("/tmp/_pact_test_resolve_lock")
    check_int(rc, 0, "resolve_and_lock succeeds")

    // Verify lockfile was written
    let lock_path = "/tmp/_pact_test_resolve_lock/pact.lock"
    let exists = file_exists(lock_path)
    check_int(exists, 1, "lockfile written")

    // Load and verify lockfile contents
    lockfile_clear()
    let load_rc = lockfile_load(lock_path)
    check_int(load_rc, 0, "lockfile loads ok")
    check_int(lockfile_pkg_count(), 1, "lockfile has 1 package")
    check_str(lock_pkg_names.unsafe_get(0), "mylib", "lockfile pkg name")
    check_str(lock_pkg_versions.unsafe_get(0), "0.3.0", "lockfile pkg version")
    check_starts_with(lock_pkg_sources.unsafe_get(0), "path:", "lockfile source is path")
    check_str(lock_pkg_caps.unsafe_get(0), "Net.Connect", "lockfile caps")
}

// ── Test: clear state ───────────────────────────────────────────

fn test_clear() {
    io.println("--- test_clear ---")
    res_names.push("test")
    res_versions.push("1.0")
    res_sources.push("path:/x")
    res_hashes.push("abc")
    res_caps.push("")

    resolver_clear()
    check_int(resolver_count(), 0, "clear: no deps")
    check_str(resolver_get_name(0), "", "clear: name oob")
}

// ── Test: query bounds ──────────────────────────────────────────

fn test_query_bounds() {
    io.println("--- test_query_bounds ---")
    resolver_clear()
    check_str(resolver_get_name(-1), "", "negative index name")
    check_str(resolver_get_version(-1), "", "negative index version")
    check_str(resolver_get_source(99), "", "large index source")
    check_str(resolver_get_hash(99), "", "large index hash")
    check_str(resolver_get_caps(99), "", "large index caps")
}

fn cleanup() {
    shell_exec("rm -rf /tmp/_pact_test_resolve_single /tmp/_pact_test_resolve_git /tmp/_pact_test_resolve_diamond /tmp/_pact_test_resolve_conflict /tmp/_pact_test_resolve_chain /tmp/_pact_test_resolve_lock /tmp/_pact_hash /tmp/_pact_commit /tmp/_pact_home")
    shell_exec("rm -rf ~/.pact/cache/git/*_pact_test_*")
}

fn main() {
    test_clear()
    test_query_bounds()
    test_single_path_dep()
    test_single_git_dep()
    test_diamond_same_version()
    test_diamond_conflict()
    test_transitive_chain()
    test_resolve_and_lock()
    cleanup()
    io.println("All resolver tests complete")
}
