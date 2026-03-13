import std.json
import diagnostics
import compiler
import lexer
import parser
import typecheck

let mut lsp_running: Int = 0

pub fn lsp_parse_content_length(line: Str) -> Int {
    if line.starts_with("Content-Length: ") != 0 {
        let num_str = line.substring(16, line.len() - 16)
        return parse_int(num_str)
    }
    -1
}

fn lsp_read_content_length() -> Int ! IO {
    let mut content_length = -1
    let mut done = 0
    while done == 0 {
        let line = io.read_line()
        if line == "" {
            done = 1
        } else {
            let cl = lsp_parse_content_length(line)
            if cl >= 0 {
                content_length = cl
            }
        }
    }
    content_length
}

fn lsp_read_message() -> Str ! IO {
    let cl = lsp_read_content_length()
    if cl <= 0 {
        return ""
    }
    let bytes = io.read_bytes(cl)
    let result = bytes.to_str()
    match result {
        Ok(s) => return s
        Err(_) => return ""
    }
}

fn lsp_write_message(body: Str) ! IO {
    let len = body.len()
    io.write("Content-Length: {len}\r\n\r\n")
    io.write(body)
}

fn lsp_send_response_int(id: Int, result_json: Str) ! IO {
    let body = "\{\"jsonrpc\":\"2.0\",\"id\":{id},\"result\":{result_json}\}"
    lsp_write_message(body)
}

fn lsp_send_error_int(id: Int, code: Int, message: Str) ! IO {
    let escaped = json_escape(message)
    let body = "\{\"jsonrpc\":\"2.0\",\"id\":{id},\"error\":\{\"code\":{code},\"message\":\"{escaped}\"\}\}"
    lsp_write_message(body)
}

fn lsp_send_notification(method: Str, params: Str) ! IO {
    let escaped_method = json_escape(method)
    let body = "\{\"jsonrpc\":\"2.0\",\"method\":\"{escaped_method}\",\"params\":{params}\}"
    lsp_write_message(body)
}

fn lsp_handle_initialize() -> Str {
    "\{\"capabilities\":\{\"textDocumentSync\":1,\"definitionProvider\":true\},\"serverInfo\":\{\"name\":\"pact-lsp\",\"version\":\"0.1.0\"\}\}"
}

fn lsp_handle_shutdown() -> Str {
    "null"
}

pub fn lsp_uri_to_path(uri: Str) -> Str {
    if uri.starts_with("file://") != 0 {
        return uri.substring(7, uri.len() - 7)
    }
    uri
}

pub fn lsp_severity(sev: Str) -> Int {
    if sev == "error" {
        return 1
    }
    if sev == "warning" {
        return 2
    }
    3
}

pub fn lsp_to_zero_based(n: Int) -> Int {
    if n > 0 {
        return n - 1
    }
    0
}

fn lsp_build_diagnostics_json(uri: Str) -> Str {
    let mut diags = ""
    let mut i = 0
    while i < diag_severity.len() {
        if i > 0 {
            diags = diags.concat(",")
        }
        let sev = lsp_severity(diag_severity.get(i).unwrap())
        let line = lsp_to_zero_based(diag_line.get(i).unwrap())
        let col = lsp_to_zero_based(diag_col.get(i).unwrap())
        let el = diag_end_line.get(i).unwrap()
        let ec = diag_end_col.get(i).unwrap()
        let end_line = if el > 0 { lsp_to_zero_based(el) } else { line }
        let end_col = if el > 0 { lsp_to_zero_based(ec) } else { col }
        let code = json_escape(diag_code.get(i).unwrap())
        let msg = json_escape(diag_message.get(i).unwrap())
        diags = diags.concat("\{\"range\":\{\"start\":\{\"line\":{line},\"character\":{col}\},\"end\":\{\"line\":{end_line},\"character\":{end_col}\}\},\"severity\":{sev},\"code\":\"{code}\",\"source\":\"pact\",\"message\":\"{msg}\"\}")
        i = i + 1
    }
    "\{\"uri\":\"{uri}\",\"diagnostics\":[{diags}]\}"
}

fn lsp_check_and_publish(uri: Str, file_path: Str) ! IO, Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck {
    io.eprintln("pact-lsp: checking {file_path}")
    reset_compiler_state()
    diag_reset()
    diag_source_file = file_path

    let source = read_file(file_path)
    lex(source)
    pos = 0
    let program = parse_program()
    loaded_files.push(file_path)

    let src_root = find_src_root(file_path)
    let mut imported_programs: List[Int] = []
    collect_root_imports(program)
    collect_imports(program, src_root, imported_programs)
    inject_prelude(src_root, imported_programs)

    let mut final_program = program
    if imported_programs.len() > 0 {
        final_program = merge_programs(program, imported_programs, import_map_nodes)
    }

    check_types(final_program)
    check_unused_imports()

    let params = lsp_build_diagnostics_json(uri)
    lsp_send_notification("textDocument/publishDiagnostics", params)
    io.eprintln("pact-lsp: published {diag_severity.len()} diagnostic(s)")
}

fn lsp_extract_document_uri(root: Int) -> Str {
    let params_node = json_get(root, "params")
    if params_node == -1 {
        return ""
    }
    let td_node = json_get(params_node, "textDocument")
    if td_node == -1 {
        return ""
    }
    let uri_node = json_get(td_node, "uri")
    if uri_node == -1 {
        return ""
    }
    json_as_str(uri_node)
}

fn lsp_handle_did_open_or_save(root: Int) ! IO, Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck {
    let uri = lsp_extract_document_uri(root)
    if uri == "" {
        return
    }
    lsp_check_and_publish(uri, lsp_uri_to_path(uri))
}

fn lsp_handle_did_close(root: Int) ! IO {
    let uri = lsp_extract_document_uri(root)
    if uri == "" {
        return
    }
    let params = "\{\"uri\":\"{uri}\",\"diagnostics\":[]\}"
    lsp_send_notification("textDocument/publishDiagnostics", params)
}

fn lsp_dispatch(method: Str, id_int: Int, id_is_present: Int, root: Int) ! IO, Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck {
    if method == "initialize" {
        let result = lsp_handle_initialize()
        if id_is_present != 0 {
            lsp_send_response_int(id_int, result)
        }
    } else if method == "initialized" {
        // no response for notifications
    } else if method == "shutdown" {
        let result = lsp_handle_shutdown()
        if id_is_present != 0 {
            lsp_send_response_int(id_int, result)
        }
    } else if method == "exit" {
        lsp_running = 0
    } else if method == "textDocument/didOpen" {
        lsp_handle_did_open_or_save(root)
    } else if method == "textDocument/didSave" {
        lsp_handle_did_open_or_save(root)
    } else if method == "textDocument/didClose" {
        lsp_handle_did_close(root)
    } else {
        if id_is_present != 0 {
            lsp_send_error_int(id_int, -32601, "Method not found")
        }
    }
}

pub fn lsp_start() ! IO, Lex.Tokenize, Parse, Parse.Build, Diag.Report, TypeCheck {
    lsp_running = 1
    io.eprintln("pact-lsp: starting")
    while lsp_running == 1 {
        let msg = lsp_read_message()
        if msg == "" {
            lsp_running = 0
            continue
        }

        json_clear()
        let root = json_parse(msg)
        if root == -1 {
            continue
        }

        let method_node = json_get(root, "method")
        let method = if method_node != -1 { json_as_str(method_node) } else { "" }

        let id_node = json_get(root, "id")
        let id_is_present = if id_node != -1 { 1 } else { 0 }
        let id_int = if id_node != -1 && json_type(id_node) == JSON_INT { json_as_int(id_node) } else { 0 }

        lsp_dispatch(method, id_int, id_is_present, root)
    }
    io.eprintln("pact-lsp: stopped")
}
