type Point {
    x: Float
    y: Float
}

type Color {
    Red
    Green
    Blue
}

type Shape {
    Circle(radius: Float)
    Rectangle(width: Float, height: Float)
    Point
}

fn add(a: Int, b: Int) -> Int {
    a + b
}

fn greet(name: Str) -> Str {
    "hello {name}"
}

fn get_value() -> Option[Int] {
    Some(42)
}

fn identity[T](x: T) -> T {
    x
}

fn first[T](a: T, b: T) -> T {
    a
}

test "type checker runs without errors" {
    let p = Point { x: 1.0, y: 2.0 }
    let c = Color.Red
    let s = Shape.Circle(5.0)
    let n = identity(42)
    let msg = identity("hello")
    let x = first(1, 2)
    assert(true)
}
