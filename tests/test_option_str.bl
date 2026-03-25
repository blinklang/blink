fn find_name(id: Int) -> Option[Str] {
    if id == 1 {
        Some("Alice")
    } else {
        None
    }
}

test "Option[Str] Some returns value" {
    let name = find_name(1)
    let v = name ?? "unknown"
    assert_eq(v, "Alice")
}

test "Option[Str] None returns default" {
    let name = find_name(0)
    let v = name ?? "unknown"
    assert_eq(v, "unknown")
}

test "Option[Str] is_some" {
    let found = find_name(1)
    assert_eq(found.is_some(), 1)
    let missing = find_name(0)
    assert_eq(missing.is_some(), 0)
}

test "Option[Str] unwrap" {
    let found = find_name(1)
    let v = found.unwrap()
    assert_eq(v, "Alice")
}
