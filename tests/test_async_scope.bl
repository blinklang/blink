fn compute(n: Int) -> Int {
    let mut sum = 0
    let mut i = 0
    while i < n {
        sum = sum + i
        i = i + 1
    }
    sum
}

test "scope with explicit awaits" {
    async.scope {
        let ha = async.spawn(fn() {
            compute(100)
        })
        let hb = async.spawn(fn() {
            compute(50)
        })
        let ra = ha.await
        let rb = hb.await
        assert_eq(ra, 4950)
        assert_eq(rb, 1225)
    }
}

test "un-awaited spawns auto-joined" {
    let mut flag = 0
    async.scope {
        let hc = async.spawn(fn() {
            compute(10)
        })
        let hd = async.spawn(fn() {
            compute(20)
        })
        flag = 1
    }
    assert_eq(flag, 1)
}

test "mixed awaited and un-awaited" {
    async.scope {
        let he = async.spawn(fn() {
            compute(100)
        })
        let re = he.await
        assert_eq(re, 4950)
        let hf = async.spawn(fn() {
            compute(50)
        })
    }
}

test "scope returns value" {
    let scoped_val = async.scope {
        let x = 42
        x + 8
    }
    assert_eq(scoped_val, 50)
}

test "nested scopes" {
    async.scope {
        let h_outer = async.spawn(fn() {
            10
        })
        async.scope {
            let h_inner = async.spawn(fn() {
                20
            })
            let r_inner = h_inner.await
            assert_eq(r_inner, 20)
        }
        let r_outer = h_outer.await
        assert_eq(r_outer, 10)
    }
}

test "scope with no spawns" {
    let simple_val = async.scope {
        let aa = 3
        let bb = 7
        aa * bb
    }
    assert_eq(simple_val, 21)
}
