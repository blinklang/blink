test "mutable counter capture" {
    let mut counter = 0
    let increment = fn() {
        counter = counter + 1
    }
    increment()
    increment()
    assert_eq(counter, 2)
}

test "mutable accumulator capture" {
    let mut total = 0
    let add = fn(n: Int) {
        total = total + n
    }
    add(10)
    add(20)
    add(30)
    assert_eq(total, 60)
}
