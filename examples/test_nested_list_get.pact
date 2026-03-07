fn main() ! IO {
    let rows: List[List[Str]] = []
    let inner: List[Str] = ["hello", "world"]
    rows.push(inner)

    let maybe_row = rows.get(0)
    let row = maybe_row ?? []
    io.println(row.get(0) ?? "empty")

    let missing = rows.get(99) ?? []
    io.println("len: {missing.len()}")
}
