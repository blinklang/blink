import multifile_helper

fn add(a: Int, b: Int) -> Int {
    a + b
}

test "pub functions from helper module are accessible" {
    assert_eq(helper_add(3, 4), 7)
    assert_eq(helper_mul(5, 6), 30)
}

test "pub let from helper module is accessible" {
    assert_eq(HELPER_CONST, 99)
}

test "local fn does not collide with helper" {
    assert_eq(add(10, 20), 30)
}

test "both local and helper functions work together" {
    assert_eq(helper_add(1, 1) + add(2, 2), 6)
}
