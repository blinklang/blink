import lexer
import parser
import typecheck
import codegen
import formatter
import diagnostics
import mutation_analysis
import symbol_index
import file_watcher
import query
import incremental
import daemon
import pkg.lockfile
import ast_dump
import std.path

// compiler.pact — Self-hosting Pact compiler driver
//
// Ties together lexer, parser, and codegen into a complete compiler.
// Reads a .pact source file, lexes, parses, generates C, and writes output.
//
// Usage (once compiled): ./pactc <source.pact> [output.c]
// If no output file given, writes to stdout.

pub fn dots_to_slashes(s: Str) -> Str {
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

fn read_module_ann(anns_sl: Int) -> Option[Str] {
    if anns_sl == -1 {
        return None
    }
    let mut ai = 0
    while ai < sublist_length(anns_sl) {
        let ann = sublist_get(anns_sl, ai)
        let ann_name = np_name.get(ann).unwrap()
        if ann_name == "module" {
            let ann_args_sl = np_args.get(ann).unwrap()
            if ann_args_sl != -1 && sublist_length(ann_args_sl) > 0 {
                let arg_nd = sublist_get(ann_args_sl, 0)
                let arg_parts = np_elements.get(arg_nd).unwrap()
                if arg_parts == -1 || sublist_length(arg_parts) == 0 {
                    return Some("")
                }
                let val = np_name.get(sublist_get(arg_parts, 0)).unwrap()
                return Some(val)
            }
        }
        ai = ai + 1
    }
    None
}

fn find_module_annotation(prog: Int) -> Option[Str] {
    let result = read_module_ann(np_handlers.get(prog).unwrap())
    if result.is_some() {
        return result
    }
    let fns_sl = np_params.get(prog).unwrap()
    if fns_sl != -1 && sublist_length(fns_sl) > 0 {
        let first_fn = sublist_get(fns_sl, 0)
        return read_module_ann(np_handlers.get(first_fn).unwrap())
    }
    None
}

pub fn dots_to_underscores(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        if s.char_at(i) == 46 {
            result = result.concat("_")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

pub fn find_src_root(source_path: Str) -> Str {
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

pub let mut trace_mode: Str = ""

pub fn trace(phase: Str, msg: Str) {
    if trace_mode == phase || trace_mode == "all" {
        io.eprintln("[trace:{phase}] {msg}")
    }
}

pub let mut lockfile_loaded: Int = 0

pub fn ensure_lockfile_loaded(src_root: Str) {
    if lockfile_loaded == 1 {
        return
    }
    lockfile_loaded = 1
    let mut project_root = src_root
    if src_root.ends_with("src/") {
        project_root = src_root.substring(0, src_root.len() - 4)
    }
    if project_root == "" {
        project_root = "."
    }
    let lock_path = path_join(project_root, "pact.lock")
    if file_exists(lock_path) == 1 {
        lockfile_load(lock_path)
    }
}

fn compiler_get_home() -> Str {
    shell_exec("printf '%s' $HOME > /tmp/_pact_home")
    let raw = read_file("/tmp/_pact_home")
    let mut end = raw.len()
    while end > 0 {
        let ch = raw.char_at(end - 1)
        if ch == 10 || ch == 13 || ch == 32 {
            end = end - 1
        } else {
            return raw.substring(0, end)
        }
    }
    ""
}

fn resolve_from_lockfile(dotted_path: Str, _src_root: Str) -> Option[Str] {
    if lockfile_pkg_count() == 0 {
        return None
    }

    // Strategy: try progressively shorter prefixes of the dotted path
    // as package names, with the rest being the submodule path
    //
    // "import std.http" → package "std/http"
    // "import std.http.client" → package "std/http", submodule "client"
    // "import mylib" → package "mylib"
    // "import mylib.utils" → package "mylib", submodule "utils"

    let mut pkg_name = ""
    let mut sub_path = ""

    // Try the whole dotted path converted to slash-separated package name
    let full_pkg = dots_to_slashes(dotted_path)
    let idx_full = lockfile_find_pkg(full_pkg)
    if idx_full >= 0 {
        pkg_name = full_pkg
        sub_path = ""
    }

    // Try first segment as package name
    if pkg_name == "" {
        let mut dot_pos = -1
        let mut i = 0
        while i < dotted_path.len() {
            if dotted_path.char_at(i) == 46 {
                dot_pos = i
                i = dotted_path.len()
            }
            i = i + 1
        }
        if dot_pos > 0 {
            let first = dotted_path.substring(0, dot_pos)
            let rest = dotted_path.substring(dot_pos + 1, dotted_path.len() - dot_pos - 1)
            let idx_first = lockfile_find_pkg(first)
            if idx_first >= 0 {
                pkg_name = first
                sub_path = rest
            }
        } else {
            let idx_single = lockfile_find_pkg(dotted_path)
            if idx_single >= 0 {
                pkg_name = dotted_path
                sub_path = ""
            }
        }
    }

    // Try two-segment package name: "std.http.client" → "std/http" + "client"
    if pkg_name == "" {
        let mut _first_dot = -1
        let mut second_dot = -1
        let mut i = 0
        while i < dotted_path.len() {
            if dotted_path.char_at(i) == 46 {
                if _first_dot == -1 {
                    _first_dot = i
                } else if second_dot == -1 {
                    second_dot = i
                }
            }
            i = i + 1
        }
        if second_dot > 0 {
            let two_seg = dotted_path.substring(0, second_dot)
            let two_pkg = dots_to_slashes(two_seg)
            let rest = dotted_path.substring(second_dot + 1, dotted_path.len() - second_dot - 1)
            let idx_two = lockfile_find_pkg(two_pkg)
            if idx_two >= 0 {
                pkg_name = two_pkg
                sub_path = rest
            }
        }
    }

    if pkg_name == "" {
        return None
    }

    // Found a matching package — resolve to its source path
    let pkg_idx = lockfile_find_pkg(pkg_name)
    let source = lock_pkg_sources.get(pkg_idx).unwrap()

    let mut base_dir = ""
    if source.starts_with("path:") {
        base_dir = source.substring(5, source.len() - 5)
    } else if source.starts_with("git:") {
        let home = compiler_get_home()
        let mut url_part = source.substring(4, source.len() - 4)
        // Strip #commit suffix
        let mut hash_pos = -1
        let mut i = 0
        while i < url_part.len() {
            if url_part.char_at(i) == 35 {
                hash_pos = i
            }
            i = i + 1
        }
        if hash_pos > 0 {
            url_part = url_part.substring(0, hash_pos)
        }
        // Convert URL to cache dir name (replace non-alphanumeric with _)
        let mut cache_name = ""
        i = 0
        while i < url_part.len() {
            let ch = url_part.char_at(i)
            if (ch >= 97 && ch <= 122) || (ch >= 65 && ch <= 90) || (ch >= 48 && ch <= 57) {
                cache_name = cache_name.concat(url_part.substring(i, 1))
            } else {
                cache_name = cache_name.concat("_")
            }
            i = i + 1
        }
        base_dir = path_join(home, path_join(".pact/cache/git", path_join(cache_name, "checkout")))
    }

    if base_dir == "" {
        return None
    }

    if sub_path == "" {
        let lib_path = path_join(base_dir, "src/lib.pact")
        if file_exists(lib_path) == 1 {
            return Some(lib_path)
        }
        return None
    }

    let sub_rel = dots_to_slashes(sub_path)
    let resolved = path_join(base_dir, path_join("src", sub_rel.concat(".pact")))
    if file_exists(resolved) == 1 {
        return Some(resolved)
    }
    None
}

pub fn resolve_module_path(dotted_path: Str, src_root: Str) -> Str ! Diag.Report {
    let rel = dots_to_slashes(dotted_path)
    let full = path_join(src_root, rel.concat(".pact"))

    // Step 1: Check local src/
    let local_exists = file_exists(full) == 1

    // Step 2: Check dependencies via pact.lock
    ensure_lockfile_loaded(src_root)
    let dep_path = resolve_from_lockfile(dotted_path, src_root)

    // If local exists, use it (but warn if it shadows a dependency)
    if local_exists {
        if dep_path.is_some() {
            io.println("warning[W1000]: local module shadows dependency")
            io.println(" --> {full}")
            io.println("  = note: import '{dotted_path}' matches both local file and a dependency")
            io.println("  = help: this is allowed but may confuse consumers expecting the library")
        }
        return full
    }

    // Use dependency path if found
    if dep_path.is_some() {
        return dep_path.unwrap()
    }

    // Step 3: Check pkg. prefix (bundled package-manager modules)
    if dotted_path.starts_with("pkg.") {
        let compiler_dir = path_dirname(get_arg(0))
        let pkg_rel = dots_to_slashes(dotted_path.substring(4, dotted_path.len() - 4))
        let pkg_full = path_join(compiler_dir, path_join("lib/pkg", pkg_rel.concat(".pact")))
        if file_exists(pkg_full) == 1 {
            return pkg_full
        }
        let pact_root = get_env("PACT_ROOT") ?? ""
        if pact_root != "" {
            let pkg_root = path_join(pact_root, path_join("lib/pkg", pkg_rel.concat(".pact")))
            if file_exists(pkg_root) == 1 {
                return pkg_root
            }
        }
        let pkg_key = "pkg_".concat(dots_to_underscores(dotted_path.substring(4, dotted_path.len() - 4)))
        if embedded_stdlib.has(pkg_key) != 0 {
            return "<embedded:{pkg_key}>"
        }
    }

    // Step 4: Check std. prefix (bundled stdlib)
    if dotted_path.starts_with("std.") {
        let compiler_dir = path_dirname(get_arg(0))
        let std_rel = dots_to_slashes(dotted_path.substring(4, dotted_path.len() - 4))
        let std_full = path_join(compiler_dir, path_join("lib/std", std_rel.concat(".pact")))
        if file_exists(std_full) == 1 {
            return std_full
        }
        let pact_root = get_env("PACT_ROOT") ?? ""
        if pact_root != "" {
            let std_root = path_join(pact_root, path_join("lib/std", std_rel.concat(".pact")))
            if file_exists(std_root) == 1 {
                return std_root
            }
        }
        let std_key = dots_to_underscores(dotted_path.substring(4, dotted_path.len() - 4))
        if embedded_stdlib.has(std_key) != 0 {
            return "<embedded:{std_key}>"
        }
    }

    diag_error_no_loc("ModuleNotFound", "E1200", "module not found: {dotted_path} (looked at: {full})", "")
    ""
}

pub fn should_import_item(item: Int, import_node: Int) -> Int {
    let names_sl = np_args.get(import_node).unwrap()
    if names_sl == -1 {
        return 1
    }
    let item_name = np_name.get(item).unwrap()
    let mut i = 0
    while i < sublist_length(names_sl) {
        let name_node = sublist_get(names_sl, i)
        if np_name.get(name_node).unwrap() == item_name {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn merge_programs(main_prog: Int, imported: List[Int], _import_nodes_list: List[Int]) -> Int ! Parse.Build {
    let mut all_fns: List[Int] = []
    let mut all_types: List[Int] = []
    let mut all_lets: List[Int] = []
    let mut all_traits: List[Int] = []
    let mut all_impls: List[Int] = []
    let mut all_effects: List[Int] = []

    let mut pi = 0
    while pi < imported.len() {
        let prog = imported.get(pi).unwrap()
        let mod_name = import_map_modules.get(pi).unwrap()

        let fns_sl = np_params.get(prog).unwrap()
        let mut fi = 0
        while fi < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, fi)
            np_module.set(fn_node, mod_name)
            all_fns.push(fn_node)
            fi = fi + 1
        }

        let types_sl = np_fields.get(prog).unwrap()
        let mut ti = 0
        while ti < sublist_length(types_sl) {
            let type_node = sublist_get(types_sl, ti)
            np_module.set(type_node, mod_name)
            all_types.push(type_node)
            ti = ti + 1
        }

        let lets_sl = np_stmts.get(prog).unwrap()
        let mut li = 0
        while li < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, li)
            np_module.set(let_node, mod_name)
            all_lets.push(let_node)
            li = li + 1
        }

        let traits_sl = np_arms.get(prog).unwrap()
        let mut tri = 0
        while tri < sublist_length(traits_sl) {
            let trait_node = sublist_get(traits_sl, tri)
            np_module.set(trait_node, mod_name)
            all_traits.push(trait_node)
            tri = tri + 1
        }

        let impls_sl = np_methods.get(prog).unwrap()
        let mut ii = 0
        while ii < sublist_length(impls_sl) {
            let impl_node = sublist_get(impls_sl, ii)
            np_module.set(impl_node, mod_name)
            all_impls.push(impl_node)
            ii = ii + 1
        }

        let effects_sl = np_args.get(prog).unwrap()
        if effects_sl != -1 {
            let mut edi = 0
            while edi < sublist_length(effects_sl) {
                let eff_node = sublist_get(effects_sl, edi)
                np_module.set(eff_node, mod_name)
                all_effects.push(eff_node)
                edi = edi + 1
            }
        }

        pi = pi + 1
    }

    let main_mod = "__main__"
    diag_module_files.set(main_mod, diag_source_file)

    let main_fns = np_params.get(main_prog).unwrap()
    let mut fi = 0
    while fi < sublist_length(main_fns) {
        let fn_node = sublist_get(main_fns, fi)
        np_module.set(fn_node, main_mod)
        all_fns.push(fn_node)
        fi = fi + 1
    }
    let main_types = np_fields.get(main_prog).unwrap()
    let mut ti = 0
    while ti < sublist_length(main_types) {
        let type_node = sublist_get(main_types, ti)
        np_module.set(type_node, main_mod)
        all_types.push(type_node)
        ti = ti + 1
    }
    let main_lets = np_stmts.get(main_prog).unwrap()
    let mut li = 0
    while li < sublist_length(main_lets) {
        let let_node = sublist_get(main_lets, li)
        np_module.set(let_node, main_mod)
        all_lets.push(let_node)
        li = li + 1
    }
    let main_traits = np_arms.get(main_prog).unwrap()
    let mut tri = 0
    while tri < sublist_length(main_traits) {
        let trait_node = sublist_get(main_traits, tri)
        np_module.set(trait_node, main_mod)
        all_traits.push(trait_node)
        tri = tri + 1
    }
    let main_impls = np_methods.get(main_prog).unwrap()
    let mut ii = 0
    while ii < sublist_length(main_impls) {
        let impl_node = sublist_get(main_impls, ii)
        np_module.set(impl_node, main_mod)
        all_impls.push(impl_node)
        ii = ii + 1
    }
    let main_effects = np_args.get(main_prog).unwrap()
    if main_effects != -1 {
        let mut edi = 0
        while edi < sublist_length(main_effects) {
            let eff_node = sublist_get(main_effects, edi)
            np_module.set(eff_node, main_mod)
            all_effects.push(eff_node)
            edi = edi + 1
        }
    }

    let merged_fns = new_sublist()
    fi = 0
    while fi < all_fns.len() {
        sublist_push(merged_fns, all_fns.get(fi).unwrap())
        fi = fi + 1
    }
    finalize_sublist(merged_fns)

    let merged_types = new_sublist()
    ti = 0
    while ti < all_types.len() {
        sublist_push(merged_types, all_types.get(ti).unwrap())
        ti = ti + 1
    }
    finalize_sublist(merged_types)

    let merged_lets = new_sublist()
    li = 0
    while li < all_lets.len() {
        sublist_push(merged_lets, all_lets.get(li).unwrap())
        li = li + 1
    }
    finalize_sublist(merged_lets)

    let merged_traits = new_sublist()
    tri = 0
    while tri < all_traits.len() {
        sublist_push(merged_traits, all_traits.get(tri).unwrap())
        tri = tri + 1
    }
    finalize_sublist(merged_traits)

    let merged_impls = new_sublist()
    ii = 0
    while ii < all_impls.len() {
        sublist_push(merged_impls, all_impls.get(ii).unwrap())
        ii = ii + 1
    }
    finalize_sublist(merged_impls)

    let mut merged_effects = -1
    if all_effects.len() > 0 {
        merged_effects = new_sublist()
        let mut edi = 0
        while edi < all_effects.len() {
            sublist_push(merged_effects, all_effects.get(edi).unwrap())
            edi = edi + 1
        }
        finalize_sublist(merged_effects)
    }

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
    np_args.pop()
    np_args.push(merged_effects)
    let main_tests = np_captures.get(main_prog).unwrap()
    np_captures.pop()
    np_captures.push(main_tests)
    merged
}

pub let mut loaded_files: List[Str] = []
pub let mut import_map_paths: List[Str] = []
pub let mut import_map_nodes: List[Int] = []
pub let mut import_map_modules: List[Str] = []
pub let mut root_import_nodes: List[Int] = []
pub let mut root_import_modules: List[Str] = []
pub let mut embedded_stdlib: Map[Str, Str] = Map()

pub fn reset_compiler_state() {
    loaded_files = []
    import_map_paths = []
    import_map_nodes = []
    import_map_modules = []
    root_import_nodes = []
    root_import_modules = []
    lockfile_loaded = 0
}

pub fn is_file_loaded(path: Str) -> Int {
    let mut i = 0
    while i < loaded_files.len() {
        if loaded_files.get(i).unwrap() == path {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn collect_imports(program: Int, src_root: Str, all_programs: List[Int]) ! Lex.Tokenize, Parse, Diag.Report {
    let imports_sl = np_elements.get(program).unwrap()
    if imports_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(imports_sl) {
        let imp_node = sublist_get(imports_sl, i)
        let dotted_path = np_str_val.get(imp_node).unwrap()
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
        if trace_mode != "" { trace("parse", "import {dotted_path} -> {file_path}") }
        let mut source = ""
        if file_path.starts_with("<embedded:") {
            let key = file_path.substring(10, file_path.len() - 11)
            source = embedded_stdlib.get(key)
        } else {
            source = read_file(file_path)
        }
        lex(source)
        pos = 0
        let imported_prog = parse_program()
        collect_imports(imported_prog, src_root, all_programs)
        all_programs.push(imported_prog)
        let mut mod_key = dots_to_underscores(dotted_path)
        let override_key = find_module_annotation(imported_prog)
        if override_key.is_some() {
            mod_key = override_key.unwrap()
        }
        import_map_paths.push(file_path)
        import_map_nodes.push(imp_node)
        import_map_modules.push(mod_key)
        diag_module_files.set(mod_key, file_path)
        i = i + 1
    }
}

pub fn collect_root_imports(program: Int) {
    root_import_nodes = []
    root_import_modules = []
    let imports_sl = np_elements.get(program).unwrap()
    if imports_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(imports_sl) {
        let imp_node = sublist_get(imports_sl, i)
        let dotted_path = np_str_val.get(imp_node).unwrap()
        let mod_key = dots_to_underscores(dotted_path)
        root_import_nodes.push(imp_node)
        root_import_modules.push(mod_key)
        i = i + 1
    }
}

pub fn check_unused_imports() ! Diag.Report {
    let mut ii = 0
    while ii < root_import_modules.len() {
        let mod_name = root_import_modules.get(ii).unwrap()
        if tc_is_module_used(mod_name) == 0 {
            let imp_node = root_import_nodes.get(ii).unwrap()
            diag_warn_at("UnusedImport", "W0602", "module '{mod_name}' is imported but not used", imp_node, "remove the unused import")
        }
        ii = ii + 1
    }
}

