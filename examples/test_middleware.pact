import std.http_types
import std.http_server

fn check(cond: Int, label: Str) {
    if cond != 0 {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label}")
    }
}

fn test_before_hooks() {
    io.println("--- before hooks ---")
    let mut srv = server_new("127.0.0.1", 8080)

    srv = server_use(srv, "add-header", fn(r: Request) -> Request {
        request_with_header(r, "X-Processed", "true")
    })

    srv = server_get(srv, "/test", fn(r: Request) -> Response {
        response_ok("ok")
    })

    check(srv.before_hooks.len() == 1, "one hook registered")

    // Simulate the hook chain
    let mut req = request_new("GET", "/test")
    let mut hi = 0
    while hi < srv.before_hooks.len() {
        let hook = srv.before_hooks.get(hi)
        req = hook.process(req)
        hi = hi + 1
    }
    check(req.method == "GET", "method preserved through hook")
}

fn test_error_handler() {
    io.println("--- error handler ---")
    let mut srv = server_new("127.0.0.1", 8080)
    srv = server_on_error(srv, fn(r: Request, msg: Str) -> Response {
        Response { status: 500, body: "custom error: {msg}", headers: Map() }
    })

    let req = request_new("GET", "/fail")
    let resp = srv.error_handler.on_error(req, "something broke")
    check(resp.status == 500, "error handler status 500")
    check(resp.body == "custom error: something broke", "error handler body")
}

fn test_default_error_handler() {
    io.println("--- default error handler ---")
    let srv = server_new("127.0.0.1", 8080)

    let req = request_new("GET", "/fail")
    let resp = srv.error_handler.on_error(req, "oops")
    check(resp.status == 500, "default error handler status 500")
    check(resp.body == "Internal Server Error: oops", "default error handler body")
}

fn test_multiple_hooks() {
    io.println("--- multiple hooks ---")
    let mut srv = server_new("127.0.0.1", 8080)

    srv = server_use(srv, "hook-1", fn(req: Request) -> Request {
        request_with_header(req, "X-Hook-1", "yes")
    })
    srv = server_use(srv, "hook-2", fn(req: Request) -> Request {
        request_with_header(req, "X-Hook-2", "yes")
    })

    check(srv.before_hooks.len() == 2, "two hooks registered")

    let h0 = srv.before_hooks.get(0)
    check(h0.name == "hook-1", "first hook name")
    let h1 = srv.before_hooks.get(1)
    check(h1.name == "hook-2", "second hook name")
}

fn test_hook_chain_execution() {
    io.println("--- hook chain execution ---")
    let mut srv = server_new("127.0.0.1", 8080)

    srv = server_use(srv, "add-method-header", fn(r: Request) -> Request {
        request_with_header(r, "X-Method", r.method)
    })
    srv = server_use(srv, "add-url-header", fn(r: Request) -> Request {
        request_with_header(r, "X-Url", r.url)
    })

    let mut req = request_new("POST", "/data")
    let mut hi = 0
    while hi < srv.before_hooks.len() {
        let hook = srv.before_hooks.get(hi)
        req = hook.process(req)
        hi = hi + 1
    }

    check(req.method == "POST", "method preserved")
    check(req.url == "/data", "url preserved")
}

fn main() {
    io.println("=== middleware tests ===")
    test_before_hooks()
    test_error_handler()
    test_default_error_handler()
    test_multiple_hooks()
    test_hook_chain_execution()
    io.println("=== done ===")
}
