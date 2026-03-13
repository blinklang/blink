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

test "args_get_all returns all repeated option values" {
    let a = Args {
        command_name: "",
        command_path: [],
        flag_names: [],
        option_keys: ["tag", "name", "tag", "tag"],
        option_vals: ["bug", "foo", "feature", "urgent"],
        positional_vals: [],
        rest_args: [],
        error: ""
    }
    let tags = args_get_all(a, "tag")
    assert_eq(tags.len(), 3)
    assert_eq(tags.get(0).unwrap(), "bug")
    assert_eq(tags.get(1).unwrap(), "feature")
    assert_eq(tags.get(2).unwrap(), "urgent")
}

test "args_get_all returns empty list if absent" {
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
    assert_eq(args_get_all(a, "missing").len(), 0)
}

test "args_positional_count" {
    let a = Args {
        command_name: "",
        command_path: [],
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: ["one", "two", "three"],
        rest_args: [],
        error: ""
    }
    assert_eq(args_positional_count(a), 3)
}

test "args_positional_count empty" {
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
    assert_eq(args_positional_count(a), 0)
}

test "parse_argv basic round-trip" {
    let mut p = argparser_new("myapp", "Test app")
    p = add_flag(p, "--verbose", "-v", "Verbose")
    p = add_option(p, "--output", "-o", "Output file")
    p = add_command(p, "build", "Build it")
    p = command_add_positional(p, "build", "file", "Source file")

    let args = parse_argv(p, ["myapp", "build", "--verbose", "-o", "out.txt", "main.pact"])
    assert_eq(args_command(args), "build")
    assert(args_has(args, "verbose"))
    assert_eq(args_get(args, "output"), "out.txt")
    assert_eq(args_positional(args, 0), "main.pact")
    assert_eq(args_error(args), "")
}

test "parse_argv unknown bare word errors when commands defined" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build it")
    p = add_command(p, "test", "Test it")

    let args = parse_argv(p, ["cli", "bild"])
    assert_eq(args_error(args), "unknown command 'bild'")
}

test "parse_argv bare word allowed when positional defs exist" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build it")
    p = add_positional(p, "file", "Source file")

    let args = parse_argv(p, ["cli", "somefile.pact"])
    assert_eq(args_error(args), "")
    assert_eq(args_positional(args, 0), "somefile.pact")
}

test "parse_argv unknown subcommand errors nested" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "daemon.start", "Start daemon")
    p = add_command(p, "daemon.stop", "Stop daemon")

    let args = parse_argv(p, ["cli", "daemon", "bild"])
    assert_eq(args_error(args), "unknown command 'bild'")
}

test "parse_argv command positional allows bare words" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "run", "Run it")
    p = command_add_positional(p, "run", "file", "Source")

    let args = parse_argv(p, ["cli", "run", "main.pact"])
    assert_eq(args_error(args), "")
    assert_eq(args_command(args), "run")
    assert_eq(args_positional(args, 0), "main.pact")
}

test "alias resolves to canonical name" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build it")
    p = add_command(p, "test", "Test it")
    p = add_command_alias(p, "b", "build")
    p = add_command_alias(p, "t", "test")

    let args = parse_argv(p, ["cli", "b"])
    assert_eq(args_command(args), "build")
    assert_eq(args_error(args), "")
}

test "original command still works alongside alias" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build it")
    p = add_command_alias(p, "b", "build")

    let args1 = parse_argv(p, ["cli", "build"])
    assert_eq(args_command(args1), "build")

    let args2 = parse_argv(p, ["cli", "b"])
    assert_eq(args_command(args2), "build")
}

test "alias shows in help text" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_command(p, "build", "Build it")
    p = add_command_alias(p, "b", "build")

    let help = generate_help(p)
    assert(help.contains("Aliases:"))
    assert(help.contains("b -> build"))
}

test "parse_argv handles rest args separator" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_flag(p, "--verbose", "-v", "Verbose")

    let args = parse_argv(p, ["cli", "--verbose", "--", "foo", "--bar"])
    assert(args_has(args, "verbose"))
    assert_eq(args_rest(args).len(), 2)
    assert_eq(args_rest(args).get(0).unwrap(), "foo")
    assert_eq(args_rest(args).get(1).unwrap(), "--bar")
}

test "parse_argv unknown option errors" {
    let p = argparser_new("cli", "CLI tool")
    let args = parse_argv(p, ["cli", "--badopt"])
    assert_eq(args_error(args), "unknown option '--badopt'")
}

test "parse_argv missing option value errors" {
    let mut p = argparser_new("cli", "CLI tool")
    p = add_option(p, "--output", "-o", "Output")
    let args = parse_argv(p, ["cli", "--output"])
    assert_eq(args_error(args), "option '--output' requires a value")
}

test "set_version stores version string" {
    let mut p = argparser_new("myapp", "My app")
    p = set_version(p, "1.2.3")
    let args = parse_argv(p, ["myapp", "--version"])
    assert_eq(args_error(args), "version")
}

test "short -V flag triggers version" {
    let mut p = argparser_new("myapp", "My app")
    p = set_version(p, "2.0.0")
    let args = parse_argv(p, ["myapp", "-V"])
    assert_eq(args_error(args), "version")
}

test "version without set_version still returns error signal" {
    let p = argparser_new("myapp", "My app")
    let args = parse_argv(p, ["myapp", "--version"])
    assert_eq(args_error(args), "version")
}
