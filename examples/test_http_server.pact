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
    srv = server_get(srv, "/hello", fn(req: Request) -> Response {
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
    srv = server_get(srv, "/hello", fn(req: Request) -> Response {
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
    srv = server_get(srv, "/hello", fn(req: Request) -> Response { response_ok("hello") })
    srv = server_post(srv, "/data", fn(req: Request) -> Response { response_ok("data") })
    srv = server_get(srv, "/users/:id", fn(req: Request) -> Response {
        let id = path_param("id")
        response_ok("user: {id}")
    })

    let idx1 = match_route(srv, "GET", "/hello")
    assert(idx1 >= 0)

    let idx2 = match_route(srv, "POST", "/data")
    assert(idx2 >= 0)

    let idx3 = match_route(srv, "GET", "/users/42")
    assert(idx3 >= 0)
    if idx3 >= 0 {
        assert_eq(path_param("id"), "42")
    }

    let idx4 = match_route(srv, "DELETE", "/hello")
    assert(idx4 < 0)
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
