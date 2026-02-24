import std.json

@derive(Serialize, Deserialize)
type Color { Red, Green, Blue }

@derive(Serialize, Deserialize)
type Shape {
    Circle(radius: Float)
    Point
}

fn check_color() -> Bool {
    let c = Color.from_json("\"Green\"")
    match c {
        Ok(v) => {
            if v.to_json() != "\"Green\"" {
                io.println("FAIL: Color round-trip -- got {v.to_json()}")
                return false
            }
            return true
        }
        Err(e) => {
            io.println("FAIL: Color from_json -- {e}")
            return false
        }
    }
}

fn check_shape() -> Bool {
    let s = Shape.from_json("\{\"type\":\"Circle\",\"radius\":2.5}")
    match s {
        Ok(v) => {
            let expected = "\{\"type\":\"Circle\",\"radius\":2.5}"
            if v.to_json() != expected {
                io.println("FAIL: Shape round-trip -- got {v.to_json()}")
                return false
            }
            return true
        }
        Err(e) => {
            io.println("FAIL: Shape from_json -- {e}")
            return false
        }
    }
}

fn main() {
    let mut pass = true
    if check_color() == false {
        pass = false
    }
    if check_shape() == false {
        pass = false
    }
    if pass {
        io.println("PASS")
    }
}
