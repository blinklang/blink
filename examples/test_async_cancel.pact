fn compute(n: Int) -> Int {
    let mut sum = 0
    let mut i = 0
    while i < n {
        sum = sum + i
        i = i + 1
    }
    sum
}

test "un-awaited spawns joined on scope exit" {
    let ch = Channel(10)
    async.scope {
        let h1 = async.spawn(fn() {
            ch.send(compute(10))
            0
        })
        let h2 = async.spawn(fn() {
            ch.send(compute(5))
            0
        })
    }
    let v1 = ch.recv()
    let v2 = ch.recv()
    let joined_sum = v1 + v2
    assert_eq(joined_sum, 55)
}

test "many un-awaited spawns" {
    let ch2 = Channel(20)
    async.scope {
        let a = async.spawn(fn() {
            ch2.send(1)
            0
        })
        let b = async.spawn(fn() {
            ch2.send(2)
            0
        })
        let c = async.spawn(fn() {
            ch2.send(3)
            0
        })
        let d = async.spawn(fn() {
            ch2.send(4)
            0
        })
    }
    ch2.close()
    let mut total = 0
    let mut n = 0
    for v in ch2 {
        total = total + v
        n = n + 1
    }
    assert_eq(n, 4)
    assert_eq(total, 10)
}

test "mixed awaited and un-awaited" {
    let ch3 = Channel(10)
    let awaited_val = async.scope {
        let h_awaited = async.spawn(fn() {
            42
        })
        let h_fire = async.spawn(fn() {
            ch3.send(99)
            0
        })
        h_awaited.await
    }
    let fire_val = ch3.recv()
    assert_eq(awaited_val, 42)
    assert_eq(fire_val, 99)
}
