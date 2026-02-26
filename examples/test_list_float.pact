fn sum_floats(nums: List[Float]) -> Float {
    let mut total = 0.0
    let mut i = 0
    while i < nums.len() {
        total = total + nums.unsafe_get(i)
        i = i + 1
    }
    total
}

fn main() {
    let mut pass = true

    // Test List[Float] in regular fn
    let mut vals: List[Float] = []
    vals.push(1.5)
    vals.push(2.5)
    vals.push(3.0)
    let s = sum_floats(vals)
    if s != 7.0 {
        io.println("FAIL: sum_floats expected 7.0, got {s}")
        pass = false
    }

    // Test List[Float] via variable alias
    let alias = vals
    let first = alias.unsafe_get(0)
    if first != 1.5 {
        io.println("FAIL: alias.get(0) expected 1.5, got {first}")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
