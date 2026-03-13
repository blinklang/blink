// test_net_listen.pact — TCP echo server test (manual testing)
//
// Run: bin/pact run tests/test_net_listen.pact
// Then connect: echo "hello" | nc localhost 9876
// Or: curl http://localhost:9876/
//
// The server accepts one connection, reads a line, echoes it back, and exits.

fn main() ! Net.Listen, IO {
    io.println("Starting TCP echo test on port 9876...")
    let fd = net.listen("0.0.0.0", 9876)
    if fd < 0 {
        io.println("FAIL: listen returned {fd}")
        return
    }
    io.println("PASS: listen returned fd {fd}")
    io.println("Waiting for connection (use: echo hello | nc localhost 9876)")

    let conn = net.accept(fd)
    if conn < 0 {
        io.println("FAIL: accept returned {conn}")
        return
    }
    io.println("PASS: accepted connection fd {conn}")

    let line = net.read_line(conn)
    io.println("PASS: read line: \"{line}\"")

    net.write_line(conn, "echo: {line}")
    io.println("PASS: wrote response")

    net.close(conn)
    net.close(fd)
    io.println("PASS: closed connections")
    io.println("All net_listen tests complete")
}
