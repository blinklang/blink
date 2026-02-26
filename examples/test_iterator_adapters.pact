fn main() {
    io.println("=== iterator adapter chain tests ===")
    let mut pass = 0
    let mut fail = 0

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

    let mut empty: List[Int] = []

    // === 3-way adapter chains ===
    io.println("--- 3-way adapter chains ---")

    // map -> filter -> collect: double, keep > 6
    let mfc = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).collect()
    // doubles: [2,4,6,8,10,12,14,16,18,20], filter >6: [8,10,12,14,16,18,20]
    if mfc.len() == 7 {
        io.println("ok: map(*2).filter(>6).collect len = 7")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*2).filter(>6).collect len = {mfc.len()}, expected 7")
        fail = fail + 1
    }
    if mfc.unsafe_get(0) == 8 && mfc.unsafe_get(6) == 20 {
        io.println("ok: map(*2).filter(>6).collect values correct")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*2).filter(>6).collect values wrong, first={mfc.unsafe_get(0)}, last={mfc.unsafe_get(6)}")
        fail = fail + 1
    }

    // map -> filter -> take: double, keep > 10, take first 3
    let mft = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 10 }).take(3).collect()
    // doubles: [2,4,6,8,10,12,14,16,18,20], filter >10: [12,14,16,18,20], take 3: [12,14,16]
    let mut mft_ok = 1
    if mft.len() != 3 { mft_ok = 0 }
    if mft.unsafe_get(0) != 12 { mft_ok = 0 }
    if mft.unsafe_get(1) != 14 { mft_ok = 0 }
    if mft.unsafe_get(2) != 16 { mft_ok = 0 }
    if mft_ok == 1 {
        io.println("ok: map(*2).filter(>10).take(3) = [12, 14, 16]")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*2).filter(>10).take(3) incorrect")
        fail = fail + 1
    }

    // filter -> skip -> count: keep evens, skip 2, count
    let fsc = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).skip(2).count()
    // evens: [2,4,6,8,10], skip 2: [6,8,10], count: 3
    if fsc == 3 {
        io.println("ok: filter(even).skip(2).count() = 3")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(even).skip(2).count() = {fsc}, expected 3")
        fail = fail + 1
    }

    // map -> take -> fold: square, take 4, sum
    let mtf = nums.map(fn(x: Int) -> Int { x * x }).take(4).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    // squares: [1,4,9,16,...], take 4: [1,4,9,16], sum: 30
    if mtf == 30 {
        io.println("ok: map(sq).take(4).fold(+) = 30")
        pass = pass + 1
    } else {
        io.println("FAIL: map(sq).take(4).fold(+) = {mtf}, expected 30")
        fail = fail + 1
    }

    // filter -> map -> collect: keep odds, then triple
    let fmc = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * 3 }).collect()
    // odds: [1,3,5,7,9], tripled: [3,9,15,21,27]
    let mut fmc_ok = 1
    if fmc.len() != 5 { fmc_ok = 0 }
    if fmc.unsafe_get(0) != 3 { fmc_ok = 0 }
    if fmc.unsafe_get(1) != 9 { fmc_ok = 0 }
    if fmc.unsafe_get(2) != 15 { fmc_ok = 0 }
    if fmc.unsafe_get(3) != 21 { fmc_ok = 0 }
    if fmc.unsafe_get(4) != 27 { fmc_ok = 0 }
    if fmc_ok == 1 {
        io.println("ok: filter(odd).map(*3).collect = [3,9,15,21,27]")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(odd).map(*3).collect incorrect")
        fail = fail + 1
    }

    // === skip + take combined ===
    io.println("--- skip + take combined ---")

    // skip then take: window into the middle
    let st = nums.skip(3).take(4).collect()
    // skip 3: [4,5,6,7,8,9,10], take 4: [4,5,6,7]
    let mut st_ok = 1
    if st.len() != 4 { st_ok = 0 }
    if st.unsafe_get(0) != 4 { st_ok = 0 }
    if st.unsafe_get(1) != 5 { st_ok = 0 }
    if st.unsafe_get(2) != 6 { st_ok = 0 }
    if st.unsafe_get(3) != 7 { st_ok = 0 }
    if st_ok == 1 {
        io.println("ok: skip(3).take(4) = [4,5,6,7]")
        pass = pass + 1
    } else {
        io.println("FAIL: skip(3).take(4) incorrect")
        fail = fail + 1
    }

    // take then skip: take first 5, skip 2 of those
    let ts = nums.take(5).skip(2).collect()
    // take 5: [1,2,3,4,5], skip 2: [3,4,5]
    let mut ts_ok = 1
    if ts.len() != 3 { ts_ok = 0 }
    if ts.unsafe_get(0) != 3 { ts_ok = 0 }
    if ts.unsafe_get(1) != 4 { ts_ok = 0 }
    if ts.unsafe_get(2) != 5 { ts_ok = 0 }
    if ts_ok == 1 {
        io.println("ok: take(5).skip(2) = [3,4,5]")
        pass = pass + 1
    } else {
        io.println("FAIL: take(5).skip(2) incorrect")
        fail = fail + 1
    }

    // skip past end then take
    let sp_past = nums.skip(20).take(5).collect()
    if sp_past.len() == 0 {
        io.println("ok: skip(20).take(5) = [] (skip past end)")
        pass = pass + 1
    } else {
        io.println("FAIL: skip(20).take(5) len = {sp_past.len()}, expected 0")
        fail = fail + 1
    }

    // === filter + count ===
    io.println("--- filter + count ---")

    let fc1 = nums.filter(fn(x: Int) -> Bool { x > 5 }).count()
    if fc1 == 5 {
        io.println("ok: filter(>5).count() = 5")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(>5).count() = {fc1}, expected 5")
        fail = fail + 1
    }

    let fc2 = nums.filter(fn(x: Int) -> Bool { x > 100 }).count()
    if fc2 == 0 {
        io.println("ok: filter(>100).count() = 0 (none match)")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(>100).count() = {fc2}, expected 0")
        fail = fail + 1
    }

    // === map + fold ===
    io.println("--- map + fold ---")

    // sum of squares
    let mf1 = nums.map(fn(x: Int) -> Int { x * x }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    // 1+4+9+16+25+36+49+64+81+100 = 385
    if mf1 == 385 {
        io.println("ok: map(sq).fold(+) = 385 (sum of squares)")
        pass = pass + 1
    } else {
        io.println("FAIL: map(sq).fold(+) = {mf1}, expected 385")
        fail = fail + 1
    }

    // product of incremented values: (1+1)*(2+1)*...*(5+1) using a smaller list
    let mut small: List[Int] = []
    small.push(1)
    small.push(2)
    small.push(3)
    small.push(4)
    small.push(5)
    let mf2 = small.map(fn(x: Int) -> Int { x + 1 }).fold(1, fn(acc: Int, x: Int) -> Int { acc * x })
    // (2)*(3)*(4)*(5)*(6) = 720
    if mf2 == 720 {
        io.println("ok: map(+1).fold(*) = 720")
        pass = pass + 1
    } else {
        io.println("FAIL: map(+1).fold(*) = {mf2}, expected 720")
        fail = fail + 1
    }

    // === map + any/all ===
    io.println("--- map + any/all ---")

    let ma1 = nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 50 })
    if ma1 {
        io.println("ok: map(*10).any(==50) = true")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*10).any(==50) should be true")
        fail = fail + 1
    }

    let ma2 = nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 55 })
    if !ma2 {
        io.println("ok: map(*10).any(==55) = false")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*10).any(==55) should be false")
        fail = fail + 1
    }

    let mall1 = nums.map(fn(x: Int) -> Int { x + 100 }).all(fn(x: Int) -> Bool { x > 99 })
    if mall1 {
        io.println("ok: map(+100).all(>99) = true")
        pass = pass + 1
    } else {
        io.println("FAIL: map(+100).all(>99) should be true")
        fail = fail + 1
    }

    let mall2 = nums.map(fn(x: Int) -> Int { x * 2 }).all(fn(x: Int) -> Bool { x > 5 })
    if !mall2 {
        io.println("ok: map(*2).all(>5) = false")
        pass = pass + 1
    } else {
        io.println("FAIL: map(*2).all(>5) should be false (2,4 fail)")
        fail = fail + 1
    }

    // === filter + find ===
    io.println("--- filter + find ---")

    let ff1 = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).find(fn(x: Int) -> Bool { x > 6 })
    let ff1_val = ff1 ?? -1
    // evens: [2,4,6,8,10], first > 6 is 8
    if ff1_val == 8 {
        io.println("ok: filter(even).find(>6) = 8")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(even).find(>6) = {ff1_val}, expected 8")
        fail = fail + 1
    }

    let ff2 = nums.filter(fn(x: Int) -> Bool { x < 3 }).find(fn(x: Int) -> Bool { x > 10 })
    let ff2_val = ff2 ?? -1
    // filtered: [1,2], none >10
    if ff2_val == -1 {
        io.println("ok: filter(<3).find(>10) = None")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(<3).find(>10) = {ff2_val}, expected None")
        fail = fail + 1
    }

    // === chain + filter + count ===
    io.println("--- chain + filter + count ---")

    let mut other: List[Int] = []
    other.push(11)
    other.push(12)
    other.push(13)
    other.push(14)
    other.push(15)

    let cfc = nums.chain(other).filter(fn(x: Int) -> Bool { x % 3 == 0 }).count()
    // [1..10,11..15], multiples of 3: 3,6,9,12,15 = 5
    if cfc == 5 {
        io.println("ok: chain.filter(%3==0).count() = 5")
        pass = pass + 1
    } else {
        io.println("FAIL: chain.filter(%3==0).count() = {cfc}, expected 5")
        fail = fail + 1
    }

    // chain + map + take
    let cmt = nums.chain(other).map(fn(x: Int) -> Int { x * 2 }).take(3).collect()
    let mut cmt_ok = 1
    if cmt.len() != 3 { cmt_ok = 0 }
    if cmt.unsafe_get(0) != 2 { cmt_ok = 0 }
    if cmt.unsafe_get(1) != 4 { cmt_ok = 0 }
    if cmt.unsafe_get(2) != 6 { cmt_ok = 0 }
    if cmt_ok == 1 {
        io.println("ok: chain.map(*2).take(3) = [2,4,6]")
        pass = pass + 1
    } else {
        io.println("FAIL: chain.map(*2).take(3) incorrect")
        fail = fail + 1
    }

    // === 4-way chain ===
    io.println("--- 4-way adapter chain ---")

    // filter -> map -> skip -> take
    let fmst = nums.filter(fn(x: Int) -> Bool { x > 2 }).map(fn(x: Int) -> Int { x * 10 }).skip(2).take(3).collect()
    // filter >2: [3,4,5,6,7,8,9,10], map *10: [30,40,50,60,70,80,90,100], skip 2: [50,60,70,80,90,100], take 3: [50,60,70]
    let mut fmst_ok = 1
    if fmst.len() != 3 { fmst_ok = 0 }
    if fmst.unsafe_get(0) != 50 { fmst_ok = 0 }
    if fmst.unsafe_get(1) != 60 { fmst_ok = 0 }
    if fmst.unsafe_get(2) != 70 { fmst_ok = 0 }
    if fmst_ok == 1 {
        io.println("ok: filter(>2).map(*10).skip(2).take(3) = [50,60,70]")
        pass = pass + 1
    } else {
        io.println("FAIL: 4-way chain incorrect")
        fail = fail + 1
    }

    // filter -> map -> filter -> fold
    let fmff = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * x }).filter(fn(x: Int) -> Bool { x > 10 }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    // odds: [1,3,5,7,9], squares: [1,9,25,49,81], filter >10: [25,49,81], sum: 155
    if fmff == 155 {
        io.println("ok: filter(odd).map(sq).filter(>10).fold(+) = 155")
        pass = pass + 1
    } else {
        io.println("FAIL: 4-way chain fold = {fmff}, expected 155")
        fail = fail + 1
    }

    // === empty list through chains ===
    io.println("--- empty list through chains ---")

    let e1 = empty.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 0 }).collect()
    if e1.len() == 0 {
        io.println("ok: empty.map.filter.collect = []")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.map.filter.collect len = {e1.len()}")
        fail = fail + 1
    }

    let e2 = empty.filter(fn(x: Int) -> Bool { x > 0 }).skip(1).take(5).count()
    if e2 == 0 {
        io.println("ok: empty.filter.skip.take.count = 0")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.filter.skip.take.count = {e2}, expected 0")
        fail = fail + 1
    }

    let e3 = empty.map(fn(x: Int) -> Int { x + 1 }).fold(42, fn(acc: Int, x: Int) -> Int { acc + x })
    if e3 == 42 {
        io.println("ok: empty.map.fold = 42 (initial value preserved)")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.map.fold = {e3}, expected 42")
        fail = fail + 1
    }

    let e4 = empty.map(fn(x: Int) -> Int { x * 2 }).any(fn(x: Int) -> Bool { x == 1 })
    if !e4 {
        io.println("ok: empty.map.any = false")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.map.any should be false")
        fail = fail + 1
    }

    let e5 = empty.map(fn(x: Int) -> Int { x * 2 }).all(fn(x: Int) -> Bool { x == 1 })
    if e5 {
        io.println("ok: empty.map.all = true (vacuous truth)")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.map.all should be true")
        fail = fail + 1
    }

    let e6 = empty.filter(fn(x: Int) -> Bool { x > 0 }).find(fn(x: Int) -> Bool { x == 1 })
    let e6_val = e6 ?? -1
    if e6_val == -1 {
        io.println("ok: empty.filter.find = None")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.filter.find = {e6_val}, expected None")
        fail = fail + 1
    }

    let mut empty2: List[Int] = []
    let e7 = empty.chain(empty2).filter(fn(x: Int) -> Bool { x > 0 }).count()
    if e7 == 0 {
        io.println("ok: empty.chain(empty).filter.count = 0")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.chain(empty).filter.count = {e7}, expected 0")
        fail = fail + 1
    }

    // === for_each after adapter chain ===
    io.println("--- for_each after chain ---")

    let mut fe_sum = 0
    nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).map(fn(x: Int) -> Int { x * 10 }).for_each(fn(x: Int) {
        fe_sum = fe_sum + x
    })
    // evens: [2,4,6,8,10], *10: [20,40,60,80,100], sum: 300
    if fe_sum == 300 {
        io.println("ok: filter(even).map(*10).for_each sum = 300")
        pass = pass + 1
    } else {
        io.println("FAIL: filter(even).map(*10).for_each sum = {fe_sum}, expected 300")
        fail = fail + 1
    }

    // === map chained twice ===
    io.println("--- double map ---")

    let dm = nums.map(fn(x: Int) -> Int { x + 1 }).map(fn(x: Int) -> Int { x * 2 }).take(5).collect()
    // +1: [2,3,4,5,6,...], *2: [4,6,8,10,12,...], take 5: [4,6,8,10,12]
    let mut dm_ok = 1
    if dm.len() != 5 { dm_ok = 0 }
    if dm.unsafe_get(0) != 4 { dm_ok = 0 }
    if dm.unsafe_get(1) != 6 { dm_ok = 0 }
    if dm.unsafe_get(2) != 8 { dm_ok = 0 }
    if dm.unsafe_get(3) != 10 { dm_ok = 0 }
    if dm.unsafe_get(4) != 12 { dm_ok = 0 }
    if dm_ok == 1 {
        io.println("ok: map(+1).map(*2).take(5) = [4,6,8,10,12]")
        pass = pass + 1
    } else {
        io.println("FAIL: double map chain incorrect")
        fail = fail + 1
    }

    // === filter chained twice ===
    io.println("--- double filter ---")

    let df = nums.filter(fn(x: Int) -> Bool { x > 3 }).filter(fn(x: Int) -> Bool { x < 8 }).collect()
    // >3: [4,5,6,7,8,9,10], <8: [4,5,6,7]
    let mut df_ok = 1
    if df.len() != 4 { df_ok = 0 }
    if df.unsafe_get(0) != 4 { df_ok = 0 }
    if df.unsafe_get(1) != 5 { df_ok = 0 }
    if df.unsafe_get(2) != 6 { df_ok = 0 }
    if df.unsafe_get(3) != 7 { df_ok = 0 }
    if df_ok == 1 {
        io.println("ok: filter(>3).filter(<8) = [4,5,6,7]")
        pass = pass + 1
    } else {
        io.println("FAIL: double filter chain incorrect")
        fail = fail + 1
    }

    // === for-in over adapter chain results ===
    io.println("--- for-in over chain results ---")

    let chain_result = nums.filter(fn(x: Int) -> Bool { x > 7 }).map(fn(x: Int) -> Int { x * 100 })
    let mut for_sum = 0
    for v in chain_result {
        for_sum = for_sum + v
    }
    // >7: [8,9,10], *100: [800,900,1000], sum: 2700
    if for_sum == 2700 {
        io.println("ok: for-in over filter.map sum = 2700")
        pass = pass + 1
    } else {
        io.println("FAIL: for-in over filter.map sum = {for_sum}, expected 2700")
        fail = fail + 1
    }

    // === results ===
    io.println("--- results ---")
    if fail == 0 {
        io.println("{pass} passed, 0 errors")
        io.println("PASS")
    } else {
        io.println("{pass} passed, {fail} FAIL")
    }
}
