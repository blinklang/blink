// Test: pact build/run auto-resolves dependencies when pact.lock is missing or stale.
// Sets up a project with pact.toml + path dep, no lockfile, and verifies
// that bin/pact build auto-generates pact.lock and compiles successfully.

fn main() {
    let base = ".tmp/_test_auto_resolve"
    shell_exec("rm -rf {base}")
    shell_exec("mkdir -p {base}/src")
    shell_exec("mkdir -p {base}/deps/mylib/src")

    // Write the dependency source
    write_file("{base}/deps/mylib/src/lib.pact", "pub fn greet() -> Str \{\n    \"hello-auto\"\n\}\n")
    write_file("{base}/deps/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")

    // Write pact.toml with a path dependency — NO pact.lock
    write_file("{base}/pact.toml", "[package]\nname = \"testproj\"\nversion = \"0.1.0\"\n\n[dependencies]\nmylib = \{ path = \"deps/mylib\" \}\n")

    // Write main source that imports the dependency
    write_file("{base}/src/main.pact", "import mylib\n\nfn main() \{\n    io.println(greet())\n\}\n")

    // Verify no pact.lock exists yet
    if file_exists("{base}/pact.lock") == 1 {
        io.println("FAIL: pact.lock should not exist before build")
        shell_exec("rm -rf {base}")
        return
    }

    // Build using bin/pact — should auto-resolve deps
    let build_rc = shell_exec("cd {base} && ../../bin/pact build src/main.pact -o build/main > build_log.txt 2>&1")
    let build_log = read_file("{base}/build_log.txt")

    if build_rc != 0 {
        io.println("FAIL: build failed (rc={build_rc})")
        io.println(build_log)
        shell_exec("rm -rf {base}")
        return
    }

    // Verify pact.lock was auto-created
    if file_exists("{base}/pact.lock") == 1 {
        io.println("PASS: pact.lock auto-created by build")
    } else {
        io.println("FAIL: pact.lock was not created by build")
        shell_exec("rm -rf {base}")
        return
    }

    // Verify binary runs correctly
    shell_exec("{base}/build/main > {base}/run_output.txt 2>&1 || true")
    let output = read_file("{base}/run_output.txt")
    if output.starts_with("hello-auto") {
        io.println("PASS: binary output correct after auto-resolve")
    } else {
        io.println("FAIL: expected 'hello-auto', got: {output}")
    }

    // --- Test stale lockfile: touch pact.toml to make it newer ---
    shell_exec("sleep 1 && touch {base}/pact.toml")

    // Add a second dep to pact.toml
    shell_exec("mkdir -p {base}/deps/otherlib/src")
    write_file("{base}/deps/otherlib/src/lib.pact", "pub fn other() -> Str \{\n    \"other-auto\"\n\}\n")
    write_file("{base}/deps/otherlib/pact.toml", "[package]\nname = \"otherlib\"\nversion = \"0.1.0\"\n")
    write_file("{base}/pact.toml", "[package]\nname = \"testproj\"\nversion = \"0.1.0\"\n\n[dependencies]\nmylib = \{ path = \"deps/mylib\" \}\notherlib = \{ path = \"deps/otherlib\" \}\n")
    write_file("{base}/src/main2.pact", "import mylib\nimport otherlib\n\nfn main() \{\n    io.println(greet())\n    io.println(other())\n\}\n")

    let build2_rc = shell_exec("cd {base} && ../../bin/pact build src/main2.pact -o build/main2 > build_log2.txt 2>&1")
    let build2_log = read_file("{base}/build_log2.txt")

    if build2_rc != 0 {
        io.println("FAIL: stale lockfile rebuild failed (rc={build2_rc})")
        io.println(build2_log)
        shell_exec("rm -rf {base}")
        return
    }

    shell_exec("{base}/build/main2 > {base}/run_output2.txt 2>&1 || true")
    let output2 = read_file("{base}/run_output2.txt")
    if output2.starts_with("hello-auto") {
        io.println("PASS: stale lockfile re-resolved correctly")
    } else {
        io.println("FAIL: expected 'hello-auto', got: {output2}")
    }

    // Cleanup
    shell_exec("rm -rf {base}")
}
