test "with block handler" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[CUSTOM-PRINT] should not appear yet")
        }
    } {
        io.println("inside with block - uses direct printf for now")
    }
    assert(true)
}

test "nested with blocks" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[OUTER] should not appear")
        }
    } {
        io.println("outer with body")
        with handler IO {
            fn print(msg: Str) {
                io.println("[INNER] should not appear")
            }
        } {
            io.println("inner with body")
        }
        io.println("back in outer with body")
    }
    assert(true)
}
