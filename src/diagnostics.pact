import parser

effect Diag {
    effect Report
}

// diagnostics.pact — Structured diagnostic collector and emitter
//
// Collects errors/warnings into parallel arrays, then flushes as
// JSON (one object per line) or human-readable format.

// ── Diagnostic storage (parallel arrays) ─────────────────────────────

pub let mut diag_severity: List[Str] = []
pub let mut diag_name: List[Str] = []
pub let mut diag_code: List[Str] = []
pub let mut diag_message: List[Str] = []
pub let mut diag_file: List[Str] = []
pub let mut diag_line: List[Int] = []
pub let mut diag_col: List[Int] = []
pub let mut diag_help: List[Str] = []
pub let mut diag_end_line: List[Int] = []
pub let mut diag_end_col: List[Int] = []

// ── Configuration ────────────────────────────────────────────────────

pub let mut diag_format: Int = 0       // 0=human, 1=json
pub let mut diag_source_file: Str = ""
pub let mut diag_count: Int = 0        // error count only
pub let mut diag_module_files: Map[Str, Str] = Map()

// ── Emit helpers ─────────────────────────────────────────────────────

pub fn diag_emit(severity: Str, name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_severity.push(severity)
    diag_name.push(name)
    diag_code.push(code)
    diag_message.push(message)
    diag_file.push(diag_source_file)
    diag_line.push(line)
    diag_col.push(col)
    diag_help.push(help)
    diag_end_line.push(0)
    diag_end_col.push(0)
    if severity == "error" {
        diag_count = diag_count + 1
    }
}

pub fn diag_error(name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_emit("error", name, code, message, line, col, help)
}

pub fn diag_error_no_loc(name: Str, code: Str, message: Str, help: Str) ! Diag.Report {
    diag_emit("error", name, code, message, 0, 0, help)
}

pub fn diag_file_for_node(node_id: Int) -> Str {
    let mod_name = np_module.get(node_id).unwrap()
    if mod_name != "" {
        let f = diag_module_files.get(mod_name)
        if f != "" {
            return f
        }
    }
    diag_source_file
}

pub fn diag_error_at(name: Str, code: Str, message: Str, node_id: Int, help: Str) ! Diag.Report {
    let line = np_line.get(node_id).unwrap()
    let col = np_col.get(node_id).unwrap()
    let saved_file = diag_source_file
    diag_source_file = diag_file_for_node(node_id)
    diag_emit("error", name, code, message, line, col, help)
    diag_source_file = saved_file
}

pub fn diag_warn(name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_emit("warning", name, code, message, line, col, help)
}

pub fn diag_warn_no_loc(name: Str, code: Str, message: Str, help: Str) ! Diag.Report {
    diag_emit("warning", name, code, message, 0, 0, help)
}

pub fn diag_warn_at(name: Str, code: Str, message: Str, node_id: Int, help: Str) ! Diag.Report {
    let line = np_line.get(node_id).unwrap()
    let col = np_col.get(node_id).unwrap()
    let saved_file = diag_source_file
    diag_source_file = diag_file_for_node(node_id)
    diag_emit("warning", name, code, message, line, col, help)
    diag_source_file = saved_file
}

pub fn diag_emit_range(severity: Str, name: Str, code: Str, message: Str, line: Int, col: Int, end_line: Int, end_col: Int, help: Str) ! Diag.Report {
    diag_severity.push(severity)
    diag_name.push(name)
    diag_code.push(code)
    diag_message.push(message)
    diag_file.push(diag_source_file)
    diag_line.push(line)
    diag_col.push(col)
    diag_help.push(help)
    diag_end_line.push(end_line)
    diag_end_col.push(end_col)
    if severity == "error" {
        diag_count = diag_count + 1
    }
}

// ── JSON string escaping ─────────────────────────────────────────────

pub fn json_escape(s: Str) -> Str {
    let mut result = ""
    let mut i = 0
    while i < s.len() {
        let ch = s.char_at(i)
        if ch == 92 {
            result = result.concat("\\\\")
        } else if ch == 34 {
            result = result.concat("\\\"")
        } else if ch == 10 {
            result = result.concat("\\n")
        } else if ch == 13 {
            result = result.concat("\\r")
        } else if ch == 9 {
            result = result.concat("\\t")
        } else {
            result = result.concat(s.substring(i, 1))
        }
        i = i + 1
    }
    result
}

// ── Flush: emit all diagnostics ──────────────────────────────────────

pub fn diag_flush() ! Diag.Report {
    let mut i = 0
    while i < diag_severity.len() {
        if diag_format == 1 {
            diag_print_json(i)
        } else {
            diag_print_human(i)
        }
        i = i + 1
    }
    if diag_format == 1 {
        // no summary in json mode
    } else {
        if diag_count > 0 {
            io.println("{diag_count} error(s) found")
        }
    }
}

pub fn diag_print_json(idx: Int) ! Diag.Report {
    let sev = json_escape(diag_severity.get(idx).unwrap())
    let name = json_escape(diag_name.get(idx).unwrap())
    let code = json_escape(diag_code.get(idx).unwrap())
    let msg = json_escape(diag_message.get(idx).unwrap())
    let file = json_escape(diag_file.get(idx).unwrap())
    let line = diag_line.get(idx).unwrap()
    let col = diag_col.get(idx).unwrap()
    let help = diag_help.get(idx).unwrap()
    let el = diag_end_line.get(idx).unwrap()
    let ec = diag_end_col.get(idx).unwrap()
    let mut span = "\"span\":\{\"file\":\"{file}\",\"line\":{line},\"col\":{col}"
    if el > 0 {
        span = span.concat(",\"end_line\":{el},\"end_col\":{ec}")
    }
    span = span.concat("}")
    let mut json = "\{\"severity\":\"{sev}\",\"name\":\"{name}\",\"code\":\"{code}\",\"message\":\"{msg}\",{span}"
    if help != "" {
        json = json.concat(",\"help\":\"").concat(json_escape(help)).concat("\"")
    }
    json = json.concat("}")
    io.println(json)
}

pub fn diag_print_human(idx: Int) ! Diag.Report {
    let sev = diag_severity.get(idx).unwrap()
    let name = diag_name.get(idx).unwrap()
    let msg = diag_message.get(idx).unwrap()
    let file = diag_file.get(idx).unwrap()
    let line = diag_line.get(idx).unwrap()
    let col = diag_col.get(idx).unwrap()
    let help = diag_help.get(idx).unwrap()
    io.println("{sev}[{name}]: {msg}")
    if line > 0 {
        io.println("  --> {file}:{line}:{col}")
    }
    if help != "" {
        io.println("  help: {help}")
    }
}

// ── Reset ────────────────────────────────────────────────────────────

pub fn diag_reset() {
    diag_severity = []
    diag_name = []
    diag_code = []
    diag_message = []
    diag_file = []
    diag_line = []
    diag_col = []
    diag_help = []
    diag_end_line = []
    diag_end_col = []
    diag_count = 0
    diag_module_files = Map()
}
