import std.args

fn main() {
    let mut pass = true

    let mut p = argparser_new("mytool", "A test tool")
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "source", "Source file")

    let help = generate_help(p)
    if help.contains("--verbose") == false {
        io.println("FAIL: help missing --verbose")
        pass = false
    }
    if help.contains("--output") == false {
        io.println("FAIL: help missing --output")
        pass = false
    }
    if help.contains("mytool") == false {
        io.println("FAIL: help missing prog name")
        pass = false
    }
    if help.contains("A test tool") == false {
        io.println("FAIL: help missing description")
        pass = false
    }

    let mut p2 = argparser_new("cli", "CLI tool")
    p2 = add_command(p2, "build", "Build the project")
    p2 = add_command(p2, "test", "Run tests")
    p2 = add_flag(p2, "--debug", "-d", "Debug mode")
    let help2 = generate_help(p2)
    if help2.contains("build") == false {
        io.println("FAIL: help2 missing build command")
        pass = false
    }
    if help2.contains("test") == false {
        io.println("FAIL: help2 missing test command")
        pass = false
    }

    let a = Args {
        command_name: "build",
        flag_names: ["verbose", "debug"],
        option_keys: ["output"],
        option_vals: ["foo.txt"],
        positional_vals: ["input.pact"],
        error: ""
    }
    if args_has(a, "verbose") == false {
        io.println("FAIL: args_has verbose")
        pass = false
    }
    if args_has(a, "debug") == false {
        io.println("FAIL: args_has debug")
        pass = false
    }
    if args_has(a, "nonexistent") == true {
        io.println("FAIL: args_has nonexistent should be false")
        pass = false
    }
    if args_get(a, "output") != "foo.txt" {
        io.println("FAIL: args_get output")
        pass = false
    }
    if args_get(a, "missing") != "" {
        io.println("FAIL: args_get missing should be empty")
        pass = false
    }
    if args_command(a) != "build" {
        io.println("FAIL: args_command")
        pass = false
    }
    if args_positional(a, 0) != "input.pact" {
        io.println("FAIL: args_positional 0")
        pass = false
    }
    if args_positional(a, 5) != "" {
        io.println("FAIL: args_positional out of bounds should be empty")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
