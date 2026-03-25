// E2E test: transitive dependencies — path chains, git chains, and diamond deps.
fn run_cmd(cmd: Str, label: Str) -> Int {
    let rc = shell_exec(cmd)
    if rc != 0 {
        io.println("FAIL: {label} (rc={rc})")
    }
    rc
}

fn check_output(path: Str, expected: Str, label: Str) -> Str {
    shell_exec("{path} > {path}_out.txt 2>&1 || true")
    let output = read_file("{path}_out.txt")
    if output.starts_with(expected) {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected '{expected}', got: {output}")
    }
    output
}

fn trim(s: Str) -> Str {
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

fn main() {
    let base = ".tmp/_test_e2e_transitive"
    shell_exec("rm -rf {base}")
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
    // ========================================================================
    // Test 1: Path chain A → B → C
    // ========================================================================
    shell_exec("mkdir -p {base}/libC/src")
    shell_exec("mkdir -p {base}/libB/src")
    shell_exec("mkdir -p {base}/projA/src")
    write_file("{base}/libC/pact.toml", "[package]\nname = \"libC\"\nversion = \"0.1.0\"\n")
    write_file("{base}/libC/src/lib.pact", "pub fn base_val() -> Int \{\n    42\n}\n")
    write_file(
        "{base}/libB/pact.toml",
        "[package]\nname = \"libB\"\nversion = \"0.1.0\"\n\n[dependencies]\nlibC = \{ path = \"../libC\" }\n"
    )
    write_file(
        "{base}/libB/src/lib.pact",
        "import libC\n\npub fn combined() -> Int \{\n    base_val() + 8\n}\n"
    )
    write_file(
        "{base}/projA/pact.toml",
        "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ path = \"../libB\" }\nlibC = \{ path = \"../libC\" }\n"
    )
    write_file(
        "{base}/projA/src/main.pact",
        "import libB\nimport libC\n\nfn main() \{\n    io.println(\"\{combined()}\")\n    io.println(\"\{base_val()}\")\n}\n"
    )
    let pact = "../../../bin/pact"
    let rc1 = run_cmd(
        "cd {base}/projA && {pact} build src/main.pact -o build/app 2>&1",
        "build path chain A→B→C"
    )
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/projA/build/app", "50\n42", "path chain: combined()=50, base_val()=42")
    // ========================================================================
    // Test 2: Git chain A → B(git) → C(git)
    // ========================================================================
    shell_exec("mkdir -p {base}/repos/libC/src")
    shell_exec("mkdir -p {base}/repos/libB/src")
    shell_exec("mkdir -p {base}/projGit/src")
    // Create libC git repo
    write_file("{base}/repos/libC/pact.toml", "[package]\nname = \"libC\"\nversion = \"1.0.0\"\n")
    write_file("{base}/repos/libC/src/lib.pact", "pub fn c_val() -> Str \{\n    \"from-c\"\n}\n")
    let rc2a = run_cmd(
        "cd {base}/repos/libC && git init && git add -A && git -c user.email='t@t' -c user.name='t' commit -m 'init' && git tag v1.0 2>&1",
        "git init libC"
    )
    if rc2a != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    // Get absolute path for file:// URLs
    shell_exec("realpath {base}/repos/libC > {base}/_abs_libC.txt")
    let abs_libC = trim(read_file("{base}/_abs_libC.txt"))
    shell_exec("realpath {base}/repos/libB > {base}/_abs_libB.txt")
    let abs_libB = trim(read_file("{base}/_abs_libB.txt"))
    // Create libB git repo (depends on libC via git)
    write_file(
        "{base}/repos/libB/pact.toml",
        "[package]\nname = \"libB\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibC = \{ git = \"file://{abs_libC}\", tag = \"v1.0\" }\n"
    )
    write_file(
        "{base}/repos/libB/src/lib.pact",
        "import libC\n\npub fn b_val() -> Str \{\n    c_val()\n}\n"
    )
    let rc2b = run_cmd(
        "cd {base}/repos/libB && git init && git add -A && git -c user.email='t@t' -c user.name='t' commit -m 'init' && git tag v1.0 2>&1",
        "git init libB"
    )
    if rc2b != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    // projGit depends on libB via git
    write_file(
        "{base}/projGit/pact.toml",
        "[package]\nname = \"projGit\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ git = \"file://{abs_libB}\", tag = \"v1.0\" }\n"
    )
    write_file(
        "{base}/projGit/src/main.pact",
        "import libB\n\nfn main() \{\n    io.println(b_val())\n}\n"
    )
    let rc2c = run_cmd(
        "cd {base}/projGit && {pact} build src/main.pact -o build/app 2>&1",
        "build git chain A→B(git)→C(git)"
    )
    if rc2c != 0 {
        shell_exec("rm -rf {base}")
        shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
        return
    }
    check_output(
        "{base}/projGit/build/app",
        "from-c",
        "git chain: b_val() returns c_val() = from-c"
    )
    // ========================================================================
    // Test 3: Diamond — A depends on B and C, B also depends on C
    // ========================================================================
    shell_exec("mkdir -p {base}/diamond/libC/src")
    shell_exec("mkdir -p {base}/diamond/libB/src")
    shell_exec("mkdir -p {base}/diamond/projA/src")
    write_file("{base}/diamond/libC/pact.toml", "[package]\nname = \"libC\"\nversion = \"0.1.0\"\n")
    write_file("{base}/diamond/libC/src/lib.pact", "pub fn base_val() -> Int \{\n    42\n}\n")
    write_file(
        "{base}/diamond/libB/pact.toml",
        "[package]\nname = \"libB\"\nversion = \"0.1.0\"\n\n[dependencies]\nlibC = \{ path = \"../libC\" }\n"
    )
    write_file(
        "{base}/diamond/libB/src/lib.pact",
        "import libC\n\npub fn combined() -> Int \{\n    base_val() + 8\n}\n"
    )
    // A depends on BOTH B and C directly — diamond pattern (B also depends on C)
    write_file(
        "{base}/diamond/projA/pact.toml",
        "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ path = \"../libB\" }\nlibC = \{ path = \"../libC\" }\n"
    )
    write_file(
        "{base}/diamond/projA/src/main.pact",
        "import libB\nimport libC\n\nfn main() \{\n    let c = combined()\n    let b = base_val()\n    io.println(\"\{c}\")\n    io.println(\"\{b}\")\n}\n"
    )
    let pact3 = "../../../../bin/pact"
    let rc3 = run_cmd(
        "cd {base}/diamond/projA && {pact3} build src/main.pact -o build/app 2>&1",
        "build diamond A→B+C, B→C"
    )
    if rc3 != 0 {
        shell_exec("rm -rf {base}")
        shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
        return
    }
    check_output(
        "{base}/diamond/projA/build/app",
        "50\n42",
        "diamond: combined()=50, base_val()=42 (no conflict)"
    )
    // Cleanup
    shell_exec("rm -rf {base}")
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
}
