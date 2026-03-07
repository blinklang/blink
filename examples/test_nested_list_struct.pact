type Person { name: Str, age: Int }

fn main() ! IO {
    let mut rows: List[List[Person]] = []
    let inner: List[Person] = [Person { name: "Alice", age: 30 }]
    rows.push(inner)

    for row in rows {
        let p = row.get(0).unwrap()
        io.println(p.name)
    }
}
