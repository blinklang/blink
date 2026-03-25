fn divide(a: Int, b: Int) -> Result[Int, Str] {
    if b == 0 {
        Err("division by zero")
    } else {
        Ok(a / b)
    }
}

fn try_divide(a: Int, b: Int) -> Result[Int, Str] {
    let result = divide(a, b)?
    Ok(result * 2)
}

fn find_value(x: Int) -> Int? {
    if x > 0 {
        Some(x * 10)
    } else {
        None
    }
}

test "? operator propagates Ok" {
    let ok_result = try_divide(10, 2)
    assert_eq(ok_result, Ok(10))
}

test "? operator propagates Err" {
    let err_result = try_divide(10, 0)
    assert_eq(err_result, Err("division by zero"))
}

test "?? operator unwraps Some" {
    let x = Some(42)
    let val = x ?? 0
    assert_eq(val, 42)
}

test "?? operator uses default for None" {
    let y = None
    let val = y ?? 99
    assert_eq(val, 99)
}

test "T? syntax sugar with Some" {
    let found = find_value(5)
    let v = found ?? 0
    assert_eq(v, 50)
}

test "T? syntax sugar with None" {
    let not_found = find_value(-1)
    let v = not_found ?? 0
    assert_eq(v, 0)
}
