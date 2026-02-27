fn fibonacci(n: Int) -> Int {
    if n <= 1 {
        n
    } else {
        fibonacci(n - 1) + fibonacci(n - 2)
    }
}

fn sum_to(n: Int) -> Int {
    let mut s = 0
    let mut i = 1
    while i <= n {
        s = s + i
        i = i + 1
    }
    s
}

fn factorial(n: Int) -> Int {
    if n <= 1 {
        1
    } else {
        n * factorial(n - 1)
    }
}

test "three different computations" {
    async.scope {
        let h_fib = async.spawn(fn() {
            fibonacci(10)
        })
        let h_sum = async.spawn(fn() {
            sum_to(100)
        })
        let h_fact = async.spawn(fn() {
            factorial(10)
        })

        let r_fib = h_fib.await
        let r_sum = h_sum.await
        let r_fact = h_fact.await

        assert_eq(r_fib, 55)
        assert_eq(r_sum, 5050)
        assert_eq(r_fact, 3628800)
    }
}

test "mixed captures and arithmetic" {
    let multiplier = 7
    let addend = 13
    async.scope {
        let h1 = async.spawn(fn() {
            multiplier * multiplier
        })
        let h2 = async.spawn(fn() {
            addend + addend + addend
        })
        let h3 = async.spawn(fn() {
            multiplier * addend
        })
        let r1 = h1.await
        let r2 = h2.await
        let r3 = h3.await
        assert_eq(r1, 49)
        assert_eq(r2, 39)
        assert_eq(r3, 91)
    }
}

test "tasks calling different functions" {
    let combined = async.scope {
        let hf = async.spawn(fn() {
            fibonacci(8)
        })
        let hs = async.spawn(fn() {
            sum_to(10)
        })
        let rf = hf.await
        let rs = hs.await
        rf + rs
    }
    assert_eq(combined, 76)
}
