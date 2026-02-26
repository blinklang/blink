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

fn test_clear() {
    lockfile_clear()
    check_int(lockfile_pkg_count(), 0, "clear: no packages")
    check_int(lock_version, 0, "clear: version 0")
    check_str(lock_pact_version, "", "clear: no pact version")
}

fn test_add_and_query() {
    lockfile_clear()
    lockfile_set_metadata("0.1.0", "2026-02-14T10:00:00Z")
    lockfile_add_pkg("std/http", "1.2.0", "registry", "sha256:abc123", "Net.Connect,Net.DNS")
    lockfile_add_pkg("std/json", "1.0.3", "registry", "sha256:def456", "")

    check_int(lockfile_pkg_count(), 2, "2 packages")
    check_int(lockfile_find_pkg("std/http"), 0, "find std/http at 0")
    check_int(lockfile_find_pkg("std/json"), 1, "find std/json at 1")
    check_int(lockfile_find_pkg("missing"), -1, "missing returns -1")
    check_str(lockfile_get_pkg_hash("std/http"), "sha256:abc123", "http hash")
    check_int(lockfile_verify_hash("std/http", "sha256:abc123"), 1, "hash matches")
    check_int(lockfile_verify_hash("std/http", "sha256:wrong"), 0, "hash mismatch")
    check_int(lockfile_verify_hash("missing", "sha256:abc"), 0, "verify missing pkg")
}

fn test_metadata() {
    lockfile_clear()
    lockfile_set_metadata("0.2.0", "2026-01-15T10:30:00Z")
    check_int(lock_version, 1, "metadata sets version 1")
    check_str(lock_pact_version, "0.2.0", "pact version set")
    check_str(lock_generated, "2026-01-15T10:30:00Z", "generated set")
}

fn test_write_and_load() {
    lockfile_clear()
    lockfile_set_metadata("0.1.0", "2026-02-14T12:00:00Z")
    lockfile_add_pkg("std/json", "1.0.3", "registry", "sha256:def456", "")
    lockfile_add_pkg("acme/auth", "0.5.0", "registry", "sha256:789ghi", "Net.Connect")
    lockfile_add_pkg("std/http", "1.2.0", "registry", "sha256:abc123", "Net.Connect,Net.DNS")

    lockfile_write("/tmp/test_pact.lock")

    lockfile_clear()
    let rc = lockfile_load("/tmp/test_pact.lock")
    check_int(rc, 0, "load succeeds")
    check_int(lock_version, 1, "loaded version")
    check_str(lock_pact_version, "0.1.0", "loaded pact version")
    check_str(lock_generated, "2026-02-14T12:00:00Z", "loaded generated")
    check_int(lockfile_pkg_count(), 3, "loaded 3 packages")

    // Should be sorted alphabetically: acme/auth, std/http, std/json
    check_str(lock_pkg_names.unsafe_get(0), "acme/auth", "sorted first: acme/auth")
    check_str(lock_pkg_names.unsafe_get(1), "std/http", "sorted second: std/http")
    check_str(lock_pkg_names.unsafe_get(2), "std/json", "sorted third: std/json")

    check_str(lock_pkg_hashes.unsafe_get(0), "sha256:789ghi", "acme/auth hash")
    check_str(lock_pkg_hashes.unsafe_get(1), "sha256:abc123", "std/http hash")
    check_str(lock_pkg_caps.unsafe_get(1), "Net.Connect,Net.DNS", "std/http caps")
}

fn test_load_missing_file() {
    lockfile_clear()
    let rc = lockfile_load("/tmp/nonexistent_lockfile_12345.lock")
    check_int(rc, 1, "missing file returns error")
}

fn test_sort_determinism() {
    lockfile_clear()
    lockfile_set_metadata("0.1.0", "2026-01-01T00:00:00Z")
    lockfile_add_pkg("zzz/last", "1.0.0", "registry", "sha256:zzz", "")
    lockfile_add_pkg("aaa/first", "1.0.0", "registry", "sha256:aaa", "")
    lockfile_add_pkg("mmm/middle", "1.0.0", "registry", "sha256:mmm", "")

    lockfile_write("/tmp/test_sort.lock")

    lockfile_clear()
    lockfile_load("/tmp/test_sort.lock")
    check_str(lock_pkg_names.unsafe_get(0), "aaa/first", "sort: first")
    check_str(lock_pkg_names.unsafe_get(1), "mmm/middle", "sort: middle")
    check_str(lock_pkg_names.unsafe_get(2), "zzz/last", "sort: last")
}

fn test_caps_format() {
    lockfile_clear()
    lockfile_set_metadata("0.1.0", "2026-01-01T00:00:00Z")
    lockfile_add_pkg("pkg/a", "1.0.0", "registry", "sha256:aaa", "Net.Connect,FS.Read,IO.Log")
    lockfile_add_pkg("pkg/b", "1.0.0", "registry", "sha256:bbb", "")

    lockfile_write("/tmp/test_caps.lock")

    lockfile_clear()
    lockfile_load("/tmp/test_caps.lock")
    check_str(lock_pkg_caps.unsafe_get(0), "Net.Connect,FS.Read,IO.Log", "multi caps round-trip")
    check_str(lock_pkg_caps.unsafe_get(1), "", "empty caps round-trip")
}

fn main() {
    test_clear()
    test_add_and_query()
    test_metadata()
    test_write_and_load()
    test_load_missing_file()
    test_sort_determinism()
    test_caps_format()
    io.println("All lockfile tests complete")
}
