@derive(Serialize)
type User {
    name: Str
    age: Int
    score: Float
    active: Bool
}

test "struct serialization" {
    let u = User { name: "Alice", age: 30, score: 9.5, active: true }
    let json = u.to_json()
    assert_eq(json, "\{\"name\":\"Alice\",\"age\":30,\"score\":9.5,\"active\":true}")
}
