// End-to-end CLI workflow: pact init → create git lib → pact add --git → build → run
// Tests the full package management user journey through the CLI.

fn trim_newlines(s: Str) -> Str {
    let mut end = s.len()
    while end > 0 {
        let ch = s.char_at(end - 1)
        if ch == 10 || ch == 13 {
            end = end - 1
        } else {
            return s.substring(0, end)
        }
    }
    ""
}

fn main() {
    let base = ".tmp/_test_cli_pkg"
    shell_exec("rm -rf {base}")
    shell_exec("mkdir -p {base}")

    // Step 1: Create a git library
    shell_exec("mkdir -p {base}/mathlib/src")
    write_file("{base}/mathlib/pact.toml", "[package]\nname = \"mathlib\"\nversion = \"0.1.0\"\n\n[dependencies]\n")
    write_file("{base}/mathlib/src/lib.pact", "pub fn add(a: Int, b: Int) -> Int \{\n    a + b\n\}\n")
    shell_exec("cd {base}/mathlib && git init && git add -A && git commit -m 'init' > /dev/null 2>&1")
    shell_exec("cd {base}/mathlib && git tag v0.1.0")

    let abs_result = process_run("sh", ["-c", "cd {base}/mathlib && pwd -P"])
    let lib_path = trim_newlines(abs_result.out)
    let git_url = "file://{lib_path}"

    // Get absolute path to pact binary
    let pact_abs = process_run("sh", ["-c", "pwd -P"])
    let pact_root = trim_newlines(pact_abs.out)

    // Step 2: Create a consumer project using pact init
    // pact init creates files in CWD, so make a subdir first
    let proj = "{base}/myapp"
    shell_exec("mkdir -p {proj}")
    let init_result = process_run("sh", ["-c", "cd {proj} && {pact_root}/build/pact init myapp 2>&1"])
    if init_result.exit_code != 0 {
        io.println("FAIL: pact init failed: {init_result.out}")
        shell_exec("rm -rf {base}")
        return
    }
    io.println("PASS: pact init created project")

    if file_exists("{proj}/blink.toml") == 0 && file_exists("{proj}/pact.toml") == 0 {
        io.println("FAIL: blink init did not create blink.toml")
        shell_exec("rm -rf {base}")
        return
    }
    if file_exists("{proj}/src/main.pact") == 0 {
        io.println("FAIL: pact init did not create src/main.pact")
        shell_exec("rm -rf {base}")
        return
    }

    // Step 3: Add git dependency
    let add_result = process_run("sh", ["-c", "cd {proj} && {pact_root}/build/pact add mathlib --git {git_url} --tag v0.1.0 2>&1"])
    if add_result.out.starts_with("error") {
        io.println("FAIL: pact add failed: {add_result.out}")
        shell_exec("rm -rf {base}")
        return
    }
    io.println("PASS: pact add --git succeeded")

    if file_exists("{proj}/blink.lock") == 0 && file_exists("{proj}/pact.lock") == 0 {
        io.println("FAIL: blink add did not create lock file")
        shell_exec("rm -rf {base}")
        return
    }
    io.println("PASS: lock file created")

    // Step 4: Write main.pact that uses the dependency
    write_file("{proj}/src/main.pact", "import mathlib\n\nfn main() \{\n    if add(2, 3) == 5 \{\n        io.println(\"correct\")\n    \} else \{\n        io.println(\"wrong\")\n    \}\n\}\n")

    // Step 5: Build using pact build
    let build_result = process_run("sh", ["-c", "cd {proj} && {pact_root}/build/pact build src/main.pact 2>&1"])
    if build_result.exit_code != 0 {
        io.println("FAIL: pact build failed: {build_result.out}")
        shell_exec("rm -rf {base}")
        return
    }
    io.println("PASS: pact build succeeded")

    // Step 6: Run the built binary
    let run_result = process_run("sh", ["-c", "cd {proj} && ./build/main 2>&1"])
    let output = trim_newlines(run_result.out)
    if output == "correct" {
        io.println("PASS: built binary produced correct output")
    } else {
        io.println("FAIL: expected 'correct', got: '{output}'")
    }

    // Cleanup
    shell_exec("rm -rf {base}")
}
