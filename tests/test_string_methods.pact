test "trim" {
    assert_eq("  hello world  ".trim(), "hello world")
    assert_eq("\n  indented  \n".trim(), "indented")
}

test "to_upper" {
    assert_eq("hello World 123".to_upper(), "HELLO WORLD 123")
}

test "to_lower" {
    assert_eq("HELLO World 123".to_lower(), "hello world 123")
}

test "replace" {
    assert_eq("foo bar foo baz".replace("foo", "qux"), "qux bar qux baz")
    assert_eq("hello".replace("xyz", "abc"), "hello")
}

test "index_of" {
    assert_eq("hello world".index_of("world"), 6)
    assert_eq("hello".index_of("xyz"), -1)
}

test "lines" {
    let parts = "line1\nline2\nline3".lines()
    assert_eq(parts.len(), 3)
    assert_eq(parts.get(0).unwrap(), "line1")
    assert_eq(parts.get(2).unwrap(), "line3")
}

test "is_empty" {
    assert("".is_empty())
    assert("x".is_empty() == false)
}

test "parse_float" {
    let f = "3.14".parse_float()
    assert(f < 3.15)
    assert(f > 3.13)
}

test "existing string methods" {
    assert_eq("hello".len(), 5)
    assert("hello world".contains("world"))
    assert("hello".starts_with("hel"))
    assert("hello".ends_with("llo"))
}
