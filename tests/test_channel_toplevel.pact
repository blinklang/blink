pub let ch = Channel(10)

test "top-level channel init" {
    ch.send(99)
    let v = ch.recv()
    assert_eq(v, 99)
}

test "top-level channel multiple sends" {
    ch.send(1)
    ch.send(2)
    ch.send(3)
    assert_eq(ch.recv(), 1)
    assert_eq(ch.recv(), 2)
    assert_eq(ch.recv(), 3)
}
