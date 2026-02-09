fn main() {
    let x = 10
    let add_x = fn(a: Int) -> Int { a + x }
    let result = add_x(5)
    io.println("{result}")

    let name = "world"
    let greet = fn() -> Str { "hello {name}" }
    io.println(greet())

    let a = 1
    let b = 2
    let c = 3
    let sum_abc = fn() -> Int { a + b + c }
    io.println("{sum_abc()}")

    let factor = 7
    let mul = fn(n: Int) -> Int { n * factor }
    io.println("{mul(6)}")

    io.println("PASS")
}
