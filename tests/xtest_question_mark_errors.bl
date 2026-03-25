fn try_parse(s: Str) -> Result[Int, Str] {
    Ok(42)
}

fn bad_usage() ! IO {
    let r = try_parse("hello")
    let v = r?
    io.println(v.to_string())
}

fn main() ! IO {
    io.println("should not reach here")
}
