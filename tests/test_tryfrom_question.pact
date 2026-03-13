trait TryFrom[T] {
    fn try_from(value: T) -> Result[Self, Str]
}

type Percent {
    value: Int
}

impl TryFrom[Int] for Percent {
    fn try_from(value: Int) -> Result[Int, Str] {
        if value < 0 {
            Err("negative percentage")
        } else if value > 100 {
            Err("percentage exceeds 100")
        } else {
            Ok(value)
        }
    }
}

type Rating {
    score: Int
}

impl TryFrom[Int] for Rating {
    fn try_from(value: Int) -> Result[Int, Str] {
        if value < 1 {
            Err("rating too low")
        } else if value > 5 {
            Err("rating too high")
        } else {
            Ok(value)
        }
    }
}

fn validate_percent(n: Int) -> Result[Int, Str] {
    let v = Percent.try_from(n)?
    Ok(v)
}

fn validate_rating(n: Int) -> Result[Int, Str] {
    let r = Rating.try_from(n)?
    Ok(r)
}

fn validate_both(pct: Int, rate: Int) -> Result[Int, Str] {
    let p = Percent.try_from(pct)?
    let r = Rating.try_from(rate)?
    Ok(p + r)
}

fn error_should_propagate(n: Int) -> Result[Int, Str] {
    let v = validate_percent(n)?
    Ok(999)
}

fn test_error_propagation() -> Result[Int, Str] {
    let e1 = error_should_propagate(-5)
    let ok1 = error_should_propagate(50)?
    if ok1 != 999 { return Err("error_prop: valid call failed") }

    let e2 = validate_both(-1, 3)
    let ok2 = validate_both(10, 2)?
    if ok2 != 12 { return Err("error_prop: chain failed") }

    let e3 = validate_both(50, 0)
    let ok3 = validate_both(20, 5)?
    if ok3 != 25 { return Err("error_prop: chain2 failed") }

    let e4 = error_should_propagate(150)
    let ok4 = error_should_propagate(25)?
    if ok4 != 999 { return Err("error_prop: boundary failed") }

    Ok(0)
}

fn run_all() -> Result[Int, Str] {
    let v1 = Percent.try_from(42)?
    if v1 != 42 { return Err("test1") }

    let v2 = validate_percent(75)?
    if v2 != 75 { return Err("test2") }

    let v3 = Rating.try_from(3)?
    if v3 != 3 { return Err("test3") }

    let v4 = validate_rating(5)?
    if v4 != 5 { return Err("test4") }

    let v5 = validate_both(50, 4)?
    if v5 != 54 { return Err("test5") }

    let v6 = Percent.try_from(0)?
    if v6 != 0 { return Err("test6") }

    let v7 = Percent.try_from(100)?
    if v7 != 100 { return Err("test7") }

    let ep = test_error_propagation()?

    Ok(0)
}

test "try_from with question mark operator" {
    let r = run_all()
    assert(r.is_ok())
}
