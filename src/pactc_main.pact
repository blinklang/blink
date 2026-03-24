import compiler
import comment_attach
import parser

fn main() {
    if arg_count() < 2 {
        io.println("Usage: blinkc <source.pact> [output.c] [--format json] [--json] [--emit pact] [--stats] [--debug] [--dump-ast] [--blink-trace <phase>]")
        io.println("  Compiles a Blink source file to C.")
        return
    }

    let source_path = get_arg(1)
    let mut out_path = ""
    let mut emit_mode = ""
    let mut stats_mode = 0
    let mut check_only = 0
    let mut dump_ast = 0
    let mut blink_trace_flag = ""
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
        } else if arg == "--dump-ast" {
            dump_ast = 1
        } else if arg == "--blink-trace" || arg == "--pact-trace" {
            if i + 1 < arg_count() {
                i = i + 1
                blink_trace_flag = get_arg(i)
            }
        } else {
            out_path = arg
        }
        i = i + 1
    }

    diag_source_file = source_path
    trace_mode = blink_trace_flag
    let source = read_file(source_path)

    let t_lex_start = time_ms()
    lex(source)
    let t_lex_end = time_ms()
    pos = 0
    let t_parse_start = time_ms()
    let first_node_blinkc = np_kind.len()
    let program_node = parse_program()
    attach_comments_pass(program_node, first_node_blinkc)
    let t_parse_end = time_ms()
    loaded_files.push(source_path)

    let src_root = find_src_root(source_path)
    let t_import_start = time_ms()
    let mut imported_programs: List[Int] = []
    collect_root_imports(program_node)
    collect_imports(program_node, src_root, imported_programs)
    if emit_mode != "pact" {
        inject_prelude(src_root, imported_programs)
    }

    let mut final_program = program_node
    if imported_programs.len() > 0 {
        final_program = merge_programs(program_node, imported_programs, import_map_nodes)
    }
    tc_import_modules = import_map_modules
    tc_import_nodes = import_map_nodes
    let t_import_end = time_ms()

    if dump_ast == 1 {
        io.println(ast_to_json(final_program))
        return
    }

    if emit_mode == "pact" {
        let fmt_output = format(final_program)
        if out_path != "" {
            write_file(out_path, fmt_output)
        } else {
            io.println(fmt_output)
        }
        return
    }

    let t_tc_start = time_ms()
    let _tc_err_count = check_types(final_program)
    let t_tc_end = time_ms()

    check_unused_imports()

    if diag_count > 0 {
        diag_flush()
        return
    }
    if diag_warn_count > 0 {
        diag_flush()
    }

    if check_only != 0 {
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
    if diag_warn_count > 0 {
        diag_flush()
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
