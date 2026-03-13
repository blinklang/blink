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
