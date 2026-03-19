type Item {
    name: Str
    value: Int
}

type MyError {
    NotFound(msg: Str)
}

fn get_result() -> Result[Item, MyError] {
    Ok(Item { name: "test", value: 42 })
}

fn get_plain() -> Int {
    7
}

fn make_list() -> List[Int] {
    let items: List[Int] = []
    items.push(1)
    items.push(2)
    items
}

test "struct state leak from Result into List" {
    let r = get_result()
    let item = r.unwrap()
    assert_eq(item.name, "test")
    let x = get_plain()
    let nums = make_list()
    nums.push(x)
    assert_eq(nums.len(), 3)
    assert_eq(nums.get(0).unwrap(), 1)
    assert_eq(nums.get(1).unwrap(), 2)
    assert_eq(nums.get(2).unwrap(), 7)
}

test "state leak after Result call into push" {
    let r = get_result()
    let val = r.unwrap()
    let x = get_plain()
    let items: List[Int] = []
    items.push(x)
    items.push(val.value)
    assert_eq(items.len(), 2)
    assert_eq(items.get(0).unwrap(), 7)
    assert_eq(items.get(1).unwrap(), 42)
}
