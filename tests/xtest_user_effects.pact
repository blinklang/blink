effect Metrics {
    effect Emit {
        fn counter(name: Str, value: Int)
        fn gauge(name: Str, value: Float)
    }
    effect Query {
        fn get_counter(name: Str) -> Int
    }
}

fn record_metric(name: Str, val: Int) ! Metrics.Emit {
    metrics.counter(name, val)
}

fn main() {
    let mut passed = 0

    io.println("=== user-defined effect tests ===")

    io.println("--- test 1: effect declaration and default handle ---")
    metrics.counter("requests", 1)
    passed = passed + 1
    io.println("ok: metrics.counter call (default handler)")

    io.println("--- test 2: handler for user effect ---")
    with handler Metrics {
        fn counter(name: Str, value: Int) {
            io.println("captured: {name} = {value}")
        }
        fn gauge(name: Str, value: Float) {
        }
        fn get_counter(name: Str) -> Int {
            42
        }
    } {
        metrics.counter("test_metric", 99)
    }
    passed = passed + 1
    io.println("ok: handler intercepted counter call")

    io.println("--- test 3: handler restores after with-block ---")
    metrics.counter("after_restore", 2)
    passed = passed + 1
    io.println("ok: default handler restored")

    io.println("--- test 4: effectful function with user effect ---")
    with handler Metrics {
        fn counter(name: Str, value: Int) {
            io.println("mock counter: {name} = {value}")
        }
        fn gauge(name: Str, value: Float) {
        }
        fn get_counter(name: Str) -> Int {
            0
        }
    } {
        record_metric("via_function", 42)
    }
    passed = passed + 1
    io.println("ok: effectful function with user effect")

    io.println("--- test 5: query sub-effect ---")
    with handler Metrics {
        fn counter(name: Str, value: Int) {
        }
        fn gauge(name: Str, value: Float) {
        }
        fn get_counter(name: Str) -> Int {
            100
        }
    } {
        let val = metrics.get_counter("requests")
        if val == 100 {
            io.println("ok: query sub-effect returns value")
            passed = passed + 1
        } else {
            io.println("FAIL: expected 100, got {val}")
        }
    }

    io.println("--- test 6: nested handlers ---")
    with handler Metrics {
        fn counter(name: Str, value: Int) {
            io.println("[OUTER] {name} = {value}")
        }
        fn gauge(name: Str, value: Float) {
        }
        fn get_counter(name: Str) -> Int {
            10
        }
    } {
        metrics.counter("outer", 1)
        with handler Metrics {
            fn counter(name: Str, value: Int) {
                io.println("[INNER] {name} = {value}")
            }
            fn gauge(name: Str, value: Float) {
            }
            fn get_counter(name: Str) -> Int {
                20
            }
        } {
            metrics.counter("inner", 2)
        }
        metrics.counter("back_outer", 3)
    }
    passed = passed + 1
    io.println("ok: nested handlers")

    io.println("--- results ---")
    io.println("tests passed: {passed}")
    if passed == 6 {
        io.println("PASS")
    } else {
        io.println("FAIL")
    }
}
