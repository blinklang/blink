import std.net

test "TcpSocket struct construction" {
    let sock = TcpSocket { fd: 42 }
    assert_eq(sock.fd, 42)
}

test "TcpListener struct construction" {
    let listener = TcpListener { fd: 99 }
    assert_eq(listener.fd, 99)
}

test "TcpSocket close on invalid fd" {
    let sock = TcpSocket { fd: -1 }
    sock.close()
}

test "TcpListener close on invalid fd" {
    let listener = TcpListener { fd: -1 }
    listener.close()
}

test "tcp_connect returns TcpSocket in Result" {
    let result = tcp_connect("192.0.2.1", 1)
    assert(result.is_err())
}

test "tcp_listen returns TcpListener" {
    let result = tcp_listen("127.0.0.1", 0)
    if result.is_ok() {
        let listener = result.unwrap()
        assert(listener.fd >= 0)
        listener.close()
    }
}

test "listener_accept on invalid fd returns error" {
    let listener = TcpListener { fd: -1 }
    let accept_result = listener_accept(listener)
    assert(accept_result.is_err())
}
