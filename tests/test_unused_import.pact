import multifile_helper

fn local_add(a: Int, b: Int) -> Int {
    a + b
}

test "unused import should produce warning" {
    assert_eq(local_add(1, 2), 3)
}
