@derive(Serialize)
type Color { Red, Green, Blue }

@derive(Serialize)
type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}

test "simple enum serializes to string" {
    let c = Color.Green
    assert_eq(c.to_json(), "\"Green\"")
}

test "data enum circle serializes with type tag" {
    let s = Shape.Circle(1.5)
    assert_eq(s.to_json(), "\{\"type\":\"Circle\",\"radius\":1.5}")
}

test "unit variant serializes with type tag only" {
    let p = Shape.Point
    assert_eq(p.to_json(), "\{\"type\":\"Point\"}")
}
