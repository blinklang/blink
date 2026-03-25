// E2E test: two packages (A depends on B via path dep), verify compile + run works.
// Also tests transitive deps (A → B → C) and selective imports.

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

fn main() {
    let base = ".tmp/_test_e2e_pathdep"
    shell_exec("rm -rf {base}")

    // --- Test 1: A depends on B, B exports a function A calls ---
    shell_exec("mkdir -p {base}/projA/src")
    shell_exec("mkdir -p {base}/libB/src")

    write_file("{base}/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.2.0\"\n")
    write_file("{base}/libB/src/lib.pact", "pub fn add(a: Int, b: Int) -> Int \{\n    a + b\n\}\n\npub fn greeting() -> Str \{\n    \"hello from B\"\n\}\n")

    write_file("{base}/projA/pact.toml", "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ path = \"../libB\" \}\n")
    write_file("{base}/projA/src/main.pact", "import libB\n\nfn main() \{\n    io.println(greeting())\n    let sum = add(2, 3)\n    io.println(\"\{sum\}\")\n\}\n")

    let pact = "../../../bin/pact"
    let rc1 = run_cmd("cd {base}/projA && {pact} build src/main.pact -o build/app 2>&1", "build A→B")
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    let out1 = check_output("{base}/projA/build/app", "hello from B", "A calls B.greeting()")

    if out1.contains("5") {
        io.println("PASS: A calls B.add(2,3) = 5")
    } else {
        io.println("FAIL: expected '5' in output, got: {out1}")
    }

    // --- Test 2: Selective import — import libB.{add} ---
    write_file("{base}/projA/src/selective.pact", "import libB.\{add\}\n\nfn main() \{\n    let r = add(10, 20)\n    io.println(\"\{r\}\")\n\}\n")

    let rc2 = run_cmd("cd {base}/projA && {pact} build src/selective.pact -o build/selective 2>&1", "build selective import")
    if rc2 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/projA/build/selective", "30", "selective import libB.\{add\}")

    // --- Test 3: Transitive deps — A → B → C ---
    shell_exec("mkdir -p {base}/libC/src")

    write_file("{base}/libC/pact.toml", "[package]\nname = \"libC\"\nversion = \"0.1.0\"\n")
    write_file("{base}/libC/src/lib.pact", "pub fn base_value() -> Int \{\n    42\n\}\n")

    // B now depends on C
    write_file("{base}/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.2.0\"\n\n[dependencies]\nlibC = \{ path = \"../libC\" \}\n")
    write_file("{base}/libB/src/lib.pact", "import libC\n\npub fn add(a: Int, b: Int) -> Int \{\n    a + b\n\}\n\npub fn greeting() -> Str \{\n    \"hello from B\"\n\}\n\npub fn combined() -> Int \{\n    add(base_value(), 8)\n\}\n")

    // A imports both B and C
    write_file("{base}/projA/src/transitive.pact", "import libB\nimport libC\n\nfn main() \{\n    let c = combined()\n    let b = base_value()\n    io.println(\"\{c\}\")\n    io.println(\"\{b\}\")\n\}\n")

    // Remove stale lockfile so it re-resolves
    shell_exec("rm -f {base}/projA/pact.lock")
    // Update A's manifest to also declare C (or rely on transitive resolution)
    write_file("{base}/projA/pact.toml", "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ path = \"../libB\" \}\nlibC = \{ path = \"../libC\" \}\n")

    let rc3 = run_cmd("cd {base}/projA && {pact} build src/transitive.pact -o build/transitive 2>&1", "build A→B→C transitive")
    if rc3 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    let out3 = check_output("{base}/projA/build/transitive", "50", "transitive: combined() = add(42, 8) = 50")

    if out3.contains("42") {
        io.println("PASS: transitive: A calls C.base_value() = 42 directly")
    } else {
        io.println("FAIL: expected '42' in output, got: {out3}")
    }

    // --- Test 4: pact run (compile+execute in one step) ---
    shell_exec("rm -f {base}/projA/pact.lock")
    write_file("{base}/projA/pact.toml", "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibB = \{ path = \"../libB\" \}\n")
    write_file("{base}/projA/src/runme.pact", "import libB\n\nfn main() \{\n    let r = add(100, 23)\n    io.println(\"\{r\}\")\n\}\n")

    shell_exec("cd {base}/projA && {pact} run src/runme.pact > run_output.txt 2>&1 || true")
    let run_out = read_file("{base}/projA/run_output.txt")
    if run_out.contains("123") {
        io.println("PASS: pact run with path dep produces correct output")
    } else {
        io.println("FAIL: pact run — expected '123' in output, got: {run_out}")
    }

    shell_exec("rm -rf {base}")
}
