fn check_value(x: Int) -> Str {
    match x {
        1 => {
            let mut result = ""
            if x > 0 {
                result = result + "positive one "
            }
            if x < 10 {
                result = result + "single digit "
            }
            result + "was one"
        }
        _ => {
            "other"
        }
    }
}

test "match with if inside arm for value 1" {
    assert_eq(check_value(1), "positive one single digit was one")
}

test "match wildcard arm" {
    assert_eq(check_value(42), "other")
}
