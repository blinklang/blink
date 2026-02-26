fn main() {
    io.println("=== iterator method tests ===")
    let mut pass = 0
    let mut fail = 0

    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    // --- count ---
    io.println("--- count ---")
    let c = nums.count()
    if c == 5 {
        io.println("ok: count = 5")
        pass = pass + 1
    } else {
        io.println("FAIL: count = {c}, expected 5")
        fail = fail + 1
    }

    let mut empty: List[Int] = []
    let ec = empty.count()
    if ec == 0 {
        io.println("ok: empty count = 0")
        pass = pass + 1
    } else {
        io.println("FAIL: empty count = {ec}, expected 0")
        fail = fail + 1
    }

    // --- collect ---
    io.println("--- collect ---")
    let collected = nums.collect()
    if collected.len() == 5 {
        io.println("ok: collect preserves length")
        pass = pass + 1
    } else {
        io.println("FAIL: collect length = {collected.len()}, expected 5")
        fail = fail + 1
    }

    // --- for_each ---
    io.println("--- for_each ---")
    let mut fe_sum = 0
    nums.for_each(fn(x: Int) {
        fe_sum = fe_sum + x
    })
    if fe_sum == 15 {
        io.println("ok: for_each sum = 15")
        pass = pass + 1
    } else {
        io.println("FAIL: for_each sum = {fe_sum}, expected 15")
        fail = fail + 1
    }

    // --- any ---
    io.println("--- any ---")
    let has_three = nums.any(fn(x: Int) -> Bool { x == 3 })
    if has_three {
        io.println("ok: any found 3")
        pass = pass + 1
    } else {
        io.println("FAIL: any should find 3")
        fail = fail + 1
    }

    let has_ten = nums.any(fn(x: Int) -> Bool { x == 10 })
    if !has_ten {
        io.println("ok: any did not find 10")
        pass = pass + 1
    } else {
        io.println("FAIL: any should not find 10")
        fail = fail + 1
    }

    let empty_any = empty.any(fn(x: Int) -> Bool { x == 1 })
    if !empty_any {
        io.println("ok: any on empty = false")
        pass = pass + 1
    } else {
        io.println("FAIL: any on empty should be false")
        fail = fail + 1
    }

    // --- all ---
    io.println("--- all ---")
    let all_pos = nums.all(fn(x: Int) -> Bool { x > 0 })
    if all_pos {
        io.println("ok: all > 0")
        pass = pass + 1
    } else {
        io.println("FAIL: all > 0 should be true")
        fail = fail + 1
    }

    let all_lt3 = nums.all(fn(x: Int) -> Bool { x < 3 })
    if !all_lt3 {
        io.println("ok: not all < 3")
        pass = pass + 1
    } else {
        io.println("FAIL: all < 3 should be false")
        fail = fail + 1
    }

    let empty_all = empty.all(fn(x: Int) -> Bool { x == 1 })
    if empty_all {
        io.println("ok: all on empty = true")
        pass = pass + 1
    } else {
        io.println("FAIL: all on empty should be true")
        fail = fail + 1
    }

    // --- find ---
    io.println("--- find ---")
    let found = nums.find(fn(x: Int) -> Bool { x > 3 })
    let found_val = found ?? -1
    if found_val == 4 {
        io.println("ok: find > 3 = 4")
        pass = pass + 1
    } else {
        io.println("FAIL: find > 3 = {found_val}, expected 4")
        fail = fail + 1
    }

    let not_found = nums.find(fn(x: Int) -> Bool { x > 100 })
    let nf_val = not_found ?? -1
    if nf_val == -1 {
        io.println("ok: find > 100 = None")
        pass = pass + 1
    } else {
        io.println("FAIL: find > 100 = {nf_val}, expected -1 (None)")
        fail = fail + 1
    }

    // --- fold ---
    io.println("--- fold ---")
    let sum = nums.fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    if sum == 15 {
        io.println("ok: fold sum = 15")
        pass = pass + 1
    } else {
        io.println("FAIL: fold sum = {sum}, expected 15")
        fail = fail + 1
    }

    let product = nums.fold(1, fn(acc: Int, x: Int) -> Int { acc * x })
    if product == 120 {
        io.println("ok: fold product = 120")
        pass = pass + 1
    } else {
        io.println("FAIL: fold product = {product}, expected 120")
        fail = fail + 1
    }

    let empty_fold = empty.fold(42, fn(acc: Int, x: Int) -> Int { acc + x })
    if empty_fold == 42 {
        io.println("ok: fold on empty = initial")
        pass = pass + 1
    } else {
        io.println("FAIL: fold on empty = {empty_fold}, expected 42")
        fail = fail + 1
    }

    // --- map ---
    io.println("--- map ---")
    let doubled = nums.map(fn(x: Int) -> Int { x * 2 }).collect()
    let mut map_ok = 1
    if doubled.len() != 5 { map_ok = 0 }
    if doubled.unsafe_get(0) != 2 { map_ok = 0 }
    if doubled.unsafe_get(1) != 4 { map_ok = 0 }
    if doubled.unsafe_get(2) != 6 { map_ok = 0 }
    if doubled.unsafe_get(3) != 8 { map_ok = 0 }
    if doubled.unsafe_get(4) != 10 { map_ok = 0 }
    if map_ok == 1 {
        io.println("ok: map doubles [1..5] = [2,4,6,8,10]")
        pass = pass + 1
    } else {
        io.println("FAIL: map doubles incorrect")
        fail = fail + 1
    }

    let empty_map = empty.map(fn(x: Int) -> Int { x * 2 }).collect()
    if empty_map.len() == 0 {
        io.println("ok: map on empty = []")
        pass = pass + 1
    } else {
        io.println("FAIL: map on empty len = {empty_map.len()}")
        fail = fail + 1
    }

    // --- filter ---
    io.println("--- filter ---")
    let evens = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).collect()
    let mut filt_ok = 1
    if evens.len() != 2 { filt_ok = 0 }
    if evens.unsafe_get(0) != 2 { filt_ok = 0 }
    if evens.unsafe_get(1) != 4 { filt_ok = 0 }
    if filt_ok == 1 {
        io.println("ok: filter evens = [2, 4]")
        pass = pass + 1
    } else {
        io.println("FAIL: filter evens incorrect, len={evens.len()}")
        fail = fail + 1
    }

    let none_match = nums.filter(fn(x: Int) -> Bool { x > 100 }).collect()
    if none_match.len() == 0 {
        io.println("ok: filter none matching = []")
        pass = pass + 1
    } else {
        io.println("FAIL: filter none matching len = {none_match.len()}")
        fail = fail + 1
    }

    let all_match = nums.filter(fn(x: Int) -> Bool { x > 0 }).collect()
    if all_match.len() == 5 {
        io.println("ok: filter all matching = 5 elements")
        pass = pass + 1
    } else {
        io.println("FAIL: filter all matching len = {all_match.len()}")
        fail = fail + 1
    }

    // --- take ---
    io.println("--- take ---")
    let first3 = nums.take(3).collect()
    let mut take_ok = 1
    if first3.len() != 3 { take_ok = 0 }
    if first3.unsafe_get(0) != 1 { take_ok = 0 }
    if first3.unsafe_get(1) != 2 { take_ok = 0 }
    if first3.unsafe_get(2) != 3 { take_ok = 0 }
    if take_ok == 1 {
        io.println("ok: take 3 = [1, 2, 3]")
        pass = pass + 1
    } else {
        io.println("FAIL: take 3 incorrect")
        fail = fail + 1
    }

    let take_more = nums.take(10).collect()
    if take_more.len() == 5 {
        io.println("ok: take 10 from 5 = 5 elements")
        pass = pass + 1
    } else {
        io.println("FAIL: take 10 from 5 = {take_more.len()}")
        fail = fail + 1
    }

    let take_zero = nums.take(0).collect()
    if take_zero.len() == 0 {
        io.println("ok: take 0 = []")
        pass = pass + 1
    } else {
        io.println("FAIL: take 0 len = {take_zero.len()}")
        fail = fail + 1
    }

    // --- skip ---
    io.println("--- skip ---")
    let after2 = nums.skip(2).collect()
    let mut skip_ok = 1
    if after2.len() != 3 { skip_ok = 0 }
    if after2.unsafe_get(0) != 3 { skip_ok = 0 }
    if after2.unsafe_get(1) != 4 { skip_ok = 0 }
    if after2.unsafe_get(2) != 5 { skip_ok = 0 }
    if skip_ok == 1 {
        io.println("ok: skip 2 = [3, 4, 5]")
        pass = pass + 1
    } else {
        io.println("FAIL: skip 2 incorrect")
        fail = fail + 1
    }

    let skip_all = nums.skip(10).collect()
    if skip_all.len() == 0 {
        io.println("ok: skip 10 from 5 = []")
        pass = pass + 1
    } else {
        io.println("FAIL: skip 10 from 5 len = {skip_all.len()}")
        fail = fail + 1
    }

    let skip_zero = nums.skip(0).collect()
    if skip_zero.len() == 5 {
        io.println("ok: skip 0 = all elements")
        pass = pass + 1
    } else {
        io.println("FAIL: skip 0 len = {skip_zero.len()}")
        fail = fail + 1
    }

    // --- chaining ---
    io.println("--- chaining ---")
    let chain1 = nums.filter(fn(x: Int) -> Bool { x % 2 != 0 }).map(fn(x: Int) -> Int { x * 10 }).collect()
    let mut ch1_ok = 1
    if chain1.len() != 3 { ch1_ok = 0 }
    if chain1.unsafe_get(0) != 10 { ch1_ok = 0 }
    if chain1.unsafe_get(1) != 30 { ch1_ok = 0 }
    if chain1.unsafe_get(2) != 50 { ch1_ok = 0 }
    if ch1_ok == 1 {
        io.println("ok: filter odds then map *10 = [10, 30, 50]")
        pass = pass + 1
    } else {
        io.println("FAIL: filter+map chain incorrect")
        fail = fail + 1
    }

    let chain2 = nums.map(fn(x: Int) -> Int { x * x }).filter(fn(x: Int) -> Bool { x > 5 }).collect()
    let mut ch2_ok = 1
    if chain2.len() != 3 { ch2_ok = 0 }
    if chain2.unsafe_get(0) != 9 { ch2_ok = 0 }
    if chain2.unsafe_get(1) != 16 { ch2_ok = 0 }
    if chain2.unsafe_get(2) != 25 { ch2_ok = 0 }
    if ch2_ok == 1 {
        io.println("ok: map squares then filter > 5 = [9, 16, 25]")
        pass = pass + 1
    } else {
        io.println("FAIL: map+filter chain incorrect")
        fail = fail + 1
    }

    let chain3 = nums.filter(fn(x: Int) -> Bool { x > 2 }).take(2).collect()
    let mut ch3_ok = 1
    if chain3.len() != 2 { ch3_ok = 0 }
    if chain3.unsafe_get(0) != 3 { ch3_ok = 0 }
    if chain3.unsafe_get(1) != 4 { ch3_ok = 0 }
    if ch3_ok == 1 {
        io.println("ok: filter > 2 then take 2 = [3, 4]")
        pass = pass + 1
    } else {
        io.println("FAIL: filter+take chain incorrect")
        fail = fail + 1
    }

    let chain4_sum = nums.skip(1).take(3).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    if chain4_sum == 9 {
        io.println("ok: skip 1, take 3, fold sum = 9")
        pass = pass + 1
    } else {
        io.println("FAIL: skip+take+fold = {chain4_sum}, expected 9")
        fail = fail + 1
    }

    let chain5 = nums.map(fn(x: Int) -> Int { x + 10 }).any(fn(x: Int) -> Bool { x == 13 })
    if chain5 {
        io.println("ok: map +10 then any == 13 = true")
        pass = pass + 1
    } else {
        io.println("FAIL: map+any chain should be true")
        fail = fail + 1
    }

    let chain6 = nums.filter(fn(x: Int) -> Bool { x > 2 }).all(fn(x: Int) -> Bool { x > 2 })
    if chain6 {
        io.println("ok: filter > 2 then all > 2 = true")
        pass = pass + 1
    } else {
        io.println("FAIL: filter+all chain should be true")
        fail = fail + 1
    }

    let chain7 = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).count()
    if chain7 == 2 {
        io.println("ok: filter evens then count = 2")
        pass = pass + 1
    } else {
        io.println("FAIL: filter+count = {chain7}, expected 2")
        fail = fail + 1
    }

    // --- for-in over adapter results ---
    io.println("--- for-in over adapter results ---")
    let mapped = nums.map(fn(x: Int) -> Int { x * 3 })
    let mut for_map_sum = 0
    for x in mapped {
        for_map_sum = for_map_sum + x
    }
    if for_map_sum == 45 {
        io.println("ok: for-in over map *3 sum = 45")
        pass = pass + 1
    } else {
        io.println("FAIL: for-in over map sum = {for_map_sum}, expected 45")
        fail = fail + 1
    }

    let filtered = nums.filter(fn(x: Int) -> Bool { x > 3 })
    let mut for_filt_sum = 0
    for x in filtered {
        for_filt_sum = for_filt_sum + x
    }
    if for_filt_sum == 9 {
        io.println("ok: for-in over filter > 3 sum = 9")
        pass = pass + 1
    } else {
        io.println("FAIL: for-in over filter sum = {for_filt_sum}, expected 9")
        fail = fail + 1
    }

    // --- results ---
    io.println("--- results ---")
    if fail == 0 {
        io.println("{pass} passed, 0 errors")
        io.println("PASS")
    } else {
        io.println("{pass} passed, {fail} FAIL")
    }
}
