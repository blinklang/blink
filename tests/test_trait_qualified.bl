import std.traits

test "trait-qualified string methods" {
    let s = "hello world"
    assert_eq(StrOps.len(s), 11)
    assert_eq(StrOps.contains(s, "world"), true)
    assert_eq(StrOps.starts_with(s, "hello"), true)
    assert_eq(StrOps.ends_with(s, "world"), true)
    assert_eq(StrOps.index_of(s, "world"), 6)
    assert_eq(StrOps.to_upper(s), "HELLO WORLD")
    assert_eq(StrOps.trim("  hi  "), "hi")
    assert_eq(StrOps.concat("a", "b"), "ab")
    assert_eq(StrOps.slice(s, 0, 5), "hello")
    assert_eq(StrOps.substring(s, 6, 5), "world")
}

test "trait-qualified map methods" {
    let m = Map()
    MapOps.set(m, "key", 42)
    assert_eq(MapOps.has(m, "key"), true)
    assert_eq(MapOps.get(m, "key"), 42)
    assert_eq(MapOps.len(m), 1)
    MapOps.remove(m, "key")
    assert_eq(MapOps.has(m, "key"), false)
}

test "trait-qualified list methods" {
    let ls: List[Int] = []
    ListOps.push(ls, 10)
    ListOps.push(ls, 20)
    assert_eq(ListOps.len(ls), 2)
    assert_eq(ListOps.is_empty(ls), false)
}

test "trait-qualified bytes methods" {
    let b = Bytes.new()
    BytesOps.push(b, 72)
    BytesOps.push(b, 105)
    assert_eq(BytesOps.len(b), 2)
    assert_eq(BytesOps.is_empty(b), false)
    assert_eq(BytesOps.to_hex(b), "4869")
}

test "trait-qualified stringbuilder methods" {
    let sb = StringBuilder.new()
    StringBuildOps.write(sb, "hello")
    assert_eq(StringBuildOps.len(sb), 5)
    assert_eq(StringBuildOps.to_str(sb), "hello")
    assert_eq(StringBuildOps.is_empty(sb), false)
    StringBuildOps.clear(sb)
    assert_eq(StringBuildOps.is_empty(sb), true)
}
