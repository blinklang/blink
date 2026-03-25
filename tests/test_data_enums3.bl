type Color { Red, Green, Blue }

type Result2 {
    Success(value: Int)
    Error(message: Str)
}

fn show_result(r: Result2) -> Str {
    match r {
        Result2.Success(v) => "success: {v}"
        Result2.Error(msg) => "error: {msg}"
    }
}

test "simple enum match" {
    let c = Color.Red
    let color_name = match c {
        Color.Red => "red"
        Color.Green => "green"
        Color.Blue => "blue"
    }
    assert_eq(color_name, "red")
}

test "data enum success" {
    let ok = Result2.Success(42)
    assert_eq(show_result(ok), "success: 42")
}

test "data enum error" {
    let err = Result2.Error("not found")
    assert_eq(show_result(err), "error: not found")
}
