let mut call_count: Int = 0

fn bump() {
    call_count = call_count + 1
}

fn do_match(x: Int) {
    match x {
        1 => bump()
        2 => {
            bump()
        }
        _ => bump()
    }
}

test "void call as last expr in match arm executes" {
    call_count = 0
    do_match(1)
    assert_eq(call_count, 1)
}

test "void call in block arm executes" {
    call_count = 0
    do_match(2)
    assert_eq(call_count, 1)
}

test "void call in wildcard arm executes" {
    call_count = 0
    do_match(99)
    assert_eq(call_count, 1)
}
