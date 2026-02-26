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
import std.lockfile

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

fn resolve_from_lockfile(dotted_path: Str, src_root: Str) -> Str {
    if lockfile_pkg_count() == 0 {
        return ""
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
        let mut first_dot = -1
        let mut second_dot = -1
        let mut i = 0
        while i < dotted_path.len() {
            if dotted_path.char_at(i) == 46 {
                if first_dot == -1 {
                    first_dot = i
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
        return ""
    }

    // Found a matching package — resolve to its source path
    let pkg_idx = lockfile_find_pkg(pkg_name)
    let source = lock_pkg_sources.get(pkg_idx)

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
        return ""
    }

    if sub_path == "" {
        let lib_path = path_join(base_dir, "src/lib.pact")
        if file_exists(lib_path) == 1 {
            return lib_path
        }
        return ""
    }

    let sub_rel = dots_to_slashes(sub_path)
    let resolved = path_join(base_dir, path_join("src", sub_rel.concat(".pact")))
    if file_exists(resolved) == 1 {
        return resolved
    }
    ""
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
        if dep_path != "" {
            io.println("warning[W1000]: local module shadows dependency")
            io.println(" --> {full}")
            io.println("  = note: import '{dotted_path}' matches both local file and a dependency")
            io.println("  = help: this is allowed but may confuse consumers expecting the library")
        }
        return full
    }

    // Use dependency path if found
    if dep_path != "" {
        return dep_path
    }

    // Step 3: Check std. prefix (bundled stdlib)
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
    }

    diag_error_no_loc("ModuleNotFound", "E1200", "module not found: {dotted_path} (looked at: {full})", "")
    ""
}

pub fn should_import_item(item: Int, import_node: Int) -> Int {
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

pub fn merge_programs(main_prog: Int, imported: List[Int], import_nodes_list: List[Int]) -> Int ! Parse.Build {
    let mut all_fns: List[Int] = []
    let mut all_types: List[Int] = []
    let mut all_lets: List[Int] = []
    let mut all_traits: List[Int] = []
    let mut all_impls: List[Int] = []
    let mut all_effects: List[Int] = []

    let mut pi = 0
    while pi < imported.len() {
        let prog = imported.get(pi)
        let mod_name = import_map_modules.get(pi)

        let fns_sl = np_params.get(prog)
        let mut fi = 0
        while fi < sublist_length(fns_sl) {
            let fn_node = sublist_get(fns_sl, fi)
            np_module.set(fn_node, mod_name)
            all_fns.push(fn_node)
            fi = fi + 1
        }

        let types_sl = np_fields.get(prog)
        let mut ti = 0
        while ti < sublist_length(types_sl) {
            let type_node = sublist_get(types_sl, ti)
            np_module.set(type_node, mod_name)
            all_types.push(type_node)
            ti = ti + 1
        }

        let lets_sl = np_stmts.get(prog)
        let mut li = 0
        while li < sublist_length(lets_sl) {
            let let_node = sublist_get(lets_sl, li)
            np_module.set(let_node, mod_name)
            all_lets.push(let_node)
            li = li + 1
        }

        let traits_sl = np_arms.get(prog)
        let mut tri = 0
        while tri < sublist_length(traits_sl) {
            let trait_node = sublist_get(traits_sl, tri)
            np_module.set(trait_node, mod_name)
            all_traits.push(trait_node)
            tri = tri + 1
        }

        let impls_sl = np_methods.get(prog)
        let mut ii = 0
        while ii < sublist_length(impls_sl) {
            let impl_node = sublist_get(impls_sl, ii)
            np_module.set(impl_node, mod_name)
            all_impls.push(impl_node)
            ii = ii + 1
        }

        let effects_sl = np_args.get(prog)
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
    let main_effects = np_args.get(main_prog)
    if main_effects != -1 {
        let mut edi = 0
        while edi < sublist_length(main_effects) {
            all_effects.push(sublist_get(main_effects, edi))
            edi = edi + 1
        }
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

    let mut merged_effects = -1
    if all_effects.len() > 0 {
        merged_effects = new_sublist()
        let mut edi = 0
        while edi < all_effects.len() {
            sublist_push(merged_effects, all_effects.get(edi))
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
    merged
}

pub let mut loaded_files: List[Str] = []
pub let mut import_map_paths: List[Str] = []
pub let mut import_map_nodes: List[Int] = []
pub let mut import_map_modules: List[Str] = []

pub fn reset_compiler_state() {
    loaded_files = []
    import_map_paths = []
    import_map_nodes = []
    import_map_modules = []
    lockfile_loaded = 0
}

pub fn is_file_loaded(path: Str) -> Int {
    let mut i = 0
    while i < loaded_files.len() {
        if loaded_files.get(i) == path {
            return 1
        }
        i = i + 1
    }
    0
}

pub fn collect_imports(program: Int, src_root: Str, all_programs: List[Int]) ! Lex.Tokenize, Parse, Diag.Report {
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
        import_map_modules.push(dots_to_underscores(dotted_path))
        i = i + 1
    }
}

