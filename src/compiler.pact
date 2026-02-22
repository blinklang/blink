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

let mut lockfile_loaded: Int = 0

fn ensure_lockfile_loaded(src_root: Str) {
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

fn resolve_module_path(dotted_path: Str, src_root: Str) -> Str ! Diag.Report {
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

fn is_builtin_type(name: Str) -> Int {
    if name == "" || name == "Int" || name == "Str" || name == "Float" || name == "Bool" || name == "Void" {
        return 1
    }
    if name == "List" || name == "Map" || name == "Option" || name == "Result" || name == "Iterator" {
        return 1
    }
    0
}

fn add_type_dep(type_name: Str, mod_fns: Map[Str, Int], mod_types: Map[Str, Int], mod_lets: Map[Str, Int], needed: Map[Str, Int]) {
    if is_builtin_type(type_name) == 1 {
        return
    }
    if needed.has(type_name) {
        return
    }
    if mod_types.has(type_name) {
        needed.set(type_name, mod_types.get(type_name))
        let tnode = mod_types.get(type_name)
        let flds = np_fields.get(tnode)
        if flds != -1 {
            let mut fi = 0
            while fi < sublist_length(flds) {
                let fld = sublist_get(flds, fi)
                let fkind = np_kind.get(fld)
                if fkind == NodeKind.TypeField {
                    let ta = np_value.get(fld)
                    if ta != -1 {
                        add_type_dep(np_name.get(ta), mod_fns, mod_types, mod_lets, needed)
                    }
                } else if fkind == NodeKind.TypeVariant {
                    let vflds = np_fields.get(fld)
                    if vflds != -1 {
                        let mut vi = 0
                        while vi < sublist_length(vflds) {
                            let vf = sublist_get(vflds, vi)
                            let vta = np_value.get(vf)
                            if vta != -1 {
                                add_type_dep(np_name.get(vta), mod_fns, mod_types, mod_lets, needed)
                            }
                            vi = vi + 1
                        }
                    }
                }
                fi = fi + 1
            }
        }
    }
}

fn walk_body_deps(node: Int, mod_fns: Map[Str, Int], mod_types: Map[Str, Int], mod_lets: Map[Str, Int], needed: Map[Str, Int]) {
    if node == -1 {
        return
    }
    let kind = np_kind.get(node)

    if kind == NodeKind.Call {
        let callee = np_left.get(node)
        if callee != -1 && np_kind.get(callee) == NodeKind.Ident {
            let cname = np_name.get(callee)
            if mod_fns.has(cname) && needed.has(cname) == false {
                needed.set(cname, mod_fns.get(cname))
                let dep_fn = mod_fns.get(cname)
                collect_fn_deps(dep_fn, mod_fns, mod_types, mod_lets, needed)
            }
        }
        walk_body_deps(callee, mod_fns, mod_types, mod_lets, needed)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_body_deps(sublist_get(args_sl, ai), mod_fns, mod_types, mod_lets, needed)
                ai = ai + 1
            }
        }
        return
    }

    if kind == NodeKind.StructLit {
        let stype = np_type_name.get(node)
        add_type_dep(stype, mod_fns, mod_types, mod_lets, needed)
        let sfields = np_fields.get(node)
        if sfields != -1 {
            let mut si = 0
            while si < sublist_length(sfields) {
                let sf = sublist_get(sfields, si)
                walk_body_deps(np_value.get(sf), mod_fns, mod_types, mod_lets, needed)
                si = si + 1
            }
        }
        return
    }

    if kind == NodeKind.Ident {
        let ref_name = np_name.get(node)
        if mod_lets.has(ref_name) && needed.has(ref_name) == false {
            needed.set(ref_name, mod_lets.get(ref_name))
            let let_node = mod_lets.get(ref_name)
            walk_body_deps(np_value.get(let_node), mod_fns, mod_types, mod_lets, needed)
        }
        return
    }

    if kind == NodeKind.BinOp {
        walk_body_deps(np_left.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_right.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.UnaryOp {
        walk_body_deps(np_left.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.IfExpr {
        walk_body_deps(np_condition.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_then_body.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_else_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.Block {
        walk_stmts_deps(np_stmts.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.LetBinding {
        walk_body_deps(np_value.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.ExprStmt {
        walk_body_deps(np_value.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.Return {
        walk_body_deps(np_value.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.Assignment || kind == NodeKind.CompoundAssign {
        walk_body_deps(np_target.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_value.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.ForIn {
        walk_body_deps(np_iterable.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.WhileLoop {
        walk_body_deps(np_condition.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.LoopExpr {
        walk_body_deps(np_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.MatchExpr {
        walk_body_deps(np_scrutinee.get(node), mod_fns, mod_types, mod_lets, needed)
        let arms_sl = np_arms.get(node)
        if arms_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(arms_sl) {
                let arm = sublist_get(arms_sl, ai)
                walk_body_deps(np_guard.get(arm), mod_fns, mod_types, mod_lets, needed)
                walk_body_deps(np_body.get(arm), mod_fns, mod_types, mod_lets, needed)
                ai = ai + 1
            }
        }
        return
    }
    if kind == NodeKind.IndexExpr {
        walk_body_deps(np_obj.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_index.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.TupleLit || kind == NodeKind.ListLit {
        let elems_sl = np_elements.get(node)
        if elems_sl != -1 {
            let mut ei = 0
            while ei < sublist_length(elems_sl) {
                walk_body_deps(sublist_get(elems_sl, ei), mod_fns, mod_types, mod_lets, needed)
                ei = ei + 1
            }
        }
        return
    }
    if kind == NodeKind.MethodCall {
        walk_body_deps(np_obj.get(node), mod_fns, mod_types, mod_lets, needed)
        let args_sl = np_args.get(node)
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                walk_body_deps(sublist_get(args_sl, ai), mod_fns, mod_types, mod_lets, needed)
                ai = ai + 1
            }
        }
        return
    }
    if kind == NodeKind.FieldAccess {
        walk_body_deps(np_obj.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.Closure {
        walk_body_deps(np_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.InterpString {
        let parts_sl = np_elements.get(node)
        if parts_sl != -1 {
            let mut pi = 0
            while pi < sublist_length(parts_sl) {
                walk_body_deps(sublist_get(parts_sl, pi), mod_fns, mod_types, mod_lets, needed)
                pi = pi + 1
            }
        }
        return
    }
    if kind == NodeKind.RangeLit {
        walk_body_deps(np_start.get(node), mod_fns, mod_types, mod_lets, needed)
        walk_body_deps(np_end.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
    if kind == NodeKind.WithBlock {
        walk_body_deps(np_body.get(node), mod_fns, mod_types, mod_lets, needed)
        return
    }
}

fn walk_stmts_deps(stmts_sl: Int, mod_fns: Map[Str, Int], mod_types: Map[Str, Int], mod_lets: Map[Str, Int], needed: Map[Str, Int]) {
    if stmts_sl == -1 {
        return
    }
    let mut i = 0
    while i < sublist_length(stmts_sl) {
        walk_body_deps(sublist_get(stmts_sl, i), mod_fns, mod_types, mod_lets, needed)
        i = i + 1
    }
}

fn collect_fn_deps(fn_node: Int, mod_fns: Map[Str, Int], mod_types: Map[Str, Int], mod_lets: Map[Str, Int], needed: Map[Str, Int]) {
    let ret_type = np_return_type.get(fn_node)
    add_type_dep(ret_type, mod_fns, mod_types, mod_lets, needed)
    let params_sl = np_params.get(fn_node)
    if params_sl != -1 {
        let mut pi = 0
        while pi < sublist_length(params_sl) {
            let p = sublist_get(params_sl, pi)
            add_type_dep(np_type_name.get(p), mod_fns, mod_types, mod_lets, needed)
            pi = pi + 1
        }
    }
    walk_body_deps(np_body.get(fn_node), mod_fns, mod_types, mod_lets, needed)
}

fn check_pub_sig(fn_node: Int, fn_name: Str, mod_types_pub: Map[Str, Int]) ! Diag.Report {
    let ret_type = np_return_type.get(fn_node)
    if is_builtin_type(ret_type) == 0 && mod_types_pub.has(ret_type) && mod_types_pub.get(ret_type) == 0 {
        diag_error_at("VisibilityError", "E1300", "pub fn '{fn_name}' returns non-pub type '{ret_type}'", fn_node, "make '{ret_type}' pub or change the return type")
    }
    let params_sl = np_params.get(fn_node)
    if params_sl != -1 {
        let mut pi = 0
        while pi < sublist_length(params_sl) {
            let p = sublist_get(params_sl, pi)
            let ptype = np_type_name.get(p)
            if is_builtin_type(ptype) == 0 && mod_types_pub.has(ptype) && mod_types_pub.get(ptype) == 0 {
                diag_error_at("VisibilityError", "E1300", "pub fn '{fn_name}' has parameter of non-pub type '{ptype}'", fn_node, "make '{ptype}' pub or change the parameter type")
            }
            pi = pi + 1
        }
    }
}

fn merge_programs(main_prog: Int, imported: List[Int], import_nodes_list: List[Int]) -> Int ! Parse.Build, Diag.Report {
    let mut all_fns: List[Int] = []
    let mut all_types: List[Int] = []
    let mut all_lets: List[Int] = []
    let mut all_traits: List[Int] = []
    let mut all_impls: List[Int] = []
    let mut all_effects: List[Int] = []

    let mut pi = 0
    while pi < imported.len() {
        let prog = imported.get(pi)
        let imp_node = import_nodes_list.get(pi)
        let is_selective = np_args.get(imp_node) != -1

        if is_selective {
            let mut mod_fns: Map[Str, Int] = Map()
            let mut mod_types: Map[Str, Int] = Map()
            let mut mod_lets: Map[Str, Int] = Map()
            let mut mod_types_pub: Map[Str, Int] = Map()

            let fns_sl = np_params.get(prog)
            let mut fi = 0
            while fi < sublist_length(fns_sl) {
                let f = sublist_get(fns_sl, fi)
                mod_fns.set(np_name.get(f), f)
                fi = fi + 1
            }
            let types_sl = np_fields.get(prog)
            let mut ti = 0
            while ti < sublist_length(types_sl) {
                let t = sublist_get(types_sl, ti)
                mod_types.set(np_name.get(t), t)
                mod_types_pub.set(np_name.get(t), np_is_pub.get(t))
                ti = ti + 1
            }
            let lets_sl = np_stmts.get(prog)
            let mut li = 0
            while li < sublist_length(lets_sl) {
                let l = sublist_get(lets_sl, li)
                mod_lets.set(np_name.get(l), l)
                li = li + 1
            }

            let mut needed: Map[Str, Int] = Map()

            fi = 0
            while fi < sublist_length(fns_sl) {
                let f = sublist_get(fns_sl, fi)
                if should_import_item(f, imp_node) == 1 {
                    let fname = np_name.get(f)
                    needed.set(fname, f)
                    if np_is_pub.get(f) != 0 {
                        check_pub_sig(f, fname, mod_types_pub)
                    }
                    collect_fn_deps(f, mod_fns, mod_types, mod_lets, needed)
                }
                fi = fi + 1
            }
            ti = 0
            while ti < sublist_length(types_sl) {
                let t = sublist_get(types_sl, ti)
                if should_import_item(t, imp_node) == 1 {
                    let tname = np_name.get(t)
                    needed.set(tname, t)
                    add_type_dep(tname, mod_fns, mod_types, mod_lets, needed)
                }
                ti = ti + 1
            }
            li = 0
            while li < sublist_length(lets_sl) {
                let l = sublist_get(lets_sl, li)
                if should_import_item(l, imp_node) == 1 {
                    needed.set(np_name.get(l), l)
                    walk_body_deps(np_value.get(l), mod_fns, mod_types, mod_lets, needed)
                }
                li = li + 1
            }
            let traits_sl = np_arms.get(prog)
            let mut tri = 0
            while tri < sublist_length(traits_sl) {
                let tr = sublist_get(traits_sl, tri)
                if should_import_item(tr, imp_node) == 1 {
                    needed.set(np_name.get(tr), tr)
                }
                tri = tri + 1
            }

            fi = 0
            while fi < sublist_length(fns_sl) {
                let f = sublist_get(fns_sl, fi)
                if needed.has(np_name.get(f)) {
                    all_fns.push(f)
                }
                fi = fi + 1
            }
            ti = 0
            while ti < sublist_length(types_sl) {
                let t = sublist_get(types_sl, ti)
                if needed.has(np_name.get(t)) {
                    all_types.push(t)
                }
                ti = ti + 1
            }
            li = 0
            while li < sublist_length(lets_sl) {
                let l = sublist_get(lets_sl, li)
                if needed.has(np_name.get(l)) {
                    all_lets.push(l)
                }
                li = li + 1
            }
            tri = 0
            while tri < sublist_length(traits_sl) {
                let tr = sublist_get(traits_sl, tri)
                if needed.has(np_name.get(tr)) {
                    all_traits.push(tr)
                }
                tri = tri + 1
            }
        } else {
            let fns_sl = np_params.get(prog)
            let mut fi = 0
            while fi < sublist_length(fns_sl) {
                all_fns.push(sublist_get(fns_sl, fi))
                fi = fi + 1
            }
            let types_sl = np_fields.get(prog)
            let mut ti = 0
            while ti < sublist_length(types_sl) {
                all_types.push(sublist_get(types_sl, ti))
                ti = ti + 1
            }
            let lets_sl = np_stmts.get(prog)
            let mut li = 0
            while li < sublist_length(lets_sl) {
                all_lets.push(sublist_get(lets_sl, li))
                li = li + 1
            }
            let traits_sl = np_arms.get(prog)
            let mut tri = 0
            while tri < sublist_length(traits_sl) {
                all_traits.push(sublist_get(traits_sl, tri))
                tri = tri + 1
            }
        }

        let impls_sl = np_methods.get(prog)
        let mut ii = 0
        while ii < sublist_length(impls_sl) {
            all_impls.push(sublist_get(impls_sl, ii))
            ii = ii + 1
        }

        let effects_sl = np_args.get(prog)
        if effects_sl != -1 {
            let mut edi = 0
            while edi < sublist_length(effects_sl) {
                all_effects.push(sublist_get(effects_sl, edi))
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

fn collect_imports(program: Int, src_root: Str, all_programs: List[Int]) ! Lex.Tokenize, Parse, Diag.Report {
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
        io.println("Usage: pactc <source.pact> [output.c] [--format json] [--json] [--emit pact] [--stats] [--debug]")
        io.println("  Compiles a Pact source file to C.")
        return
    }

    let source_path = get_arg(1)
    let mut out_path = ""
    let mut emit_mode = ""
    let mut stats_mode = 0
    let mut check_only = 0
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
        } else if arg == "--json" {
            diag_format = 1
        } else if arg == "--emit" {
            if i + 1 < arg_count() {
                i = i + 1
                emit_mode = get_arg(i)
            }
        } else if arg == "--debug" {
            cg_debug_mode = 1
        } else if arg == "--stats" {
            stats_mode = 1
        } else if arg == "--check-only" {
            check_only = 1
        } else {
            out_path = arg
        }
        i = i + 1
    }

    diag_source_file = source_path
    let source = read_file(source_path)

    let t_lex_start = time_ms()
    lex(source)
    let t_lex_end = time_ms()
    pos = 0
    let t_parse_start = time_ms()
    let program_node = parse_program()
    let t_parse_end = time_ms()
    loaded_files.push(source_path)

    let src_root = find_src_root(source_path)
    let t_import_start = time_ms()
    let mut imported_programs: List[Int] = []
    collect_imports(program_node, src_root, imported_programs)

    let mut final_program = program_node
    if imported_programs.len() > 0 {
        final_program = merge_programs(program_node, imported_programs, import_map_nodes)
    }
    let t_import_end = time_ms()

    if emit_mode == "pact" {
        let pact_output = format(final_program)
        if out_path != "" {
            write_file(out_path, pact_output)
        } else {
            io.println(pact_output)
        }
        return
    }

    let t_tc_start = time_ms()
    let tc_err_count = check_types(final_program)
    let t_tc_end = time_ms()

    if diag_count > 0 {
        diag_flush()
        return
    }

    if check_only != 0 {
        diag_flush()
        return
    }

    let t_mut_start = time_ms()
    analyze_mutations(final_program)
    analyze_save_restore(final_program)
    let t_mut_end = time_ms()

    let t_cg_start = time_ms()
    let c_output = generate(final_program)
    let t_cg_end = time_ms()

    if diag_count > 0 {
        diag_flush()
        return
    }

    if out_path != "" {
        write_file(out_path, c_output)
    } else {
        io.println(c_output)
    }

    if stats_mode == 1 {
        let lex_ms = t_lex_end - t_lex_start
        let parse_ms = t_parse_end - t_parse_start
        let import_ms = t_import_end - t_import_start
        let typecheck_ms = t_tc_end - t_tc_start
        let mutation_ms = t_mut_end - t_mut_start
        let codegen_ms = t_cg_end - t_cg_start
        let total_ms = t_cg_end - t_lex_start
        let q = "\""
        io.eprintln("\{{q}lex_ms{q}:{lex_ms},{q}parse_ms{q}:{parse_ms},{q}import_ms{q}:{import_ms},{q}typecheck_ms{q}:{typecheck_ms},{q}mutation_ms{q}:{mutation_ms},{q}codegen_ms{q}:{codegen_ms},{q}total_ms{q}:{total_ms}\}")
    }
}
