import std.json

test "object with nested children roundtrip" {
    json_clear()
    let root = json_parse("\{\"a\": \{\"x\": 1}, \"b\": \"test\", \"c\": \"foo\"}")
    let out = json_serialize(root)
    assert_eq(out, "\{\"a\":\{\"x\":1},\"b\":\"test\",\"c\":\"foo\"}")
}

test "array with nested object elements" {
    json_clear()
    let root = json_parse("[\{\"k\": 1}, \{\"k\": 2}, \{\"k\": 3}]")
    let e0 = json_at(root, 0)
    let e1 = json_at(root, 1)
    let e2 = json_at(root, 2)
    assert_eq(json_as_int(json_get(e0, "k")), 1)
    assert_eq(json_as_int(json_get(e1, "k")), 2)
    assert_eq(json_as_int(json_get(e2, "k")), 3)
    let out = json_serialize(root)
    assert_eq(out, "[\{\"k\":1},\{\"k\":2},\{\"k\":3}]")
}

test "parse then push to empty array" {
    json_clear()
    let root = json_parse("\{\"items\": []}")
    let arr = json_get(root, "items")
    json_push(arr, json_new_int(42))
    json_push(arr, json_new_str("hello"))
    let out = json_serialize(root)
    assert_eq(out, "\{\"items\":[42,\"hello\"]}")
}

test "json_set on parsed tree" {
    json_clear()
    let root = json_parse("\{\"name\": \"old\", \"nested\": \{\"val\": 0}}")
    json_set(root, "name", json_new_str("new"))
    let nested = json_get(root, "nested")
    json_set(nested, "val", json_new_int(99))
    let out = json_serialize(root)
    assert_eq(out, "\{\"name\":\"new\",\"nested\":\{\"val\":99}}")
}

test "deeply nested object roundtrip" {
    json_clear()
    let root = json_parse("\{\"a\": \{\"b\": \{\"c\": 1}}, \"d\": 2}")
    let out = json_serialize(root)
    assert_eq(out, "\{\"a\":\{\"b\":\{\"c\":1}},\"d\":2}")
}
