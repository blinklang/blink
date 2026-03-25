// Test: async effect propagation errors

// This function uses async.scope but does NOT declare ! Async — should error
fn helper_missing_effect() {
    async.scope {
        let x = 42
        x + 1
    }
}

// This function correctly declares ! Async — should pass
fn helper_with_effect() ! Async {
    async.scope {
        let x = 42
        x + 1
    }
}

// This function uses async.spawn but does NOT declare ! Async — should error
fn spawner_missing_effect() {
    let h = async.spawn(fn() {
        10
    })
    h.await
}

// E0650: mutable variable captured by async.spawn — should error
fn test_mut_capture() ! Async {
    let mut counter = 0
    let h = async.spawn(fn() {
        counter + 1
    })
    h.await
}

// No error: immutable variable captured by async.spawn — should pass
fn test_immutable_capture() ! Async {
    let x = 42
    let h = async.spawn(fn() {
        x + 1
    })
    h.await
}

fn main() {
    io.println("async effect tests")
}
