fn sum_floats(nums: List[Float]) -> Float {
    let mut total = 0.0
    let mut i = 0
    while i < nums.len() {
        total = total + nums.get(i).unwrap()
        i = i + 1
    }
    total
}

test "List[Float] in regular fn" {
    let mut vals: List[Float] = []
    vals.push(1.5)
    vals.push(2.5)
    vals.push(3.0)
    let s = sum_floats(vals)
    assert_eq(s, 7.0)
}

test "List[Float] via variable alias" {
    let mut vals: List[Float] = []
    vals.push(1.5)
    vals.push(2.5)
    vals.push(3.0)
    let alias = vals
    let first = alias.get(0).unwrap()
    assert_eq(first, 1.5)
}
