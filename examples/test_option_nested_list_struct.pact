type Person { name: Str, age: Int }

fn main() ! IO {
    let rows: List[List[Person]] = []
    let inner: List[Person] = [Person { name: "Alice", age: 30 }]
    rows.push(inner)

    let row = rows.get(0) ?? []
    let p = row.get(0).unwrap()
    io.println(p.name)

    let row2 = rows.get(0).unwrap()
    let p2 = row2.get(0).unwrap()
    io.println(p2.name)

    match rows.get(0) {
        Some(row3) => {
            let p3 = row3.get(0).unwrap()
            io.println(p3.name)
        }
        None => io.println("none")
    }
}
