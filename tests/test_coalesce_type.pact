fn get_opt() -> Str? {
    Some("hello")
}

test "?? result assigns to plain type" {
    let x: Str = get_opt() ?? "default"
    assert_eq(x, "hello")
}

test "?? result reassignable to plain type" {
    let x = get_opt() ?? "default"
    let mut y: Str = ""
    y = x
    assert_eq(y, "hello")
}
