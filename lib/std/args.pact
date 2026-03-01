type FlagDef {
    long_name: Str
    short_name: Str
    description: Str
}

type OptionDef {
    long_name: Str
    short_name: Str
    description: Str
    default_val: Str
}

type PositionalDef {
    name: Str
    description: Str
}

type CommandDef {
    name: Str
    description: Str
    flags: List[FlagDef]
    options: List[OptionDef]
    positionals: List[PositionalDef]
    subcommands: List[CommandDef]
}

type CmdList {
    items: List[CommandDef]
}

type CommandAlias {
    alias: Str
    target: Str
}

type ArgParser {
    prog_name: Str
    description: Str
    flags: List[FlagDef]
    options: List[OptionDef]
    positionals: List[PositionalDef]
    commands: List[CommandDef]
    aliases: List[CommandAlias]
}

type Args {
    command_name: Str
    command_path: List[Str]
    flag_names: List[Str]
    option_keys: List[Str]
    option_vals: List[Str]
    positional_vals: List[Str]
    rest_args: List[Str]
    error: Str
}

/// Create a new argument parser.
///
/// Example:
///     let p = argparser_new("myapp", "My cool app")
///     let p = add_flag(p, "--verbose", "-v", "Enable verbose output")
///     let p = add_option(p, "--output", "-o", "Output file path")
///     let args = argparse(p)
pub fn argparser_new(name: Str, desc: Str) -> ArgParser {
    ArgParser {
        prog_name: name,
        description: desc,
        flags: [],
        options: [],
        positionals: [],
        commands: [],
        aliases: []
    }
}

/// Add a boolean flag (e.g. --verbose).
///
/// Example:
///     let p = argparser_new("myapp", "My app")
///     let p = add_flag(p, "--verbose", "-v", "Verbose output")
///     let args = argparse(p)
///     if args_has(args, "verbose") {
///         io.println("Verbose mode on")
///     }
pub fn add_flag(p: ArgParser, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut flags = p.flags
    flags.push(FlagDef { long_name: long_name, short_name: short_name, description: desc })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: flags,
        options: p.options,
        positionals: p.positionals,
        commands: p.commands,
        aliases: p.aliases
    }
}

/// Add a key-value option (e.g. --output path).
///
/// Example:
///     let p = argparser_new("myapp", "My app")
///     let p = add_option(p, "--output", "-o", "Output file")
///     let args = argparse(p)
///     let out = args_get(args, "output")
pub fn add_option(p: ArgParser, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut opts = p.options
    opts.push(OptionDef { long_name: long_name, short_name: short_name, description: desc, default_val: "" })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: opts,
        positionals: p.positionals,
        commands: p.commands,
        aliases: p.aliases
    }
}

/// Add a positional argument
pub fn add_positional(p: ArgParser, name: Str, desc: Str) -> ArgParser {
    let mut pos = p.positionals
    pos.push(PositionalDef { name: name, description: desc })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: pos,
        commands: p.commands,
        aliases: p.aliases
    }
}

fn find_command_idx(cl: CmdList, name: Str) -> Int {
    let mut i = 0
    while i < cl.items.len() {
        let c = cl.items.get(i).unwrap()
        if c.name == name {
            return i
        }
        i = i + 1
    }
    -1
}

fn wrap(cmds: List[CommandDef]) -> CmdList {
    CmdList { items: cmds }
}

fn new_cmd(name: Str, desc: Str) -> CommandDef {
    CommandDef { name: name, description: desc, flags: [], options: [], positionals: [], subcommands: [] }
}

fn cmd_with_sub(c: CommandDef, sub: CommandDef) -> CommandDef {
    let mut subs = c.subcommands
    let existing = find_command_idx(wrap(subs), sub.name)
    if existing == -1 {
        subs.push(sub)
    }
    CommandDef { name: c.name, description: c.description, flags: c.flags, options: c.options, positionals: c.positionals, subcommands: subs }
}

fn rebuild_cmds_with_sub(cl: CmdList, parent_name: Str, sub: CommandDef) -> List[CommandDef] {
    let mut result: List[CommandDef] = []
    let mut i = 0
    while i < cl.items.len() {
        let c = cl.items.get(i).unwrap()
        if c.name == parent_name {
            result.push(cmd_with_sub(c, sub))
        } else {
            result.push(c)
        }
        i = i + 1
    }
    result
}

fn rebuild_cmds_nested_sub(cl: CmdList, parent_name: Str, mid_name: Str, leaf: CommandDef) -> List[CommandDef] {
    let mut result: List[CommandDef] = []
    let mut i = 0
    while i < cl.items.len() {
        let c = cl.items.get(i).unwrap()
        if c.name == parent_name {
            let new_subs = rebuild_cmds_with_sub(wrap(c.subcommands), mid_name, leaf)
            result.push(CommandDef { name: c.name, description: c.description, flags: c.flags, options: c.options, positionals: c.positionals, subcommands: new_subs })
        } else {
            result.push(c)
        }
        i = i + 1
    }
    result
}

/// Add a subcommand. Use dot-notation for nesting (e.g. "daemon.start").
///
/// Example:
///     let p = argparser_new("myapp", "My app")
///     let p = add_command(p, "build", "Build the project")
///     let p = add_command(p, "test", "Run tests")
///     let p = add_command(p, "daemon.start", "Start daemon")
///     let args = argparse(p)
///     if args_command(args) == "build" {
///         io.println("Building...")
///     }
pub fn add_command(p: ArgParser, path: Str, desc: Str) -> ArgParser {
    if !path.contains(".") {
        let mut cmds = p.commands
        if find_command_idx(wrap(cmds), path) == -1 {
            cmds.push(new_cmd(path, desc))
        }
        return ArgParser {
            prog_name: p.prog_name,
            description: p.description,
            flags: p.flags,
            options: p.options,
            positionals: p.positionals,
            commands: cmds,
            aliases: p.aliases
        }
    }

    let dot_pos = path.index_of(".")
    let parent_name = path.substring(0, dot_pos)
    let rest = path.substring(dot_pos + 1, path.len())

    let mut cmds = p.commands
    if find_command_idx(wrap(cmds), parent_name) == -1 {
        cmds.push(new_cmd(parent_name, ""))
    }

    if !rest.contains(".") {
        cmds = rebuild_cmds_with_sub(wrap(cmds), parent_name, new_cmd(rest, desc))
        return ArgParser {
            prog_name: p.prog_name,
            description: p.description,
            flags: p.flags,
            options: p.options,
            positionals: p.positionals,
            commands: cmds,
            aliases: p.aliases
        }
    }

    let dot2 = rest.index_of(".")
    let mid_name = rest.substring(0, dot2)
    let leaf_name = rest.substring(dot2 + 1, rest.len())

    cmds = rebuild_cmds_with_sub(wrap(cmds), parent_name, new_cmd(mid_name, ""))
    cmds = rebuild_cmds_nested_sub(wrap(cmds), parent_name, mid_name, new_cmd(leaf_name, desc))

    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: cmds,
        aliases: p.aliases
    }
}

fn cmd_add_flag_direct(c: CommandDef, long: Str, short: Str, desc: Str) -> CommandDef {
    let mut flags = c.flags
    flags.push(FlagDef { long_name: long, short_name: short, description: desc })
    CommandDef { name: c.name, description: c.description, flags: flags, options: c.options, positionals: c.positionals, subcommands: c.subcommands }
}

fn cmd_add_option_direct(c: CommandDef, long: Str, short: Str, desc: Str) -> CommandDef {
    let mut opts = c.options
    opts.push(OptionDef { long_name: long, short_name: short, description: desc, default_val: "" })
    CommandDef { name: c.name, description: c.description, flags: c.flags, options: opts, positionals: c.positionals, subcommands: c.subcommands }
}

fn cmd_add_positional_direct(c: CommandDef, name: Str, desc: Str) -> CommandDef {
    let mut pos = c.positionals
    pos.push(PositionalDef { name: name, description: desc })
    CommandDef { name: c.name, description: c.description, flags: c.flags, options: c.options, positionals: pos, subcommands: c.subcommands }
}

fn modify_cmd_in_list(cl: CmdList, name: Str, modifier: Str, long: Str, short: Str, desc: Str) -> List[CommandDef] {
    let mut result: List[CommandDef] = []
    let mut i = 0
    while i < cl.items.len() {
        let c = cl.items.get(i).unwrap()
        if c.name == name {
            if modifier == "flag" {
                result.push(cmd_add_flag_direct(c, long, short, desc))
            } else if modifier == "option" {
                result.push(cmd_add_option_direct(c, long, short, desc))
            } else if modifier == "positional" {
                result.push(cmd_add_positional_direct(c, long, desc))
            } else {
                result.push(c)
            }
        } else {
            result.push(c)
        }
        i = i + 1
    }
    result
}

fn modify_nested_cmd(cl: CmdList, path: Str, modifier: Str, long: Str, short: Str, desc: Str) -> List[CommandDef] {
    if !path.contains(".") {
        return modify_cmd_in_list(cl, path, modifier, long, short, desc)
    }

    let dot_pos = path.index_of(".")
    let parent_name = path.substring(0, dot_pos)
    let rest = path.substring(dot_pos + 1, path.len())

    let mut result: List[CommandDef] = []
    let mut i = 0
    while i < cl.items.len() {
        let c = cl.items.get(i).unwrap()
        if c.name == parent_name {
            let new_subs = modify_nested_cmd(wrap(c.subcommands), rest, modifier, long, short, desc)
            result.push(CommandDef { name: c.name, description: c.description, flags: c.flags, options: c.options, positionals: c.positionals, subcommands: new_subs })
        } else {
            result.push(c)
        }
        i = i + 1
    }
    result
}

/// Add a flag to a specific subcommand
pub fn command_add_flag(p: ArgParser, cmd_path: Str, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: modify_nested_cmd(wrap(p.commands), cmd_path, "flag", long_name, short_name, desc),
        aliases: p.aliases
    }
}

/// Add an option to a specific subcommand
pub fn command_add_option(p: ArgParser, cmd_path: Str, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: modify_nested_cmd(wrap(p.commands), cmd_path, "option", long_name, short_name, desc),
        aliases: p.aliases
    }
}

/// Add a positional argument to a specific subcommand
pub fn command_add_positional(p: ArgParser, cmd_path: Str, name: Str, desc: Str) -> ArgParser {
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: modify_nested_cmd(wrap(p.commands), cmd_path, "positional", name, "", desc),
        aliases: p.aliases
    }
}

/// Add a top-level alias for a command (e.g. "t" -> "test").
/// Aliases only resolve at the root command level, not for subcommands.
pub fn add_command_alias(p: ArgParser, alias: Str, target: Str) -> ArgParser {
    let mut aliases = p.aliases
    aliases.push(CommandAlias { alias: alias, target: target })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: p.commands,
        aliases: aliases
    }
}

fn resolve_alias(p: ArgParser, name: Str) -> Str {
    let mut i = 0
    while i < p.aliases.len() {
        let a = p.aliases.get(i).unwrap()
        if a.alias == name {
            return a.target
        }
        i = i + 1
    }
    ""
}

fn strip_dashes(s: Str) -> Str {
    if s.starts_with("--") {
        return s.substring(2, s.len())
    }
    if s.starts_with("-") {
        return s.substring(1, s.len())
    }
    s
}

fn resolve_flag_name(p: ArgParser, arg: Str) -> Str {
    let mut i = 0
    while i < p.flags.len() {
        let f = p.flags.get(i).unwrap()
        if f.long_name == arg || f.short_name == arg {
            return strip_dashes(f.long_name)
        }
        i = i + 1
    }
    ""
}

fn resolve_option_name(p: ArgParser, arg: Str) -> Str {
    let mut i = 0
    while i < p.options.len() {
        let o = p.options.get(i).unwrap()
        if o.long_name == arg || o.short_name == arg {
            return strip_dashes(o.long_name)
        }
        i = i + 1
    }
    ""
}

fn resolve_cmd_flag(c: CommandDef, arg: Str) -> Str {
    let mut i = 0
    while i < c.flags.len() {
        let f = c.flags.get(i).unwrap()
        if f.long_name == arg || f.short_name == arg {
            return strip_dashes(f.long_name)
        }
        i = i + 1
    }
    ""
}

fn resolve_cmd_option(c: CommandDef, arg: Str) -> Str {
    let mut i = 0
    while i < c.options.len() {
        let o = c.options.get(i).unwrap()
        if o.long_name == arg || o.short_name == arg {
            return strip_dashes(o.long_name)
        }
        i = i + 1
    }
    ""
}

fn resolve_cmd_flag_hierarchical(cl: CmdList, arg: Str) -> Str {
    let mut i = cl.items.len() - 1
    while i >= 0 {
        let result = resolve_cmd_flag(cl.items.get(i).unwrap(), arg)
        if result != "" {
            return result
        }
        i = i - 1
    }
    ""
}

fn resolve_cmd_option_hierarchical(cl: CmdList, arg: Str) -> Str {
    let mut i = cl.items.len() - 1
    while i >= 0 {
        let result = resolve_cmd_option(cl.items.get(i).unwrap(), arg)
        if result != "" {
            return result
        }
        i = i - 1
    }
    ""
}

fn join_path(parts: List[Str]) -> Str {
    let mut result = ""
    let mut i = 0
    while i < parts.len() {
        if i > 0 {
            result = result.concat(" ")
        }
        result = result.concat(parts.get(i).unwrap())
        i = i + 1
    }
    result
}

fn find_command_in(cl: CmdList, name: Str) -> CommandDef {
    let idx = find_command_idx(cl, name)
    if idx == -1 {
        return new_cmd("", "")
    }
    cl.items.get(idx).unwrap()
}

/// Parse an explicit argument list. argv[0] is the program name (skipped).
///
/// Example:
///     let p = argparser_new("myapp", "My app")
///     let p = add_flag(p, "--verbose", "-v", "Verbose")
///     let args = parse_argv(p, ["myapp", "--verbose", "file.pact"])
pub fn parse_argv(p: ArgParser, argv: List[Str]) -> Args {
    let mut result = Args {
        command_name: "",
        command_path: [],
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: [],
        rest_args: [],
        error: ""
    }
    let mut i = 1
    let mut cmd_chain: List[CommandDef] = []
    let mut current_cmds = p.commands

    while i < argv.len() {
        let arg = argv.get(i).unwrap()

        if arg == "--" {
            i = i + 1
            while i < argv.len() {
                result.rest_args.push(argv.get(i).unwrap())
                i = i + 1
            }
            result.command_name = join_path(result.command_path)
            return result
        }

        if arg == "--help" || arg == "-h" {
            result.command_name = join_path(result.command_path)
            if cmd_chain.len() > 0 {
                io.println(generate_command_help(p, result.command_name))
            } else {
                io.println(generate_help(p))
            }
            result.error = "help"
            return result
        }

        if !arg.starts_with("-") {
            let mut cmd_name = arg
            let alias_target = resolve_alias(p, arg)
            if alias_target != "" {
                cmd_name = alias_target
            }
            let matched = find_command_in(wrap(current_cmds), cmd_name)
            if matched.name != "" {
                result.command_path.push(cmd_name)
                cmd_chain.push(matched)
                current_cmds = matched.subcommands
                i = i + 1
                continue
            }
        }

        let mut flag_name = resolve_flag_name(p, arg)
        if cmd_chain.len() > 0 && flag_name == "" {
            flag_name = resolve_cmd_flag_hierarchical(wrap(cmd_chain), arg)
        }

        if flag_name != "" {
            result.flag_names.push(flag_name)
            i = i + 1
            continue
        }

        let mut opt_name = resolve_option_name(p, arg)
        if cmd_chain.len() > 0 && opt_name == "" {
            opt_name = resolve_cmd_option_hierarchical(wrap(cmd_chain), arg)
        }

        if opt_name != "" {
            if i + 1 >= argv.len() {
                result.error = "option '{arg}' requires a value"
                return result
            }
            i = i + 1
            result.option_keys.push(opt_name)
            result.option_vals.push(argv.get(i).unwrap())
            i = i + 1
            continue
        }

        if arg.starts_with("-") {
            result.error = "unknown option '{arg}'"
            return result
        }

        let mut ctx_has_positionals = p.positionals.len() > 0
        let mut ctx_has_commands = p.commands.len() > 0
        if cmd_chain.len() > 0 {
            let active = cmd_chain.get(cmd_chain.len() - 1).unwrap()
            ctx_has_positionals = active.positionals.len() > 0
            ctx_has_commands = active.subcommands.len() > 0
        }
        if ctx_has_commands && !ctx_has_positionals {
            result.error = "unknown command '{arg}'"
            return result
        }
        result.positional_vals.push(arg)
        i = i + 1
    }

    result.command_name = join_path(result.command_path)
    result
}

/// Parse command-line arguments from process args. Returns Args with parsed results.
///
/// Example:
///     let p = argparser_new("myapp", "My app")
///     let p = add_flag(p, "--verbose", "-v", "Verbose")
///     let p = add_command(p, "run", "Run something")
///     let args = argparse(p)
///     if args_error(args) != "" {
///         io.println(args_error(args))
///         return
///     }
pub fn argparse(p: ArgParser) -> Args {
    let mut argv: List[Str] = []
    let mut i = 0
    while i < arg_count() {
        argv.push(get_arg(i))
        i = i + 1
    }
    parse_argv(p, argv)
}

/// Check if a flag was set
pub fn args_has(a: Args, name: Str) -> Bool {
    let mut i = 0
    while i < a.flag_names.len() {
        if a.flag_names.get(i).unwrap() == name {
            return true
        }
        i = i + 1
    }
    false
}

/// Get an option value (first occurrence). Returns empty string if not set
pub fn args_get(a: Args, name: Str) -> Str {
    let mut i = 0
    while i < a.option_keys.len() {
        if a.option_keys.get(i).unwrap() == name {
            return a.option_vals.get(i).unwrap()
        }
        i = i + 1
    }
    ""
}

/// Get all values for a repeated option. Returns empty list if not set
pub fn args_get_all(a: Args, name: Str) -> List[Str] {
    let mut vals: List[Str] = []
    let mut i = 0
    while i < a.option_keys.len() {
        if a.option_keys.get(i).unwrap() == name {
            vals.push(a.option_vals.get(i).unwrap())
        }
        i = i + 1
    }
    vals
}

/// Get the matched command name
pub fn args_command(a: Args) -> Str {
    a.command_name
}

/// Get the command path as a list
pub fn args_command_path(a: Args) -> List[Str] {
    a.command_path
}

/// Get positional argument at index. Returns empty string if missing
pub fn args_positional(a: Args, idx: Int) -> Str {
    if idx < a.positional_vals.len() {
        return a.positional_vals.get(idx).unwrap()
    }
    ""
}

/// Get the count of positional arguments
pub fn args_positional_count(a: Args) -> Int {
    a.positional_vals.len()
}

/// Get arguments after the "--" separator
pub fn args_rest(a: Args) -> List[Str] {
    a.rest_args
}

/// Get parse error. Returns "help" for --help, empty if no error
pub fn args_error(a: Args) -> Str {
    a.error
}

fn emit_cmd_help(h: Str, cmd: CommandDef, indent: Str) -> Str {
    let mut result = h
    result = result.concat("{indent}{cmd.name}")
    if cmd.description != "" {
        result = result.concat("    {cmd.description}")
    }
    result = result.concat("\n")
    let inner_indent = indent.concat("  ")
    let mut cfi = 0
    while cfi < cmd.flags.len() {
        let cf = cmd.flags.get(cfi).unwrap()
        result = result.concat("{inner_indent}{cf.long_name}")
        if cf.short_name != "" {
            result = result.concat(", {cf.short_name}")
        }
        result = result.concat("    {cf.description}\n")
        cfi = cfi + 1
    }
    let mut coi = 0
    while coi < cmd.options.len() {
        let co = cmd.options.get(coi).unwrap()
        result = result.concat("{inner_indent}{co.long_name}")
        if co.short_name != "" {
            result = result.concat(", {co.short_name}")
        }
        result = result.concat(" <value>    {co.description}\n")
        coi = coi + 1
    }
    if cmd.subcommands.len() > 0 {
        result = emit_command_tree(result, wrap(cmd.subcommands), inner_indent)
    }
    result
}

fn emit_command_tree(h: Str, cl: CmdList, indent: Str) -> Str {
    let mut result = h
    let mut ci = 0
    while ci < cl.items.len() {
        result = emit_cmd_help(result, cl.items.get(ci).unwrap(), indent)
        ci = ci + 1
    }
    result
}

/// Generate help text for the full parser
pub fn generate_help(p: ArgParser) -> Str {
    let mut h = "Usage: {p.prog_name}"
    if p.commands.len() > 0 {
        h = h.concat(" <command>")
    }
    if p.options.len() > 0 || p.flags.len() > 0 {
        h = h.concat(" [options]")
    }
    let mut pi = 0
    while pi < p.positionals.len() {
        let pos = p.positionals.get(pi).unwrap()
        h = h.concat(" <{pos.name}>")
        pi = pi + 1
    }
    h = h.concat("\n\n{p.description}\n")

    if p.commands.len() > 0 {
        h = h.concat("\nCommands:\n")
        h = emit_command_tree(h, wrap(p.commands), "  ")
    }

    if p.aliases.len() > 0 {
        h = h.concat("\nAliases:\n")
        let mut ai = 0
        while ai < p.aliases.len() {
            let a = p.aliases.get(ai).unwrap()
            h = h.concat("  {a.alias} -> {a.target}\n")
            ai = ai + 1
        }
    }

    if p.flags.len() > 0 {
        h = h.concat("\nFlags:\n")
        let mut fi = 0
        while fi < p.flags.len() {
            let f = p.flags.get(fi).unwrap()
            h = h.concat("  {f.long_name}")
            if f.short_name != "" {
                h = h.concat(", {f.short_name}")
            }
            h = h.concat("    {f.description}\n")
            fi = fi + 1
        }
    }

    if p.options.len() > 0 {
        h = h.concat("\nOptions:\n")
        let mut oi = 0
        while oi < p.options.len() {
            let o = p.options.get(oi).unwrap()
            h = h.concat("  {o.long_name}")
            if o.short_name != "" {
                h = h.concat(", {o.short_name}")
            }
            h = h.concat(" <value>    {o.description}\n")
            oi = oi + 1
        }
    }

    h
}

fn find_cmd_by_path(p: ArgParser, cmd_path: Str) -> CommandDef {
    let parts = cmd_path.split(" ")
    let mut cmds = p.commands
    let mut found = new_cmd("", "")
    let mut pi = 0
    while pi < parts.len() {
        let seg = parts.get(pi).unwrap()
        found = find_command_in(wrap(cmds), seg)
        if found.name == "" {
            return new_cmd("", "")
        }
        cmds = found.subcommands
        pi = pi + 1
    }
    found
}

fn emit_cmd_detail_help(found: CommandDef, prog_name: Str, cmd_path: Str) -> Str {
    let mut h = "Usage: {prog_name} {cmd_path}"
    if found.options.len() > 0 || found.flags.len() > 0 {
        h = h.concat(" [options]")
    }
    let mut posi = 0
    while posi < found.positionals.len() {
        let pos = found.positionals.get(posi).unwrap()
        h = h.concat(" <{pos.name}>")
        posi = posi + 1
    }
    if found.subcommands.len() > 0 {
        h = h.concat(" <subcommand>")
    }
    h = h.concat("\n\n{found.description}\n")

    if found.subcommands.len() > 0 {
        h = h.concat("\nSubcommands:\n")
        h = emit_command_tree(h, wrap(found.subcommands), "  ")
    }

    if found.flags.len() > 0 {
        h = h.concat("\nFlags:\n")
        let mut fi = 0
        while fi < found.flags.len() {
            let f = found.flags.get(fi).unwrap()
            h = h.concat("  {f.long_name}")
            if f.short_name != "" {
                h = h.concat(", {f.short_name}")
            }
            h = h.concat("    {f.description}\n")
            fi = fi + 1
        }
    }

    if found.options.len() > 0 {
        h = h.concat("\nOptions:\n")
        let mut oi = 0
        while oi < found.options.len() {
            let o = found.options.get(oi).unwrap()
            h = h.concat("  {o.long_name}")
            if o.short_name != "" {
                h = h.concat(", {o.short_name}")
            }
            h = h.concat(" <value>    {o.description}\n")
            oi = oi + 1
        }
    }

    h
}

/// Generate help text for a specific subcommand
pub fn generate_command_help(p: ArgParser, cmd_path: Str) -> Str {
    let found = find_cmd_by_path(p, cmd_path)
    if found.name == "" {
        return "unknown command '{cmd_path}'"
    }
    emit_cmd_detail_help(found, p.prog_name, cmd_path)
}
