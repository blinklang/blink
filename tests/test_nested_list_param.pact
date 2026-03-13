fn get_first(rows: List[List[Str]]) -> Str {
    let row = rows.get(0) ?? []
    let val = row.get(0) ?? "none"
    val
}

fn unwrap_first(rows: List[List[Str]]) -> Str {
    let row = rows.get(0).unwrap()
    let val = row.get(0).unwrap()
    val
}

test "nested list passed as parameter" {
    let mut rows: List[List[Str]] = []
    let inner: List[Str] = ["hello", "world"]
    rows.push(inner)

    assert_eq(get_first(rows), "hello")
    assert_eq(unwrap_first(rows), "hello")
}
