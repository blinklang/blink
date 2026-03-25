type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}

fn describe(s: Shape) -> Str {
    match s {
        Shape.Circle(r) => "circle r={r}"
        Shape.Rectangle(w, h) => "rect {w}x{h}"
        Shape.Point => "point"
    }
}

fn main() ! IO {
    let mut shapes: List[Shape] = []
    shapes.push(Shape.Circle(5.0))
    shapes.push(Shape.Rectangle(3.0, 4.0))
    shapes.push(Shape.Point)

    let c = Shape.Circle(1.0)
    shapes.push(c)

    let s0 = shapes.get(0).unwrap()
    io.println(describe(s0))

    let s1 = shapes.get(1).unwrap()
    io.println(describe(s1))

    let s2 = shapes.get(2).unwrap()
    io.println(describe(s2))

    let s3 = shapes.get(3).unwrap()
    io.println(describe(s3))

    io.println("len={shapes.len()}")

    for s in shapes {
        match s {
            Shape.Circle(r) => io.println("for circle r={r}")
            Shape.Rectangle(w, h) => io.println("for rect {w}x{h}")
            Shape.Point => io.println("for point")
        }
    }
}
