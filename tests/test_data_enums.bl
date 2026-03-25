type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}

fn area(s: Shape) -> Float {
    match s {
        Shape.Circle(r) => 3.14159 * r * r
        Shape.Rectangle(w, h) => w * h
        Shape.Point => 0.0
    }
}

fn describe(s: Shape) -> Str {
    match s {
        Shape.Circle(_) => "circle"
        Shape.Rectangle(_, _) => "rectangle"
        Shape.Point => "point"
    }
}

test "circle area" {
    let c = Shape.Circle(5.0)
    assert_eq(area(c), 78.53975)
}

test "rectangle area" {
    let r = Shape.Rectangle(3.0, 4.0)
    assert_eq(area(r), 12.0)
}

test "point area" {
    let p = Shape.Point
    assert_eq(area(p), 0.0)
}

test "describe shapes" {
    assert_eq(describe(Shape.Circle(5.0)), "circle")
    assert_eq(describe(Shape.Rectangle(3.0, 4.0)), "rectangle")
    assert_eq(describe(Shape.Point), "point")
}
