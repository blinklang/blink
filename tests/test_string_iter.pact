test "string iteration" {
    let s = "hello"
    let chars: List[Str] = []
    for c in s {
        chars.push(c)
    }
    assert_eq(chars.len(), 5)
    assert_eq(chars.get(0).unwrap(), "h")
    assert_eq(chars.get(4).unwrap(), "o")
}
