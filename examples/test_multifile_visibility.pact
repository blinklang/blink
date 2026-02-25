import multifile_helper

fn add(a: Int, b: Int) -> Int {
    a + b
}

fn main() {
    // pub functions from helper module are accessible
    assert_eq(helper_add(3, 4), 7)
    assert_eq(helper_mul(5, 6), 30)

    // pub let from helper module is accessible
    assert_eq(HELPER_CONST, 99)

    // local fn with same name as a common pattern won't collide
    // because helper's C name is pact_multifile_helper_add
    assert_eq(add(10, 20), 30)

    // both work in same program
    assert_eq(helper_add(1, 1) + add(2, 2), 6)

    io.println("all multifile visibility tests passed")
}
