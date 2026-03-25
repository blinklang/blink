import multifile_helper

test "pub functions from helper module are accessible" {
    assert_eq(helper_add(3, 4), 7)
}

test "pub let from helper module is accessible" {
    assert_eq(HELPER_CONST, 99)
}

test "pub type from helper module is accessible" {
    let p = HelperPoint { x: 10, y: 20 }
    assert_eq(p.x, 10)
    assert_eq(p.y, 20)
}

test "pub enum variants from helper module are accessible" {
    let c = Red
    match c {
        Red => assert_eq(1, 1)
        Green => assert_eq(1, 0)
        Blue => assert_eq(1, 0)
    }
}
