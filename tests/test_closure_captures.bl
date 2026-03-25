test "mutable counter across closure boundary" {
    let mut counter = 0
    let increment = fn() {
        counter = counter + 1
    }
    increment()
    increment()
    increment()
    assert_eq(counter, 3)
}

test "snapshot idiom captures frozen copy" {
    let mut count = 0
    count = count + 1
    count = count + 1
    let snapshot = count
    let get_snapshot = fn() -> Int { snapshot }
    count = count + 1
    count = count + 1
    assert_eq(get_snapshot(), 2)
    assert_eq(count, 4)
}

test "immutable capture" {
    let x = 42
    let msg = "hello"
    let check = fn() -> Int { x }
    let greet = fn() -> Str { "{msg} world" }
    assert_eq(check(), 42)
    assert_eq(greet(), "hello world")
}
