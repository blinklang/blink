type Point { x: Int, y: Int }

fn make_point(x: Int, y: Int) -> Point {
    Point { x: x, y: y }
}

fn main() ! IO {
    let mut points: List[Point] = []
    points.push(Point { x: 1, y: 2 })
    points.push(Point { x: 3, y: 4 })
    points.push(make_point(5, 6))

    let p = points.get(0).unwrap()
    io.println("x={p.x} y={p.y}")

    io.println("len={points.len()}")
}
