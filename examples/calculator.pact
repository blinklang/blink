// calculator.pact — Refinement types + contracts
//
// Demonstrates: @requires, @ensures, @where, refinement types,
//               recursive enum (ADT), pattern matching, pure functions

/// A non-zero integer, enforced by the type system.
type NonZero = Int @where(self != 0)

/// Arithmetic expressions as a recursive ADT.
type Expr {
    Lit(value: Float)
    Add(left: Expr, right: Expr)
    Sub(left: Expr, right: Expr)
    Mul(left: Expr, right: Expr)
    Div(left: Expr, right: Expr)
    Neg(inner: Expr)
}

type CalcError {
    DivisionByZero
}

/// Evaluate an expression tree.
fn eval(expr: Expr) -> Result[Float, CalcError] {
    match expr {
        Lit(v) => Ok(v)
        Add(l, r) => Ok(eval(l)? + eval(r)?)
        Sub(l, r) => Ok(eval(l)? - eval(r)?)
        Mul(l, r) => Ok(eval(l)? * eval(r)?)
        Div(l, r) => {
            let divisor = eval(r)?
            if divisor == 0.0 {
                Err(CalcError.DivisionByZero)
            } else {
                Ok(eval(l)? / divisor)
            }
        }
        Neg(inner) => Ok(-eval(inner)?)
    }
}

/// Safe integer division with a refinement-typed divisor.
@requires(a >= 0)
@ensures(result >= 0)
fn safe_div(a: Int, b: NonZero) -> Int {
    a / b
}

/// Absolute value with a postcondition.
@ensures(result >= 0)
fn abs(n: Int) -> Int {
    if n < 0 { -n } else { n }
}

/// Clamp a value to a range.
@requires(lo <= hi)
@ensures(result >= lo && result <= hi)
fn clamp(value: Int, lo: Int, hi: Int) -> Int {
    if value < lo { lo }
    else if value > hi { hi }
    else { value }
}

fn main() {
    // (2 + 3) * -4 = -20
    let expr = Expr.Mul(
        Expr.Add(Expr.Lit(2.0), Expr.Lit(3.0))
        Expr.Neg(Expr.Lit(4.0))
    )

    match eval(expr) {
        Ok(result) => io.println("Result: {result}")
        Err(CalcError.DivisionByZero) => io.println("Error: division by zero")
    }

    // Refinement types in action
    io.println("safe_div(10, 3) = {safe_div(10, 3)}")
    io.println("abs(-42) = {abs(-42)}")
    io.println("clamp(150, 0, 100) = {clamp(150, 0, 100)}")
}

test "eval addition" {
    let expr = Expr.Add(Expr.Lit(2.0), Expr.Lit(3.0))
    assert_eq(eval(expr), Ok(5.0))
}

test "eval division by zero" {
    let expr = Expr.Div(Expr.Lit(1.0), Expr.Lit(0.0))
    assert_eq(eval(expr), Err(CalcError.DivisionByZero))
}

test "eval nested expression" {
    // (10 - 4) / 2 = 3
    let expr = Expr.Div(
        Expr.Sub(Expr.Lit(10.0), Expr.Lit(4.0))
        Expr.Lit(2.0)
    )
    assert_eq(eval(expr), Ok(3.0))
}
