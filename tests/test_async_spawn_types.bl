type Point { x: Int, y: Int }

test "spawn returning Str" {
    let h = async.spawn(fn() -> Str {
        "hello async"
    })
    assert_eq(h.await, "hello async")
}

test "spawn returning Bool" {
    let h = async.spawn(fn() -> Bool {
        true
    })
    assert_eq(h.await, true)
}

test "spawn returning Float" {
    let h = async.spawn(fn() -> Float {
        3.14
    })
    assert_eq(h.await, 3.14)
}

test "spawn returning struct" {
    let h = async.spawn(fn() -> Point {
        Point { x: 10, y: 20 }
    })
    let p = h.await
    assert_eq(p.x, 10)
    assert_eq(p.y, 20)
}

test "spawn returning Option Some" {
    let h = async.spawn(fn() -> Option[Int] {
        Some(42)
    })
    let opt = h.await
    assert_eq(opt.is_some(), true)
    assert_eq(opt.unwrap(), 42)
}

test "spawn returning Option None" {
    let h = async.spawn(fn() -> Option[Int] {
        None
    })
    let opt = h.await
    assert_eq(opt.is_none(), true)
}

test "spawn returning Result Ok" {
    let h = async.spawn(fn() -> Result[Int, Str] {
        Ok(99)
    })
    let res = h.await
    assert_eq(res.is_ok(), true)
    assert_eq(res.unwrap(), 99)
}

test "spawn returning Result Err" {
    let h = async.spawn(fn() -> Result[Int, Str] {
        Err("oops")
    })
    let res = h.await
    assert_eq(res.is_err(), true)
    assert_eq(res.unwrap_err(), "oops")
}

test "spawn returning List" {
    let h = async.spawn(fn() -> List[Int] {
        [1, 2, 3]
    })
    let result: List[Int] = h.await
    assert_eq(result.len(), 3)
    assert_eq(result.get(0).unwrap(), 1)
    assert_eq(result.get(2).unwrap(), 3)
}

test "spawn capturing struct and computing" {
    let p = Point { x: 7, y: 8 }
    let h = async.spawn(fn() -> Int {
        p.x * p.y
    })
    assert_eq(h.await, 56)
}
