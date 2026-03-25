fn main() {
}

fn pair() -> (Int, Str) {
    (42, "hello")
}

fn sum_pair(p: (Int, Int)) -> Int {
    p.0 + p.1
}

fn triple() -> (Int, Str, Int) {
    (1, "mid", 99)
}

fn quad() -> (Int, Int, Int, Int) {
    (10, 20, 30, 40)
}

test "basic tuple creation and field access" {
    let t = (1, "hello")
    assert(t.0 == 1)
    assert(t.1 == "hello")
}

test "tuple with 3 elements" {
    let t = (10, "mid", 99)
    assert(t.0 == 10)
    assert(t.1 == "mid")
    assert(t.2 == 99)
}

test "tuple with 4 elements" {
    let t = (1, 2, 3, 4)
    assert(t.0 == 1)
    assert(t.1 == 2)
    assert(t.2 == 3)
    assert(t.3 == 4)
}

test "tuple function return" {
    let r = pair()
    assert(r.0 == 42)
    assert(r.1 == "hello")
}

test "tuple function parameter" {
    let result = sum_pair((3, 7))
    assert(result == 10)
}

test "triple return" {
    let t = triple()
    assert(t.0 == 1)
    assert(t.1 == "mid")
    assert(t.2 == 99)
}

test "quad return" {
    let q = quad()
    assert(q.0 == 10)
    assert(q.1 == 20)
    assert(q.2 == 30)
    assert(q.3 == 40)
}

test "tuple in match" {
    let x = 1
    let y = 2
    let result = match (x, y) {
        (0, 0) => "origin"
        (1, 2) => "one-two"
        _ => "other"
    }
    assert(result == "one-two")
}

test "tuple with computed values" {
    let a = 10
    let b = 20
    let t = (a + b, a * b)
    assert(t.0 == 30)
    assert(t.1 == 200)
}

test "nested tuple via intermediate" {
    let inner = (1, 2)
    let outer = (inner, "label")
    let first = outer.0
    assert(first.0 == 1)
    assert(first.1 == 2)
    assert(outer.1 == "label")
}

test "multiple tuple arities in one program" {
    let t2 = (1, 2)
    let t3 = (1, 2, 3)
    let t4 = (1, 2, 3, 4)
    assert(t2.0 + t2.1 == 3)
    assert(t3.0 + t3.1 + t3.2 == 6)
    assert(t4.0 + t4.1 + t4.2 + t4.3 == 10)
}
