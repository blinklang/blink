test "count" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    assert_eq(nums.count(), 5)

    let mut empty: List[Int] = []
    assert_eq(empty.count(), 0)
}

test "collect preserves length" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let collected = nums.collect()
    assert_eq(collected.len(), 5)
}

test "for_each" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let mut fe_sum = 0
    nums.for_each(fn(x: Int) {
        fe_sum = fe_sum + x
    })
    assert_eq(fe_sum, 15)
}

test "any" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    let mut empty: List[Int] = []

    assert(nums.any(fn(x: Int) -> Bool { x == 3 }))
    assert(!nums.any(fn(x: Int) -> Bool { x == 10 }))
    assert(!empty.any(fn(x: Int) -> Bool { x == 1 }))
}

test "all" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    let mut empty: List[Int] = []

    assert(nums.all(fn(x: Int) -> Bool { x > 0 }))
    assert(!nums.all(fn(x: Int) -> Bool { x < 3 }))
    assert(empty.all(fn(x: Int) -> Bool { x == 1 }))
}

test "find" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let found = nums.find(fn(x: Int) -> Bool { x > 3 })
    assert_eq(found ?? -1, 4)

    let not_found = nums.find(fn(x: Int) -> Bool { x > 100 })
    assert_eq(not_found ?? -1, -1)
}

test "fold" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    let mut empty: List[Int] = []

    let sum = nums.fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(sum, 15)

    let product = nums.fold(1, fn(acc: Int, x: Int) -> Int { acc * x })
    assert_eq(product, 120)

    let empty_fold = empty.fold(42, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(empty_fold, 42)
}

test "map" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    let mut empty: List[Int] = []

    let doubled = nums.map(fn(x: Int) -> Int { x * 2 }).collect()
    assert_eq(doubled.len(), 5)
    assert_eq(doubled.get(0).unwrap(), 2)
    assert_eq(doubled.get(1).unwrap(), 4)
    assert_eq(doubled.get(2).unwrap(), 6)
    assert_eq(doubled.get(3).unwrap(), 8)
    assert_eq(doubled.get(4).unwrap(), 10)

    let empty_map = empty.map(fn(x: Int) -> Int { x * 2 }).collect()
    assert_eq(empty_map.len(), 0)
}

test "filter" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let evens = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).collect()
    assert_eq(evens.len(), 2)
    assert_eq(evens.get(0).unwrap(), 2)
    assert_eq(evens.get(1).unwrap(), 4)

    let none_match = nums.filter(fn(x: Int) -> Bool { x > 100 }).collect()
    assert_eq(none_match.len(), 0)

    let all_match = nums.filter(fn(x: Int) -> Bool { x > 0 }).collect()
    assert_eq(all_match.len(), 5)
}

test "take" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let first3 = nums.take(3).collect()
    assert_eq(first3.len(), 3)
    assert_eq(first3.get(0).unwrap(), 1)
    assert_eq(first3.get(1).unwrap(), 2)
    assert_eq(first3.get(2).unwrap(), 3)

    let take_more = nums.take(10).collect()
    assert_eq(take_more.len(), 5)

    let take_zero = nums.take(0).collect()
    assert_eq(take_zero.len(), 0)
}

test "skip" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let after2 = nums.skip(2).collect()
    assert_eq(after2.len(), 3)
    assert_eq(after2.get(0).unwrap(), 3)
    assert_eq(after2.get(1).unwrap(), 4)
    assert_eq(after2.get(2).unwrap(), 5)

    let skip_all = nums.skip(10).collect()
    assert_eq(skip_all.len(), 0)

    let skip_zero = nums.skip(0).collect()
    assert_eq(skip_zero.len(), 5)
}

test "chaining filter map" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let chain1 = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * 10 }).collect()
    assert_eq(chain1.len(), 3)
    assert_eq(chain1.get(0).unwrap(), 10)
    assert_eq(chain1.get(1).unwrap(), 30)
    assert_eq(chain1.get(2).unwrap(), 50)

    let chain2 = nums.map(fn(x: Int) -> Int { x * x }).filter(fn(x: Int) -> Bool { x > 5 }).collect()
    assert_eq(chain2.len(), 3)
    assert_eq(chain2.get(0).unwrap(), 9)
    assert_eq(chain2.get(1).unwrap(), 16)
    assert_eq(chain2.get(2).unwrap(), 25)

    let chain3 = nums.filter(fn(x: Int) -> Bool { x > 2 }).take(2).collect()
    assert_eq(chain3.len(), 2)
    assert_eq(chain3.get(0).unwrap(), 3)
    assert_eq(chain3.get(1).unwrap(), 4)
}

test "chaining skip take fold" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let chain4_sum = nums.skip(1).take(3).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(chain4_sum, 9)
}

test "chaining map any and filter all" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    assert(nums.map(fn(x: Int) -> Int { x + 10 }).any(fn(x: Int) -> Bool { x == 13 }))
    assert(nums.filter(fn(x: Int) -> Bool { x > 2 }).all(fn(x: Int) -> Bool { x > 2 }))
}

test "chaining filter count" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    assert_eq(nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).count(), 2)
}

test "for-in over adapter results" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let mapped = nums.map(fn(x: Int) -> Int { x * 3 })
    let mut for_map_sum = 0
    for x in mapped {
        for_map_sum = for_map_sum + x
    }
    assert_eq(for_map_sum, 45)

    let filtered = nums.filter(fn(x: Int) -> Bool { x > 3 })
    let mut for_filt_sum = 0
    for x in filtered {
        for_filt_sum = for_filt_sum + x
    }
    assert_eq(for_filt_sum, 9)
}
