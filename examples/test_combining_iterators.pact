fn main() {
    io.println("=== combining iterator tests ===")
    let mut pass = 0
    let mut fail = 0

    let mut a: List[Int] = []
    a.push(1)
    a.push(2)
    a.push(3)

    let mut b: List[Int] = []
    b.push(4)
    b.push(5)

    // --- chain ---
    io.println("--- chain ---")
    let chained = a.chain(b).collect()
    if chained.len() == 5 {
        io.println("ok: chain length = 5")
        pass = pass + 1
    } else {
        io.println("FAIL: chain length = {chained.len()}, expected 5")
        fail = fail + 1
    }

    let mut chain_ok = 1
    if chained.unsafe_get(0) != 1 { chain_ok = 0 }
    if chained.unsafe_get(1) != 2 { chain_ok = 0 }
    if chained.unsafe_get(2) != 3 { chain_ok = 0 }
    if chained.unsafe_get(3) != 4 { chain_ok = 0 }
    if chained.unsafe_get(4) != 5 { chain_ok = 0 }
    if chain_ok == 1 {
        io.println("ok: chain values = [1, 2, 3, 4, 5]")
        pass = pass + 1
    } else {
        io.println("FAIL: chain values incorrect")
        fail = fail + 1
    }

    let mut empty: List[Int] = []
    let chain_empty = empty.chain(a).collect()
    if chain_empty.len() == 3 {
        io.println("ok: empty.chain(a) length = 3")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.chain(a) length = {chain_empty.len()}, expected 3")
        fail = fail + 1
    }

    let chain_with_empty = a.chain(empty).collect()
    if chain_with_empty.len() == 3 {
        io.println("ok: a.chain(empty) length = 3")
        pass = pass + 1
    } else {
        io.println("FAIL: a.chain(empty) length = {chain_with_empty.len()}, expected 3")
        fail = fail + 1
    }

    // chain + other adapters
    let chain_sum = a.chain(b).fold(0, fn(acc: Int, v: Int) -> Int { acc + v })
    if chain_sum == 15 {
        io.println("ok: chain then fold sum = 15")
        pass = pass + 1
    } else {
        io.println("FAIL: chain then fold sum = {chain_sum}, expected 15")
        fail = fail + 1
    }

    let chain_count = a.chain(b).count()
    if chain_count == 5 {
        io.println("ok: chain then count = 5")
        pass = pass + 1
    } else {
        io.println("FAIL: chain then count = {chain_count}, expected 5")
        fail = fail + 1
    }

    // --- enumerate ---
    io.println("--- enumerate ---")
    let enumerated = a.enumerate()
    if enumerated.len() == 3 {
        io.println("ok: enumerate length = 3")
        pass = pass + 1
    } else {
        io.println("FAIL: enumerate length = {enumerated.len()}, expected 3")
        fail = fail + 1
    }

    let pair0 = enumerated.unsafe_get(0)
    let idx0 = pair0.unsafe_get(0)
    let val0 = pair0.unsafe_get(1)
    if idx0 == 0 && val0 == 1 {
        io.println("ok: enumerate[0] = (0, 1)")
        pass = pass + 1
    } else {
        io.println("FAIL: enumerate[0] = ({idx0}, {val0}), expected (0, 1)")
        fail = fail + 1
    }

    let pair1 = enumerated.unsafe_get(1)
    let idx1 = pair1.unsafe_get(0)
    let val1 = pair1.unsafe_get(1)
    if idx1 == 1 && val1 == 2 {
        io.println("ok: enumerate[1] = (1, 2)")
        pass = pass + 1
    } else {
        io.println("FAIL: enumerate[1] = ({idx1}, {val1}), expected (1, 2)")
        fail = fail + 1
    }

    let pair2 = enumerated.unsafe_get(2)
    let idx2 = pair2.unsafe_get(0)
    let val2 = pair2.unsafe_get(1)
    if idx2 == 2 && val2 == 3 {
        io.println("ok: enumerate[2] = (2, 3)")
        pass = pass + 1
    } else {
        io.println("FAIL: enumerate[2] = ({idx2}, {val2}), expected (2, 3)")
        fail = fail + 1
    }

    let empty_enum = empty.enumerate()
    if empty_enum.len() == 0 {
        io.println("ok: empty.enumerate() length = 0")
        pass = pass + 1
    } else {
        io.println("FAIL: empty.enumerate() length = {empty_enum.len()}, expected 0")
        fail = fail + 1
    }

    // --- zip ---
    io.println("--- zip ---")
    let mut x: List[Int] = []
    x.push(10)
    x.push(20)
    x.push(30)

    let mut y: List[Int] = []
    y.push(1)
    y.push(2)
    y.push(3)

    let zipped = x.zip(y)
    if zipped.len() == 3 {
        io.println("ok: zip length = 3")
        pass = pass + 1
    } else {
        io.println("FAIL: zip length = {zipped.len()}, expected 3")
        fail = fail + 1
    }

    let zp0 = zipped.unsafe_get(0)
    let zp0_a = zp0.unsafe_get(0)
    let zp0_b = zp0.unsafe_get(1)
    if zp0_a == 10 && zp0_b == 1 {
        io.println("ok: zip[0] = (10, 1)")
        pass = pass + 1
    } else {
        io.println("FAIL: zip[0] = ({zp0_a}, {zp0_b}), expected (10, 1)")
        fail = fail + 1
    }

    let zp2 = zipped.unsafe_get(2)
    let zp2_a = zp2.unsafe_get(0)
    let zp2_b = zp2.unsafe_get(1)
    if zp2_a == 30 && zp2_b == 3 {
        io.println("ok: zip[2] = (30, 3)")
        pass = pass + 1
    } else {
        io.println("FAIL: zip[2] = ({zp2_a}, {zp2_b}), expected (30, 3)")
        fail = fail + 1
    }

    // zip with different lengths (truncates to shorter)
    let mut shorter: List[Int] = []
    shorter.push(100)
    shorter.push(200)

    let zip_short = x.zip(shorter)
    if zip_short.len() == 2 {
        io.println("ok: zip different lengths = 2")
        pass = pass + 1
    } else {
        io.println("FAIL: zip different lengths = {zip_short.len()}, expected 2")
        fail = fail + 1
    }

    let zps0 = zip_short.unsafe_get(0)
    let zps0_a = zps0.unsafe_get(0)
    let zps0_b = zps0.unsafe_get(1)
    if zps0_a == 10 && zps0_b == 100 {
        io.println("ok: zip_short[0] = (10, 100)")
        pass = pass + 1
    } else {
        io.println("FAIL: zip_short[0] = ({zps0_a}, {zps0_b}), expected (10, 100)")
        fail = fail + 1
    }

    let zip_empty = a.zip(empty)
    if zip_empty.len() == 0 {
        io.println("ok: zip with empty = 0 length")
        pass = pass + 1
    } else {
        io.println("FAIL: zip with empty = {zip_empty.len()}, expected 0")
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
