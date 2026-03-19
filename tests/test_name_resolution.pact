import compile_test_helpers

fn main() {
    let bad_source = "fn main() \{\n    let x = undefined_function(42)\n    io.println(unknown_var)\n}\n"
    let output = compile_test_helpers.compile_and_capture(bad_source, "_test_nr_bad")
    compile_test_helpers.expect_error(output, "UndefinedFunction", "UndefinedFunction diagnostic")
    compile_test_helpers.expect_error(output, "UndefinedVariable", "UndefinedVariable diagnostic")
    compile_test_helpers.expect_error(output, "E0504", "error code E0504")
    compile_test_helpers.expect_error(output, "E0506", "error code E0506")
}
