fn apply(f: fn(Int) -> Int, x: Int) -> Int {
    f(x)
}

fn apply_twice(f: fn(Int) -> Int, x: Int) -> Int {
    f(f(x))
}

fn apply_then_add(f: fn(Int) -> Int, x: Int, extra: Int) -> Int {
    f(x) + extra
}

test "basic HOF: pass named closure to function" {
    let dbl = fn(x: Int) -> Int { x * 2 }
    assert_eq(apply(dbl, 5), 10)
}

test "pass inline anonymous closure directly" {
    assert_eq(apply(fn(x: Int) -> Int { x + 3 }, 10), 13)
}

test "apply a closure twice" {
    let dbl = fn(x: Int) -> Int { x * 2 }
    assert_eq(apply_twice(dbl, 3), 12)
}

test "apply with extra computation in HOF body" {
    let triple = fn(x: Int) -> Int { x * 3 }
    assert_eq(apply_then_add(triple, 4, 1), 13)
}

test "closure with single capture passed to HOF" {
    let offset = 100
    let add_offset = fn(x: Int) -> Int { x + offset }
    assert_eq(apply(add_offset, 5), 105)
}

test "closure with multiple captures passed to HOF" {
    let base = 10
    let multiplier = 3
    let transform = fn(x: Int) -> Int { (x + base) * multiplier }
    assert_eq(apply(transform, 5), 45)
}

test "apply-twice with a capturing closure" {
    let step = 10
    let add_step = fn(x: Int) -> Int { x + step }
    assert_eq(apply_twice(add_step, 0), 20)
}

test "different closures reuse the same HOF" {
    let negate = fn(x: Int) -> Int { 0 - x }
    let square = fn(x: Int) -> Int { x * x }
    assert_eq(apply(negate, 42), -42)
    assert_eq(apply(square, 7), 49)
}

test "chain HOF calls" {
    let dbl = fn(x: Int) -> Int { x * 2 }
    let inc = fn(x: Int) -> Int { x + 1 }
    let r = apply(dbl, apply(inc, 4))
    assert_eq(r, 10)
}

test "pass same capturing closure to different HOFs" {
    let bias = 7
    let add_bias = fn(x: Int) -> Int { x + bias }
    assert_eq(apply(add_bias, 3), 10)
    assert_eq(apply_twice(add_bias, 0), 14)
    assert_eq(apply_then_add(add_bias, 10, 3), 20)
}

test "inline closure with capture passed to HOF" {
    let factor = 5
    assert_eq(apply(fn(x: Int) -> Int { x * factor }, 6), 30)
}

test "deeply nested apply" {
    let dbl = fn(x: Int) -> Int { x * 2 }
    assert_eq(apply(dbl, apply(dbl, apply(dbl, 1))), 8)
}
