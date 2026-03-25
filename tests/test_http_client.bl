import std.http_types
import std.net_error

test "request construction" {
    let req = request_new("GET", "http://example.com/test")
    assert_eq(req.method, "GET")
    assert_eq(req.url, "http://example.com/test")
    assert_eq(req.timeout_ms, 30000)

    let req2 = request_with_body(req, "hello")
    assert_eq(req2.body, "hello")

    let req3 = request_with_header(req, "Accept", "application/json")
    assert_eq(req3.method, "GET")
}

test "response helpers" {
    let r = response_ok("hi")
    assert_eq(r.status, 200)
    assert_eq(r.body, "hi")
    assert(response_is_ok(r) != 0)

    let r2 = response_not_found("nope")
    assert_eq(r2.status, 404)
}
