type Color {
    Red
    Green
    Blue
}

fn get_color(fail: Bool) -> Result[Color, Str] {
    if fail {
        Err("no color")
    } else {
        Ok(Color.Red)
    }
}

test "Ok(SimpleEnum) generates correct Result type" {
    let r = get_color(false)
    match r {
        Ok(_c) => assert(true)
        Err(_e) => assert(false)
    }
    let r2 = get_color(true)
    match r2 {
        Ok(_c) => assert(false)
        Err(e) => assert_eq(e, "no color")
    }
}

fn wrap[T](val: T, fail: Bool) -> Result[List[T], Str] {
    if fail {
        Err("x")
    } else {
        Ok([val])
    }
}

test "Generic Err with compound ok type" {
    let r = wrap(42, true)
    match r {
        Ok(_list) => assert(false)
        Err(e) => assert_eq(e, "x")
    }
    let r2 = wrap(42, false)
    assert(r2.is_ok())
}

test "None in Option[List[Int]] type annotation" {
    let opt: Option[List[Int]] = None
    let _result = opt ?? [99]
    assert(true)
}
