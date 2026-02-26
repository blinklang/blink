import std.audit
import std.lockfile

fn write_lockfile_content(path: Str, packages: Str) {
    let header = "[metadata]\nlockfile-version = 1\npact-version = \"0.1.0\"\ngenerated = \"2026-01-01T00:00:00Z\"\n"
    write_file(path, header.concat(packages))
}

fn check_int(actual: Int, expected: Int, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected {expected}, got {actual}")
    }
}

fn check_str(actual: Str, expected: Str, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected \"{expected}\", got \"{actual}\"")
    }
}

fn test_no_escalation() {
    audit_clear()
    lockfile_clear()

    let pkg = "\n[[package]]\nname = \"mylib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:abc\"\ncapabilities = [\"Net.Connect\"]\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", pkg)
    write_lockfile_content("/tmp/_pact_test_current.lock", pkg)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 0, "no escalation: count == 0")
}

fn test_new_capability() {
    audit_clear()
    lockfile_clear()

    let baseline_pkg = "\n[[package]]\nname = \"mylib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:abc\"\ncapabilities = [\"Net.Connect\"]\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkg)

    let current_pkg = "\n[[package]]\nname = \"mylib\"\nversion = \"1.1.0\"\nsource = \"registry\"\nhash = \"sha256:def\"\ncapabilities = [\"Net.Connect\", \"FS.Read\"]\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", current_pkg)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 1, "new cap: count == 1")
    check_str(escalation_types.unsafe_get(0), "escalation", "new cap: type is escalation")
    check_str(escalation_names.unsafe_get(0), "mylib", "new cap: name is mylib")
    check_str(escalation_new_caps.unsafe_get(0), "FS.Read", "new cap: new cap is FS.Read")
}

fn test_new_pkg_with_caps() {
    audit_clear()
    lockfile_clear()

    let baseline_pkg = "\n[[package]]\nname = \"oldlib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:aaa\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkg)

    let current_pkgs = "\n[[package]]\nname = \"newlib\"\nversion = \"0.1.0\"\nsource = \"registry\"\nhash = \"sha256:bbb\"\ncapabilities = [\"FS.Write\", \"Net.Connect\"]\n\n[[package]]\nname = \"oldlib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:aaa\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", current_pkgs)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 1, "new pkg with caps: count == 1")
    check_str(escalation_types.unsafe_get(0), "new_pkg", "new pkg with caps: type is new_pkg")
    check_str(escalation_names.unsafe_get(0), "newlib", "new pkg with caps: name is newlib")
}

fn test_new_pkg_without_caps() {
    audit_clear()
    lockfile_clear()

    let baseline_pkg = "\n[[package]]\nname = \"oldlib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:aaa\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkg)

    let current_pkgs = "\n[[package]]\nname = \"newlib\"\nversion = \"0.1.0\"\nsource = \"registry\"\nhash = \"sha256:bbb\"\ncapabilities = []\n\n[[package]]\nname = \"oldlib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:aaa\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", current_pkgs)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 0, "new pkg no caps: count == 0")
}

fn test_removed_package() {
    audit_clear()
    lockfile_clear()

    let baseline_pkgs = "\n[[package]]\nname = \"removed\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:rem\"\ncapabilities = [\"Net.Connect\"]\n\n[[package]]\nname = \"kept\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:kept\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkgs)

    let current_pkg = "\n[[package]]\nname = \"kept\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:kept\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", current_pkg)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 0, "removed pkg: count == 0")
}

fn test_clear_state() {
    audit_clear()
    lockfile_clear()

    let pkg = "\n[[package]]\nname = \"mylib\"\nversion = \"1.1.0\"\nsource = \"registry\"\nhash = \"sha256:def\"\ncapabilities = [\"Net.Connect\", \"FS.Read\"]\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", pkg)

    let baseline_pkg = "\n[[package]]\nname = \"mylib\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:abc\"\ncapabilities = [\"Net.Connect\"]\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkg)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")
    audit_check()
    check_int(escalation_names.len(), 1, "clear: has 1 escalation before clear")

    audit_clear()
    check_int(escalation_names.len(), 0, "clear: 0 escalations after clear")
    check_int(escalation_types.len(), 0, "clear: 0 types after clear")
}

fn test_multiple_escalations() {
    audit_clear()
    lockfile_clear()

    let baseline_pkgs = "\n[[package]]\nname = \"lib-a\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:a1\"\ncapabilities = [\"Net.Connect\"]\n\n[[package]]\nname = \"lib-b\"\nversion = \"1.0.0\"\nsource = \"registry\"\nhash = \"sha256:b1\"\ncapabilities = []\n"
    write_lockfile_content("/tmp/_pact_test_baseline.lock", baseline_pkgs)

    let current_pkgs = "\n[[package]]\nname = \"lib-a\"\nversion = \"1.1.0\"\nsource = \"registry\"\nhash = \"sha256:a2\"\ncapabilities = [\"Net.Connect\", \"FS.Read\"]\n\n[[package]]\nname = \"lib-b\"\nversion = \"1.1.0\"\nsource = \"registry\"\nhash = \"sha256:b2\"\ncapabilities = [\"IO.Log\"]\n"
    write_lockfile_content("/tmp/_pact_test_current.lock", current_pkgs)

    lockfile_load("/tmp/_pact_test_current.lock")
    audit_load_baseline("/tmp/_pact_test_baseline.lock")
    lockfile_load("/tmp/_pact_test_current.lock")

    let count = audit_check()
    check_int(count, 2, "multi: count == 2")
    check_str(escalation_types.unsafe_get(0), "escalation", "multi: first is escalation")
    check_str(escalation_types.unsafe_get(1), "escalation", "multi: second is escalation")
}

fn main() {
    test_no_escalation()
    test_new_capability()
    test_new_pkg_with_caps()
    test_new_pkg_without_caps()
    test_removed_package()
    test_clear_state()
    test_multiple_escalations()

    shell_exec("rm -f /tmp/_pact_test_baseline.lock /tmp/_pact_test_current.lock")
    io.println("All audit tests complete")
}
