// http_server.pact — HTTP server with struct types + closure handlers

import std.http_types

// ── Route, Hook, and Server types ───────────────────────────────────

pub type Route {
    method: Str
    pattern: Str
    callback: fn(Request) -> Response
}

pub type Hook {
    name: Str
    process: fn(Request) -> Request
}

pub type ErrorHandler {
    on_error: fn(Request, Str) -> Response
}

pub type Server {
    host: Str
    port: Int
    routes: List[Route]
    before_hooks: List[Hook]
    error_handler: ErrorHandler
}

// ── Path param storage (per-request, reset each match) ──────────────

pub let mut param_names: List[Str] = []
pub let mut param_values: List[Str] = []

// ── Server API ──────────────────────────────────────────────────────

pub fn server_new(host: Str, port: Int) -> Server {
    let routes: List[Route] = []
    let hooks: List[Hook] = []
    let err_handler = ErrorHandler {
        on_error: fn(req: Request, msg: Str) -> Response {
            response_internal_error("Internal Server Error: {msg}")
        }
    }
    Server { host: host, port: port, routes: routes, before_hooks: hooks, error_handler: err_handler }
}

pub fn server_route(srv: Server, method: Str, pattern: Str, cb: fn(Request) -> Response) -> Server {
    let r = Route { method: method, pattern: pattern, callback: cb }
    srv.routes.push(r)
    srv
}

pub fn server_get(srv: Server, pattern: Str, cb: fn(Request) -> Response) -> Server {
    server_route(srv, "GET", pattern, cb)
}

pub fn server_post(srv: Server, pattern: Str, cb: fn(Request) -> Response) -> Server {
    server_route(srv, "POST", pattern, cb)
}

pub fn server_put(srv: Server, pattern: Str, cb: fn(Request) -> Response) -> Server {
    server_route(srv, "PUT", pattern, cb)
}

pub fn server_delete(srv: Server, pattern: Str, cb: fn(Request) -> Response) -> Server {
    server_route(srv, "DELETE", pattern, cb)
}

// ── Middleware API ──────────────────────────────────────────────────

pub fn server_use(srv: Server, name: Str, hook: fn(Request) -> Request) -> Server {
    let h = Hook { name: name, process: hook }
    srv.before_hooks.push(h)
    srv
}

pub fn server_on_error(srv: Server, err_fn: fn(Request, Str) -> Response) -> Server {
    let eh = ErrorHandler { on_error: err_fn }
    Server { host: srv.host, port: srv.port, routes: srv.routes, before_hooks: srv.before_hooks, error_handler: eh }
}

// ── Route matching ──────────────────────────────────────────────────

pub fn match_route(srv: Server, method: Str, path: Str) -> Int {
    path_param_clear()
    let mut i = 0
    while i < srv.routes.len() {
        let route = srv.routes.get(i)
        if route.method == method {
            if path_match(route.pattern, path) == 1 {
                return i
            }
            path_param_clear()
        }
        i = i + 1
    }
    -1
}

pub fn path_match(pattern: Str, path: Str) -> Int {
    let pat_parts = split_path(pattern)
    let path_parts = split_path(path)
    if pat_parts.len() != path_parts.len() {
        return 0
    }
    let mut i = 0
    while i < pat_parts.len() {
        let pat_seg = pat_parts.get(i)
        let path_seg = path_parts.get(i)
        if pat_seg.len() > 0 && pat_seg.char_at(0) == 58 {
            // ':' = 58 — path parameter
            let pname = pat_seg.substring(1, pat_seg.len() - 1)
            param_names.push(pname)
            param_values.push(path_seg)
        } else if pat_seg != path_seg {
            return 0
        }
        i = i + 1
    }
    1
}

pub fn path_param(name: Str) -> Str {
    let mut i = 0
    while i < param_names.len() {
        if param_names.get(i) == name {
            return param_values.get(i)
        }
        i = i + 1
    }
    ""
}

pub fn path_param_clear() {
    param_names = []
    param_values = []
}

// ── HTTP parsing ────────────────────────────────────────────────────

pub fn parse_request(raw: Str) -> Request {
    // Parse "METHOD URL HTTP/1.1\r\n..."
    let mut method = ""
    let mut url = ""
    let mut body = ""
    let mut i = 0

    // Extract method (up to first space)
    while i < raw.len() && raw.char_at(i) != 32 {
        i = i + 1
    }
    method = raw.substring(0, i)

    // Skip space
    i = i + 1

    // Extract URL (up to next space)
    let url_start = i
    while i < raw.len() && raw.char_at(i) != 32 {
        i = i + 1
    }
    url = raw.substring(url_start, i - url_start)

    // Skip to end of request line (find \r\n)
    while i < raw.len() - 1 {
        if raw.char_at(i) == 13 && raw.char_at(i + 1) == 10 {
            i = i + 2
            // Now skip headers until we find \r\n\r\n
            while i < raw.len() - 3 {
                if raw.char_at(i) == 13 && raw.char_at(i + 1) == 10 && raw.char_at(i + 2) == 13 && raw.char_at(i + 3) == 10 {
                    // Body starts after \r\n\r\n
                    let body_start = i + 4
                    if body_start < raw.len() {
                        body = raw.substring(body_start, raw.len() - body_start)
                    }
                    return request_new_with_body(method, url, body)
                }
                i = i + 1
            }
            return request_new_with_body(method, url, "")
        }
        i = i + 1
    }

    request_new_with_body(method, url, body)
}

fn request_new_with_body(method: Str, url: Str, body: Str) -> Request {
    let hdrs: Map[Str, Str] = Map()
    Request { method: method, url: url, body: body, headers: hdrs, timeout_ms: 0 }
}

// ── HTTP response formatting ────────────────────────────────────────

pub fn format_response(resp: Response) -> Str {
    let reason = status_reason(resp.status)
    let status_str = resp.status.to_string()
    let body_len = resp.body.len().to_string()
    let mut result = "HTTP/1.1 {status_str} {reason}\r\nContent-Length: {body_len}\r\nConnection: close\r\n\r\n{resp.body}"
    result
}

// ── Server loop ─────────────────────────────────────────────────────

pub fn server_serve(srv: Server) ! Net.Listen, IO {
    let fd = net.listen(srv.host, srv.port)
    if fd < 0 {
        io.eprintln("Failed to listen on {srv.host}:{srv.port.to_string()}")
        return
    }
    io.println("Listening on {srv.host}:{srv.port.to_string()}")

    while 1 == 1 {
        let conn = net.accept(fd)
        if conn < 0 {
            io.eprintln("Accept failed")
            // continue accepting
        } else {
            let raw = net.read(conn, 8192)
            if raw.len() > 0 {
                let mut req = parse_request(raw)

                // Apply before hooks
                let mut hi = 0
                while hi < srv.before_hooks.len() {
                    let hook = srv.before_hooks.get(hi)
                    req = hook.process(req)
                    hi = hi + 1
                }

                // Match and dispatch
                let idx = match_route(srv, req.method, req.url)
                let mut resp = response_not_found("Not Found")
                if idx >= 0 {
                    let matched_route = srv.routes.get(idx)
                    resp = matched_route.callback(req)
                }

                // Error recovery: invalid response status triggers error handler
                if resp.status <= 0 {
                    resp = srv.error_handler.on_error(req, "handler returned invalid response")
                }

                let text = format_response(resp)
                net.write(conn, text)
            }
            net.close(conn)
        }
    }
}

// ── Helpers ─────────────────────────────────────────────────────────

fn split_path(path: Str) -> List[Str] {
    let mut parts: List[Str] = []
    let mut current = ""
    let mut i = 0
    while i < path.len() {
        if path.char_at(i) == 47 {
            // '/' = 47
            if current.len() > 0 {
                parts.push(current)
                current = ""
            }
        } else {
            current = current.concat(path.substring(i, 1))
        }
        i = i + 1
    }
    if current.len() > 0 {
        parts.push(current)
    }
    parts
}
