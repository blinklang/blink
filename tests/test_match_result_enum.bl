type Color {
    Red
    Green
    Blue
}

fn pick_color(n: Int) -> Result[Color, Str] {
    if n == 1 { Ok(Color.Red) }
    else if n == 2 { Ok(Color.Green) }
    else { Err("invalid") }
}

fn color_name(n: Int) -> Result[Str, Str] {
    let r = pick_color(n)
    let c = match r {
        Ok(color) => color
        Err(e) => return Err(e)
    }
    let name = match c {
        Color.Red => "red"
        Color.Green => "green"
        Color.Blue => "blue"
    }
    Ok(name)
}

test "match on Result[Enum, Str] let binding" {
    let result = color_name(1)
    assert_eq(result, Ok("red"))
}

test "match on Result[Enum, Str] error path" {
    let result = color_name(99)
    assert(result.is_err())
}
