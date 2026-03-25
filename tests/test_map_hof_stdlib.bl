test "map_for_each: iterate entries" {
    let m: Map[Str, Int] = Map()
    m.set("a", 10)
    m.set("b", 20)
    let mut total = 0
    map_for_each(m, fn(_k: Str, v: Int) -> Void { total = total + v })
    assert_eq(total, 30)
}

test "map_filter: keep matching entries" {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("b", 2)
    m.set("c", 3)
    let filtered = map_filter(m, fn(_k: Str, v: Int) -> Bool { v > 1 })
    assert_eq(filtered.len(), 2)
    assert_eq(filtered.has("b"), true)
    assert_eq(filtered.has("c"), true)
    assert_eq(filtered.has("a"), false)
}

test "map_fold: sum values" {
    let m: Map[Str, Int] = Map()
    m.set("x", 5)
    m.set("y", 15)
    let total = map_fold(m, 0, fn(acc: Int, _k: Str, v: Int) -> Int { acc + v })
    assert_eq(total, 20)
}

test "map_fold: collect keys" {
    let m: Map[Str, Int] = Map()
    m.set("hello", 1)
    m.set("world", 2)
    let keys_str = map_fold(m, "", fn(acc: Str, k: Str, _v: Int) -> Str {
        if acc == "" { k } else { "{acc},{k}" }
    })
    assert(keys_str.len() > 0)
}

test "map_merge: combine two maps" {
    let a: Map[Str, Int] = Map()
    a.set("x", 1)
    let b: Map[Str, Int] = Map()
    b.set("y", 2)
    let merged = map_merge(a, b)
    assert_eq(merged.len(), 2)
    assert_eq(merged.get("x"), 1)
    assert_eq(merged.get("y"), 2)
}

test "map_merge: second overrides first" {
    let a: Map[Str, Int] = Map()
    a.set("k", 1)
    let b: Map[Str, Int] = Map()
    b.set("k", 99)
    let merged = map_merge(a, b)
    assert_eq(merged.len(), 1)
    assert_eq(merged.get("k"), 99)
}
