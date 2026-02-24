import std.http_types
import std.http_server

fn check(cond: Int, label: Str) {
    if cond != 0 {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label}")
    }
}

fn test_server_construction() {
    io.println("--- server construction ---")
    let srv = server_new("127.0.0.1", 8080)
    check(srv.host == "127.0.0.1", "host set")
    check(srv.port == 8080, "port set")
    check(srv.routes.len() == 0, "no routes initially")
    check(srv.before_hooks.len() == 0, "no hooks initially")
}

fn test_route_registration() {
    io.println("--- route registration ---")
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(req: Request) -> Response {
        response_ok("hello world")
    })
    srv = server_post(srv, "/echo", fn(req: Request) -> Response {
        response_ok(req.body)
    })
    check(srv.routes.len() == 2, "2 routes registered")

    let r0 = srv.routes.get(0)
    check(r0.method == "GET", "route 0 method")
    check(r0.pattern == "/hello", "route 0 pattern")

    let r1 = srv.routes.get(1)
    check(r1.method == "POST", "route 1 method")
    check(r1.pattern == "/echo", "route 1 pattern")
}

fn test_handler_dispatch() {
    io.println("--- handler dispatch ---")
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(req: Request) -> Response {
        response_ok("hello from handler")
    })

    let route = srv.routes.get(0)
    let req = request_new("GET", "/hello")
    let resp = route.callback(req)
    check(resp.status == 200, "handler returned 200")
    check(resp.body == "hello from handler", "handler body correct")
}

fn test_route_matching() {
    io.println("--- route matching ---")
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_get(srv, "/hello", fn(req: Request) -> Response { response_ok("hello") })
    srv = server_post(srv, "/data", fn(req: Request) -> Response { response_ok("data") })
    srv = server_get(srv, "/users/:id", fn(req: Request) -> Response {
        let id = path_param("id")
        response_ok("user: {id}")
    })

    let idx1 = match_route(srv, "GET", "/hello")
    check(idx1 >= 0, "matched GET /hello")

    let idx2 = match_route(srv, "POST", "/data")
    check(idx2 >= 0, "matched POST /data")

    let idx3 = match_route(srv, "GET", "/users/42")
    check(idx3 >= 0, "matched GET /users/:id")
    if idx3 >= 0 {
        check(path_param("id") == "42", "path param id=42")
    }

    let idx4 = match_route(srv, "DELETE", "/hello")
    check(idx4 < 0, "no match DELETE /hello")
}

fn test_http_parsing() {
    io.println("--- HTTP parsing ---")
    let raw = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let req = parse_request(raw)
    check(req.method == "GET", "parsed method")
    check(req.url == "/hello", "parsed url")
}

fn test_response_formatting() {
    io.println("--- response formatting ---")
    let resp = response_ok("hello")
    let text = format_response(resp)
    check(text.contains("200"), "contains status 200")
    check(text.contains("hello"), "contains body")
}

fn main() {
    io.println("=== HTTP server tests ===")
    test_server_construction()
    test_route_registration()
    test_handler_dispatch()
    test_route_matching()
    test_http_parsing()
    test_response_formatting()
    io.println("=== done ===")
}
