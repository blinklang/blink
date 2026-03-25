@derive(Serialize)
type Address {
    city: Str
    zip: Str
}

@derive(Serialize)
type Person {
    name: Str
    address: Address
    tags: List[Str]
}

test "nested struct serialization" {
    let a = Address { city: "NYC", zip: "10001" }
    let p = Person {
        name: "Bob",
        address: a,
        tags: ["dev", "pact"]
    }
    let json = p.to_json()
    assert_eq(json, "\{\"name\":\"Bob\",\"address\":\{\"city\":\"NYC\",\"zip\":\"10001\"},\"tags\":[\"dev\",\"pact\"]}")
}
