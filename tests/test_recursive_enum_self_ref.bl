type Expr {
    Num(val: Int)
    Add(left: Expr, right: Expr)
    Block(stmts: List[Expr])
}

fn eval(e: Expr) -> Int {
    match e {
        Expr.Num(v) => v
        Expr.Add(l, r) => eval(l) + eval(r)
        Expr.Block(stmts) => {
            let mut result = 0
            for s in stmts {
                result = eval(s)
            }
            result
        }
    }
}

test "simple num" {
    let e = Expr.Num(42)
    assert_eq(eval(e), 42)
}

test "add two nums" {
    let e = Expr.Add(Expr.Num(3), Expr.Num(4))
    assert_eq(eval(e), 7)
}

test "nested add" {
    let e = Expr.Add(Expr.Num(1), Expr.Add(Expr.Num(2), Expr.Num(3)))
    assert_eq(eval(e), 6)
}

test "block with list" {
    let mut stmts: List[Expr] = []
    stmts.push(Expr.Num(10))
    stmts.push(Expr.Add(Expr.Num(3), Expr.Num(4)))
    let e = Expr.Block(stmts)
    assert_eq(eval(e), 7)
}

test "deeply nested" {
    let a = Expr.Add(Expr.Num(1), Expr.Num(2))
    let b = Expr.Add(Expr.Num(3), Expr.Num(4))
    let e = Expr.Add(a, b)
    assert_eq(eval(e), 10)
}
