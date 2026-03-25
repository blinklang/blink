// E2E test: pub/private visibility across packages — path deps and git deps.
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
    let base = ".tmp/_test_e2e_pub_visibility"
    shell_exec("rm -rf {base}")
    let pact = "../../../bin/pact"
    // --- Setup: create libV with pub and private items ---
    shell_exec("mkdir -p {base}/libV/src")
    write_file("{base}/libV/pact.toml", "[package]\nname = \"libV\"\nversion = \"0.1.0\"\n")
    write_file(
        "{base}/libV/src/lib.pact",
        "pub fn visible() -> Str \{\n    \"you can see me\"\n}\n\nfn hidden() -> Str \{\n    \"you cannot\"\n}\n\npub type Visible \{\n    x: Int\n}\n\ntype Hidden \{\n    y: Int\n}\n\npub trait PubCodec \{\n    fn encode(self) -> Str\n}\n\ntrait PrivCodec \{\n    fn decode(self) -> Str\n}\n"
    )
    shell_exec("mkdir -p {base}/projA/src")
    write_file(
        "{base}/projA/pact.toml",
        "[package]\nname = \"projA\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibV = \{ path = \"../libV\" }\n"
    )
    // --- Test 1: Pub function accessible (path dep) ---
    write_file(
        "{base}/projA/src/main.pact",
        "import libV\n\nfn main() \{\n    io.println(visible())\n}\n"
    )
    let rc1 = run_cmd(
        "cd {base}/projA && {pact} build src/main.pact -o build/app 2>&1",
        "build pub fn access"
    )
    if rc1 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/projA/build/app", "you can see me", "pub fn accessible via path dep")
    // --- Test 2: Private function rejected (path dep) ---
    write_file(
        "{base}/projA/src/bad_fn.pact",
        "import libV\n\nfn main() \{\n    io.println(hidden())\n}\n"
    )
    let rc2 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_fn.pact -o build/bad_fn > err_fn.txt 2>&1"
    )
    if rc2 != 0 {
        let err_fn = read_file("{base}/projA/err_fn.txt")
        if err_fn.contains("cannot access private") {
            io.println("PASS: private fn access correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_fn}")
        }
    } else {
        io.println("FAIL: build should have failed for private fn access")
    }
    // --- Test 3: Pub type accessible (path dep) ---
    write_file(
        "{base}/projA/src/pub_type.pact",
        "import libV\n\nfn main() \{\n    let v = Visible \{ x: 42 }\n    io.println(\"\{v.x}\")\n}\n"
    )
    let rc3 = run_cmd(
        "cd {base}/projA && {pact} build src/pub_type.pact -o build/pub_type 2>&1",
        "build pub type access"
    )
    if rc3 != 0 {
        shell_exec("rm -rf {base}")
        return
    }
    check_output("{base}/projA/build/pub_type", "42", "pub type accessible via path dep")
    // --- Test 4: Private type rejected (path dep) ---
    write_file(
        "{base}/projA/src/bad_type.pact",
        "import libV\n\nfn main() \{\n    let h = Hidden \{ y: 1 }\n    io.println(\"\{h.y}\")\n}\n"
    )
    let rc4 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_type.pact -o build/bad_type > err_type.txt 2>&1"
    )
    if rc4 != 0 {
        let err_type = read_file("{base}/projA/err_type.txt")
        if err_type.contains("cannot access private") {
            io.println("PASS: private type access correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_type}")
        }
    } else {
        io.println("FAIL: build should have failed for private type access")
    }
    // --- Test 5: Pub fn accessible via git dep ---
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_pub*")
    shell_exec("mkdir -p {base}")
    shell_exec("realpath {base} > {base}/_abs")
    let abs = trim(read_file("{base}/_abs"))
    let git_cfg = "-c user.email='t@t' -c user.name='t'"
    // Create libV as a git repo
    shell_exec("mkdir -p {base}/repos/libV/src")
    write_file("{base}/repos/libV/pact.toml", "[package]\nname = \"libV\"\nversion = \"1.0.0\"\n")
    write_file(
        "{base}/repos/libV/src/lib.pact",
        "pub fn visible() -> Str \{\n    \"git visible\"\n}\n\nfn hidden() -> Str \{\n    \"git hidden\"\n}\n"
    )
    shell_exec(
        "cd {base}/repos/libV && git init -q && git add -A && git {git_cfg} commit -q -m 'init' && git tag v1.0"
    )
    // Create projB that depends on libV via git
    shell_exec("mkdir -p {base}/projB/src")
    write_file(
        "{base}/projB/pact.toml",
        "[package]\nname = \"projB\"\nversion = \"1.0.0\"\n\n[dependencies]\nlibV = \{ git = \"file://{abs}/repos/libV\", tag = \"v1.0\" }\n"
    )
    write_file(
        "{base}/projB/src/main.pact",
        "import libV\n\nfn main() \{\n    io.println(visible())\n}\n"
    )
    let rc5 = run_cmd(
        "cd {base}/projB && {pact} build src/main.pact -o build/app 2>&1",
        "build pub fn via git dep"
    )
    if rc5 != 0 {
        shell_exec("rm -rf {base}")
        shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_pub*")
        return
    }
    check_output("{base}/projB/build/app", "git visible", "pub fn accessible via git dep")
    // --- Test 6: Private fn rejected via git dep ---
    write_file(
        "{base}/projB/src/bad.pact",
        "import libV\n\nfn main() \{\n    io.println(hidden())\n}\n"
    )
    let rc6 = shell_exec(
        "cd {base}/projB && {pact} build src/bad.pact -o build/bad > err_git.txt 2>&1"
    )
    if rc6 != 0 {
        let err_git = read_file("{base}/projB/err_git.txt")
        if err_git.contains("cannot access private") {
            io.println("PASS: private fn rejected via git dep")
        } else {
            io.println("FAIL: git dep build failed but wrong error: {err_git}")
        }
    } else {
        io.println("FAIL: git dep build should have failed for private fn access")
    }
    // --- Test 7: Private trait rejected in type annotation (path dep) ---
    write_file(
        "{base}/projA/src/bad_trait.pact",
        "import libV\n\nfn main() \{\n    let t: PrivCodec = 42\n    io.println(\"hi\")\n}\n"
    )
    let rc7 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_trait.pact -o build/bad_trait > err_trait.txt 2>&1"
    )
    if rc7 != 0 {
        let err_trait = read_file("{base}/projA/err_trait.txt")
        if err_trait.contains("cannot access private") {
            io.println("PASS: private trait access correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_trait}")
        }
    } else {
        io.println("FAIL: build should have failed for private trait access")
    }
    // --- Test 8: Private trait in generic type param rejected (let binding) ---
    write_file(
        "{base}/projA/src/bad_generic_trait.pact",
        "import libV\n\nfn main() \{\n    let x: List[PrivCodec] = []\n    io.println(\"hi\")\n}\n"
    )
    let rc8 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_generic_trait.pact -o build/bad_generic_trait > err_generic_trait.txt 2>&1"
    )
    if rc8 != 0 {
        let err_generic_trait = read_file("{base}/projA/err_generic_trait.txt")
        if err_generic_trait.contains("cannot access private") {
            io.println("PASS: private trait in generic param correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_generic_trait}")
        }
    } else {
        io.println("FAIL: build should have failed for private trait in generic param")
    }
    // --- Test 9: Private type in generic fn param rejected ---
    write_file(
        "{base}/projA/src/bad_generic_param.pact",
        "import libV\n\nfn use_priv(x: List[Hidden]) \{\n    io.println(\"hi\")\n}\n\nfn main() \{\n    use_priv([])\n}\n"
    )
    let rc9 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_generic_param.pact -o build/bad_generic_param > err_generic_param.txt 2>&1"
    )
    if rc9 != 0 {
        let err_generic_param = read_file("{base}/projA/err_generic_param.txt")
        if err_generic_param.contains("cannot access private") {
            io.println("PASS: private type in generic fn param correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_generic_param}")
        }
    } else {
        io.println("FAIL: build should have failed for private type in generic fn param")
    }
    // --- Test 10: Private type in generic return type rejected ---
    write_file(
        "{base}/projA/src/bad_generic_ret.pact",
        "import libV\n\nfn ret_priv() -> List[Hidden] \{\n    []\n}\n\nfn main() \{\n    let x = ret_priv()\n    io.println(\"hi\")\n}\n"
    )
    let rc10 = shell_exec(
        "cd {base}/projA && {pact} build src/bad_generic_ret.pact -o build/bad_generic_ret > err_generic_ret.txt 2>&1"
    )
    if rc10 != 0 {
        let err_generic_ret = read_file("{base}/projA/err_generic_ret.txt")
        if err_generic_ret.contains("cannot access private") {
            io.println("PASS: private type in generic return type correctly rejected")
        } else {
            io.println("FAIL: build failed but wrong error: {err_generic_ret}")
        }
    } else {
        io.println("FAIL: build should have failed for private type in generic return type")
    }
    // --- Cleanup ---
    shell_exec("rm -rf {base}")
    shell_exec("rm -rf ~/.blink/cache/git/*_test_e2e_pub*")
}
