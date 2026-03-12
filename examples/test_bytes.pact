test "basic push and len" {
    let b = Bytes.new()
    b.push(72)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    assert_eq(b.len(), 5)
}

test "get valid and out of bounds" {
    let b = Bytes.new()
    b.push(72)
    b.push(101)
    b.push(108)
    assert_eq(b.get(0) ?? -1, 72)
    assert_eq(b.get(99) ?? -1, -1)
}

test "to_str" {
    let b = Bytes.new()
    b.push(72)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    match b.to_str() {
        Ok(s) => assert_eq(s, "Hello")
        Err(e) => assert(false)
    }
}

test "set modifies byte" {
    let b = Bytes.new()
    b.push(72)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    b.set(0, 104)
    match b.to_str() {
        Ok(s) => assert_eq(s, "hello")
        Err(e) => assert(false)
    }
}

test "slice" {
    let b = Bytes.new()
    b.push(104)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    let sl = b.slice(0, 3)
    assert_eq(sl.len(), 3)
    match sl.to_str() {
        Ok(s) => assert_eq(s, "hel")
        Err(e) => assert(false)
    }
}

test "from_str" {
    let b2 = Bytes.from_str("world")
    match b2.to_str() {
        Ok(s) => assert_eq(s, "world")
        Err(e) => assert(false)
    }
    assert_eq(b2.len(), 5)
}

test "Bytes() constructor" {
    let b3 = Bytes()
    b3.push(65)
    match b3.to_str() {
        Ok(s) => assert_eq(s, "A")
        Err(e) => assert(false)
    }
}

test "is_empty" {
    let empty = Bytes.new()
    assert_eq(empty.is_empty(), true)

    let b = Bytes.new()
    b.push(72)
    assert_eq(b.is_empty(), false)
}

test "concat" {
    let b = Bytes.new()
    b.push(104)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    let b2 = Bytes.from_str("world")
    let joined = b.concat(b2)
    match joined.to_str() {
        Ok(s) => assert_eq(s, "helloworld")
        Err(e) => assert(false)
    }
    assert_eq(joined.len(), 10)
}

test "to_hex" {
    let b = Bytes.new()
    b.push(104)
    b.push(101)
    b.push(108)
    b.push(108)
    b.push(111)
    assert_eq(b.to_hex(), "68656c6c6f")
}

test "invalid utf8 returns Err" {
    let bad = Bytes.new()
    bad.push(255)
    bad.push(254)
    assert(bad.to_str().is_err())
}

test "free function bytes_new and bytes_len" {
    let b = bytes_new()
    assert_eq(bytes_len(b), 0)
    assert_eq(bytes_is_empty(b), 1)
}

test "free function bytes_push and bytes_get" {
    let b = bytes_new()
    bytes_push(b, 72)
    bytes_push(b, 101)
    assert_eq(bytes_len(b), 2)
    assert_eq(bytes_get(b, 0), 72)
    assert_eq(bytes_get(b, 1), 101)
}

test "free function bytes_from_str and bytes_to_hex" {
    let b = bytes_from_str("hello")
    assert_eq(bytes_len(b), 5)
    assert_eq(bytes_to_hex(b), "68656c6c6f")
}

test "free function bytes_set" {
    let b = bytes_from_str("Hello")
    bytes_set(b, 0, 104)
    assert_eq(bytes_get(b, 0), 104)
}

test "free function bytes_slice and bytes_concat" {
    let a = bytes_from_str("hello")
    let b = bytes_from_str("world")
    let joined = bytes_concat(a, b)
    assert_eq(bytes_len(joined), 10)
    let sl = bytes_slice(joined, 0, 5)
    assert_eq(bytes_len(sl), 5)
}
