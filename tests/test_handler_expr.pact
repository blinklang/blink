test "basic handler construction" {
    handler IO {
        fn print(msg: Str) {
            io.println("[CUSTOM] {msg}")
        }
        fn log(msg: Str) {
            io.println("[CUSTOM-LOG] {msg}")
        }
    }
    assert(true)
}

test "handler in with block" {
    with handler IO {
        fn print(msg: Str) {
            io.println("[WITH-PRINT] {msg}")
        }
    } {
        io.println("inside with-handler block")
    }
    assert(true)
}
