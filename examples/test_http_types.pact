import std.http_types
import std.http_error

fn main() {
    let mut pass = true

    let req = request_new("GET", "https://example.com/api")
    if req.method != "GET" {
        io.println("FAIL: request method")
        pass = false
    }
    if req.url != "https://example.com/api" {
        io.println("FAIL: request url")
        pass = false
    }
    if req.body != "" {
        io.println("FAIL: request body should be empty")
        pass = false
    }
    if req.timeout_ms != 30000 {
        io.println("FAIL: request timeout_ms")
        pass = false
    }

    let req2 = request_with_body(req, "hello world")
    if req2.body != "hello world" {
        io.println("FAIL: request_with_body")
        pass = false
    }
    if req2.method != "GET" {
        io.println("FAIL: request_with_body preserved method")
        pass = false
    }

    let req3 = request_with_header(req2, "Content-Type", "application/json")
    if req3.headers.has("Content-Type") != 1 {
        io.println("FAIL: request_with_header")
        pass = false
    }
    let ct_val = req3.headers.unsafe_get("Content-Type")
    if ct_val != "application/json" {
        io.println("FAIL: request_with_header value")
        pass = false
    }

    let req4 = request_with_timeout(req, 5000)
    if req4.timeout_ms != 5000 {
        io.println("FAIL: request_with_timeout")
        pass = false
    }

    let resp = response_new(200, "hello")
    if resp.status != 200 {
        io.println("FAIL: response status")
        pass = false
    }
    if resp.body != "hello" {
        io.println("FAIL: response body")
        pass = false
    }

    if response_is_ok(resp) != true {
        io.println("FAIL: response_is_ok for 200")
        pass = false
    }

    let resp404 = response_not_found("not here")
    if resp404.status != 404 {
        io.println("FAIL: response_not_found status")
        pass = false
    }
    if response_is_ok(resp404) != false {
        io.println("FAIL: response_is_ok for 404")
        pass = false
    }

    let resp400 = response_bad_request("bad input")
    if resp400.status != 400 {
        io.println("FAIL: response_bad_request status")
        pass = false
    }

    let resp500 = response_internal_error("oops")
    if resp500.status != 500 {
        io.println("FAIL: response_internal_error status")
        pass = false
    }

    let resp_ok = response_ok("all good")
    if resp_ok.status != 200 {
        io.println("FAIL: response_ok status")
        pass = false
    }
    if resp_ok.body != "all good" {
        io.println("FAIL: response_ok body")
        pass = false
    }

    let resp_json = response_json("ok-json")
    if resp_json.status != 200 {
        io.println("FAIL: response_json status")
        pass = false
    }
    let json_ct = resp_json.headers.unsafe_get("Content-Type")
    if json_ct != "application/json" {
        io.println("FAIL: response_json content-type")
        pass = false
    }

    if status_reason(200) != "OK" {
        io.println("FAIL: status_reason 200")
        pass = false
    }
    if status_reason(404) != "Not Found" {
        io.println("FAIL: status_reason 404")
        pass = false
    }
    if status_reason(500) != "Internal Server Error" {
        io.println("FAIL: status_reason 500")
        pass = false
    }
    if status_reason(999) != "Unknown" {
        io.println("FAIL: status_reason unknown")
        pass = false
    }

    let err1 = NetError.Timeout("request timed out")
    let d1 = net_error_display(err1)
    if d1 != "timeout: request timed out" {
        io.println("FAIL: net_error_display Timeout: {d1}")
        pass = false
    }

    let err2 = NetError.ConnectionRefused("port closed")
    let d2 = net_error_display(err2)
    if d2 != "connection_refused: port closed" {
        io.println("FAIL: net_error_display ConnectionRefused: {d2}")
        pass = false
    }

    let err3 = NetError.DnsFailure("no such host")
    let d3 = net_error_display(err3)
    if d3 != "dns_failure: no such host" {
        io.println("FAIL: net_error_display DnsFailure: {d3}")
        pass = false
    }

    let err4 = NetError.TlsError("cert expired")
    let d4 = net_error_display(err4)
    if d4 != "tls: cert expired" {
        io.println("FAIL: net_error_display TlsError: {d4}")
        pass = false
    }

    let err5 = NetError.InvalidUrl("missing scheme")
    let d5 = net_error_display(err5)
    if d5 != "invalid_url: missing scheme" {
        io.println("FAIL: net_error_display InvalidUrl: {d5}")
        pass = false
    }

    if pass {
        io.println("all tests passed")
    } else {
        io.println("SOME TESTS FAILED")
    }
}
