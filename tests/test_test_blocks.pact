test "basic math" {
    let x = 1 + 2
    assert(x == 3)
    assert_eq(x, 3)
}

test "string equality" {
    let s = "hello"
    assert_eq(s, "hello")
    assert_ne(s, "world")
}
