// Test: set-but-not-read warnings (W0601)
// Expected: W0601 for overwritten values that are never read

fn test_overwrite_before_read() ! IO {
    let mut x = 10
    x = 20
    io.println("{x}")
}

fn test_multiple_overwrites() ! IO {
    let mut x = 1
    x = 2
    x = 3
    io.println("{x}")
}

fn test_no_warning_when_read() ! IO {
    let mut x = 10
    io.println("{x}")
    x = 20
    io.println("{x}")
}

fn test_no_warning_underscore() ! IO {
    let mut _x = 10
    _x = 20
    io.println("{_x}")
}

fn test_compound_assign_ok() ! IO {
    let mut x = 10
    x = x + 5
    io.println("{x}")
}

fn test_loop_reassign() ! IO {
    let mut total = 0
    let items = [1, 2, 3]
    for item in items {
        total = total + item
    }
    io.println("{total}")
}

fn main() ! IO {
    test_overwrite_before_read()
    test_multiple_overwrites()
    test_no_warning_when_read()
    test_no_warning_underscore()
    test_compound_assign_ok()
    test_loop_reassign()
}
