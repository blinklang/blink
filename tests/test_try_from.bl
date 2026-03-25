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
        } else {
            Ok(value)
        }
    }
}

test "try_from basic" {
    let result = Percent.try_from(42)
    assert(result.is_ok())
}
