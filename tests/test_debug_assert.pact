test "debug_assert with true" {
    debug_assert(true)
}

test "debug_assert with equality" {
    debug_assert(1 == 1)
}

test "debug_assert with expression" {
    debug_assert(1 + 1 == 2)
}

test "debug_assert with variable" {
    let x = 42
    debug_assert(x == 42)
}

test "debug_assert with optional message" {
    debug_assert(true, "this should pass")
    debug_assert(1 == 1, "math still works")
}
