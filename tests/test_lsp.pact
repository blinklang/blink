fn parse_content_length(line: Str) -> Int {
    if line.starts_with("Content-Length: ") != 0 {
        let num_str = line.substring(16, line.len() - 16)
        return parse_int(num_str)
    }
    -1
}

test "parse content length from valid header" {
    assert_eq(parse_content_length("Content-Length: 42"), 42)
    assert_eq(parse_content_length("Content-Length: 0"), 0)
    assert_eq(parse_content_length("Content-Length: 1234"), 1234)
}

test "parse content length returns -1 for non-matching headers" {
    assert_eq(parse_content_length("Content-Type: utf-8"), -1)
    assert_eq(parse_content_length(""), -1)
}

fn mock_initialize_result() -> Str {
    "\{\"capabilities\":\{\"textDocumentSync\":1,\"definitionProvider\":true\},\"serverInfo\":\{\"name\":\"pact-lsp\",\"version\":\"0.1.0\"\}\}"
}

test "initialize result contains expected capabilities" {
    let result = mock_initialize_result()
    assert(result.contains("textDocumentSync"))
    assert(result.contains("definitionProvider"))
    assert(result.contains("pact-lsp"))
}

fn uri_to_path(uri: Str) -> Str {
    if uri.starts_with("file://") != 0 {
        return uri.substring(7, uri.len() - 7)
    }
    uri
}

test "uri to path strips file:// prefix" {
    assert_eq(uri_to_path("file:///home/user/test.pact"), "/home/user/test.pact")
    assert_eq(uri_to_path("file:///tmp/foo.pact"), "/tmp/foo.pact")
}

test "uri to path returns raw string if no file:// prefix" {
    assert_eq(uri_to_path("/already/a/path"), "/already/a/path")
    assert_eq(uri_to_path(""), "")
}

fn severity_to_lsp(sev: Str) -> Int {
    if sev == "error" {
        return 1
    }
    if sev == "warning" {
        return 2
    }
    3
}

test "severity mapping" {
    assert_eq(severity_to_lsp("error"), 1)
    assert_eq(severity_to_lsp("warning"), 2)
    assert_eq(severity_to_lsp("info"), 3)
}

fn to_zero_based(n: Int) -> Int {
    if n > 0 {
        return n - 1
    }
    0
}

test "1-based to 0-based line/col conversion" {
    assert_eq(to_zero_based(1), 0)
    assert_eq(to_zero_based(10), 9)
    assert_eq(to_zero_based(0), 0)
}

// ── LSP integration helpers ──────────────────────────────────────

fn lsp_msg(body: Str) -> Str {
    let len = body.len()
    "Content-Length: {len}\r\n\r\n{body}"
}

fn lsp_run_session(input: Str) {
    write_file(".tmp/lsp_test_input.bin", input)
    let result = process_run("sh", ["-c", "timeout 5 build/pact lsp < .tmp/lsp_test_input.bin"])
    lsp_last_out = result.out
    lsp_last_err = result.err_out
    lsp_last_exit = result.exit_code
}

let mut lsp_last_out: Str = ""
let mut lsp_last_err: Str = ""
let mut lsp_last_exit: Int = -1

// ── LSP integration tests ────────────────────────────────────────

test "lsp initialize returns capabilities" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.len() > 0)
    assert(lsp_last_out.contains("textDocumentSync"))
    assert(lsp_last_out.contains("pact-lsp"))
}

test "lsp didOpen with type error produces diagnostics" {
    write_file(".tmp/lsp_test_bad.pact", "fn main() \{\n    let x: Int = \"hello\"\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_bad.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("publishDiagnostics"))
    assert(lsp_last_out.contains("severity"))
}

test "lsp didOpen with clean file produces empty diagnostics" {
    write_file(".tmp/lsp_test_good.pact", "fn main() \{\n    io.println(\"hello\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_good.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("publishDiagnostics"))
    assert(lsp_last_out.contains("\"diagnostics\":[]"))
}

test "lsp didClose clears diagnostics" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didclose = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_bad.pact\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didclose).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("publishDiagnostics"))
    assert(lsp_last_out.contains("\"diagnostics\":[]"))
}
