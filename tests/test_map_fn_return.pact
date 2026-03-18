fn make_str_map() -> Map[Str, Str] {
    let m: Map[Str, Str] = Map()
    m.set("hello", "world")
    m
}

test "map get from fn return" {
    let m = make_str_map()
    assert_eq(m.get("hello"), "world")
}
