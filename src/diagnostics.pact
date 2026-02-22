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

// ── Configuration ────────────────────────────────────────────────────

pub let mut diag_format: Int = 0       // 0=human, 1=json
pub let mut diag_source_file: Str = ""
pub let mut diag_count: Int = 0        // error count only

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

pub fn diag_error_at(name: Str, code: Str, message: Str, node_id: Int, help: Str) ! Diag.Report {
    let line = np_line.get(node_id)
    let col = np_col.get(node_id)
    diag_emit("error", name, code, message, line, col, help)
}

pub fn diag_warn(name: Str, code: Str, message: Str, line: Int, col: Int, help: Str) ! Diag.Report {
    diag_emit("warning", name, code, message, line, col, help)
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
    let sev = json_escape(diag_severity.get(idx))
    let name = json_escape(diag_name.get(idx))
    let code = json_escape(diag_code.get(idx))
    let msg = json_escape(diag_message.get(idx))
    let file = json_escape(diag_file.get(idx))
    let line = diag_line.get(idx)
    let col = diag_col.get(idx)
    let help = diag_help.get(idx)
    let mut json = "\{\"severity\":\"{sev}\",\"name\":\"{name}\",\"code\":\"{code}\",\"message\":\"{msg}\",\"span\":\{\"file\":\"{file}\",\"line\":{line},\"col\":{col}}"
    if help != "" {
        json = json.concat(",\"help\":\"").concat(json_escape(help)).concat("\"")
    }
    json = json.concat("}")
    io.println(json)
}

pub fn diag_print_human(idx: Int) ! Diag.Report {
    let sev = diag_severity.get(idx)
    let name = diag_name.get(idx)
    let msg = diag_message.get(idx)
    let file = diag_file.get(idx)
    let line = diag_line.get(idx)
    let col = diag_col.get(idx)
    let help = diag_help.get(idx)
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
    diag_count = 0
}
