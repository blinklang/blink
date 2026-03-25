type Coord {
    x: Int
    y: Int
}

type MathError {
    DivByZero
    Overflow(msg: Str)
}

fn make_coord(x: Int, y: Int) -> Result[Coord, MathError] {
    if x == 0 && y == 0 {
        Err(MathError.DivByZero)
    } else {
        Ok(Coord { x: x, y: y })
    }
}

fn use_coord() -> Result[Int, MathError] {
    let c = make_coord(3, 4)?
    Ok(c.x + c.y)
}

fn maybe_coord(x: Int) -> Option[Coord] {
    if x > 0 {
        Some(Coord { x: x, y: x * 2 })
    } else {
        None
    }
}

test "Result with ? operator on struct" {
    let r = use_coord()
    match r {
        Ok(val) => assert_eq(val, 7)
        Err(_) => assert(false)
    }
}

test "Result Ok with struct fields" {
    let r = make_coord(3, 4)
    match r {
        Ok(c) => {
            assert_eq(c.x, 3)
            assert_eq(c.y, 4)
        }
        Err(_) => assert(false)
    }
}

test "Result Err with enum variant" {
    let r = make_coord(0, 0)
    match r {
        Ok(_) => assert(false)
        Err(e) => {
            match e {
                DivByZero => assert(true)
                Overflow(msg) => assert(false)
            }
        }
    }
}

test "Option with struct and ?? operator" {
    let opt = maybe_coord(5)
    let fallback = Coord { x: 0, y: 0 }
    let c = opt ?? fallback
    assert_eq(c.x, 5)
    assert_eq(c.y, 10)
}

test "Option None with struct fallback" {
    let opt = maybe_coord(-1)
    let c = opt ?? Coord { x: 99, y: 99 }
    assert_eq(c.x, 99)
    assert_eq(c.y, 99)
}
