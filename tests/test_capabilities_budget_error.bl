test "budget violation emits E0501" {
    let src = "@capabilities(IO)\n\nfn violates_budget() ! FS.Read \{\n    let _x = 1\n\}\n\nfn main() \{\n    violates_budget()\n\}\n"
    write_file(".tmp/_test_cap_budget.pact", src)
    let args = [".tmp/_test_cap_budget.pact", "/dev/null", "--format", "json"]
    let result = process_run("build/pactc", args)
    let output = "{result.out}{result.err_out}"
    assert(output.contains("E0501"))
    assert(output.contains("CapabilityBudgetExceeded"))
    assert(output.contains("FS.Read"))
    shell_exec("rm -f .tmp/_test_cap_budget.pact")
}

test "budget allows declared effects" {
    let src = "@capabilities(IO, FS.Read)\n\nfn uses_io() ! IO \{\n    let _x = 1\n\}\n\nfn uses_fs() ! FS.Read \{\n    let _x = 1\n\}\n\nfn main() \{\n    uses_io()\n    uses_fs()\n\}\n"
    write_file(".tmp/_test_cap_ok.pact", src)
    let args = [".tmp/_test_cap_ok.pact", "/dev/null", "--format", "json"]
    let result = process_run("build/pactc", args)
    let output = "{result.out}{result.err_out}"
    assert(!output.contains("E0501"))
    shell_exec("rm -f .tmp/_test_cap_ok.pact")
}

test "parent effect covers child" {
    let src = "@capabilities(IO)\n\nfn uses_child() ! IO.Print \{\n    let _x = 1\n\}\n\nfn main() \{\n    uses_child()\n\}\n"
    write_file(".tmp/_test_cap_parent.pact", src)
    let args = [".tmp/_test_cap_parent.pact", "/dev/null", "--format", "json"]
    let result = process_run("build/pactc", args)
    let output = "{result.out}{result.err_out}"
    assert(!output.contains("E0501"))
    shell_exec("rm -f .tmp/_test_cap_parent.pact")
}
