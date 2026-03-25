fn has_substr(haystack: Str, needle: Str) -> Int {
    if needle.len() > haystack.len() {
        return 0
    }
    let mut i = 0
    while i <= haystack.len() - needle.len() {
        if haystack.substring(i, needle.len()) == needle {
            return 1
        }
        i = i + 1
    }
    0
}

fn json_get_str(json: Str, key: Str) -> Str {
    let needle = "\"".concat(key).concat("\":\"")
    let mut i = 0
    while i <= json.len() - needle.len() {
        if json.substring(i, needle.len()) == needle {
            let val_start = i + needle.len()
            let mut j = val_start
            while j < json.len() {
                if json.char_at(j) == 34 {
                    return json.substring(val_start, j - val_start)
                }
                if json.char_at(j) == 92 {
                    j = j + 2
                } else {
                    j = j + 1
                }
            }
            return ""
        }
        i = i + 1
    }
    ""
}

test "status request" {
    let req = "\{\"type\":\"status\"}"
    assert_eq(json_get_str(req, "type"), "status")
}

test "stop request" {
    let req = "\{\"type\":\"stop\"}"
    assert_eq(json_get_str(req, "type"), "stop")
}

test "query fn request" {
    let name = "my_func"
    let req = "\{\"type\":\"query\",\"query_type\":\"fn\",\"name\":\"{name}\"}"
    assert_eq(json_get_str(req, "type"), "query")
    assert_eq(json_get_str(req, "query_type"), "fn")
    assert_eq(json_get_str(req, "name"), "my_func")
}

test "query effect request" {
    let eff_name = "IO"
    let req = "\{\"type\":\"query\",\"query_type\":\"effect\",\"effect\":\"{eff_name}\"}"
    assert_eq(json_get_str(req, "type"), "query")
    assert_eq(json_get_str(req, "query_type"), "effect")
    assert_eq(json_get_str(req, "effect"), "IO")
}

test "query signature request" {
    let mod_name = "main"
    let req = "\{\"type\":\"query\",\"query_type\":\"signature\",\"module\":\"{mod_name}\"}"
    assert_eq(json_get_str(req, "type"), "query")
    assert_eq(json_get_str(req, "query_type"), "signature")
    assert_eq(json_get_str(req, "module"), "main")
}

test "query pub pure request" {
    let req = "\{\"type\":\"query\",\"query_type\":\"pub_pure\"}"
    assert_eq(json_get_str(req, "type"), "query")
    assert_eq(json_get_str(req, "query_type"), "pub_pure")
}

test "status response format" {
    let resp = "\{\"ok\":true,\"uptime_ms\":12345,\"symbols\":10,\"files\":2,\"checks\":3}"
    assert_eq(json_get_str(resp, "uptime_ms"), "")
    assert_eq(has_substr(resp, "\"ok\":true"), 1)
    assert_eq(has_substr(resp, "\"uptime_ms\":"), 1)
    assert_eq(has_substr(resp, "\"symbols\":"), 1)
    assert_eq(has_substr(resp, "\"files\":"), 1)
    assert_eq(has_substr(resp, "\"checks\":"), 1)
}

test "stop response format" {
    let resp = "\{\"ok\":true,\"message\":\"daemon stopping\"}"
    assert_eq(has_substr(resp, "\"ok\":true"), 1)
    assert_eq(json_get_str(resp, "message"), "daemon stopping")
}

test "error response format" {
    let resp = "\{\"ok\":false,\"error\":\"unknown request type: bogus\"}"
    assert_eq(has_substr(resp, "\"ok\":false"), 1)
    assert_eq(has_substr(resp, "\"error\":"), 1)
}

test "json get missing key" {
    let json = "\{\"type\":\"status\"}"
    assert_eq(json_get_str(json, "missing"), "")
}

test "json get empty value" {
    let json = "\{\"type\":\"\"}"
    assert_eq(json_get_str(json, "type"), "")
}

test "json get multiple keys" {
    let json = "\{\"a\":\"one\",\"b\":\"two\",\"c\":\"three\"}"
    assert_eq(json_get_str(json, "a"), "one")
    assert_eq(json_get_str(json, "b"), "two")
    assert_eq(json_get_str(json, "c"), "three")
}

test "check request" {
    let req = "\{\"type\":\"check\"}"
    assert_eq(json_get_str(req, "type"), "check")
}

test "query dispatch request" {
    let req = "\{\"type\":\"signature\",\"module\":\"codegen\"}"
    assert_eq(json_get_str(req, "type"), "signature")
    assert_eq(json_get_str(req, "module"), "codegen")
}
