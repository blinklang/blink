type Callback {
    name: Str
    action: fn(Int) -> Int
}

type Transformer {
    label: Str
    transform: fn(Str) -> Str
}

type MathOp {
    name: Str
    compute: fn(Int, Int) -> Int
}

type MathOpList {
    name: Str
    compute: fn(Int, Int) -> Int
}

test "closure field basic" {
    let cb = Callback { name: "doubler", action: fn(x: Int) -> Int { x * 2 } }
    assert_eq(cb.name, "doubler")
    assert_eq(cb.action(21), 42)
}

test "closure field string" {
    let t = Transformer { label: "upper", transform: fn(s: Str) -> Str { "transformed: {s}" } }
    assert_eq(t.label, "upper")
    assert_eq(t.transform("hello"), "transformed: hello")
}

test "closure field multi param" {
    let add = MathOp { name: "add", compute: fn(a: Int, b: Int) -> Int { a + b } }
    assert_eq(add.compute(3, 4), 7)

    let mul = MathOp { name: "mul", compute: fn(a: Int, b: Int) -> Int { a * b } }
    assert_eq(mul.compute(5, 6), 30)
}

test "closure field in list" {
    let ops: List[MathOpList] = []
    ops.push(MathOpList { name: "add", compute: fn(a: Int, b: Int) -> Int { a + b } })
    ops.push(MathOpList { name: "sub", compute: fn(a: Int, b: Int) -> Int { a - b } })

    let op0 = ops.get(0).unwrap()
    assert_eq(op0.name, "add")
    assert_eq(op0.compute(10, 3), 13)

    let op1 = ops.get(1).unwrap()
    assert_eq(op1.name, "sub")
    assert_eq(op1.compute(10, 3), 7)
}
