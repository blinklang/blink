// Test that C reserved words can be used as Pact identifiers

fn process(int: Int, char: Str) -> Str {
    "{int}: {char}"
}

fn use_reserved_let() -> Int {
    let float = 3
    let double = 7
    let void = 10
    float + double + void
}

fn use_reserved_params(struct: Str, default: Int) -> Str {
    "{struct}-{default}"
}

test "C reserved words as function parameters" {
    assert_eq(process(42, "hello"), "42: hello")
}

test "C reserved words as let bindings" {
    assert_eq(use_reserved_let(), 20)
}

test "more C reserved words as parameters" {
    assert_eq(use_reserved_params("test", 5), "test-5")
}

test "C reserved words in list iteration" {
    let items: List[Int] = [10, 20, 30]
    let mut static = 0
    for int in items {
        static = static + int
    }
    assert_eq(static, 60)
}

test "libc names as identifiers" {
    let printf = "formatted"
    let malloc = 42
    let strlen = 10
    assert_eq(printf, "formatted")
    assert_eq(malloc, 42)
    assert_eq(strlen, 10)
}

test "mutable C reserved word bindings" {
    let mut register = 0
    register = register + 5
    register = register + 10
    assert_eq(register, 15)
}
