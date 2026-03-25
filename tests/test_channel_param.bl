fn process_channel(ch: Channel) {
    ch.send(42)
}

fn relay(src: Channel, dst: Channel) {
    let val = src.recv()
    dst.send(val)
}

test "channel as function parameter" {
    let ch = Channel(10)
    process_channel(ch)
    let val = ch.recv()
    assert_eq(val, 42)
}

test "channel passed to relay function" {
    let a = Channel(10)
    let b = Channel(10)
    a.send(99)
    relay(a, b)
    assert_eq(b.recv(), 99)
}
