import std.json

test "parse string" {
    json_clear()
    let idx = json_parse("\"hello world\"")
    assert_eq(json_type(idx), JSON_STRING)
    assert_eq(json_as_str(idx), "hello world")
}

test "parse int" {
    json_clear()
    let idx = json_parse("42")
    assert_eq(json_type(idx), JSON_INT)
    assert_eq(json_as_int(idx), 42)
}

test "parse negative int" {
    json_clear()
    let idx = json_parse("-7")
    assert_eq(json_type(idx), JSON_INT)
    assert_eq(json_as_int(idx), -7)
}

test "parse float" {
    json_clear()
    let idx = json_parse("3.14")
    assert_eq(json_type(idx), JSON_FLOAT)
    assert_eq(json_as_float(idx), 3.14)
}

test "parse bool true" {
    json_clear()
    let idx = json_parse("true")
    assert_eq(json_type(idx), JSON_BOOL)
    assert_eq(json_as_bool(idx), 1)
}

test "parse bool false" {
    json_clear()
    let idx = json_parse("false")
    assert_eq(json_type(idx), JSON_BOOL)
    assert_eq(json_as_bool(idx), 0)
}

test "parse null" {
    json_clear()
    let idx = json_parse("null")
    assert_eq(json_type(idx), JSON_NULL)
}

test "parse empty array" {
    json_clear()
    let idx = json_parse("[]")
    assert_eq(json_type(idx), JSON_ARRAY)
    assert_eq(json_len(idx), 0)
}

test "parse int array" {
    json_clear()
    let idx = json_parse("[1, 2, 3]")
    assert_eq(json_type(idx), JSON_ARRAY)
    assert_eq(json_len(idx), 3)

    let first = json_at(idx, 0)
    assert_eq(json_as_int(first), 1)
    let second = json_at(idx, 1)
    assert_eq(json_as_int(second), 2)
    let third = json_at(idx, 2)
    assert_eq(json_as_int(third), 3)
}

test "parse string array" {
    json_clear()
    let idx = json_parse("[\"a\", \"b\", \"c\"]")
    assert_eq(json_len(idx), 3)
    assert_eq(json_as_str(json_at(idx, 0)), "a")
    assert_eq(json_as_str(json_at(idx, 2)), "c")
}

test "parse empty object" {
    json_clear()
    let idx = json_parse("\{}")
    assert_eq(json_type(idx), JSON_OBJECT)
    assert_eq(json_len(idx), 0)
}

test "parse simple object" {
    json_clear()
    let idx = json_parse("\{\"name\":\"Alice\",\"age\":30}")
    assert_eq(json_type(idx), JSON_OBJECT)
    assert_eq(json_len(idx), 2)

    let name_idx = json_get(idx, "name")
    assert_eq(json_type(name_idx), JSON_STRING)
    assert_eq(json_as_str(name_idx), "Alice")

    let age_idx = json_get(idx, "age")
    assert_eq(json_type(age_idx), JSON_INT)
    assert_eq(json_as_int(age_idx), 30)
}

test "parse nested object" {
    json_clear()
    let idx = json_parse("\{\"user\":\{\"id\":1,\"name\":\"Bob\"},\"active\":true}")
    assert_eq(json_type(idx), JSON_OBJECT)

    let user_idx = json_get(idx, "user")
    assert_eq(json_type(user_idx), JSON_OBJECT)

    let id_idx = json_get(user_idx, "id")
    assert_eq(json_as_int(id_idx), 1)

    let name_idx = json_get(user_idx, "name")
    assert_eq(json_as_str(name_idx), "Bob")

    let active_idx = json_get(idx, "active")
    assert_eq(json_as_bool(active_idx), 1)
}

test "parse mixed array" {
    json_clear()
    let idx = json_parse("[1, \"two\", true, null]")
    assert_eq(json_len(idx), 4)
    assert_eq(json_type(json_at(idx, 0)), JSON_INT)
    assert_eq(json_type(json_at(idx, 1)), JSON_STRING)
    assert_eq(json_type(json_at(idx, 2)), JSON_BOOL)
    assert_eq(json_type(json_at(idx, 3)), JSON_NULL)
}

test "get missing key" {
    json_clear()
    let idx = json_parse("\{\"a\":1}")
    let missing = json_get(idx, "b")
    assert_eq(missing, -1)
}

test "at out of bounds" {
    json_clear()
    let idx = json_parse("[1, 2]")
    let oob = json_at(idx, 5)
    assert_eq(oob, -1)
}

test "parse invalid" {
    json_clear()
    let idx = json_parse("invalid")
    assert_eq(idx, -1)
}

test "serialize null" {
    json_clear()
    let idx = json_parse("null")
    assert_eq(json_serialize(idx), "null")
}

test "serialize bool" {
    json_clear()
    let idx = json_parse("true")
    assert_eq(json_serialize(idx), "true")

    json_clear()
    let idx2 = json_parse("false")
    assert_eq(json_serialize(idx2), "false")
}

test "serialize int" {
    json_clear()
    let idx = json_parse("42")
    assert_eq(json_serialize(idx), "42")
}

test "serialize string" {
    json_clear()
    let idx = json_parse("\"hello\"")
    assert_eq(json_serialize(idx), "\"hello\"")
}

test "serialize array" {
    json_clear()
    let idx = json_parse("[1,2,3]")
    assert_eq(json_serialize(idx), "[1,2,3]")
}

test "serialize object" {
    json_clear()
    let idx = json_parse("\{\"a\":1,\"b\":\"two\"}")
    let result = json_serialize(idx)
    assert_eq(result, "\{\"a\":1,\"b\":\"two\"}")
}

test "parse whitespace" {
    json_clear()
    let idx = json_parse("  \{  \"key\"  :  \"value\"  }  ")
    assert_eq(json_type(idx), JSON_OBJECT)
    assert_eq(json_as_str(json_get(idx, "key")), "value")
}

test "parse escaped string" {
    json_clear()
    let idx = json_parse("\"hello\\nworld\"")
    assert_eq(json_as_str(idx), "hello\nworld")
}

test "parse unicode escape ascii" {
    json_clear()
    let idx = json_parse("\"\\u0041\"")
    assert_eq(json_as_str(idx), "A")
}

test "parse unicode escape space" {
    json_clear()
    let idx = json_parse("\"hello\\u0020world\"")
    assert_eq(json_as_str(idx), "hello world")
}

test "parse unicode escape 2byte" {
    json_clear()
    let idx = json_parse("\"caf\\u00E9\"")
    // 0xE9 = 233 = é
    let expected = "caf".concat(Char.from_code_point(233))
    assert_eq(json_as_str(idx), expected)
}

test "parse unicode escape 3byte" {
    json_clear()
    let idx = json_parse("\"\\u4E16\"")
    // 0x4E16 = 19990 = 世
    let expected = Char.from_code_point(19990)
    assert_eq(json_as_str(idx), expected)
}

test "parse unicode escape surrogate pair" {
    json_clear()
    let idx = json_parse("\"\\uD83D\\uDE00\"")
    // 0x1F600 = 128512 = 😀
    let expected = Char.from_code_point(128512)
    assert_eq(json_as_str(idx), expected)
}

test "parse unicode escape lone low surrogate" {
    json_clear()
    let idx = json_parse("\"\\uDC00\"")
    assert_eq(json_as_str(idx), "?")
}

test "parse unicode escape lowercase" {
    json_clear()
    let idx = json_parse("\"\\u00e9\"")
    // 0xE9 = 233 = é
    assert_eq(json_as_str(idx), Char.from_code_point(233))
}

test "clear" {
    json_clear()
    json_parse("\{\"a\":1}")
    assert_eq(json_types.len(), 2)
    json_clear()
    assert_eq(json_types.len(), 0)
    assert_eq(json_str_vals.len(), 0)
    assert_eq(json_int_vals.len(), 0)
    assert_eq(json_parents.len(), 0)
}
