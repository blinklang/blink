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
    let base = ".tmp/_test_qualified_import"
    shell_exec("rm -rf {base}")
    let pact = "../../../bin/pact"

    shell_exec("mkdir -p {base}/mylib/src")
    write_file("{base}/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")
    write_file(
        "{base}/mylib/src/lib.pact",
        "pub fn add(a: Int, b: Int) -> Int \{\n    a + b\n}\n\npub fn multiply(a: Int, b: Int) -> Int \{\n    a * b\n}\n\npub fn subtract(a: Int, b: Int) -> Int \{\n    a - b\n}\n\nfn internal_helper() -> Int \{\n    999\n}\n"
    )

    shell_exec("mkdir -p {base}/app/src")
    write_file(
        "{base}/app/pact.toml",
        "[package]\nname = \"app\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"../mylib\" }\n"
    )

    // Test 1: Basic qualified access — mylib.add(2, 3)
    write_file(
        "{base}/app/src/t1.pact",
        "import mylib\n\nfn main() \{\n    io.println(\"\{mylib.add(2, 3)\}\")\n}\n"
    )
    let rc1 = run_cmd("cd {base}/app && {pact} build src/t1.pact -o build/t1 2>&1", "build qualified add")
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t1", "5", "qualified access: mylib.add works")

    // Test 2: Mixed usage — qualified + unqualified in same file
    write_file(
        "{base}/app/src/t2.pact",
        "import mylib\n\nfn main() \{\n    io.println(\"\{mylib.add(2, 3)\}\")\n    io.println(\"\{multiply(4, 5)\}\")\n}\n"
    )
    let rc2 = run_cmd("cd {base}/app && {pact} build src/t2.pact -o build/t2 2>&1", "build mixed usage")
    if rc2 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t2", "5", "mixed: qualified + unqualified")

    // Test 3: Qualified access marks module used (no W0602 unused import warning)
    write_file(
        "{base}/app/src/t3.pact",
        "import mylib\n\nfn main() \{\n    io.println(\"\{mylib.add(1, 2)\}\")\n}\n"
    )
    shell_exec("mkdir -p {base}/app/build")
    shell_exec("cd {base}/app && {pact} build src/t3.pact -o build/t3 > ../out3.txt 2>&1")
    let out3 = read_file("{base}/out3.txt")
    if out3.contains("not used") {
        io.println("FAIL: qualified access should mark module used, got: {out3}")
    } else {
        io.println("PASS: qualified access marks module used")
    }

    // Test 4: Selective + qualified — import mylib.{add} then mylib.multiply() should work
    write_file(
        "{base}/app/src/t4.pact",
        "import mylib.\{add\}\n\nfn main() \{\n    io.println(\"\{add(2, 3)\}\")\n    io.println(\"\{mylib.multiply(4, 5)\}\")\n}\n"
    )
    let rc4 = run_cmd("cd {base}/app && {pact} build src/t4.pact -o build/t4 2>&1", "build selective+qualified")
    if rc4 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t4", "5", "selective+qualified: add bare + mylib.multiply qualified")

    shell_exec("rm -rf {base}")
}
