type Pair[A, B] {
    first: A
    second: B
}

type Box[T] {
    value: T
}

fn identity[T](x: T) -> T {
    x
}

fn first_of[T](a: T, b: T) -> T {
    a
}

fn max_val[T](a: T, b: T) -> T {
    if a > b { a } else { b }
}

test "generic struct Pair with Int fields" {
    let p1 = Pair { first: 10, second: 20 }
    assert_eq(p1.first, 10)
    assert_eq(p1.second, 20)
}

test "generic struct Pair with Str fields" {
    let p2 = Pair { first: "hello", second: "world" }
    io.println(p2.first)
    io.println(p2.second)
}

test "generic struct Pair with mixed fields" {
    let p3 = Pair { first: 42, second: "answer" }
    assert_eq(p3.first, 42)
    let p4 = Pair { first: "count", second: 99 }
    assert_eq(p4.second, 99)
}

test "generic struct Box" {
    let b1 = Box { value: 777 }
    assert_eq(b1.value, 777)
    let b2 = Box { value: "boxed" }
    io.println(b2.value)
}

test "generic functions" {
    let id_int = identity(123)
    assert_eq(id_int, 123)
    let id_str = identity("hello identity")
    io.println(id_str)
    let f1 = first_of(10, 20)
    assert_eq(f1, 10)
    let m1 = max_val(3, 7)
    assert_eq(m1, 7)
    let m2 = max_val(100, 42)
    assert_eq(m2, 100)
}
