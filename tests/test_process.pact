fn main() {
    let result = process_run("echo", ["hello world"])
    io.println("exit: {result.exit_code}")
    io.println("has output: {result.out.len() > 0}")

    let result2 = process_run("printf", ["no newline"])
    io.println("printf: {result2.out}")

    let result3 = process_run("false", [])
    io.println("false exit: {result3.exit_code}")

    let result4 = process_run("sh", ["-c", "echo errtext >&2"])
    io.println("has stderr: {result4.err_out.len() > 0}")

    let result5 = process_run("nonexistent_command_xyz", [])
    io.println("not found exit: {result5.exit_code}")
}
