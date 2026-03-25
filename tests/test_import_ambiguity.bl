fn run_cmd(cmd: Str, label: Str) -> Int {
    let rc = shell_exec(cmd)
    if rc != 0 {
        io.println("FAIL: {label} (rc={rc})")
    }
    rc
}

fn check_output(path: Str, expected: Str, label: Str) {
    shell_exec("{path} > {path}_out.txt 2>&1 || true")
    let output = read_file("{path}_out.txt")
    if output.starts_with(expected) {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected '{expected}', got: {output}")
    }
}

fn main() {
    let base = ".tmp/_test_import_ambiguity"
    shell_exec("rm -rf {base}")
    let pact = "../../../bin/pact"

    // Create two libs with same pub fn name
    shell_exec("mkdir -p {base}/libA/src")
    write_file("{base}/libA/pact.toml", "[package]\nname = \"libA\"\nversion = \"0.1.0\"\n")
    write_file("{base}/libA/src/lib.pact", "pub fn process(x: Int) -> Int \{\n    x + 1\n}\n\npub fn only_a() -> Int \{\n    42\n}\n")

    shell_exec("mkdir -p {base}/libB/src")
    write_file("{base}/libB/pact.toml", "[package]\nname = \"libB\"\nversion = \"0.1.0\"\n")
    write_file("{base}/libB/src/lib.pact", "pub fn process(x: Int) -> Int \{\n    x * 2\n}\n\npub fn only_b() -> Int \{\n    99\n}\n")

    shell_exec("mkdir -p {base}/app/src")
    write_file(
        "{base}/app/pact.toml",
        "[package]\nname = \"app\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibA = \{ path = \"../libA\" }\nlibB = \{ path = \"../libB\" }\n"
    )

    // Test 1: Two imports with same name — E1005 error
    write_file(
        "{base}/app/src/t1.pact",
        "import libA\nimport libB\n\nfn main() \{\n    io.println(\"\{process(5)\}\")\n}\n"
    )
    shell_exec("mkdir -p {base}/app/build")
    let rc1 = shell_exec("cd {base}/app && {pact} build src/t1.pact -o build/t1 > ../err1.txt 2>&1")
    if rc1 == 0 {
        io.println("FAIL: ambiguous import should produce error")
    } else {
        let err = read_file("{base}/err1.txt")
        if err.contains("ambiguous") || err.contains("E1005") {
            io.println("PASS: ambiguous import detected")
        } else {
            io.println("FAIL: expected ambiguity error, got: {err}")
        }
    }

    // Test 2: Selective imports on both sides resolves ambiguity
    write_file(
        "{base}/app/src/t2.pact",
        "import libA.\{process\}\nimport libB.\{only_b\}\n\nfn main() \{\n    io.println(\"\{process(5)\}\")\n    io.println(\"\{only_b()\}\")\n}\n"
    )
    let rc2 = run_cmd("cd {base}/app && {pact} build src/t2.pact -o build/t2 2>&1", "build selective disambiguate")
    if rc2 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t2", "6", "selective import disambiguates")

    // Test 3: Non-overlapping names from two modules — no ambiguity
    write_file(
        "{base}/app/src/t3.pact",
        "import libA.\{only_a\}\nimport libB.\{only_b\}\n\nfn main() \{\n    io.println(\"\{only_a() + only_b()\}\")\n}\n"
    )
    let rc3 = run_cmd("cd {base}/app && {pact} build src/t3.pact -o build/t3 2>&1", "build non-overlapping selective")
    if rc3 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t3", "141", "non-overlapping selective imports")

    // Test 4: Unique names from different modules via selective — no error
    write_file(
        "{base}/app/src/t4.pact",
        "import libA.\{only_a\}\nimport libB.\{only_b\}\n\nfn main() \{\n    io.println(\"\{only_a()\}\")\n    io.println(\"\{only_b()\}\")\n}\n"
    )
    let rc4 = run_cmd("cd {base}/app && {pact} build src/t4.pact -o build/t4 2>&1", "build unique names")
    if rc4 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t4", "42", "unique names from different modules")

    shell_exec("rm -rf {base}")
}
