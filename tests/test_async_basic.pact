fn compute(n: Int) -> Int {
    let mut sum = 0
    let mut i = 0
    while i < n {
        sum = sum + i
        i = i + 1
    }
    sum
}

test "fork-join two tasks" {
    async.scope {
        let h1 = async.spawn(fn() {
            compute(100)
        })
        let h2 = async.spawn(fn() {
            compute(50)
        })
        let r1 = h1.await
        let r2 = h2.await
        assert_eq(r1, 4950)
        assert_eq(r2, 1225)
    }
}

test "fork-join three tasks combined" {
    let total = async.scope {
        let ha = async.spawn(fn() {
            10 + 20
        })
        let hb = async.spawn(fn() {
            30 + 40
        })
        let hc = async.spawn(fn() {
            50 + 60
        })
        let ra = ha.await
        let rb = hb.await
        let rc = hc.await
        ra + rb + rc
    }
    assert_eq(total, 210)
}

test "scope returns value" {
    let scoped = async.scope {
        let hv = async.spawn(fn() {
            7 * 6
        })
        hv.await
    }
    assert_eq(scoped, 42)
}

test "fork-join with captures" {
    let base = 1000
    let offset = 337
    async.scope {
        let hx = async.spawn(fn() {
            base + offset
        })
        let hy = async.spawn(fn() {
            base - offset
        })
        let rx = hx.await
        let ry = hy.await
        assert_eq(rx, 1337)
        assert_eq(ry, 663)
    }
}
