test "basic send and recv" {
    let ch = Channel(10)
    ch.send(42)
    let val = ch.recv()
    assert_eq(val, 42)
}

test "FIFO order" {
    let ch = Channel(10)
    ch.send(1)
    ch.send(2)
    ch.send(3)
    let a = ch.recv()
    let b = ch.recv()
    let c = ch.recv()
    assert_eq(a, 1)
    assert_eq(b, 2)
    assert_eq(c, 3)
}

test "close channel" {
    let ch = Channel(10)
    ch.close()
    assert(true)
}

test "async producer consumer" {
    let ch2 = Channel(10)
    let h = async.spawn(fn() {
        ch2.send(100)
        ch2.send(200)
        ch2.close()
        0
    })
    let v1 = ch2.recv()
    let v2 = ch2.recv()
    h.await
    assert_eq(v1, 100)
    assert_eq(v2, 200)
}

test "for-in on channel" {
    let ch3 = Channel(10)
    ch3.send(10)
    ch3.send(20)
    ch3.send(30)
    ch3.close()
    let mut sum = 0
    for val in ch3 {
        sum = sum + val
    }
    assert_eq(sum, 60)
}
