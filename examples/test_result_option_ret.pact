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

fn main() {
    let mut pass = true

    // Test Option[Int] with ?? operator
    let found = find_positive(42)
    let v1 = found ?? 0
    if v1 != 42 {
        io.println("FAIL: find_positive(42) ?? 0 expected 42, got {v1}")
        pass = false
    }

    let missing = find_positive(-1)
    let v2 = missing ?? 99
    if v2 != 99 {
        io.println("FAIL: find_positive(-1) ?? 99 expected 99, got {v2}")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
