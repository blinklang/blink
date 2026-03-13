fn make_result(good: Bool) -> Result[Int, Str] {
    if good {
        return Ok(42)
    }
    Err("bad")
}

fn process_ok() -> Int {
    let mut total = 0
    let r = make_result(true)
    match r {
        Ok(n) => total = n
        Err(_) => total = -1
    }
    total
}

fn process_err() -> Int {
    let mut total = 0
    let r = make_result(false)
    match r {
        Ok(n) => total = n
        Err(_) => total = -1
    }
    total
}

test "match arm assigns to outer mut variable from Ok" {
    assert_eq(process_ok(), 42)
}

test "match arm assigns to outer mut variable from Err" {
    assert_eq(process_err(), -1)
}
