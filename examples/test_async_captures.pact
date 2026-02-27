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
