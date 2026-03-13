// End-to-end test: verify compiler resolves imports via pact.lock
// Creates a mini project with a path dependency and lockfile,
// compiles a file that imports from the dependency, runs it.

fn main() {
    let base = ".tmp/_test_import_lockfile"
    shell_exec("rm -rf {base}")
    shell_exec("mkdir -p {base}/src")
    shell_exec("mkdir -p {base}/deps/mylib/src")

    // Write the dependency's lib.pact
    write_file("{base}/deps/mylib/src/lib.pact", "pub fn dep_hello() -> Str \{\n    \"hello-from-dep\"\n\}\n")

    // Write the lockfile pointing to the path dependency
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n\n[[package]]\nname = \"mylib\"\nversion = \"0.1.0\"\nsource = \"path:{base}/deps/mylib\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n")

    // Write the main source file that imports from the dependency
    write_file("{base}/src/main.pact", "import mylib\n\nfn main() \{\n    io.println(dep_hello())\n\}\n")

    // Compile it
    shell_exec("build/pactc {base}/src/main.pact build/_test_import_lockfile.c > build/_test_il_compile.txt 2>&1 || true")

    // Check compilation succeeded (output C file should exist and be non-empty)
    let c_content = read_file("build/_test_import_lockfile.c")
    if c_content.len() > 0 {
        io.println("PASS: compilation produced C output")
    } else {
        io.println("FAIL: compilation produced no output")
        io.println(read_file("build/_test_il_compile.txt"))
        shell_exec("rm -rf {base} build/_test_import_lockfile.c build/_test_il_compile.txt")
        return
    }

    // Compile C to binary and run
    shell_exec("cc -o build/_test_import_lockfile build/_test_import_lockfile.c -lm 2>&1 || true")
    shell_exec("build/_test_import_lockfile > build/_test_il_output.txt 2>&1 || true")

    let output = read_file("build/_test_il_output.txt")
    if output.starts_with("hello-from-dep") {
        io.println("PASS: import via lockfile resolved correctly")
    } else {
        io.println("FAIL: expected 'hello-from-dep', got: {output}")
    }

    // Test submodule import: import mylib.utils → deps/mylib/src/utils.pact
    write_file("{base}/deps/mylib/src/utils.pact", "pub fn dep_util() -> Str \{\n    \"util-from-dep\"\n\}\n")
    write_file("{base}/src/main2.pact", "import mylib.utils\n\nfn main() \{\n    io.println(dep_util())\n\}\n")

    shell_exec("build/pactc {base}/src/main2.pact build/_test_import_lockfile2.c > build/_test_il_compile2.txt 2>&1 || true")
    let c2 = read_file("build/_test_import_lockfile2.c")
    if c2.len() > 0 {
        io.println("PASS: submodule compilation produced C output")
    } else {
        io.println("FAIL: submodule compilation produced no output")
        io.println(read_file("build/_test_il_compile2.txt"))
        shell_exec("rm -rf {base} build/_test_import_lockfile* build/_test_il_*")
        return
    }

    shell_exec("cc -o build/_test_import_lockfile2 build/_test_import_lockfile2.c -lm 2>&1 || true")
    shell_exec("build/_test_import_lockfile2 > build/_test_il_output2.txt 2>&1 || true")

    let output2 = read_file("build/_test_il_output2.txt")
    if output2.starts_with("util-from-dep") {
        io.println("PASS: submodule import via lockfile resolved correctly")
    } else {
        io.println("FAIL: expected 'util-from-dep', got: {output2}")
    }

    // --- Test: Two-segment package name ---
    // Package named "std/http" in lockfile, import std.http → deps/stdhttp/src/lib.pact
    shell_exec("mkdir -p {base}/deps/stdhttp/src")
    write_file("{base}/deps/stdhttp/src/lib.pact", "pub fn http_get() -> Str \{\n    \"got-it\"\n\}\n")
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n\n[[package]]\nname = \"std/http\"\nversion = \"0.1.0\"\nsource = \"path:{base}/deps/stdhttp\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n")
    write_file("{base}/src/main_twoseg.pact", "import std.http\n\nfn main() \{\n    io.println(http_get())\n\}\n")

    shell_exec("build/pactc {base}/src/main_twoseg.pact build/_test_il_twoseg.c > build/_test_il_twoseg_log.txt 2>&1 || true")
    let c_twoseg = read_file("build/_test_il_twoseg.c")
    if c_twoseg.len() > 0 {
        io.println("PASS: two-segment package compilation produced C output")
    } else {
        io.println("FAIL: two-segment package compilation produced no output")
        io.println(read_file("build/_test_il_twoseg_log.txt"))
    }

    if c_twoseg.len() > 0 {
        shell_exec("cc -o build/_test_il_twoseg build/_test_il_twoseg.c -lm 2>&1 || true")
        shell_exec("build/_test_il_twoseg > build/_test_il_twoseg_out.txt 2>&1 || true")
        let out_twoseg = read_file("build/_test_il_twoseg_out.txt")
        if out_twoseg.starts_with("got-it") {
            io.println("PASS: two-segment package import resolved correctly")
        } else {
            io.println("FAIL: expected 'got-it', got: {out_twoseg}")
        }
    }

    // --- Test: Local shadows dependency ---
    // Both local src/mylib.pact AND lockfile dep "mylib" exist → local wins
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n\n[[package]]\nname = \"mylib\"\nversion = \"0.1.0\"\nsource = \"path:{base}/deps/mylib\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n")
    write_file("{base}/src/mylib.pact", "pub fn dep_hello() -> Str \{\n    \"hello-from-local\"\n\}\n")
    write_file("{base}/src/main_shadow.pact", "import mylib\n\nfn main() \{\n    io.println(dep_hello())\n\}\n")

    shell_exec("build/pactc {base}/src/main_shadow.pact build/_test_il_shadow.c > build/_test_il_shadow_log.txt 2>&1 || true")
    let c_shadow = read_file("build/_test_il_shadow.c")
    if c_shadow.len() > 0 {
        io.println("PASS: local-shadows-dep compilation produced C output")
    } else {
        io.println("FAIL: local-shadows-dep compilation produced no output")
        io.println(read_file("build/_test_il_shadow_log.txt"))
    }

    if c_shadow.len() > 0 {
        shell_exec("cc -o build/_test_il_shadow build/_test_il_shadow.c -lm 2>&1 || true")
        shell_exec("build/_test_il_shadow > build/_test_il_shadow_out.txt 2>&1 || true")
        let out_shadow = read_file("build/_test_il_shadow_out.txt")
        if out_shadow.starts_with("hello-from-local") {
            io.println("PASS: local module correctly shadows lockfile dependency")
        } else {
            io.println("FAIL: expected 'hello-from-local', got: {out_shadow}")
        }
    }

    // Remove local shadow file so it doesn't interfere with later tests
    shell_exec("rm -f {base}/src/mylib.pact")

    // --- Test: Transitive import ---
    // Main imports liba, liba imports libb. Both in lockfile.
    shell_exec("mkdir -p {base}/deps/liba/src")
    shell_exec("mkdir -p {base}/deps/libb/src")
    write_file("{base}/deps/libb/src/lib.pact", "pub fn libb_value() -> Str \{\n    \"from-libb\"\n\}\n")
    write_file("{base}/deps/liba/src/lib.pact", "import libb\n\npub fn liba_value() -> Str \{\n    libb_value()\n\}\n")
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n\n[[package]]\nname = \"liba\"\nversion = \"0.1.0\"\nsource = \"path:{base}/deps/liba\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n\n[[package]]\nname = \"libb\"\nversion = \"0.1.0\"\nsource = \"path:{base}/deps/libb\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n")
    write_file("{base}/src/main_trans.pact", "import liba\n\nfn main() \{\n    io.println(liba_value())\n\}\n")

    shell_exec("build/pactc {base}/src/main_trans.pact build/_test_il_trans.c > build/_test_il_trans_log.txt 2>&1 || true")
    let c_trans = read_file("build/_test_il_trans.c")
    if c_trans.len() > 0 {
        io.println("PASS: transitive import compilation produced C output")
    } else {
        io.println("FAIL: transitive import compilation produced no output")
        io.println(read_file("build/_test_il_trans_log.txt"))
    }

    if c_trans.len() > 0 {
        shell_exec("cc -o build/_test_il_trans build/_test_il_trans.c -lm 2>&1 || true")
        shell_exec("build/_test_il_trans > build/_test_il_trans_out.txt 2>&1 || true")
        let out_trans = read_file("build/_test_il_trans_out.txt")
        if out_trans.starts_with("from-libb") {
            io.println("PASS: transitive import via lockfile resolved correctly")
        } else {
            io.println("FAIL: expected 'from-libb', got: {out_trans}")
        }
    }

    // --- Test: Missing lockfile dep ---
    // Import references a module not in lockfile and not local → should fail
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n")
    write_file("{base}/src/main_missing.pact", "import nonexistent\n\nfn main() \{\n    io.println(\"should not reach\")\n\}\n")

    shell_exec("rm -f build/_test_il_missing.c")
    shell_exec("build/pactc {base}/src/main_missing.pact build/_test_il_missing.c > build/_test_il_missing_log.txt 2>&1 || true")
    shell_exec("test -f build/_test_il_missing.c && echo EXISTS || echo MISSING > build/_test_il_missing_check.txt")
    let missing_check = read_file("build/_test_il_missing_check.txt")
    if missing_check.starts_with("MISSING") {
        io.println("PASS: missing dep correctly failed compilation (no C output)")
    } else {
        io.println("FAIL: missing dep should not have produced C output")
    }

    // Cleanup
    shell_exec("rm -rf {base} build/_test_import_lockfile* build/_test_il_*")
}
