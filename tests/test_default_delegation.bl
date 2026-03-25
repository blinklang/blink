effect Audit {
    effect Log {
        fn record(msg: Str)
    }
}

test "IO default delegation" {
    with handler IO {
        fn print(msg: Str) {
            default.print("[WRAPPED] {msg}")
        }
    } {
        io.println("hello from wrapped handler")
    }
    assert(true)
}

test "user effect default delegation" {
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
    assert(true)
}

test "default delegation restores" {
    with handler IO {
        fn print(msg: Str) {
            default.print("[LAYER1] {msg}")
        }
    } {
        io.println("via layer1")
    }
    io.println("back to default handler")
    assert(true)
}
