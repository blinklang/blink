import std.http_types
import std.http_error

test "request construction" {
    let req = request_new("GET", "https://example.com/api")
    assert_eq(req.method, "GET")
    assert_eq(req.url, "https://example.com/api")
    assert_eq(req.body, "")
    assert_eq(req.timeout_ms, 30000)
}

test "request with body" {
    let req = request_new("GET", "https://example.com/api")
    let req2 = request_with_body(req, "hello world")
    assert_eq(req2.body, "hello world")
    assert_eq(req2.method, "GET")
}

test "request with header" {
    let req = request_new("GET", "https://example.com/api")
    let req2 = request_with_body(req, "hello world")
    let req3 = request_with_header(req2, "Content-Type", "application/json")
    assert_eq(req3.headers.has("Content-Type"), 1)
    let ct_val = req3.headers.get("Content-Type")
    assert_eq(ct_val, "application/json")
}

test "request with timeout" {
    let req = request_new("GET", "https://example.com/api")
    let req4 = request_with_timeout(req, 5000)
    assert_eq(req4.timeout_ms, 5000)
}

test "response construction and ok check" {
    let resp = response_new(200, "hello")
    assert_eq(resp.status, 200)
    assert_eq(resp.body, "hello")
    assert_eq(response_is_ok(resp), true)
}

test "response not found" {
    let resp404 = response_not_found("not here")
    assert_eq(resp404.status, 404)
    assert_eq(response_is_ok(resp404), false)
}

test "response bad request" {
    let resp400 = response_bad_request("bad input")
    assert_eq(resp400.status, 400)
}

test "response internal error" {
    let resp500 = response_internal_error("oops")
    assert_eq(resp500.status, 500)
}

test "response ok helper" {
    let resp_ok = response_ok("all good")
    assert_eq(resp_ok.status, 200)
    assert_eq(resp_ok.body, "all good")
}

test "response json helper" {
    let resp_json = response_json("ok-json")
    assert_eq(resp_json.status, 200)
    let json_ct = resp_json.headers.get("Content-Type")
    assert_eq(json_ct, "application/json")
}

test "status reason codes" {
    assert_eq(status_reason(200), "OK")
    assert_eq(status_reason(404), "Not Found")
    assert_eq(status_reason(500), "Internal Server Error")
    assert_eq(status_reason(999), "Unknown")
}

test "net error display" {
    let err1 = NetError.Timeout("request timed out")
    assert_eq(net_error_display(err1), "timeout: request timed out")

    let err2 = NetError.ConnectionRefused("port closed")
    assert_eq(net_error_display(err2), "connection_refused: port closed")

    let err3 = NetError.DnsFailure("no such host")
    assert_eq(net_error_display(err3), "dns_failure: no such host")

    let err4 = NetError.TlsError("cert expired")
    assert_eq(net_error_display(err4), "tls: cert expired")

    let err5 = NetError.InvalidUrl("missing scheme")
    assert_eq(net_error_display(err5), "invalid_url: missing scheme")
}
