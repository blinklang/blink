fn sum_list(nums: List[Float]) -> Float {
    let mut total = 0.0
    let mut i = 0
    while i < nums.len() {
        total = total + nums.get(i).unwrap()
        i = i + 1
    }
    total
}

test "float list literal boxing" {
    let vals = [1.5, 2.5, 3.0]
    let first = vals.get(0).unwrap()
    assert_eq(first, 1.5)
    let s = sum_list(vals)
    assert_eq(s, 7.0)
}

test "for-in over List[Float]" {
    let vals = [1.5, 2.5, 3.0]
    let mut for_sum = 0.0
    for v in vals {
        for_sum = for_sum + v
    }
    assert_eq(for_sum, 7.0)
}

test "Map[Str, Float] set/get round-trip" {
    let mut prices: Map[Str, Float] = Map()
    prices.set("apple", 1.99)
    prices.set("banana", 0.75)
    let apple = prices.get("apple")
    assert_eq(apple, 1.99)
    let banana = prices.get("banana")
    assert_eq(banana, 0.75)
}
