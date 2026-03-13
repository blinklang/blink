@requires(x > 0)
fn positive_double(x: Int) -> Int {
    x * 2
}

@requires(a >= 0)
@requires(b >= 0)
fn safe_add(a: Int, b: Int) -> Int {
    a + b
}

test "requires passes with valid args" {
    assert_eq(positive_double(5), 10)
    assert_eq(positive_double(1), 2)
}

test "multiple requires pass" {
    assert_eq(safe_add(3, 4), 7)
    assert_eq(safe_add(0, 0), 0)
}
