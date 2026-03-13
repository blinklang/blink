fn make_handler() -> Int {
    42
}

fn make_handler2() -> Int {
    43
}

test "single with handler" {
    let h = make_handler()

    with h {
        assert_eq(h, 42)
    }
}

test "multiple with handlers" {
    with make_handler(), make_handler2() {
        assert(true)
    }
}
