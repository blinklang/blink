fn sum_list(nums: List[Float]) -> Float {
    let mut total = 0.0
    let mut i = 0
    while i < nums.len() {
        total = total + nums.unsafe_get(i)
        i = i + 1
    }
    total
}

fn main() {
    let mut pass = true

    // Float list literal boxing
    let vals = [1.5, 2.5, 3.0]
    let first = vals.unsafe_get(0)
    if first != 1.5 {
        io.println("FAIL: literal .get(0) expected 1.5, got {first}")
        pass = false
    }
    let s = sum_list(vals)
    if s != 7.0 {
        io.println("FAIL: sum_list expected 7.0, got {s}")
        pass = false
    }

    // For-in over List[Float]
    let mut for_sum = 0.0
    for v in vals {
        for_sum = for_sum + v
    }
    if for_sum != 7.0 {
        io.println("FAIL: for-in sum expected 7.0, got {for_sum}")
        pass = false
    }

    // Map[Str, Float] set/get round-trip
    let mut prices: Map[Str, Float] = Map()
    prices.set("apple", 1.99)
    prices.set("banana", 0.75)
    let apple = prices.get("apple")
    if apple != 1.99 {
        io.println("FAIL: map get 'apple' expected 1.99, got {apple}")
        pass = false
    }
    let banana = prices.get("banana")
    if banana != 0.75 {
        io.println("FAIL: map get 'banana' expected 0.75, got {banana}")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
