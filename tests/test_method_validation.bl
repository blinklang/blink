test "string methods" {
    let s = "hello"
    assert_eq(s.len(), 5)
    assert(s.contains("ell"))
}

test "list methods" {
    let parts: List[Str] = []
    parts.push("a")
    parts.push("b")
    assert_eq(parts.len(), 2)
    assert_eq(parts.get(0).unwrap(), "a")
}

test "map methods" {
    let m = Map()
    m.set("key", "val")
    assert(m.has("key"))
    assert_eq(m.len(), 1)
}
