fn print_via_io(msg: Str) ! IO.Print {
    io.print(msg)
}

fn log_via_io(msg: Str) ! IO {
    io.log(msg)
}

fn do_fs_read(path: Str) ! FS.Read {
    let content = fs.read(path)
    io.println("read {content.len()} bytes from {path}")
}

fn io_and_fs(path: Str) ! IO, FS.Read {
    io.println("multi-effect function")
    do_fs_read(path)
}

fn parent_calls_child() ! IO {
    print_via_io("parent grants IO, child needs IO.Print")
    io.println("")
}

fn multi_effect_fn() ! IO, FS, DB {
    io.println("has IO, FS, DB effects")
}

test "IO.Print via function" {
    print_via_io("io.print works")
    io.println("")
}

test "IO parent calling IO.Print child" {
    parent_calls_child()
}

test "IO.Log via stderr" {
    log_via_io("stderr log message")
}

test "FS.Read dispatch" {
    do_fs_read("tests/test_effect_vtable.pact")
}

test "multi-effect IO + FS.Read" {
    io_and_fs("tests/test_effect_vtable.pact")
}

test "multi-effect IO + FS + DB" {
    multi_effect_fn()
}

test "main implicit effects" {
    io.print("main can print ")
    io.println("without declaring effects")
    fs.read("tests/test_effect_vtable.pact")
    io.println("main can fs.read without declaring effects")
}
