@derive(Serialize)
type Color { Red, Green, Blue }

@derive(Serialize)
type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}

fn main() {
    let mut pass = true

    // Simple enum -> string
    let c = Color.Green
    if c.to_json() != "\"Green\"" {
        io.println("FAIL: simple enum -- got {c.to_json()}")
        pass = false
    }

    // Data enum with fields -> internally tagged
    let s = Shape.Circle(1.5)
    let expected = "\{\"type\":\"Circle\",\"radius\":1.5}"
    if s.to_json() != expected {
        io.println("FAIL: data enum Circle -- got {s.to_json()}")
        pass = false
    }

    // Unit variant
    let p = Shape.Point
    if p.to_json() != "\{\"type\":\"Point\"}" {
        io.println("FAIL: data enum Point -- got {p.to_json()}")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
