fn check(cond: Int, label: Str) {
    if cond != 0 {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label}")
    }
}

type Callback {
    name: Str
    action: fn(Int) -> Int
}

fn test_closure_field_basic() {
    io.println("--- closure field basic ---")
    let cb = Callback { name: "doubler", action: fn(x: Int) -> Int { x * 2 } }
    check(cb.name == "doubler", "name field")
    let result = cb.action(21)
    check(result == 42, "closure call returns 42")
}

type Transformer {
    label: Str
    transform: fn(Str) -> Str
}

fn test_closure_field_string() {
    io.println("--- closure field string ---")
    let t = Transformer { label: "upper", transform: fn(s: Str) -> Str { "transformed: {s}" } }
    check(t.label == "upper", "label field")
    let out = t.transform("hello")
    check(out == "transformed: hello", "string closure works")
}

type MathOp {
    name: Str
    compute: fn(Int, Int) -> Int
}

fn test_closure_field_multi_param() {
    io.println("--- closure field multi param ---")
    let add = MathOp { name: "add", compute: fn(a: Int, b: Int) -> Int { a + b } }
    check(add.compute(3, 4) == 7, "add closure 3+4=7")

    let mul = MathOp { name: "mul", compute: fn(a: Int, b: Int) -> Int { a * b } }
    check(mul.compute(5, 6) == 30, "mul closure 5*6=30")
}

type MathOpList {
    name: Str
    compute: fn(Int, Int) -> Int
}

fn test_closure_field_in_list() {
    io.println("--- closure field in list ---")
    let ops: List[MathOpList] = []
    ops.push(MathOpList { name: "add", compute: fn(a: Int, b: Int) -> Int { a + b } })
    ops.push(MathOpList { name: "sub", compute: fn(a: Int, b: Int) -> Int { a - b } })

    let op0 = ops.unsafe_get(0)
    check(op0.name == "add", "list item 0 name")
    check(op0.compute(10, 3) == 13, "list item 0 compute")

    let op1 = ops.unsafe_get(1)
    check(op1.name == "sub", "list item 1 name")
    check(op1.compute(10, 3) == 7, "list item 1 compute")
}

fn main() {
    io.println("=== closure struct tests ===")
    test_closure_field_basic()
    test_closure_field_string()
    test_closure_field_multi_param()
    test_closure_field_in_list()
    io.println("=== done ===")
}
