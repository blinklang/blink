// struct_list_test.pact — Integration test for structs, lists, strings
//
// Exercises: type def, struct lit, field access, list ops, string methods,
//            string interpolation, match, for-in range, index access

type Point {
    x: Int
    y: Int
}

fn describe_point(px: Int, py: Int) -> Str {
    "({px}, {py})"
}

fn classify(n: Int) -> Str {
    match n {
        0 => "zero"
        1 => "one"
        _ => "other"
    }
}

fn main() {
    // Struct creation and field access
    let p = Point { x: 10, y: 20 }
    io.println("Point: {p.x}, {p.y}")
    io.println(describe_point(p.x, p.y))

    // Mutable list with push, len, get
    let mut nums = [1, 2, 3]
    nums.push(4)
    io.println("List len: {nums.len()}")

    // For-in over range with list.get
    for i in 0..4 {
        io.println("nums[{i}] = {nums.get(i).unwrap()}")
    }

    // String methods
    let greeting = "Hello, Pact!"
    io.println("Greeting length: {greeting.len()}")

    // String contains
    if greeting.contains("Pact") {
        io.println("Contains Pact: true")
    } else {
        io.println("Contains Pact: false")
    }

    // String starts_with
    if greeting.starts_with("Hello") {
        io.println("Starts with Hello: true")
    } else {
        io.println("Starts with Hello: false")
    }

    // Match expression
    io.println(classify(0))
    io.println(classify(1))
    io.println(classify(42))

    // Arithmetic in interpolation
    let a = 3
    let b = 7
    io.println("{a} + {b} = {a + b}")
}
