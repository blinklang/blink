fn parse_name(input: Str) -> Result[Str, Str] {
    if input == "" {
        Err("empty input")
    } else {
        Ok(input)
    }
}

fn name_length(input: Str) -> Result[Int, Str] {
    let name = parse_name(input)?
    Ok(name.len())
}

test "? with different Ok types propagates Ok" {
    let r = name_length("hello")
    assert_eq(r, Ok(5))
}

test "? with different Ok types propagates Err" {
    let r = name_length("")
    assert_eq(r, Err("empty input"))
}
