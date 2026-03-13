test "List.is_empty on empty list" {
    let items: List[Int] = []
    assert_eq(items.is_empty(), true)
}

test "List.is_empty on non-empty list" {
    let items = [1, 2, 3]
    assert_eq(items.is_empty(), false)
}

test "List.is_empty after clearing" {
    let items = [42]
    items.pop()
    assert_eq(items.is_empty(), true)
}
