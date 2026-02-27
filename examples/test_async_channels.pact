test "producer-consumer with for-in" {
    let ch = Channel(20)
    let producer = async.spawn(fn() {
        let mut i = 1
        while i <= 10 {
            ch.send(i)
            i = i + 1
        }
        ch.close()
        0
    })
    let mut count = 0
    let mut sum = 0
    for val in ch {
        count = count + 1
        sum = sum + val
    }
    producer.await
    assert_eq(count, 10)
    assert_eq(sum, 55)
}

test "two producers one consumer" {
    let ch2 = Channel(20)
    let p1 = async.spawn(fn() {
        ch2.send(100)
        ch2.send(200)
        0
    })
    let p2 = async.spawn(fn() {
        ch2.send(300)
        ch2.send(400)
        0
    })
    p1.await
    p2.await
    ch2.close()
    let mut sum2 = 0
    let mut count2 = 0
    for v in ch2 {
        sum2 = sum2 + v
        count2 = count2 + 1
    }
    assert_eq(count2, 4)
    assert_eq(sum2, 1000)
}

test "scoped producer" {
    let ch3 = Channel(10)
    async.scope {
        let p = async.spawn(fn() {
            ch3.send(11)
            ch3.send(22)
            ch3.send(33)
            ch3.close()
            0
        })
    }
    let mut sum3 = 0
    for v in ch3 {
        sum3 = sum3 + v
    }
    assert_eq(sum3, 66)
}
