type Point { x: Int, y: Int }

test "single capture" {
    let multiplier = 10
    let h = async.spawn(fn() {
        5 * multiplier
    })
    let result = h.await
    assert_eq(result, 50)
}

test "multiple captures" {
    let base = 100
    let offset = 42
    let h2 = async.spawn(fn() {
        base + offset
    })
    let r2 = h2.await
    assert_eq(r2, 142)
}

test "struct capture in spawn" {
    let p = Point { x: 3, y: 4 }
    let _h = async.spawn(fn() -> Int {
        p.x + p.y
    })
    assert_eq(_h.await, 7)
}
