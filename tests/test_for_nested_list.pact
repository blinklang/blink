fn main() ! IO {
    let rows: List[List[Str]] = []
    let inner1: List[Str] = ["hello", "world"]
    let inner2: List[Str] = ["foo", "bar"]
    rows.push(inner1)
    rows.push(inner2)

    for row in rows {
        let first = row.get(0) ?? "empty"
        io.println(first)
    }
}
