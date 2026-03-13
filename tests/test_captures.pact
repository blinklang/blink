test "capture single int" {
    let x = 10
    let add_x = fn(a: Int) -> Int { a + x }
    assert_eq(add_x(5), 15)
}

test "capture string" {
    let name = "world"
    let greet = fn() -> Str { "hello {name}" }
    assert_eq(greet(), "hello world")
}

test "capture multiple variables" {
    let a = 1
    let b = 2
    let c = 3
    let sum_abc = fn() -> Int { a + b + c }
    assert_eq(sum_abc(), 6)
}

test "capture in multiplication" {
    let factor = 7
    let mul = fn(n: Int) -> Int { n * factor }
    assert_eq(mul(6), 42)
}
