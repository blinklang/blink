import symbol_index
import file_watcher
import incremental
import query
import diagnostics
import std.json
import lexer
import parser
import typecheck

effect Daemon {
    effect Serve
}

// daemon.pact — Persistent compiler service with Unix socket IPC
//
// Single-threaded event loop: accept connection, read JSON request,
// dispatch (check/query/status/stop), respond, check file watcher.
// Reuses compiler pipeline (lex → parse → typecheck) for recheck.

// ── State ───────────────────────────────────────────────────────────

let mut daemon_running: Int = 0
let mut daemon_socket_fd: Int = -1
let mut daemon_pid_path: Str = ""
let mut daemon_sock_path: Str = ""
let mut daemon_project_root: Str = ""
let mut daemon_source_path: Str = ""
let mut daemon_start_time: Int = 0
let mut daemon_check_count: Int = 0
let mut daemon_program: Int = -1

// ── JSON string escaping ────────────────────────────────────────────

fn dj_escape(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 {
            result = result.concat("\\\"")
        } else if c == 92 {
            result = result.concat("\\\\")
        } else if c == 10 {
            result = result.concat("\\n")
        } else if c == 9 {
            result = result.concat("\\t")
        } else if c == 13 {
            result = result.concat("\\r")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

// ── Minimal JSON request parser ─────────────────────────────────────
// Reuses the same flat {"key":"value"} approach from query.pact.

let mut dr_keys: List[Str] = []
let mut dr_vals: List[Str] = []

fn dr_skip_ws(s: Str, p: Int) -> Int {
    let mut i = p
    while i < s.len() {
        let c = s.char_at(i)
        if c == 32 || c == 9 || c == 10 || c == 13 {
            i = i + 1
        } else {
            return i
        }
    }
    i
}

fn dr_parse_string(s: Str, p: Int) -> Option[Str] {
    if p >= s.len() || s.char_at(p) != 34 {
        return None
    }
    let mut i = p + 1
    let mut result = ""
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 {
            return Some(result)
        }
        if c == 92 && i + 1 < s.len() {
            let next = s.char_at(i + 1)
            if next == 34 {
                result = result.concat("\"")
                i = i + 2
            } else if next == 92 {
                result = result.concat("\\")
                i = i + 2
            } else if next == 110 {
                result = result.concat("\n")
                i = i + 2
            } else {
                result = result.concat(s.substring(i, 1))
                i = i + 1
            }
        } else {
            result = result.concat(s.substring(i, 1))
            i = i + 1
        }
    }
    Some(result)
}

fn dr_end_of_string(s: Str, p: Int) -> Int {
    if p >= s.len() || s.char_at(p) != 34 {
        return p
    }
    let mut i = p + 1
    while i < s.len() {
        let c = s.char_at(i)
        if c == 34 {
            return i + 1
        }
        if c == 92 {
            i = i + 2
        } else {
            i = i + 1
        }
    }
    i
}

fn dr_parse_request(s: Str) -> Int {
    dr_keys = []
    dr_vals = []
    let mut p = dr_skip_ws(s, 0)
    if p >= s.len() || s.char_at(p) != 123 {
        return 0
    }
    p = p + 1
    p = dr_skip_ws(s, p)
    while p < s.len() && s.char_at(p) != 125 {
        if dr_keys.len() > 0 {
            if p < s.len() && s.char_at(p) == 44 {
                p = p + 1
                p = dr_skip_ws(s, p)
            }
        }
        let key = dr_parse_string(s, p) ?? ""
        p = dr_end_of_string(s, p)
        p = dr_skip_ws(s, p)
        if p < s.len() && s.char_at(p) == 58 {
            p = p + 1
        }
        p = dr_skip_ws(s, p)
        let val = dr_parse_string(s, p) ?? ""
        p = dr_end_of_string(s, p)
        p = dr_skip_ws(s, p)
        dr_keys.push(key)
        dr_vals.push(val)
    }
    1
}

fn dr_get(key: Str) -> Str {
    let mut i = 0
    while i < dr_keys.len() {
        if dr_keys.get(i).unwrap() == key {
            return dr_vals.get(i).unwrap()
        }
        i = i + 1
    }
    ""
}

// ── Extract request type ────────────────────────────────────────────

fn daemon_extract_type(request: Str) -> Option[Str] {
    if dr_parse_request(request) == 0 {
        return None
    }
    Some(dr_get("type"))
}

// ── Diagnostics to JSON ─────────────────────────────────────────────
// Collects current diagnostics into a JSON array string instead of printing.

fn daemon_diags_to_json() -> Str {
    json_clear()
    let arr = json_new_array()
    let mut i = 0
    while i < diag_severity.len() {
        let obj = json_new_object()
        json_set(obj, "severity", json_new_str(diag_severity.get(i).unwrap()))
        json_set(obj, "name", json_new_str(diag_name.get(i).unwrap()))
        json_set(obj, "code", json_new_str(diag_code.get(i).unwrap()))
        json_set(obj, "message", json_new_str(diag_message.get(i).unwrap()))
        json_set(obj, "file", json_new_str(diag_file.get(i).unwrap()))
        json_set(obj, "line", json_new_int(diag_line.get(i).unwrap()))
        json_set(obj, "col", json_new_int(diag_col.get(i).unwrap()))
        let help = diag_help.get(i).unwrap()
        if help != "" {
            json_set(obj, "help", json_new_str(help))
        }
        json_push(arr, obj)
        i = i + 1
    }
    json_encode(arr)
}

// ── Handle: check ───────────────────────────────────────────────────
// Poll file watcher, detect changes, selective recheck, return diagnostics.

fn daemon_handle_check() -> Str ! Daemon.Serve, Lex.Tokenize, Parse, TypeCheck, Diag.Report {
    daemon_check_count = daemon_check_count + 1

    let changed = fw_poll()
    if changed == 0 {
        return "\{\"ok\":true,\"changed\":0,\"diagnostics\":[]}"
    }

    // Detect which files changed and compute affected symbol set
    inc_detect_changes()
    inc_compute_affected()

    // Build incremental filter from affected symbols
    let mut affected_names: List[Str] = []
    let mut i = 0
    while i < inc_affected_count {
        let sym_idx = inc_affected.get(i).unwrap()
        affected_names.push(si_sym_name.get(sym_idx).unwrap())
        i = i + 1
    }

    // Re-read and re-parse the source
    diag_reset()
    let source = read_file(daemon_source_path)
    lex(source)
    pos = 0
    let program = parse_program()
    daemon_program = program

    // Selective typecheck using incremental filter
    tc_set_incremental_filter(affected_names)
    check_types(program)
    tc_clear_incremental_filter()

    // Rebuild symbol index for the new parse
    si_reset()
    si_build(program, daemon_source_path, "main")

    // Re-snapshot for next cycle
    inc_snapshot()
    fw_clear_dirty()

    let diags_json = daemon_diags_to_json()
    let err_count = diag_count
    "\{\"ok\":true,\"changed\":{changed},\"errors\":{err_count},\"diagnostics\":{diags_json}}"
}

// ── Handle: query ───────────────────────────────────────────────────

fn daemon_handle_query(request: Str) -> Str {
    query_dispatch(request)
}

// ── Handle: status ──────────────────────────────────────────────────

fn daemon_handle_status() -> Str {
    let now = time_ms()
    let uptime = now - daemon_start_time
    let sym_count = si_sym_count
    let file_count = si_file_count
    let checks = daemon_check_count
    "\{\"ok\":true,\"uptime_ms\":{uptime},\"symbols\":{sym_count},\"files\":{file_count},\"checks\":{checks}}"
}

// ── Handle: stop ────────────────────────────────────────────────────

fn daemon_handle_stop() -> Str {
    daemon_running = 0
    "\{\"ok\":true,\"message\":\"daemon stopping\"}"
}

// ── Event loop ──────────────────────────────────────────────────────

fn daemon_loop() ! Daemon.Serve, Lex.Tokenize, Parse, TypeCheck, Diag.Report {
    while daemon_running == 1 {
        let client_fd = unix_socket_accept_timeout(daemon_socket_fd, 500)
        if client_fd < 0 {
            // Timeout — poll files for changes between requests
            fw_poll()
            continue
        }

        let request = socket_read_line(client_fd)
        let req_type = daemon_extract_type(request) ?? ""

        let mut response = ""
        if req_type == "check" {
            response = daemon_handle_check()
        } else if req_type == "query" {
            response = daemon_handle_query(request)
        } else if req_type == "status" {
            response = daemon_handle_status()
        } else if req_type == "stop" {
            response = daemon_handle_stop()
        } else {
            response = "\{\"ok\":false,\"error\":\"unknown request type: {req_type}\"}"
        }

        socket_write(client_fd, response.concat("\n"))
        unix_socket_close(client_fd)
    }
}

// ── Shutdown ────────────────────────────────────────────────────────

pub fn daemon_stop() ! Daemon.Serve {
    if daemon_socket_fd >= 0 {
        unix_socket_close(daemon_socket_fd)
        daemon_socket_fd = -1
    }
    if daemon_pid_path != "" {
        shell_exec("rm -f {daemon_pid_path}")
    }
    if daemon_sock_path != "" {
        shell_exec("rm -f {daemon_sock_path}")
    }
    si_reset()
    inc_reset()
    fw_reset()
    daemon_running = 0
}

// ── Startup ─────────────────────────────────────────────────────────

pub fn daemon_start(root: Str, source: Str) ! Daemon.Serve, Lex.Tokenize, Parse, TypeCheck, Diag.Report {
    daemon_project_root = root
    daemon_source_path = source
    daemon_start_time = time_ms()

    // Ensure .pact/ directory exists
    let pact_dir = path_join(root, ".pact")
    shell_exec("mkdir -p {pact_dir}")

    // Write PID file
    daemon_pid_path = path_join(pact_dir, "daemon.pid")
    let pid = getpid()
    write_file(daemon_pid_path, "{pid}")

    // Create Unix socket
    daemon_sock_path = path_join(pact_dir, "daemon.sock")
    daemon_socket_fd = unix_socket_listen(daemon_sock_path)
    if daemon_socket_fd < 0 {
        io.eprintln("daemon: failed to create socket at {daemon_sock_path}")
        return
    }

    // Initial full compile: lex → parse → typecheck
    let src = read_file(source)
    lex(src)
    pos = 0
    let program = parse_program()
    daemon_program = program

    check_types(program)

    // Build symbol index
    si_build(program, source, "main")

    // Initialize file watcher from symbol index
    fw_init()

    // Snapshot for incremental detection
    inc_snapshot()

    io.eprintln("daemon: listening on {daemon_sock_path} (pid {pid})")
    daemon_running = 1
    daemon_loop()

    // Cleanup on exit
    daemon_stop()
}
