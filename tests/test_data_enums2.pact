type Expr {
    Lit(value: Int)
    Add(left: Int, right: Int)
    Neg(inner: Int)
}

fn eval(e: Expr) -> Int {
    match e {
        Expr.Lit(v) => v
        Expr.Add(l, r) => l + r
        Expr.Neg(i) => 0 - i
    }
}

test "eval literal" {
    assert_eq(eval(Expr.Lit(42)), 42)
}

test "eval add" {
    assert_eq(eval(Expr.Add(10, 20)), 30)
}

test "eval neg" {
    assert_eq(eval(Expr.Neg(7)), -7)
}

test "bare variant constructor" {
    let d = Lit(100)
    assert_eq(eval(d), 100)
}
