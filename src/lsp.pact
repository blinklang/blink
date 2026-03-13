import std.json
import diagnostics

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
    let mut body = ""
    match bytes.to_str() {
        Ok(s) => body = s
        Err(_) => body = ""
    }
    body
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

fn lsp_handle_initialize() -> Str {
    "\{\"capabilities\":\{\"textDocumentSync\":1,\"definitionProvider\":true\},\"serverInfo\":\{\"name\":\"pact-lsp\",\"version\":\"0.1.0\"\}\}"
}

fn lsp_handle_shutdown() -> Str {
    "null"
}

fn lsp_dispatch(method: Str, id_int: Int, id_is_present: Int) ! IO {
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
    } else {
        if id_is_present != 0 {
            lsp_send_error_int(id_int, -32601, "Method not found")
        }
    }
}

pub fn lsp_start() ! IO {
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

        lsp_dispatch(method, id_int, id_is_present)
    }
    io.eprintln("pact-lsp: stopped")
}
