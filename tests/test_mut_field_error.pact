test "mut on struct field emits E1109" {
    let src = "type Foo \{ mut x: Bool \}\nfn main() \{ \}\n"
    write_file(".tmp/_test_mut_field.pact", src)
    let args = [".tmp/_test_mut_field.pact", "/dev/null", "--format", "json"]
    let result = process_run("build/pactc", args)
    let output = "{result.out}{result.err_out}"
    assert(output.contains("E1109"))
    assert(output.contains("MutFieldNotSupported"))
    shell_exec("rm -f .tmp/_test_mut_field.pact")
}

test "mut on enum variant field emits E1109" {
    let src = "type Shape \{ Circle(mut r: Float) \}\nfn main() \{ \}\n"
    write_file(".tmp/_test_mut_vfield.pact", src)
    let args = [".tmp/_test_mut_vfield.pact", "/dev/null", "--format", "json"]
    let result = process_run("build/pactc", args)
    let output = "{result.out}{result.err_out}"
    assert(output.contains("E1109"))
    assert(output.contains("MutFieldNotSupported"))
    shell_exec("rm -f .tmp/_test_mut_vfield.pact")
}
