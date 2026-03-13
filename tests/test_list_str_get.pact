test "list str get with type annotation" {
    let names: List[Str] = ["alice", "bob", "charlie"]
    let first = names.get(0).unwrap()
    assert_eq(first, "alice")
    assert_eq(names.get(1).unwrap(), "bob")
    assert_eq(names.get(2).unwrap(), "charlie")
}

test "list str get in interpolation" {
    let names: List[Str] = ["alice", "bob"]
    let msg = "hello {names.get(0).unwrap()}"
    assert_eq(msg, "hello alice")
    let msg2 = "{names.get(0).unwrap()} and {names.get(1).unwrap()}"
    assert_eq(msg2, "alice and bob")
}

test "list str get inferred from literal" {
    let items = ["red", "green", "blue"]
    assert_eq(items.get(0).unwrap(), "red")
    let msg = "color: {items.get(1).unwrap()}"
    assert_eq(msg, "color: green")
}

test "list str push then get" {
    let mut words: List[Str] = []
    words.push("hello")
    words.push("world")
    assert_eq(words.get(0).unwrap(), "hello")
    let msg = "say: {words.get(1).unwrap()}"
    assert_eq(msg, "say: world")
}

test "list str get in concat" {
    let names: List[Str] = ["alice", "bob"]
    let greeting = "Hi, ".concat(names.get(0).unwrap())
    assert_eq(greeting, "Hi, alice")
}
