// Test: E0650 -- mutable capture in async.spawn should be a compile error.
//
// The Pact spec forbids capturing `let mut` variables in async.spawn closures
// because mutable shared state across threads is unsafe without synchronization.
// Error E0650: "mutable variable 'x' cannot be captured by async.spawn"
//
// This file tests the PASSING case: immutable captures work fine in async.spawn.
// The failing case (mutable capture) is commented out below for reference.

test "immutable capture" {
    let x = 10
    let y = 20
    let h = async.spawn(fn() {
        x + y
    })
    let result = h.await
    assert_eq(result, 30)
}

test "multiple immutable captures" {
    let a = 100
    let b = 200
    let c = 300
    async.scope {
        let h1 = async.spawn(fn() {
            a + b + c
        })
        let r1 = h1.await
        assert_eq(r1, 600)
    }
}

test "capture of computed value" {
    let computed = 7 * 8
    let h2 = async.spawn(fn() {
        computed + 1
    })
    let r2 = h2.await
    assert_eq(r2, 57)
}

// --- E0650: mutable capture (SHOULD NOT COMPILE) ---
// Uncommenting the code below should produce:
//   error E0650: mutable variable 'counter' cannot be captured by async.spawn
//
// let mut counter = 0
// let h_bad = async.spawn(fn() {
//     counter + 1
// })
// h_bad.await
