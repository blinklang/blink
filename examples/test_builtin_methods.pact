import std.path

// Test that methods resolve correctly on built-in function return values

fn main() ! IO {
    // read_file returns Str — string methods should work
    write_file(".tmp/_test_bm.txt", "  hello world  ")
    let content = read_file(".tmp/_test_bm.txt")
    let trimmed = content.trim()
    assert_eq(trimmed, "hello world")

    let has = content.contains("hello")
    assert(has)

    let parts = content.trim().split(" ")
    assert_eq(parts.len(), 2)

    // path_join returns Str
    let p = path_join("a", "b")
    assert(p.contains("b"))

    // path_dirname returns Str
    let d = path_dirname("/a/b/c")
    assert(d.len() > 0)

    // path_basename returns Str
    let b = path_basename("/a/b/c.txt")
    assert_eq(b, "c.txt")

    // get_arg returns Str
    let a = get_arg(0)
    assert(a.len() > 0)

    // get_env returns Option[Str] — unwrap then method
    let home = get_env("HOME") ?? "/tmp"
    assert(home.len() > 0)

    shell_exec("rm -f .tmp/_test_bm.txt")
    io.println("PASS: all builtin method tests")
}
