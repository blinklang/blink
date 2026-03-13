fn expand(x: Int) -> List[Int] {
    let mut result: List[Int] = []
    let mut i = 0
    while i < x {
        result.push(x)
        i = i + 1
    }
    result
}

test "flat_map expand" {
    let nums: List[Int] = [1, 2, 3]
    let expanded = nums.flat_map(fn(x: Int) -> List[Int] { expand(x) }).collect()
    assert_eq(expanded.len(), 6)
    assert_eq(expanded.get(0).unwrap(), 1)
    assert_eq(expanded.get(1).unwrap(), 2)
    assert_eq(expanded.get(2).unwrap(), 2)
    assert_eq(expanded.get(3).unwrap(), 3)
    assert_eq(expanded.get(4).unwrap(), 3)
    assert_eq(expanded.get(5).unwrap(), 3)
}
