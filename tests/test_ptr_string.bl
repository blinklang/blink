fn main() {
    let s = "hello world"
    let p = s.as_cstr()
    assert_eq(p.is_null(), false)

    let result = p.to_str()
    match result {
        Some(val) => assert_eq(val, "hello world")
        None => assert_eq(1, 0)
    }

    let null_p: Ptr[U8] = null_ptr()
    let null_result = null_p.to_str()
    match null_result {
        Some(_val) => assert_eq(1, 0)
        None => io.println("null check passed")
    }

    io.println("All Ptr string tests passed!")
}
