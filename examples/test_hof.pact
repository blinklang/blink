fn apply(f: fn(Int) -> Int, x: Int) -> Int {
    f(x)
}

fn apply_twice(f: fn(Int) -> Int, x: Int) -> Int {
    f(f(x))
}

fn main() {
    let dbl = fn(x: Int) -> Int { x * 2 }
    let result = apply(dbl, 5)
    io.println("{result}")

    let add3 = fn(x: Int) -> Int { x + 3 }
    io.println("{apply(add3, 10)}")

    io.println("{apply_twice(dbl, 3)}")

    io.println("PASS")
}
