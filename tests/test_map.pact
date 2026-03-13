test "basic map operations" {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("b", 2)
    m.set("c", 3)

    assert_eq(m.len(), 3)
    assert_eq(m.get("a"), 1)
    assert_eq(m.get("b"), 2)
    assert_eq(m.has("a"), true)
    assert_eq(m.has("z"), false)
}

test "update existing key" {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("a", 42)
    assert_eq(m.get("a"), 42)
}

test "remove key" {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("b", 2)
    m.set("c", 3)
    m.remove("b")
    assert_eq(m.len(), 2)
    assert_eq(m.has("b"), false)
}

test "keys and values" {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("c", 3)
    assert_eq(m.keys().len(), 2)
    assert_eq(m.values().len(), 2)
}

test "string value map" {
    let m2: Map[Str, Str] = Map()
    m2.set("hello", "world")
    m2.set("foo", "bar")
    assert_eq(m2.get("hello"), "world")
    assert_eq(m2.len(), 2)
}
