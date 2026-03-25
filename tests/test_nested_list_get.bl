test "nested list get with coalesce" {
    let rows: List[List[Str]] = []
    let inner: List[Str] = ["hello", "world"]
    rows.push(inner)

    let maybe_row = rows.get(0)
    let row = maybe_row ?? []
    assert_eq(row.get(0) ?? "empty", "hello")

    let missing = rows.get(99) ?? []
    assert_eq(missing.len(), 0)
}
