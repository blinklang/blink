test "closure parameter shadows outer variable" {
    let mut x = 10
    let f = fn(x: Int) -> Int { x + 1 }
    assert_eq(f(42), 43)
    assert_eq(x, 10)
    x = 20
    assert_eq(f(99), 100)
    assert_eq(x, 20)
}
