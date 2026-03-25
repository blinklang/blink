fn safe_divide(a: Int, b: Int) -> Result[Int, Str] {
    if b == 0 {
        Err("division by zero")
    } else {
        Ok(a / b)
    }
}

fn try_chain(a: Int, b: Int) -> Result[Int, Str] {
    let r = safe_divide(a, b)?
    Ok(r * 2)
}

fn find_positive(x: Int) -> Option[Int] {
    if x > 0 {
        Some(x)
    } else {
        None
    }
}

test "Option with ?? unwraps Some value" {
    let found = find_positive(42)
    let v = found ?? 0
    assert_eq(v, 42)
}

test "Option with ?? uses default for None" {
    let missing = find_positive(-1)
    let v = missing ?? 99
    assert_eq(v, 99)
}
