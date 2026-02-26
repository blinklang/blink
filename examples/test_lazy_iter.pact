fn main() {
    io.println("=== lazy iterator smoke test ===")

    let mut nums: List[Int] = []
    nums.push(1)
    nums.push(2)
    nums.push(3)
    nums.push(4)
    nums.push(5)

    // Test 1: map then collect
    let doubled = nums.map(fn(x: Int) -> Int { x * 2 }).collect()
    if doubled.len() == 5 {
        io.println("ok: map.collect len = 5")
    } else {
        io.println("FAIL: map.collect len = {doubled.len()}")
    }
    if doubled.unsafe_get(0) == 2 {
        io.println("ok: map.collect[0] = 2")
    } else {
        io.println("FAIL: map.collect[0] = {doubled.unsafe_get(0)}")
    }

    // Test 2: filter then collect
    let evens = nums.filter(fn(x: Int) -> Bool { x % 2 == 0 }).collect()
    if evens.len() == 2 {
        io.println("ok: filter.collect len = 2")
    } else {
        io.println("FAIL: filter.collect len = {evens.len()}")
    }

    // Test 3: chain adapters then collect
    let result = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).collect()
    if result.len() == 2 {
        io.println("ok: map.filter.collect len = 2")
    } else {
        io.println("FAIL: map.filter.collect len = {result.len()}")
    }

    // Test 4: chain adapters then fold (consumer)
    let sum = nums.map(fn(x: Int) -> Int { x * 2 }).filter(fn(x: Int) -> Bool { x > 6 }).fold(0, fn(acc: Int, x: Int) -> Int { acc + x })
    if sum == 18 {
        io.println("ok: map.filter.fold = 18")
    } else {
        io.println("FAIL: map.filter.fold = {sum}")
    }

    // Test 5: take then collect
    let first3 = nums.take(3).collect()
    if first3.len() == 3 {
        io.println("ok: take(3).collect len = 3")
    } else {
        io.println("FAIL: take(3).collect len = {first3.len()}")
    }

    // Test 6: skip then collect
    let after2 = nums.skip(2).collect()
    if after2.len() == 3 {
        io.println("ok: skip(2).collect len = 3")
    } else {
        io.println("FAIL: skip(2).collect len = {after2.len()}")
    }

    // Test 7: map.filter.take.collect (4-way chain)
    let chain4 = nums.map(fn(x: Int) -> Int { x * 10 }).filter(fn(x: Int) -> Bool { x > 20 }).take(2).collect()
    if chain4.len() == 2 {
        io.println("ok: map.filter.take(2).collect len = 2")
    } else {
        io.println("FAIL: map.filter.take(2).collect len = {chain4.len()}")
    }
    if chain4.unsafe_get(0) == 30 {
        io.println("ok: map.filter.take(2).collect[0] = 30")
    } else {
        io.println("FAIL: map.filter.take(2).collect[0] = {chain4.unsafe_get(0)}")
    }

    // Test 8: count on iterator
    let c = nums.filter(fn(x: Int) -> Bool { x > 3 }).count()
    if c == 2 {
        io.println("ok: filter.count = 2")
    } else {
        io.println("FAIL: filter.count = {c}")
    }

    // Test 9: any on iterator
    let a = nums.map(fn(x: Int) -> Int { x * 10 }).any(fn(x: Int) -> Bool { x == 30 })
    if a {
        io.println("ok: map.any found 30")
    } else {
        io.println("FAIL: map.any did not find 30")
    }

    // Test 10: all on iterator
    let al = nums.filter(fn(x: Int) -> Bool { x > 2 }).all(fn(x: Int) -> Bool { x > 2 })
    if al {
        io.println("ok: filter.all > 2")
    } else {
        io.println("FAIL: filter.all > 2 failed")
    }

    io.println("=== done ===")
}
