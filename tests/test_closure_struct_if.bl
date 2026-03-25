type Point { x: Int, y: Int }

test "struct from if/else in closure" {
    let make_point = fn(flag: Bool) -> Point {
        if flag { Point { x: 1, y: 2 } } else { Point { x: 0, y: 0 } }
    }
    let p = make_point(true)
    assert_eq(p.x, 1)
    assert_eq(p.y, 2)
    let q = make_point(false)
    assert_eq(q.x, 0)
}
