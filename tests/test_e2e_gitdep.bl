// E2E test: git dependencies — clone, build, lockfile, pact run, tag update.
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
    let base = ".tmp/_test_e2e_gitdep"
    shell_exec("rm -rf {base}")
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
    // Get absolute path for file:// URLs
    shell_exec("mkdir -p {base}")
    shell_exec("realpath {base} > {base}/_abs")
    let abs = trim(read_file("{base}/_abs"))
    let git_cfg = "-c user.email='t@t' -c user.name='t'"
    // --- Setup: create libB as a git repo with tag v1.0 ---
    shell_exec("mkdir -p {base}/repos/libB/src")
    write_file("{base}/repos/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"1.0.0\"\n")
    write_file("{base}/repos/libB/src/lib.pact", "pub fn greet() -> Str \{\n    \"hello-git\"\n}\n")
    shell_exec(
        "cd {base}/repos/libB && git init -q && git add -A && git {git_cfg} commit -q -m 'init' && git tag v1.0"
    )
    // --- Test 1: Basic git dep build ---
    shell_exec("mkdir -p {base}/projA/src")
    write_file(
        "{base}/projA/pact.toml",
        "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ git = \"file://{abs}/repos/libB\", tag = \"v1.0\" }\n"
    )
    write_file(
        "{base}/projA/src/main.pact",
        "import libB\n\nfn main() \{\n    io.println(greet())\n}\n"
    )
    let pact = "../../../bin/pact"
    let rc1 = run_cmd(
        "cd {base}/projA && {pact} build src/main.pact -o build/app 2>&1",
        "build projA with git dep"
    )
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
        return
    }
    check_output("{base}/projA/build/app", "hello-git", "basic git dep output")
    if file_exists("{base}/projA/pact.lock") == 1 {
        // --- Test 2: Lockfile written ---
        io.println("PASS: lockfile written after git dep build")
    } else {
        io.println("FAIL: lockfile not found after git dep build")
    }
    // --- Test 3: pact run with git dep ---
    write_file(
        "{base}/projA/src/runme.pact",
        "import libB\n\nfn main() \{\n    io.println(greet())\n    io.println(\"run-ok\")\n}\n"
    )
    shell_exec("cd {base}/projA && {pact} run src/runme.pact > run_output.txt 2>&1 || true")
    let run_out = read_file("{base}/projA/run_output.txt")
    if run_out.contains("hello-git") && run_out.contains("run-ok") {
        io.println("PASS: pact run with git dep")
    } else {
        io.println("FAIL: pact run — expected 'hello-git' and 'run-ok', got: {run_out}")
    }
    // --- Test 4: Tag update (v1.0 → v2.0) ---
    write_file(
        "{base}/repos/libB/src/lib.pact",
        "pub fn greet() -> Str \{\n    \"hello-git-v2\"\n}\n"
    )
    shell_exec(
        "cd {base}/repos/libB && git add -A && git {git_cfg} commit -q -m 'v2' && git tag v2.0"
    )
    write_file(
        "{base}/projA/pact.toml",
        "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ git = \"file://{abs}/repos/libB\", tag = \"v2.0\" }\n"
    )
    shell_exec("rm -f {base}/projA/pact.lock")
    let rc4 = run_cmd(
        "cd {base}/projA && {pact} build src/main.pact -o build/app2 2>&1",
        "build projA with git dep v2.0"
    )
    if rc4 != 0 {
        shell_exec("rm -rf {base}")
        shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
        return
    }
    check_output("{base}/projA/build/app2", "hello-git-v2", "tag update v2.0 output")
    // --- Cleanup ---
    shell_exec("rm -rf {base}")
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_*")
}
