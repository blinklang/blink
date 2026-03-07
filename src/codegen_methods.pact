import codegen_types
import diagnostics

pub fn emit_method_call(node: Int) ! Codegen.Emit, Codegen.Register, Codegen.Scope, Diag.Report {
    let obj_node = np_obj.get(node).unwrap()
    let method = np_method.get(node).unwrap()

    // Static derive method dispatch: Type.from_json(str)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let static_type_name = np_name.get(obj_node).unwrap()
        if method == "from_json" && has_derive_method(static_type_name, "from_json") != 0 {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                let tmp = fresh_temp("_deser_")
                emit_line("pact_Result_{static_type_name}_str {tmp} = pact_{static_type_name}_from_json({arg_str});")
                set_var_struct(tmp, "Result_{static_type_name}_str")
                set_var(tmp, CT_VOID, 0)
                set_var_result_struct(tmp, CT_VOID, CT_STRING, static_type_name, "")
                expr_result_str = tmp
                expr_result_type = CT_RESULT
                expr_result_ok_type = CT_VOID
                expr_result_ok_struct = static_type_name
                expr_result_err_type = CT_STRING
                expr_result_err_struct = ""
                return
            }
        }
    }

    // Data-carrying enum variant constructor: Shape.Circle(5.0)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let mc_obj_name = np_name.get(obj_node).unwrap()
        if is_enum_type(mc_obj_name) != 0 && is_data_enum(mc_obj_name) != 0 {
            let vidx = get_variant_index(mc_obj_name, method)
            if vidx >= 0 {
                let tag = get_variant_tag(mc_obj_name, method)
                let fcount = get_variant_field_count(vidx)
                let args_sl = np_args.get(node).unwrap()
                let mut init_str = "({c_type_c_name(mc_obj_name)})\{.tag = {tag}"
                if fcount > 0 && args_sl != -1 {
                    init_str = init_str.concat(", .data.{method} = \{")
                    let mut fi = 0
                    while fi < sublist_length(args_sl) && fi < fcount {
                        if fi > 0 {
                            init_str = init_str.concat(", ")
                        }
                        let field_name = get_variant_field_name(vidx, fi)
                        emit_expr(sublist_get(args_sl, fi))
                        let arg_str = expr_result_str
                        init_str = init_str.concat(".{field_name} = {arg_str}")
                        fi = fi + 1
                    }
                    init_str = init_str.concat("}")
                }
                init_str = init_str.concat("}")
                expr_result_str = init_str
                expr_result_type = CT_INT
                return
            }
        }
    }

    // Bytes.new() and Bytes.from_str(s) — static constructors
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "Bytes" {
        if method == "new" {
            expr_result_str = "pact_bytes_new()"
            expr_result_type = CT_BYTES
            return
        }
        if method == "from_str" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                expr_result_str = "pact_bytes_from_str({arg_str})"
                expr_result_type = CT_BYTES
                return
            }
            expr_result_str = "pact_bytes_new()"
            expr_result_type = CT_BYTES
            return
        }
    }

    // Char.from_code_point(n) — static constructor
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "Char" {
        if method == "from_code_point" {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                expr_result_str = "pact_str_from_char_code({arg_str})"
                expr_result_type = CT_STRING
                return
            }
        }
    }

    // Duration static constructors: Duration.nanos(n), Duration.ms(n), etc.
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "Duration" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            if method == "nanos" {
                expr_result_str = "pact_duration_nanos({arg_str})"
                expr_result_type = CT_DURATION
                return
            }
            if method == "ms" {
                expr_result_str = "pact_duration_ms({arg_str})"
                expr_result_type = CT_DURATION
                return
            }
            if method == "seconds" {
                expr_result_str = "pact_duration_seconds({arg_str})"
                expr_result_type = CT_DURATION
                return
            }
            if method == "minutes" {
                expr_result_str = "pact_duration_minutes({arg_str})"
                expr_result_type = CT_DURATION
                return
            }
            if method == "hours" {
                expr_result_str = "pact_duration_hours({arg_str})"
                expr_result_type = CT_DURATION
                return
            }
        }
    }

    // Instant.from_epoch_secs(n) — static constructor
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "Instant" {
        let args_sl = np_args.get(node).unwrap()
        if method == "from_epoch_secs" && args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            expr_result_str = "(pact_instant)\{.nanos = {arg_str} * 1000000000LL}"
            expr_result_type = CT_INSTANT
            return
        }
    }

    // Special case: io.println — dispatch through IO vtable (unless in handler body)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "io" && method == "println" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if cg_in_handler_body != 0 {
                if arg_type == CT_INT {
                    emit_line("printf(\"%%lld\\n\", (long long){arg_str});")
                } else if arg_type == CT_FLOAT {
                    emit_line("printf(\"%%g\\n\", {arg_str});")
                } else if arg_type == CT_BOOL {
                    emit_line("printf(\"%%s\\n\", {arg_str} ? \"true\" : \"false\");")
                } else {
                    emit_line("printf(\"%%s\\n\", {arg_str});")
                }
            } else {
                if arg_type == CT_INT {
                    let tmp = fresh_temp("_io_")
                    emit_line("char {tmp}[64]; snprintf({tmp}, 64, \"%%lld\", (long long){arg_str});")
                    emit_line("__pact_ctx.io->print({tmp});")
                } else if arg_type == CT_FLOAT {
                    let tmp = fresh_temp("_io_")
                    emit_line("char {tmp}[64]; snprintf({tmp}, 64, \"%%g\", {arg_str});")
                    emit_line("__pact_ctx.io->print({tmp});")
                } else if arg_type == CT_BOOL {
                    emit_line("__pact_ctx.io->print({arg_str} ? \"true\" : \"false\");")
                } else {
                    emit_line("__pact_ctx.io->print({arg_str});")
                }
            }
        } else {
            if cg_in_handler_body != 0 {
                emit_line("printf(\"\\n\");")
            } else {
                emit_line("__pact_ctx.io->print(\"\");")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.print — like println but no trailing newline (direct printf, no vtable)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "io" && method == "print" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("printf(\"%%lld\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("printf(\"%%g\", {arg_str});")
            } else if arg_type == CT_BOOL {
                emit_line("printf(\"%%s\", {arg_str} ? \"true\" : \"false\");")
            } else {
                emit_line("printf(\"%%s\", {arg_str});")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.eprintln — print to stderr with newline (direct fprintf)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "io" && method == "eprintln" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("fprintf(stderr, \"%%lld\\n\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("fprintf(stderr, \"%%g\\n\", {arg_str});")
            } else if arg_type == CT_BOOL {
                emit_line("fprintf(stderr, \"%%s\\n\", {arg_str} ? \"true\" : \"false\");")
            } else {
                emit_line("fprintf(stderr, \"%%s\\n\", {arg_str});")
            }
        } else {
            emit_line("fprintf(stderr, \"\\n\");")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.eprint — print to stderr without newline
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "io" && method == "eprint" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("fprintf(stderr, \"%%lld\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("fprintf(stderr, \"%%g\", {arg_str});")
            } else if arg_type == CT_BOOL {
                emit_line("fprintf(stderr, \"%%s\", {arg_str} ? \"true\" : \"false\");")
            } else {
                emit_line("fprintf(stderr, \"%%s\", {arg_str});")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // io.log — log to stderr
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "io" && method == "log" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let arg_type = expr_result_type
            if arg_type == CT_INT {
                emit_line("fprintf(stderr, \"[LOG] %%lld\\n\", (long long){arg_str});")
            } else if arg_type == CT_FLOAT {
                emit_line("fprintf(stderr, \"[LOG] %%g\\n\", {arg_str});")
            } else {
                emit_line("fprintf(stderr, \"[LOG] %%s\\n\", {arg_str});")
            }
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // time.read() — returns pact_instant via Time vtable
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "time" && method == "read" {
        expr_result_str = "__pact_ctx.time->read()"
        expr_result_type = CT_INSTANT
        return
    }

    // time.sleep(duration) — accepts pact_duration via Time vtable
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "time" && method == "sleep" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let dur_str = expr_result_str
            emit_line("__pact_ctx.time->sleep({dur_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // ── net.* operations ────────────────────────────────────────────

    // net.request(req_idx) — HTTP request via libcurl, returns response index
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "request" {
        cg_uses_curl = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let req_str = expr_result_str
            let tmp_req = fresh_temp("__req_idx_")
            let tmp_method = fresh_temp("__method_")
            let tmp_method_str = fresh_temp("__method_str_")
            let tmp_url = fresh_temp("__url_")
            let tmp_body = fresh_temp("__body_")
            let tmp_hdr_count = fresh_temp("__hdr_count_")
            let tmp_hdr_names = fresh_temp("__hdr_names_")
            let tmp_hdr_vals = fresh_temp("__hdr_vals_")
            let tmp_out_body = fresh_temp("__out_body_")
            let tmp_out_status = fresh_temp("__out_status_")
            let tmp_resp = fresh_temp("__resp_idx_")
            let tmp_hi = fresh_temp("__hi_")
            let tmp_hj = fresh_temp("__hj_")

            emit_line("int64_t {tmp_req} = {req_str};")
            emit_line("int64_t {tmp_method} = (int64_t)(intptr_t)pact_list_get(req_methods, {tmp_req});")
            emit_line("const char* {tmp_method_str} = pact_method_to_str({tmp_method});")
            emit_line("const char* {tmp_url} = (const char*)pact_list_get(req_paths, {tmp_req});")
            emit_line("const char* {tmp_body} = (const char*)pact_list_get(req_bodies, {tmp_req});")

            // Collect headers matching this request
            emit_line("int64_t {tmp_hdr_count} = 0;")
            emit_line("for (int64_t {tmp_hi} = 0; {tmp_hi} < pact_list_len(req_header_owners); {tmp_hi}++) \{")
            emit_line("  if ((int64_t)(intptr_t)pact_list_get(req_header_owners, {tmp_hi}) == {tmp_req}) {tmp_hdr_count}++;")
            emit_line("}")
            emit_line("const char** {tmp_hdr_names} = (const char**)pact_alloc(sizeof(const char*) * ({tmp_hdr_count} + 1));")
            emit_line("const char** {tmp_hdr_vals} = (const char**)pact_alloc(sizeof(const char*) * ({tmp_hdr_count} + 1));")
            emit_line("int64_t {tmp_hj} = 0;")
            emit_line("for (int64_t {tmp_hi} = 0; {tmp_hi} < pact_list_len(req_header_owners); {tmp_hi}++) \{")
            emit_line("  if ((int64_t)(intptr_t)pact_list_get(req_header_owners, {tmp_hi}) == {tmp_req}) \{")
            emit_line("    {tmp_hdr_names}[{tmp_hj}] = (const char*)pact_list_get(req_header_names, {tmp_hi});")
            emit_line("    {tmp_hdr_vals}[{tmp_hj}] = (const char*)pact_list_get(req_header_values, {tmp_hi});")
            emit_line("    {tmp_hj}++;")
            emit_line("  }")
            emit_line("}")

            // Call curl
            emit_line("const char* {tmp_out_body} = NULL;")
            emit_line("int64_t {tmp_out_status} = 0;")
            emit_line("int __curl_rc = pact_curl_perform({tmp_method_str}, {tmp_url}, {tmp_body}, {tmp_hdr_names}, {tmp_hdr_vals}, {tmp_hdr_count}, &{tmp_out_body}, &{tmp_out_status});")

            // Build response
            emit_line("int64_t {tmp_resp};")
            emit_line("if (__curl_rc != 0) \{")
            emit_line("  {tmp_resp} = -1;")
            emit_line("} else \{")
            emit_line("  {tmp_resp} = pact_list_len(resp_statuses);")
            emit_line("  pact_list_push(resp_statuses, (void*)(intptr_t){tmp_out_status});")
            emit_line("  pact_list_push(resp_bodies, (void*){tmp_out_body});")
            emit_line("}")

            expr_result_str = tmp_resp
        } else {
            expr_result_str = "-1"
        }
        expr_result_type = CT_INT
        return
    }

    // net.listen(addr, port) — TCP listen, returns fd
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "listen" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let addr_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let port_str = expr_result_str
            let tmp = fresh_temp("__listen_fd_")
            emit_line("int64_t {tmp} = pact_tcp_listen({addr_str}, {port_str});")
            expr_result_str = tmp
        } else {
            expr_result_str = "-1"
        }
        expr_result_type = CT_INT
        return
    }

    // net.accept(fd) — TCP accept, returns client fd
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "accept" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            let tmp = fresh_temp("__accept_fd_")
            emit_line("int64_t {tmp} = pact_tcp_accept({fd_str});")
            expr_result_str = tmp
        } else {
            expr_result_str = "-1"
        }
        expr_result_type = CT_INT
        return
    }

    // net.read_line(fd) — read line from socket
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "read_line" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            let tmp = fresh_temp("__rline_")
            emit_line("const char* {tmp} = pact_socket_read_line({fd_str});")
            expr_result_str = tmp
        } else {
            expr_result_str = "\"\""
        }
        expr_result_type = CT_STRING
        return
    }

    // net.read_n(fd, n) — read exactly n bytes
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "read_n" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let n_str = expr_result_str
            let tmp = fresh_temp("__rn_")
            emit_line("const char* {tmp} = pact_socket_read_n({fd_str}, {n_str});")
            expr_result_str = tmp
        } else {
            expr_result_str = "\"\""
        }
        expr_result_type = CT_STRING
        return
    }

    // net.write(fd, data) — write data to socket
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "write" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let data_str = expr_result_str
            emit_line("pact_socket_write({fd_str}, {data_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // net.write_line(fd, data) — write data + CRLF to socket
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "write_line" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let data_str = expr_result_str
            emit_line("pact_socket_write_line({fd_str}, {data_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // net.close(fd) — close socket
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "close" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let fd_str = expr_result_str
            emit_line("close((int){fd_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // ── db.* operations (SQLite) ────────────────────────────────────

    // db.open(path) — open database, sets global __pact_db, returns opaque handle as Int
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "open" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            emit_line("__pact_db = pact_sqlite3_open({arg_str});")
            expr_result_str = "(int64_t)(intptr_t)__pact_db"
            expr_result_type = CT_INT
            return
        }
    }

    // db.close(handle) — close database connection
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "close" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            emit_line("pact_sqlite3_close((void*)(intptr_t){arg_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.exec(sql) — execute SQL (DDL/DML), no return value
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "exec" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            emit_line("pact_sqlite3_exec(__pact_db, {arg_str}, NULL, NULL, NULL);")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.execute(sql) — execute SQL, returns last insert rowid as Int
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "execute" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_exec_")
            emit_line("pact_sqlite3_exec(__pact_db, {arg_str}, NULL, NULL, NULL);")
            emit_line("int64_t {tmp} = (int64_t)sqlite3_last_insert_rowid((sqlite3*)__pact_db);")
            expr_result_str = tmp
            expr_result_type = CT_INT
            return
        }
    }

    // db.query(sql) — execute query, returns List[List[Str]]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "query" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_qr_")
            let tmp_rows = fresh_temp("__db_rows_")
            emit_line("pact_sqlite3_result* {tmp} = pact_sqlite3_query(__pact_db, {arg_str});")
            emit_line("pact_list* {tmp_rows} = {tmp}->rows;")
            set_list_elem_type(tmp_rows, CT_LIST)
            set_list_nested_elem_type(tmp_rows, CT_STRING)
            expr_result_str = tmp_rows
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_LIST
            return
        }
    }

    // db.query_one(sql) — query returning first row or None (Option[List[Str]])
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "query_one" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            ensure_option_type(CT_LIST)
            let opt_type = option_c_type(CT_LIST)
            let tmp_res = fresh_temp("__db_qr_")
            let tmp_opt = fresh_temp("__db_opt_")
            emit_line("pact_sqlite3_result* {tmp_res} = pact_sqlite3_query(__pact_db, {arg_str});")
            emit_line("{opt_type} {tmp_opt};")
            emit_line("if ({tmp_res}->num_rows > 0) \{")
            emit_line("  {tmp_opt}.tag = 1;")
            emit_line("  {tmp_opt}.value = (pact_list*)pact_list_get({tmp_res}->rows, 0);")
            emit_line("} else \{")
            emit_line("  {tmp_opt}.tag = 0;")
            emit_line("}")
            set_var_option(tmp_opt, CT_LIST)
            set_var_option_inner2(tmp_opt, CT_STRING)
            expr_result_str = tmp_opt
            expr_result_type = CT_OPTION
            expr_option_inner = CT_LIST
            expr_option_inner_struct = ""
            expr_option_inner_list_elem = CT_STRING
            return
        }
    }

    // db.prepare(sql) — prepare statement, returns opaque handle as Int
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "prepare" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_stmt_")
            emit_line("void* {tmp} = pact_sqlite3_prepare(__pact_db, {arg_str});")
            expr_result_str = "(int64_t)(intptr_t){tmp}"
            expr_result_type = CT_INT
            return
        }
    }

    // db.bind_int(stmt, idx, val) — bind Int parameter to prepared statement
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "bind_int" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 3 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let idx_str = expr_result_str
            emit_expr(sublist_get(args_sl, 2))
            let val_str = expr_result_str
            emit_line("pact_sqlite3_bind_int((void*)(intptr_t){stmt_str}, {idx_str}, {val_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.bind_text(stmt, idx, val) — bind Str parameter to prepared statement
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "bind_text" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 3 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let idx_str = expr_result_str
            emit_expr(sublist_get(args_sl, 2))
            let val_str = expr_result_str
            emit_line("pact_sqlite3_bind_text((void*)(intptr_t){stmt_str}, {idx_str}, {val_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.step(stmt) — step prepared statement, returns status code
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "step" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_step((void*)(intptr_t){stmt_str});")
            expr_result_str = tmp
            expr_result_type = CT_INT
            return
        }
    }

    // db.column_int(stmt, col) — get Int from column in current row
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "column_int" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let col_str = expr_result_str
            let tmp = fresh_temp("__db_ci_")
            emit_line("int64_t {tmp} = pact_sqlite3_column_int((void*)(intptr_t){stmt_str}, {col_str});")
            expr_result_str = tmp
            expr_result_type = CT_INT
            return
        }
    }

    // db.column_text(stmt, col) — get Str from column in current row
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "column_text" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let col_str = expr_result_str
            let tmp = fresh_temp("__db_ct_")
            emit_line("const char* {tmp} = pact_sqlite3_column_text((void*)(intptr_t){stmt_str}, {col_str});")
            expr_result_str = tmp
            expr_result_type = CT_STRING
            return
        }
    }

    // db.reset(stmt) — reset prepared statement for re-execution
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "reset" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_line("pact_sqlite3_reset((void*)(intptr_t){stmt_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.finalize(stmt) — finalize (destroy) prepared statement
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "finalize" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let stmt_str = expr_result_str
            emit_line("pact_sqlite3_finalize((void*)(intptr_t){stmt_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // db.errmsg(handle) — get last error message from database
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "errmsg" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_err_")
            emit_line("const char* {tmp} = pact_sqlite3_errmsg((void*)(intptr_t){arg_str});")
            expr_result_str = tmp
        } else {
            let tmp = fresh_temp("__db_err_")
            emit_line("const char* {tmp} = pact_sqlite3_errmsg(__pact_db);")
            expr_result_str = tmp
        }
        expr_result_type = CT_STRING
        return
    }

    // db.begin(handle) — begin transaction
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "begin" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_begin((void*)(intptr_t){arg_str});")
            expr_result_str = tmp
        } else {
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_begin(__pact_db);")
            expr_result_str = tmp
        }
        expr_result_type = CT_INT
        return
    }

    // db.commit(handle) — commit transaction
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "commit" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_commit((void*)(intptr_t){arg_str});")
            expr_result_str = tmp
        } else {
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_commit(__pact_db);")
            expr_result_str = tmp
        }
        expr_result_type = CT_INT
        return
    }

    // db.rollback(handle) — rollback transaction
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "db" && method == "rollback" {
        cg_uses_sqlite = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_rollback((void*)(intptr_t){arg_str});")
            expr_result_str = tmp
        } else {
            let tmp = fresh_temp("__db_rc_")
            emit_line("int64_t {tmp} = pact_sqlite3_rollback(__pact_db);")
            expr_result_str = tmp
        }
        expr_result_type = CT_INT
        return
    }

    // async.spawn(closure) — spawn async task on thread pool
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "async" && method == "spawn" {
        cg_uses_async = 1
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            let spawn_arg_node = sublist_get(args_sl, 0)
            let wrapper_idx = cg_async_wrapper_counter
            cg_async_wrapper_counter = cg_async_wrapper_counter + 1
            let wrapper_name = "__async_wrapper_{wrapper_idx}"
            let task_fn_name = "__async_task_{wrapper_idx}"
            let handle_tmp = fresh_temp("__handle_")
            let arg_tmp = fresh_temp("__spawn_arg_")

            if np_kind.get(spawn_arg_node).unwrap() == NodeKind.Closure {
                let cap_reg_idx = closure_cap_infos.len()
                emit_async_spawn_closure(spawn_arg_node, wrapper_idx, wrapper_name, task_fn_name)

                emit_line("pact_handle* {handle_tmp} = pact_handle_new();")
                emit_line("__async_arg_{wrapper_idx}_t* {arg_tmp} = (__async_arg_{wrapper_idx}_t*)pact_alloc(sizeof(__async_arg_{wrapper_idx}_t));")
                emit_line("{arg_tmp}->handle = {handle_tmp};")
                let ac_info = closure_cap_infos.get(cap_reg_idx).unwrap()
                if ac_info.count > 0 {
                    let caps_var = "__acaps_{wrapper_idx}"
                    emit_line("void** {caps_var} = (void**)pact_alloc(sizeof(void*) * {ac_info.count});")
                    let mut ci2 = 0
                    while ci2 < ac_info.count {
                        let cap_e = closure_captures.get(ac_info.start + ci2).unwrap()
                        if cap_e.is_mut != 0 {
                            emit_line("{caps_var}[{ci2}] = (void*){cap_e.name}_cell;")
                        } else if cap_e.ctype == CT_INT {
                            emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
                        } else if cap_e.ctype == CT_FLOAT {
                            let fp_tmp = fresh_temp("__fp_")
                            emit_line("\{double* {fp_tmp} = (double*)pact_alloc(sizeof(double)); *{fp_tmp} = {cap_e.name}; {caps_var}[{ci2}] = (void*){fp_tmp};}")
                        } else if cap_e.ctype == CT_BOOL {
                            emit_line("{caps_var}[{ci2}] = (void*)(intptr_t){cap_e.name};")
                        } else {
                            emit_line("{caps_var}[{ci2}] = (void*){cap_e.name};")
                        }
                        ci2 = ci2 + 1
                    }
                    emit_line("{arg_tmp}->captures = {caps_var};")
                    emit_line("{arg_tmp}->capture_count = {ac_info.count};")
                }
                emit_line("pact_threadpool_submit(__pact_pool, {wrapper_name}, (void*){arg_tmp});")
            } else {
                emit_expr(spawn_arg_node)
                let closure_str = expr_result_str
                cg_closure_defs.push("typedef struct \{")
                cg_closure_defs.push("    pact_closure* closure;")
                cg_closure_defs.push("    pact_handle* handle;")
                cg_closure_defs.push("} __async_arg_{wrapper_idx}_t;")
                cg_closure_defs.push("")
                cg_closure_defs.push("static void {wrapper_name}(void* __arg) \{")
                cg_closure_defs.push("    __async_arg_{wrapper_idx}_t* __a = (__async_arg_{wrapper_idx}_t*)__arg;")
                cg_closure_defs.push("    pact_closure* __cl = __a->closure;")
                cg_closure_defs.push("    pact_handle* __h = __a->handle;")
                cg_closure_defs.push("    int64_t __r = ((int64_t(*)(const pact_closure*))__cl->fn_ptr)(__cl);")
                cg_closure_defs.push("    pact_handle_set_result(__h, (void*)(intptr_t)__r);")
                cg_closure_defs.push("    free(__arg);")
                cg_closure_defs.push("}")
                cg_closure_defs.push("")

                emit_line("pact_handle* {handle_tmp} = pact_handle_new();")
                emit_line("__async_arg_{wrapper_idx}_t* {arg_tmp} = (__async_arg_{wrapper_idx}_t*)pact_alloc(sizeof(__async_arg_{wrapper_idx}_t));")
                emit_line("{arg_tmp}->closure = {closure_str};")
                emit_line("{arg_tmp}->handle = {handle_tmp};")
                emit_line("pact_threadpool_submit(__pact_pool, {wrapper_name}, (void*){arg_tmp});")
            }

            if cg_async_scope_stack.len() > 0 {
                let scope_list = cg_async_scope_stack.get(cg_async_scope_stack.len() - 1).unwrap()
                emit_line("pact_list_push({scope_list}, (void*){handle_tmp});")
            }

            set_var_handle(handle_tmp, CT_INT)
            expr_result_str = handle_tmp
            expr_result_type = CT_HANDLE
        } else {
            expr_result_str = "0"
            expr_result_type = CT_VOID
        }
        return
    }

    // fs.read — read file contents
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "fs" && method == "read" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            expr_result_str = "pact_read_file({arg_str})"
            expr_result_type = CT_STRING
        } else {
            expr_result_str = "\"\""
            expr_result_type = CT_STRING
        }
        return
    }

    // fs.write — write file contents
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "fs" && method == "write" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let path_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let content_str = expr_result_str
            emit_line("pact_write_file({path_str}, {content_str});")
        }
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // fs.list_dir — list directory contents
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "fs" && method == "list_dir" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 1 {
            emit_expr(sublist_get(args_sl, 0))
            let arg_str = expr_result_str
            expr_result_str = "pact_list_dir({arg_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
        } else {
            expr_result_str = "pact_list_new()"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
        }
        return
    }

    // env.args — return List[Str] of command-line arguments
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "env" && method == "args" {
        let tmp = fresh_temp("_args_")
        emit_line("pact_list* {tmp} = pact_list_new();")
        emit_line("for (int __ai = 0; __ai < pact_g_argc; __ai++) \{")
        emit_line("    pact_list_push({tmp}, (void*)pact_g_argv[__ai]);")
        emit_line("}")
        set_list_elem_type(tmp, CT_STRING)
        expr_result_str = tmp
        expr_result_type = CT_LIST
        expr_list_elem_type = CT_STRING
        return
    }

    // default.method(args) — delegate to outer handler inside handler body
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "default" && cg_in_handler_body != 0 {
        let outer_name = "__handler_{cg_handler_body_idx}_outer"
        let args_sl = np_args.get(node).unwrap()
        let mut args_str = ""
        if args_sl != -1 {
            let mut ai = 0
            while ai < sublist_length(args_sl) {
                if ai > 0 {
                    args_str = args_str.concat(", ")
                }
                emit_expr(sublist_get(args_sl, ai))
                args_str = args_str.concat(expr_result_str)
                ai = ai + 1
            }
        }
        expr_result_str = "{outer_name}->{method}({args_str})"
        expr_result_type = CT_VOID
        return
    }

    // User-defined effect handle dispatch: handle.method(args) -> __pact_ue_handle->method(args)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let handle_name = np_name.get(obj_node).unwrap()
        if is_user_effect_handle(handle_name) != 0 {
            let args_sl = np_args.get(node).unwrap()
            let mut args_str = ""
            if args_sl != -1 {
                let mut ai = 0
                while ai < sublist_length(args_sl) {
                    if ai > 0 {
                        args_str = args_str.concat(", ")
                    }
                    emit_expr(sublist_get(args_sl, ai))
                    args_str = args_str.concat(expr_result_str)
                    ai = ai + 1
                }
            }
            let mut ue_ret_type = CT_VOID
            let mut mi = 0
            while mi < ue_methods.len() {
                let uem = ue_methods.get(mi).unwrap()
                if uem.effect_handle == handle_name && uem.name == method {
                    if uem.ret == "int64_t" {
                        ue_ret_type = CT_INT
                    } else if uem.ret == "const char*" {
                        ue_ret_type = CT_STRING
                    } else if uem.ret == "double" {
                        ue_ret_type = CT_FLOAT
                    } else if uem.ret == "int" {
                        ue_ret_type = CT_BOOL
                    }
                    break
                }
                mi = mi + 1
            }
            if ue_ret_type == CT_VOID {
                emit_line("__pact_ue_{handle_name}->{method}({args_str});")
                expr_result_str = "0"
            } else {
                expr_result_str = "__pact_ue_{handle_name}->{method}({args_str})"
            }
            expr_result_type = ue_ret_type
            return
        }
    }

    // Qualified trait call: Trait.method(args) parsed as MethodCall(obj=Trait, method=method)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let trait_name = np_name.get(obj_node).unwrap()
        if is_trait_type(trait_name) != 0 {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let first_str = expr_result_str
                let type_name = get_var_struct(first_str)
                if type_name != "" {
                    let mangled = "{type_name}_{method}"
                    let mut args_str = first_str
                    let mut i = 1
                    while i < sublist_length(args_sl) {
                        args_str = args_str.concat(", ")
                        emit_expr(sublist_get(args_sl, i))
                        args_str = args_str.concat(expr_result_str)
                        i = i + 1
                    }
                    expr_result_str = "{c_fn_name(mangled)}({args_str})"
                    expr_result_type = get_impl_method_ret(type_name, method)
                    return
                }
            }
        }
    }

    // Static From dispatch: Type.from(value)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let target_type = np_name.get(obj_node).unwrap()
        if method == "from" && (is_struct_type(target_type) != 0 || is_enum_type(target_type) != 0) {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                let arg_type = expr_result_type
                let source_type = type_name_from_ct(arg_type)
                let arg_struct = get_var_struct(arg_str)
                let mut src = source_type
                if arg_struct != "" {
                    src = arg_struct
                }
                let from_methods = find_from_impl(src, target_type)
                if from_methods != -1 && sublist_length(from_methods) > 0 {
                    let from_fn = sublist_get(from_methods, 0)
                    let from_name = np_name.get(from_fn).unwrap()
                    let mangled = "{target_type}_{from_name}"
                    expr_result_str = "{c_fn_name(mangled)}({arg_str})"
                    expr_result_type = get_fn_ret(mangled)
                    if expr_result_type == CT_VOID {
                        set_var_struct(expr_result_str, target_type)
                    }
                    return
                }
            }
        }
    }

    // Static TryFrom dispatch: Type.try_from(value)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident {
        let target_type = np_name.get(obj_node).unwrap()
        if method == "try_from" && (is_struct_type(target_type) != 0 || is_enum_type(target_type) != 0) {
            let args_sl = np_args.get(node).unwrap()
            if args_sl != -1 && sublist_length(args_sl) > 0 {
                emit_expr(sublist_get(args_sl, 0))
                let arg_str = expr_result_str
                let arg_type = expr_result_type
                let source_type = type_name_from_ct(arg_type)
                let arg_struct = get_var_struct(arg_str)
                let mut src = source_type
                if arg_struct != "" {
                    src = arg_struct
                }
                let tf_methods = find_tryfrom_impl(src, target_type)
                if tf_methods != -1 && sublist_length(tf_methods) > 0 {
                    let tf_fn = sublist_get(tf_methods, 0)
                    let tf_name = np_name.get(tf_fn).unwrap()
                    let mangled = "{target_type}_{tf_name}"
                    expr_result_str = "{c_fn_name(mangled)}({arg_str})"
                    expr_result_type = get_fn_ret(mangled)
                    let tf_rt = get_fn_ret_type(mangled)
                    if tf_rt.inner1 != -1 && tf_rt.inner2 != -1 {
                        expr_result_ok_type = tf_rt.inner1
                        expr_result_err_type = tf_rt.inner2
                        set_var_result(expr_result_str, tf_rt.inner1, tf_rt.inner2)
                    }
                    return
                }
            }
        }
    }

    // net.request(req) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "request" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let req_str = expr_result_str

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request({req_str}.method, {req_str}.url, {req_str}.body, {req_str}.headers, {req_str}.timeout_ms, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.get(url) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "get" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"GET\", {url_str}, \"\", NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.post(url, body) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "post" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let body_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"POST\", {url_str}, {body_str}, NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.put(url, body) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "put" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let body_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"PUT\", {url_str}, {body_str}, NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.delete(url) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "delete" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"DELETE\", {url_str}, \"\", NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.head(url) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "head" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) > 0 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"HEAD\", {url_str}, \"\", NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.patch(url, body) -> Result[Response, NetError]
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "patch" {
        let args_sl = np_args.get(node).unwrap()
        if args_sl != -1 && sublist_length(args_sl) >= 2 {
            emit_expr(sublist_get(args_sl, 0))
            let url_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let body_str = expr_result_str

            ensure_struct_result_type("Response", "NetError")
            let result_type = struct_result_c_type("Response", "NetError")

            let status_tmp = fresh_temp("__http_status_")
            let body_tmp = fresh_temp("__http_body_")
            let hdrs_tmp = fresh_temp("__http_hdrs_")
            let rc_tmp = fresh_temp("__http_rc_")
            let result_tmp = fresh_temp("__http_result_")

            emit_line("int64_t {status_tmp} = 0;")
            emit_line("const char* {body_tmp} = \"\";")
            emit_line("pact_map* {hdrs_tmp} = NULL;")
            emit_line("int {rc_tmp} = pact_http_request(\"PATCH\", {url_str}, {body_str}, NULL, 30000, &{status_tmp}, &{body_tmp}, &{hdrs_tmp});")
            emit_line("{result_type} {result_tmp};")
            emit_line("if ({rc_tmp} == 0) \{")
            emit_line("    {result_tmp}.tag = 0;")
            emit_line("    {result_tmp}.ok.status = {status_tmp};")
            emit_line("    {result_tmp}.ok.body = {body_tmp};")
            emit_line("    {result_tmp}.ok.headers = {hdrs_tmp} ? {hdrs_tmp} : pact_map_new();")
            emit_line("} else \{")
            emit_line("    {result_tmp}.tag = 1;")
            emit_line("    {result_tmp}.err.tag = 1;")
            emit_line("    {result_tmp}.err.data.ConnectionRefused.msg = {body_tmp} ? {body_tmp} : \"request failed\";")
            emit_line("}")

            set_var_struct(result_tmp, "")
            set_var_result_struct(result_tmp, CT_VOID, CT_VOID, "Response", "NetError")
            expr_result_str = result_tmp
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_VOID
            expr_result_err_type = CT_VOID
            expr_result_ok_struct = "Response"
            expr_result_err_struct = "NetError"
        }
        return
    }

    // net.listen(host, port) -> Int
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "listen" {
        let args_sl = np_args.get(node).unwrap()
        emit_expr(sublist_get(args_sl, 0))
        let host_str = expr_result_str
        emit_expr(sublist_get(args_sl, 1))
        let port_str = expr_result_str
        expr_result_str = "pact_tcp_listen({host_str}, {port_str})"
        expr_result_type = CT_INT
        return
    }

    // net.accept(fd) -> Int
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "accept" {
        let args_sl = np_args.get(node).unwrap()
        emit_expr(sublist_get(args_sl, 0))
        let fd_str = expr_result_str
        expr_result_str = "pact_tcp_accept({fd_str})"
        expr_result_type = CT_INT
        return
    }

    // net.read(fd, max_bytes) -> Str
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "read" {
        let args_sl = np_args.get(node).unwrap()
        emit_expr(sublist_get(args_sl, 0))
        let fd_str = expr_result_str
        emit_expr(sublist_get(args_sl, 1))
        let max_str = expr_result_str
        expr_result_str = "pact_tcp_read({fd_str}, {max_str})"
        expr_result_type = CT_STRING
        return
    }

    // net.write(fd, data)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "write" {
        let args_sl = np_args.get(node).unwrap()
        emit_expr(sublist_get(args_sl, 0))
        let fd_str = expr_result_str
        emit_expr(sublist_get(args_sl, 1))
        let data_str = expr_result_str
        emit_line("pact_tcp_write({fd_str}, {data_str});")
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    // net.close(fd)
    if np_kind.get(obj_node).unwrap() == NodeKind.Ident && np_name.get(obj_node).unwrap() == "net" && method == "close" {
        let args_sl = np_args.get(node).unwrap()
        emit_expr(sublist_get(args_sl, 0))
        let fd_str = expr_result_str
        emit_line("pact_tcp_close({fd_str});")
        expr_result_str = "0"
        expr_result_type = CT_VOID
        return
    }

    emit_expr(obj_node)
    let obj_str = expr_result_str
    let obj_type = expr_result_type

    // .into() dispatch — infer target type from assignment context
    if method == "into" {
        let target = cg_let_target_type
        if target == CT_FLOAT && obj_type == CT_INT {
            expr_result_str = "(double){obj_str}"
            expr_result_type = CT_FLOAT
            return
        }
        if target == CT_INT && obj_type == CT_FLOAT {
            expr_result_str = "(int64_t){obj_str}"
            expr_result_type = CT_INT
            return
        }
        if target == CT_STRING && obj_type == CT_INT {
            expr_result_str = "pact_int_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if target == CT_STRING && obj_type == CT_FLOAT {
            expr_result_str = "pact_float_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        let mut src_name = type_name_from_ct(obj_type)
        let src_struct = get_var_struct(obj_str)
        if src_struct != "" {
            src_name = src_struct
        }
        let mut tgt_name = type_name_from_ct(target)
        if target == CT_VOID && cg_let_target_name != "" {
            tgt_name = cg_let_target_name
        }
        let from_methods = find_from_impl(src_name, tgt_name)
        if from_methods != -1 && sublist_length(from_methods) > 0 {
            let from_fn = sublist_get(from_methods, 0)
            let from_name = np_name.get(from_fn).unwrap()
            let mangled = "{tgt_name}_{from_name}"
            expr_result_str = "{c_fn_name(mangled)}({obj_str})"
            expr_result_type = target
            return
        }
        emit_line("/* into() conversion not found */")
        expr_result_str = obj_str
        expr_result_type = obj_type
        return
    }

    // Numeric conversion methods
    if method == "to_float" && obj_type == CT_INT {
        expr_result_str = "(double){obj_str}"
        expr_result_type = CT_FLOAT
        return
    }
    if method == "to_int" && obj_type == CT_FLOAT {
        expr_result_str = "(int64_t){obj_str}"
        expr_result_type = CT_INT
        return
    }
    if method == "to_int" && obj_type == CT_STRING {
        expr_result_str = "(int64_t)atoll({obj_str})"
        expr_result_type = CT_INT
        return
    }
    if method == "to_string" {
        if obj_type == CT_INT {
            expr_result_str = "pact_int_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if obj_type == CT_FLOAT {
            expr_result_str = "pact_float_to_str({obj_str})"
            expr_result_type = CT_STRING
            return
        }
    }

    // String methods
    if obj_type == CT_STRING {
        if method == "len" {
            expr_result_str = "pact_str_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "char_at" || method == "charAt" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            expr_result_str = "pact_str_char_at({obj_str}, {idx_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "substring" || method == "substr" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let start_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let len_str = expr_result_str
            expr_result_str = "pact_str_substr({obj_str}, {start_str}, {len_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "contains" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let needle_str = expr_result_str
            expr_result_str = "pact_str_contains({obj_str}, {needle_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "starts_with" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let pfx_str = expr_result_str
            expr_result_str = "pact_str_starts_with({obj_str}, {pfx_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "ends_with" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let sfx_str = expr_result_str
            expr_result_str = "pact_str_ends_with({obj_str}, {sfx_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "concat" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_str_concat({obj_str}, {other_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "slice" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let start_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let end_str = expr_result_str
            expr_result_str = "pact_str_slice({obj_str}, {start_str}, {end_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "to_int" {
            expr_result_str = "pact_parse_int({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "split" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let delim_str = expr_result_str
            expr_result_str = "pact_str_split({obj_str}, {delim_str})"
            expr_result_type = CT_LIST
            set_list_elem_type(expr_result_str, CT_STRING)
            expr_list_elem_type = CT_STRING
            return
        }
        if method == "trim" {
            expr_result_str = "pact_str_trim({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "to_upper" {
            expr_result_str = "pact_str_to_upper({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "to_lower" {
            expr_result_str = "pact_str_to_lower({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "replace" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let needle_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let repl_str = expr_result_str
            expr_result_str = "pact_str_replace({obj_str}, {needle_str}, {repl_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "index_of" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let needle_str = expr_result_str
            expr_result_str = "pact_str_index_of({obj_str}, {needle_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "lines" {
            expr_result_str = "pact_str_lines({obj_str})"
            expr_result_type = CT_LIST
            set_list_elem_type(expr_result_str, CT_STRING)
            expr_list_elem_type = CT_STRING
            return
        }
        if method == "is_empty" {
            expr_result_str = "(strlen({obj_str}) == 0)"
            expr_result_type = CT_BOOL
            return
        }
        if method == "parse_float" {
            expr_result_str = "pact_parse_float({obj_str})"
            expr_result_type = CT_FLOAT
            return
        }
    }

    // List methods
    if obj_type == CT_LIST {
        if method == "push" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let val_str = expr_result_str
            let val_type = expr_result_type
            if val_type != CT_INT {
                set_list_elem_type(obj_str, val_type)
            }
            let val_struct = get_var_struct(val_str)
            if val_type == CT_VOID && val_struct != "" {
                set_list_elem_struct(obj_str, val_struct)
                set_list_elem_type(obj_str, CT_VOID)
                let box_tmp = fresh_temp("_box")
                emit_line("{c_type_c_name(val_struct)}* {box_tmp} = ({c_type_c_name(val_struct)}*)pact_alloc(sizeof({c_type_c_name(val_struct)}));")
                emit_line("*{box_tmp} = {val_str};")
                emit_line("pact_list_push({obj_str}, (void*){box_tmp});")
            } else if val_type == CT_INT {
                emit_line("pact_list_push({obj_str}, (void*)(intptr_t){val_str});")
            } else if val_type == CT_FLOAT {
                let box_tmp = fresh_temp("_fbox")
                emit_line("double* {box_tmp} = (double*)pact_alloc(sizeof(double));")
                emit_line("*{box_tmp} = {val_str};")
                emit_line("pact_list_push({obj_str}, (void*){box_tmp});")
            } else {
                emit_line("pact_list_push({obj_str}, (void*){val_str});")
            }
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "pop" {
            let elem_type = get_list_elem_type(obj_str)
            let elem_struct = get_list_elem_struct(obj_str)
            let res = fresh_temp("_lpop_")
            if elem_type == CT_VOID && elem_struct != "" {
                ensure_struct_option_type(elem_struct)
                let opt_type = struct_option_c_type(elem_struct)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_len({obj_str}) > 0) \{")
                emit_line("    {res}.tag = 1; {res}.value = *({c_type_c_name(elem_struct)}*)pact_list_pop({obj_str});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option_struct(res, CT_VOID, elem_struct)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_VOID
                expr_option_inner_struct = elem_struct
            } else if elem_type == CT_STRING {
                ensure_option_type(CT_STRING)
                let opt_type = option_c_type(CT_STRING)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_len({obj_str}) > 0) \{")
                emit_line("    {res}.tag = 1; {res}.value = (const char*)pact_list_pop({obj_str});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_STRING)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_STRING
                expr_option_inner_struct = ""
            } else if elem_type == CT_FLOAT {
                ensure_option_type(CT_FLOAT)
                let opt_type = option_c_type(CT_FLOAT)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_len({obj_str}) > 0) \{")
                emit_line("    {res}.tag = 1; {res}.value = *(double*)pact_list_pop({obj_str});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_FLOAT)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_FLOAT
                expr_option_inner_struct = ""
            } else if elem_type == CT_LIST {
                ensure_option_type(CT_LIST)
                let opt_type = option_c_type(CT_LIST)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_len({obj_str}) > 0) \{")
                emit_line("    {res}.tag = 1; {res}.value = (pact_list*)pact_list_pop({obj_str});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_LIST)
                let pop_nested = get_list_nested_elem_type(obj_str)
                if pop_nested != -1 {
                    set_var_option_inner2(res, pop_nested)
                }
                let pop_nested_s = get_list_nested_elem_struct(obj_str)
                if pop_nested_s != "" {
                    set_var_option_inner2_struct(res, pop_nested_s)
                }
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_LIST
                expr_option_inner_struct = ""
                expr_option_inner_list_elem = pop_nested
                expr_option_inner_list_struct = pop_nested_s
            } else {
                ensure_option_type(CT_INT)
                let opt_type = option_c_type(CT_INT)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_len({obj_str}) > 0) \{")
                emit_line("    {res}.tag = 1; {res}.value = (int64_t)(intptr_t)pact_list_pop({obj_str});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_INT)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_INT
                expr_option_inner_struct = ""
            }
            return
        }
        if method == "len" {
            expr_result_str = "pact_list_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "is_empty" {
            expr_result_str = "(pact_list_len({obj_str}) == 0)"
            expr_result_type = CT_BOOL
            return
        }
        if method == "get" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            let elem_type = get_list_elem_type(obj_str)
            let elem_struct = get_list_elem_struct(obj_str)
            let idx_tmp = fresh_temp("_lgi_")
            emit_line("int64_t {idx_tmp} = {idx_str};")
            let res = fresh_temp("_lget_")
            if elem_type == CT_VOID && elem_struct != "" {
                ensure_struct_option_type(elem_struct)
                let opt_type = struct_option_c_type(elem_struct)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_in_bounds({obj_str}, {idx_tmp})) \{")
                emit_line("    {res}.tag = 1; {res}.value = *({c_type_c_name(elem_struct)}*)pact_list_get({obj_str}, {idx_tmp});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option_struct(res, CT_VOID, elem_struct)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_VOID
                expr_option_inner_struct = elem_struct
            } else if elem_type == CT_STRING {
                ensure_option_type(CT_STRING)
                let opt_type = option_c_type(CT_STRING)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_in_bounds({obj_str}, {idx_tmp})) \{")
                emit_line("    {res}.tag = 1; {res}.value = (const char*)pact_list_get({obj_str}, {idx_tmp});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_STRING)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_STRING
                expr_option_inner_struct = ""
            } else if elem_type == CT_FLOAT {
                ensure_option_type(CT_FLOAT)
                let opt_type = option_c_type(CT_FLOAT)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_in_bounds({obj_str}, {idx_tmp})) \{")
                emit_line("    {res}.tag = 1; {res}.value = *(double*)pact_list_get({obj_str}, {idx_tmp});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_FLOAT)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_FLOAT
                expr_option_inner_struct = ""
            } else if elem_type == CT_LIST {
                ensure_option_type(CT_LIST)
                let opt_type = option_c_type(CT_LIST)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_in_bounds({obj_str}, {idx_tmp})) \{")
                emit_line("    {res}.tag = 1; {res}.value = (pact_list*)pact_list_get({obj_str}, {idx_tmp});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_LIST)
                let nested_et = get_list_nested_elem_type(obj_str)
                if nested_et != -1 {
                    set_var_option_inner2(res, nested_et)
                }
                let nested_es = get_list_nested_elem_struct(obj_str)
                if nested_es != "" {
                    set_var_option_inner2_struct(res, nested_es)
                }
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_LIST
                expr_option_inner_struct = ""
                expr_option_inner_list_elem = nested_et
                expr_option_inner_list_struct = nested_es
            } else {
                ensure_option_type(CT_INT)
                let opt_type = option_c_type(CT_INT)
                emit_line("{opt_type} {res};")
                emit_line("if (pact_list_in_bounds({obj_str}, {idx_tmp})) \{")
                emit_line("    {res}.tag = 1; {res}.value = (int64_t)(intptr_t)pact_list_get({obj_str}, {idx_tmp});")
                emit_line("} else \{ {res}.tag = 0; }")
                set_var_option(res, CT_INT)
                expr_result_str = res
                expr_result_type = CT_OPTION
                expr_option_inner = CT_INT
                expr_option_inner_struct = ""
            }
            return
        }
        if method == "set" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let val_str2 = expr_result_str
            let val_type2 = expr_result_type
            let val_struct2 = get_var_struct(val_str2)
            if val_type2 == CT_VOID && val_struct2 != "" {
                let box_tmp = fresh_temp("_box")
                emit_line("{c_type_c_name(val_struct2)}* {box_tmp} = ({c_type_c_name(val_struct2)}*)pact_alloc(sizeof({c_type_c_name(val_struct2)}));")
                emit_line("*{box_tmp} = {val_str2};")
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){box_tmp});")
            } else if val_type2 == CT_INT {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*)(intptr_t){val_str2});")
            } else if val_type2 == CT_FLOAT {
                let box_tmp = fresh_temp("_fbox")
                emit_line("double* {box_tmp} = (double*)pact_alloc(sizeof(double));")
                emit_line("*{box_tmp} = {val_str2};")
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){box_tmp});")
            } else {
                emit_line("pact_list_set({obj_str}, {idx_str}, (void*){val_str2});")
            }
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "join" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let delim_str = expr_result_str
            expr_result_str = "pact_str_join({obj_str}, {delim_str})"
            expr_result_type = CT_STRING
            return
        }
    }

    // Iterator adapter and consumer methods — work on both CT_LIST and CT_ITERATOR
    if (obj_type == CT_LIST || obj_type == CT_ITERATOR) && (method == "count" || method == "collect" || method == "for_each" || method == "any" || method == "all" || method == "find" || method == "fold" || method == "map" || method == "filter" || method == "take" || method == "skip" || method == "chain" || method == "flat_map" || method == "enumerate" || method == "zip") {

        // Set element type hint for closure param type inference
        if obj_type == CT_LIST {
            let hint_elem = get_list_elem_type(obj_str)
            if hint_elem != -1 {
                cg_closure_param_type_hint = hint_elem
            }
        } else if obj_type == CT_ITERATOR {
            let hint_elem = get_var_iterator_inner(obj_str)
            if hint_elem > 0 {
                cg_closure_param_type_hint = hint_elem
            }
        }

        // --- Adapter methods: return CT_ITERATOR ---

        if method == "map" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_map_iter(elem_type)
            let adapter_var = fresh_temp("__map_")
            emit_line("pact_MapIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str} };")
            set_var_iterator(adapter_var, elem_type, "pact_MapIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_MapIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "filter" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_filter_iter(elem_type)
            let adapter_var = fresh_temp("__filter_")
            emit_line("pact_FilterIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str} };")
            set_var_iterator(adapter_var, elem_type, "pact_FilterIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_FilterIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "take" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let n_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_take_iter(elem_type)
            let adapter_var = fresh_temp("__take_")
            emit_line("pact_TakeIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .limit = {n_str}, .count = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_TakeIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_TakeIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "skip" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let n_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_skip_iter(elem_type)
            let adapter_var = fresh_temp("__skip_")
            emit_line("pact_SkipIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .skip_n = {n_str}, .skipped = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_SkipIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_SkipIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "chain" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            let other_type = expr_result_type
            iter_from_source(obj_str, obj_type)
            let src_a_var = ifs_iter_var
            let next_a = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let tag = c_type_tag(elem_type)
            iter_from_source(other_str, other_type)
            let src_b_var = ifs_iter_var
            let next_b = ifs_next_fn
            ensure_chain_iter(elem_type)
            let adapter_var = fresh_temp("__chain_")
            emit_line("pact_ChainIterator_{tag} {adapter_var} = \{ .source_a = &{src_a_var}, .next_a = ({opt_t} (*)(void*)){next_a}, .source_b = &{src_b_var}, .next_b = ({opt_t} (*)(void*)){next_b}, .phase = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_ChainIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_ChainIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "flat_map" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let tag = c_type_tag(elem_type)
            ensure_flat_map_iter(elem_type)
            let adapter_var = fresh_temp("__flatmap_")
            emit_line("pact_FlatMapIterator_{tag} {adapter_var} = \{ .source = &{src_var}, .source_next = ({ifs_opt_type} (*)(void*)){src_next}, .fn = {fn_str}, .buffer = NULL, .buf_idx = 0 };")
            set_var_iterator(adapter_var, elem_type, "pact_FlatMapIterator_{tag}_next")
            expr_result_str = adapter_var
            expr_result_type = CT_ITERATOR
            expr_iter_next_fn = "pact_FlatMapIterator_{tag}_next"
            expr_list_elem_type = elem_type
            return
        }
        if method == "enumerate" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let tag = c_type_tag(elem_type)
            let result_list = fresh_temp("__enum_")
            let next_var = fresh_temp("__enum_next_")
            let i_var = fresh_temp("__enum_i_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("int64_t {i_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            let pair_var = fresh_temp("__enum_pair_")
            emit_line("pact_list* {pair_var} = pact_list_new();")
            emit_line("pact_list_push({pair_var}, (void*)(intptr_t){i_var});")
            if elem_type == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_var}.value);")
            }
            emit_line("pact_list_push({result_list}, (void*){pair_var});")
            emit_line("{i_var}++;")
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, CT_LIST)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_LIST
            return
        }
        if method == "zip" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            let other_type = expr_result_type
            iter_from_source(obj_str, obj_type)
            let src_a_var = ifs_iter_var
            let next_a = ifs_next_fn
            let elem_type_a = ifs_elem_type
            let opt_a = ifs_opt_type
            iter_from_source(other_str, other_type)
            let src_b_var = ifs_iter_var
            let next_b = ifs_next_fn
            let elem_type_b = ifs_elem_type
            let opt_b = ifs_opt_type
            let result_list = fresh_temp("__zip_")
            let next_a_var = fresh_temp("__zip_na_")
            let next_b_var = fresh_temp("__zip_nb_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_a} {next_a_var} = (({opt_a} (*)(void*)){next_a})(&{src_a_var});")
            emit_line("if ({next_a_var}.tag == 0) break;")
            emit_line("{opt_b} {next_b_var} = (({opt_b} (*)(void*)){next_b})(&{src_b_var});")
            emit_line("if ({next_b_var}.tag == 0) break;")
            let pair_var = fresh_temp("__zip_pair_")
            emit_line("pact_list* {pair_var} = pact_list_new();")
            if elem_type_a == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_a_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_a_var}.value);")
            }
            if elem_type_b == CT_INT {
                emit_line("pact_list_push({pair_var}, (void*)(intptr_t){next_b_var}.value);")
            } else {
                emit_line("pact_list_push({pair_var}, (void*){next_b_var}.value);")
            }
            emit_line("pact_list_push({result_list}, (void*){pair_var});")
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, CT_LIST)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_LIST
            return
        }

        // --- Consumer methods: drive an iterator to completion ---

        if method == "collect" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            let result_list = fresh_temp("__collect_")
            let next_var = fresh_temp("__collect_next_")
            emit_line("pact_list* {result_list} = pact_list_new();")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            if elem_type == CT_INT {
                emit_line("pact_list_push({result_list}, (void*)(intptr_t){next_var}.value);")
            } else {
                emit_line("pact_list_push({result_list}, (void*){next_var}.value);")
            }
            cg_indent = cg_indent - 1
            emit_line("}")
            set_list_elem_type(result_list, elem_type)
            expr_result_str = result_list
            expr_result_type = CT_LIST
            expr_list_elem_type = elem_type
            return
        }
        if method == "count" {
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type
            let count_var = fresh_temp("__count_")
            let next_var = fresh_temp("__count_next_")
            emit_line("int64_t {count_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("{count_var}++;")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = count_var
            expr_result_type = CT_INT
            return
        }
        if method == "for_each" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type

            let next_var = fresh_temp("__fe_next_")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("(({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value);")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "any" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type

            let result_var = fresh_temp("__any_")
            let next_var = fresh_temp("__any_next_")
            emit_line("int {result_var} = 0;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if ((({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = 1; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = result_var
            expr_result_type = CT_BOOL
            return
        }
        if method == "all" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type

            let result_var = fresh_temp("__all_")
            let next_var = fresh_temp("__all_next_")
            emit_line("int {result_var} = 1;")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if (!(({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = 0; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = result_var
            expr_result_type = CT_BOOL
            return
        }
        if method == "find" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let elem_type = ifs_elem_type
            let opt_t = ifs_opt_type
            ensure_option_type(elem_type)
            let result_var = fresh_temp("__find_")
            let next_var = fresh_temp("__find_next_")
            emit_line("{opt_t} {result_var} = ({opt_t})\{.tag = 0};")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("if ((({fn_sig}){fn_str}->fn_ptr)({fn_str}, {next_var}.value)) \{ {result_var} = ({opt_t})\{.tag = 1, .value = {next_var}.value}; break; }")
            cg_indent = cg_indent - 1
            emit_line("}")
            set_var_option(result_var, elem_type)
            expr_result_str = result_var
            expr_result_type = CT_OPTION
            expr_option_inner = elem_type
            expr_option_inner_struct = ""
            return
        }
        if method == "fold" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let init_str = expr_result_str
            let init_type = expr_result_type
            emit_expr(sublist_get(args_sl, 1))
            let fn_str = expr_result_str
            let fn_sig = expr_closure_sig
            iter_from_source(obj_str, obj_type)
            let src_var = ifs_iter_var
            let src_next = ifs_next_fn
            let opt_t = ifs_opt_type
            let acc_var = fresh_temp("__fold_acc_")
            let next_var = fresh_temp("__fold_next_")
            emit_line("{c_type_str(init_type)} {acc_var} = {init_str};")
            emit_line("while (1) \{")
            cg_indent = cg_indent + 1
            emit_line("{opt_t} {next_var} = (({opt_t} (*)(void*)){src_next})(&{src_var});")
            emit_line("if ({next_var}.tag == 0) break;")
            emit_line("{acc_var} = (({fn_sig}){fn_str}->fn_ptr)({fn_str}, {acc_var}, {next_var}.value);")
            cg_indent = cg_indent - 1
            emit_line("}")
            expr_result_str = acc_var
            expr_result_type = init_type
            return
        }
        cg_closure_param_type_hint = -1
    }

    // Channel methods
    if obj_type == CT_CHANNEL {
        if method == "send" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let val_str = expr_result_str
            let val_type = expr_result_type
            if val_type == CT_INT {
                emit_line("pact_channel_send({obj_str}, (void*)(intptr_t){val_str});")
            } else {
                emit_line("pact_channel_send({obj_str}, (void*){val_str});")
            }
            expr_result_str = "0"
            expr_result_type = CT_INT
            return
        }
        if method == "recv" {
            let recv_tmp = fresh_temp("__recv_")
            let ch_inner = get_var_channel_inner(obj_str)
            emit_line("void* {recv_tmp} = pact_channel_recv({obj_str});")
            if ch_inner == CT_STRING {
                expr_result_str = "(const char*){recv_tmp}"
                expr_result_type = CT_STRING
            } else {
                expr_result_str = "(int64_t)(intptr_t){recv_tmp}"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "close" {
            emit_line("pact_channel_close({obj_str});")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
    }

    // Map methods
    if obj_type == CT_MAP {
        if method == "set" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let val_str2 = expr_result_str
            let val_type2 = expr_result_type
            if val_type2 == CT_INT {
                emit_line("pact_map_set({obj_str}, {key_str}, (void*)(intptr_t){val_str2});")
            } else if val_type2 == CT_FLOAT {
                let box_tmp = fresh_temp("_fbox")
                emit_line("double* {box_tmp} = (double*)pact_alloc(sizeof(double));")
                emit_line("*{box_tmp} = {val_str2};")
                emit_line("pact_map_set({obj_str}, {key_str}, (void*){box_tmp});")
            } else {
                emit_line("pact_map_set({obj_str}, {key_str}, (void*){val_str2});")
            }
            set_map_types(obj_str, CT_STRING, val_type2)
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "get" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            let vtype = get_map_value_type(obj_str)
            if vtype == CT_STRING {
                expr_result_str = "(const char*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_STRING
            } else if vtype == CT_LIST {
                expr_result_str = "(pact_list*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_LIST
            } else if vtype == CT_MAP {
                expr_result_str = "(pact_map*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_MAP
            } else if vtype == CT_FLOAT {
                expr_result_str = "*(double*)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_FLOAT
            } else {
                expr_result_str = "(int64_t)(intptr_t)pact_map_get({obj_str}, {key_str})"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "has" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            expr_result_str = "pact_map_has({obj_str}, {key_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "remove" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let key_str = expr_result_str
            expr_result_str = "pact_map_remove({obj_str}, {key_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "len" {
            expr_result_str = "pact_map_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "keys" {
            expr_result_str = "pact_map_keys({obj_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = CT_STRING
            return
        }
        if method == "values" {
            let vtype = get_map_value_type(obj_str)
            expr_result_str = "pact_map_values({obj_str})"
            expr_result_type = CT_LIST
            expr_list_elem_type = vtype
            return
        }
    }

    // Bytes methods
    if obj_type == CT_BYTES {
        if method == "push" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let val_str = expr_result_str
            emit_line("pact_bytes_push({obj_str}, {val_str});")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "get" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            ensure_option_type(CT_INT)
            let opt_type = option_c_type(CT_INT)
            let raw = fresh_temp("_bget_")
            let res = fresh_temp("_bget_opt_")
            emit_line("int64_t {raw} = pact_bytes_get({obj_str}, {idx_str});")
            emit_line("{opt_type} {res} = {raw} >= 0 ? ({opt_type})\{.tag = 1, .value = {raw}} : ({opt_type})\{.tag = 0};")
            set_var_option(res, CT_INT)
            expr_result_str = res
            expr_result_type = CT_OPTION
            expr_option_inner = CT_INT
            expr_option_inner_struct = ""
            return
        }
        if method == "set" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let idx_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let val_str = expr_result_str
            emit_line("pact_bytes_set({obj_str}, {idx_str}, {val_str});")
            expr_result_str = "0"
            expr_result_type = CT_VOID
            return
        }
        if method == "len" {
            expr_result_str = "pact_bytes_len({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "is_empty" {
            expr_result_str = "pact_bytes_is_empty({obj_str})"
            expr_result_type = CT_BOOL
            return
        }
        if method == "slice" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let start_str = expr_result_str
            emit_expr(sublist_get(args_sl, 1))
            let end_str = expr_result_str
            expr_result_str = "pact_bytes_slice({obj_str}, {start_str}, {end_str})"
            expr_result_type = CT_BYTES
            return
        }
        if method == "concat" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_bytes_concat({obj_str}, {other_str})"
            expr_result_type = CT_BYTES
            return
        }
        if method == "to_str" {
            ensure_result_type(CT_STRING, CT_STRING)
            let res_type = result_c_type(CT_STRING, CT_STRING)
            let out = fresh_temp("_bstr_")
            let ok = fresh_temp("_bstr_ok_")
            let res = fresh_temp("_bstr_res_")
            emit_line("const char* {out};")
            emit_line("int {ok} = pact_bytes_to_str_checked({obj_str}, &{out});")
            emit_line("{res_type} {res} = {ok} ? ({res_type})\{.tag = 0, .ok = {out}} : ({res_type})\{.tag = 1, .err = {out}};")
            expr_result_str = res
            expr_result_type = CT_RESULT
            expr_result_ok_type = CT_STRING
            expr_result_err_type = CT_STRING
            return
        }
        if method == "to_hex" {
            expr_result_str = "pact_bytes_to_hex({obj_str})"
            expr_result_type = CT_STRING
            return
        }
    }

    // Instant methods
    if obj_type == CT_INSTANT {
        if method == "elapsed" {
            expr_result_str = "pact_instant_elapsed({obj_str})"
            expr_result_type = CT_DURATION
            return
        }
        if method == "since" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_instant_since({obj_str}, {other_str})"
            expr_result_type = CT_DURATION
            return
        }
        if method == "add" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let dur_str = expr_result_str
            expr_result_str = "pact_instant_add({obj_str}, {dur_str})"
            expr_result_type = CT_INSTANT
            return
        }
        if method == "to_rfc3339" {
            expr_result_str = "pact_instant_to_rfc3339({obj_str})"
            expr_result_type = CT_STRING
            return
        }
        if method == "to_unix_ms" {
            expr_result_str = "pact_instant_to_unix_ms({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "to_unix_secs" {
            expr_result_str = "pact_instant_to_unix_secs({obj_str})"
            expr_result_type = CT_INT
            return
        }
    }

    // Duration methods
    if obj_type == CT_DURATION {
        if method == "to_ms" {
            expr_result_str = "pact_duration_to_ms({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "to_seconds" {
            expr_result_str = "pact_duration_to_seconds({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "to_nanos" {
            expr_result_str = "pact_duration_to_nanos({obj_str})"
            expr_result_type = CT_INT
            return
        }
        if method == "add" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_duration_add({obj_str}, {other_str})"
            expr_result_type = CT_DURATION
            return
        }
        if method == "sub" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let other_str = expr_result_str
            expr_result_str = "pact_duration_sub({obj_str}, {other_str})"
            expr_result_type = CT_DURATION
            return
        }
        if method == "scale" {
            let args_sl = np_args.get(node).unwrap()
            emit_expr(sublist_get(args_sl, 0))
            let n_str = expr_result_str
            expr_result_str = "pact_duration_scale({obj_str}, {n_str})"
            expr_result_type = CT_DURATION
            return
        }
        if method == "is_zero" {
            expr_result_str = "pact_duration_is_zero({obj_str})"
            expr_result_type = CT_BOOL
            return
        }
    }

    // Option methods: unwrap, is_some, is_none
    if obj_type == CT_OPTION {
        if method == "unwrap" {
            let inner = get_var_option_inner(obj_str)
            let inner_s = get_var_option_inner_struct(obj_str)
            let tmp = fresh_temp("_ounw_")
            if inner_s != "" {
                let opt_c = struct_option_c_type(inner_s)
                emit_line("{opt_c} {tmp} = {obj_str};")
                emit_line("if ({tmp}.tag == 0) \{ fprintf(stderr, \"panic: unwrap called on None\\n\"); exit(1); }")
                let val_tmp = fresh_temp("_ounv_")
                emit_line("{c_type_c_name(inner_s)} {val_tmp} = {tmp}.value;")
                set_var_struct(val_tmp, inner_s)
                expr_result_str = val_tmp
                expr_result_type = CT_VOID
            } else if inner == CT_STRING {
                let opt_c = option_c_type(CT_STRING)
                emit_line("{opt_c} {tmp} = {obj_str};")
                emit_line("if ({tmp}.tag == 0) \{ fprintf(stderr, \"panic: unwrap called on None\\n\"); exit(1); }")
                expr_result_str = "{tmp}.value"
                expr_result_type = CT_STRING
            } else if inner == CT_LIST {
                let opt_c = option_c_type(CT_LIST)
                emit_line("{opt_c} {tmp} = {obj_str};")
                emit_line("if ({tmp}.tag == 0) \{ fprintf(stderr, \"panic: unwrap called on None\\n\"); exit(1); }")
                let val_tmp = fresh_temp("_ounv_")
                emit_line("pact_list* {val_tmp} = {tmp}.value;")
                set_var(val_tmp, CT_LIST, 0)
                let nested = get_var_option_inner2(obj_str)
                if nested != -1 {
                    set_list_elem_type(val_tmp, nested)
                    expr_list_elem_type = nested
                } else {
                    set_list_elem_type(val_tmp, CT_INT)
                    expr_list_elem_type = CT_INT
                }
                let nested_s = get_var_option_inner2_struct(obj_str)
                if nested_s != "" {
                    set_list_elem_struct(val_tmp, nested_s)
                }
                expr_result_str = val_tmp
                expr_result_type = CT_LIST
            } else {
                if inner == CT_FLOAT {
                    let opt_c = option_c_type(CT_FLOAT)
                    emit_line("{opt_c} {tmp} = {obj_str};")
                    emit_line("if ({tmp}.tag == 0) \{ fprintf(stderr, \"panic: unwrap called on None\\n\"); exit(1); }")
                    expr_result_str = "{tmp}.value"
                    expr_result_type = CT_FLOAT
                } else {
                    let opt_c = option_c_type(CT_INT)
                    emit_line("{opt_c} {tmp} = {obj_str};")
                    emit_line("if ({tmp}.tag == 0) \{ fprintf(stderr, \"panic: unwrap called on None\\n\"); exit(1); }")
                    expr_result_str = "{tmp}.value"
                    expr_result_type = CT_INT
                }
            }
            return
        }
        if method == "is_some" {
            expr_result_str = "({obj_str}.tag == 1)"
            expr_result_type = CT_BOOL
            return
        }
        if method == "is_none" {
            expr_result_str = "({obj_str}.tag == 0)"
            expr_result_type = CT_BOOL
            return
        }
    }

    // Result methods: unwrap, unwrap_err, is_ok, is_err
    if obj_type == CT_RESULT {
        if method == "unwrap" {
            let ok_t = get_var_result_ok(obj_str)
            let ok_s = get_var_result_ok_struct(obj_str)
            let err_t = get_var_result_err(obj_str)
            let err_s = get_var_result_err_struct(obj_str)
            if ok_s != "" {
                let res_c = result_c_type_mixed(ok_t, err_t, ok_s, err_s)
                let tmp = fresh_temp("_runw_")
                emit_line("{res_c} {tmp} = {obj_str};")
                emit_line("if ({tmp}.tag == 1) \{ fprintf(stderr, \"panic: unwrap called on Err\\n\"); exit(1); }")
                let val_tmp = fresh_temp("_runv_")
                emit_line("{c_type_c_name(ok_s)} {val_tmp} = {tmp}.ok;")
                set_var_struct(val_tmp, ok_s)
                expr_result_str = val_tmp
                expr_result_type = CT_VOID
            } else if ok_t == CT_STRING {
                emit_line("if ({obj_str}.tag == 1) \{ fprintf(stderr, \"panic: unwrap called on Err\\n\"); exit(1); }")
                expr_result_str = "{obj_str}.ok"
                expr_result_type = CT_STRING
            } else {
                if ok_t == CT_FLOAT {
                    emit_line("if ({obj_str}.tag == 1) \{ fprintf(stderr, \"panic: unwrap called on Err\\n\"); exit(1); }")
                    expr_result_str = "{obj_str}.ok"
                    expr_result_type = CT_FLOAT
                } else {
                    emit_line("if ({obj_str}.tag == 1) \{ fprintf(stderr, \"panic: unwrap called on Err\\n\"); exit(1); }")
                    expr_result_str = "{obj_str}.ok"
                    expr_result_type = CT_INT
                }
            }
            return
        }
        if method == "unwrap_err" {
            let err_t = get_var_result_err(obj_str)
            let err_s = get_var_result_err_struct(obj_str)
            if err_s != "" {
                emit_line("if ({obj_str}.tag == 0) \{ fprintf(stderr, \"panic: unwrap_err called on Ok\\n\"); exit(1); }")
                let val_tmp = fresh_temp("_ruerr_")
                emit_line("{c_type_c_name(err_s)} {val_tmp} = {obj_str}.err;")
                set_var_struct(val_tmp, err_s)
                expr_result_str = val_tmp
                expr_result_type = CT_VOID
            } else if err_t == CT_STRING {
                emit_line("if ({obj_str}.tag == 0) \{ fprintf(stderr, \"panic: unwrap_err called on Ok\\n\"); exit(1); }")
                expr_result_str = "{obj_str}.err"
                expr_result_type = CT_STRING
            } else {
                emit_line("if ({obj_str}.tag == 0) \{ fprintf(stderr, \"panic: unwrap_err called on Ok\\n\"); exit(1); }")
                expr_result_str = "{obj_str}.err"
                expr_result_type = CT_INT
            }
            return
        }
        if method == "is_ok" {
            expr_result_str = "({obj_str}.tag == 0)"
            expr_result_type = CT_BOOL
            return
        }
        if method == "is_err" {
            expr_result_str = "({obj_str}.tag == 1)"
            expr_result_type = CT_BOOL
            return
        }
    }

    // Derived method dispatch (Serialize/Deserialize)
    let derive_struct = get_var_struct(obj_str)
    if derive_struct != "" && has_derive_method(derive_struct, method) != 0 {
        if method == "to_json" {
            let ds_mangled = "{derive_struct}_to_json"
            expr_result_str = "{c_fn_name(ds_mangled)}({obj_str})"
            expr_result_type = CT_STRING
            return
        }
    }
    let derive_enum = get_var_enum(obj_str)
    if derive_enum != "" && has_derive_method(derive_enum, method) != 0 {
        if method == "to_json" {
            let de_mangled = "{derive_enum}_to_json"
            expr_result_str = "{c_fn_name(de_mangled)}({obj_str})"
            expr_result_type = CT_STRING
            return
        }
    }

    // Trait impl method resolution
    let struct_type = get_var_struct(obj_str)
    if struct_type != "" && lookup_impl_method(struct_type, method) != 0 {
        let mangled = "{struct_type}_{method}"
        let args_sl = np_args.get(node).unwrap()
        let mut args_str = obj_str
        if args_sl != -1 {
            let mut i = 0
            while i < sublist_length(args_sl) {
                args_str = args_str.concat(", ")
                emit_expr(sublist_get(args_sl, i))
                args_str = args_str.concat(expr_result_str)
                i = i + 1
            }
        }
        expr_result_str = "{c_fn_name(mangled)}({args_str})"
        expr_result_type = get_impl_method_ret(struct_type, method)
        return
    }

    // Closure field dispatch: struct.closure_field(args)
    if struct_type != "" {
        let cls_field_type = get_struct_field_type(struct_type, method)
        if cls_field_type == CT_CLOSURE {
            let cls_sig = get_struct_field_closure_sig(struct_type, method)
            if cls_sig != "" {
                let cls_ptr = "{obj_str}.{method}"
                let args_sl = np_args.get(node).unwrap()
                let mut args_str = cls_ptr
                if args_sl != -1 {
                    let mut i = 0
                    while i < sublist_length(args_sl) {
                        args_str = args_str.concat(", ")
                        emit_expr(sublist_get(args_sl, i))
                        args_str = args_str.concat(expr_result_str)
                        i = i + 1
                    }
                }
                expr_result_str = "(({cls_sig}){cls_ptr}->fn_ptr)({args_str})"
                let mut ret_end = 0
                while ret_end < cls_sig.len() && cls_sig.char_at(ret_end) != 40 {
                    ret_end = ret_end + 1
                }
                let ret_part = cls_sig.substring(0, ret_end)
                if ret_part == "int64_t" {
                    expr_result_type = CT_INT
                } else if ret_part == "double" {
                    expr_result_type = CT_FLOAT
                } else if ret_part == "const char*" {
                    expr_result_type = CT_STRING
                } else if ret_part == "int" {
                    expr_result_type = CT_BOOL
                } else if ret_part.starts_with("pact_") {
                    let sname = ret_part.substring(5, ret_part.len() - 5)
                    let resolved = resolve_struct_from_c_name(sname)
                    if resolved != "" {
                        let tmp = fresh_temp("_cls_ret_")
                        emit_line("{ret_part} {tmp} = (({cls_sig}){cls_ptr}->fn_ptr)({args_str});")
                        set_var(tmp, CT_VOID, 0)
                        set_var_struct(tmp, resolved)
                        expr_result_str = tmp
                        expr_result_type = CT_VOID
                    } else {
                        expr_result_type = CT_VOID
                    }
                } else {
                    expr_result_type = CT_VOID
                }
                return
            }
        }
    }

    // Generic fallback — emit diagnostic and produce safe placeholder
    let recv_type_name = type_name_from_ct(obj_type)
    diag_error_at("UnresolvedMethod", "E0505", "unresolved method '.{method}' on type {recv_type_name} in '{cg_current_fn_name}'", node, "")
    expr_result_str = "(void)0"
    expr_result_type = CT_VOID
}
