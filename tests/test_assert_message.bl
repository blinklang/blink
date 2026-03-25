test "assert with true condition" {
    assert(true)
    assert(1 == 1)
}

test "assert_eq with ints" {
    assert_eq(1 + 2, 3)
    assert_eq(10 * 2, 20)
}

test "assert_ne with ints" {
    assert_ne(1, 2)
    assert_ne(0, -1)
}

test "assert_eq with strings" {
    assert_eq("same", "same")
    assert_eq("hello", "hello")
}

test "assert_ne with strings" {
    assert_ne("hello", "world")
    assert_ne("foo", "bar")
}

test "assert_eq with bools" {
    assert_eq(true, true)
    assert_eq(false, false)
}

test "assert_ne with bools" {
    assert_ne(true, false)
}

test "mixed assertions" {
    let x = 42
    let s = "pact"
    assert(x == 42)
    assert_eq(x, 42)
    assert_ne(x, 0)
    assert_eq(s, "pact")
    assert_ne(s, "rust")
}
