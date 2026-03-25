import std.json

test "object builder" {
    let obj = json_new_object()
    json_set(obj, "name", json_new_str("Alice"))
    json_set(obj, "age", json_new_int(30))
    json_set(obj, "score", json_new_float(9.5))
    json_set(obj, "active", json_new_bool(1))
    let result = json_encode(obj)
    assert_eq(result, "\{\"name\":\"Alice\",\"age\":30,\"score\":9.5,\"active\":true}")
}

test "array builder" {
    json_clear()
    let arr = json_new_array()
    json_push(arr, json_new_int(1))
    json_push(arr, json_new_int(2))
    json_push(arr, json_new_int(3))
    assert_eq(json_encode(arr), "[1,2,3]")
}

test "nested object" {
    json_clear()
    let outer = json_new_object()
    let inner = json_new_object()
    json_set(inner, "x", json_new_int(10))
    json_set(outer, "point", inner)
    json_set(outer, "label", json_new_str("origin"))
    assert_eq(json_encode(outer), "\{\"point\":\{\"x\":10},\"label\":\"origin\"}")
}

test "null builder" {
    json_clear()
    let n = json_new_null()
    assert_eq(json_encode(n), "null")
}

test "json_set replaces existing key" {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "name", json_new_str("Alice"))
    json_set(obj, "name", json_new_str("Bob"))
    let result = json_encode(obj)
    assert_eq(result, "\{\"name\":\"Bob\"}")
}

test "json_set replace nested object" {
    json_clear()
    let obj = json_new_object()
    let inner1 = json_new_object()
    json_set(inner1, "x", json_new_int(1))
    json_set(obj, "data", inner1)
    let inner2 = json_new_object()
    json_set(inner2, "y", json_new_int(2))
    json_set(obj, "data", inner2)
    let result = json_encode(obj)
    assert_eq(result, "\{\"data\":\{\"y\":2}}")
}

test "json_remove removes key" {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "a", json_new_int(1))
    json_set(obj, "b", json_new_int(2))
    json_set(obj, "c", json_new_int(3))
    let removed = json_remove(obj, "b")
    assert(removed >= 0)
    assert_eq(json_len(obj), 2)
    assert_eq(json_get(obj, "b"), -1)
    let result = json_encode(obj)
    assert_eq(result, "\{\"a\":1,\"c\":3}")
}

test "json_remove missing key" {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "a", json_new_int(1))
    let removed = json_remove(obj, "nope")
    assert_eq(removed, -1)
    assert_eq(json_len(obj), 1)
    assert_eq(json_encode(obj), "\{\"a\":1}")
}

test "json_key_at iteration" {
    json_clear()
    let obj = json_new_object()
    json_set(obj, "alpha", json_new_int(1))
    json_set(obj, "beta", json_new_int(2))
    json_set(obj, "gamma", json_new_int(3))
    assert_eq(json_key_at(obj, 0), "alpha")
    assert_eq(json_key_at(obj, 1), "beta")
    assert_eq(json_key_at(obj, 2), "gamma")
    assert_eq(json_key_at(obj, 3), "")
}
