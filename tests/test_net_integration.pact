import std.http_types
import std.http_server
import std.http_error

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
    assert(idx1 >= 0)
    if idx1 >= 0 {
        let route = srv.routes.get(idx1).unwrap()
        let req = request_new("GET", "/hello")
        let resp = route.callback(req)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "hello world")
    }

    let idx2 = match_route(srv, "POST", "/echo")
    assert(idx2 >= 0)
    if idx2 >= 0 {
        let route = srv.routes.get(idx2).unwrap()
        let req = request_new("POST", "/echo")
        let req2 = request_with_body(req, "ping")
        let resp = route.callback(req2)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "ping")
    }

    let idx3 = match_route(srv, "GET", "/users/42")
    assert(idx3 >= 0)
    if idx3 >= 0 {
        assert_eq(path_param("id"), "42")
        let route = srv.routes.get(idx3).unwrap()
        let req = request_new("GET", "/users/42")
        let resp = route.callback(req)
        assert_eq(resp.status, 200)
        assert_eq(resp.body, "user 42")
    }

    let idx4 = match_route(srv, "DELETE", "/hello")
    assert(idx4 < 0)

    let idx5 = match_route(srv, "GET", "/nonexistent")
    assert(idx5 < 0)
}

test "full pipeline" {
    let mut srv = server_new("127.0.0.1", 9999)
    srv = server_get(srv, "/greet", fn(req: Request) -> Response {
        response_ok("hi there")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })

    let raw1 = "GET /greet HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req1 = parse_request(raw1)
    let idx1 = match_route(srv, req1.method, req1.url)
    assert(idx1 >= 0)
    if idx1 >= 0 {
        let route = srv.routes.get(idx1).unwrap()
        let resp = route.callback(req1)
        let text = format_response(resp)
        assert(text.contains("200"))
        assert(text.contains("hi there"))
    }

    let raw2 = "POST /echo HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let parsed2 = parse_request(raw2)
    let req2 = request_with_body(parsed2, "hello")
    let idx2 = match_route(srv, req2.method, req2.url)
    assert(idx2 >= 0)
    if idx2 >= 0 {
        let route = srv.routes.get(idx2).unwrap()
        let resp = route.callback(req2)
        assert_eq(resp.body, "hello")
        let text = format_response(resp)
        assert(text.contains("200"))
    }

    let raw3 = "DELETE /nope HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req3 = parse_request(raw3)
    let idx3 = match_route(srv, req3.method, req3.url)
    assert(idx3 < 0)
    if idx3 < 0 {
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
    srv = server_get(srv, "/check-header", fn(req: Request) -> Response {
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

    let idx = match_route(srv, req.method, req.url)
    assert(idx >= 0)
    if idx >= 0 {
        let route = srv.routes.get(idx).unwrap()
        let resp = route.callback(req)
        assert_eq(resp.status, 200)
    }
}
