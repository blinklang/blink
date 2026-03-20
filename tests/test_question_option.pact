fn find_value(x: Int) -> Option[Int] {
    if x > 0 {
        Some(x * 10)
    } else {
        None
    }
}

fn try_find(x: Int) -> Option[Int] {
    let v = find_value(x)?
    Some(v + 1)
}

fn try_chain(x: Int) -> Option[Int] {
    let a = find_value(x)?
    let b = find_value(a)?
    Some(b + 1)
}

fn try_list_get(items: List[Int], idx: Int) -> Option[Int] {
    let v = items.get(idx)?
    Some(v * 2)
}

test "? on Some unwraps value" {
    let r = try_find(5)
    assert_eq(r, Some(51))
}

test "? on None propagates None" {
    let r = try_find(-1)
    assert_eq(r, None)
}

test "chaining multiple ? operations" {
    let r = try_chain(1)
    assert_eq(r, Some(101))
}

test "chaining ? where second returns None" {
    let r = try_chain(-1)
    assert_eq(r, None)
}

test "? with List.get" {
    let items = [10, 20, 30]
    let r = try_list_get(items, 1)
    assert_eq(r, Some(40))
}

test "? with List.get out of bounds" {
    let items = [10, 20, 30]
    let r = try_list_get(items, 5)
    assert_eq(r, None)
}
