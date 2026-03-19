import std.http_types
import std.net_error
import std.net_tcp

fn hex_char_val(c: Int) -> Int {
    if c >= 48 && c <= 57 { return c - 48 }
    if c >= 97 && c <= 102 { return c - 87 }
    if c >= 65 && c <= 70 { return c - 55 }
    -1
}

fn parse_hex(s: Str) -> Int {
    let slen = s.len()
    let mut result = 0
    let mut i = 0
    while i < slen {
        let v = hex_char_val(s.char_at(i))
        if v < 0 { break }
        result = result * 16 + v
        i = i + 1
    }
    result
}

pub fn parse_url(url: Str) -> Result[UrlParts, NetError] {
    let mut p = url
    let scheme = "http"
    if p.starts_with("https://") {
        return Err(NetError.TlsError("HTTPS not supported"))
    }
    if p.starts_with("http://") {
        p = p.slice(7, p.len())
    }
    let slash_idx = p.index_of("/")
    let mut host_port = p
    let mut path = "/"
    if slash_idx >= 0 {
        host_port = p.slice(0, slash_idx)
        path = p.slice(slash_idx, p.len())
    }
    let colon_idx = host_port.index_of(":")
    let mut host = host_port
    let mut port = 80
    if colon_idx >= 0 {
        host = host_port.slice(0, colon_idx)
        let port_str = host_port.slice(colon_idx + 1, host_port.len())
        port = port_str.to_int()
    }
    if host.is_empty() {
        return Err(NetError.InvalidUrl("empty host"))
    }
    Ok(UrlParts { scheme: scheme, host: host, port: port, path: path })
}

pub fn format_request(req: Request, host: Str, path: Str) -> Str {
    let sb = StringBuilder.new()
    sb.write(req.method)
    sb.write(" ")
    sb.write(path)
    sb.write(" HTTP/1.1\r\nHost: ")
    sb.write(host)
    sb.write("\r\n")
    let mut has_content_length = false
    let mut has_connection = false
    let keys = req.headers.keys()
    let mut i = 0
    while i < keys.len() {
        let k = keys.get(i).unwrap()
        let v = req.headers.get(k).unwrap()
        sb.write(k)
        sb.write(": ")
        sb.write(v)
        sb.write("\r\n")
        let kl = k.to_lower()
        if kl == "content-length" {
            has_content_length = true
        }
        if kl == "connection" {
            has_connection = true
        }
        i = i + 1
    }
    if req.body.len() > 0 && !has_content_length {
        sb.write("Content-Length: ")
        sb.write_int(req.body.len())
        sb.write("\r\n")
    }
    if !has_connection {
        sb.write("Connection: close\r\n")
    }
    sb.write("\r\n")
    if req.body.len() > 0 {
        sb.write(req.body)
    }
    sb.to_str()
}

fn decode_chunked(raw: Str) -> Str {
    let sb = StringBuilder.new()
    let rlen = raw.len()
    let mut cursor = 0
    while cursor < rlen {
        let crlf_idx = raw.slice(cursor, rlen).index_of("\r\n")
        if crlf_idx < 0 { break }
        let size_str = raw.slice(cursor, cursor + crlf_idx).trim()
        let chunk_size = parse_hex(size_str)
        if chunk_size <= 0 { break }
        let data_start = cursor + crlf_idx + 2
        let data_end = data_start + chunk_size
        if data_end > rlen {
            sb.write(raw.slice(data_start, rlen))
            break
        }
        sb.write(raw.slice(data_start, data_end))
        cursor = data_end
        if cursor + 2 <= rlen && raw.char_at(cursor) == 13 && raw.char_at(cursor + 1) == 10 {
            cursor = cursor + 2
        }
    }
    sb.to_str()
}

pub fn parse_response(raw: Str) -> Result[Response, NetError] {
    let hdr_end_idx = raw.index_of("\r\n\r\n")
    if hdr_end_idx < 0 {
        return Err(NetError.ProtocolError("malformed HTTP response"))
    }
    let header_section = raw.slice(0, hdr_end_idx)
    let body_start = hdr_end_idx + 4
    let body_raw = raw.slice(body_start, raw.len())

    let first_crlf = header_section.index_of("\r\n")
    let status_line = header_section.slice(0, if first_crlf >= 0 { first_crlf } else { header_section.len() })

    let mut status_code = 0
    if status_line.len() > 12 && status_line.starts_with("HTTP/") {
        let space_idx = status_line.index_of(" ")
        if space_idx >= 0 {
            let after_space = status_line.slice(space_idx + 1, status_line.len())
            let space2 = after_space.index_of(" ")
            let code_str = if space2 >= 0 { after_space.slice(0, space2) } else { after_space }
            status_code = code_str.to_int()
        }
    }

    let hdrs: Map[Str, Str] = Map()
    if first_crlf >= 0 && first_crlf < hdr_end_idx {
        let hdr_lines_str = header_section.slice(first_crlf + 2, header_section.len())
        let hdr_lines = hdr_lines_str.split("\r\n")
        let mut i = 0
        while i < hdr_lines.len() {
            let line = hdr_lines.get(i).unwrap()
            let colon_idx = line.index_of(":")
            if colon_idx > 0 {
                let key = line.slice(0, colon_idx).to_lower()
                let mut val = line.slice(colon_idx + 1, line.len())
                if val.len() > 0 && val.char_at(0) == 32 {
                    val = val.slice(1, val.len())
                }
                hdrs.set(key, val)
            }
            i = i + 1
        }
    }

    let mut body = body_raw
    let te = hdrs.get("transfer-encoding")
    if te != "" && te.contains("chunked") {
        body = decode_chunked(body_raw)
    }

    Ok(Response { status: status_code, body: body, headers: hdrs })
}

pub fn http_do_request(req: Request) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let url_result = parse_url(req.url)
    if url_result.is_err() {
        return Err(url_result.unwrap_err())
    }
    let parts = url_result.unwrap()

    let connect_result = tcp_connect(parts.host, parts.port)
    if connect_result.is_err() {
        return Err(connect_result.unwrap_err())
    }
    let sock = connect_result.unwrap()

    if req.timeout_ms > 0 {
        sock.set_timeout(req.timeout_ms)
    }

    let request_str = format_request(req, parts.host, parts.path)
    sock.write(request_str)

    let raw = sock.read_all()
    sock.close()

    if raw.is_empty() {
        return Err(NetError.ProtocolError("empty response"))
    }

    parse_response(raw)
}

/// Make a GET request
pub fn get(url: Str) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let req = request_new("GET", url)
    http_do_request(req)
}

/// Make a POST request with body
pub fn post(url: Str, body: Str) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let req = request_new("POST", url)
    let req2 = request_with_body(req, body)
    http_do_request(req2)
}

/// Make a PUT request with body
pub fn put(url: Str, body: Str) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let req = request_new("PUT", url)
    let req2 = request_with_body(req, body)
    http_do_request(req2)
}

/// Make a DELETE request
pub fn delete(url: Str) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let req = request_new("DELETE", url)
    http_do_request(req)
}

/// Make a HEAD request
pub fn head(url: Str) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    let req = request_new("HEAD", url)
    http_do_request(req)
}

/// Make an HTTP request from a Request struct
pub fn request(req: Request) -> Result[Response, NetError] ! Net.Connect, Net.DNS {
    http_do_request(req)
}
