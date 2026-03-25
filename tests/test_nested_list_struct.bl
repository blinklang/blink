type Person { name: Str, age: Int }

test "nested list with struct elements" {
    let mut rows: List[List[Person]] = []
    let inner: List[Person] = [Person { name: "Alice", age: 30 }]
    rows.push(inner)

    for row in rows {
        let p = row.get(0).unwrap()
        assert_eq(p.name, "Alice")
    }
}
