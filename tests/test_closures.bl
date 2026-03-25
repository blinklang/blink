test "arithmetic closures" {
    let add = fn(a: Int, b: Int) -> Int { a + b }
    assert_eq(add(1, 2), 3)
    let mul = fn(x: Int, y: Int) -> Int { x * y }
    assert_eq(mul(6, 7), 42)
}

test "string closures" {
    let greet = fn(name: Str) -> Str { "hello {name}" }
    assert_eq(greet("pact"), "hello pact")
    let identity = fn(s: Str) -> Str { s }
    assert_eq(identity("echo"), "echo")
}

test "predicate closures" {
    let is_even = fn(n: Int) -> Bool { n % 2 == 0 }
    assert(is_even(4))
    assert(is_even(3) == false)
}
