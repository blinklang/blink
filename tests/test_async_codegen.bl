fn compute(n: Int) -> Int {
    let mut sum = 0
    let mut i = 0
    while i < n {
        sum = sum + i
        i = i + 1
    }
    sum
}

test "basic spawn and await" {
    let h1 = async.spawn(fn() {
        compute(100)
    })
    let result1 = h1.await
    assert_eq(result1, 4950)
}

test "multiple spawns" {
    let h2 = async.spawn(fn() {
        10 + 20
    })
    let h3 = async.spawn(fn() {
        100 + 200
    })
    let r2 = h2.await
    let r3 = h3.await
    assert_eq(r2, 30)
    assert_eq(r3, 300)
}

test "async scope" {
    let scoped = async.scope {
        let x = 5
        x * 10
    }
    assert_eq(scoped, 50)
}

fn do_nothing() {
    let _ = 1
}

test "void spawn" {
    let _h = async.spawn(fn() {
        do_nothing()
    })
    _h.await
}
