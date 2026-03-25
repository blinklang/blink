test "list_map: double ints" {
    let doubled = list_map([1, 2, 3], fn(x: Int) -> Int { x * 2 })
    assert_eq(doubled.len(), 3)
    assert_eq(doubled.get(0).unwrap(), 2)
    assert_eq(doubled.get(1).unwrap(), 4)
    assert_eq(doubled.get(2).unwrap(), 6)
}

test "list_filter: keep evens" {
    let evens = list_filter([1, 2, 3, 4, 5, 6], fn(x: Int) -> Bool { x % 2 == 0 })
    assert_eq(evens.len(), 3)
    assert_eq(evens.get(0).unwrap(), 2)
}

test "list_fold: sum" {
    let sum = list_fold([1, 2, 3, 4], 0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(sum, 10)
}

test "list_any and list_all" {
    assert_eq(list_any([1, -2, 3], fn(x: Int) -> Bool { x < 0 }), true)
    assert_eq(list_any([1, 2, 3], fn(x: Int) -> Bool { x < 0 }), false)
    assert_eq(list_all([1, 2, 3], fn(x: Int) -> Bool { x > 0 }), true)
    assert_eq(list_all([1, -2, 3], fn(x: Int) -> Bool { x > 0 }), false)
}

test "list_concat" {
    let result = list_concat([1, 2], [3, 4])
    assert_eq(result.len(), 4)
    assert_eq(result.get(0).unwrap(), 1)
    assert_eq(result.get(3).unwrap(), 4)
}

test "list_slice" {
    let result = list_slice([10, 20, 30, 40, 50], 1, 4)
    assert_eq(result.len(), 3)
    assert_eq(result.get(0).unwrap(), 20)
    assert_eq(result.get(2).unwrap(), 40)
}

test "list_for_each side effect" {
    let mut sum = 0
    list_for_each([10, 20, 30], fn(x: Int) -> Void { sum = sum + x })
    assert_eq(sum, 60)
}

test "list_map with capture" {
    let factor = 3
    let tripled = list_map([1, 2, 3], fn(x: Int) -> Int { x * factor })
    assert_eq(tripled.get(0).unwrap(), 3)
    assert_eq(tripled.get(2).unwrap(), 9)
}

test "list_fold: string concat" {
    let joined = list_fold([1, 2, 3], "", fn(acc: Str, x: Int) -> Str {
        if acc == "" { "{x}" } else { "{acc},{x}" }
    })
    assert_eq(joined, "1,2,3")
}

test "list_slice: out of bounds clamped" {
    let result = list_slice([1, 2, 3], 1, 100)
    assert_eq(result.len(), 2)
    assert_eq(result.get(0).unwrap(), 2)
}

test "method syntax: .fold() via stdlib" {
    let nums: List[Int] = [1, 2, 3, 4]
    let sum = nums.fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(sum, 10)
}

test "method syntax: .any() and .all() via stdlib" {
    let a: List[Int] = [1, -2, 3]
    let b: List[Int] = [1, 2, 3]
    assert_eq(a.any(fn(x: Int) -> Bool { x < 0 }), true)
    assert_eq(b.all(fn(x: Int) -> Bool { x > 0 }), true)
}

test "method syntax: .for_each() via stdlib" {
    let mut total = 0
    let nums: List[Int] = [5, 10, 15]
    nums.for_each(fn(x: Int) -> Void { total = total + x })
    assert_eq(total, 30)
}

test "list_filter then list_map chained" {
    let items = [1, 2, 3, 4, 5, 6]
    let evens = list_filter(items, fn(x: Int) -> Bool { x % 2 == 0 })
    let doubled = list_map(evens, fn(x: Int) -> Int { x * 2 })
    assert_eq(doubled.len(), 3)
    assert_eq(doubled.get(0).unwrap(), 4)
    assert_eq(doubled.get(1).unwrap(), 8)
    assert_eq(doubled.get(2).unwrap(), 12)
}
