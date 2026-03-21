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
    let base = ".tmp/_test_import_alias"
    shell_exec("rm -rf {base}")
    let pact = "../../../bin/pact"

    shell_exec("mkdir -p {base}/mylib/src")
    write_file("{base}/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")
    write_file(
        "{base}/mylib/src/lib.pact",
        "pub fn add(a: Int, b: Int) -> Int \{\n    a + b\n}\n\npub fn multiply(a: Int, b: Int) -> Int \{\n    a * b\n}\n"
    )

    shell_exec("mkdir -p {base}/app/src")
    write_file(
        "{base}/app/pact.toml",
        "[package]\nname = \"app\"\nversion = \"1.0.0\"\n\n[dependencies]\nmylib = \{ path = \"../mylib\" }\n"
    )

    // Test 1: Alias works — add imported as plus
    write_file(
        "{base}/app/src/t1.pact",
        "import mylib.\{add as plus\}\n\nfn main() \{\n    io.println(\"\{plus(2, 3)\}\")\n}\n"
    )
    let rc1 = run_cmd("cd {base}/app && {pact} build src/t1.pact -o build/t1 2>&1", "build alias")
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t1", "5", "alias: plus works")

    // Test 2: Original name rejected when aliased
    write_file(
        "{base}/app/src/t2.pact",
        "import mylib.\{add as plus\}\n\nfn main() \{\n    io.println(\"\{add(2, 3)\}\")\n}\n"
    )
    shell_exec("mkdir -p {base}/app/build")
    let rc2 = shell_exec("cd {base}/app && {pact} build src/t2.pact -o build/t2 > ../err2.txt 2>&1")
    if rc2 == 0 {
        io.println("FAIL: original name should be rejected when aliased")
    } else {
        let err = read_file("{base}/err2.txt")
        if err.contains("add") {
            io.println("PASS: original name rejected when aliased")
        } else {
            io.println("FAIL: expected error about add, got: {err}")
        }
    }

    // Test 3: Alias + selective — alias and non-aliased together
    write_file(
        "{base}/app/src/t3.pact",
        "import mylib.\{add as plus, multiply\}\n\nfn main() \{\n    io.println(\"\{plus(2, 3)\}\")\n    io.println(\"\{multiply(4, 5)\}\")\n}\n"
    )
    let rc3 = run_cmd("cd {base}/app && {pact} build src/t3.pact -o build/t3 2>&1", "build alias+selective")
    if rc3 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/app/build/t3", "5", "alias+selective: both work")

    shell_exec("rm -rf {base}")
}
