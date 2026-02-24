effect Audit {
    effect Log {
        fn record(msg: Str)
    }
}

fn main() {
    let mut passed = 0

    io.println("=== handler default delegation tests ===")

    io.println("--- test 1: default delegation for IO ---")
    with handler IO {
        fn print(msg: Str) {
            default.print("[WRAPPED] {msg}")
        }
    } {
        io.println("hello from wrapped handler")
    }
    passed = passed + 1
    io.println("ok: IO default delegation")

    io.println("--- test 2: default delegation for user effect ---")
    with handler Audit {
        fn record(msg: Str) {
            io.println("[BASE] {msg}")
        }
    } {
        with handler Audit {
            fn record(msg: Str) {
                default.record("[FILTERED] {msg}")
            }
        } {
            audit.record("important event")
        }
    }
    passed = passed + 1
    io.println("ok: user effect default delegation")

    io.println("--- test 3: default delegation restores ---")
    with handler IO {
        fn print(msg: Str) {
            default.print("[LAYER1] {msg}")
        }
    } {
        io.println("via layer1")
    }
    io.println("back to default handler")
    passed = passed + 1
    io.println("ok: delegation restores")

    io.println("--- results ---")
    io.println("tests passed: {passed}")
    if passed == 3 {
        io.println("PASS")
    } else {
        io.println("FAIL")
    }
}
