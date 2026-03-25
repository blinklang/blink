fn main() {
    let base = ".tmp/_test_cycle_detection"
    let pact = "../../../bin/pact"
    shell_exec("rm -rf {base}")

    // --- Test 1: Cross-package cycle should emit E1002 ---
    shell_exec("mkdir -p {base}/cross/src/alpha")
    shell_exec("mkdir -p {base}/cross/src/beta")
    write_file("{base}/cross/src/alpha/alpha.pact", "import beta.beta.\{get_beta}\n\npub fn get_alpha() -> Str \{\n    \"alpha\"\n}\n")
    write_file("{base}/cross/src/beta/beta.pact", "import alpha.alpha.\{get_alpha}\n\npub fn get_beta() -> Str \{\n    \"beta\"\n}\n")
    write_file("{base}/cross/src/main.pact", "import alpha.alpha.\{get_alpha}\n\nfn main() \{\n    io.println(get_alpha())\n}\n")

    let cross_out = process_run("sh", ["-c", "cd {base}/cross && {pact} build src/main.pact -o build/cross 2>&1"])
    let cross_combined = "{cross_out.out}{cross_out.err_out}"
    if cross_combined.contains("circular package dependency") {
        io.println("PASS: cross-package cycle detected (E1002)")
    } else {
        if cross_out.exit_code != 0 {
            io.println("FAIL: build failed but no cycle error: {cross_combined}")
        } else {
            io.println("FAIL: cross-package cycle was not detected (compiled successfully)")
        }
    }

    // --- Test 2: Intra-package cycle should compile fine ---
    shell_exec("mkdir -p {base}/intra/src/pkg")
    write_file("{base}/intra/src/pkg/a.pact", "import pkg.b.\{from_b}\n\npub fn from_a() -> Str \{\n    \"a\"\n}\n")
    write_file("{base}/intra/src/pkg/b.pact", "import pkg.a.\{from_a}\n\npub fn from_b() -> Str \{\n    \"b\"\n}\n")
    write_file("{base}/intra/src/main.pact", "import pkg.a.\{from_a}\n\nfn main() \{\n    io.println(from_a())\n}\n")

    let intra_rc = shell_exec("cd {base}/intra && {pact} build src/main.pact -o build/intra 2>&1")
    if intra_rc == 0 {
        let intra_out = process_run("{base}/intra/build/intra", [])
        if intra_out.out.starts_with("a") {
            io.println("PASS: intra-package cycle allowed")
        } else {
            io.println("FAIL: intra-package compiled but wrong output: {intra_out.out}")
        }
    } else {
        io.println("FAIL: intra-package cycle should compile but failed (rc={intra_rc})")
    }

    // --- Test 3: Three-package cycle A -> B -> C -> A ---
    shell_exec("mkdir -p {base}/tri/src/aa")
    shell_exec("mkdir -p {base}/tri/src/bb")
    shell_exec("mkdir -p {base}/tri/src/cc")
    write_file("{base}/tri/src/aa/aa.pact", "import cc.cc.\{get_cc}\n\npub fn get_aa() -> Str \{\n    \"aa\"\n}\n")
    write_file("{base}/tri/src/bb/bb.pact", "import aa.aa.\{get_aa}\n\npub fn get_bb() -> Str \{\n    \"bb\"\n}\n")
    write_file("{base}/tri/src/cc/cc.pact", "import bb.bb.\{get_bb}\n\npub fn get_cc() -> Str \{\n    \"cc\"\n}\n")
    write_file("{base}/tri/src/main.pact", "import aa.aa.\{get_aa}\n\nfn main() \{\n    io.println(get_aa())\n}\n")

    let tri_out = process_run("sh", ["-c", "cd {base}/tri && {pact} build src/main.pact -o build/tri 2>&1"])
    let tri_combined = "{tri_out.out}{tri_out.err_out}"
    if tri_combined.contains("circular package dependency") {
        io.println("PASS: three-package cycle detected (E1002)")
    } else {
        if tri_out.exit_code != 0 {
            io.println("FAIL: tri build failed but no cycle error: {tri_combined}")
        } else {
            io.println("FAIL: three-package cycle was not detected")
        }
    }

    // --- Test 4: Verify help text is included ---
    if cross_combined.contains("extract shared types into a common package") {
        io.println("PASS: help text present in error output")
    } else {
        io.println("FAIL: help text missing from error output")
    }

    // --- Test 5: Non-cyclic cross-package import should work ---
    shell_exec("mkdir -p {base}/nocycle/src/lib1")
    shell_exec("mkdir -p {base}/nocycle/src/lib2")
    write_file("{base}/nocycle/src/lib1/lib1.pact", "pub fn value1() -> Str \{\n    \"v1\"\n}\n")
    write_file("{base}/nocycle/src/lib2/lib2.pact", "import lib1.lib1.\{value1}\n\npub fn combined() -> Str \{\n    value1()\n}\n")
    write_file("{base}/nocycle/src/main.pact", "import lib2.lib2.\{combined}\n\nfn main() \{\n    io.println(combined())\n}\n")

    let nocycle_rc = shell_exec("cd {base}/nocycle && {pact} build src/main.pact -o build/nocycle 2>&1")
    if nocycle_rc == 0 {
        let nocycle_out = process_run("{base}/nocycle/build/nocycle", [])
        if nocycle_out.out.starts_with("v1") {
            io.println("PASS: non-cyclic cross-package import works")
        } else {
            io.println("FAIL: non-cyclic compiled but wrong output: {nocycle_out.out}")
        }
    } else {
        io.println("FAIL: non-cyclic cross-package should compile but failed (rc={nocycle_rc})")
    }

    shell_exec("rm -rf {base}")
}
