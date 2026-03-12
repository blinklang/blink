// Manual test — run with: printf 'hello from stdin\nABCDE' | build/test_stdio_stdin

test "io.read_line reads from stdin" {
    let line = io.read_line()
    assert(line == "hello from stdin")
}

test "io.read_bytes reads exact count from stdin" {
    let data = io.read_bytes(5)
    assert(data.len() == 5)
    match data.to_str() {
        Ok(s) => assert_eq(s, "ABCDE")
        Err(_e) => assert(false)
    }
}
