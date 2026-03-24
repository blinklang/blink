import symbol_index
import file_watcher
import incremental
import query
import diagnostics
import std.json
import std.path
import std.flat_json
import lexer
import parser
import typecheck
import comment_attach

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

// ── Extract request type ────────────────────────────────────────────

fn daemon_extract_type(request: Str) -> Option[Str] {
    if fj_parse(request) == 0 {
        return None
    }
    Some(fj_get("type"))
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

@allow(UnrestoredMutation, IncompleteStateRestore)
fn daemon_handle_check() -> Str ! Daemon.Serve, Lex.Tokenize, Parse, TypeCheck, Diag.Report {
    daemon_check_count = daemon_check_count + 1

    let changed = fw_poll()
    if changed == 0 {
        return "\{\"ok\":true,\"changed\":0,\"diagnostics\":[]}"
    }

    // Detect which files changed and compute affected symbol set
    inc_detect_changes()
    inc_compute_affected()

    let affected_names = inc_affected_names()

    // Re-read and re-parse the source
    diag_reset()
    parser_reset()
    let source = read_file(daemon_source_path)
    lex(source)
    let first_node_check = np_kind.len()
    let program = parse_program()
    attach_comments_pass(program, first_node_check)
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

fn daemon_stop() ! Daemon.Serve {
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

    // Ensure .blink/ directory exists
    let blink_dir = path_join(root, ".blink")
    shell_exec("mkdir -p {blink_dir}")

    // Write PID file
    daemon_pid_path = path_join(blink_dir, "daemon.pid")
    let pid = getpid()
    write_file(daemon_pid_path, "{pid}")

    // Create Unix socket
    daemon_sock_path = path_join(blink_dir, "daemon.sock")
    daemon_socket_fd = unix_socket_listen(daemon_sock_path)
    if daemon_socket_fd < 0 {
        io.eprintln("daemon: failed to create socket at {daemon_sock_path}")
        return
    }

    // Initial full compile: lex → parse → typecheck
    parser_reset()
    let src = read_file(source)
    lex(src)
    let first_node_daemon = np_kind.len()
    let program = parse_program()
    attach_comments_pass(program, first_node_daemon)
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
