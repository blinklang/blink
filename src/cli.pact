import std.audit
import std.lockfile
import std.manifest
import std.resolver

fn print_usage() {
    io.println("Usage: pact <command> [options] <file>")
    io.println("")
    io.println("Commands:")
    io.println("  build <file>    Compile .pact to native binary")
    io.println("  run <file>      Build and execute")
    io.println("  test [<file>]   Build and run tests (discovers .pact files with test blocks)")
    io.println("  check <file>    Validate without producing binary")
    io.println("  fmt [<file>]    Format source file(s) in place")
    io.println("  audit           Check for capability escalations in dependencies")
    io.println("  add <pkg>       Add a dependency (use --path or --git)")
    io.println("  remove <pkg>    Remove a dependency")
    io.println("  update [<pkg>]  Re-resolve dependencies and update lockfile")
    io.println("")
    io.println("Options:")
    io.println("  --output <path>   Output path (default: build/<name>)")
    io.println("  --format json     Machine-readable JSON diagnostic output")
    io.println("  --path <dir>      Path dependency source (for 'add')")
    io.println("  --git <url>       Git dependency source (for 'add')")
    io.println("  --tag <tag>       Git tag (for 'add', used with --git)")
    io.println("  --dev             Add as dev-dependency (for 'add')")
    io.println("  --debug           Enable debug mode (debug_assert, -g -O0)")
    io.println("")
    io.println("Test options:")
    io.println("  --filter <pat>    Run only tests matching pattern")
    io.println("  --json            Output test results as JSON")
    io.println("  --tags <tag>      Run only tests with matching tag")
}

fn strip_extension(filename: Str) -> Str {
    if filename.ends_with(".pact") {
        return filename.substring(0, filename.len() - 5)
    }
    return filename
}

fn detect_async(source: Str) -> Int {
    if source.contains("async.spawn") || source.contains("async.scope") {
        return 1
    }
    return 0
}

fn has_test_blocks(source: Str) -> Int {
    if source.starts_with("test \"") || source.contains("\ntest \"") {
        return 1
    }
    return 0
}

fn collect_test_files(dir: Str, results: List[Str]) {
    let entries = fs.list_dir(dir)
    let mut i = 0
    while i < entries.len() {
        let entry = entries.get(i)
        if entry.starts_with(".") || entry == "build" || entry == "legacy" || entry == "node_modules" {
            i = i + 1
            continue
        }
        let full_path = path_join(dir, entry)
        if is_dir(full_path) {
            collect_test_files(full_path, results)
        } else if entry.ends_with(".pact") {
            let source = read_file(full_path)
            if has_test_blocks(source) {
                results.push(full_path)
            }
        }
        i = i + 1
    }
}

fn do_build(source_path: Str, output_path: Str, c_path: Str, format_flag: Str, debug_mode: Int) -> Int {
    let pactc = "build/pactc"
    if !file_exists(pactc) {
        io.println("error: compiler not found at build/pactc")
        io.println("  run: ./bootstrap/bootstrap.sh")
        return 1
    }

    let mut compile_cmd = "{pactc} {source_path} {c_path}"
    if format_flag != "" {
        compile_cmd = "{pactc} {source_path} {c_path} --format {format_flag}"
    }
    if debug_mode != 0 {
        compile_cmd = "{compile_cmd} --debug"
    }
    let rc = shell_exec(compile_cmd)
    if rc != 0 {
        io.println("error: compilation failed")
        return rc
    }

    let source = read_file(source_path)
    let mut link_flags = "-lm"
    if detect_async(source) {
        link_flags = "-lm -pthread"
    }

    let mut cc_cmd = "cc -o {output_path} {c_path} -Ibuild {link_flags}"
    if debug_mode != 0 {
        cc_cmd = "cc -g -O0 -o {output_path} {c_path} -Ibuild {link_flags}"
    }
    let cc_rc = shell_exec(cc_cmd)
    if cc_rc != 0 {
        io.println("error: C compilation failed")
        return cc_rc
    }

    return 0
}

fn find_section_end(content: Str, section: Str) -> Int {
    let header = "[".concat(section).concat("]")
    let mut pos = -1
    let mut i = 0
    while i < content.len() - header.len() {
        let mut found_match = 1
        let mut j = 0
        while j < header.len() {
            if content.char_at(i + j) != header.char_at(j) {
                found_match = 0
                j = header.len()
            }
            j = j + 1
        }
        if found_match == 1 {
            pos = i + header.len()
            while pos < content.len() && content.char_at(pos) != 10 {
                pos = pos + 1
            }
            if pos < content.len() {
                pos = pos + 1
            }
            let mut end = pos
            while end < content.len() {
                if content.char_at(end) == 91 {
                    if end == 0 || content.char_at(end - 1) == 10 {
                        return end
                    }
                }
                end = end + 1
            }
            return content.len()
        }
        i = i + 1
    }
    -1
}

fn has_section(content: Str, section: Str) -> Int {
    let header = "[".concat(section).concat("]")
    let mut i = 0
    while i < content.len() - header.len() + 1 {
        let mut found_match = 1
        let mut j = 0
        while j < header.len() {
            if i + j >= content.len() || content.char_at(i + j) != header.char_at(j) {
                found_match = 0
                j = header.len()
            }
            j = j + 1
        }
        if found_match == 1 {
            if i == 0 || content.char_at(i - 1) == 10 {
                return 1
            }
        }
        i = i + 1
    }
    0
}

fn format_dep_value(dep_path_flag: Str, git_url_flag: Str, git_tag_flag: Str) -> Str {
    if dep_path_flag != "" {
        return "\{ path = \"".concat(dep_path_flag).concat("\" \}")
    }
    if git_url_flag != "" {
        if git_tag_flag != "" {
            return "\{ git = \"".concat(git_url_flag).concat("\", tag = \"").concat(git_tag_flag).concat("\" \}")
        }
        return "\{ git = \"".concat(git_url_flag).concat("\" \}")
    }
    ""
}

fn insert_dep_line(content: Str, section: Str, dep_name: Str, dep_value: Str) -> Str {
    let line = dep_name.concat(" = ").concat(dep_value).concat("\n")
    if has_section(content, section) == 1 {
        let end = find_section_end(content, section)
        let before = content.substring(0, end)
        let after = content.substring(end, content.len() - end)
        return before.concat(line).concat(after)
    }
    content.concat("\n[").concat(section).concat("]\n").concat(line)
}

fn remove_dep_line(content: Str, dep_name: Str) -> Str {
    let mut result = ""
    let mut i = 0
    let mut line_start = 0
    while i <= content.len() {
        if i == content.len() || content.char_at(i) == 10 {
            let line_len = i - line_start
            let line = content.substring(line_start, line_len)
            let mut skip = 0
            if line.starts_with(dep_name) {
                let after_name_pos = dep_name.len()
                if after_name_pos < line.len() {
                    let ch = line.char_at(after_name_pos)
                    if ch == 61 || ch == 32 {
                        skip = 1
                    }
                }
            }
            if skip == 0 {
                result = result.concat(line)
                if i < content.len() {
                    result = result.concat("\n")
                }
            }
            line_start = i + 1
        }
        i = i + 1
    }
    result
}

fn main() {
    if arg_count() < 2 {
        print_usage()
        return
    }

    let command = get_arg(1)
    let mut source_path = ""
    let mut output_path = ""
    let mut format_flag = ""
    let mut filter_pattern = ""
    let mut json_output = 0
    let mut tags_filter = ""
    let mut dep_path_flag = ""
    let mut git_url_flag = ""
    let mut git_tag_flag = ""
    let mut dev_flag = 0
    let mut debug_flag = 0
    let mut i = 2

    while i < arg_count() {
        let arg = get_arg(i)
        if arg == "--output" {
            if i + 1 < arg_count() {
                i = i + 1
                output_path = get_arg(i)
            } else {
                io.println("error: --output requires a path")
                return
            }
        } else if arg == "--format" {
            if i + 1 < arg_count() {
                i = i + 1
                format_flag = get_arg(i)
            } else {
                io.println("error: --format requires a value")
                return
            }
        } else if arg == "--filter" {
            if i + 1 < arg_count() {
                i = i + 1
                filter_pattern = get_arg(i)
            } else {
                io.println("error: --filter requires a pattern")
                return
            }
        } else if arg == "--path" {
            if i + 1 < arg_count() {
                i = i + 1
                dep_path_flag = get_arg(i)
            } else {
                io.println("error: --path requires a directory")
                return
            }
        } else if arg == "--git" {
            if i + 1 < arg_count() {
                i = i + 1
                git_url_flag = get_arg(i)
            } else {
                io.println("error: --git requires a URL")
                return
            }
        } else if arg == "--tag" {
            if i + 1 < arg_count() {
                i = i + 1
                git_tag_flag = get_arg(i)
            } else {
                io.println("error: --tag requires a value")
                return
            }
        } else if arg == "--dev" {
            dev_flag = 1
        } else if arg == "--debug" {
            debug_flag = 1
        } else if arg == "--json" {
            json_output = 1
        } else if arg == "--tags" {
            if i + 1 < arg_count() {
                i = i + 1
                tags_filter = get_arg(i)
            } else {
                io.println("error: --tags requires a value")
                return
            }
        } else {
            source_path = arg
        }
        i = i + 1
    }

    if source_path == "" && command != "fmt" && command != "test" && command != "audit" && command != "add" && command != "remove" && command != "update" {
        io.println("error: no source file specified")
        print_usage()
        return
    }

    if source_path != "" && command != "add" && command != "remove" && command != "update" && !file_exists(source_path) {
        io.println("error: file not found: {source_path}")
        return
    }

    let mut basename = ""
    let mut name = ""
    let mut c_path = ""
    if source_path != "" {
        basename = path_basename(source_path)
        name = strip_extension(basename)
        c_path = "build/{name}.c"
    }

    shell_exec("mkdir -p build")

    if output_path == "" && name != "" {
        output_path = "build/{name}"
    }

    if command == "build" {
        let rc = do_build(source_path, output_path, c_path, format_flag, debug_flag)
        if rc == 0 {
            io.println("built: {output_path}")
        }
    } else if command == "run" {
        let rc = do_build(source_path, output_path, c_path, format_flag, debug_flag)
        if rc != 0 {
            return
        }
        let run_rc = shell_exec(output_path)
        exit(run_rc)
    } else if command == "test" {
        if source_path != "" {
            let rc = do_build(source_path, output_path, c_path, format_flag, 1)
            if rc != 0 {
                return
            }
            let mut run_cmd = output_path
            if filter_pattern != "" {
                run_cmd = "{run_cmd} --test-filter \"{filter_pattern}\""
            }
            if json_output != 0 {
                run_cmd = "{run_cmd} --test-json"
            }
            if tags_filter != "" {
                run_cmd = "{run_cmd} --test-tags \"{tags_filter}\""
            }
            let test_rc = shell_exec(run_cmd)
            exit(test_rc)
        }

        let mut test_files: List[Str] = []
        collect_test_files(".", test_files)

        let mut total_passed = 0
        let mut total_failed = 0
        let mut total_errors = 0
        let file_count = test_files.len()
        let mut json_first = 1
        let mut fi = 0

        if json_output != 0 {
            io.println("\{\"files\":[")
        }

        while fi < file_count {
            let tf = test_files.get(fi)
            let tf_dir = path_dirname(tf)
            let tf_base = strip_extension(path_basename(tf))
            let mut build_dir = "build"
            if tf_dir != "." && tf_dir != "" {
                build_dir = "build/{tf_dir}"
            }
            shell_exec("mkdir -p {build_dir}")
            let tf_c = "{build_dir}/{tf_base}.c"
            let tf_out = "{build_dir}/{tf_base}"

            let build_rc = do_build(tf, tf_out, tf_c, format_flag, 1)
            if build_rc != 0 {
                total_errors = total_errors + 1
                if json_output != 0 {
                    if json_first == 0 {
                        io.println(",")
                    }
                    json_first = 0
                    io.println("\{\"file\":\"{tf}\",\"error\":\"build failed\"}")
                } else {
                    io.println("--- {tf} ---")
                    io.println("  BUILD FAILED")
                    io.println("")
                }
                fi = fi + 1
                continue
            }

            let source = read_file(tf)
            let mut run_cmd = tf_out
            if source.contains("fn main(") {
                run_cmd = "{run_cmd} --test"
            }
            if filter_pattern != "" {
                run_cmd = "{run_cmd} --test-filter \"{filter_pattern}\""
            }
            if json_output != 0 {
                run_cmd = "{run_cmd} --test-json"
            }
            if tags_filter != "" {
                run_cmd = "{run_cmd} --test-tags \"{tags_filter}\""
            }

            if json_output == 0 {
                io.println("--- {tf} ---")
            } else {
                if json_first == 0 {
                    io.println(",")
                }
                json_first = 0
                io.println("\{\"file\":\"{tf}\",\"results\":")
            }

            let test_rc = shell_exec(run_cmd)

            if json_output != 0 {
                io.println("}")
            }

            if test_rc != 0 {
                total_failed = total_failed + 1
            } else {
                total_passed = total_passed + 1
            }

            fi = fi + 1
        }

        if file_count == 0 {
            if json_output != 0 {
                io.println("],\"summary\":\{\"files\":0,\"files_passed\":0,\"files_failed\":0,\"build_errors\":0}}")
            } else {
                io.println("error: no files with test blocks found")
            }
            exit(1)
        }

        if json_output != 0 {
            io.println("],\"summary\":\{\"files\":{file_count},\"files_passed\":{total_passed},\"files_failed\":{total_failed},\"build_errors\":{total_errors}}}")
        } else {
            io.println("========================================")
            io.println("{file_count} test files: {total_passed} passed, {total_failed} failed, {total_errors} build errors")
        }

        if total_failed > 0 || total_errors > 0 {
            exit(1)
        }
    } else if command == "check" {
        let pactc = "build/pactc"
        if !file_exists(pactc) {
            io.println("error: compiler not found at build/pactc")
            io.println("  run: ./bootstrap/bootstrap.sh")
            return
        }
        let mut compile_cmd = "{pactc} {source_path} {c_path}"
        if format_flag != "" {
            compile_cmd = "{pactc} {source_path} {c_path} --format {format_flag}"
        }
        let rc = shell_exec(compile_cmd)
        if rc == 0 {
            io.println("ok: {source_path}")
        } else {
            io.println("error: check failed")
        }
    } else if command == "fmt" {
        let pactc = "build/pactc"
        if !file_exists(pactc) {
            io.println("error: compiler not found at build/pactc")
            io.println("  run: ./bootstrap/bootstrap.sh")
            return
        }
        if source_path == "" {
            let files = fs.list_dir(".")
            let mut fi = 0
            while fi < files.len() {
                let fname = files.get(fi)
                if fname.ends_with(".pact") {
                    let fmt_cmd = "{pactc} {fname} {fname} --emit pact"
                    let rc = shell_exec(fmt_cmd)
                    if rc == 0 {
                        io.println("formatted: {fname}")
                    } else {
                        io.println("error: formatting failed for {fname}")
                    }
                }
                fi = fi + 1
            }
        } else {
            let compile_cmd = "{pactc} {source_path} {source_path} --emit pact"
            let rc = shell_exec(compile_cmd)
            if rc == 0 {
                io.println("formatted: {source_path}")
            } else {
                io.println("error: formatting failed")
            }
        }
    } else if command == "audit" {
        let mut baseline_path = ""
        let mut ai = 2
        while ai < arg_count() {
            let aarg = get_arg(ai)
            if aarg == "--baseline" {
                if ai + 1 < arg_count() {
                    ai = ai + 1
                    baseline_path = get_arg(ai)
                } else {
                    io.println("error: --baseline requires a path")
                    return
                }
            }
            ai = ai + 1
        }

        if file_exists("pact.lock") == 0 {
            io.println("error: no pact.lock found. Run 'pact build' first.")
            return
        }

        lockfile_load("pact.lock")

        if baseline_path != "" {
            audit_load_baseline(baseline_path)
        }

        let count = audit_check()
        audit_report()
        if count > 0 {
            exit(1)
        }
    } else if command == "add" {
        if source_path == "" {
            io.println("error: pact add requires a package name")
            io.println("usage: pact add <pkg> --path <dir>")
            io.println("       pact add <pkg> --git <url> [--tag <tag>]")
            return
        }
        let pkg_name = source_path

        if dep_path_flag == "" && git_url_flag == "" {
            io.println("error: pact add requires --path or --git (registry not supported in v1)")
            return
        }

        if file_exists("pact.toml") == 0 {
            io.println("error: no pact.toml found in current directory")
            return
        }

        manifest_clear()
        let load_rc = manifest_load("pact.toml")
        if load_rc != 0 {
            return
        }

        if manifest_has_dep(pkg_name) == 1 {
            io.println("error: dependency '{pkg_name}' already exists in pact.toml")
            return
        }

        let dep_val = format_dep_value(dep_path_flag, git_url_flag, git_tag_flag)
        let content = read_file("pact.toml")
        let section = "dependencies"
        if dev_flag == 1 {
            let updated = insert_dep_line(content, "dev-dependencies", pkg_name, dep_val)
            write_file("pact.toml", updated)
        } else {
            let updated = insert_dep_line(content, section, pkg_name, dep_val)
            write_file("pact.toml", updated)
        }

        let resolve_rc = resolve_and_lock(".")
        if resolve_rc == 0 {
            io.println("added: {pkg_name}")
        } else {
            io.println("error: dependency resolution failed after adding '{pkg_name}'")
        }
    } else if command == "remove" {
        if source_path == "" {
            io.println("error: pact remove requires a package name")
            io.println("usage: pact remove <pkg>")
            return
        }
        let pkg_name = source_path

        if file_exists("pact.toml") == 0 {
            io.println("error: no pact.toml found in current directory")
            return
        }

        manifest_clear()
        let load_rc = manifest_load("pact.toml")
        if load_rc != 0 {
            return
        }

        if manifest_has_dep(pkg_name) == 0 {
            io.println("error: dependency '{pkg_name}' not found in pact.toml")
            return
        }

        let content = read_file("pact.toml")
        let updated = remove_dep_line(content, pkg_name)
        write_file("pact.toml", updated)

        let resolve_rc = resolve_and_lock(".")
        if resolve_rc == 0 {
            io.println("removed: {pkg_name}")
        } else {
            io.println("warning: dependency resolution failed after removing '{pkg_name}'")
            io.println("removed: {pkg_name}")
        }
    } else if command == "update" {
        if file_exists("pact.toml") == 0 {
            io.println("error: no pact.toml found in current directory")
            return
        }

        let resolve_rc = resolve_and_lock(".")
        if resolve_rc == 0 {
            if source_path != "" {
                io.println("updated: {source_path}")
            } else {
                io.println("updated: all dependencies")
            }
            io.println("lockfile written: pact.lock")
        } else {
            io.println("error: dependency resolution failed")
        }
    } else {
        io.println("error: unknown command '{command}'")
        print_usage()
    }
}
