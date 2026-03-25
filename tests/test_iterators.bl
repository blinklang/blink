test "for-in over exclusive range" {
    let mut sum1 = 0
    for x in 1..5 {
        sum1 = sum1 + x
    }
    assert_eq(sum1, 10)
}

test "for-in over inclusive range" {
    let mut sum2 = 0
    for x in 1..=5 {
        sum2 = sum2 + x
    }
    assert_eq(sum2, 15)
}

test "for-in over list" {
    let mut items: List[Int] = []
    items.push(10)
    items.push(20)
    items.push(30)
    let mut sum3 = 0
    for x in items {
        sum3 = sum3 + x
    }
    assert_eq(sum3, 60)
}

test "empty range iterates zero times" {
    let mut count4 = 0
    for x in 5..5 {
        count4 = count4 + 1
    }
    assert_eq(count4, 0)
}

test "inclusive range with single element" {
    let mut count5 = 0
    let mut val5 = 0
    for x in 3..=3 {
        count5 = count5 + 1
        val5 = x
    }
    assert_eq(count5, 1)
    assert_eq(val5, 3)
}

test "nested for-in loops" {
    let mut sum6 = 0
    for i in 1..=3 {
        for j in 1..=3 {
            sum6 = sum6 + i * j
        }
    }
    assert_eq(sum6, 36)
}

test "for-in over empty list" {
    let mut empty_list: List[Int] = []
    let mut count7 = 0
    for x in empty_list {
        count7 = count7 + 1
    }
    assert_eq(count7, 0)
}
