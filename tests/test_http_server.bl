import std.http_types
import std.http_server

test "server construction" {
    let srv = server_new("127.0.0.1", 8080)
    assert_eq(srv.host, "127.0.0.1")
    assert_eq(srv.port, 8080)
    assert_eq(srv.routes.len(), 0)
    assert_eq(srv.before_hooks.len(), 0)
}

test "route registration" {
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(_req: Request) -> Response {
        response_ok("hello world")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })
    assert_eq(srv.routes.len(), 2)

    let r0 = srv.routes.get(0).unwrap()
    assert_eq(r0.method, "GET")
    assert_eq(r0.pattern, "/hello")

    let r1 = srv.routes.get(1).unwrap()
    assert_eq(r1.method, "POST")
    assert_eq(r1.pattern, "/echo")
}

test "handler dispatch" {
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(_req: Request) -> Response {
        response_ok("hello from handler")
    })

    let route = srv.routes.get(0).unwrap()
    let req = request_new("GET", "/hello")
    let resp = route.callback(req)
    assert_eq(resp.status, 200)
    assert_eq(resp.body, "hello from handler")
}

test "route matching" {
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(_req: Request) -> Response { response_ok("hello") })
    srv = server_post(srv, "/data", fn(_req: Request) -> Response { response_ok("data") })
    srv = server_get(srv, "/users/:id", fn(req: Request) -> Response {
        let id = req_path_param(req, "id")
        response_ok("user: {id}")
    })

    let r1 = match_route(srv, "GET", "/hello")
    assert(r1.index >= 0)

    let r2 = match_route(srv, "POST", "/data")
    assert(r2.index >= 0)

    let r3 = match_route(srv, "GET", "/users/42")
    assert(r3.index >= 0)
    if r3.index >= 0 {
        assert_eq(r3.param_names.len(), 1)
        assert_eq(r3.param_names.get(0).unwrap(), "id")
        assert_eq(r3.param_values.get(0).unwrap(), "42")
    }

    let r4 = match_route(srv, "DELETE", "/hello")
    assert(r4.index < 0)
}

test "match result params populated on request" {
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/users/:id/posts/:post_id", fn(req: Request) -> Response {
        let uid = req_path_param(req, "id")
        let pid = req_path_param(req, "post_id")
        response_ok("{uid}:{pid}")
    })

    let result = match_route(srv, "GET", "/users/7/posts/99")
    assert(result.index >= 0)
    assert_eq(result.param_names.get(0).unwrap(), "id")
    assert_eq(result.param_values.get(0).unwrap(), "7")
    assert_eq(result.param_names.get(1).unwrap(), "post_id")
    assert_eq(result.param_values.get(1).unwrap(), "99")

    let base = request_new("GET", "/users/7/posts/99")
    let req = Request { method: base.method, url: base.url, body: base.body, headers: base.headers, param_names: result.param_names, param_values: result.param_values, timeout_ms: base.timeout_ms }
    let route = srv.routes.get(result.index).unwrap()
    let resp = route.callback(req)
    assert_eq(resp.body, "7:99")
}

test "parse_pattern splits segments correctly" {
    let segs = parse_pattern("/users/:id/posts/:post_id")
    assert_eq(segs.len(), 4)

    let empty = parse_pattern("/")
    assert_eq(empty.len(), 0)

    let single = parse_pattern("/hello")
    assert_eq(single.len(), 1)
}

test "route stores pre-split segments" {
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/users/:id", fn(_req: Request) -> Response {
        response_ok("ok")
    })
    let route = srv.routes.get(0).unwrap()
    assert_eq(route.segments.len(), 2)
    assert_eq(route.pattern, "/users/:id")
}

test "req_path_param returns empty for missing param" {
    let req = request_new("GET", "/test")
    assert_eq(req_path_param(req, "nope"), "")
}

test "http parsing" {
    let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req = parse_request(raw)
    assert_eq(req.method, "GET")
    assert_eq(req.url, "/hello")
}

test "response formatting" {
    let resp = response_ok("hello")
    let text = format_response(resp)
    assert(text.contains("200"))
    assert(text.contains("hello"))
}
