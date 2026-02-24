// test_net_integration.pact — integration tests for struct-based HTTP API
//
// Tests request/response construction, parsing, formatting, server routing,
// and the full dispatch pipeline working together.

import std.http_types
import std.http_server
import std.http_error

fn check(cond: Int, label: Str) {
    if cond != 0 {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label}")
    }
}

// ── Test 1: Str.slice and Str.to_int ────────────────────────────────

fn test_str_methods() {
    io.println("--- Str.slice + Str.to_int ---")
    let s = "hello world"
    check(s.slice(0, 5) == "hello", "slice(0,5) == hello")
    check(s.slice(6, 11) == "world", "slice(6,11) == world")
    check("42".to_int() == 42, "to_int: 42")
    check("0".to_int() == 0, "to_int: 0")
    check("-7".to_int() == -7, "to_int: -7")
}

// ── Test 2: HTTP request parsing ────────────────────────────────────

fn test_http_parsing() {
    io.println("--- HTTP parsing ---")

    // Note: \r codegen produces backslash not CR, so parse_request body
    // extraction (which scans for char 13) won't find the boundary.
    // We test method/url parsing here; body is tested via struct API.
    let raw_get = "GET /foo HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req1 = parse_request(raw_get)
    check(req1.method == "GET", "parse GET method")
    check(req1.url == "/foo", "parse GET url")

    let raw_post = "POST /bar/baz HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req2 = parse_request(raw_post)
    check(req2.method == "POST", "parse POST method")
    check(req2.url == "/bar/baz", "parse POST url")
}

// ── Test 3: response formatting ─────────────────────────────────────

fn test_response_formatting() {
    io.println("--- response formatting ---")

    let resp = response_ok("hello world")
    let text = format_response(resp)
    check(text.contains("200"), "format contains status 200")
    check(text.contains("OK"), "format contains reason OK")
    check(text.contains("hello world"), "format contains body")
    check(text.contains("Content-Length: 11"), "format contains content-length")

    let resp404 = response_not_found("not here")
    let text404 = format_response(resp404)
    check(text404.contains("404"), "format 404 status")
    check(text404.contains("Not Found"), "format 404 reason")
    check(text404.contains("not here"), "format 404 body")
}

// ── Test 4: server routing + dispatch ───────────────────────────────

fn test_server_routing() {
    io.println("--- server routing ---")

    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_get(srv, "/hello", fn(req: Request) -> Response {
        response_ok("hello world")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })
    srv = server_get(srv, "/users/:id", fn(req: Request) -> Response {
        let id = path_param("id")
        response_ok("user {id}")
    })

    let idx1 = match_route(srv, "GET", "/hello")
    check(idx1 >= 0, "match GET /hello")
    if idx1 >= 0 {
        let route = srv.routes.get(idx1)
        let req = request_new("GET", "/hello")
        let resp = route.callback(req)
        check(resp.status == 200, "GET /hello status 200")
        check(resp.body == "hello world", "GET /hello body")
    }

    let idx2 = match_route(srv, "POST", "/echo")
    check(idx2 >= 0, "match POST /echo")
    if idx2 >= 0 {
        let route = srv.routes.get(idx2)
        let req = request_new("POST", "/echo")
        let req2 = request_with_body(req, "ping")
        let resp = route.callback(req2)
        check(resp.status == 200, "POST /echo status 200")
        check(resp.body == "ping", "POST /echo body echoed")
    }

    let idx3 = match_route(srv, "GET", "/users/42")
    check(idx3 >= 0, "match GET /users/:id")
    if idx3 >= 0 {
        check(path_param("id") == "42", "path param id=42")
        let route = srv.routes.get(idx3)
        let req = request_new("GET", "/users/42")
        let resp = route.callback(req)
        check(resp.status == 200, "GET /users/42 status 200")
        check(resp.body == "user 42", "GET /users/42 body")
    }

    let idx4 = match_route(srv, "DELETE", "/hello")
    check(idx4 < 0, "no match DELETE /hello")

    let idx5 = match_route(srv, "GET", "/nonexistent")
    check(idx5 < 0, "no match GET /nonexistent")
}

// ── Test 5: full pipeline (parse → route → dispatch → format) ──────

fn test_full_pipeline() {
    io.println("--- full pipeline ---")

    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_get(srv, "/greet", fn(req: Request) -> Response {
        response_ok("hi there")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })

    // Simulate GET /greet
    let raw1 = "GET /greet HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req1 = parse_request(raw1)
    let idx1 = match_route(srv, req1.method, req1.url)
    check(idx1 >= 0, "pipeline: matched GET /greet")
    if idx1 >= 0 {
        let route = srv.routes.get(idx1)
        let resp = route.callback(req1)
        let text = format_response(resp)
        check(text.contains("200"), "pipeline: GET response 200")
        check(text.contains("hi there"), "pipeline: GET response body")
    }

    // Simulate POST /echo — build request via struct API since \r body
    // parsing is limited (see test_http_parsing note)
    let raw2 = "POST /echo HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let parsed2 = parse_request(raw2)
    let req2 = request_with_body(parsed2, "hello")
    let idx2 = match_route(srv, req2.method, req2.url)
    check(idx2 >= 0, "pipeline: matched POST /echo")
    if idx2 >= 0 {
        let route = srv.routes.get(idx2)
        let resp = route.callback(req2)
        check(resp.body == "hello", "pipeline: POST echoed body")
        let text = format_response(resp)
        check(text.contains("200"), "pipeline: POST response 200")
    }

    // Simulate unmatched route
    let raw3 = "DELETE /nope HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req3 = parse_request(raw3)
    let idx3 = match_route(srv, req3.method, req3.url)
    check(idx3 < 0, "pipeline: no match for DELETE /nope")
    if idx3 < 0 {
        let resp = response_not_found("not found")
        let text = format_response(resp)
        check(text.contains("404"), "pipeline: 404 response")
    }
}

// ── Test 6: middleware hooks ────────────────────────────────────────

fn test_middleware() {
    io.println("--- middleware ---")

    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_use(srv, "add-header", fn(req: Request) -> Request {
        request_with_header(req, "X-Test", "injected")
    })
    srv = server_get(srv, "/check-header", fn(req: Request) -> Response {
        response_ok("checked")
    })

    check(srv.before_hooks.len() == 1, "1 hook registered")

    let h0 = srv.before_hooks.get(0)
    check(h0.name == "add-header", "hook name correct")

    // Simulate the middleware pipeline manually
    let raw_req = request_new("GET", "/check-header")
    let hook = srv.before_hooks.get(0)
    let req = hook.process(raw_req)

    // Verify header was injected by extracting from the processed request
    let hdr_val = req.headers.get("X-Test")
    check(hdr_val == "injected", "hook injected header")

    let idx = match_route(srv, req.method, req.url)
    check(idx >= 0, "middleware: route matched")
    if idx >= 0 {
        let route = srv.routes.get(idx)
        let resp = route.callback(req)
        check(resp.status == 200, "middleware: handler returned 200")
    }
}

fn main() {
    io.println("=== net integration tests ===")
    test_str_methods()
    test_http_parsing()
    test_response_formatting()
    test_server_routing()
    test_full_pipeline()
    test_middleware()
    io.println("=== done ===")
}
