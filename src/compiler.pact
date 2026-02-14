import lexer
import parser
import typecheck
import codegen
import formatter
import diagnostics

// compiler.pact — Self-hosting Pact compiler driver
//
// Ties together lexer, parser, and codegen into a complete compiler.
// Reads a .pact source file, lexes, parses, generates C, and writes output.
//
// Usage (once compiled): ./pactc <source.pact> [output.c]
// If no output file given, writes to stdout.

fn dots_to_slashes(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        if s.char_at(i) == 46 {
            result = result.concat("/")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

fn find_src_root(source_path: Str) -> Str {
    let mut i = 0
    while i < source_path.len() - 4 {
        if source_path.char_at(i) == 47 && source_path.substring(i, 5) == "/src/" {
            return source_path.substring(0, i + 5)
        }
        i = i + 1
    }
    if source_path.len() >= 4 && source_path.substring(0, 4) == "src/" {
        return "src/"
    }
    path_dirname(source_path)
}

fn resolve_module_path(dotted_path: Str, src_root: Str) -> Str {
    let rel = dots_to_slashes(dotted_path)
    let full = path_join(src_root, rel.concat(".pact"))
    if file_exists(full) == 1 {
        return full
    }
    if dotted_path.starts_with("std.") {
        let compiler_dir = path_dirname(get_arg(0))
        let std_rel = dots_to_slashes(dotted_path.substring(4, dotted_path.len() - 4))
        let std_full = path_join(compiler_dir, path_join("lib/std", std_rel.concat(".pact")))
        if file_exists(std_full) == 1 {
            return std_full
        }
    }
    diag_error_no_loc("ModuleNotFound", "E1200", "module not found: {dotted_path} (looked at: {full})", "")
    ""
}

fn should_import_item(item: Int, import_node: Int) -> Int {
    let names_sl = np_args.get(import_node)
    if names_sl == -1 {
        return 1
    }
    let item_name = np_name.get(item)
    let mut i = 0
    while i < sublist_length(names_sl) {
        let name_node = sublist_get(names_sl, i)
        if np_name.get(name_node) == item_name {
            return 1
        }
        i = i + 1
    }
    0
}

fn merge_programs(main_prog: Int, imported: List[Int], import_nodes_list: List[Int]) -> Int {
    let mut all_fns: List[Int] = []
    let mut all_types: List[Int] = []
    let mut all_lets: List[Int] = []
    let mut all_traits: List[Int] = []
    let mut all_impls: List[Int] = []

    let mut pi = 0
    while pi < imported.len() {
        let prog = imported.get(pi)
        let imp_node = import_nodes_list.get(pi)

        let fns_sl = np_params.get(prog)
        let mut fi = 0
        while fi < sublist_length(fns_sl) {
            let f = sublist_get(fns_sl, fi)
            if should_import_item(f, imp_node) == 1 {
                all_fns.push(f)
            }
            fi = fi + 1
        }

        let types_sl = np_fields.get(prog)
        let mut ti = 0
        while ti < sublist_length(types_sl) {
            let t = sublist_get(types_sl, ti)
            if should_import_item(t, imp_node) == 1 {
                all_types.push(t)
            }
            ti = ti + 1
        }

        let lets_sl = np_stmts.get(prog)
        let mut li = 0
        while li < sublist_length(lets_sl) {
            let l = sublist_get(lets_sl, li)
            if should_import_item(l, imp_node) == 1 {
                all_lets.push(l)
            }
            li = li + 1
        }

        let traits_sl = np_arms.get(prog)
        let mut tri = 0
        while tri < sublist_length(traits_sl) {
            let tr = sublist_get(traits_sl, tri)
            if should_import_item(tr, imp_node) == 1 {
                all_traits.push(tr)
            }
            tri = tri + 1
        }

        let impls_sl = np_methods.get(prog)
        let mut ii = 0
        while ii < sublist_length(impls_sl) {
            all_impls.push(sublist_get(impls_sl, ii))
            ii = ii + 1
        }

        pi = pi + 1
    }

    let main_fns = np_params.get(main_prog)
    let mut fi = 0
    while fi < sublist_length(main_fns) {
        all_fns.push(sublist_get(main_fns, fi))
        fi = fi + 1
    }
    let main_types = np_fields.get(main_prog)
    let mut ti = 0
    while ti < sublist_length(main_types) {
        all_types.push(sublist_get(main_types, ti))
        ti = ti + 1
    }
    let main_lets = np_stmts.get(main_prog)
    let mut li = 0
    while li < sublist_length(main_lets) {
        all_lets.push(sublist_get(main_lets, li))
        li = li + 1
    }
    let main_traits = np_arms.get(main_prog)
    let mut tri = 0
    while tri < sublist_length(main_traits) {
        all_traits.push(sublist_get(main_traits, tri))
        tri = tri + 1
    }
    let main_impls = np_methods.get(main_prog)
    let mut ii = 0
    while ii < sublist_length(main_impls) {
        all_impls.push(sublist_get(main_impls, ii))
        ii = ii + 1
    }

    let merged_fns = new_sublist()
    fi = 0
    while fi < all_fns.len() {
        sublist_push(merged_fns, all_fns.get(fi))
        fi = fi + 1
    }
    finalize_sublist(merged_fns)

    let merged_types = new_sublist()
    ti = 0
    while ti < all_types.len() {
        sublist_push(merged_types, all_types.get(ti))
        ti = ti + 1
    }
    finalize_sublist(merged_types)

    let merged_lets = new_sublist()
    li = 0
    while li < all_lets.len() {
        sublist_push(merged_lets, all_lets.get(li))
        li = li + 1
    }
    finalize_sublist(merged_lets)

    let merged_traits = new_sublist()
    tri = 0
    while tri < all_traits.len() {
        sublist_push(merged_traits, all_traits.get(tri))
        tri = tri + 1
    }
    finalize_sublist(merged_traits)

    let merged_impls = new_sublist()
    ii = 0
    while ii < all_impls.len() {
        sublist_push(merged_impls, all_impls.get(ii))
        ii = ii + 1
    }
    finalize_sublist(merged_impls)

    let merged = new_node(NodeKind.Program)
    np_params.pop()
    np_params.push(merged_fns)
    np_fields.pop()
    np_fields.push(merged_types)
    np_stmts.pop()
    np_stmts.push(merged_lets)
    np_arms.pop()
    np_arms.push(merged_traits)
    np_methods.pop()
    np_methods.push(merged_impls)
    merged
}

let mut loaded_files: List[Str] = []
let mut import_map_paths: List[Str] = []
let mut import_map_nodes: List[Int] = []

fn is_file_loaded(path: Str) -> Int {
    let mut i = 0
    while i < loaded_files.len() {
        if loaded_files.get(i) == path {
            return 1
        }
        i = i + 1
    }
    0
}

fn collect_imports(program: Int, src_root: Str, all_programs: List[Int]) {
    let imports_sl = np_elements.get(program)
    if imports_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(imports_sl) {
        let imp_node = sublist_get(imports_sl, i)
        let dotted_path = np_str_val.get(imp_node)
        let file_path = resolve_module_path(dotted_path, src_root)
        if file_path == "" {
            i = i + 1
            continue
        }
        if is_file_loaded(file_path) == 1 {
            i = i + 1
            continue
        }
        loaded_files.push(file_path)
        let source = read_file(file_path)
        lex(source)
        pos = 0
        let imported_prog = parse_program()
        collect_imports(imported_prog, src_root, all_programs)
        all_programs.push(imported_prog)
        import_map_paths.push(file_path)
        import_map_nodes.push(imp_node)
        i = i + 1
    }
}

fn main() {
    if arg_count() < 2 {
        io.println("Usage: pactc <source.pact> [output.c] [--format json] [--emit pact]")
        io.println("  Compiles a Pact source file to C.")
        return
    }

    let source_path = get_arg(1)
    let mut out_path = ""
    let mut emit_mode = ""
    let mut i = 2
    while i < arg_count() {
        let arg = get_arg(i)
        if arg == "--format" {
            if i + 1 < arg_count() {
                i = i + 1
                let fmt = get_arg(i)
                if fmt == "json" {
                    diag_format = 1
                }
            }
        } else if arg == "--emit" {
            if i + 1 < arg_count() {
                i = i + 1
                emit_mode = get_arg(i)
            }
        } else {
            out_path = arg
        }
        i = i + 1
    }

    diag_source_file = source_path
    let source = read_file(source_path)

    lex(source)
    pos = 0
    let program_node = parse_program()
    loaded_files.push(source_path)

    let src_root = find_src_root(source_path)
    let mut imported_programs: List[Int] = []
    collect_imports(program_node, src_root, imported_programs)

    let mut final_program = program_node
    if imported_programs.len() > 0 {
        final_program = merge_programs(program_node, imported_programs, import_map_nodes)
    }

    if emit_mode == "pact" {
        let pact_output = format(final_program)
        if out_path != "" {
            write_file(out_path, pact_output)
        } else {
            io.println(pact_output)
        }
        return
    }

    let tc_err_count = check_types(final_program)

    if diag_count > 0 {
        diag_flush()
        return
    }

    let c_output = generate(final_program)

    if diag_count > 0 {
        diag_flush()
        return
    }

    if out_path != "" {
        write_file(out_path, c_output)
    } else {
        io.println(c_output)
    }
}
