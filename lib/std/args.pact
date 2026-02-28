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
}

type ArgParser {
    prog_name: Str
    description: Str
    flags: List[FlagDef]
    options: List[OptionDef]
    positionals: List[PositionalDef]
    commands: List[CommandDef]
}

type Args {
    command_name: Str
    flag_names: List[Str]
    option_keys: List[Str]
    option_vals: List[Str]
    positional_vals: List[Str]
    rest_args: List[Str]
    error: Str
}

pub fn argparser_new(name: Str, desc: Str) -> ArgParser {
    ArgParser {
        prog_name: name,
        description: desc,
        flags: [],
        options: [],
        positionals: [],
        commands: []
    }
}

pub fn add_flag(p: ArgParser, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut flags = p.flags
    flags.push(FlagDef { long_name: long_name, short_name: short_name, description: desc })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: flags,
        options: p.options,
        positionals: p.positionals,
        commands: p.commands
    }
}

pub fn add_option(p: ArgParser, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut opts = p.options
    opts.push(OptionDef { long_name: long_name, short_name: short_name, description: desc, default_val: "" })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: opts,
        positionals: p.positionals,
        commands: p.commands
    }
}

pub fn add_positional(p: ArgParser, name: Str, desc: Str) -> ArgParser {
    let mut pos = p.positionals
    pos.push(PositionalDef { name: name, description: desc })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: pos,
        commands: p.commands
    }
}

pub fn add_command(p: ArgParser, name: Str, desc: Str) -> ArgParser {
    let mut cmds = p.commands
    cmds.push(CommandDef { name: name, description: desc, flags: [], options: [], positionals: [] })
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: cmds
    }
}

pub fn command_add_flag(p: ArgParser, cmd_name: Str, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut cmds: List[CommandDef] = []
    let mut i = 0
    while i < p.commands.len() {
        let c = p.commands.get(i).unwrap()
        if c.name == cmd_name {
            let mut flags = c.flags
            flags.push(FlagDef { long_name: long_name, short_name: short_name, description: desc })
            cmds.push(CommandDef { name: c.name, description: c.description, flags: flags, options: c.options, positionals: c.positionals })
        } else {
            cmds.push(c)
        }
        i = i + 1
    }
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: cmds
    }
}

pub fn command_add_option(p: ArgParser, cmd_name: Str, long_name: Str, short_name: Str, desc: Str) -> ArgParser {
    let mut cmds: List[CommandDef] = []
    let mut i = 0
    while i < p.commands.len() {
        let c = p.commands.get(i).unwrap()
        if c.name == cmd_name {
            let mut opts = c.options
            opts.push(OptionDef { long_name: long_name, short_name: short_name, description: desc, default_val: "" })
            cmds.push(CommandDef { name: c.name, description: c.description, flags: c.flags, options: opts, positionals: c.positionals })
        } else {
            cmds.push(c)
        }
        i = i + 1
    }
    ArgParser {
        prog_name: p.prog_name,
        description: p.description,
        flags: p.flags,
        options: p.options,
        positionals: p.positionals,
        commands: cmds
    }
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

fn resolve_cmd_flag_name(p: ArgParser, cmd_idx: Int, arg: Str) -> Str {
    let cmd = p.commands.get(cmd_idx).unwrap()
    let mut i = 0
    while i < cmd.flags.len() {
        let f = cmd.flags.get(i).unwrap()
        if f.long_name == arg || f.short_name == arg {
            return strip_dashes(f.long_name)
        }
        i = i + 1
    }
    ""
}

fn resolve_cmd_option_name(p: ArgParser, cmd_idx: Int, arg: Str) -> Str {
    let cmd = p.commands.get(cmd_idx).unwrap()
    let mut i = 0
    while i < cmd.options.len() {
        let o = cmd.options.get(i).unwrap()
        if o.long_name == arg || o.short_name == arg {
            return strip_dashes(o.long_name)
        }
        i = i + 1
    }
    ""
}

fn find_command_idx(p: ArgParser, name: Str) -> Int {
    let mut i = 0
    while i < p.commands.len() {
        let c = p.commands.get(i).unwrap()
        if c.name == name {
            return i
        }
        i = i + 1
    }
    -1
}

pub fn argparse(p: ArgParser) -> Args {
    let mut result = Args {
        command_name: "",
        flag_names: [],
        option_keys: [],
        option_vals: [],
        positional_vals: [],
        rest_args: [],
        error: ""
    }
    let mut i = 1
    let mut cmd_idx = -1

    while i < arg_count() {
        let arg = get_arg(i)

        if arg == "--" {
            i = i + 1
            while i < arg_count() {
                result.rest_args.push(get_arg(i))
                i = i + 1
            }
            return result
        }

        if arg == "--help" || arg == "-h" {
            if cmd_idx != -1 {
                io.println(generate_command_help(p, result.command_name))
            } else {
                io.println(generate_help(p))
            }
            result = Args {
                command_name: result.command_name,
                flag_names: result.flag_names,
                option_keys: result.option_keys,
                option_vals: result.option_vals,
                positional_vals: result.positional_vals,
                rest_args: result.rest_args,
                error: "help"
            }
            return result
        }

        if cmd_idx == -1 && result.command_name == "" {
            let ci = find_command_idx(p, arg)
            if ci != -1 {
                result = Args {
                    command_name: arg,
                    flag_names: result.flag_names,
                    option_keys: result.option_keys,
                    option_vals: result.option_vals,
                    positional_vals: result.positional_vals,
                    rest_args: result.rest_args,
                    error: ""
                }
                cmd_idx = ci
                i = i + 1
                continue
            }
        }

        let mut flag_name = resolve_flag_name(p, arg)
        if cmd_idx != -1 && flag_name == "" {
            flag_name = resolve_cmd_flag_name(p, cmd_idx, arg)
        }

        if flag_name != "" {
            result.flag_names.push(flag_name)
            i = i + 1
            continue
        }

        let mut opt_name = resolve_option_name(p, arg)
        if cmd_idx != -1 && opt_name == "" {
            opt_name = resolve_cmd_option_name(p, cmd_idx, arg)
        }

        if opt_name != "" {
            if i + 1 >= arg_count() {
                result = Args {
                    command_name: result.command_name,
                    flag_names: result.flag_names,
                    option_keys: result.option_keys,
                    option_vals: result.option_vals,
                    positional_vals: result.positional_vals,
                    rest_args: result.rest_args,
                    error: "option '{arg}' requires a value"
                }
                return result
            }
            i = i + 1
            result.option_keys.push(opt_name)
            result.option_vals.push(get_arg(i))
            i = i + 1
            continue
        }

        if arg.starts_with("-") {
            result = Args {
                command_name: result.command_name,
                flag_names: result.flag_names,
                option_keys: result.option_keys,
                option_vals: result.option_vals,
                positional_vals: result.positional_vals,
                rest_args: result.rest_args,
                error: "unknown option '{arg}'"
            }
            return result
        }

        result.positional_vals.push(arg)
        i = i + 1
    }

    result
}

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

pub fn args_command(a: Args) -> Str {
    a.command_name
}

pub fn args_positional(a: Args, idx: Int) -> Str {
    if idx < a.positional_vals.len() {
        return a.positional_vals.get(idx).unwrap()
    }
    ""
}

pub fn args_rest(a: Args) -> List[Str] {
    a.rest_args
}

pub fn args_error(a: Args) -> Str {
    a.error
}

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
        let mut ci = 0
        while ci < p.commands.len() {
            let cmd = p.commands.get(ci).unwrap()
            h = h.concat("  {cmd.name}")
            h = h.concat("    {cmd.description}\n")
            let mut cfi = 0
            while cfi < cmd.flags.len() {
                let cf = cmd.flags.get(cfi).unwrap()
                h = h.concat("    {cf.long_name}")
                if cf.short_name != "" {
                    h = h.concat(", {cf.short_name}")
                }
                h = h.concat("    {cf.description}\n")
                cfi = cfi + 1
            }
            let mut coi = 0
            while coi < cmd.options.len() {
                let co = cmd.options.get(coi).unwrap()
                h = h.concat("    {co.long_name}")
                if co.short_name != "" {
                    h = h.concat(", {co.short_name}")
                }
                h = h.concat(" <value>    {co.description}\n")
                coi = coi + 1
            }
            ci = ci + 1
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

pub fn generate_command_help(p: ArgParser, cmd_name: Str) -> Str {
    let idx = find_command_idx(p, cmd_name)
    if idx == -1 {
        return "unknown command '{cmd_name}'"
    }
    let cmd = p.commands.get(idx).unwrap()
    let mut h = "Usage: {p.prog_name} {cmd_name}"
    if cmd.options.len() > 0 || cmd.flags.len() > 0 {
        h = h.concat(" [options]")
    }
    let mut pi = 0
    while pi < cmd.positionals.len() {
        let pos = cmd.positionals.get(pi).unwrap()
        h = h.concat(" <{pos.name}>")
        pi = pi + 1
    }
    h = h.concat("\n\n{cmd.description}\n")

    if cmd.flags.len() > 0 {
        h = h.concat("\nFlags:\n")
        let mut fi = 0
        while fi < cmd.flags.len() {
            let f = cmd.flags.get(fi).unwrap()
            h = h.concat("  {f.long_name}")
            if f.short_name != "" {
                h = h.concat(", {f.short_name}")
            }
            h = h.concat("    {f.description}\n")
            fi = fi + 1
        }
    }

    if cmd.options.len() > 0 {
        h = h.concat("\nOptions:\n")
        let mut oi = 0
        while oi < cmd.options.len() {
            let o = cmd.options.get(oi).unwrap()
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
