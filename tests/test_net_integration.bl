import std.http_types
import std.http_server

test "str methods" {
    let s = "hello world"
    assert_eq(s.slice(0, 5), "hello")
    assert_eq(s.slice(6, 11), "world")
    assert_eq("42".to_int(), 42)
    assert_eq("0".to_int(), 0)
    assert_eq("-7".to_int(), -7)
}

test "http parsing" {
    let raw_get = "GET /foo HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req1 = parse_request(raw_get)
    assert_eq(req1.method, "GET")
    assert_eq(req1.url, "/foo")

    let raw_post = "POST /bar/baz HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req2 = parse_request(raw_post)
    assert_eq(req2.method, "POST")
    assert_eq(req2.url, "/bar/baz")
}

test "response formatting" {
    let resp = response_ok("hello world")
    let text = format_response(resp)
    assert(text.contains("200"))
    assert(text.contains("OK"))
    assert(text.contains("hello world"))
    assert(text.contains("Content-Length: 11"))

    let resp404 = response_not_found("not here")
    let text404 = format_response(resp404)
    assert(text404.contains("404"))
    assert(text404.contains("Not Found"))
    assert(text404.contains("not here"))
}

test "server routing" {
    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_get(srv, "/hello", fn(_req: Request) -> Response {
        response_ok("hello world")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })
    srv = server_get(srv, "/users/:id", fn(req: Request) -> Response {
        let id = req_path_param(req, "id")
        response_ok("user {id}")
    })

    let r1 = match_route(srv, "GET", "/hello")
    assert(r1.index >= 0)
    if r1.index >= 0 {
        let route = srv.routes.get(r1.index).unwrap()
        let req = request_new("GET", "/hello")
        let resp = route.callback(req)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "hello world")
    }

    let r2 = match_route(srv, "POST", "/echo")
    assert(r2.index >= 0)
    if r2.index >= 0 {
        let route = srv.routes.get(r2.index).unwrap()
        let req = request_new("POST", "/echo")
        let req2 = request_with_body(req, "ping")
        let resp = route.callback(req2)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "ping")
    }

    let r3 = match_route(srv, "GET", "/users/42")
    assert(r3.index >= 0)
    if r3.index >= 0 {
        let route = srv.routes.get(r3.index).unwrap()
        let base = request_new("GET", "/users/42")
        let req3 = Request { method: base.method, url: base.url, body: base.body, headers: base.headers, param_names: r3.param_names, param_values: r3.param_values, timeout_ms: base.timeout_ms }
        let resp = route.callback(req3)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "user 42")
    }

    let r4 = match_route(srv, "DELETE", "/hello")
    assert(r4.index < 0)

    let r5 = match_route(srv, "GET", "/nonexistent")
    assert(r5.index < 0)
}

test "full pipeline" {
    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_get(srv, "/greet", fn(_req: Request) -> Response {
        response_ok("hi there")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })

    let raw1 = "GET /greet HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req1 = parse_request(raw1)
    let r1 = match_route(srv, req1.method, req1.url)
    assert(r1.index >= 0)
    if r1.index >= 0 {
        let route = srv.routes.get(r1.index).unwrap()
        let resp = route.callback(req1)
        let text = format_response(resp)
        assert(text.contains("200"))
        assert(text.contains("hi there"))
    }

    let raw2 = "POST /echo HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let parsed2 = parse_request(raw2)
    let req2 = request_with_body(parsed2, "hello")
    let r2 = match_route(srv, req2.method, req2.url)
    assert(r2.index >= 0)
    if r2.index >= 0 {
        let route = srv.routes.get(r2.index).unwrap()
        let resp = route.callback(req2)
        assert_eq(resp.body, "hello")
        let text = format_response(resp)
        assert(text.contains("200"))
    }

    let raw3 = "DELETE /nope HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req3 = parse_request(raw3)
    let r3 = match_route(srv, req3.method, req3.url)
    assert(r3.index < 0)
    if r3.index < 0 {
        let resp = response_not_found("not found")
        let text = format_response(resp)
        assert(text.contains("404"))
    }
}

test "middleware" {
    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_use(srv, "add-header", fn(req: Request) -> Request {
        request_with_header(req, "X-Test", "injected")
    })
    srv = server_get(srv, "/check-header", fn(_req: Request) -> Response {
        response_ok("checked")
    })

    assert_eq(srv.before_hooks.len(), 1)

    let h0 = srv.before_hooks.get(0).unwrap()
    assert_eq(h0.name, "add-header")

    let raw_req = request_new("GET", "/check-header")
    let hook = srv.before_hooks.get(0).unwrap()
    let req = hook.process(raw_req)

    let hdr_val = req.headers.get("X-Test")
    assert_eq(hdr_val, "injected")

    let r = match_route(srv, req.method, req.url)
    assert(r.index >= 0)
    if r.index >= 0 {
        let route = srv.routes.get(r.index).unwrap()
        let resp = route.callback(req)
        assert_eq(resp.status, 200)
    }
}
