@trusted
@ffi("c", "strlen")
fn c_strlen(s: Ptr[U8]) -> Int ! FFI

@trusted
@ffi("c", "atoi")
fn c_atoi(s: Ptr[U8]) -> Int ! FFI

fn main() {
    let s = "hello"
    let len = c_strlen(s.as_cstr())
    assert_eq(len, 5)

    let num_str = "42"
    let num = c_atoi(num_str.as_cstr())
    assert_eq(num, 42)

    io.println("PASS: FFI functions using runtime header symbols work without conflicting externs")
}
