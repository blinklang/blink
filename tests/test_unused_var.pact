// Test: unused variable warnings (W0600)
// Expected: warnings for 'unused' and 'also_unused', no warning for '_ignored' or 'used'

fn test_unused_local() ! IO {
    let unused = 42
    let used = 10
    let _ignored = 99
    io.println("{used}")
}

fn test_unused_param(x: Int, y: Int) -> Int {
    x + 1
}

fn test_unused_in_match(val: Int) -> Int {
    match val {
        1 => 10
        other => 20
    }
}

fn test_unused_for_var() ! IO {
    let items = [1, 2, 3]
    for _i in items {
        io.println("hello")
    }
}

fn test_used_in_closure() ! IO {
    let x = 5
    let f = fn(n: Int) -> Int { n + x }
    io.println("{f(10)}")
}

fn main() ! IO {
    test_unused_local()
    let result = test_unused_param(1, 2)
    io.println("{result}")
    let r2 = test_unused_in_match(1)
    io.println("{r2}")
    test_unused_for_var()
    test_used_in_closure()
}
