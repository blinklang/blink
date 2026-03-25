import std.str

test "new creates empty builder" {
    let sb = StringBuilder.new()
    assert_eq(sb.len(), 0)
    assert(sb.is_empty())
    assert_eq(sb.to_str(), "")
}

test "write appends strings" {
    let mut sb = StringBuilder.new()
    sb.write("hello")
    sb.write(" ")
    sb.write("world")
    assert_eq(sb.to_str(), "hello world")
    assert_eq(sb.len(), 11)
}

test "with_capacity pre-allocates" {
    let sb = StringBuilder.with_capacity(100)
    assert(sb.capacity() >= 100)
    assert_eq(sb.len(), 0)
    assert(sb.is_empty())
}

test "write_char appends character" {
    let mut sb = StringBuilder.new()
    sb.write_char("H")
    sb.write_char("i")
    assert_eq(sb.to_str(), "Hi")
}

test "clear resets content but retains capacity" {
    let mut sb = StringBuilder.with_capacity(50)
    sb.write("test data")
    let cap_before = sb.capacity()
    sb.clear()
    assert_eq(sb.len(), 0)
    assert(sb.is_empty())
    assert_eq(sb.to_str(), "")
    assert(sb.capacity() >= cap_before)
}

test "to_str returns independent copies" {
    let mut sb = StringBuilder.new()
    sb.write("hello")
    let s1 = sb.to_str()
    sb.write(" world")
    let s2 = sb.to_str()
    assert_eq(s1, "hello")
    assert_eq(s2, "hello world")
}

test "interpolation optimization in write" {
    let x = 42
    let y = "world"
    let mut sb = StringBuilder.new()
    sb.write("{x}: {y}")
    assert_eq(sb.to_str(), "42: world")
}

test "loop building" {
    let mut sb = StringBuilder.new()
    let mut i = 0
    while i < 100 {
        sb.write("x")
        i = i + 1
    }
    assert_eq(sb.len(), 100)
}

test "with_capacity then write" {
    let mut sb = StringBuilder.with_capacity(256)
    sb.write("hello")
    assert_eq(sb.to_str(), "hello")
    assert(sb.capacity() >= 256)
}

test "bare constructor" {
    let sb = StringBuilder()
    assert_eq(sb.len(), 0)
    assert_eq(sb.to_str(), "")
}

test "bare constructor with capacity" {
    let sb = StringBuilder(200)
    assert(sb.capacity() >= 200)
}
