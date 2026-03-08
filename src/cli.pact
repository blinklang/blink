import ast
import std.args
import pkg.audit
import pkg.lockfile
import pkg.manifest
import pkg.resolver
import lexer
import parser
import typecheck
import compiler
import codegen
import codegen_types
import formatter
import mutation_analysis
import symbol_index
import query
import diagnostics
import daemon
import docgen

let pact_cli_version: Str = "dev"
let mut lint_cache_mtime: Int = -1
const embedded_llms_full: Str = #embed("../llms-full.md")
const embedded_llms_short: Str = #embed("../llms.md")
const embedded_runtime_h: Str = #embed("../bootstrap/runtime.h")
const embedded_upgrade_cmd: Str = #embed("../templates/claude-commands/pact:upgrade.md")
const embedded_std_args: Str = #embed("../lib/std/args.pact")
const embedded_pkg_audit: Str = #embed("../lib/pkg/audit.pact")
const embedded_pkg_gitdeps: Str = #embed("../lib/pkg/gitdeps.pact")
const embedded_std_http: Str = #embed("../lib/std/http.pact")
const embedded_std_http_client: Str = #embed("../lib/std/http_client.pact")
const embedded_std_http_error: Str = #embed("../lib/std/http_error.pact")
const embedded_std_http_server: Str = #embed("../lib/std/http_server.pact")
const embedded_std_http_types: Str = #embed("../lib/std/http_types.pact")
const embedded_std_json: Str = #embed("../lib/std/json.pact")
const embedded_pkg_lockfile: Str = #embed("../lib/pkg/lockfile.pact")
const embedded_pkg_manifest: Str = #embed("../lib/pkg/manifest.pact")
const embedded_pkg_pathdeps: Str = #embed("../lib/pkg/pathdeps.pact")
const embedded_pkg_resolver: Str = #embed("../lib/pkg/resolver.pact")
const embedded_std_semver: Str = #embed("../lib/std/semver.pact")
const embedded_std_toml: Str = #embed("../lib/std/toml.pact")

fn init_embedded_stdlib() {
    embedded_stdlib.set("args", embedded_std_args)
    embedded_stdlib.set("http", embedded_std_http)
    embedded_stdlib.set("http_client", embedded_std_http_client)
    embedded_stdlib.set("http_error", embedded_std_http_error)
    embedded_stdlib.set("http_server", embedded_std_http_server)
    embedded_stdlib.set("http_types", embedded_std_http_types)
    embedded_stdlib.set("json", embedded_std_json)
    embedded_stdlib.set("semver", embedded_std_semver)
    embedded_stdlib.set("toml", embedded_std_toml)
    embedded_stdlib.set("pkg_audit", embedded_pkg_audit)
    embedded_stdlib.set("pkg_gitdeps", embedded_pkg_gitdeps)
    embedded_stdlib.set("pkg_lockfile", embedded_pkg_lockfile)
    embedded_stdlib.set("pkg_manifest", embedded_pkg_manifest)
    embedded_stdlib.set("pkg_pathdeps", embedded_pkg_pathdeps)
    embedded_stdlib.set("pkg_resolver", embedded_pkg_resolver)
}

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

fn resolve_pact_bin() -> Str {
    let env = get_env("PACT_BIN") ?? ""
    if env != "" { return env }
    if file_exists("bin/pact") { return "bin/pact" }
    return "pact"
}

fn detect_async(source: Str) -> Int {
    if source.contains("async.spawn") || source.contains("async.scope") {
        return 1
    }
    return 0
}


fn detect_sqlite(c_source: Str) -> Int {
    if c_source.contains("PACT_USE_SQLITE") {
        return 1
    }
    return 0
}

fn detect_ffi_libs(c_source: Str) -> List[Str] {
    let mut libs: List[Str] = []
    let marker = "// PACT_FFI_LIB:"
    let mut remaining = c_source
    let mut idx = remaining.index_of(marker)
    while idx != -1 {
        let start = idx + marker.len()
        let tail = remaining.substring(start, remaining.len())
        let nl = tail.index_of("\n")
        if nl == -1 {
            break
        }
        let lib = tail.substring(0, nl)
        libs.push(lib)
        remaining = tail.substring(nl + 1, tail.len())
        idx = remaining.index_of(marker)
    }
    libs
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
        let entry = entries.get(i).unwrap()
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
        let entry = entries.get(i).unwrap()
        if entry.starts_with(".") || entry == "build" || entry == "legacy" || entry == "node_modules" {
            i = i + 1
            continue
        }
        let full_path = path_join(dir, entry)
        if is_dir(full_path) {
            collect_test_files(full_path, results)
        } else if entry.ends_with(".pact") {
            let source = read_file(full_path)
            if source.starts_with("// xtest") {
                i = i + 1
                continue
            }
            if has_test_blocks(source) {
                results.push(full_path)
            }
        }
        i = i + 1
    }
}

fn load_lint_overrides() {
    let mtime = file_mtime("pact.toml")
    if mtime == -1 {
        return
    }
    if mtime != lint_cache_mtime {
        lint_cache_mtime = mtime
        manifest_clear()
        let rc = manifest_load("pact.toml")
        if rc != 0 {
            return
        }
    }
    let mut i = 0
    while i < lint_names.len() {
        lint_set_override(lint_names.get(i).unwrap(), lint_levels.get(i).unwrap())
        i = i + 1
    }
}

fn do_compile(source_path: Str, c_path: Str, format_flag: Str, debug_mode: Int, strict_mode: Int) -> Int ! Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck, Format.Emit, Codegen {
    reset_compiler_state()
    diag_reset()
    load_lint_overrides()
    diag_source_file = source_path

    let source = read_file(source_path)
    lex(source)
    pos = 0
    let program = parse_program()
    loaded_files.push(source_path)

    let src_root = find_src_root(source_path)
    let mut imported_programs: List[Int] = []
    collect_root_imports(program)
    collect_imports(program, src_root, imported_programs)

    let mut final_program = program
    if imported_programs.len() > 0 {
        final_program = merge_programs(program, imported_programs, import_map_nodes)
    }

    if format_flag == "pact" {
        let pact_output = format(final_program)
        write_file(c_path, pact_output)
        return 0
    }

    let _tc_err_count = check_types(final_program)

    check_unused_imports()

    if diag_count > 0 {
        diag_flush()
        return 1
    }
    if diag_warn_count > 0 {
        diag_flush()
        if strict_mode != 0 {
            return 1
        }
    }

    analyze_mutations(final_program)
    analyze_save_restore(final_program)

    if debug_mode != 0 {
        cg_debug_mode = 1
    } else {
        cg_debug_mode = 0
    }

    cg_runtime_header = resolve_runtime_header()

    let c_output = generate(final_program)

    if diag_count > 0 {
        diag_flush()
        return 1
    }
    if diag_warn_count > 0 {
        diag_flush()
        if strict_mode != 0 {
            return 1
        }
    }

    write_file(c_path, c_output)
    return 0
}

fn resolve_runtime_header() -> Str {
    let pact_root = get_env("PACT_ROOT") ?? ""
    if pact_root != "" {
        let path = "{pact_root}/bootstrap/runtime.h"
        if file_exists(path) == 1 {
            return read_file(path)
        }
    }
    if file_exists("build/runtime.h") == 1 {
        return read_file("build/runtime.h")
    }
    if file_exists("bootstrap/runtime.h") == 1 {
        return read_file("bootstrap/runtime.h")
    }
    return embedded_runtime_h
}

fn resolve_target_triple(alias: Str) -> Str {
    if alias == "linux" || alias == "linux-amd64" {
        return "x86_64-linux-gnu"
    }
    if alias == "linux-arm64" {
        return "aarch64-linux-gnu"
    }
    if alias == "macos-arm64" {
        return "aarch64-macos"
    }
    if alias == "macos-amd64" {
        return "x86_64-macos"
    }
    if alias == "macos" {
        let result = process_run("uname", ["-m"])
        let arch = result.out.trim()
        return "{arch}-macos"
    }
    return alias
}

fn do_link_target(out: Str, c_path: Str, link_flags: Str, debug_mode: Int, release_mode: Int, target: Str) -> Int {
    let mut compiler = "cc"
    if target != "" {
        compiler = "zig cc -target {target}"
    }
    let mut cc_cmd = "{compiler} -o {out} {c_path} {link_flags}"
    if debug_mode != 0 {
        cc_cmd = "{compiler} -g -O0 -o {out} {c_path} {link_flags}"
    } else if release_mode != 0 {
        cc_cmd = "{compiler} -O2 -o {out} {c_path} {link_flags}"
    }
    let cc_rc = shell_exec(cc_cmd)
    if cc_rc != 0 {
        io.println("error: C compilation failed")
        return cc_rc
    }
    return 0
}

fn do_build(source_path: Str, output_path: Str, c_path: Str, format_flag: Str, debug_mode: Int, release_mode: Int, emit_mode: Str, targets: List[Str], json_output: Int, strict_mode: Int) -> Int ! Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck, Format.Emit, Codegen {
    shell_exec("rm -f {output_path}")
    let rc = do_compile(source_path, c_path, format_flag, debug_mode, strict_mode)
    if rc != 0 {
        return rc
    }

    if emit_mode == "c" {
        return 0
    }

    let source = read_file(source_path)
    let c_source = read_file(c_path)
    let mut link_flags = "-lm"
    if detect_async(source) {
        link_flags = "-lm -pthread"
    }

    if detect_sqlite(c_source) {
        link_flags = "{link_flags} -lsqlite3"
    }

    let ffi_libs = detect_ffi_libs(c_source)
    let mut ffi_i = 0
    while ffi_i < ffi_libs.len() {
        link_flags = "{link_flags} -l{ffi_libs.get(ffi_i).unwrap()}"
        ffi_i = ffi_i + 1
    }

    if targets.len() <= 1 {
        let mut target = ""
        if targets.len() == 1 {
            target = resolve_target_triple(targets.get(0).unwrap())
        }
        let lrc = do_link_target(output_path, c_path, link_flags, debug_mode, release_mode, target)
        if lrc != 0 {
            return lrc
        }
        if json_output != 0 {
            io.println("\{\"status\":\"ok\",\"output\":\"{output_path}\"}")
        } else {
            io.println("built: {output_path}")
        }
        return 0
    }

    if json_output != 0 {
        io.print("\{\"status\":\"ok\",\"outputs\":[")
    }
    let mut i = 0
    while i < targets.len() {
        let alias = targets.get(i).unwrap()
        let triple = resolve_target_triple(alias)
        let out = "{output_path}-{alias}"
        shell_exec("rm -f {out}")
        let lrc = do_link_target(out, c_path, link_flags, debug_mode, release_mode, triple)
        if lrc != 0 {
            return lrc
        }
        if json_output != 0 {
            if i > 0 {
                io.print(",")
            }
            io.print("\"{out}\"")
        } else {
            io.println("built: {out}")
        }
        i = i + 1
    }
    if json_output != 0 {
        io.println("]}")
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
    let kind = np_kind.get(id).unwrap()
    let kind_name = node_kind_name(kind)
    let mut r = "\{\"kind\":\""
    r = r.concat(ast_json_escape(kind_name)).concat("\"")

    let line = np_line.get(id).unwrap()
    let col = np_col.get(id).unwrap()
    if line > 0 { r = r.concat(",\"line\":{line},\"col\":{col}") }

    let name = np_name.get(id).unwrap()
    if name != "" { r = r.concat(",\"name\":\"").concat(ast_json_escape(name)).concat("\"") }

    let str_val = np_str_val.get(id).unwrap()
    if str_val != "" { r = r.concat(",\"str_val\":\"").concat(ast_json_escape(str_val)).concat("\"") }

    let int_val = np_int_val.get(id).unwrap()
    if kind == NodeKind.IntLit { r = r.concat(",\"int_val\":{int_val}") }
    else if int_val != 0 { r = r.concat(",\"int_val\":{int_val}") }

    let op = np_op.get(id).unwrap()
    if op != "" { r = r.concat(",\"op\":\"").concat(ast_json_escape(op)).concat("\"") }

    let type_name = np_type_name.get(id).unwrap()
    if type_name != "" { r = r.concat(",\"type_name\":\"").concat(ast_json_escape(type_name)).concat("\"") }

    let trait_name = np_trait_name.get(id).unwrap()
    if trait_name != "" { r = r.concat(",\"trait_name\":\"").concat(ast_json_escape(trait_name)).concat("\"") }

    let var_name = np_var_name.get(id).unwrap()
    if var_name != "" { r = r.concat(",\"var_name\":\"").concat(ast_json_escape(var_name)).concat("\"") }

    let method_name = np_method.get(id).unwrap()
    if method_name != "" { r = r.concat(",\"method\":\"").concat(ast_json_escape(method_name)).concat("\"") }

    let return_type = np_return_type.get(id).unwrap()
    if return_type != "" { r = r.concat(",\"return_type\":\"").concat(ast_json_escape(return_type)).concat("\"") }

    if np_is_mut.get(id).unwrap() != 0 { r = r.concat(",\"is_mut\":true") }
    if np_is_pub.get(id).unwrap() != 0 { r = r.concat(",\"is_pub\":true") }
    if np_inclusive.get(id).unwrap() != 0 { r = r.concat(",\"inclusive\":true") }

    let left = np_left.get(id).unwrap()
    if left >= 0 { r = r.concat(",\"left\":").concat(ast_to_json(left)) }

    let right = np_right.get(id).unwrap()
    if right >= 0 { r = r.concat(",\"right\":").concat(ast_to_json(right)) }

    let body = np_body.get(id).unwrap()
    if body >= 0 { r = r.concat(",\"body\":").concat(ast_to_json(body)) }

    let condition = np_condition.get(id).unwrap()
    if condition >= 0 { r = r.concat(",\"condition\":").concat(ast_to_json(condition)) }

    let then_body = np_then_body.get(id).unwrap()
    if then_body >= 0 { r = r.concat(",\"then_body\":").concat(ast_to_json(then_body)) }

    let else_body = np_else_body.get(id).unwrap()
    if else_body >= 0 { r = r.concat(",\"else_body\":").concat(ast_to_json(else_body)) }

    let scrutinee = np_scrutinee.get(id).unwrap()
    if scrutinee >= 0 { r = r.concat(",\"scrutinee\":").concat(ast_to_json(scrutinee)) }

    let pattern = np_pattern.get(id).unwrap()
    if pattern >= 0 { r = r.concat(",\"pattern\":").concat(ast_to_json(pattern)) }

    let guard = np_guard.get(id).unwrap()
    if guard >= 0 { r = r.concat(",\"guard\":").concat(ast_to_json(guard)) }

    let value = np_value.get(id).unwrap()
    if value >= 0 { r = r.concat(",\"value\":").concat(ast_to_json(value)) }

    let target = np_target.get(id).unwrap()
    if target >= 0 { r = r.concat(",\"target\":").concat(ast_to_json(target)) }

    let iterable = np_iterable.get(id).unwrap()
    if iterable >= 0 { r = r.concat(",\"iterable\":").concat(ast_to_json(iterable)) }

    let start = np_start.get(id).unwrap()
    if start >= 0 { r = r.concat(",\"start\":").concat(ast_to_json(start)) }

    let end_node = np_end.get(id).unwrap()
    if end_node >= 0 { r = r.concat(",\"end\":").concat(ast_to_json(end_node)) }

    let obj = np_obj.get(id).unwrap()
    if obj >= 0 { r = r.concat(",\"obj\":").concat(ast_to_json(obj)) }

    let index = np_index.get(id).unwrap()
    if index >= 0 { r = r.concat(",\"index\":").concat(ast_to_json(index)) }

    let type_ann = np_type_ann.get(id).unwrap()
    if type_ann >= 0 { r = r.concat(",\"type_ann\":").concat(ast_to_json(type_ann)) }

    let stmts = np_stmts.get(id).unwrap()
    if stmts >= 0 { r = r.concat(",\"stmts\":").concat(sublist_to_json(stmts)) }

    let params = np_params.get(id).unwrap()
    if params >= 0 { r = r.concat(",\"params\":").concat(sublist_to_json(params)) }

    let args = np_args.get(id).unwrap()
    if args >= 0 { r = r.concat(",\"args\":").concat(sublist_to_json(args)) }

    let elements = np_elements.get(id).unwrap()
    if elements >= 0 { r = r.concat(",\"elements\":").concat(sublist_to_json(elements)) }

    let fields = np_fields.get(id).unwrap()
    if fields >= 0 { r = r.concat(",\"fields\":").concat(sublist_to_json(fields)) }

    let methods = np_methods.get(id).unwrap()
    if methods >= 0 { r = r.concat(",\"methods\":").concat(sublist_to_json(methods)) }

    let arms = np_arms.get(id).unwrap()
    if arms >= 0 { r = r.concat(",\"arms\":").concat(sublist_to_json(arms)) }

    let handlers = np_handlers.get(id).unwrap()
    if handlers >= 0 { r = r.concat(",\"handlers\":").concat(sublist_to_json(handlers)) }

    let type_params = np_type_params.get(id).unwrap()
    if type_params >= 0 { r = r.concat(",\"type_params\":").concat(sublist_to_json(type_params)) }

    let effects = np_effects.get(id).unwrap()
    if effects >= 0 { r = r.concat(",\"effects\":").concat(sublist_to_json(effects)) }

    let captures = np_captures.get(id).unwrap()
    if captures >= 0 { r = r.concat(",\"captures\":").concat(sublist_to_json(captures)) }

    let doc = np_doc_comment.get(id).unwrap()
    if doc != "" { r = r.concat(",\"doc_comment\":\"").concat(ast_json_escape(doc)).concat("\"") }

    let leading = np_leading_comments.get(id).unwrap()
    if leading != "" { r = r.concat(",\"leading_comments\":\"").concat(ast_json_escape(leading)).concat("\"") }

    r = r.concat("}")
    r
}

fn main() {
    init_embedded_stdlib()
    let mut p = argparser_new("pact", "The Pact programming language compiler and toolchain")
    p = add_command(p, "init", "Initialize a new Pact project")
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
    p = add_command(p, "daemon.start", "Start compiler daemon")
    p = add_command(p, "daemon.status", "Show daemon status")
    p = add_command(p, "daemon.stop", "Stop compiler daemon")
    p = command_add_positional(p, "daemon.start", "file", "Source file to watch")
    p = add_command(p, "query", "Query symbol index (uses daemon if running)")
    p = add_command(p, "doc", "Print module documentation")
    p = add_command(p, "llms", "Print LLM language reference to stdout")
    p = add_command(p, "explain", "Explain an error or warning code")
    p = command_add_positional(p, "explain", "code", "Error code (e.g. E0500)")

    p = add_flag(p, "--help", "-h", "Print help")
    p = set_version(p, pact_cli_version)

    p = command_add_flag(p, "build", "--debug", "-d", "Enable debug mode (debug_assert, -g -O0)")
    p = command_add_flag(p, "run", "--debug", "-d", "Enable debug mode (debug_assert, -g -O0)")
    p = command_add_flag(p, "build", "--release", "-R", "Optimized production build (-O2)")
    p = command_add_flag(p, "run", "--release", "-R", "Optimized production build (-O2)")

    p = command_add_flag(p, "build", "--json", "-j", "JSON output")
    p = command_add_flag(p, "check", "--json", "-j", "JSON output")
    p = command_add_flag(p, "test", "--json", "-j", "JSON output")
    p = command_add_flag(p, "fmt", "--json", "-j", "JSON output")
    p = command_add_flag(p, "doc", "--json", "-j", "JSON output")
    p = command_add_flag(p, "doc", "--list", "-l", "List available stdlib modules")
    p = command_add_flag(p, "query", "--json", "-j", "JSON output")

    p = command_add_option(p, "build", "--output", "-o", "Output path")
    p = command_add_option(p, "run", "--output", "-o", "Output path")

    p = command_add_option(p, "build", "--target", "-T", "Target triple (e.g. linux, macos-arm64)")
    p = command_add_option(p, "run", "--target", "-T", "Target triple (e.g. linux, macos-arm64)")
    p = command_add_option(p, "build", "--emit", "-e", "Output format: binary (default) or c")

    p = command_add_option(p, "build", "--format", "-f", "Output format")
    p = command_add_option(p, "check", "--format", "-f", "Output format")
    p = command_add_option(p, "fmt", "--format", "-f", "Output format")

    p = command_add_flag(p, "llms", "--list", "", "List available topics")
    p = command_add_flag(p, "llms", "--full", "", "Print full reference (default is short summary)")
    p = command_add_option(p, "llms", "--topic", "", "Print a specific topic section")

    p = command_add_flag(p, "build", "--strict", "", "Treat warnings as errors")
    p = command_add_flag(p, "check", "--strict", "", "Treat warnings as errors")
    p = command_add_flag(p, "run", "--strict", "", "Treat warnings as errors")

    p = command_add_flag(p, "fmt", "--check", "-c", "Check formatting without modifying files")

    p = command_add_flag(p, "query", "--pub", "", "Filter to public symbols only")
    p = command_add_flag(p, "query", "--pure", "", "Filter to pure functions")
    p = command_add_option(p, "query", "--layer", "", "Query detail level")
    p = command_add_option(p, "query", "--effect", "", "Filter by effect")
    p = command_add_option(p, "query", "--module", "-m", "Filter by module")
    p = command_add_option(p, "query", "--fn", "", "Look up function by name")

    p = command_add_flag(p, "add", "--dev", "", "Add as dev-dependency")
    p = command_add_option(p, "add", "--path", "", "Path dependency source")
    p = command_add_option(p, "add", "--git", "", "Git dependency source")
    p = command_add_option(p, "add", "--tag", "", "Git tag")

    p = command_add_option(p, "test", "--filter", "", "Test filter pattern")
    p = command_add_option(p, "test", "--tags", "", "Test tags filter")
    p = command_add_option(p, "test", "--parallel", "-P", "Parallel workers (default: 4)")

    p = command_add_option(p, "audit", "--baseline", "", "Audit baseline path")

    let a = argparse(p)

    let err = args_error(a)
    if err == "help" || err == "version" {
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
    let parallel_str = args_get(a, "parallel")
    let mut num_workers = 4
    if parallel_str != "" {
        num_workers = parallel_str.to_int()
    }
    if num_workers < 1 {
        num_workers = 1
    }
    let dep_path_flag = args_get(a, "path")
    let git_url_flag = args_get(a, "git")
    let git_tag_flag = args_get(a, "tag")
    let dev_flag = if args_has(a, "dev") { 1 } else { 0 }
    let debug_flag = if args_has(a, "debug") { 1 } else { 0 }
    let release_flag = if args_has(a, "release") { 1 } else { 0 }
    let check_flag = if args_has(a, "check") { 1 } else { 0 }
    let strict_flag = if args_has(a, "strict") { 1 } else { 0 }
    let mut query_layer = args_get(a, "layer")
    let query_effect = args_get(a, "effect")
    let query_module = args_get(a, "module")
    let query_fn = args_get(a, "fn")
    let query_pub = if args_has(a, "pub") { 1 } else { 0 }
    let query_pure = if args_has(a, "pure") { 1 } else { 0 }
    let json_output = if args_has(a, "json") { 1 } else { 0 }
    let targets = args_get_all(a, "target")
    let emit_flag = args_get(a, "emit")
    if json_output != 0 && format_flag == "" {
        format_flag = "json"
    }

    if debug_flag != 0 && release_flag != 0 {
        io.eprintln("error: --debug and --release are mutually exclusive")
        exit(1)
    }

    if source_path == "" && command != "init" && command != "llms" && command != "explain" && command != "doc" && command != "fmt" && command != "test" && command != "audit" && command != "add" && command != "remove" && command != "update" && command != "daemon start" && command != "daemon status" && command != "daemon stop" && command != "daemon" {
        io.println("error: no source file specified")
        io.println(generate_help(p))
        return
    }

    if source_path != "" && command != "init" && command != "llms" && command != "explain" && command != "doc" && command != "add" && command != "remove" && command != "update" && command != "daemon start" && !file_exists(source_path) {
        io.eprintln("error: file not found: {source_path}")
        exit(1)
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

    if command == "init" {
        let project_name = if source_path != "" {
            source_path
        } else {
            let pwd_result = process_run("pwd", [])
            path_basename(pwd_result.out.trim())
        }

        let already_initialized = file_exists("pact.toml")

        if already_initialized == 0 {
            // Create pact.toml
            let toml_content = "[package]\nname = \"{project_name}\"\nversion = \"0.1.0\"\npact-version = \"{pact_cli_version}\"\n\n[dependencies]\n"
            write_file("pact.toml", toml_content)
            io.println("  created pact.toml")

            // Create src/main.pact if it doesn't exist
            if file_exists("src") == 0 {
                shell_exec("mkdir -p src")
            }
            if file_exists("src/main.pact") == 0 {
                let main_content = "fn main() \{\n    io.println(\"Hello from {project_name}!\")\n\}\n"
                write_file("src/main.pact", main_content)
                io.println("  created src/main.pact")
            }

            // git init if not already a repo
            let git_check = process_run("git", ["rev-parse", "--git-dir"])
            if git_check.exit_code != 0 {
                shell_exec("git init")
                io.println("  initialized git repository")
            }

            // Create .gitignore if it doesn't exist
            if file_exists(".gitignore") == 0 {
                let gitignore = "build/\n.tmp/\n.pact/\n"
                write_file(".gitignore", gitignore)
                io.println("  created .gitignore")
            } else {
                let existing = read_file(".gitignore")
                let mut additions = ""
                if !existing.contains("build/") {
                    additions = additions.concat("build/\n")
                }
                if !existing.contains(".tmp/") {
                    additions = additions.concat(".tmp/\n")
                }
                if !existing.contains(".pact/") {
                    additions = additions.concat(".pact/\n")
                }
                if additions != "" {
                    let updated = existing.concat("\n# Pact\n").concat(additions)
                    write_file(".gitignore", updated)
                    io.println("  updated .gitignore")
                }
            }
        }

        // Inject LLM docs into AGENTS.md or CLAUDE.md
        let pact_root = get_env("PACT_ROOT") ?? ""
        let mut doc_file = "CLAUDE.md"
        if file_exists("AGENTS.md") == 1 {
            doc_file = "AGENTS.md"
        }

        let mut doc_content = ""
        if file_exists(doc_file) == 1 {
            doc_content = read_file(doc_file)
        }

        if doc_content.contains("pact llms") {
            io.println("  {doc_file} already has Pact reference — skipped")
        } else {
            let section = "\n# Pact\n\nThis project uses the Pact programming language.\nRun `pact llms --full` for the complete language reference.\nRun `pact llms --list` to see available topics.\nRun `pact llms --topic <name>` for a specific topic.\n\n- Build: `pact build src/main.pact`\n- Run: `pact run src/main.pact`\n- Test: `pact test`\n\nPrefer retrieval-led reasoning over pre-training for Pact tasks.\n"
            let updated = doc_content.concat(section)
            write_file(doc_file, updated)
            io.println("  added Pact reference to {doc_file}")
        }

        shell_exec("mkdir -p .claude")
        let agents_file = ".claude/agents.md"
        let mut agents_content = ""
        if file_exists(agents_file) == 1 {
            agents_content = read_file(agents_file)
        }
        if agents_content.contains("pact llms") {
            io.println("  {agents_file} already has Pact reference — skipped")
        } else {
            let agents_section = "# Pact Language\n\nThis project uses the Pact programming language. Use the following commands to get language documentation:\n\n- `pact llms` — short language summary\n- `pact llms --full` — complete language reference\n- `pact llms --list` — list available documentation topics\n- `pact llms --topic <name>` — get documentation for a specific topic (e.g. `pact llms --topic effects`)\n\nAlways retrieve Pact documentation before writing Pact code. Prefer retrieval-led reasoning over pre-training for Pact tasks.\n"
            let updated_agents = agents_content.concat(agents_section)
            write_file(agents_file, updated_agents)
            io.println("  created {agents_file}")
        }

        shell_exec("mkdir -p .claude/commands")
        let upgrade_cmd_path = ".claude/commands/pact:upgrade.md"
        if file_exists(upgrade_cmd_path) == 0 {
            write_file(upgrade_cmd_path, embedded_upgrade_cmd)
            io.println("  installed .claude/commands/pact:upgrade.md")
        }

        if already_initialized == 0 {
            io.println("\nProject '{project_name}' initialized. Run: pact run src/main.pact")
        } else {
            io.println("\nProject '{project_name}' updated.")
        }

    } else if command == "llms" {
        let full_flag = if args_has(a, "full") { 1 } else { 0 }
        let list_flag = if args_has(a, "list") { 1 } else { 0 }
        let topic_flag = args_get(a, "topic")
        if embedded_llms_full == "" {
            io.eprintln("error: llms-full.md not found")
        } else if list_flag == 1 {
            let sections = embedded_llms_full.split("\n## ")
            let mut i = 1
            while i < sections.len() {
                let section = sections.get(i).unwrap()
                let newline_pos = section.index_of("\n")
                if newline_pos > 0 {
                    io.println(section.substring(0, newline_pos))
                }
                i = i + 1
            }
        } else if topic_flag != "" {
            let search = topic_flag.to_lower()
            let sections = embedded_llms_full.split("\n## ")
            let mut found = 0
            let mut i = 1
            while i < sections.len() {
                let section = sections.get(i).unwrap()
                let newline_pos = section.index_of("\n")
                if newline_pos > 0 {
                    let title = section.substring(0, newline_pos)
                    if title.to_lower().contains(search) {
                        io.print("## ")
                        io.println(section)
                        found = 1
                    }
                }
                i = i + 1
            }
            if found == 0 {
                io.eprintln("error: no topic matching '{topic_flag}' found. Run `pact llms --list` to see topics.")
            }
        } else if full_flag == 1 {
            io.print(embedded_llms_full)
        } else {
            if embedded_llms_short != "" {
                io.print(embedded_llms_short)
            } else {
                io.eprintln("error: llms.md not found")
            }
        }

    } else if command == "build" {
        let rc = do_build(source_path, output_path, c_path, format_flag, debug_flag, release_flag, emit_flag, targets, json_output, strict_flag)
        if rc == 0 {
            if emit_flag == "c" {
                if json_output != 0 {
                    io.println("\{\"status\":\"ok\",\"output\":\"{c_path}\"}")
                } else {
                    io.println("emitted: {c_path}")
                }
            }
        } else {
            if json_output != 0 {
                io.println("\{\"status\":\"error\"}")
            }
            exit(1)
        }
    } else if command == "run" {
        if targets.len() > 1 {
            io.eprintln("error: 'run' does not support multiple targets")
            exit(1)
        }
        let rc = do_build(source_path, output_path, c_path, format_flag, debug_flag, release_flag, "", targets, 0, strict_flag)
        if rc != 0 {
            exit(1)
        }
        let rest = args_rest(a)
        process_exec(output_path, rest)
    } else if command == "test" {
        if source_path != "" && is_dir(source_path) == 0 {
            let rc = do_build(source_path, output_path, c_path, format_flag, 1, 0, "", targets, 0, 0)
            if rc != 0 {
                exit(1)
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

        let mut test_dir = "."
        if source_path != "" {
            test_dir = source_path
        }
        let mut test_files: List[Str] = []
        collect_test_files(test_dir, test_files)
        let file_count = test_files.len()

        if file_count == 0 {
            if json_output != 0 {
                io.println("\{\"files\":[],\"summary\":\{\"files\":0,\"files_passed\":0,\"files_failed\":0,\"build_errors\":0}}")
            } else {
                io.println("error: no files with test blocks found")
            }
            exit(1)
        }

        let pact_bin = resolve_pact_bin()

        // Phase A: discovery — compute paths, build args, create dirs
        let mut build_args: List[List[Str]] = []
        let mut run_args: List[List[Str]] = []
        let mut output_bins: List[Str] = []
        let mut fi = 0
        while fi < file_count {
            let tf = test_files.get(fi).unwrap()
            let tf_dir = path_dirname(tf)
            let tf_base = strip_extension(path_basename(tf))
            let mut build_dir = "build"
            if tf_dir != "." && tf_dir != "" {
                build_dir = "build/{tf_dir}"
            }
            shell_exec("mkdir -p {build_dir}")
            let tf_out = "{build_dir}/{tf_base}"
            output_bins.push(tf_out)

            let mut ba: List[Str] = ["build", tf, "-o", tf_out, "--debug"]
            build_args.push(ba)

            let source = read_file(tf)
            let mut ra: List[Str] = []
            if source.contains("fn main(") {
                ra.push("--test")
            }
            if filter_pattern != "" {
                ra.push("--test-filter")
                ra.push(filter_pattern)
            }
            if json_output != 0 {
                ra.push("--test-json")
            }
            if tags_filter != "" {
                ra.push("--test-tags")
                ra.push(tags_filter)
            }
            run_args.push(ra)
            fi = fi + 1
        }

        // Phase B: parallel build + run
        let mut exit_codes: List[Int] = []
        let mut outputs: List[Str] = []
        let mut errors: List[Str] = []
        let mut pi = 0
        while pi < file_count {
            exit_codes.push(-1)
            outputs.push("")
            errors.push("")
            pi = pi + 1
        }

        let sem = Channel(num_workers)
        let mut ti = 0
        while ti < num_workers {
            sem.send(1)
            ti = ti + 1
        }

        async.scope {
            let mut si = 0
            while si < file_count {
                let idx = si
                let bcmd = build_args.get(si).unwrap()
                let rcmd = run_args.get(si).unwrap()
                let bin_path = output_bins.get(si).unwrap()
                async.spawn(fn() {
                    sem.recv()
                    let br = process_run(pact_bin, bcmd)
                    if br.exit_code != 0 || !file_exists(bin_path) {
                        let mut err_text = br.out
                        if br.err_out != "" {
                            if err_text != "" {
                                err_text = "{err_text}\n{br.err_out}"
                            } else {
                                err_text = br.err_out
                            }
                        }
                        errors.set(idx, err_text)
                        sem.send(1)
                        return 0
                    }
                    let rr = process_run(bin_path, rcmd)
                    exit_codes.set(idx, rr.exit_code)
                    outputs.set(idx, rr.out)
                    sem.send(1)
                    0
                })
                si = si + 1
            }
        }

        // Phase C: report results
        let mut total_passed = 0
        let mut total_failed = 0
        let mut total_errors = 0

        if json_output != 0 {
            io.println("\{\"files\":[")
        }

        let mut ri = 0
        let mut json_first = 1
        while ri < file_count {
            let tf = test_files.get(ri).unwrap()
            let ec = exit_codes.get(ri).unwrap()
            if ec == -1 {
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
                    let err_msg = errors.get(ri).unwrap()
                    if err_msg != "" {
                        io.println(err_msg)
                    }
                    io.println("")
                }
            } else {
                if json_output == 0 {
                    io.println("--- {tf} ---")
                    let out = outputs.get(ri).unwrap()
                    if out != "" {
                        io.println(out)
                    }
                } else {
                    if json_first == 0 {
                        io.println(",")
                    }
                    json_first = 0
                    let out = outputs.get(ri).unwrap().trim()
                    io.println("\{\"file\":\"{tf}\",\"results\":{out}}")
                }
                if ec != 0 {
                    total_failed = total_failed + 1
                } else {
                    total_passed = total_passed + 1
                }
            }
            ri = ri + 1
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
            reset_compiler_state()
            diag_reset()
            load_lint_overrides()
            diag_source_file = source_path
            if format_flag != "" {
                diag_format = 1
            }

            let source = read_file(source_path)
            lex(source)
            pos = 0
            let program = parse_program()
            loaded_files.push(source_path)

            let src_root = find_src_root(source_path)
            let mut imported_programs: List[Int] = []
            collect_root_imports(program)
            collect_imports(program, src_root, imported_programs)

            let mut final_program = program
            if imported_programs.len() > 0 {
                final_program = merge_programs(program, imported_programs, import_map_nodes)
            }

            check_types(final_program)

            check_unused_imports()

            if diag_count > 0 {
                diag_flush()
                if json_output != 0 {
                    io.println("\{\"status\":\"error\",\"file\":\"{source_path}\"}")
                } else {
                    io.println("error: check failed")
                }
                exit(1)
            } else if strict_flag != 0 && diag_warn_count > 0 {
                diag_flush()
                if json_output != 0 {
                    io.println("\{\"status\":\"error\",\"file\":\"{source_path}\"}")
                } else {
                    io.println("error: check failed (warnings treated as errors in --strict mode)")
                }
                exit(1)
            } else {
                diag_flush()
                if json_output != 0 {
                    io.println("\{\"status\":\"ok\",\"file\":\"{source_path}\"}")
                } else {
                    io.println("ok: {source_path}")
                }
            }
        }
    } else if command == "fmt" {
        if check_flag == 1 {
            shell_exec("mkdir -p .tmp")
            let mut needs_format: List[Str] = []
            let mut ok_files: List[Str] = []
            if source_path == "" {
                let mut fmt_files: List[Str] = []
                collect_pact_files(".", fmt_files)
                let mut fi = 0
                while fi < fmt_files.len() {
                    let fname = fmt_files.get(fi).unwrap()
                    let tmp_name = strip_extension(path_basename(fname))
                    let tmp_path = ".tmp/fmt_check_{tmp_name}.pact"
                    let rc = do_compile(fname, tmp_path, "pact", 0, 0)
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
                let rc = do_compile(source_path, tmp_path, "pact", 0, 0)
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
                    json_needs = json_needs.concat("\"").concat(needs_format.get(ni).unwrap()).concat("\"")
                    ni = ni + 1
                }
                let mut json_ok = ""
                let mut oi = 0
                while oi < ok_files.len() {
                    if oi > 0 {
                        json_ok = json_ok.concat(",")
                    }
                    json_ok = json_ok.concat("\"").concat(ok_files.get(oi).unwrap()).concat("\"")
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
                    let fname = fmt_files.get(fi).unwrap()
                    let rc = do_compile(fname, fname, "pact", 0, 0)
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
                        ok_json = ok_json.concat("\"").concat(fmt_ok.get(oi).unwrap()).concat("\"")
                        oi = oi + 1
                    }
                    ok_json = ok_json.concat("]")
                    let mut err_json = "["
                    let mut ei = 0
                    while ei < fmt_err.len() {
                        if ei > 0 {
                            err_json = err_json.concat(",")
                        }
                        err_json = err_json.concat("\"").concat(fmt_err.get(ei).unwrap()).concat("\"")
                        ei = ei + 1
                    }
                    err_json = err_json.concat("]")
                    io.println("\{\"formatted\":{ok_json},\"errors\":{err_json}}")
                }
            } else {
                let rc = do_compile(source_path, source_path, "pact", 0, 0)
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

        let resolve_rc = resolve_and_lock(".", pact_cli_version)
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

        let resolve_rc = resolve_and_lock(".", pact_cli_version)
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

        let resolve_rc = resolve_and_lock(".", pact_cli_version)
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
    } else if command == "doc" {
        let list_flag = if args_has(a, "list") { 1 } else { 0 }
        if list_flag == 1 {
            io.println("Standard library modules:")
            io.println("  std.args        CLI argument parsing")
            io.println("  std.http        HTTP client and server")
            io.println("  std.json        JSON parser and serializer")
            io.println("  std.semver      Semantic version parsing")
            io.println("  std.toml        TOML parser")
            io.println("")
            io.println("Run: pact doc <module>  (e.g. pact doc std.args)")
            return
        }
        let module_name = source_path
        if module_name == "" {
            io.println("error: pact doc requires a module name")
            io.println("usage: pact doc <module>  (e.g. pact doc std.args)")
            io.println("       pact doc --list    (list available modules)")
            return
        }
        reset_compiler_state()
        diag_reset()
        let file_path = resolve_module_path(module_name, "src/")
        if file_path == "" {
            diag_flush()
            return
        }
        let mut source = ""
        if file_path.starts_with("<embedded:") {
            let key = file_path.substring(10, file_path.len() - 11)
            source = embedded_stdlib.get(key)
        } else {
            source = read_file(file_path)
        }
        if source == "" {
            io.println("error: could not read module: {module_name}")
            return
        }
        lex(source)
        pos = 0
        diag_source_file = file_path
        let program = parse_program()
        if diag_count > 0 {
            diag_flush()
            io.println("error: parse failed for module: {module_name}")
            return
        }
        let result = generate_doc(program, module_name, json_output)
        io.println(result)
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
    } else if command == "daemon start" {
        let daemon_source = args_positional(a, 0)
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
    } else if command == "daemon status" {
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
    } else if command == "daemon stop" {
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
    } else if command == "daemon" {
        io.println("error: daemon requires a subcommand: start, status, or stop")
        io.println(generate_command_help(p, "daemon"))
    } else if command == "explain" {
        let code = source_path
        if code == "" {
            io.println("usage: pact explain <code>")
            io.println("example: pact explain E0500")
            return
        }
        let explanation = diag_explain(code)
        if explanation == "" {
            io.println("unknown error code: {code}")
            exit(1)
        }
        io.println(explanation)
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
