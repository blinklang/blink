// test_http_live.pact — live HTTP client test (needs network + libcurl)
//
// Run: bin/pact run tests/test_http_live.pact
// Requires: network access, libcurl installed

import std.http_types
import std.http_client

fn check_int(actual: Int, expected: Int, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected {expected}, got {actual}")
    }
}

fn test_get_request() ! Net.Connect, Net.DNS {
    io.println("--- GET request ---")
    let resp = get("http://httpbin.org/get")
    check_int(client_ok, 1, "GET: client_ok is 1")
    if client_ok == 1 {
        let status = response_status(resp)
        check_int(status, 200, "GET: status is 200")
        let body = response_body(resp)
        if body.len() > 0 {
            io.println("PASS: GET: body is non-empty ({body.len()} bytes)")
        } else {
            io.println("FAIL: GET: body is empty")
        }
    }
}

fn test_post_request() ! Net.Connect, Net.DNS {
    io.println("--- POST request ---")
    let req = request_new(METHOD_POST, "http://httpbin.org/post", "\{\"hello\":\"world\"\}")
    request_add_header(req, "Content-Type", "application/json")
    let resp = request_with_headers(req, [])
    check_int(client_ok, 1, "POST: client_ok is 1")
    if client_ok == 1 {
        let status = response_status(resp)
        check_int(status, 200, "POST: status is 200")
        let body = response_body(resp)
        if body.contains("hello") {
            io.println("PASS: POST: body contains our data")
        } else {
            io.println("FAIL: POST: body doesn't contain our data")
        }
    }
}

fn test_404_request() ! Net.Connect, Net.DNS {
    io.println("--- 404 request ---")
    let resp = get("http://httpbin.org/status/404")
    check_int(client_ok, 0, "404: client_ok is 0")
}

fn main() {
    io.println("=== Live HTTP Client Tests ===")
    test_get_request()
    http_client_clear()
    http_types_clear()

    test_post_request()
    http_client_clear()
    http_types_clear()

    test_404_request()

    io.println("=== Done ===")
}
