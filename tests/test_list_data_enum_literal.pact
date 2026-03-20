type Value {
    Text(s: Str)
    Num(n: Int)
    Arr(items: List[Value])
    Nil
}

fn describe(v: Value) -> Str {
    match v {
        Value.Text(s) => "text({s})"
        Value.Num(n) => "num({n})"
        Value.Arr(items) => "arr({items.len()})"
        Value.Nil => "nil"
    }
}

test "data enum list literal" {
    let items = [Value.Text("hello"), Value.Num(42)]
    assert_eq(items.len(), 2)
    assert_eq(describe(items.get(0).unwrap()), "text(hello)")
    assert_eq(describe(items.get(1).unwrap()), "num(42)")
}

test "nested data enum list literal" {
    let inner = [Value.Num(1), Value.Num(2)]
    let outer = [Value.Arr(inner), Value.Nil]
    assert_eq(outer.len(), 2)
    assert_eq(describe(outer.get(0).unwrap()), "arr(2)")
    assert_eq(describe(outer.get(1).unwrap()), "nil")
}
