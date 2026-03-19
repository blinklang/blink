fn abs(n: Int) -> Int {
    if n < 0 { -n } else { n }
}

fn sign(n: Int) -> Int {
    if n > 0 { 1 }
    else if n < 0 { -1 }
    else { 0 }
}

fn max(a: Int, b: Int) -> Int {
    if a > b { a } else { b }
}

fn label(n: Int) -> Str {
    if n > 0 { "positive" } else { "non-positive" }
}

test "if-else expr returns value in tail position" {
    assert_eq(abs(-42), 42)
    assert_eq(abs(7), 7)
    assert_eq(abs(0), 0)
}

test "if-else-if chain as expr" {
    assert_eq(sign(5), 1)
    assert_eq(sign(-3), -1)
    assert_eq(sign(0), 0)
}

test "if-else expr with identifiers" {
    assert_eq(max(3, 7), 7)
    assert_eq(max(10, 2), 10)
}

test "if-else expr returning strings" {
    assert_eq(label(1), "positive")
    assert_eq(label(-1), "non-positive")
    assert_eq(label(0), "non-positive")
}
