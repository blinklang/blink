test "handler builds vtable struct" {
    handler IO {
        fn print(msg: Str) {
            io.println("[MOCK] {msg}")
        }
        fn log(msg: Str) {
            io.println("[MOCK-LOG] {msg}")
        }
    }
}

test "with-block installs and restores handler" {
    io.println("before with-block")
    with handler IO {
        fn print(msg: Str) {
            io.println("[CAPTURE] {msg}")
        }
    } {
        io.println("inside with-block")
    }
    io.println("after with-block (handler restored)")
}

test "nested with-blocks restore correctly" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[OUTER-HANDLER] {msg}")
        }
    } {
        io.println("in outer handler scope")
        with handler IO {
            fn print(msg: Str) {
                io.println("[INNER-HANDLER] {msg}")
            }
        } {
            io.println("in inner handler scope")
        }
        io.println("back in outer handler scope")
    }
    io.println("back in default scope")
}

test "deeply nested with-blocks 3 levels" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[L1] {msg}")
        }
    } {
        io.println("level 1")
        with handler IO {
            fn print(msg: Str) {
                io.println("[L2] {msg}")
            }
        } {
            io.println("level 2")
            with handler IO {
                fn print(msg: Str) {
                    io.println("[L3] {msg}")
                }
            } {
                io.println("level 3")
            }
            io.println("back to level 2")
        }
        io.println("back to level 1")
    }
    io.println("back to default")
}

test "handler with single method" {
    with handler IO {
        fn log(msg: Str) {
            io.println("[CUSTOM-LOG-ONLY] {msg}")
        }
    } {
        io.println("with-block that only overrides log")
    }
}

test "sequential with-blocks" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[FIRST] {msg}")
        }
    } {
        io.println("first with-block")
    }
    with handler IO {
        fn print(msg: Str) {
            io.println("[SECOND] {msg}")
        }
    } {
        io.println("second with-block")
    }
    io.println("after both sequential with-blocks")
}

test "with-block with let bindings inside" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[BINDING-TEST] {msg}")
        }
    } {
        let x = 42
        let y = x + 8
        io.println("computed {y} inside with-block")
    }
}

test "FS handler vtable construction" {
    handler FS {
        fn read(path: Str) -> Str {
            "[mock-content]"
        }
    }
}

test "with-block for FS handler" {
    with handler FS {
        fn read(path: Str) -> Str {
            "[mock-read]"
        }
    } {
        io.println("inside FS with-block")
    }
    io.println("after FS with-block")
}
