fn make_handler() -> Int {
    42
}

fn make_handler2() -> Int {
    43
}

fn main() {
    let h = make_handler()

    with h {
        io.println("single handler")
    }

    with make_handler(), make_handler2() {
        io.println("multiple handlers")
    }
}
