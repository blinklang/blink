import ast
import std.args
import std.audit
import std.lockfile
import std.manifest
import std.resolver
import lexer
import parser
import typecheck
import symbol_index
import query
import diagnostics
import daemon

fn strip_extension(filename: Str) -> Str {
    if filename.ends_with(".pact") {
        return filename.substring(0, filename.len() - 5)
    }
    return filename
}

fn find_daemon_sock_from(start_dir: Str) -> Str {
    let first = path_join(start_dir, ".pact/daemon.sock")
    if file_exists(first) {
        return first
    }
    let mut prev = start_dir
    let mut dir = path_dirname(start_dir)
    let mut depth = 0
    while depth < 10 {
        if dir == prev {
            return ""
        }
        let candidate = path_join(dir, ".pact/daemon.sock")
        if file_exists(candidate) {
            return candidate
        }
        prev = dir
        dir = path_dirname(dir)
        depth = depth + 1
    }
    return ""
}

fn find_daemon_sock() -> Str {
    // CWD-relative check is the common case
    if file_exists(".pact/daemon.sock") {
        return ".pact/daemon.sock"
    }
    return ""
}

fn detect_async(source: Str) -> Int {
    if source.contains("async.spawn") || source.contains("async.scope") {
        return 1
    }
    return 0
}

fn detect_net_client(c_source: Str) -> Int {
    if c_source.contains("PACT_USE_CURL") {
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

fn collect_pact_files(dir: Str, results: List[Str]) {
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
            collect_pact_files(full_path, results)
        } else if entry.ends_with(".pact") {
            results.push(full_path)
        }
        i = i + 1
    }
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
    let c_source = read_file(c_path)
    let mut link_flags = "-lm"
    if detect_async(source) {
        link_flags = "-lm -pthread"
    }

    if detect_net_client(c_source) {
        link_flags = "{link_flags} -lcurl"
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

fn ast_json_escape(s: Str) -> Str {
    let mut r = ""
    let mut i = 0
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 { r = r.concat("\\\"") }
        else if c == 92 { r = r.concat("\\\\") }
        else if c == 10 { r = r.concat("\\n") }
        else if c == 9 { r = r.concat("\\t") }
        else if c == 13 { r = r.concat("\\r") }
        else { r = r.concat(s.substring(i, 1)) }
        i = i + 1
    }
    r
}

fn sublist_to_json(sl: Int) -> Str {
    let len = sublist_length(sl)
    let mut r = "["
    let mut i = 0
    while i < len {
        if i > 0 { r = r.concat(",") }
        let child = sublist_get(sl, i)
        r = r.concat(ast_to_json(child))
        i = i + 1
    }
    r = r.concat("]")
    r
}

fn ast_to_json(id: Int) -> Str {
    if id < 0 { return "null" }
    let kind = np_kind.get(id)
    let kind_name = node_kind_name(kind)
    let mut r = "\{\"kind\":\""
    r = r.concat(ast_json_escape(kind_name)).concat("\"")

    let line = np_line.get(id)
    let col = np_col.get(id)
    if line > 0 { r = r.concat(",\"line\":{line},\"col\":{col}") }

    let name = np_name.get(id)
    if name != "" { r = r.concat(",\"name\":\"").concat(ast_json_escape(name)).concat("\"") }

    let str_val = np_str_val.get(id)
    if str_val != "" { r = r.concat(",\"str_val\":\"").concat(ast_json_escape(str_val)).concat("\"") }

    let int_val = np_int_val.get(id)
    if kind == NodeKind.IntLit { r = r.concat(",\"int_val\":{int_val}") }
    else if int_val != 0 { r = r.concat(",\"int_val\":{int_val}") }

    let op = np_op.get(id)
    if op != "" { r = r.concat(",\"op\":\"").concat(ast_json_escape(op)).concat("\"") }

    let type_name = np_type_name.get(id)
    if type_name != "" { r = r.concat(",\"type_name\":\"").concat(ast_json_escape(type_name)).concat("\"") }

    let trait_name = np_trait_name.get(id)
    if trait_name != "" { r = r.concat(",\"trait_name\":\"").concat(ast_json_escape(trait_name)).concat("\"") }

    let var_name = np_var_name.get(id)
    if var_name != "" { r = r.concat(",\"var_name\":\"").concat(ast_json_escape(var_name)).concat("\"") }

    let method_name = np_method.get(id)
    if method_name != "" { r = r.concat(",\"method\":\"").concat(ast_json_escape(method_name)).concat("\"") }

    let return_type = np_return_type.get(id)
    if return_type != "" { r = r.concat(",\"return_type\":\"").concat(ast_json_escape(return_type)).concat("\"") }

    if np_is_mut.get(id) != 0 { r = r.concat(",\"is_mut\":true") }
    if np_is_pub.get(id) != 0 { r = r.concat(",\"is_pub\":true") }
    if np_inclusive.get(id) != 0 { r = r.concat(",\"inclusive\":true") }

    let left = np_left.get(id)
    if left >= 0 { r = r.concat(",\"left\":").concat(ast_to_json(left)) }

    let right = np_right.get(id)
    if right >= 0 { r = r.concat(",\"right\":").concat(ast_to_json(right)) }

    let body = np_body.get(id)
    if body >= 0 { r = r.concat(",\"body\":").concat(ast_to_json(body)) }

    let condition = np_condition.get(id)
    if condition >= 0 { r = r.concat(",\"condition\":").concat(ast_to_json(condition)) }

    let then_body = np_then_body.get(id)
    if then_body >= 0 { r = r.concat(",\"then_body\":").concat(ast_to_json(then_body)) }

    let else_body = np_else_body.get(id)
    if else_body >= 0 { r = r.concat(",\"else_body\":").concat(ast_to_json(else_body)) }

    let scrutinee = np_scrutinee.get(id)
    if scrutinee >= 0 { r = r.concat(",\"scrutinee\":").concat(ast_to_json(scrutinee)) }

    let pattern = np_pattern.get(id)
    if pattern >= 0 { r = r.concat(",\"pattern\":").concat(ast_to_json(pattern)) }

    let guard = np_guard.get(id)
    if guard >= 0 { r = r.concat(",\"guard\":").concat(ast_to_json(guard)) }

    let value = np_value.get(id)
    if value >= 0 { r = r.concat(",\"value\":").concat(ast_to_json(value)) }

    let target = np_target.get(id)
    if target >= 0 { r = r.concat(",\"target\":").concat(ast_to_json(target)) }

    let iterable = np_iterable.get(id)
    if iterable >= 0 { r = r.concat(",\"iterable\":").concat(ast_to_json(iterable)) }

    let start = np_start.get(id)
    if start >= 0 { r = r.concat(",\"start\":").concat(ast_to_json(start)) }

    let end_node = np_end.get(id)
    if end_node >= 0 { r = r.concat(",\"end\":").concat(ast_to_json(end_node)) }

    let obj = np_obj.get(id)
    if obj >= 0 { r = r.concat(",\"obj\":").concat(ast_to_json(obj)) }

    let index = np_index.get(id)
    if index >= 0 { r = r.concat(",\"index\":").concat(ast_to_json(index)) }

    let type_ann = np_type_ann.get(id)
    if type_ann >= 0 { r = r.concat(",\"type_ann\":").concat(ast_to_json(type_ann)) }

    let stmts = np_stmts.get(id)
    if stmts >= 0 { r = r.concat(",\"stmts\":").concat(sublist_to_json(stmts)) }

    let params = np_params.get(id)
    if params >= 0 { r = r.concat(",\"params\":").concat(sublist_to_json(params)) }

    let args = np_args.get(id)
    if args >= 0 { r = r.concat(",\"args\":").concat(sublist_to_json(args)) }

    let elements = np_elements.get(id)
    if elements >= 0 { r = r.concat(",\"elements\":").concat(sublist_to_json(elements)) }

    let fields = np_fields.get(id)
    if fields >= 0 { r = r.concat(",\"fields\":").concat(sublist_to_json(fields)) }

    let methods = np_methods.get(id)
    if methods >= 0 { r = r.concat(",\"methods\":").concat(sublist_to_json(methods)) }

    let arms = np_arms.get(id)
    if arms >= 0 { r = r.concat(",\"arms\":").concat(sublist_to_json(arms)) }

    let handlers = np_handlers.get(id)
    if handlers >= 0 { r = r.concat(",\"handlers\":").concat(sublist_to_json(handlers)) }

    let type_params = np_type_params.get(id)
    if type_params >= 0 { r = r.concat(",\"type_params\":").concat(sublist_to_json(type_params)) }

    let effects = np_effects.get(id)
    if effects >= 0 { r = r.concat(",\"effects\":").concat(sublist_to_json(effects)) }

    let captures = np_captures.get(id)
    if captures >= 0 { r = r.concat(",\"captures\":").concat(sublist_to_json(captures)) }

    let doc = np_doc_comment.get(id)
    if doc != "" { r = r.concat(",\"doc_comment\":\"").concat(ast_json_escape(doc)).concat("\"") }

    let leading = np_leading_comments.get(id)
    if leading != "" { r = r.concat(",\"leading_comments\":\"").concat(ast_json_escape(leading)).concat("\"") }

    r = r.concat("}")
    r
}

fn main() {
    let mut p = argparser_new("pact", "The Pact programming language compiler and toolchain")
    p = add_command(p, "build", "Compile .pact to native binary")
    p = add_command(p, "run", "Build and execute")
    p = add_command(p, "check", "Validate without producing binary")
    p = add_command(p, "test", "Build and run tests (discovers .pact files with test blocks)")
    p = add_command(p, "fmt", "Format source file(s) in place")
    p = add_command(p, "ast", "Dump parsed AST as JSON")
    p = add_command(p, "audit", "Check for capability escalations in dependencies")
    p = add_command(p, "add", "Add a dependency (use --path or --git)")
    p = add_command(p, "remove", "Remove a dependency")
    p = add_command(p, "update", "Re-resolve dependencies and update lockfile")
    p = add_command(p, "daemon", "Compiler daemon (start/status/stop)")
    p = add_command(p, "query", "Query symbol index (uses daemon if running)")

    p = add_flag(p, "--debug", "-d", "Enable debug mode (debug_assert, -g -O0)")
    p = add_flag(p, "--check", "-c", "Check formatting without modifying files")
    p = add_flag(p, "--json", "-j", "JSON output")
    p = add_flag(p, "--pub", "", "Filter to public symbols only")
    p = add_flag(p, "--pure", "", "Filter to pure functions")
    p = add_flag(p, "--dev", "", "Add as dev-dependency")

    p = add_option(p, "--output", "-o", "Output path")
    p = add_option(p, "--format", "-f", "Output format")
    p = add_option(p, "--filter", "", "Test filter pattern")
    p = add_option(p, "--tags", "", "Test tags filter")
    p = add_option(p, "--layer", "", "Query detail level")
    p = add_option(p, "--effect", "", "Filter by effect")
    p = add_option(p, "--module", "-m", "Filter by module")
    p = add_option(p, "--fn", "", "Look up function by name")
    p = add_option(p, "--path", "", "Path dependency source")
    p = add_option(p, "--git", "", "Git dependency source")
    p = add_option(p, "--tag", "", "Git tag")
    p = add_option(p, "--baseline", "", "Audit baseline path")

    let a = argparse(p)

    let err = args_error(a)
    if err == "help" {
        return
    }
    if err != "" {
        io.println("error: {err}")
        return
    }

    let command = args_command(a)
    if command == "" {
        io.println(generate_help(p))
        return
    }

    let source_path = args_positional(a, 0)
    let mut output_path = args_get(a, "output")
    let mut format_flag = args_get(a, "format")
    let filter_pattern = args_get(a, "filter")
    let tags_filter = args_get(a, "tags")
    let dep_path_flag = args_get(a, "path")
    let git_url_flag = args_get(a, "git")
    let git_tag_flag = args_get(a, "tag")
    let dev_flag = if args_has(a, "dev") { 1 } else { 0 }
    let debug_flag = if args_has(a, "debug") { 1 } else { 0 }
    let check_flag = if args_has(a, "check") { 1 } else { 0 }
    let mut query_layer = args_get(a, "layer")
    let query_effect = args_get(a, "effect")
    let query_module = args_get(a, "module")
    let query_fn = args_get(a, "fn")
    let query_pub = if args_has(a, "pub") { 1 } else { 0 }
    let query_pure = if args_has(a, "pure") { 1 } else { 0 }
    let json_output = if args_has(a, "json") { 1 } else { 0 }
    if json_output != 0 && format_flag == "" {
        format_flag = "json"
    }

    if source_path == "" && command != "fmt" && command != "test" && command != "audit" && command != "add" && command != "remove" && command != "update" && command != "daemon" {
        io.println("error: no source file specified")
        io.println(generate_help(p))
        return
    }

    if source_path != "" && command != "add" && command != "remove" && command != "update" && command != "daemon" && !file_exists(source_path) {
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
            if json_output != 0 {
                io.println("\{\"status\":\"ok\",\"output\":\"{output_path}\"}")
            } else {
                io.println("built: {output_path}")
            }
        } else if json_output != 0 {
            io.println("\{\"status\":\"error\"}")
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
        // Try daemon first if running
        let mut daemon_used = 0
        let sock = find_daemon_sock()
        if sock != "" {
            let fd = unix_socket_connect(sock)
            if fd >= 0 {
                socket_write(fd, "\{\"type\":\"check\"}\n")
                let response = socket_read_line(fd)
                unix_socket_close(fd)
                daemon_used = 1
                io.println(response)
            }
        }
        if daemon_used == 0 {
            let pactc = "build/pactc"
            if !file_exists(pactc) {
                io.println("error: compiler not found at build/pactc")
                io.println("  run: ./bootstrap/bootstrap.sh")
                return
            }
            let mut compile_cmd = "{pactc} {source_path} {c_path} --check-only"
            if format_flag != "" {
                compile_cmd = "{compile_cmd} --format {format_flag}"
            }
            let rc = shell_exec(compile_cmd)
            if rc == 0 {
                if json_output != 0 {
                    io.println("\{\"status\":\"ok\",\"file\":\"{source_path}\"}")
                } else {
                    io.println("ok: {source_path}")
                }
            } else {
                if json_output != 0 {
                    io.println("\{\"status\":\"error\",\"file\":\"{source_path}\"}")
                } else {
                    io.println("error: check failed")
                }
            }
        }
    } else if command == "fmt" {
        let pactc = "build/pactc"
        if !file_exists(pactc) {
            io.println("error: compiler not found at build/pactc")
            io.println("  run: ./bootstrap/bootstrap.sh")
            return
        }
        if check_flag == 1 {
            shell_exec("mkdir -p .tmp")
            let mut needs_format: List[Str] = []
            let mut ok_files: List[Str] = []
            if source_path == "" {
                let mut fmt_files: List[Str] = []
                collect_pact_files(".", fmt_files)
                let mut fi = 0
                while fi < fmt_files.len() {
                    let fname = fmt_files.get(fi)
                    let tmp_name = strip_extension(path_basename(fname))
                    let tmp_path = ".tmp/fmt_check_{tmp_name}.pact"
                    let fmt_cmd = "{pactc} {fname} {tmp_path} --emit pact"
                    let rc = shell_exec(fmt_cmd)
                    if rc == 0 {
                        let original = read_file(fname)
                        let formatted = read_file(tmp_path)
                        if original != formatted {
                            needs_format.push(fname)
                            if json_output == 0 {
                                io.println("would reformat: {fname}")
                            }
                        } else {
                            ok_files.push(fname)
                        }
                    } else {
                        if json_output == 0 {
                            io.println("error: formatting failed for {fname}")
                        }
                    }
                    shell_exec("rm -f {tmp_path}")
                    fi = fi + 1
                }
            } else {
                let tmp_path = ".tmp/fmt_check_{name}.pact"
                let fmt_cmd = "{pactc} {source_path} {tmp_path} --emit pact"
                let rc = shell_exec(fmt_cmd)
                if rc == 0 {
                    let original = read_file(source_path)
                    let formatted = read_file(tmp_path)
                    if original != formatted {
                        needs_format.push(source_path)
                        if json_output == 0 {
                            io.println("would reformat: {source_path}")
                        }
                    } else {
                        ok_files.push(source_path)
                    }
                } else {
                    if json_output == 0 {
                        io.println("error: formatting failed")
                    }
                }
                shell_exec("rm -f {tmp_path}")
            }
            if json_output != 0 {
                let mut json_needs = ""
                let mut ni = 0
                while ni < needs_format.len() {
                    if ni > 0 {
                        json_needs = json_needs.concat(",")
                    }
                    json_needs = json_needs.concat("\"").concat(needs_format.get(ni)).concat("\"")
                    ni = ni + 1
                }
                let mut json_ok = ""
                let mut oi = 0
                while oi < ok_files.len() {
                    if oi > 0 {
                        json_ok = json_ok.concat(",")
                    }
                    json_ok = json_ok.concat("\"").concat(ok_files.get(oi)).concat("\"")
                    oi = oi + 1
                }
                io.println("\{\"check\":true,\"needs_format\":[{json_needs}],\"ok\":[{json_ok}]}")
            } else {
                if needs_format.len() > 0 {
                    io.println("{needs_format.len()} file(s) would be reformatted")
                } else {
                    io.println("All files formatted correctly")
                }
            }
            if needs_format.len() > 0 {
                exit(1)
            }
        } else {
            if source_path == "" {
                let mut fmt_files: List[Str] = []
                collect_pact_files(".", fmt_files)
                let mut fmt_ok: List[Str] = []
                let mut fmt_err: List[Str] = []
                let mut fi = 0
                while fi < fmt_files.len() {
                    let fname = fmt_files.get(fi)
                    let fmt_cmd = "{pactc} {fname} {fname} --emit pact"
                    let rc = shell_exec(fmt_cmd)
                    if rc == 0 {
                        if json_output == 0 {
                            io.println("formatted: {fname}")
                        }
                        fmt_ok.push(fname)
                    } else {
                        if json_output == 0 {
                            io.println("error: formatting failed for {fname}")
                        }
                        fmt_err.push(fname)
                    }
                    fi = fi + 1
                }
                if json_output != 0 {
                    let mut ok_json = "["
                    let mut oi = 0
                    while oi < fmt_ok.len() {
                        if oi > 0 {
                            ok_json = ok_json.concat(",")
                        }
                        ok_json = ok_json.concat("\"").concat(fmt_ok.get(oi)).concat("\"")
                        oi = oi + 1
                    }
                    ok_json = ok_json.concat("]")
                    let mut err_json = "["
                    let mut ei = 0
                    while ei < fmt_err.len() {
                        if ei > 0 {
                            err_json = err_json.concat(",")
                        }
                        err_json = err_json.concat("\"").concat(fmt_err.get(ei)).concat("\"")
                        ei = ei + 1
                    }
                    err_json = err_json.concat("]")
                    io.println("\{\"formatted\":{ok_json},\"errors\":{err_json}}")
                }
            } else {
                let compile_cmd = "{pactc} {source_path} {source_path} --emit pact"
                let rc = shell_exec(compile_cmd)
                if rc == 0 {
                    if json_output != 0 {
                        io.println("\{\"formatted\":[\"{source_path}\"],\"errors\":[]}")
                    } else {
                        io.println("formatted: {source_path}")
                    }
                } else {
                    if json_output != 0 {
                        io.println("\{\"formatted\":[],\"errors\":[\"{source_path}\"]}")
                    } else {
                        io.println("error: formatting failed")
                    }
                }
            }
        }
    } else if command == "audit" {
        let baseline_path = args_get(a, "baseline")

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
    } else if command == "query" {
        if query_layer == "" {
            query_layer = "signature"
        }
        let sock_path = find_daemon_sock()
        let sock_fd = if sock_path != "" { unix_socket_connect(sock_path) } else { -1 }
        if sock_fd >= 0 {
            let mut request = ""
            if query_fn != "" {
                request = "\{\"type\":\"query\",\"query_type\":\"fn\",\"name\":\"{query_fn}\"}"
            } else if query_effect != "" {
                request = "\{\"type\":\"query\",\"query_type\":\"effect\",\"effect\":\"{query_effect}\"}"
            } else if query_pub != 0 && query_pure != 0 {
                request = "\{\"type\":\"query\",\"query_type\":\"pub_pure\"}"
            } else if query_pub != 0 {
                let mod_name = if query_module != "" { query_module } else { strip_extension(path_basename(source_path)) }
                request = "\{\"type\":\"query\",\"query_type\":\"signature\",\"module\":\"{mod_name}\"}"
            } else if query_pure != 0 {
                request = "\{\"type\":\"query\",\"query_type\":\"pub_pure\"}"
            } else if query_layer == "signature" {
                let mod_name = if query_module != "" { query_module } else { strip_extension(path_basename(source_path)) }
                request = "\{\"type\":\"query\",\"query_type\":\"signature\",\"module\":\"{mod_name}\"}"
            } else {
                let mod_name = if query_module != "" { query_module } else { strip_extension(path_basename(source_path)) }
                request = "\{\"type\":\"query\",\"query_type\":\"signature\",\"module\":\"{mod_name}\"}"
            }
            socket_write(sock_fd, request.concat("\n"))
            let response = socket_read_line(sock_fd)
            unix_socket_close(sock_fd)
            io.println(response)
        } else {
            let source = read_file(source_path)
            lex(source)
            pos = 0
            diag_source_file = source_path
            let program = parse_program()

            if diag_count > 0 {
                diag_flush()
                io.println("error: parse failed, cannot query")
                exit(1)
            }

            let module_name = strip_extension(path_basename(source_path))
            si_reset()
            si_build(program, source_path, module_name)

            let vis = if query_pub != 0 { 1 } else { -1 }
            let mod_f = if query_module != "" { query_module } else if query_fn == "" { module_name } else { "" }
            let result = query_filtered_layer(query_layer, vis, mod_f, query_effect, query_pure, query_fn)

            io.println(result)
        }
    } else if command == "daemon" {
        let sub_cmd = args_positional(a, 0)
        let daemon_source = args_positional(a, 1)

        if sub_cmd == "" {
            io.println("error: daemon requires a subcommand: start, status, or stop")
            io.println(generate_help(p))
            return
        }

        if sub_cmd == "start" {
            if daemon_source == "" {
                io.println("error: daemon start requires a source file")
                io.println("usage: pact daemon start <file.pact>")
                return
            }
            if !file_exists(daemon_source) {
                io.println("error: file not found: {daemon_source}")
                return
            }
            let root = path_dirname(daemon_source)
            let actual_root = if root == "" { "." } else { root }
            io.println("Daemon starting on .pact/daemon.sock")
            daemon_start(actual_root, daemon_source)
        } else if sub_cmd == "status" {
            let sock_path = find_daemon_sock()
            if sock_path == "" {
                io.println("error: daemon not running (no .pact/daemon.sock found)")
                exit(1)
            }
            let fd = unix_socket_connect(sock_path)
            if fd < 0 {
                io.println("error: daemon not running (could not connect to {sock_path})")
                exit(1)
            }
            socket_write(fd, "\{\"type\":\"status\"}\n")
            let response = socket_read_line(fd)
            unix_socket_close(fd)
            io.println(response)
        } else if sub_cmd == "stop" {
            let sock_path = find_daemon_sock()
            if sock_path == "" {
                io.println("error: daemon not running (no .pact/daemon.sock found)")
                exit(1)
            }
            let fd = unix_socket_connect(sock_path)
            if fd < 0 {
                io.println("error: daemon not running (could not connect to {sock_path})")
                exit(1)
            }
            socket_write(fd, "\{\"type\":\"stop\"}\n")
            let response = socket_read_line(fd)
            unix_socket_close(fd)
            io.println("Daemon stopped")
        }
    } else if command == "ast" {
        let source = read_file(source_path)
        lex(source)
        pos = 0
        diag_source_file = source_path
        let program = parse_program()

        if diag_count > 0 {
            diag_flush()
            io.println("error: parse failed, cannot dump AST")
            exit(1)
        }

        io.println(ast_to_json(program))
    } else {
        io.println("error: unknown command '{command}'")
        io.println(generate_help(p))
    }
}
