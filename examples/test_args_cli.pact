import std.args

fn main() {
    let mut p = argparser_new("test", "Arg parser CLI test")
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "source", "Source file")
    p = add_command(p, "build", "Build the project")
    p = command_add_flag(p, "build", "--release", "-r", "Release mode")

    let a = argparse(p)
    let cmd = args_command(a)
    let verbose = args_has(a, "verbose")
    let output = args_get(a, "output")
    let pos = args_positional(a, 0)
    io.println("command={cmd}")
    io.println("verbose={verbose}")
    io.println("output={output}")
    io.println("positional={pos}")
}
