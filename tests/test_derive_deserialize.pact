import std.json

@derive(Serialize, Deserialize)
type User {
    name: Str
    age: Int
    score: Float
    active: Bool
}

test "user round-trip" {
    let u = User { name: "Alice", age: 30, score: 9.5, active: true }
    let json = u.to_json()
    let result = User.from_json(json)
    match result {
        Ok(u2) => {
            assert_eq(u2.name, "Alice")
            assert_eq(u2.to_json(), json)
        }
        Err(e) => assert(false)
    }
}

test "invalid json returns error" {
    let bad = User.from_json("not json")
    match bad {
        Ok(_) => assert(false)
        Err(_) => assert(true)
    }
}
