@tags(unit)
test "tagged unit test" {
    assert_eq(1 + 1, 2)
}

@tags(unit)
test "another unit test" {
    assert(42 > 0)
}

@tags(slow)
test "tagged slow test" {
    assert_eq(100 * 100, 10000)
}

@tags(unit, integration)
test "multi-tagged test" {
    assert_ne("foo", "bar")
}

test "untagged test" {
    assert(1 == 1)
}
