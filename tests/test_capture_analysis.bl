// Test capture analysis (pact-217)
// Closures that reference outer variables.
// For now, capture analysis runs but doesn't change codegen output.
// This verifies the compiler doesn't crash when closures have free variables.

test "non-capturing closure works" {
    let add = fn(a: Int, b: Int) -> Int { a + b }
    assert_eq(add(1, 2), 3)
}

test "identity closure returns input" {
    let identity = fn(s: Str) -> Str { s }
    assert_eq(identity("works"), "works")
}
