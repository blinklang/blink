fn apply(f: fn(Int) -> Int, x: Int) -> Int {
    f(x)
}

test "apply named closure" {
    let add_one = fn(x: Int) -> Int { x + 1 }
    assert_eq(apply(add_one, 5), 6)
}

test "apply inline closure" {
    let result = apply(fn(x: Int) -> Int { x * 3 }, 4)
    assert_eq(result, 12)
}
