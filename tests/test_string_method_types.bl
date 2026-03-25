test "lines returns list" {
    let result: List[Str] = "a\nb\nc".lines()
    assert_eq(result.len(), 3)
}

test "parse_float returns float" {
    let f: Float = "3.14".parse_float()
    assert(f > 3.0)
}

test "parse_int returns int" {
    let n: Int = "42".parse_int()
    assert_eq(n, 42)
}

test "is_empty returns bool" {
    let b: Bool = "".is_empty()
    assert(b)
}
