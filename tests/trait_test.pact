type Point {
    x: Int
    y: Int
}

trait Describe {
    fn describe(self) -> Str
}

trait Magnitude {
    fn magnitude(self) -> Int
}

impl Describe for Point {
    fn describe(self) -> Str {
        "a point"
    }
}

impl Magnitude for Point {
    fn magnitude(self) -> Int {
        self.x + self.y
    }
}

fn main() {
    let p = Point { x: 3, y: 7 }

    // Method call via trait impl
    let s = p.describe()
    io.println(s)

    // Qualified trait call
    let s2 = Describe.describe(p)
    io.println(s2)

    // Second trait with Int return
    let m = p.magnitude()
    io.println(m)

    io.println("done")
}
