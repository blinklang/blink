import std.args

test "help text contains flags and options" {
    let mut p = argparser_new("mytool", "A test tool")
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "source", "Source file")

    let help = generate_help(p)
    assert(help.contains("--verbose"))
    assert(help.contains("--output"))
    assert(help.contains("mytool"))
    assert(help.contains("A test tool"))
}

test "help text contains commands" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build the project")
    p = add_command(p, "test", "Run tests")
    p = add_flag(p, "--debug", "-d", "Debug mode")
    let help = generate_help(p)
    assert(help.contains("build"))
    assert(help.contains("test"))
}

test "Args struct accessors" {
    let a = Args {
        command_name: "build",
        command_path: ["build"],
        flag_names: ["verbose", "debug"],
        option_keys: ["output"],
        option_vals: ["foo.txt"],
        positional_vals: ["input.pact"],
        rest_args: [],
        error: ""
    }
    assert(args_has(a, "verbose"))
    assert(args_has(a, "debug"))
    assert(args_has(a, "nonexistent") == false)
    assert_eq(args_get(a, "output"), "foo.txt")
    assert_eq(args_get(a, "missing"), "")
    assert_eq(args_command(a), "build")
    assert_eq(args_positional(a, 0), "input.pact")
    assert_eq(args_positional(a, 5), "")
}

test "args_rest returns rest args" {
    let a = Args {
        command_name: "",
        command_path: [],
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: [],
        rest_args: ["foo", "bar", "--baz"],
        error: ""
    }
    let rest = args_rest(a)
    assert_eq(rest.len(), 3)
    assert_eq(rest.get(0).unwrap(), "foo")
    assert_eq(rest.get(1).unwrap(), "bar")
    assert_eq(rest.get(2).unwrap(), "--baz")
}

test "args_rest empty when no rest args" {
    let a = Args {
        command_name: "",
        command_path: [],
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: [],
        rest_args: [],
        error: ""
    }
    assert_eq(args_rest(a).len(), 0)
}

test "args_command_path accessor" {
    let a = Args {
        command_name: "daemon start",
        command_path: ["daemon", "start"],
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: [],
        rest_args: [],
        error: ""
    }
    let path = args_command_path(a)
    assert_eq(path.len(), 2)
    assert_eq(path.get(0).unwrap(), "daemon")
    assert_eq(path.get(1).unwrap(), "start")
    assert_eq(args_command(a), "daemon start")
}

test "nested command builder" {
    let mut p = argparser_new("pact", "Pact compiler")
    p = add_command(p, "build", "Build project")
    p = add_command(p, "daemon.start", "Start daemon")
    p = add_command(p, "daemon.stop", "Stop daemon")
    p = add_command(p, "daemon.status", "Daemon status")
    let help = generate_help(p)
    assert(help.contains("daemon"))
    assert(help.contains("start"))
    assert(help.contains("stop"))
    assert(help.contains("build"))
}

test "command_add_flag with dotted path" {
    let mut p = argparser_new("pact", "Pact compiler")
    p = add_command(p, "daemon.start", "Start daemon")
    p = command_add_flag(p, "daemon.start", "--background", "-b", "Run in background")
    let help = generate_command_help(p, "daemon start")
    assert(help.contains("--background"))
}

test "command_add_positional" {
    let mut p = argparser_new("pact", "Pact compiler")
    p = add_command(p, "daemon.start", "Start daemon")
    p = command_add_positional(p, "daemon.start", "file", "Source file")
    let help = generate_command_help(p, "daemon start")
    assert(help.contains("<file>"))
}
