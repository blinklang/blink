test "chain combines two lists" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)

    let mut b: List[Int] = []
    b.push(4)
    b.push(5)

    let chained = a.chain(b).collect()
    assert_eq(chained.len(), 5)
    assert_eq(chained.get(0).unwrap(), 1)
    assert_eq(chained.get(1).unwrap(), 2)
    assert_eq(chained.get(2).unwrap(), 3)
    assert_eq(chained.get(3).unwrap(), 4)
    assert_eq(chained.get(4).unwrap(), 5)
}

test "chain with empty list on left" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)
    let mut empty: List[Int] = []

    let chain_empty = empty.chain(a).collect()
    assert_eq(chain_empty.len(), 3)
}

test "chain with empty list on right" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)
    let mut empty: List[Int] = []

    let chain_with_empty = a.chain(empty).collect()
    assert_eq(chain_with_empty.len(), 3)
}

test "chain then fold sums all elements" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)

    let mut b: List[Int] = []
    b.push(4)
    b.push(5)

    let chain_sum = a.chain(b).fold(0, fn(acc: Int, v: Int) -> Int { acc + v })
    assert_eq(chain_sum, 15)
}

test "chain then count" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)

    let mut b: List[Int] = []
    b.push(4)
    b.push(5)

    let chain_count = a.chain(b).count()
    assert_eq(chain_count, 5)
}

test "enumerate produces index-value pairs" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)

    let enumerated = a.enumerate()
    assert_eq(enumerated.len(), 3)

    let pair0 = enumerated.get(0).unwrap()
    assert_eq(pair0.get(0).unwrap(), 0)
    assert_eq(pair0.get(1).unwrap(), 1)

    let pair1 = enumerated.get(1).unwrap()
    assert_eq(pair1.get(0).unwrap(), 1)
    assert_eq(pair1.get(1).unwrap(), 2)

    let pair2 = enumerated.get(2).unwrap()
    assert_eq(pair2.get(0).unwrap(), 2)
    assert_eq(pair2.get(1).unwrap(), 3)
}

test "enumerate on empty list" {
    let mut empty: List[Int] = []
    let empty_enum = empty.enumerate()
    assert_eq(empty_enum.len(), 0)
}

test "zip pairs elements from two lists" {
    let mut x: List[Int] = []
    x.push(10)
    x.push(20)
    x.push(30)

    let mut y: List[Int] = []
    y.push(1)
    y.push(2)
    y.push(3)

    let zipped = x.zip(y)
    assert_eq(zipped.len(), 3)

    let zp0 = zipped.get(0).unwrap()
    assert_eq(zp0.get(0).unwrap(), 10)
    assert_eq(zp0.get(1).unwrap(), 1)

    let zp2 = zipped.get(2).unwrap()
    assert_eq(zp2.get(0).unwrap(), 30)
    assert_eq(zp2.get(1).unwrap(), 3)
}

test "zip truncates to shorter list" {
    let mut x: List[Int] = []
    x.push(10)
    x.push(20)
    x.push(30)

    let mut shorter: List[Int] = []
    shorter.push(100)
    shorter.push(200)

    let zip_short = x.zip(shorter)
    assert_eq(zip_short.len(), 2)

    let zps0 = zip_short.get(0).unwrap()
    assert_eq(zps0.get(0).unwrap(), 10)
    assert_eq(zps0.get(1).unwrap(), 100)
}

test "zip with empty list produces empty" {
    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)
    let mut empty: List[Int] = []

    let zip_empty = a.zip(empty)
    assert_eq(zip_empty.len(), 0)
}
