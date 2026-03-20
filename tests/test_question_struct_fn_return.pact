type Status {
    code: Int
    msg: Str
}

fn parse_code(input: Str) -> Result[Int, Str] {
    if input == "" {
        Err("empty")
    } else {
        Ok(input.len())
    }
}

fn make_status(input: Str) -> Result[Status, Str] {
    let code = parse_code(input)?
    Ok(Status { code: code, msg: input })
}

test "? with primitive operand and struct fn return - Ok path" {
    let r = make_status("hello")
    match r {
        Ok(s) => {
            assert_eq(s.code, 5)
            assert_eq(s.msg, "hello")
        }
        Err(_) => assert(false)
    }
}

test "? with primitive operand and struct fn return - Err path" {
    let r = make_status("")
    match r {
        Ok(_) => assert(false)
        Err(e) => assert_eq(e, "empty")
    }
}
