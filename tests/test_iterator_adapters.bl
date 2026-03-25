test "map then filter then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mfc = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).collect()
    assert_eq(mfc.len(), 7)
    assert_eq(mfc.get(0).unwrap(), 8)
    assert_eq(mfc.get(6).unwrap(), 20)
}

test "map then filter then take" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mft = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 10 }).take(3).collect()
    assert_eq(mft.len(), 3)
    assert_eq(mft.get(0).unwrap(), 12)
    assert_eq(mft.get(1).unwrap(), 14)
    assert_eq(mft.get(2).unwrap(), 16)
}

test "filter then skip then count" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let fsc = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).skip(2).count()
    assert_eq(fsc, 3)
}

test "map then take then fold" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mtf = nums.map(fn(x: Int) -> Int { x * x }).take(4).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(mtf, 30)
}

test "filter then map then collect" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let fmc = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * 3 }).collect()
    assert_eq(fmc.len(), 5)
    assert_eq(fmc.get(0).unwrap(), 3)
    assert_eq(fmc.get(1).unwrap(), 9)
    assert_eq(fmc.get(2).unwrap(), 15)
    assert_eq(fmc.get(3).unwrap(), 21)
    assert_eq(fmc.get(4).unwrap(), 27)
}

test "skip then take windows into middle" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let st = nums.skip(3).take(4).collect()
    assert_eq(st.len(), 4)
    assert_eq(st.get(0).unwrap(), 4)
    assert_eq(st.get(1).unwrap(), 5)
    assert_eq(st.get(2).unwrap(), 6)
    assert_eq(st.get(3).unwrap(), 7)
}

test "take then skip" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let ts = nums.take(5).skip(2).collect()
    assert_eq(ts.len(), 3)
    assert_eq(ts.get(0).unwrap(), 3)
    assert_eq(ts.get(1).unwrap(), 4)
    assert_eq(ts.get(2).unwrap(), 5)
}

test "skip past end then take gives empty" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let sp_past = nums.skip(20).take(5).collect()
    assert_eq(sp_past.len(), 0)
}

test "filter then count" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    assert_eq(nums.filter(fn(x: Int) -> Bool { x > 5 }).count(), 5)
    assert_eq(nums.filter(fn(x: Int) -> Bool { x > 100 }).count(), 0)
}

test "map then fold sum of squares" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mf1 = nums.map(fn(x: Int) -> Int { x * x }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(mf1, 385)
}

test "map then fold product" {
    let mut small: List[Int] = []
    small.push(1)
    small.push(2)
    small.push(3)
    small.push(4)
    small.push(5)

    let mf2 = small.map(fn(x: Int) -> Int { x + 1 }).fold(1, fn(acc: Int, x: Int) -> Int { acc * x })
    assert_eq(mf2, 720)
}

test "map then any" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    assert(nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 50 }))
    assert(!nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 55 }))
}

test "map then all" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    assert(nums.map(fn(x: Int) -> Int { x + 100 }).all(fn(x: Int) -> Bool { x > 99 }))
    assert(!nums.map(fn(x: Int) -> Int { x * 2 }).all(fn(x: Int) -> Bool { x > 5 }))
}

test "filter then find" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let ff1 = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).find(fn(x: Int) -> Bool { x > 6 })
    assert_eq(ff1 ?? -1, 8)

    let ff2 = nums.filter(fn(x: Int) -> Bool { x < 3 }).find(fn(x: Int) -> Bool { x > 10 })
    assert_eq(ff2 ?? -1, -1)
}

test "chain then filter then count" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mut other: List[Int] = []
    other.push(11)
    other.push(12)
    other.push(13)
    other.push(14)
    other.push(15)

    let cfc = nums.chain(other).filter(fn(x: Int) -> Bool { x % 3 == 0 }).count()
    assert_eq(cfc, 5)
}

test "chain then map then take" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mut other: List[Int] = []
    other.push(11)
    other.push(12)
    other.push(13)
    other.push(14)
    other.push(15)

    let cmt = nums.chain(other).map(fn(x: Int) -> Int { x * 2 }).take(3).collect()
    assert_eq(cmt.len(), 3)
    assert_eq(cmt.get(0).unwrap(), 2)
    assert_eq(cmt.get(1).unwrap(), 4)
    assert_eq(cmt.get(2).unwrap(), 6)
}

test "4-way filter map skip take" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let fmst = nums.filter(fn(x: Int) -> Bool { x > 2 }).map(fn(x: Int) -> Int { x * 10 }).skip(2).take(3).collect()
    assert_eq(fmst.len(), 3)
    assert_eq(fmst.get(0).unwrap(), 50)
    assert_eq(fmst.get(1).unwrap(), 60)
    assert_eq(fmst.get(2).unwrap(), 70)
}

test "4-way filter map filter fold" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let fmff = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * x }).filter(fn(x: Int) -> Bool { x > 10 }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(fmff, 155)
}

test "empty list through adapter chains" {
    let mut empty: List[Int] = []

    let e1 = empty.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 0 }).collect()
    assert_eq(e1.len(), 0)

    let e2 = empty.filter(fn(x: Int) -> Bool { x > 0 }).skip(1).take(5).count()
    assert_eq(e2, 0)

    let e3 = empty.map(fn(x: Int) -> Int { x + 1 }).fold(42, fn(acc: Int, x: Int) -> Int { acc + x })
    assert_eq(e3, 42)

    assert(!empty.map(fn(x: Int) -> Int { x * 2 }).any(fn(x: Int) -> Bool { x == 1 }))
    assert(empty.map(fn(x: Int) -> Int { x * 2 }).all(fn(x: Int) -> Bool { x == 1 }))

    let e6 = empty.filter(fn(x: Int) -> Bool { x > 0 }).find(fn(x: Int) -> Bool { x == 1 })
    assert_eq(e6 ?? -1, -1)

    let mut empty2: List[Int] = []
    let e7 = empty.chain(empty2).filter(fn(x: Int) -> Bool { x > 0 }).count()
    assert_eq(e7, 0)
}

test "for_each after adapter chain" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let mut fe_sum = 0
    nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).map(fn(x: Int) -> Int { x * 10 }).for_each(fn(x: Int) {
        fe_sum = fe_sum + x
    })
    assert_eq(fe_sum, 300)
}

test "double map chain" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let dm = nums.map(fn(x: Int) -> Int { x + 1 }).map(fn(x: Int) -> Int { x * 2 }).take(5).collect()
    assert_eq(dm.len(), 5)
    assert_eq(dm.get(0).unwrap(), 4)
    assert_eq(dm.get(1).unwrap(), 6)
    assert_eq(dm.get(2).unwrap(), 8)
    assert_eq(dm.get(3).unwrap(), 10)
    assert_eq(dm.get(4).unwrap(), 12)
}

test "double filter chain" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let df = nums.filter(fn(x: Int) -> Bool { x > 3 }).filter(fn(x: Int) -> Bool { x < 8 }).collect()
    assert_eq(df.len(), 4)
    assert_eq(df.get(0).unwrap(), 4)
    assert_eq(df.get(1).unwrap(), 5)
    assert_eq(df.get(2).unwrap(), 6)
    assert_eq(df.get(3).unwrap(), 7)
}

test "for-in over adapter chain results" {
    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)
    nums.push(6)
    nums.push(7)
    nums.push(8)
    nums.push(9)
    nums.push(10)

    let chain_result = nums.filter(fn(x: Int) -> Bool { x > 7 }).map(fn(x: Int) -> Int { x * 100 })
    let mut for_sum = 0
    for v in chain_result {
        for_sum = for_sum + v
    }
    assert_eq(for_sum, 2700)
}
