fn pure_function() -> Int {
    let x = 1 + 2
    x
}

fn prints_stuff() ! IO {
    io.println("hello")
}

test "pure function returns correct value" {
    assert_eq(pure_function(), 3)
}

test "effectful functions callable from test blocks" {
    prints_stuff()
    io.println("effects check passed")
}
