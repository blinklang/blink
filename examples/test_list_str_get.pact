test "list str get with type annotation" {
    let names: List[Str] = ["alice", "bob", "charlie"]
    let first = names.unsafe_get(0)
    assert_eq(first, "alice")
    assert_eq(names.unsafe_get(1), "bob")
    assert_eq(names.unsafe_get(2), "charlie")
}

test "list str get in interpolation" {
    let names: List[Str] = ["alice", "bob"]
    let msg = "hello {names.unsafe_get(0)}"
    assert_eq(msg, "hello alice")
    let msg2 = "{names.unsafe_get(0)} and {names.unsafe_get(1)}"
    assert_eq(msg2, "alice and bob")
}

test "list str get inferred from literal" {
    let items = ["red", "green", "blue"]
    assert_eq(items.unsafe_get(0), "red")
    let msg = "color: {items.unsafe_get(1)}"
    assert_eq(msg, "color: green")
}

test "list str push then get" {
    let mut words: List[Str] = []
    words.push("hello")
    words.push("world")
    assert_eq(words.unsafe_get(0), "hello")
    let msg = "say: {words.unsafe_get(1)}"
    assert_eq(msg, "say: world")
}

test "list str get in concat" {
    let names: List[Str] = ["alice", "bob"]
    let greeting = "Hi, ".concat(names.unsafe_get(0))
    assert_eq(greeting, "Hi, alice")
}
