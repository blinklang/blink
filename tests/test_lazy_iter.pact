test "map then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let doubled = nums.map(fn(x: Int) -> Int { x * 2 }).collect()
    assert_eq(doubled.len(), 5)
    assert_eq(doubled.get(0).unwrap(), 2)
}

test "filter then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let evens = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).collect()
    assert_eq(evens.len(), 2)
}

test "chain adapters then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let result = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).collect()
    assert_eq(result.len(), 2)
}

test "chain adapters then fold" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let sum = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(sum, 18)
}

test "take then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let first3 = nums.take(3).collect()
    assert_eq(first3.len(), 3)
}

test "skip then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let after2 = nums.skip(2).collect()
    assert_eq(after2.len(), 3)
}

test "4-way chain map filter take collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let chain4 = nums.map(fn(x: Int) -> Int { x * 10 }).filter(fn(x: Int) -> Bool { x > 20 }).take(2).collect()
    assert_eq(chain4.len(), 2)
    assert_eq(chain4.get(0).unwrap(), 30)
}

test "count on iterator" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    let c = nums.filter(fn(x: Int) -> Bool { x > 3 }).count()
    assert_eq(c, 2)
}

test "any on iterator" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    assert(nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 30 }))
}

test "all on iterator" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    assert(nums.filter(fn(x: Int) -> Bool { x > 2 }).all(fn(x: Int) -> Bool { x > 2 }))
}
