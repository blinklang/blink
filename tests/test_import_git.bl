// End-to-end test: verify compiler resolves imports via git source in pact.lock
// Creates a local git repo, sets up the cache directory manually, writes a
// lockfile with a git: source, and verifies the compiler resolves imports.

import pkg.gitdeps

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
    let base = ".tmp/_test_import_git"
    shell_exec("rm -rf {base}")
    shell_exec("mkdir -p {base}/mylib/src")

    let home = get_env("HOME") ?? ""

    // Create the library source
    write_file("{base}/mylib/pact.toml", "[package]\nname = \"mylib\"\nversion = \"0.1.0\"\n")
    write_file("{base}/mylib/src/lib.pact", "pub fn git_hello() -> Str \{\n    \"hello-from-git\"\n\}\n")
    write_file("{base}/mylib/src/utils.pact", "pub fn git_util() -> Str \{\n    \"util-from-git\"\n\}\n")

    // Initialize git repo, commit, tag
    shell_exec("cd {base}/mylib && git init && git add -A && git commit -m 'init' > /dev/null 2>&1")
    shell_exec("cd {base}/mylib && git tag v0.1.0")

    // Get commit hash
    let commit_result = process_run("git", ["-C", "{base}/mylib", "rev-parse", "HEAD"])
    let commit = trim_newlines(commit_result.out)

    // Get absolute path to the repo for the git URL
    let pwd_result = process_run("sh", ["-c", "cd {base}/mylib && pwd -P"])
    let repo_path = trim_newlines(pwd_result.out)

    let git_url = "file://{repo_path}"
    let sanitized = sanitize_url(git_url)

    // Set up the cache directory with the library source
    let cache_dir = "{home}/.blink/cache/git/{sanitized}/{commit}"
    shell_exec("mkdir -p {cache_dir}/src")
    shell_exec("cp {base}/mylib/src/lib.pact {cache_dir}/src/lib.pact")
    shell_exec("cp {base}/mylib/src/utils.pact {cache_dir}/src/utils.pact")

    // Create the project that imports mylib
    shell_exec("mkdir -p {base}/src")
    write_file("{base}/pact.lock", "[metadata]\nlockfile-version = 1\npact-version = \"dev\"\ngenerated = \"2026-01-01T00:00:00Z\"\n\n[[package]]\nname = \"mylib\"\nversion = \"0.1.0\"\nsource = \"git:{git_url}#{commit}\"\nhash = \"0000000000000000000000000000000000000000000000000000000000000000\"\ncapabilities = []\n")

    write_file("{base}/src/main.pact", "import mylib\n\nfn main() \{\n    io.println(git_hello())\n\}\n")

    // --- Test 1: Basic git dep ---
    shell_exec("build/pactc {base}/src/main.pact build/_test_ig_main.c > build/_test_ig_compile.txt 2>&1 || true")
    let c_content = read_file("build/_test_ig_main.c")
    if c_content.len() > 0 {
        io.println("PASS: git dep compilation produced C output")
    } else {
        io.println("FAIL: git dep compilation produced no output")
        io.println(read_file("build/_test_ig_compile.txt"))
        shell_exec("rm -rf {base} {cache_dir} build/_test_ig_* .tmp/_test_ig_*")
        return
    }

    shell_exec("cc -o build/_test_ig_main build/_test_ig_main.c -lm -lgc 2>&1 || true")
    shell_exec("build/_test_ig_main > build/_test_ig_output.txt 2>&1 || true")
    let output = read_file("build/_test_ig_output.txt")
    if output.starts_with("hello-from-git") {
        io.println("PASS: import via git lockfile resolved correctly")
    } else {
        io.println("FAIL: expected 'hello-from-git', got: {output}")
    }

    // --- Test 2: Git dep submodule ---
    write_file("{base}/src/main2.pact", "import mylib.utils\n\nfn main() \{\n    io.println(git_util())\n\}\n")

    shell_exec("build/pactc {base}/src/main2.pact build/_test_ig_main2.c > build/_test_ig_compile2.txt 2>&1 || true")
    let c2 = read_file("build/_test_ig_main2.c")
    if c2.len() > 0 {
        io.println("PASS: git dep submodule compilation produced C output")
    } else {
        io.println("FAIL: git dep submodule compilation produced no output")
        io.println(read_file("build/_test_ig_compile2.txt"))
        shell_exec("rm -rf {base} {cache_dir} build/_test_ig_* .tmp/_test_ig_*")
        return
    }

    shell_exec("cc -o build/_test_ig_main2 build/_test_ig_main2.c -lm -lgc 2>&1 || true")
    shell_exec("build/_test_ig_main2 > build/_test_ig_output2.txt 2>&1 || true")
    let output2 = read_file("build/_test_ig_output2.txt")
    if output2.starts_with("util-from-git") {
        io.println("PASS: git dep submodule import resolved correctly")
    } else {
        io.println("FAIL: expected 'util-from-git', got: {output2}")
    }

    // Cleanup
    shell_exec("rm -rf {base} {cache_dir} build/_test_ig_* .tmp/_test_ig_*")
}
