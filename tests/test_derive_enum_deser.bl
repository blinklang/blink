import std.json

@derive(Serialize, Deserialize)
type Color { Red, Green, Blue }

@derive(Serialize, Deserialize)
type Shape {
    Circle(radius: Float)
    Point
}

test "color round-trip" {
    let c = Color.from_json("\"Green\"")
    match c {
        Ok(v) => assert_eq(v.to_json(), "\"Green\"")
        Err(_) => assert(false)
    }
}

test "shape round-trip" {
    let s = Shape.from_json("\{\"type\":\"Circle\",\"radius\":2.5}")
    match s {
        Ok(v) => assert_eq(v.to_json(), "\{\"type\":\"Circle\",\"radius\":2.5}")
        Err(_) => assert(false)
    }
}
