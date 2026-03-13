// Negative test: verifies the compiler rejects undefined names
// Writes a bad .pact file, compiles it, checks for expected diagnostics

fn main() {
    let bad_source = "fn main() \{\n    let x = undefined_function(42)\n    io.println(unknown_var)\n\}\n"
    write_file("build/_test_nr_bad.pact", bad_source)

    // Compile bad file, capture all output
    shell_exec("build/pactc build/_test_nr_bad.pact /dev/null --format json > build/_test_nr_out.txt 2>&1 || true")

    // Check each expected diagnostic via shell grep
    shell_exec("grep -q UndefinedFunction build/_test_nr_out.txt && echo 'PASS: UndefinedFunction diagnostic' || echo 'FAIL: UndefinedFunction diagnostic'")
    shell_exec("grep -q UndefinedVariable build/_test_nr_out.txt && echo 'PASS: UndefinedVariable diagnostic' || echo 'FAIL: UndefinedVariable diagnostic'")
    shell_exec("grep -q E0504 build/_test_nr_out.txt && echo 'PASS: error code E0504' || echo 'FAIL: error code E0504'")
    shell_exec("grep -q E0506 build/_test_nr_out.txt && echo 'PASS: error code E0506' || echo 'FAIL: error code E0506'")

    shell_exec("rm -f build/_test_nr_bad.pact build/_test_nr_out.txt")
}
