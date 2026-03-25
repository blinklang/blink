fn with_closure_then_none(flag: Int) -> Option[Str] {
    let transform = fn(s: Str) -> Str { s.concat("!") }
    if flag == 1 {
        Some(transform("hello"))
    } else {
        None
    }
}

test "closure inside Option[Str] fn - Some path" {
    let r = with_closure_then_none(1)
    assert_eq(r.unwrap(), "hello!")
}

test "closure inside Option[Str] fn - None path" {
    let r = with_closure_then_none(0)
    assert_eq(r.is_some(), 0)
}

fn closure_returns_option(flag: Int) -> Option[Str] {
    let maybe = fn(x: Int) -> Option[Str] {
        if x > 0 {
            Some("yes")
        } else {
            None
        }
    }
    maybe(flag)
}

test "closure returning Option[Str] - Some" {
    let r = closure_returns_option(1)
    assert_eq(r.unwrap(), "yes")
}

test "closure returning Option[Str] - None" {
    let r = closure_returns_option(0)
    assert_eq(r.is_some(), 0)
}
