type Wrapper {
    Empty
    Pair(first: Str, second: Int)
    WithMap(data: Map[Str, Int])
    MapAndMore(m: Map[Str, Int], count: Int)
}

test "enum variant with Map field preserves type" {
    let m: Map[Str, Int] = Map()
    m.set("x", 42)
    let w = Wrapper.WithMap(m)
    match w {
        WithMap(data) => {
            assert_eq(data.len(), 1)
        }
        _ => assert(false)
    }
}

test "enum variant with two fields" {
    let w = Wrapper.Pair("hello", 99)
    match w {
        Pair(first, second) => {
            assert_eq(first, "hello")
            assert_eq(second, 99)
        }
        _ => assert(false)
    }
}

test "enum variant with Map and Int fields" {
    let m: Map[Str, Int] = Map()
    m.set("k", 7)
    let w = Wrapper.MapAndMore(m, 5)
    match w {
        MapAndMore(m2, count) => {
            assert_eq(m2.len(), 1)
            assert_eq(count, 5)
        }
        _ => assert(false)
    }
}
