fn first_item[T](items: List[T]) -> Option[T] {
    items.get(0)
}

fn none_item[T](_items: List[T]) -> Option[T] {
    None
}

test "generic fn returning Option[Str]" {
    let names = ["alice", "bob"]
    let result = first_item(names)
    assert_eq(result.unwrap(), "alice")
}

test "generic fn returning Option[Int]" {
    let nums = [10, 20, 30]
    let result = first_item(nums)
    assert_eq(result.unwrap(), 10)
}

test "generic fn returning None" {
    let names = ["alice"]
    let result = none_item(names)
    assert_eq(result.is_none(), 1)
}

test "generic Option[Str] with match" {
    let names = ["hello"]
    let result = first_item(names)
    let msg = match result {
        Some(s) => s
        None => "nope"
    }
    assert_eq(msg, "hello")
}

test "generic Option[Int] unwrap_or" {
    let empty: List[Int] = []
    let result = first_item(empty)
    let val = result ?? 42
    assert_eq(val, 42)
}
