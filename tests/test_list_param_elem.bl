type Item {
    name: Str
    value: Int
}

fn get_first_name(items: List[Item]) -> Str {
    let first = items.get(0).unwrap()
    first.name
}

fn sum_values(items: List[Item]) -> Int {
    let mut total = 0
    let mut i = 0
    while i < items.len() {
        let item = items.get(i).unwrap()
        total = total + item.value
        i = i + 1
    }
    total
}

fn main() {
    let mut items: List[Item] = []
    items.push(Item { name: "alpha", value: 10 })
    items.push(Item { name: "beta", value: 20 })
    items.push(Item { name: "gamma", value: 30 })

    let name = get_first_name(items)
    assert_eq(name, "alpha")

    let total = sum_values(items)
    assert_eq(total, 60)

    io.println("PASS: List[Struct] function parameters preserve element type")
}
