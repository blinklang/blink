test "map.get in closure preserves string type" {
    let m: Map[Str, Str] = Map()
    m.set("key", "hello")
    let get_val = fn() -> Str {
        m.get("key")
    }
    assert_eq(get_val(), "hello")
}

test "map.set and get in closure" {
    let m: Map[Str, Str] = Map()
    let setter = fn() {
        m.set("x", "world")
    }
    setter()
    assert_eq(m.get("x"), "world")
}

test "map.get closure with multiple keys" {
    let m: Map[Str, Str] = Map()
    m.set("a", "alpha")
    m.set("b", "beta")
    let lookup = fn(key: Str) -> Str {
        m.get(key)
    }
    assert_eq(lookup("a"), "alpha")
    assert_eq(lookup("b"), "beta")
}
