// Test: unreachable code warnings (W0700)
// Expected: warnings for code after return/break/continue

fn test_after_return() -> Int {
    return 42
    let _dead = 99
    0
}

fn test_after_break() ! IO {
    let mut i = 0
    while i < 10 {
        if i == 5 {
            break
            io.println("never")
        }
        i = i + 1
    }
    io.println("done: {i}")
}

fn test_after_continue() ! IO {
    for i in [1, 2, 3] {
        if i == 2 {
            continue
            io.println("never")
        }
        io.println("{i}")
    }
}

fn test_no_warning() -> Int {
    let x = 10
    if x > 5 {
        return x
    }
    0
}

fn main() ! IO {
    let r = test_after_return()
    io.println("{r}")
    test_after_break()
    test_after_continue()
    let r2 = test_no_warning()
    io.println("{r2}")
}
