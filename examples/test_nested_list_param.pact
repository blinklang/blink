fn process_rows(rows: List[List[Str]]) ! IO {
    for row in rows {
        let val = row.get(0) ?? "missing"
        io.println(val)
    }
}

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

fn main() ! IO {
    let mut rows: List[List[Str]] = []
    let inner: List[Str] = ["hello", "world"]
    rows.push(inner)

    process_rows(rows)
    io.println(get_first(rows))
    io.println(unwrap_first(rows))
}
