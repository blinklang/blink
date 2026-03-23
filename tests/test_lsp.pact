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

test "lsp definition resolves function call to definition" {
    write_file(".tmp/lsp_test_def.pact", "fn foo() \{\n    io.println(\"hi\")\n\}\n\nfn main() \{\n    foo()\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_def.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let defn = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/definition\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_def.pact\"\},\"position\":\{\"line\":5,\"character\":4\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(defn).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("lsp_test_def.pact"))
    assert(lsp_last_out.contains("\"line\":0"))
}

test "lsp definition returns null for non-identifier" {
    write_file(".tmp/lsp_test_def2.pact", "fn main() \{\n    io.println(\"hi\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_def2.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let defn = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/definition\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_def2.pact\"\},\"position\":\{\"line\":0,\"character\":0\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(defn).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("null"))
}

test "lsp didSave after didOpen uses incremental check" {
    write_file(".tmp/lsp_test_inc.pact", "fn foo() \{\n    io.println(\"v1\")\n\}\n\nfn main() \{\n    foo()\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_inc.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let didsave = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_inc.pact\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(didsave).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_err.contains("full check"))
    assert(lsp_last_err.contains("incremental") || lsp_last_err.contains("no affected symbols"))
}

test "lsp didClose then didOpen does full recompile" {
    write_file(".tmp/lsp_test_reset.pact", "fn main() \{\n    io.println(\"hi\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen1 = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_reset.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let didclose = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_reset.pact\"\}\}\}")
    let didopen2 = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_reset.pact\",\"languageId\":\"pact\",\"version\":2,\"text\":\"\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen1).concat(didclose).concat(didopen2).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    let parts = lsp_last_err.split("full check")
    assert(parts.len() >= 3)
}

test "lsp initialize advertises hoverProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("hoverProvider"))
}

test "lsp hover on function shows signature and doc" {
    write_file(".tmp/lsp_test_hover.pact", "fn main() \{\n    greet(\"world\")\n\}\n\n/// Greets the user\nfn greet(name: Str) -> Str \{\n    \"hello\"\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hover.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let hover = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/hover\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hover.pact\"\},\"position\":\{\"line\":1,\"character\":4\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(hover).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("markdown"))
    assert(lsp_last_out.contains("greet"))
    assert(lsp_last_out.contains("Str"))
    assert(lsp_last_out.contains("Greets the user"))
}

test "lsp initialize advertises referencesProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("referencesProvider"))
}

test "lsp references finds call sites" {
    write_file(".tmp/lsp_test_refs.pact", "fn foo() \{\n    io.println(\"hi\")\n\}\n\nfn bar() \{\n    foo()\n\}\n\nfn main() \{\n    foo()\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let refs = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/references\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs.pact\"\},\"position\":\{\"line\":5,\"character\":4\},\"context\":\{\"includeDeclaration\":false\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(refs).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("lsp_test_refs.pact"))
    let parts = lsp_last_out.split("\"uri\"")
    assert(parts.len() >= 3)
}

test "lsp references includes declaration when requested" {
    write_file(".tmp/lsp_test_refs2.pact", "fn foo() \{\n    io.println(\"hi\")\n\}\n\nfn main() \{\n    foo()\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs2.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let refs_with_decl = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/references\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs2.pact\"\},\"position\":\{\"line\":5,\"character\":4\},\"context\":\{\"includeDeclaration\":true\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(refs_with_decl).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":5"))
    let uri_parts = lsp_last_out.split("\"id\":5")
    let response = uri_parts.get(1).unwrap()
    let locs = response.split("\"uri\"")
    assert(locs.len() >= 3)
    assert(response.contains("\"line\":0"))
}

test "lsp references returns empty for non-identifier" {
    write_file(".tmp/lsp_test_refs3.pact", "fn main() \{\n    io.println(\"hi\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs3.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let refs = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/references\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_refs3.pact\"\},\"position\":\{\"line\":0,\"character\":0\},\"context\":\{\"includeDeclaration\":false\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(refs).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("[]"))
}

test "lsp hover on non-identifier returns null" {
    write_file(".tmp/lsp_test_hover2.pact", "fn main() \{\n    io.println(\"hi\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hover2.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let hover = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/hover\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hover2.pact\"\},\"position\":\{\"line\":0,\"character\":0\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(hover).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("null"))
}

// ── documentSymbol tests ────────────────────────────────────────

test "lsp initialize advertises documentSymbolProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("documentSymbolProvider"))
}

test "lsp documentSymbol returns functions and types" {
    write_file(".tmp/lsp_test_symbols.pact", "fn foo() \{\n    io.println(\"hi\")\n\}\n\ntype Bar \{ x: Int \}\n\nfn main() \{\n    foo()\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_symbols.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let docsym = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/documentSymbol\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_symbols.pact\"\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(docsym).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("foo"))
    assert(lsp_last_out.contains("Bar"))
    assert(lsp_last_out.contains("main"))
    assert(lsp_last_out.contains("\"kind\":12"))
    assert(lsp_last_out.contains("\"kind\":23"))
}

// ── completion tests ────────────────────────────────────────────

test "lsp initialize advertises completionProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("completionProvider"))
}

test "lsp completion returns matching symbols" {
    write_file(".tmp/lsp_test_comp.pact", "fn foo_bar() \{\n    io.println(\"a\")\n\}\n\nfn foo_baz() \{\n    io.println(\"b\")\n\}\n\nfn main() \{\n    let fo = 1\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_comp.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let comp = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_comp.pact\"\},\"position\":\{\"line\":9,\"character\":10\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(comp).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("foo_bar"))
    assert(lsp_last_out.contains("foo_baz"))
    assert(lsp_last_out.contains("\"kind\":3"))
}

test "lsp completion returns keywords" {
    write_file(".tmp/lsp_test_comp_kw.pact", "fn main() \{\n    let wh = 1\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_comp_kw.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let comp = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_comp_kw.pact\"\},\"position\":\{\"line\":1,\"character\":10\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(comp).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("while"))
    assert(lsp_last_out.contains("\"kind\":14"))
}

// ── signatureHelp tests ─────────────────────────────────────────

test "lsp initialize advertises signatureHelpProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("signatureHelpProvider"))
}

test "lsp signatureHelp shows params inside call" {
    write_file(".tmp/lsp_test_sig.pact", "fn greet(name: Str, age: Int) -> Str \{\n    \"hello\"\n\}\n\nfn main() \{\n    greet(\"a\", 1)\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let sighelp = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/signatureHelp\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig.pact\"\},\"position\":\{\"line\":5,\"character\":10\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(sighelp).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("greet"))
    assert(lsp_last_out.contains("signatures"))
    assert(lsp_last_out.contains("\"activeParameter\":0"))
}

test "lsp signatureHelp after comma shows second param" {
    write_file(".tmp/lsp_test_sig2.pact", "fn greet(name: Str, age: Int) -> Str \{\n    \"hello\"\n\}\n\nfn main() \{\n    greet(\"hi\", 1)\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig2.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let sighelp = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/signatureHelp\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig2.pact\"\},\"position\":\{\"line\":5,\"character\":17\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(sighelp).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("\"activeParameter\":1"))
}

test "lsp signatureHelp outside call returns null" {
    write_file(".tmp/lsp_test_sig3.pact", "fn main() \{\n    io.println(\"hi\")\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig3.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let sighelp = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/signatureHelp\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_sig3.pact\"\},\"position\":\{\"line\":0,\"character\":0\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(sighelp).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("null"))
}

// ── inlayHint tests ────────────────────────────────────────────

test "lsp initialize advertises inlayHintProvider" {
    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("inlayHintProvider"))
}

test "lsp inlayHint shows inferred type for let without annotation" {
    write_file(".tmp/lsp_test_hint.pact", "fn main() \{\n    let _x = 42\n    let _y = \"hello\"\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let hint = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/inlayHint\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint.pact\"\},\"range\":\{\"start\":\{\"line\":0,\"character\":0\},\"end\":\{\"line\":10,\"character\":0\}\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(hint).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains(": Int"))
    assert(lsp_last_out.contains(": Str"))
}

test "lsp inlayHint does not show hint for annotated let" {
    write_file(".tmp/lsp_test_hint2.pact", "fn main() \{\n    let _x: Int = 42\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint2.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let hint = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/inlayHint\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint2.pact\"\},\"range\":\{\"start\":\{\"line\":0,\"character\":0\},\"end\":\{\"line\":10,\"character\":0\}\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(hint).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains("[]"))
}

test "lsp inlayHint shows correct label format" {
    write_file(".tmp/lsp_test_hint3.pact", "fn add(a: Int, b: Int) -> Int \{ a + b \}\n\nfn main() \{\n    let _result = add(1, 2)\n\}\n")

    let init = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{\"capabilities\":\{\}\}\}")
    let initialized = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":\{\}\}")
    let didopen = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint3.pact\",\"languageId\":\"pact\",\"version\":1,\"text\":\"\"\}\}\}")
    let hint = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/inlayHint\",\"params\":\{\"textDocument\":\{\"uri\":\"file://.tmp/lsp_test_hint3.pact\"\},\"range\":\{\"start\":\{\"line\":0,\"character\":0\},\"end\":\{\"line\":10,\"character\":0\}\}\}\}")
    let shutdown = lsp_msg("\{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null\}")
    let exit_msg = lsp_msg("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":\{\}\}")
    let input = init.concat(initialized).concat(didopen).concat(hint).concat(shutdown).concat(exit_msg)

    lsp_run_session(input)
    assert(lsp_last_out.contains("\"id\":3"))
    assert(lsp_last_out.contains(": Int"))
    assert(lsp_last_out.contains("\"kind\":1"))
}
